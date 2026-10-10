mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789"
    }
  }
}

variables {
  github_repository_owner = "example-owner"
  project_id              = "example-project"
  identity_pool_id        = "example-pool"
  identity_provider_id    = "example-provider"
  federated_github_users = {
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
  github_image_publisher = {
    federated_user_key            = "publisher"
    workload_identity_provider_id = "example-publisher"
    repository                    = "example-owner/example-publisher"
    repository_id                 = "1412600981"
    workflow_path                 = ".github/workflows/image.yml"
  }
  artifact_bucket_name     = "example-private-artifacts"
  artifact_bucket_location = "southamerica-west1"
  artifact_bucket_writers  = {}
}

run "publisher_uses_only_strict_federation" {
  command = plan

  assert {
    condition     = nonsensitive(module.github-identity-federation.federated-github-users["publisher"].iam_member_count) == 0 && nonsensitive(module.github-identity-federation.federated-github-users["secrets"].iam_member_count) == 1
    error_message = "The publisher must lose the general provider's repository member while unrelated federation remains unchanged."
  }

  assert {
    condition     = nonsensitive(module.github-identity-federation.federated-github-users["publisher"].federated-user.account_id) == "example-publisher-fa"
    error_message = "Hardening must preserve the applied publisher service-account identity."
  }

  assert {
    condition     = strcontains(nonsensitive(module.github_image_publisher.attribute_condition), "assertion.repository_id == \"1412600981\"") && strcontains(nonsensitive(module.github_image_publisher.attribute_condition), "assertion.workflow_ref == \"example-owner/example-publisher/.github/workflows/image.yml@\" + assertion.ref")
    error_message = "The root must configure the publisher-specific provider with the immutable repository and exact workflow."
  }

  assert {
    condition     = issensitive(output.github_image_publisher_workload_identity_provider) && issensitive(output.federated_github_service_accounts)
    error_message = "Workflow-facing provider and service-account outputs must remain sensitive."
  }
}

run "reject_missing_publisher_account" {
  command = plan
  variables {
    github_image_publisher = {
      federated_user_key            = "missing"
      workload_identity_provider_id = "example-publisher"
      repository                    = "example-owner/example-publisher"
      repository_id                 = "1412600981"
      workflow_path                 = ".github/workflows/image.yml"
    }
  }
  expect_failures = [output.github_image_publisher_workload_identity_provider]
}

run "reject_mismatched_publisher_repository" {
  command = plan
  variables {
    github_image_publisher = {
      federated_user_key            = "publisher"
      workload_identity_provider_id = "example-publisher"
      repository                    = "example-owner/other-repository"
      repository_id                 = "1412600981"
      workflow_path                 = ".github/workflows/image.yml"
    }
  }
  expect_failures = [output.github_image_publisher_workload_identity_provider]
}
