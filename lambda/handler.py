"""Procesa lecturas simuladas. DynamoDB es el historial; metricas son auxiliares."""
import base64
import binascii
import json
import logging
import os
from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import ClientError

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)
TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
METRICS = boto3.client("cloudwatch")
NAMESPACE = os.environ.get("METRIC_NAMESPACE", "Lab5/750962")
SENSOR = os.environ.get("EXPECTED_SENSOR_ID", "watch-750962")
USER = os.environ.get("EXPECTED_USER_ID", "750962")
THRESHOLD = int(os.environ.get("DEMO_THRESHOLD_BPM", "120"))


def validate(payload):
    if not isinstance(payload, dict):
        raise ValueError("El mensaje debe ser un objeto JSON")
    if payload.get("sensor_id") != SENSOR or payload.get("usuario_id") != USER:
        raise ValueError("Sensor o usuario no reconocido")
    bpm = payload.get("bpm")
    if type(bpm) is not int or not 20 <= bpm <= 250:
        raise ValueError("bpm debe ser un entero de 20 a 250 para esta simulacion")
    activity = payload.get("actividad")
    if activity not in ("reposo", "ejercicio", "recuperacion"):
        raise ValueError("actividad no reconocida")
    timestamp = payload.get("timestamp")
    if not isinstance(timestamp, str):
        raise ValueError("timestamp debe ser ISO 8601")
    measured_at = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    if measured_at.tzinfo is None:
        raise ValueError("timestamp debe incluir zona horaria")
    measured_at = measured_at.astimezone(timezone.utc)
    now = datetime.now(timezone.utc)
    if measured_at < now - timedelta(hours=24) or measured_at > now + timedelta(minutes=5):
        raise ValueError("timestamp fuera de la ventana de demostracion")
    return {
        "sensor_id": SENSOR,
        "timestamp": measured_at.isoformat(timespec="microseconds").replace("+00:00", "Z"),
        "usuario_id": USER,
        "bpm": bpm,
        "actividad": activity,
        "supera_umbral_demo": bpm > THRESHOLD,
        "umbral_demo_bpm": THRESHOLD,
        "expires_at": int(measured_at.timestamp()) + 7 * 24 * 3600,
    }, measured_at


def lambda_handler(event, context):
    for record in event.get("Records", []):
        sequence = record["kinesis"]["sequenceNumber"]
        try:
            raw = base64.b64decode(record["kinesis"]["data"], validate=True)
            item, measured_at = validate(json.loads(raw))
        except (ValueError, TypeError, UnicodeError, binascii.Error) as exc:
            LOGGER.warning("Lectura rechazada sequence=%s motivo=%s", sequence, exc)
            continue

        try:
            TABLE.put_item(
                Item=item,
                ConditionExpression="attribute_not_exists(sensor_id) AND attribute_not_exists(#ts)",
                ExpressionAttributeNames={"#ts": "timestamp"},
            )
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
                LOGGER.info("Lectura duplicada sequence=%s", sequence)
                continue
            LOGGER.exception("No se pudo guardar sequence=%s", sequence)
            return {"batchItemFailures": [{"itemIdentifier": sequence}]}
        except Exception:
            LOGGER.exception("Fallo transitorio al guardar sequence=%s", sequence)
            return {"batchItemFailures": [{"itemIdentifier": sequence}]}

        dimensions = [{"Name": "Usuario", "Value": USER}, {"Name": "Sensor", "Value": SENSOR}]
        try:
            METRICS.put_metric_data(
                Namespace=NAMESPACE,
                MetricData=[
                    {"MetricName": "BPM", "Dimensions": dimensions, "Timestamp": measured_at,
                     "Value": item["bpm"], "Unit": "None", "StorageResolution": 1},
                    {"MetricName": "SuperaUmbralDemo", "Dimensions": dimensions, "Timestamp": measured_at,
                     "Value": int(item["supera_umbral_demo"]), "Unit": "Count", "StorageResolution": 1},
                ],
            )
        except Exception:
            LOGGER.exception("Lectura guardada, pero no se pudo publicar su metrica sequence=%s", sequence)
        LOGGER.info("Lectura guardada sensor=%s bpm=%s supera_umbral_demo=%s", SENSOR, item["bpm"], item["supera_umbral_demo"])
    return {"batchItemFailures": []}
