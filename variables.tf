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
    "ms-app-web"                 = "us-central1-docker.pkg.dev/misw4301-g26/project-images/ms-app-web:latest"
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
  default = ["pedidos", "inventario", "pedidos", "ventas-crm", "integraciones", "telemetria", "compras"]
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
}

variable "db_password" {
  type      = string
  sensitive = true
}

# JWT (servicio de usuarios)
variable "jwt_issuer" {
  type = string
  default = "ms-usuarios-autenticacion"
}

variable "jwt_jwks_uri" {
  type = string
  default = "/.well-known/jwks.json"
}

variable "gateway_base_url" {
  type        = string
  description = "Base URL pública del API Gateway (p.ej. https://medisupply-gw-xxxxx.uc.gateway.dev)"
  validation {
    condition     = can(regex("^https://", var.gateway_base_url))
    error_message = "gateway_base_url debe empezar por https://"
  }
}
