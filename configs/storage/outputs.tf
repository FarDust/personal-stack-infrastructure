output "gpu_idle_lab_dvc_bucket" {
  description = "The private GCS bucket for DVC artifacts."
  value       = google_storage_bucket.gpu_idle_lab_dvc.name
  sensitive   = true
}
