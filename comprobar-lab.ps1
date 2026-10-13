param([string]$Region = 'us-east-1')

$ErrorActionPreference = 'Continue'
$env:AWS_PAGER = ''
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw 'No se encontro AWS CLI.'
}

Write-Host 'Lab 5 | matricula 750962 | comprobacion de solo lectura'
Write-Host "Region: $Region"
Write-Host 'Estos comandos no crean recursos ni muestran claves o tokens.'

$identityText = & aws sts get-caller-identity --region $Region --output json --no-cli-pager --cli-connect-timeout 5 --cli-read-timeout 10 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ($identityText -join "`n")
    throw 'Autenticacion fallida. Inicia Learner Lab y actualiza AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY y AWS_SESSION_TOKEN en esta terminal.'
}
$identity = ($identityText -join "`n") | ConvertFrom-Json
Write-Host "Identidad autenticada: $($identity.Arn)"

$checks = @(
    @{ Label = 'Kinesis'; Arguments = @('kinesis', 'list-streams', '--limit', '1', '--query', 'length(StreamNames)') },
    @{ Label = 'IoT Core'; Arguments = @('iot', 'list-things', '--max-results', '1', '--query', 'length(things)') },
    @{ Label = 'Amazon Keyspaces'; Arguments = @('keyspaces', 'list-keyspaces', '--max-results', '1', '--query', 'length(keyspaces)') },
    @{ Label = 'Lambda'; Arguments = @('lambda', 'list-functions', '--max-items', '1', '--query', 'length(Functions)') },
    @{ Label = 'SQS (opcional)'; Arguments = @('sqs', 'list-queues', '--max-results', '1', '--query', 'length(QueueUrls || `[]`)') }
)
foreach ($check in $checks) {
    $commandArgs = $check.Arguments + @('--region', $Region, '--output', 'json', '--no-cli-pager', '--no-paginate', '--cli-connect-timeout', '5', '--cli-read-timeout', '10')
    $result = & aws @commandArgs 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[LECTURA OK] $($check.Label)"
    } else {
        Write-Host "[REVISAR] $($check.Label)"
        Write-Host ($result -join "`n")
    }
}

Write-Host 'LabRole: ARN y politica de confianza (no son credenciales)'
& aws iam get-role --role-name LabRole --query 'Role.{Arn:Arn,Trust:AssumeRolePolicyDocument}' --output json --no-cli-pager --cli-connect-timeout 5 --cli-read-timeout 10
if ($LASTEXITCODE -ne 0) {
    Write-Host 'No se pudo leer LabRole; revisar sus datos y permisos en la consola del laboratorio.'
}
Write-Host 'Lectura OK no garantiza permisos para crear recursos, pasar roles o escribir datos.'
Write-Host 'La politica de confianza tampoco garantiza los permisos de escritura del rol.'
Write-Host 'Fin de comprobacion.'
