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
  artifact_bucket_location = "SOUTHAMERICA-WEST1"
  artifact_bucket_writers  = {}
}

run "accept_reviewed_region" {
  command = plan
  assert {
    condition     = nonsensitive(output.dvc_base_url) == "gs://example-private-artifacts/dvc"
    error_message = "The root module must expose the shared DVC namespace."
  }
}

run "reject_uncosted_region" {
  command = plan
  variables {
    artifact_bucket_location = "us-central1"
  }
  expect_failures = [var.artifact_bucket_location]
}
