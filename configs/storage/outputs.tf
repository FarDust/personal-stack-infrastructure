output "artifact_bucket_name" {
  description = "The shared private GCS artifact bucket."
  value       = google_storage_bucket.shared_artifacts.name
  sensitive   = true
}

output "dvc_base_url" {
  description = "DVC namespace; append a project slug to isolate each remote."
  value       = "gs://${google_storage_bucket.shared_artifacts.name}/dvc"
  sensitive   = true
}
