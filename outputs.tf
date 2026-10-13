output "client_config" {
  value = {
    endpoint   = data.aws_iot_endpoint.mqtt.endpoint_address
    port       = 8883
    client_id  = local.sensor_id
    sensor_id  = local.sensor_id
    usuario_id = "750962"
    topic      = local.topic
    region     = var.aws_region
  }
}
output "certificate_pem" {
  value     = aws_iot_certificate.watch.certificate_pem
  sensitive = true
}
output "private_key" {
  value     = aws_iot_certificate.watch.private_key
  sensitive = true
}
output "table_name" { value = aws_dynamodb_table.readings.name }
output "lambda_name" { value = aws_lambda_function.processor.function_name }
output "kinesis_name" { value = aws_kinesis_stream.heart_rate.name }
output "metric_namespace" { value = local.namespace }
output "lab_role_arn" { value = local.lab_role }
