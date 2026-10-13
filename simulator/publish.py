"""Publica lecturas sinteticas con MQTT/TLS y certificado de dispositivo."""
import argparse
import json
import random
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

import paho.mqtt.client as mqtt

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description="Simulador de frecuencia cardiaca 750962")
    parser.add_argument("--count", type=int, default=24)
    parser.add_argument("--interval", type=float, default=5)
    parser.add_argument("--scenario", choices=["demo", "reposo", "ejercicio", "recuperacion"], default="demo")
    parser.add_argument("--invalid", action="store_true", help="Envia un mensaje adicional sin bpm")
    args = parser.parse_args()
    if args.count < 1 or args.interval <= 0:
        parser.error("count debe ser >= 1 e interval debe ser > 0")
    with (ROOT / "client-config.json").open(encoding="utf-8-sig") as stream:
        config = json.load(stream)
    connected = threading.Event()
    connection_errors = []

    def on_connect(client, userdata, flags, reason_code, properties):
        if reason_code.is_failure:
            connection_errors.append(str(reason_code))
        connected.set()

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=config["client_id"], protocol=mqtt.MQTTv311)
    client.on_connect = on_connect
    client.tls_set(ca_certs=str(ROOT / "certs/AmazonRootCA1.pem"),
                   certfile=str(ROOT / "certs/device.pem"), keyfile=str(ROOT / "certs/private.key"))
    client.connect(config["endpoint"], config["port"], keepalive=60)
    client.loop_start()
    try:
        if not connected.wait(timeout=15):
            raise RuntimeError("No se recibio confirmacion MQTT; revisar certificado, politica y red en puerto 8883")
        if connection_errors:
            raise RuntimeError("Conexion rechazada: " + connection_errors[0])
        for index in range(args.count):
            activity = args.scenario
            if activity == "demo":
                activity = ["reposo", "ejercicio", "recuperacion"][min(2, index * 3 // args.count)]
            limits = {"reposo": (60, 85), "ejercicio": (125, 155), "recuperacion": (85, 115)}
            payload = {
                "usuario_id": config["usuario_id"], "sensor_id": config["sensor_id"],
                "timestamp": datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z"),
                "bpm": random.randint(*limits[activity]), "actividad": activity,
            }
            send(client, config["topic"], payload)
            if index < args.count - 1:
                time.sleep(args.interval)
        if args.invalid:
            send(client, config["topic"], {"usuario_id": config["usuario_id"], "sensor_id": config["sensor_id"]})
    finally:
        client.disconnect()
        client.loop_stop()


def send(client, topic, payload):
    message = json.dumps(payload)
    result = client.publish(topic, message, qos=1)
    if result.rc != mqtt.MQTT_ERR_SUCCESS:
        raise RuntimeError(f"No se pudo publicar: {mqtt.error_string(result.rc)}")
    result.wait_for_publish(timeout=15)
    if not result.is_published():
        raise TimeoutError("No se recibio confirmacion de publicacion MQTT")
    print("MQTT confirmado:", message, flush=True)


if __name__ == "__main__":
    main()
