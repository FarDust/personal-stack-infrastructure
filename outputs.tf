output "artifact_bucket_name" {
  description = "The shared private artifact bucket for agent and cluster workloads."
  sensitive   = true
  value       = module.storage.artifact_bucket_name
}

output "dvc_base_url" {
  description = "Shared DVC namespace; append the repository's stable project slug."
  value       = module.storage.dvc_base_url
  sensitive   = true
}
