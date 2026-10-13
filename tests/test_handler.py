import base64
import importlib.util
import json
import os
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

from botocore.exceptions import ClientError


class HandlerTests(unittest.TestCase):
    def setUp(self):
        self.table = MagicMock()
        self.metrics = MagicMock()
        resource = MagicMock()
        resource.Table.return_value = self.table
        with patch.dict(os.environ, {"TABLE_NAME": "test-readings", "DEMO_THRESHOLD_BPM": "120"}), \
                patch("boto3.resource", return_value=resource), patch("boto3.client", return_value=self.metrics):
            path = Path(__file__).resolve().parents[1] / "lambda/handler.py"
            spec = importlib.util.spec_from_file_location("lab_handler", path)
            self.handler = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.handler)
        self.payload = {
            "sensor_id": "watch-750962", "usuario_id": "750962", "bpm": 130,
            "actividad": "ejercicio", "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    def event(self, payloads):
        return {"Records": [{"kinesis": {"sequenceNumber": str(index + 1),
                    "data": base64.b64encode(json.dumps(payload).encode()).decode()}}
                for index, payload in enumerate(payloads)]}

    def test_reading_is_persisted_and_metrics_published(self):
        result = self.handler.lambda_handler(self.event([self.payload]), None)
        self.assertEqual(result, {"batchItemFailures": []})
        item = self.table.put_item.call_args.kwargs["Item"]
        self.assertTrue(item["supera_umbral_demo"])
        self.assertTrue(item["timestamp"].endswith("Z"))
        self.assertEqual(item["bpm"], 130)
        self.assertGreater(item["expires_at"], datetime.now(timezone.utc).timestamp())
        data = self.metrics.put_metric_data.call_args.kwargs["MetricData"]
        self.assertEqual(data[0]["Value"], 130)
        self.assertEqual(data[1]["Value"], 1)

    def test_duplicate_does_not_publish_metrics_again(self):
        seen = set()
        def write(**kwargs):
            self.assertIn("attribute_not_exists", kwargs["ConditionExpression"])
            key = (kwargs["Item"]["sensor_id"], kwargs["Item"]["timestamp"])
            if key in seen:
                raise ClientError({"Error": {"Code": "ConditionalCheckFailedException"}}, "PutItem")
            seen.add(key)
        self.table.put_item.side_effect = write
        result = self.handler.lambda_handler(self.event([self.payload, self.payload]), None)
        self.assertEqual(result, {"batchItemFailures": []})
        self.assertEqual(len(seen), 1)
        self.metrics.put_metric_data.assert_called_once()

    def test_invalid_message_does_not_block_valid_record(self):
        result = self.handler.lambda_handler(self.event([{}, self.payload]), None)
        self.assertEqual(result, {"batchItemFailures": []})
        self.table.put_item.assert_called_once()

    def test_storage_failure_retries_from_first_failure(self):
        self.table.put_item.side_effect = ClientError({"Error": {"Code": "AccessDeniedException"}}, "PutItem")
        result = self.handler.lambda_handler(self.event([self.payload, self.payload]), None)
        self.assertEqual(result, {"batchItemFailures": [{"itemIdentifier": "1"}]})
        self.table.put_item.assert_called_once()
        self.metrics.put_metric_data.assert_not_called()

    def test_metric_failure_keeps_saved_reading(self):
        self.metrics.put_metric_data.side_effect = RuntimeError("metric service unavailable")
        self.assertEqual(self.handler.lambda_handler(self.event([self.payload]), None), {"batchItemFailures": []})
        self.table.put_item.assert_called_once()

    def test_validation_rejects_wrong_types_and_naive_timestamp(self):
        for field, value in [("bpm", True), ("bpm", "130"), ("bpm", 251),
                             ("timestamp", "2026-01-01T00:00:00"), ("sensor_id", "other")]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                self.handler.validate({**self.payload, field: value})

    def test_malformed_base64_is_discarded(self):
        result = self.handler.lambda_handler({"Records": [{"kinesis": {"sequenceNumber": "1", "data": "%%%"}}]}, None)
        self.assertEqual(result, {"batchItemFailures": []})
        self.table.put_item.assert_not_called()


if __name__ == "__main__":
    unittest.main()
