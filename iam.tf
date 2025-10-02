# Dar permisos a las service accounts de microservicios para conectarse a Cloud SQL y usar secretos
resource "google_project_iam_binding" "ms_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  members = [for sa in google_service_account.ms_sa : "serviceAccount:${sa.email}"]
}

resource "google_project_iam_binding" "ms_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  members = [for sa in google_service_account.ms_sa : "serviceAccount:${sa.email}"]
}

resource "google_project_iam_binding" "ms_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  members = [for sa in google_service_account.ms_sa : "serviceAccount:${sa.email}"]
}

resource "google_project_iam_binding" "ms_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  members = [for sa in google_service_account.ms_sa : "serviceAccount:${sa.email}"]
}
