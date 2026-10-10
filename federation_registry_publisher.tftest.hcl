mock_provider "google" {}

variables {
  github_repository_owner  = "example-owner"
  project-id               = "example-project"
  landing-identity-pool-id = "example-pool"
  identity-provider-id     = "example-provider"
  federated-github-users = {
    secrets = {
      name                 = "secrets"
      display_name         = "Secrets"
      description          = "reads secrets"
      allowed-repositories = ["example-owner/example-secrets"]
    }
    publisher = {
      name                 = "example-publisher-fa"
      display_name         = "Example Publisher"
      description          = "publishes images to the private registry"
      allowed-repositories = ["example-owner/example-publisher"]
    }
  }
}

run "publisher_has_its_own_account_and_preserves_owner_condition" {
  command = plan
  module {
    source = "./.terraform/modules/github-identity-federation/modules/github-identity-federation"
  }
  providers = {
    google = google
  }
  assert {
    condition     = nonsensitive(length(output.federated-github-users)) == 2 && nonsensitive(output.federated-github-users["publisher"].federated-user.account_id) == "example-publisher-fa" && nonsensitive(output.federated-github-users["secrets"].federated-user.account_id) == "secrets-federated-user"
    error_message = "The publisher must receive a dedicated service account without altering the existing one."
  }
  assert {
    condition     = nonsensitive(output.federated-github-users["publisher"].iam_member_count) == 1 && nonsensitive(output.federated-github-users["publisher"].iam_binding_count) == 0
    error_message = "The publisher must have exactly one additive member and no authoritative binding."
  }
  assert {
    condition     = nonsensitive(output.owner_condition) == "attribute.repository_owner == \"example-owner\"\n"
    error_message = "The owner condition must remain exactly unchanged."
  }
  assert {
    condition     = issensitive(output.federated-github-users) && issensitive(output.owner_condition)
    error_message = "Federation outputs and the owner condition must remain sensitive."
  }
}

run "publisher_member_is_exact_repository" {
  command = plan
  module {
    source = "./.terraform/modules/github-identity-federation/modules/github-identity-federation/federated-github-user"
  }
  providers = {
    google = google
  }
  variables {
    project-id           = "example-project"
    identity-pool-name   = "projects/123456/locations/global/workloadIdentityPools/example-pool"
    name                 = "example-publisher-fa"
    display_name         = "Example Publisher"
    description          = "publishes images to the private registry"
    allowed-repositories = ["example-owner/example-publisher"]
    legacy-repositories  = null
  }
  assert {
    condition     = length(google_service_account_iam_member.github-federated-user-repository-binding) == 1 && google_service_account_iam_member.github-federated-user-repository-binding["example-owner/example-publisher"].member == "principalSet://iam.googleapis.com/projects/123456/locations/global/workloadIdentityPools/example-pool/attribute.repository/example-owner/example-publisher"
    error_message = "The federation member must name the exact repository, not the owner or the whole pool."
  }
  assert {
    condition     = google_service_account_iam_member.github-federated-user-repository-binding["example-owner/example-publisher"].role == "roles/iam.workloadIdentityUser"
    error_message = "The federation member must carry only the workload identity user role."
  }
}
