# MediSupply Infraestructura con Terraform (Versión Completa)

Este proyecto despliega en **Google Cloud (us-central1)** la arquitectura de microservicios para MediSupply e incluye **TODO** lo necesario para ejecutarla de extremo a extremo:

- **8 microservicios** en Cloud Run v2 (privados, accesibles solo vía API Gateway).
- **API Gateway** con autenticación JWT y rutas versionadas `/{country}/v1/...`.
- **Cloud SQL (PostgreSQL)** con **1 base de datos por microservicio** y **schemas por país** (`co`, `mx`, `ec`, `pe`).
- **Memorystore (Redis)** básico para caching.
- **Pub/Sub** con tópicos base.
- **Buckets de Cloud Storage** por país.
- **Secret Manager** con DSN por servicio y mapeo de schemas.
- **Serverless VPC Connector** para acceso privado desde Cloud Run a SQL/Redis.
- **Artifact Registry** (DOCKER) para alojar imágenes de los microservicios.
- **IAM** (bindings de proyecto) mínimos para que los servicios funcionen (Cloud SQL Client, Secret Accessor, Pub/Sub Publisher, Storage Object Admin).
- **Automatización** post-`apply` que crea los **schemas por país** en cada DB usando **Cloud SQL Auth Proxy** + `psql`.

> Proyecto: **misw4301-g26** · Región: **us-central1**

---

## 📂 Estructura recomendada

```
infra/
 ├── providers.tf
 ├── variables.tf
 ├── main.tf
 ├── iam.tf
 ├── artifact-registry.tf
 ├── openapi.yaml.tmpl
 ├── outputs.tf
 ├── terraform.tfvars
 ├── crea_schemas.sql
```

---

## 🚀 Requisitos previos

1) **Google Cloud SDK (gcloud)**  
   ```bash
   gcloud init
   gcloud auth application-default login
   ```

2) **Terraform >= 1.6**

3) **psql** (cliente PostgreSQL en PATH).

4) **Docker** (para construir y publicar imágenes).

5) Permisos en la cuenta que ejecuta Terraform (o en el Service Account si usas Terraform en CI):
   - `roles/editor` o granular:
     - `roles/run.admin`, `roles/iam.serviceAccountAdmin`, `roles/iam.serviceAccountUser`
     - `roles/cloudsql.admin`, `roles/cloudsql.client`
     - `roles/secretmanager.admin`
     - `roles/artifactregistry.admin`
     - `roles/pubsub.admin`
     - `roles/storage.admin`
     - `roles/apigateway.admin`
     - `roles/vpcaccess.admin`

---

## ⚙️ Configuración

Edita `infra/terraform.tfvars` (valores por defecto listos para `misw4301-g26`):

```hcl
project_id   = "misw4301-g26"
region       = "us-central1"
api_domain   = "api.medisupply.misw4301-g26.internal"

# ⚠️ Cambia esta contraseña por una fuerte y considera moverla a Secret Manager
db_password  = "cambia-esto-por-favor"

# JWT emitido por tu Servicio de Usuarios
jwt_issuer   = "https://auth.medisupply.com"
jwt_jwks_uri = "https://auth.medisupply.com/.well-known/jwks.json"
jwt_audience = "medi-supply-api"
```

Opcionalmente, ajusta en `variables.tf`:
- `service_images` para apuntar a tags/versiones específicas.
- `common_env` para variables comunes (`APP_ENV`, `LOG_LEVEL`, etc.).
- `countries` para agregar/quitar países (los schemas se crean dinámicamente).

---

## 🏗️ Despliegue (Infraestructura + Schemas)

### 1) Inicializa Terraform
```bash
cd infra
terraform init
```

### 2) Prepara el **Artifact Registry** y publica imágenes
> Terraform crea el repo `project-images` (archivo `artifact-registry.tf`). Luego publica tus imágenes:

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev

# Ejemplo para ms-compras (repite para cada servicio)
docker build -t us-central1-docker.pkg.dev/misw4301-g26/project-images/ms-compras:latest ./ms-compras
docker push    us-central1-docker.pkg.dev/misw4301-g26/project-images/ms-compras:latest
```

> Asegúrate de que `variables.tf` → `service_images` apunten a las rutas/tags que has publicado.

### 3) Verifica el plan
```bash
terraform plan -var-file="terraform.tfvars"
```

### 4) Aplica cambios
```bash
terraform apply -var-file="terraform.tfvars"
```

- Creará Cloud Run (v2) privado, Redis, Pub/Sub, Cloud SQL (instancia/DB/usuario), buckets, API Gateway y secrets.
- Al final, ejecutará **por cada DB** el script [`crea_schemas.sql`](./crea_schemas.sql) vía **Cloud SQL Proxy** + `psql` para crear `co|mx|ec|pe` y asignar permisos.

> Si el paso de schemas falla por falta de `psql` o permisos de Cloud SQL Client en tu cuenta local, corrige y reintenta:  
> ```bash
> terraform taint 'null_resource.create_country_schemas["db_ms_compras"]' # o todos con un for
> terraform apply -var-file="terraform.tfvars"
> ```

---

## 🗄️ Modelo de datos

- **Instancia**: `pg-main`
- **Usuario**: `appuser`
- **DBs** (una por servicio):
  - `db_ms_compras`, `db_ms_inventario`, `db_ms_pedidos`, `db_ms_logistica`,
    `db_ms_ventas_crm`, `db_ms_integraciones`, `db_ms_usuarios_aut`, `db_ms_telemetria`
- **Schemas por país**: `co`, `mx`, `ec`, `pe` (en **cada DB**).

> Los microservicios se conectan a **su DB** y definen `search_path` al schema según `{country}` del path.

---

## 🔑 Secretos

- `dsn-ms-*` (uno por servicio): DSN base de conexión a su DB.  
  Ejemplo form: `postgres://appuser:PASS@<PRIVATE_IP>:5432/db_ms_compras?sslmode=disable`
