# Grafana local — Lab 5 / 750962

Las evidencias del alumno verifican MQTT, procesamiento Lambda, almacenamiento DynamoDB, metricas CloudWatch y rechazo del mensaje incompleto. Grafana visualizara las metricas de CloudWatch; DynamoDB conserva el historial.

## Iniciar

Abre Docker Desktop desde el menu Inicio de Windows y espera a que muestre el motor iniciado. En la terminal VS Code donde estan las tres credenciales temporales vigentes:

```powershell
Set-Location -LiteralPath 'C:\lab5-750962'
.\iniciar-grafana.ps1
```

El script verifica la cuenta AWS y Docker, descarga la imagen oficial grafana/grafana:13.2.4 y configura automaticamente CloudWatch y el tablero. La fuente usa AWS SDK Default y recibe las tres variables de la terminal mediante el entorno del contenedor. No se escriben sus valores en YAML ni en el tablero. No compartas docker inspect ni docker compose config: pueden mostrar esas variables resueltas.

Abre http://127.0.0.1:3005. Primer acceso: usuario admin y contrasena admin. Cambia la contrasena cuando Grafana lo solicite. Despues abre http://127.0.0.1:3005/d/lab5-750962-heart o entra a Dashboards → Lab 5.

El puerto local predeterminado es 3005, porque 3000 estaba ocupado. Si necesitas otro puerto, usa por ejemplo `.\iniciar-grafana.ps1 -Restart -Port 3006`; el script actualiza el mapeo Docker y los enlaces. Dentro del contenedor Grafana sigue usando 3000. El reinicio conserva el volumen de configuracion.

El servicio solo se expone a la computadora local. El volumen Docker guarda la configuracion y contrasena entre reinicios. No se crean servicios nuevos en AWS ni se requiere una cuenta Grafana Cloud.

Para enviar lecturas nuevas:

```powershell
.\.venv\Scripts\python.exe simulator\publish.py --scenario demo --count 60 --interval 5
```

El tablero consulta los ultimos 15 minutos y se refresca cada 10 segundos. Para la primera prueba, elige un rango que incluya 2026-10-13 18:35–18:38 UTC (12:35–12:38 en America/Mexico_City). Las metricas pueden tardar un poco en aparecer.

## Credenciales renovadas

Carga las tres variables nuevas de Learner Lab en la terminal y ejecuta:

```powershell
.\iniciar-grafana.ps1 -Restart
```

Se recrea el contenedor del proyecto con las credenciales nuevas, conservando el volumen. Cambiar las variables PowerShell no actualiza las de un contenedor que ya estaba iniciado.

## Diagnostico

- Revisa primero el rango de tiempo del tablero.
- En Connections → Data sources → CloudWatch Lab5 750962 usa Save & test. Si las credenciales vencieron, renuevalas y reinicia.
- ListMetrics autorizado no garantiza GetMetricData o GetMetricStatistics. Conserva el error exacto si hay AccessDenied.
- La fuente usa us-east-1, namespace Lab5/750962, Usuario=750962 y Sensor=watch-750962.
- Para problemas de inicio: `docker logs lab5-grafana-750962 --tail 30`.

## Detener al terminar

```powershell
docker compose --project-name lab5-750962 --file grafana\compose.yaml down
```

Elimina el contenedor del proyecto y conserva el volumen. La limpieza AWS se realiza por separado con Terraform, como indica README.md. No uses --volumes si quieres conservar la contrasena y cambios locales de Grafana.

## Estado de comprobacion

Grafana se inició correctamente con Docker en el puerto local 3005. El tablero mostró las métricas reales publicadas por Lambda para los datos simulados. En la segunda prueba, de 60 lecturas, se observó un máximo de 154 bpm y 20 lecturas sobre el umbral de demostración. La opción portable fue bloqueada por Control de aplicaciones de Windows; se utilizó Docker sin modificar esa protección.

Documentacion oficial:

- https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/
- https://grafana.com/docs/grafana/latest/datasources/aws-cloudwatch/configure/
- https://grafana.com/docs/grafana/latest/administration/provisioning/
