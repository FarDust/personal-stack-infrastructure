mock_provider "google" {}

variables {
  github_repository_owner = "example-owner"
  project_id              = "example-project"
  identity_pool_id        = "example-pool"
  identity_provider_id    = "example-provider"
  federated_github_users = {
    secrets = {
      name                 = "example"
      display_name         = "Example"
      description          = "validates root composition"
      allowed-repositories = ["example-owner/example-repository"]
    }
  }
  artifact_bucket_name     = "example-private-artifacts"
  artifact_bucket_location = "US-CENTRAL1"
  artifact_bucket_writers  = {}
}

run "accept_valid_region" {
  command = plan
  assert {
    condition     = nonsensitive(output.dvc_base_url) == "gs://example-private-artifacts/dvc"
    error_message = "The root module must expose the shared DVC namespace."
  }
  assert {
    condition     = nonsensitive(module.github-identity-federation.federated-github-users["secrets"].iam_binding_count) == 1 && nonsensitive(module.github-identity-federation.federated-github-users["secrets"].iam_member_count) == 0
    error_message = "The root module must select the legacy IAM binding layout."
  }
  assert {
    condition     = nonsensitive(module.github-identity-federation.federated-github-users["secrets"].federated-user.account_id) == "example-federated-user"
    error_message = "The root module must preserve the legacy service-account name."
  }
  assert {
    condition     = nonsensitive(module.github-identity-federation.owner_condition) == "attribute.repository_owner == \"example-owner\"\n" && issensitive(module.github-identity-federation.owner_condition)
    error_message = "The root module must preserve the exact sensitive owner condition."
  }
}

run "reject_invalid_region" {
  command = plan
  variables {
    artifact_bucket_location = "not-a-region"
  }
  expect_failures = [var.artifact_bucket_location]
}
