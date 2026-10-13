# Lab 5: frecuencia cardiaca por MQTT — 750962

Esta primera comprobacion determina si la arquitectura propuesta se puede desplegar en tu AWS Academy Learner Lab. Todavia no crea recursos de AWS.

Arquitectura propuesta: simulador Python → MQTT sobre TLS → AWS IoT Core → regla IoT → Kinesis Data Streams → Lambda → Amazon Keyspaces.

SQS queda pendiente de confirmar en la consigna. DynamoDB solo seria una alternativa si el docente acepta una base NoSQL de clave-valor/documentos en lugar de columnas anchas.

## Ejecutar desde VS Code

Abre `C:\lab5-750962` y usa la misma terminal PowerShell en la que cargaste las tres variables temporales del laboratorio: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y `AWS_SESSION_TOKEN`. Incluye el token de sesion y renueva las tres variables cuando el laboratorio emita nuevas credenciales. No las copies al chat ni a archivos Terraform.

```powershell
Set-Location -LiteralPath 'C:\lab5-750962'
.\comprobar-lab.ps1 -Region us-east-1
```

Si PowerShell bloquea la ejecucion del archivo, puedes usar una excepcion para ese proceso:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\comprobar-lab.ps1 -Region us-east-1
```

Comparte la salida de la comprobacion, sin claves ni tokens. El script muestra identidad, errores de los servicios y la confianza de LabRole; no lee ni imprime valores de credenciales.

## Que falta validar

- Acceso de lectura a IoT Core, Kinesis, Keyspaces y Lambda.
- Permisos de creacion y escritura: los comandos de lectura no los prueban.
- Un rol que IoT Core pueda asumir (`iot.amazonaws.com`) para escribir en Kinesis y otro que Lambda pueda asumir (`lambda.amazonaws.com`) para leer Kinesis y escribir en Keyspaces. Pueden ser el mismo rol existente si su confianza y permisos lo permiten.
- Permiso para pasar esos roles a los servicios.
- Si la consigna requiere SQS ademas de Kinesis.

No se debe modificar LabRole ni crear roles IAM como parte del Terraform sin comprobar las restricciones del laboratorio. La politica de confianza permite asumir un rol; sus politicas de permisos determinan las acciones que puede ejecutar.

No necesitas un repositorio remoto para usar Terraform. La carpeta local es suficiente; Git es opcional. Mantener el estado de Terraform permite administrar y eliminar los recursos que se creen mas adelante.
