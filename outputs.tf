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

output "cluster_artifact_registry_repository_url" {
  description = "Private Docker registry URL for internal cluster images."
  value       = module.cluster_artifact_registry.cluster_artifact_registry_repository_url
  sensitive   = true
}

data "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = "github-${var.identity_pool_id}"
  workload_identity_pool_provider_id = "github-${var.identity_provider_id}"

  depends_on = [module.github-identity-federation]
}

output "github_workload_identity_provider" {
  description = "Full resource name of the GitHub workload identity provider, for the workflow `workload_identity_provider` input. Record it privately."
  value       = data.google_iam_workload_identity_pool_provider.github.name
  sensitive   = true
}

output "federated_github_service_accounts" {
  description = "Federated service-account emails keyed by federated user alias, for the workflow `service_account` input. Record them privately."
  value       = { for alias, user in module.github-identity-federation.federated-github-users : alias => user.federated-user.email }
  sensitive   = true
}
