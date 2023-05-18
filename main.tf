
module "github-identity-federation" {
  source = "git@github.com:FarDust/terraform-infrastructure.git//modules/github-identity-federation?ref=752db911c1d9cc8d1ce4a665f5d5a1791796bd5d"
  project-id = var.project_id
  federated-github-users = var.federated_github_users
  landing-identity-pool-id = var.identity_pool_id
  identity-provider-id = var.identity_provider_id
}

resource "google_project_iam_member" "github-actions-artifacts-binding" {
  depends_on = [
    module.github-identity-federation
  ]
  project = var.project_id
  role = "roles/secretmanager.secretAccessor"
  member = "serviceAccount:${module.github-identity-federation.federated-github-users["secrets"].federated-user.email}"
}