locals {
  github_federated_users = {
    for key, user in var.federated_github_users : key => merge(user, {
      allowed-repositories = key == var.github_image_publisher.federated_user_key && !var.github_image_publisher.retain_general_provider_access ? [] : user.allowed-repositories
    })
  }
  github_image_publisher_user = contains(keys(var.federated_github_users), var.github_image_publisher.federated_user_key) ? var.federated_github_users[var.github_image_publisher.federated_user_key] : null
  github_image_publisher_account_id = local.github_image_publisher_user == null ? null : (
    endswith(local.github_image_publisher_user.name, "-fa") ? local.github_image_publisher_user.name : "${local.github_image_publisher_user.name}-federated-user"
  )
  github_image_publisher_principal = local.github_image_publisher_account_id == null ? null : "serviceAccount:${local.github_image_publisher_account_id}@${var.project_id}.iam.gserviceaccount.com"
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
  trusted_workflow_path         = var.github_image_publisher.trusted_workflow_path
}
