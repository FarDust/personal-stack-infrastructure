output "gpu_idle_lab_dvc_bucket" {
  description = "The private GCS bucket for GPU Idle Lab DVC artifacts."
  sensitive   = true
  value       = module.storage.gpu_idle_lab_dvc_bucket
}
