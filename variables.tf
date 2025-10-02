variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}

variable "api_domain" {
  type = string
  default = "api.medisupply.misw4301-g26.internal"
}

# Imágenes (puedes cambiar tags)
variable "service_images" {
  type = map(string)
  default = {
    "ms-compras"                 = "us-central1-docker.pkg.dev/misw4301-g26/project-images/ms-compras:latest"
    "ms-inventario"              = "us-central1-docker.pkg.dev/misw4301-g26/project-images/ms-inventario:latest"
    "ms-pedidos"                 = "us-central1-docker.pkg.dev/misw4301-g26/project-images/ms-pedidos:latest"
    "ms-logistica"               = "us-central1-docker.pkg.dev/misw4301-g26/project-images/ms-logistica:latest"
    "ms-ventas-crm"              = "us-central1-docker.pkg.dev/misw4301-g26/project-images/ms-ventas-crm:latest"
    "ms-integraciones"           = "us-central1-docker.pkg.dev/misw4301-g26/project-images/ms-integraciones:latest"
    "ms-usuarios-autenticacion"  = "us-central1-docker.pkg.dev/misw4301-g26/project-images/ms-usuarios-autenticacion:latest"
    "ms-telemetria"              = "us-central1-docker.pkg.dev/misw4301-g26/project-images/ms-telemetria:latest"
  }
}

# Env comunes (puedes añadir más luego)
variable "common_env" {
  type = map(string)
  default = {
    APP_ENV    = "prod"
    LOG_LEVEL  = "INFO"
    REDIS_PORT = "6379"
  }
}

# Países/shard
variable "countries" {
  type    = list(string)
  default = ["CO", "MX", "EC", "PE"]
}

# Pub/Sub tópicos base
variable "pubsub_topics" {
  type    = list(string)
  default = ["telemetria.eventos", "pedidos.creados", "inventario.actualizado", "integraciones.webhooks"]
}

# Memorystore Redis
variable "redis_tier" {
  type = string
  default = "BASIC"
}
variable "redis_size_gb" {
  type = number
  default = 1
}

# Cloud SQL
variable "db_tier" {
  type = string
  default = "db-f1-micro"
}
variable "db_version" {
  type = string
  default = "POSTGRES_15"
}
variable "db_user" {
  type = string
  default = "appuser"
}
variable "db_password" {
  type = string
  default = "CHANGEME-STRONG-PASS"
}

# JWT (servicio de usuarios)
variable "jwt_issuer" {
  type = string
  default = "https://auth.medisupply.com"
}
variable "jwt_jwks_uri" {
  type = string
  default = "https://auth.medisupply.com/.well-known/jwks.json"
}
variable "jwt_audience" {
  type = string
  default = "medi-supply-api"
}
