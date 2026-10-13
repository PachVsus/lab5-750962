# Validación y resultados

## Comprobaciones locales

- Terraform inicializado con AWS provider 6.68.0 y Archive provider 2.8.1; versiones fijadas en `.terraform.lock.hcl`.
- `terraform validate` y `terraform fmt -check -recursive`: correctos.
- Siete pruebas de Lambda aprobadas: lectura válida, duplicados, mensaje incompleto, Base64 inválido, tipos inválidos, fallo de almacenamiento y fallo de métricas.
- Cuatro pruebas simuladas de la recuperación de Kinesis aprobaron: stream válido con marca, stream válido sin marca, retención incorrecta y ARN incorrecto.
- Sintaxis PowerShell, JSON del tablero y configuración Docker Compose comprobados.
- Mapeos locales 3005 y 3006 validados hacia el puerto 3000 del contenedor.

## Ejecución en AWS Academy Learner Lab

Las evidencias de terminal y tablero del 13 de octubre de 2026 verifican:

- Despliegue Terraform completado: se crearon la regla IoT y el origen Kinesis-Lambda que faltaban del primer apply.
- Publicación MQTT confirmada por AWS IoT Core.
- Lecturas almacenadas y consultadas con consistencia fuerte en DynamoDB.
- Métrica BPM disponible en CloudWatch bajo `Lab5/750962`, con Usuario=750962 y Sensor=watch-750962.
- Mensaje sin bpm rechazado por Lambda, mientras una lectura válida del mismo lote se guardó.
- Grafana iniciado en Docker y conectado a CloudWatch en `http://127.0.0.1:3005`.

## Pruebas de datos

| Prueba | Entrada | Resultado |
| --- | --- | --- |
| Primera | 24 lecturas válidas y un mensaje incompleto | Persistencia, clasificación y rechazo del mensaje sin bpm |
| Segunda | 60 lecturas válidas cada cinco segundos | Gráfica de promedios por minuto, máximo de 154 bpm y 20 lecturas sobre 120 bpm |

## Incidencias resueltas

- **Retención de Kinesis:** el proveedor intentó ejecutar `IncreaseStreamRetentionPeriod` y Learner Lab lo rechazó. Se verificó el stream existente y se retiró su marca `tainted`; un nuevo plan completó las dependencias sin destruir recursos.
- **Ejecución portable de Grafana:** Windows bloqueó el ejecutable. Se utilizó la imagen oficial en Docker.
- **Puerto ocupado:** el puerto 3000 local estaba asignado; Grafana se configuró en 3005.

## Alcance

Se utilizan datos simulados y Kinesis como canal de ingestión. No se desplegó SQS ni se configuraron notificaciones automáticas. DynamoDB conserva el historial; las métricas CloudWatch son auxiliares y pueden omitir un punto si su publicación falla después de guardar una lectura. La limpieza de los recursos AWS se realiza por separado con Terraform.
