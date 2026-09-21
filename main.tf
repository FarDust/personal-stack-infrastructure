
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
