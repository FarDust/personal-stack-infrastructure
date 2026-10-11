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
    federated_user_key             = "publisher"
    workload_identity_provider_id  = "example-publisher"
    repository                     = "example-owner/example-publisher"
    repository_id                  = "1412600981"
    workflow_path                  = ".github/workflows/image.yml"
    trusted_workflow_path          = ".github/workflows/publish-image.yml"
    retain_general_provider_access = true
  }
  artifact_bucket_name     = "example-private-artifacts"
  artifact_bucket_location = "southamerica-west1"
  artifact_bucket_writers  = {}
  cluster_artifact_registry_writers = {
    publisher = "serviceAccount:example-publisher-fa@example-project.iam.gserviceaccount.com"
  }
}

run "publisher_adds_strict_federation_before_cutover" {
  command = plan

  assert {
    condition     = nonsensitive(module.github-identity-federation.federated-github-users["publisher"].iam_member_count) == 1 && nonsensitive(module.github-identity-federation.federated-github-users["secrets"].iam_member_count) == 1
    error_message = "Phase one must retain the publisher's general-provider member while adding strict federation; unrelated federation must remain unchanged."
  }

  assert {
    condition     = nonsensitive(module.github-identity-federation.federated-github-users["publisher"].federated-user.account_id) == "example-publisher-fa"
    error_message = "Hardening must preserve the applied publisher service-account identity."
  }

  assert {
    condition     = strcontains(nonsensitive(module.github_image_publisher.attribute_condition), "assertion.repository_id == \"1412600981\"") && strcontains(nonsensitive(module.github_image_publisher.attribute_condition), "assertion.workflow_ref == \"example-owner/example-publisher/.github/workflows/image.yml@\" + assertion.ref") && strcontains(nonsensitive(module.github_image_publisher.attribute_condition), "assertion.job_workflow_ref == \"example-owner/example-publisher/.github/workflows/publish-image.yml@refs/heads/main\"")
    error_message = "The root must configure the immutable repository, exact caller workflow, and trusted reusable workflow on main."
  }

  assert {
    condition     = issensitive(output.github_image_publisher_workload_identity_provider) && issensitive(output.federated_github_service_accounts)
    error_message = "Workflow-facing provider and service-account outputs must remain sensitive."
  }
}

run "publisher_removes_general_federation_after_canary" {
  command = plan
  variables {
    github_image_publisher = {
      federated_user_key             = "publisher"
      workload_identity_provider_id  = "example-publisher"
      repository                     = "example-owner/example-publisher"
      repository_id                  = "1412600981"
      workflow_path                  = ".github/workflows/image.yml"
      trusted_workflow_path          = ".github/workflows/publish-image.yml"
      retain_general_provider_access = false
    }
  }

  assert {
    condition     = nonsensitive(module.github-identity-federation.federated-github-users["publisher"].iam_member_count) == 0 && nonsensitive(module.github-identity-federation.federated-github-users["secrets"].iam_member_count) == 1
    error_message = "Phase two must remove only the publisher's general-provider member after the canary authorizes cutover."
  }
}

run "reject_missing_publisher_account" {
  command = plan
  variables {
    github_image_publisher = {
      federated_user_key             = "missing"
      workload_identity_provider_id  = "example-publisher"
      repository                     = "example-owner/example-publisher"
      repository_id                  = "1412600981"
      workflow_path                  = ".github/workflows/image.yml"
      trusted_workflow_path          = ".github/workflows/publish-image.yml"
      retain_general_provider_access = true
    }
  }
  expect_failures = [output.github_image_publisher_workload_identity_provider]
}

run "reject_mismatched_publisher_repository" {
  command = plan
  variables {
    github_image_publisher = {
      federated_user_key             = "publisher"
      workload_identity_provider_id  = "example-publisher"
      repository                     = "example-owner/other-repository"
      repository_id                  = "1412600981"
      workflow_path                  = ".github/workflows/image.yml"
      trusted_workflow_path          = ".github/workflows/publish-image.yml"
      retain_general_provider_access = true
    }
  }
  expect_failures = [output.github_image_publisher_workload_identity_provider]
}

run "reject_general_provider_id_collision" {
  command = plan
  variables {
    identity_provider_id = "example-publisher"
  }
  expect_failures = [output.github_image_publisher_workload_identity_provider]
}

run "reject_publisher_without_registry_writer" {
  command = plan
  variables {
    cluster_artifact_registry_writers = {
      other = "serviceAccount:other@example-project.iam.gserviceaccount.com"
    }
  }
  expect_failures = [output.github_image_publisher_workload_identity_provider]
}
