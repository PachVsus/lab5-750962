param([string]$Region = 'us-east-1')

$ErrorActionPreference = 'Continue'
$env:AWS_PAGER = ''
Set-Location -LiteralPath $PSScriptRoot

# Solo muestra metadatos del stream. No lee ni imprime credenciales.
$summaryText = & aws kinesis describe-stream-summary --stream-name lab5-750962-frecuencia --region $Region --output json --no-cli-pager --cli-connect-timeout 5 --cli-read-timeout 10 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ($summaryText -join "`n")
    throw 'No se pudo verificar el stream. No se modifico el estado de Terraform.'
}
$summary = (($summaryText -join "`n") | ConvertFrom-Json).StreamDescriptionSummary
$expectedArn = "arn:aws:kinesis:${Region}:679322737424:stream/lab5-750962-frecuencia"
if ($summary.StreamARN -ne $expectedArn -or $summary.StreamStatus -ne 'ACTIVE' -or $summary.RetentionPeriodHours -ne 24 -or $summary.OpenShardCount -ne 1 -or $summary.StreamModeDetails.StreamMode -ne 'PROVISIONED') {
    $summary | Select-Object StreamARN,StreamStatus,RetentionPeriodHours,OpenShardCount,StreamModeDetails | Format-List
    throw 'El stream no coincide con la configuracion esperada. No se modifico el estado.'
}

# El estado contiene secretos; se captura y procesa en memoria, sin imprimirlo.
$stateText = & terraform state pull
if ($LASTEXITCODE -ne 0) { throw 'No se pudo leer el estado. No se modifico.' }
$state = ($stateText -join "`n") | ConvertFrom-Json
$resource = @($state.resources | Where-Object { $_.mode -eq 'managed' -and $_.type -eq 'aws_kinesis_stream' -and $_.name -eq 'heart_rate' -and -not $_.module })
if ($resource.Count -ne 1 -or @($resource[0].instances).Count -ne 1) {
    throw 'Se esperaba un unico aws_kinesis_stream.heart_rate registrado en el estado.'
}
$instance = $resource[0].instances[0]
if ($instance.attributes.id -ne $expectedArn) { throw 'El identificador del estado no coincide con el stream verificado.' }

Write-Host 'Stream verificado: ACTIVE, un shard, PROVISIONED, retencion de 24 horas.'
if ($instance.status -eq 'tainted') {
    & terraform untaint aws_kinesis_stream.heart_rate
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo quitar la marca de reemplazo.' }
} else {
    Write-Host 'El stream no tiene marca de reemplazo; se conserva su estado.'
}

Write-Host 'Generando un plan nuevo, con refresco de los recursos reales...'
& terraform plan -out lab5-recuperado.tfplan
if ($LASTEXITCODE -ne 0) { throw 'No se pudo completar el plan. Conserva el mensaje exacto.' }
Write-Host 'Revisa el plan: no debe eliminar ni reemplazar el stream.'
Write-Host 'Para continuar: terraform apply lab5-recuperado.tfplan'
