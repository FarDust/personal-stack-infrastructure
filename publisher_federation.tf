locals {
  github_federated_users = {
    for key, user in var.federated_github_users : key => merge(user, {
      allowed-repositories = key == var.github_image_publisher.federated_user_key ? [] : user.allowed-repositories
    })
  }
}

module "github_image_publisher" {
  source = "./configs/github-image-publisher"

  project_id                    = var.project_id
  workload_identity_pool_id     = var.identity_pool_id
  workload_identity_provider_id = var.github_image_publisher.workload_identity_provider_id
  service_account_id            = try(module.github-identity-federation.federated-github-users[var.github_image_publisher.federated_user_key].federated-user.name, "projects/invalid/serviceAccounts/invalid@invalid.iam.gserviceaccount.com")
  repository                    = var.github_image_publisher.repository
  repository_id                 = var.github_image_publisher.repository_id
  workflow_path                 = var.github_image_publisher.workflow_path
}