- `schema-map-json`: JSON con `{ "CO": "co", "MX": "mx", "EC": "ec", "PE": "pe" }`

> Reemplaza `PRIVATE_IP_OR_HOST` en el secreto por la **IP privada** de Cloud SQL o usa el **Cloud SQL Connector** (preferido en producción).

---

## 🌐 API Gateway

- Dominio: `api_domain`.
- Seguridad JWT (issuer/audience/jwks): se valida en el Gateway.
- Rutas de ejemplo:
  - `/public/v1/health` (sin JWT)
  - `/{country}/v1/compras/ordenes` → `ms-compras`
  - `/{country}/v1/inventario/items` → `ms-inventario`
  - `/{country}/v1/pedidos` → `ms-pedidos`
  - `/{country}/v1/logistica/envios` → `ms-logistica`
  - `/{country}/v1/ventas/ordenes` → `ms-ventas-crm`
  - `/{country}/v1/integraciones/proveedores` → `ms-integraciones`
  - `/{country}/v1/usuarios/me` → `ms-usuarios-autenticacion`
  - `/{country}/v1/telemetria/eventos` → `ms-telemetria`

---

## 🔐 IAM (proyecto)

Terraform crea los **bindings** mínimos para que los microservicios funcionen (archivo `iam.tf`). En resumen, las Service Accounts de los MS reciben:

- `roles/cloudsql.client` (conexión a Cloud SQL)
- `roles/secretmanager.secretAccessor` (lectura de secretos)
- `roles/pubsub.publisher` (publicar eventos)
- `roles/storage.objectAdmin` (leer/escribir objetos en GCS)

> El **Gateway SA** recibe permiso de invocar a los servicios (`roles/run.invoker`).

---

## ⚙️ Cloud Run: variables de entorno

Cada servicio recibe variables comunes (`common_env`) + infraestructura:

- `REDIS_HOST`: host privado de Redis
- `DB_NAME`: nombre de su DB
- `SERVICE_NAME`: nombre del servicio
- `PROJECT_ID`, `REGION` (puedes usarlas si deseas)
- Tus propias (`APP_ENV`, `LOG_LEVEL`, etc.)

> Agrega/ajusta en `variables.tf` → `common_env` y en `main.tf` el bloque `envs`.

---

## 💰 Costos aproximados (mensual)

- Cloud SQL (db-f1-micro): ~7.3 USD
- Redis BASIC (1GB): ~6.3 USD
- API Gateway: ~3 USD
- Cloud Run (bajo uso académico): ~0–5 USD
- Pub/Sub y Storage: casi cero  
**Total** ≈ **22 USD/mes** (≈ 44 USD por 2 meses)

---

## 🛠️ Troubleshooting

- **Falla creación de schemas**: instala `psql`, asegura `gcloud auth application-default login` y el rol `Cloud SQL Client`. Reintenta con `taint` del `null_resource` correspondiente.
- **No puedo invocar servicios**: confirma que el **Gateway SA** tiene `roles/run.invoker` sobre cada servicio.
- **Imágenes no encontradas**: verifica que publicaste las imágenes en `us-central1-docker.pkg.dev/misw4301-g26/project-images/...` y que `service_images` las referencia.
- **Conexión a DB rechazada**: usa **Cloud SQL Auth Proxy** local para diagnóstico y confirma que tus servicios se despliegan con el **Serverless VPC Connector**.

---

## ✅ Post-Apply Checks

1) `terraform output service_uris` → URLs internas de Cloud Run.  
2) `terraform output gateway_default_hostname` → hostname del Gateway.  
3) Prueba `/public/v1/health` y luego un endpoint protegido con JWT válido.  
4) En Cloud SQL, valida que en cada DB existan los schemas `co|mx|ec|pe`.

---

## 📎 Comandos útiles

```bash
# Levantar Cloud SQL Proxy local (diagnóstico)
./cloud-sql-proxy --private-ip --port 5432 misw4301-g26:us-central1:pg-main

# Conectarte con psql a una DB
PGPASSWORD="TU_PASS" psql "host=127.0.0.1 port=5432 dbname=db_ms_compras user=appuser sslmode=disable"

# Reaplicar solo el paso de schemas
terraform taint 'null_resource.create_country_schemas["db_ms_compras"]'
terraform apply -var-file="terraform.tfvars"
```

---

## 🧩 Notas finales

- En producción, prefiere **Cloud SQL Connector** (biblioteca del lenguaje) en lugar de IP privada directa; reduce superficie y rotación de credenciales.
- Agrega **observabilidad** (Cloud Trace/Profiler/Logging) en tus imágenes de servicio.
- Si expones públicamente, considera **Cloud Armor** (WAF/rate limiting) delante del Gateway.

---

¡Eso es todo! Con este repo Terraform puedes levantar el entorno completo, publicar imágenes y comenzar a trabajar con tus microservicios versionados por país.
