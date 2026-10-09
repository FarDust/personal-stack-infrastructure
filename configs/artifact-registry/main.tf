data "google_artifact_registry_repository" "cluster_internal_images" {
  project       = var.project_id
  location      = var.cluster_artifact_registry_location
  repository_id = var.cluster_artifact_registry_repository_id
}

resource "google_artifact_registry_repository_iam_member" "cluster_internal_image_writer" {
  # Only stable, non-secret aliases are exposed as resource keys, never identities.
  for_each   = nonsensitive(toset(keys(var.cluster_artifact_registry_writers)))
  project    = data.google_artifact_registry_repository.cluster_internal_images.project
  location   = data.google_artifact_registry_repository.cluster_internal_images.location
  repository = data.google_artifact_registry_repository.cluster_internal_images.name
  role       = "roles/artifactregistry.writer"
  member     = var.cluster_artifact_registry_writers[each.key]
}

resource "google_artifact_registry_repository_iam_member" "cluster_internal_image_reader" {
  # Only stable, non-secret aliases are exposed as resource keys, never identities.
  for_each   = nonsensitive(toset(keys(var.cluster_artifact_registry_readers)))
  project    = data.google_artifact_registry_repository.cluster_internal_images.project
  location   = data.google_artifact_registry_repository.cluster_internal_images.location
  repository = data.google_artifact_registry_repository.cluster_internal_images.name
  role       = "roles/artifactregistry.reader"
  member     = var.cluster_artifact_registry_readers[each.key]
}
