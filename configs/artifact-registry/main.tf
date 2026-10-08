resource "google_project_iam_member" "terraform_executor_artifact_registry_admin" {
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = var.terraform_executor
}

resource "google_artifact_registry_repository" "cluster_internal_images" {
  project       = var.project_id
  location      = var.cluster_artifact_registry_location
  repository_id = var.cluster_artifact_registry_repository_id
  description   = "Private Docker images for internal cluster services"
  format        = "DOCKER"

  depends_on = [
    google_project_iam_member.terraform_executor_artifact_registry_admin
  ]
}

resource "google_artifact_registry_repository_iam_member" "cluster_internal_image_writer" {
  # Only stable, non-secret aliases are exposed as resource keys, never identities.
  for_each   = nonsensitive(toset(keys(var.cluster_artifact_registry_writers)))
  project    = google_artifact_registry_repository.cluster_internal_images.project
  location   = google_artifact_registry_repository.cluster_internal_images.location
  repository = google_artifact_registry_repository.cluster_internal_images.name
  role       = "roles/artifactregistry.writer"
  member     = var.cluster_artifact_registry_writers[each.key]
}

resource "google_artifact_registry_repository_iam_member" "cluster_internal_image_reader" {
  # Only stable, non-secret aliases are exposed as resource keys, never identities.
  for_each   = nonsensitive(toset(keys(var.cluster_artifact_registry_readers)))
  project    = google_artifact_registry_repository.cluster_internal_images.project
  location   = google_artifact_registry_repository.cluster_internal_images.location
  repository = google_artifact_registry_repository.cluster_internal_images.name
  role       = "roles/artifactregistry.reader"
  member     = var.cluster_artifact_registry_readers[each.key]
}
