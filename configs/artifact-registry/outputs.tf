output "cluster_artifact_registry_repository_name" {
  description = "The private Artifact Registry repository name for internal cluster images."
  value       = data.google_artifact_registry_repository.cluster_internal_images.name
}

output "cluster_artifact_registry_repository_url" {
  description = "Docker registry URL for internal cluster images."
  value       = "${data.google_artifact_registry_repository.cluster_internal_images.location}-docker.pkg.dev/${data.google_artifact_registry_repository.cluster_internal_images.project}/${data.google_artifact_registry_repository.cluster_internal_images.repository_id}"
  sensitive   = true
}
