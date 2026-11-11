
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

  noncurrent_version_expiry = merge(var.loki_storage_folder_path == "" ? {} : {
    loki = {
      prefix = var.loki_storage_folder_path
      days   = var.loki_noncurrent_version_days
    }
    }, var.panel_backup_folder_path != "" && var.panel_backup_bucket_name == var.artifact_bucket_name ? {
    panel = {
      prefix = var.panel_backup_folder_path
      days   = 1
    }
  } : {})
}

module "wallet_signing" {
  source                    = "./configs/wallet-signing"
  project_id                = var.project_id
  signer_service_account_id = var.wallet_signer_service_account_id
  signer_members            = var.wallet_signer_members
}

module "workspace_backup_storage" {
  source                        = "./configs/workspace-backup-storage"
  project_id                    = var.project_id
  artifact_bucket_name          = var.artifact_bucket_name
  workspace_backup_folder_paths = var.workspace_backup_folder_paths
  writer_service_account_id     = var.workspace_backup_writer_service_account_id
}

module "panel_backup_storage" {
  source        = "./configs/panel-backup-storage"
  enabled       = nonsensitive(var.panel_backup_folder_path != "")
  project_id    = var.project_id
  bucket_name   = var.panel_backup_bucket_name
  folder_path   = var.panel_backup_folder_path
  grant_enabled = var.panel_backup_grant_enabled
  depends_on    = [module.storage]
}

module "cluster_artifact_registry" {
  source                                  = "./configs/artifact-registry"
  project_id                              = var.project_id
  cluster_artifact_registry_location      = var.cluster_artifact_registry_location
  cluster_artifact_registry_repository_id = var.cluster_artifact_registry_repository_id
  cluster_artifact_registry_writers       = var.cluster_artifact_registry_writers
  cluster_artifact_registry_readers       = var.cluster_artifact_registry_readers
}

module "python_artifact_registry" {
  # Reuses the reader/writer module for the bootstrap-owned PYTHON repository; resource names inside keep the original wording.
  source                                  = "./configs/artifact-registry"
  project_id                              = var.project_id
  cluster_artifact_registry_location      = var.python_artifact_registry_location
  cluster_artifact_registry_repository_id = var.python_artifact_registry_repository_id
  cluster_artifact_registry_writers       = var.python_artifact_registry_writers
  cluster_artifact_registry_readers       = var.python_artifact_registry_readers
}

module "loki_storage" {
  source                   = "./configs/loki-storage"
  project_id               = var.project_id
  artifact_bucket_name     = module.storage.artifact_bucket_name
  loki_storage_folder_path = var.loki_storage_folder_path
  loki_service_account_id  = var.loki_service_account_id
}

module "asset_connector" {
  source                  = "./configs/asset-connector"
  project_id              = var.project_id
  region                  = var.asset_connector_region
  zone                    = var.asset_connector_zone
  bucket_name             = var.asset_connector_bucket_name
  cors_origin             = var.asset_connector_cors_origin
  tailscale_tag           = var.asset_connector_tailscale_tag
  tailscale_version       = var.asset_connector_tailscale_version
  tailscale_sha256        = var.asset_connector_tailscale_sha256
  nginx_version           = var.asset_connector_nginx_version
  nginx_deb_sha256        = var.asset_connector_nginx_deb_sha256
  nginx_common_deb_sha256 = var.asset_connector_nginx_common_deb_sha256
  tenants                 = var.asset_connector_tenants
  tailscale_authkey       = var.asset_connector_tailscale_authkey
  notification_email      = var.asset_connector_notification_email
  billing_account_id      = var.asset_connector_billing_account_id
  budget_usd              = var.asset_connector_budget_usd
}
