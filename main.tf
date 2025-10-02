locals {
  services = [
    "ms-compras",
    "ms-inventario",
    "ms-pedidos",
    "ms-logistica",
    "ms-ventas-crm",
    "ms-integraciones",
    "ms-usuarios-autenticacion",
    "ms-telemetria"
  ]

  # DB por microservicio (nombre de DB en Postgres)
  db_per_service = {
    "ms-compras"                 = "db_ms_compras"
    "ms-inventario"              = "db_ms_inventario"
    "ms-pedidos"                 = "db_ms_pedidos"
    "ms-logistica"               = "db_ms_logistica"
    "ms-ventas-crm"              = "db_ms_ventas_crm"
    "ms-integraciones"           = "db_ms_integraciones"
    "ms-usuarios-autenticacion"  = "db_ms_usuarios_aut"
    "ms-telemetria"              = "db_ms_telemetria"
  }

  api_name     = "medisupply-api"
  gateway_name = "medisupply-gw"
  vpc_network  = "default"
}

# ---------- Service Accounts ----------
resource "google_service_account" "gateway_sa" {
  account_id   = "gw-medisupply"
  display_name = "Gateway SA"
}

resource "google_service_account" "ms_sa" {
  for_each     = toset(local.services)
  account_id   = "sa-${each.key}"
  display_name = "SA ${each.key}"
}

# ---------- Serverless VPC Connector ----------
resource "google_vpc_access_connector" "srvless" {
  name          = "srvless-conn"
  region        = var.region
  network       = local.vpc_network
  ip_cidr_range = "10.8.0.0/28"
}

# ---------- Memorystore (Redis) ----------
resource "google_redis_instance" "redis" {
  name               = "ms-redis"
  tier               = var.redis_tier
  memory_size_gb     = var.redis_size_gb
  region             = var.region
  authorized_network = "projects/${var.project_id}/global/networks/${local.vpc_network}"
}

# ---------- Cloud SQL (1 instancia) ----------
resource "google_sql_database_instance" "pg" {
  name             = "pg-main"
  database_version = var.db_version
  region           = var.region

  settings {
    tier = var.db_tier
    ip_configuration {
      ipv4_enabled    = false
      private_network = "projects/${var.project_id}/global/networks/${local.vpc_network}"
    }
    activation_policy = "ALWAYS"
  }
}

resource "google_sql_user" "pguser" {
  instance = google_sql_database_instance.pg.name
  name     = var.db_user
  password = var.db_password
}

resource "google_sql_database" "db" {
  for_each = local.db_per_service
  name     = each.value
  instance = google_sql_database_instance.pg.name
}

# ---------- Pub/Sub ----------
resource "google_pubsub_topic" "topics" {
  for_each = toset(var.pubsub_topics)
  name     = each.key
}

# ---------- Cloud Storage ----------
resource "google_storage_bucket" "buckets" {
  for_each                    = toset(var.countries)
  name                        = "${var.project_id}-medi-${lower(each.key)}"
  location                    = "US"
  uniform_bucket_level_access = true
  force_destroy               = false
}

# ---------- Cloud Run v2 ----------
resource "google_cloud_run_v2_service" "svc" {
  for_each = toset(local.services)

  name     = each.key
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.ms_sa[each.key].email

    scaling { max_instance_count = 50 }

    vpc_access {
      connector = google_vpc_access_connector.srvless.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = lookup(var.service_images, each.key)
      dynamic "env" {
        for_each = merge(
          var.common_env,
          {
            REDIS_HOST               = google_redis_instance.redis.host
            DB_NAME                  = local.db_per_service[each.key]
            DB_USER                  = var.db_user
            DB_PASS                  = var.db_password
            INSTANCE_CONNECTION_NAME = google_sql_database_instance.pg.connection_name
            SERVICE_NAME             = each.key
            PROJECT_ID               = var.project_id
            REGION                   = var.region
          }
        )
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
}

# Permitir que el Gateway invoque cada servicio
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = toset(local.services)
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.svc[each.key].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.gateway_sa.email}"
}

