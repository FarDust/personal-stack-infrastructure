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
    publisher = {
      name                 = "example-publisher-fa"
      display_name         = "Example Publisher"
      description          = "validates strict publisher composition"
      allowed-repositories = ["example-owner/example-publisher"]
    }
  }
  github_image_publisher = {
    federated_user_key             = "publisher"
    workload_identity_provider_id  = "example-publisher"
    repository                     = "example-owner/example-publisher"
    repository_id                  = "1412600981"
    workflow_path                  = ".github/workflows/image.yml"
    trusted_workflow_path          = ".github/workflows/publish-image.yml"
    retain_general_provider_access = true
  }
  artifact_bucket_name     = "example-private-artifacts"
  artifact_bucket_location = "US-CENTRAL1"
  artifact_bucket_writers  = {}
  cluster_artifact_registry_writers = {
    publisher = "serviceAccount:example-publisher-fa@example-project.iam.gserviceaccount.com"
  }
  cluster_artifact_registry_readers = {
    cluster = "serviceAccount:cluster@example-project.iam.gserviceaccount.com"
  }
}

run "accept_valid_region" {
  command = plan
  assert {
    condition     = nonsensitive(output.dvc_base_url) == "gs://example-private-artifacts/dvc"
    error_message = "The root module must expose the shared DVC namespace."
  }
  assert {
    condition     = nonsensitive(module.github-identity-federation.federated-github-users["secrets"].iam_binding_count) == 0 && nonsensitive(module.github-identity-federation.federated-github-users["secrets"].iam_member_count) == 1
    error_message = "The root module must use the shared module's modern IAM member default."
  }
  assert {
    condition     = nonsensitive(module.github-identity-federation.federated-github-users["secrets"].federated-user.account_id) == "example-federated-user"
    error_message = "Switching IAM ownership must preserve the existing compatible account name."
  }
  assert {
    condition     = nonsensitive(module.github-identity-federation.owner_condition) == "attribute.repository_owner == \"example-owner\"\n" && issensitive(module.github-identity-federation.owner_condition)
    error_message = "The root module must preserve the exact sensitive owner condition."
  }
  assert {
    condition     = nonsensitive(output.cluster_artifact_registry_repository_url) == "southamerica-west1-docker.pkg.dev/example-project/cluster-internal-images" && issensitive(output.cluster_artifact_registry_repository_url)
    error_message = "The root module must expose the private cluster image repository URL as a sensitive output."
  }
}

run "reject_invalid_region" {
  command = plan
  variables {
    artifact_bucket_location = "not-a-region"
  }
  expect_failures = [var.artifact_bucket_location]
}

run "modern_multiple_repositories_and_account_name" {
  command = plan
  variables {
    federated_github_users = {
      secrets = {
        name                 = "example-fa"
        display_name         = "Example"
        description          = "validates modern composition"
        allowed-repositories = ["example-owner/first", "example-owner/second"]
      }
      publisher = {
        name                 = "example-publisher-fa"
        display_name         = "Example Publisher"
        description          = "validates strict publisher composition"
        allowed-repositories = ["example-owner/example-publisher"]
      }
    }
  }
  assert {
    condition     = nonsensitive(module.github-identity-federation.federated-github-users["secrets"].iam_binding_count) == 0 && nonsensitive(module.github-identity-federation.federated-github-users["secrets"].iam_member_count) == 2
    error_message = "Each repository must use its own additive IAM member, without authoritative bindings."
  }
  assert {
    condition     = nonsensitive(module.github-identity-federation.federated-github-users["secrets"].federated-user.account_id) == "example-fa"
    error_message = "Modern account names must not receive the legacy suffix."
  }
}
