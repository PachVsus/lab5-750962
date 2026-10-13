param(
    [switch]$Restart,
    [ValidateRange(1024, 65535)][int]$Port = 3005
)

$ErrorActionPreference = 'Continue'
$env:AWS_PAGER = ''
Set-Location -LiteralPath $PSScriptRoot
foreach ($labCredentialName in @('AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_SESSION_TOKEN')) {
    if (-not [Environment]::GetEnvironmentVariable($labCredentialName, 'Process')) {
        throw "Falta $labCredentialName en esta terminal. Carga las tres variables temporales de Learner Lab."
    }
}
$labIdentityText = & aws sts get-caller-identity --region us-east-1 --output json --no-cli-pager --cli-connect-timeout 5 --cli-read-timeout 10 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ($labIdentityText -join "`n")
    throw 'AWS no autentico esta terminal. Renueva las credenciales completas del laboratorio.'
}
$labIdentity = ($labIdentityText -join "`n") | ConvertFrom-Json
if ($labIdentity.Account -ne '679322737424') { throw 'La cuenta autenticada no es la cuenta Academy del proyecto.' }

$labDockerInfo = & docker info --format '{{.OSType}}' 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Docker no esta listo. Abre Docker Desktop y espera hasta que el motor este iniciado; despues ejecuta este script otra vez.' }
if (($labDockerInfo -join '').Trim() -ne 'linux') { throw 'Grafana requiere Docker en modo Linux containers.' }
& docker compose version
if ($LASTEXITCODE -ne 0) { throw 'No se encontro Docker Compose. Revisa la instalacion de Docker Desktop.' }

$ErrorActionPreference = 'Stop'
$labDashboardDirectory = Join-Path $PSScriptRoot '.runtime\grafana\dashboards'
New-Item -ItemType Directory -Path $labDashboardDirectory -Force | Out-Null
$labEncoding = New-Object System.Text.UTF8Encoding($false)
$labDashboard = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'grafana\dashboard.json') -Raw
$labDashboard = $labDashboard.Replace('${DS_CLOUDWATCH}', 'cloudwatch750962')
[IO.File]::WriteAllText((Join-Path $labDashboardDirectory 'lab5.json'), $labDashboard, $labEncoding)

# No imprimir compose config: resolveria las variables secretas.
$env:LAB5_GRAFANA_PORT = [string]$Port
$labBaseUrl = "http://127.0.0.1:$Port"
$labComposePath = Join-Path $PSScriptRoot 'grafana\compose.yaml'
$labComposeArgs = @('compose','--project-name','lab5-750962','--file',$labComposePath,'up','-d')
if ($Restart) { $labComposeArgs += '--force-recreate' }
Write-Host 'Preparando Grafana local; la primera ejecucion descarga la imagen oficial...'
& docker @labComposeArgs
if ($LASTEXITCODE -ne 0) { throw 'Docker no pudo iniciar Grafana. Conserva el mensaje exacto.' }

$labReady = $false
for ($labAttempt = 0; $labAttempt -lt 30; $labAttempt++) {
    Start-Sleep -Seconds 1
    try {
        $labHealth = Invoke-RestMethod -Uri "$labBaseUrl/api/health" -TimeoutSec 1
        if ($labHealth.database -eq 'ok') { $labReady = $true; break }
    } catch { }
}
if (-not $labReady) {
    & docker logs lab5-grafana-750962 --tail 20
    throw 'Grafana aun no confirmo su inicio. Revisa los registros anteriores.'
}
Write-Host "Grafana listo: $labBaseUrl"
Write-Host 'Primer acceso: usuario admin y contrasena admin; Grafana pedira cambiarla.'
Write-Host "Tablero: $labBaseUrl/d/lab5-750962-heart"
Write-Host 'La fuente CloudWatch y el tablero ya estan configurados.'
Write-Host 'Tras renovar las credenciales, ejecuta .\iniciar-grafana.ps1 -Restart'
