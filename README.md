# Lab 5 — Frecuencia cardiaca — 750962

Proyecto académico de frecuencia cardiaca simulada para Diseño de Sistemas Escalables, matrícula **750962**. La infraestructura se administra con Terraform en AWS Academy Learner Lab.

El flujo completo fue comprobado: publicación MQTT, procesamiento Lambda, almacenamiento DynamoDB, métricas CloudWatch y visualización Grafana. En la segunda prueba se enviaron 60 lecturas; el tablero mostró un máximo de **154 bpm** y **20 lecturas mayores que 120 bpm**. Los valores son sintéticos y el umbral es una regla de demostración.

## Contenido del repositorio

| Ruta | Contenido |
| --- | --- |
| `*.tf` y `.terraform.lock.hcl` | Infraestructura y versiones de proveedores |
| `lambda/` | Validación y procesamiento de lecturas |
| `simulator/` | Publicador MQTT con certificado de dispositivo |
| `tests/` | Pruebas locales de Lambda con servicios simulados |
| `grafana/` | Docker Compose, tablero y configuración CloudWatch |
| `*.ps1` | Comprobación, recuperación, exportación e inicio local |

Guías: [Grafana local](GRAFANA-LOCAL.md) y [validación y resultados](VALIDACION.md).

El repositorio publica código y documentación. El estado y los planes Terraform, certificados, claves privadas, configuración local del cliente y entornos de ejecución permanecen excluidos mediante `.gitignore`.

```text
Simulador Python --MQTT/TLS--> IoT Core --regla--> Kinesis --> Lambda
                                                             |--> DynamoDB
                                                             |--> CloudWatch --> Grafana
```

## 1. Preparar Terraform en VS Code

Trabaja en la terminal PowerShell donde estan las credenciales temporales vigentes del Learner Lab. Se necesitan las tres variables AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY y AWS_SESSION_TOKEN. No las escribas en archivos Terraform.

```powershell
Set-Location -LiteralPath 'C:\lab5-750962'
aws sts get-caller-identity --no-cli-pager
terraform init
terraform fmt -check
terraform validate
terraform plan -out lab5.tfplan
```

Comprueba que el plan cree solo recursos del proyecto. El proveedor admite por defecto la cuenta Academy comprobada, 679322737424, y la region us-east-1. Si Academy asigna otra cuenta, revisa la identidad y actualiza expected_account_id de manera intencional.

```powershell
terraform apply lab5.tfplan
```

El proyecto reutiliza LabRole; no crea ni modifica roles o politicas IAM del laboratorio. La politica MQTT si se crea: es una politica de AWS IoT para el certificado del sensor, no una politica IAM. Las consultas de lectura que ya funcionaron no garantizan permisos de creacion, escritura o iam:PassRole. Si aparece AccessDenied, conserva el mensaje exacto y el estado; no elimines el estado ni repitas apply hasta entender el error. Un apply fallido puede haber creado algunos recursos.

### Recuperacion del error de retencion Kinesis

Si la creacion falla exactamente en IncreaseStreamRetentionPeriod con AccessDenied, el proveedor puede haber creado el stream y marcado su instancia en el estado como tainted (pendiente de reemplazo). Quitar retention_period de main.tf no evita necesariamente la llamada de creacion: el proveedor tambien tiene 24 como valor predeterminado.

Ejecuta desde la terminal con credenciales vigentes:

```powershell
.\recuperar-kinesis.ps1
```

El script verifica en AWS que el stream registrado esta ACTIVE, es PROVISIONED y tiene un shard y 24 horas de retencion. Tambien verifica que el ARN coincida con el estado y la cuenta esperada. Solo entonces ejecuta terraform untaint, que quita la marca de reemplazo en el estado; no recrea el stream ni modifica su retencion. Finalmente genera lab5-recuperado.tfplan con refresco normal. Si alguna comprobacion falla, detiene la recuperacion.

Revisa que el plan no elimine ni reemplace el stream. Para el despliegue parcial observado, normalmente quedaran por crear la regla IoT y la conexion Kinesis-Lambda. Si el plan es el esperado:

```powershell
terraform apply lab5-recuperado.tfplan
```

No reutilices lab5.tfplan: corresponde al estado anterior. Esta recuperacion administra el stream ya existente; no elimina la restriccion de permisos del laboratorio para futuras creaciones desde cero. Si se repite el caso en otro despliegue, vuelve a verificar el recurso antes de recuperar el estado.

Recursos principales: una tabla con capacidad bajo demanda, un stream Kinesis de un shard y retencion de 24 horas, una Lambda Python 3.12, su conexion a Kinesis, dos grupos de registros, un dispositivo IoT, su certificado, su politica y sus asociaciones, y una regla IoT. Kinesis puede generar cargos aunque no envies lecturas.

## 2. Exportar el certificado y ejecutar el simulador

```powershell
.\exportar-cliente.ps1
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r simulator\requirements.txt
.\.venv\Scripts\python.exe simulator\publish.py --scenario demo --count 24 --interval 5 --invalid
```

Si py no esta instalado pero python funciona, reemplaza `py -3` por `python`. El simulador requiere Python 3.9 o posterior. Si una politica de PowerShell bloquea exportar-cliente.ps1, ejecuta `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` para esa terminal.

La demostracion envia reposo, ejercicio y recuperacion, seguida de un mensaje incompleto. Los valores son sinteticos. Un bpm mayor que 120 activa supera_umbral_demo; es una regla educativa, no una alerta clinica. El umbral se puede cambiar mediante demo_threshold_bpm.

