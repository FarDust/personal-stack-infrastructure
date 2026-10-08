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

output "workspace_backup_writer_service_account" {
  description = "The service-account principal used by the externally managed workspace-backup runner."
  value       = module.workspace_backup_storage.writer_service_account_email
  sensitive   = true
}

output "workspace_backup_managed_folder_paths" {
  description = "The private managed-folder paths reserved for workspace backups."
  value       = module.workspace_backup_storage.managed_folder_paths
  sensitive   = true
}
