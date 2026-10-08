
module "github-identity-federation" {
  # v0.1.0
  source                   = "git::https://github.com/FarDust/terraform-infrastructure.git//modules/github-identity-federation?ref=132e099a43d302b472863e110f11338833503eb6"
  github_repository_owner  = var.github_repository_owner
  project-id               = var.project_id
  federated-github-users   = var.federated_github_users
  landing-identity-pool-id = var.identity_pool_id
  identity-provider-id     = var.identity_provider_id
}

resource "google_project_iam_member" "github-actions-artifacts-binding" {
  depends_on = [
    module.github-identity-federation
  ]
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${module.github-identity-federation.federated-github-users["secrets"].federated-user.email}"
}

module "storage" {
  source                   = "./configs/storage"
  project_id               = var.project_id
  artifact_bucket_location = var.artifact_bucket_location
  artifact_bucket_name     = var.artifact_bucket_name
  artifact_bucket_writers  = var.artifact_bucket_writers
}

module "workspace_backup_storage" {
  source                        = "./configs/workspace-backup-storage"
  project_id                    = var.project_id
  artifact_bucket_name          = var.artifact_bucket_name
  workspace_backup_folder_paths = var.workspace_backup_folder_paths
  writer_service_account_id     = var.workspace_backup_writer_service_account_id
}

module "cluster_artifact_registry" {
  source                                  = "./configs/artifact-registry"
  project_id                              = var.project_id
  terraform_executor                      = var.terraform_executor
  cluster_artifact_registry_location      = var.cluster_artifact_registry_location
  cluster_artifact_registry_repository_id = var.cluster_artifact_registry_repository_id
  cluster_artifact_registry_writers       = var.cluster_artifact_registry_writers
  cluster_artifact_registry_readers       = var.cluster_artifact_registry_readers
}
