data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_iot_endpoint" "mqtt" { endpoint_type = "iot:Data-ATS" }

locals {
  prefix    = "lab5-750962"
  sensor_id = "watch-750962"
  topic     = "lab5/750962/frecuencia"
  namespace = "Lab5/750962"
  lab_role  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  iot_arn   = "arn:${data.aws_partition.current.partition}:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
}

resource "aws_kinesis_stream" "heart_rate" {
  name             = "${local.prefix}-frecuencia"
  shard_count      = 1
  retention_period = 24
  stream_mode_details { stream_mode = "PROVISIONED" }
}

resource "aws_dynamodb_table" "readings" {
  name         = "${local.prefix}-lecturas"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sensor_id"
  range_key    = "timestamp"
  attribute {
    name = "sensor_id"
    type = "S"
  }
  attribute {
    name = "timestamp"
    type = "S"
  }
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.prefix}-procesar"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "iot_errors" {
  name              = "/lab5/750962/iot-errors"
  retention_in_days = 7
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "processor" {
  function_name    = "${local.prefix}-procesar"
  role             = local.lab_role
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
  memory_size      = 128
  environment {
    variables = {
      TABLE_NAME         = aws_dynamodb_table.readings.name
      METRIC_NAMESPACE   = local.namespace
      EXPECTED_SENSOR_ID = local.sensor_id
      EXPECTED_USER_ID   = "750962"
      DEMO_THRESHOLD_BPM = tostring(var.demo_threshold_bpm)
    }
  }
  depends_on = [aws_cloudwatch_log_group.lambda]
}

resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn                   = aws_kinesis_stream.heart_rate.arn
  function_name                      = aws_lambda_function.processor.arn
  starting_position                  = "TRIM_HORIZON"
  batch_size                         = 10
  maximum_batching_window_in_seconds = 1
  function_response_types            = ["ReportBatchItemFailures"]
  maximum_retry_attempts             = -1
  maximum_record_age_in_seconds      = -1
  enabled                            = true
}

resource "aws_iot_thing" "watch" { name = local.sensor_id }

resource "aws_iot_certificate" "watch" { active = true }

resource "aws_iot_policy" "watch" {
  name = "${local.prefix}-mqtt"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["iot:Connect"], Resource = ["${local.iot_arn}:client/${local.sensor_id}"] },
      { Effect = "Allow", Action = ["iot:Publish"], Resource = ["${local.iot_arn}:topic/${local.topic}"] }
    ]
  })
}

resource "aws_iot_policy_attachment" "watch" {
  policy = aws_iot_policy.watch.name
  target = aws_iot_certificate.watch.arn
}

resource "aws_iot_thing_principal_attachment" "watch" {
  thing     = aws_iot_thing.watch.name
  principal = aws_iot_certificate.watch.arn
}

resource "aws_iot_topic_rule" "heart_rate" {
  name        = "lab5_750962_frecuencia"
  description = "Frecuencia cardiaca simulada por MQTT a Kinesis"
  enabled     = true
  sql         = "SELECT * FROM '${local.topic}'"
  sql_version = "2016-03-23"
  kinesis {
    stream_name   = aws_kinesis_stream.heart_rate.name
    partition_key = "$${sensor_id}"
    role_arn      = local.lab_role
  }
  error_action {
    cloudwatch_logs {
      log_group_name = aws_cloudwatch_log_group.iot_errors.name
      role_arn       = local.lab_role
    }
  }
}
