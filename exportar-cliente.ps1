$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$encoding = New-Object System.Text.UTF8Encoding($false)

function Read-TerraformOutput([string]$Name, [switch]$Json) {
    $format = '-raw'
    if ($Json) { $format = '-json' }
    $value = & terraform output $format $Name
    if ($LASTEXITCODE -ne 0) { throw "No se pudo leer el output $Name. Ejecuta terraform apply primero." }
    return ($value -join "`n")
}

# Capturar los outputs evita imprimir la clave privada en pantalla.
$configuration = Read-TerraformOutput 'client_config' -Json
$certificate = Read-TerraformOutput 'certificate_pem'
$privateKey = Read-TerraformOutput 'private_key'
$certDirectory = Join-Path $PSScriptRoot 'certs'
New-Item -ItemType Directory -Path $certDirectory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'client-config.json'), $configuration, $encoding)
[IO.File]::WriteAllText((Join-Path $certDirectory 'device.pem'), $certificate, $encoding)
[IO.File]::WriteAllText((Join-Path $certDirectory 'private.key'), $privateKey, $encoding)
Invoke-WebRequest -Uri 'https://www.amazontrust.com/repository/AmazonRootCA1.pem' -OutFile (Join-Path $certDirectory 'AmazonRootCA1.pem') -UseBasicParsing
Write-Host 'Configuracion y certificados exportados. No compartas certs ni el estado de Terraform.'