El simulador usa MQTT 3.1.1 sobre TLS, puerto 8883, QoS 1, client ID watch-750962 y topic lab5/750962/frecuencia. La confirmacion MQTT significa que IoT Core recibio el mensaje; no confirma que Lambda lo haya guardado. El certificado permite conectar y publicar solo con esos valores. Los permisos de la consola de pruebas MQTT son independientes.

Ejemplo de mensaje (el simulador genera siempre una fecha actual):

```json
{
  "usuario_id": "750962",
  "sensor_id": "watch-750962",
  "timestamp": "2026-10-13T16:30:00.000000Z",
  "bpm": 130,
  "actividad": "ejercicio"
}
```

## 3. Verificar las lecturas

Consulta las diez lecturas mas recientes, con consistencia fuerte:

```powershell
aws dynamodb query --table-name lab5-750962-lecturas --key-condition-expression 'sensor_id = :s' --expression-attribute-values file://consulta-sensor.json --no-scan-index-forward --limit 10 --consistent-read --region us-east-1 --no-cli-pager
aws logs tail /aws/lambda/lab5-750962-procesar --since 10m --region us-east-1 --no-cli-pager
aws logs tail /lab5/750962/iot-errors --since 10m --region us-east-1 --no-cli-pager
```

En DynamoDB la clave de particion es sensor_id y la clave de ordenamiento es timestamp normalizado a UTC. Se guardan bpm, actividad, usuario_id, el umbral y la marca de demostracion. Dos mensajes con el mismo sensor y timestamp se consideran la misma lectura. Los datos tienen un TTL de siete dias; la eliminacion por TTL es eventual.

Lambda rechaza mensajes mal formados y deja su motivo en los registros; no reintenta datos invalidos. Los errores al guardar en DynamoDB devuelven el primer numero de secuencia fallido para reintentar. El stream conserva los datos solo 24 horas, por lo que un error de permisos persistente debe resolverse antes de que expiren. No se ha configurado un archivo de registros descartados.

DynamoDB es el historial de referencia. Las metricas son auxiliares: si CloudWatch falla despues de guardar una lectura, la lectura permanece en DynamoDB, se registra el error y puede faltar ese punto en Grafana. No existe una transaccion atomica entre ambos servicios. Una interrupcion de Lambda justo despues del guardado tambien puede producir ese desfase.

## 4. Grafana (opcional, despues de verificar el flujo)

Se agrego configuracion automatica local con Docker: abre Docker Desktop y ejecuta `.\iniciar-grafana.ps1` desde la terminal que tiene las tres credenciales AWS. Consulta GRAFANA-LOCAL.md. La fuente CloudWatch y el tablero se configuran automaticamente. Las instrucciones manuales siguientes siguen siendo una alternativa para otra instalacion Grafana.

El proyecto incluye grafana/dashboard.json y su configuración automática con Docker. Terraform administra la infraestructura AWS; Grafana se ejecuta localmente. Puedes ejecutar Grafana localmente; no asumimos que Amazon Managed Grafana este disponible en Learner Lab.

Agrega una fuente de datos Amazon CloudWatch con region us-east-1 y autenticacion AWS SDK Default. Si Grafana se ejecuta localmente, su proceso debe recibir las credenciales temporales completas del laboratorio: iniciarlo desde la terminal que tiene esas variables es una opcion. Un servicio de Windows o un contenedor no hereda automaticamente las variables de esa terminal. Si ya estaba iniciado, renueva sus credenciales y reinicialo cuando sea necesario. No pongas claves en el JSON del tablero. Sigue la documentacion oficial para tu instalacion:

- https://grafana.com/docs/grafana/latest/datasources/aws-cloudwatch/configure/
- https://grafana.com/docs/grafana/latest/setup-grafana/installation/windows/

En la configuracion de CloudWatch agrega Lab5/750962 en Custom Metrics Namespaces si el selector no muestra el namespace. Importa el JSON y selecciona la fuente de datos CloudWatch cuando Grafana lo solicite.

Metricas: BPM y SuperaUmbralDemo. Dimensiones: Usuario=750962 y Sensor=watch-750962. El tablero muestra promedio de pulsaciones por minuto, maximo del periodo y numero de lecturas que superan el umbral de prueba. Los puntos de CloudWatch no son una lectura directa de la tabla DynamoDB. Las metricas nuevas pueden tardar varios minutos en aparecer en los selectores. Esta guia no configura notificaciones automaticas.

## 5. Evidencias para entregar

- El plan Terraform y los recursos creados, ocultando cualquier credencial o clave privada.
- Los mensajes del simulador y el topic de IoT Core.
- La regla IoT hacia Kinesis y el origen Kinesis de Lambda.
- Lecturas almacenadas en DynamoDB.
- Un mensaje rechazado y su motivo en los registros.
- El tablero Grafana, si se utiliza.

SQS no forma parte del diagrama implementado. Si la consigna del Lab 5 lo exige, falta agregar la cola y su consumidor; ese requisito aun no se ha confirmado.

## 6. Limpieza y archivos privados

Cuando termines y ya tengas tus evidencias, usa las credenciales vigentes de la misma cuenta para revisar y confirmar la eliminacion de los recursos de este proyecto:

```powershell
terraform plan -destroy
terraform destroy
```

No elimines terraform.tfstate antes de la limpieza. El estado y los planes pueden contener la clave privada del certificado IoT, aunque los outputs esten marcados como sensibles. No subas el estado, planes, certs, configuracion local o credenciales a Git ni los entregues como evidencia. El repositorio incluye .gitignore; conserva .terraform.lock.hcl en Git. terraform destroy no modifica LabRole y elimina la tabla y sus datos, entre otros recursos del proyecto.

## Pruebas locales del procesamiento

Opcional: estas pruebas usan servicios simulados y no acceden a AWS.

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```