# ---------- API Gateway ----------
resource "google_api_gateway_api" "api" {
  provider = google-beta
  api_id   = local.api_name
}

data "template_file" "openapi" {
  template = file("${path.module}/openapi.yaml.tmpl")
  vars = {
    API_DOMAIN   = var.api_domain
    JWT_ISSUER   = var.jwt_issuer
    JWT_JWKS_URI = var.jwt_jwks_uri
    JWT_AUDIENCE = var.jwt_audience

    MS_COMPRAS_URL                = google_cloud_run_v2_service.svc["ms-compras"].uri
    MS_INVENTARIO_URL             = google_cloud_run_v2_service.svc["ms-inventario"].uri
    MS_PEDIDOS_URL                = google_cloud_run_v2_service.svc["ms-pedidos"].uri
    MS_LOGISTICA_URL              = google_cloud_run_v2_service.svc["ms-logistica"].uri
    MS_VENTAS_CRM_URL             = google_cloud_run_v2_service.svc["ms-ventas-crm"].uri
    MS_INTEGRACIONES_URL          = google_cloud_run_v2_service.svc["ms-integraciones"].uri
    MS_USUARIOS_AUTENTICACION_URL = google_cloud_run_v2_service.svc["ms-usuarios-autenticacion"].uri
    MS_TELEMETRIA_URL             = google_cloud_run_v2_service.svc["ms-telemetria"].uri
  }
}

resource "google_api_gateway_api_config" "cfg" {
  provider      = google-beta
  api           = google_api_gateway_api.api.api_id
  api_config_id = "medi-config"

  openapi_documents {
    document {
      path     = "openapi.yaml"
      contents = base64encode(data.template_file.openapi.rendered)
    }
  }

  depends_on = [google_cloud_run_v2_service.svc]
}

resource "google_api_gateway_gateway" "gw" {
  provider   = google-beta
  gateway_id = local.gateway_name
  api_config = google_api_gateway_api_config.cfg.id
  region     = var.region
}

# ---------- Crear schemas por país en cada DB ----------
resource "null_resource" "create_country_schemas" {
  for_each = local.db_per_service

  triggers = {
    sql_hash       = filesha256("${path.module}/crea_schemas.sql")
    db_name        = each.value
    instance_cn    = google_sql_database_instance.pg.connection_name
    db_user        = var.db_user
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      set -euo pipefail

      PROXY_BIN="$${PROXY_BIN:-cloud-sql-proxy}"
      if ! command -v "$${PROXY_BIN}" >/dev/null 2>&1; then
        echo "[INFO] Descargando Cloud SQL Proxy..."
        curl -sSL -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.10.1/cloud-sql-proxy.linux.amd64
        chmod +x cloud-sql-proxy
        PROXY_BIN="./cloud-sql-proxy"
      else
        PROXY_BIN="$(command -v $${PROXY_BIN})"
      fi

      INSTANCE="${google_sql_database_instance.pg.connection_name}"
      echo "[INFO] Iniciando proxy contra instancia: $${INSTANCE}"
      "$${PROXY_BIN}" --private-ip --port 5432 "$${INSTANCE}" >/dev/null 2>&1 &
      PROXY_PID=$!

      for i in $(seq 1 30); do
        (echo > /dev/tcp/127.0.0.1/5432) >/dev/null 2>&1 && break || sleep 1
      done

      export PGPASSWORD='${var.db_password}'
      DBNAME='${each.value}'
      echo "[INFO] Creando/verificando schemas en DB: $${DBNAME}"

      psql "host=127.0.0.1 port=5432 dbname=$${DBNAME} user=${var.db_user} sslmode=disable" \
        -v ON_ERROR_STOP=1 \
        -f "${path.module}/crea_schemas.sql"

      kill $${PROXY_PID} || true
      wait $${PROXY_PID} 2>/dev/null || true
      echo "[OK] Schemas creados/verificados en $${DBNAME}"
    EOT
  }

  depends_on = [
    google_sql_database_instance.pg,
    google_sql_user.pguser,
    google_sql_database.db
  ]
}
