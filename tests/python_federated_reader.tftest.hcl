mock_provider "google" {}

override_resource {
  override_during = plan
  target          = module.github-identity-federation.module.federated-github-user["package_reader"].google_service_account.federated-user
  values = {
    email = "example-reader-fa@example-project.iam.gserviceaccount.com"
    name  = "projects/example-project/serviceAccounts/example-reader-fa@example-project.iam.gserviceaccount.com"
  }
}

variables {
  github_repository_owner                 = "example-owner"
  project_id                              = "example-project"
  identity_pool_id                        = "example-pool"
  identity_provider_id                    = "example-provider"
  artifact_bucket_name                    = "example-private-artifacts"
  artifact_bucket_location                = "example-region1"
  artifact_bucket_writers                 = {}
  cluster_artifact_registry_location      = "example-region1"
  cluster_artifact_registry_repository_id = "example-images"
  python_artifact_registry_location       = "example-region1"
  python_artifact_registry_repository_id  = "example-python"
  loki_storage_folder_path                = ""
  federated_github_users = {
    secrets = {
      name                 = "secrets"
      display_name         = "Existing identity"
      description          = "Existing identity"
      allowed-repositories = ["example-owner/example-secrets"]
    }
    package_reader = {
      name                 = "example-reader-fa"
      display_name         = "Package reader"
      description          = "Reads private packages"
      allowed-repositories = ["example-owner/example-consumer"]
    }
  }
  python_artifact_registry_federated_readers = ["package_reader"]
}

run "dedicated_reader_is_connected_without_writer_grant" {
  command = plan
  assert {
    condition     = length(google_artifact_registry_repository_iam_member.python_federated_reader) == 1 && google_artifact_registry_repository_iam_member.python_federated_reader["package_reader"].role == "roles/artifactregistry.reader" && google_artifact_registry_repository_iam_member.python_federated_reader["package_reader"].repository == var.python_artifact_registry_repository_id
    error_message = "The selected federation account must become a Python repository reader."
  }
}

run "disabled_by_default" {
  command = plan
  variables {
    python_artifact_registry_federated_readers = []
  }
  assert {
    condition     = length(google_artifact_registry_repository_iam_member.python_federated_reader) == 0
    error_message = "An empty selection must preserve existing deployments."
  }
}

run "reject_unknown_account" {
  command = plan
  variables {
    python_artifact_registry_federated_readers = ["missing"]
  }
  expect_failures = [var.python_artifact_registry_federated_readers]
}

run "reject_secrets_identity" {
  command = plan
  variables {
    python_artifact_registry_federated_readers = ["secrets"]
  }
  expect_failures = [var.python_artifact_registry_federated_readers]
}

run "reject_existing_reader_under_different_alias" {
  command = plan
  variables {
    python_artifact_registry_readers = { legacy_reader = "serviceAccount:example-reader-fa@example-project.iam.gserviceaccount.com" }
  }
  expect_failures = [google_artifact_registry_repository_iam_member.python_federated_reader]
}

run "reject_python_writer_under_different_alias" {
  command = plan
  variables {
    python_artifact_registry_writers = { publisher = "serviceAccount:example-reader-fa@example-project.iam.gserviceaccount.com" }
  }
  expect_failures = [google_artifact_registry_repository_iam_member.python_federated_reader]
}

run "reject_image_writer_under_different_alias" {
  command = plan
  variables {
    cluster_artifact_registry_writers = { image_publisher = "serviceAccount:example-reader-fa@example-project.iam.gserviceaccount.com" }
  }
  expect_failures = [google_artifact_registry_repository_iam_member.python_federated_reader]
}

run "reject_bucket_writer_under_different_alias" {
  command = plan
  variables {
    artifact_bucket_writers = { uploader = "serviceAccount:example-reader-fa@example-project.iam.gserviceaccount.com" }
  }
  expect_failures = [google_artifact_registry_repository_iam_member.python_federated_reader]
}

run "reject_null_alias" {
  command = plan
  variables {
    python_artifact_registry_federated_readers = [null]
  }
  expect_failures = [var.python_artifact_registry_federated_readers]
}

run "reject_empty_alias" {
  command = plan
  variables {
    python_artifact_registry_federated_readers = [""]
  }
  expect_failures = [var.python_artifact_registry_federated_readers]
}

run "reject_wrong_owner" {
  command = plan
  variables {
    github_repository_owner = "different-owner"
  }
  expect_failures = [var.python_artifact_registry_federated_readers]
}

run "reject_multiple_repositories" {
  command = plan
  variables {
    federated_github_users = {
      secrets = {
        name                 = "secrets"
        display_name         = "Existing"
        description          = "Existing"
        allowed-repositories = ["example-owner/example-secrets"]
      }
      package_reader = {
        name                 = "example-reader-fa"
        display_name         = "Reader"
        description          = "Reader"
        allowed-repositories = ["example-owner/example-consumer", "example-owner/other-consumer"]
      }
    }
  }
  expect_failures = [var.python_artifact_registry_federated_readers]
}

run "independent_operator_grants_remain_valid" {
  command = plan
  variables {
    python_artifact_registry_writers  = { operator = "user:operator@example.com" }
    python_artifact_registry_readers  = { operator = "user:operator@example.com" }
    cluster_artifact_registry_writers = { publisher = "serviceAccount:other-publisher@example-project.iam.gserviceaccount.com" }
    artifact_bucket_writers           = { uploader = "serviceAccount:other-uploader@example-project.iam.gserviceaccount.com" }
  }
  assert {
    condition     = length(google_artifact_registry_repository_iam_member.python_federated_reader) == 1
    error_message = "Independent principals must retain their existing grants."
  }
}
