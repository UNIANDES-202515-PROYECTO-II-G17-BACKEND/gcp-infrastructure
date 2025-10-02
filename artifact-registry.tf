resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "project-images"
  description   = "Repo de imágenes de microservicios"
  format        = "DOCKER"
}
