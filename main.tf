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

  frontend_service = "ms-app-web"

  # DB por microservicio (nombre de DB en Postgres)
  db_per_service = {
    "ms-compras"                = "db_ms_compras"
    "ms-inventario"             = "db_ms_inventario"
    "ms-pedidos"                = "db_ms_pedidos"
    "ms-logistica"              = "db_ms_logistica"
    "ms-ventas-crm"             = "db_ms_ventas_crm"
    "ms-integraciones"          = "db_ms_integraciones"
    "ms-usuarios-autenticacion" = "db_ms_usuarios_aut"
    "ms-telemetria"             = "db_ms_telemetria"
  }

  api_name     = "medisupply-api"
  gateway_name = "medisupply-gw"
  vpc_network  = "default"

  inbox_services = toset([
    for service in local.services : service
    if !contains([
      "ms-usuarios-autenticacion",
      "ms-integraciones",
      "ms-compras"
    ], service)
  ])

}

# ---------- Service Accounts ----------
resource "google_service_account" "gateway_sa" {
  account_id   = "gw-medisupply"
  display_name = "Gateway SA"
}

# Incluir backend + frontend para SAs
resource "google_service_account" "ms_sa" {
  for_each     = toset(setunion(local.services, [local.frontend_service]))
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

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = "projects/${var.project_id}/global/networks/${local.vpc_network}"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

resource "google_compute_global_address" "private_ip_range" {
  name          = "cloudsql-private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = "projects/${var.project_id}/global/networks/${local.vpc_network}"
}

# ---------- Cloud SQL (1 instancia) ----------
resource "google_sql_database_instance" "pg" {
  name             = "pg-main"
  database_version = var.db_version
  region           = var.region

  settings {
    tier = var.db_tier

    ip_configuration {
      ipv4_enabled    = true
      private_network = "projects/${var.project_id}/global/networks/${local.vpc_network}"
    }

    activation_policy = "ALWAYS"
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
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

locals {
  pg_private_ip = one([
    for ip in google_sql_database_instance.pg.ip_address : ip.ip_address
    if ip.type == "PRIVATE"
  ])
}

# ---------- Pub/Sub ----------
resource "google_pubsub_topic" "inbox" {
  for_each = local.inbox_services
  name     = replace(each.key, "ms-", "")

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [labels]
  }
}

resource "google_pubsub_subscription" "inbox_push" {
  for_each = local.inbox_services
  name     = "${replace(each.key, "ms-", "")}-inbox"
  topic    = google_pubsub_topic.inbox[each.key].name

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.svc[each.key].uri}/pubsub"
  }

  ack_deadline_seconds       = 90
  message_retention_duration = "86400s"

  expiration_policy {
    ttl = "604800s"
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  enable_exactly_once_delivery = false
}

# ---------- Cloud Storage ----------
resource "google_storage_bucket" "buckets" {
  for_each                    = toset(var.countries)
  name                        = "${var.project_id}-medi-${lower(each.key)}"
  location                    = "US"
  uniform_bucket_level_access = true
  force_destroy               = false
}

# ---------- Cloud Run v2 (Backends) ----------
resource "google_cloud_run_v2_service" "svc" {
  for_each = toset(local.services)
  name     = each.key
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

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
            DB_HOST                  = local.pg_private_ip
            DB_PORT                  = 5432
            INSTANCE_CONNECTION_NAME = google_sql_database_instance.pg.connection_name
            SERVICE_NAME             = each.key
            PROJECT_ID               = var.project_id
            REGION                   = var.region
            JWT_SECRET_KEY           = "M1swN3JvNWMtZzI2LXNlY3JldC1mItand0LTIwMjUtbWlzd0A0MzAxIQ=="
            GATEWAY_BASE_URL         = var.gateway_base_url
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

# ---------- Cloud Run v2 (Frontend) ----------
resource "google_cloud_run_v2_service" "frontend" {
  name     = local.frontend_service # "ms-app-web"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.ms_sa[local.frontend_service].email

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      image = lookup(var.service_images, local.frontend_service)

      ports {
        container_port = 8080
      }

      env {
        name  = "GATEWAY_BASE_URL"
        value = "https://${google_api_gateway_gateway.gw.default_hostname}"
      }
    }
  }
}

# ---------- IAM: permitir invocación pública ----------
# Backends
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = toset(local.services)
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.svc[each.key].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Frontend
resource "google_cloud_run_v2_service_iam_member" "invoker_frontend" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
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
  api_config_id = "medi-config-${formatdate("YYYYMMDD-HHmmss", timestamp())}"

  openapi_documents {
    document {
      path     = "openapi.yaml"
      contents = base64encode(data.template_file.openapi.rendered)
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_api_gateway_gateway" "gw" {
  provider   = google-beta
  gateway_id = local.gateway_name
  api_config = google_api_gateway_api_config.cfg.id
  region     = var.region
}
