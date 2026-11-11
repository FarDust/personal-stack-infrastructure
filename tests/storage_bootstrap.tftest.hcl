mock_provider "google" {}

variables {
  project_id           = "example-project"
  artifact_bucket_name = "example-private-artifacts"
  terraform_executor   = "serviceAccount:terraform@example-project.iam.gserviceaccount.com"

  cluster_artifact_registry_location      = "example-region1"
  cluster_artifact_registry_repository_id = "example-image-repo"
  python_artifact_registry_location       = "example-region1"
  python_artifact_registry_repository_id  = "example-python-repo"
}

run "creation_only_and_bucket_scoped_management" {
  command = apply
  module {
    source = "./bootstrap/storage"
  }
  assert {
    condition     = toset(google_project_iam_custom_role.bucket_creator.permissions) == toset(["storage.buckets.create"])
    error_message = "Project-level creation permissions must not include existing-data access."
  }
  assert {
    condition     = nonsensitive(google_project_iam_member.bucket_manager.condition[0].expression) == "resource.name == \"projects/_/buckets/example-private-artifacts\""
    error_message = "Storage administration must be restricted to the exact target bucket."
  }
  assert {
    condition     = issensitive(google_project_iam_member.bucket_manager.member)
    error_message = "The runtime principal must remain sensitive."
  }
  assert {
    condition     = google_artifact_registry_repository.cluster_internal_images.format == "DOCKER" && google_artifact_registry_repository.cluster_internal_images.location == "example-region1" && google_artifact_registry_repository.cluster_internal_images.repository_id == "example-image-repo" && google_artifact_registry_repository.cluster_internal_images.deletion_policy == "PREVENT"
    error_message = "Bootstrap must own the protected private Docker repository in the configured location."
  }
  assert {
    condition     = toset(google_project_iam_custom_role.artifact_registry_repository_iam_manager.permissions) == toset(["artifactregistry.repositories.get", "artifactregistry.repositories.getIamPolicy", "artifactregistry.repositories.setIamPolicy"])
    error_message = "The executor's custom Artifact Registry role must contain only repository lookup and IAM-policy permissions."
  }
  assert {
    condition     = google_artifact_registry_repository_iam_member.terraform_executor_manager.project == "example-project" && google_artifact_registry_repository_iam_member.terraform_executor_manager.location == "example-region1" && google_artifact_registry_repository_iam_member.terraform_executor_manager.repository == google_artifact_registry_repository.cluster_internal_images.name && google_artifact_registry_repository_iam_member.terraform_executor_manager.role == google_project_iam_custom_role.artifact_registry_repository_iam_manager.name && nonsensitive(google_artifact_registry_repository_iam_member.terraform_executor_manager.member) == "serviceAccount:terraform@example-project.iam.gserviceaccount.com" && issensitive(google_artifact_registry_repository_iam_member.terraform_executor_manager.member)
    error_message = "The executor's repository IAM manager role must be an additive grant scoped to the designated repository."
  }
}

run "private_python_repository_is_protected_and_executor_scoped" {
  command = apply
  module {
    source = "./bootstrap/storage"
  }
  assert {
    condition     = google_artifact_registry_repository.python_internal.format == "PYTHON" && google_artifact_registry_repository.python_internal.location == "example-region1" && google_artifact_registry_repository.python_internal.repository_id == "example-python-repo" && google_artifact_registry_repository.python_internal.deletion_policy == "PREVENT"
    error_message = "Bootstrap must own the protected private Python repository in the configured location."
  }
  assert {
    condition     = google_artifact_registry_repository_iam_member.terraform_executor_python_manager.repository == google_artifact_registry_repository.python_internal.name && google_artifact_registry_repository_iam_member.terraform_executor_python_manager.role == google_project_iam_custom_role.artifact_registry_repository_iam_manager.name && issensitive(google_artifact_registry_repository_iam_member.terraform_executor_python_manager.member)
    error_message = "The executor receives only the repository IAM manager role, scoped to the Python repository."
  }
}

run "reject_public_bootstrap_principal" {
  command = plan
  module {
    source = "./bootstrap/storage"
  }
  variables {
    terraform_executor = "allUsers"
  }
  expect_failures = [var.terraform_executor]
}

run "asset_connector_roles_are_minimal_and_conditioned" {
  command = apply
  module {
    source = "./bootstrap/storage"
  }
  variables {
    asset_connector_bucket_name = "example-assets"
  }
  assert {
    condition     = nonsensitive(google_project_iam_member.asset_connector_bucket_manager[0].condition[0].expression) == "resource.name == \"projects/_/buckets/example-assets\" || resource.name.startsWith(\"projects/_/buckets/example-assets/objects/\")"
    error_message = "Storage administration for the connector must be limited to its exact bucket."
  }
  assert {
    condition     = nonsensitive(google_service_account_iam_member.asset_connector_identity_user[0].service_account_id) == "projects/example-project/serviceAccounts/asset-connector@example-project.iam.gserviceaccount.com" && google_service_account_iam_member.asset_connector_identity_user[0].role == "roles/iam.serviceAccountUser"
    error_message = "Acting as a service account must be bound on the connector identity only."
  }
  assert {
    condition     = alltrue([for p in google_project_iam_custom_role.asset_connector_network_manager[0].permissions : can(regex("^compute\\.(networks|subnetworks|firewalls|globalOperations|regionOperations|zoneOperations)\\.", p)) && !can(regex("[Ii]am[Pp]olicy", p)) && !can(regex("instances", p))])
    error_message = "The custom network role must not hold instance or IAM administration."
  }
  assert {
    condition     = alltrue([for r in [google_project_iam_member.asset_connector_instance_admin[0].role, google_project_iam_member.asset_connector_alert_policy_editor[0].role] : !contains(["roles/owner", "roles/editor", "roles/serviceusage.serviceUsageAdmin"], r)])
    error_message = "The executor must not receive broad or API-enabling roles."
  }
}

run "connector_roles_absent_without_bucket" {
  command = apply
  module {
    source = "./bootstrap/storage"
  }
  assert {
    condition     = length(google_project_iam_member.asset_connector_bucket_manager) == 0 && length(google_project_iam_member.asset_connector_instance_admin) == 0
    error_message = "Without a connector bucket no extra executor roles may exist."
  }
}
