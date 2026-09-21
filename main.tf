
module "github-identity-federation" {
  source                   = "./modules/github-identity-federation"
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
  source                       = "./configs/storage"
  project_id                   = var.project_id
  gcp_region                   = var.gpu_idle_lab_dvc_location
  gpu_idle_lab_dvc_bucket_name = var.gpu_idle_lab_dvc_bucket_name
}
