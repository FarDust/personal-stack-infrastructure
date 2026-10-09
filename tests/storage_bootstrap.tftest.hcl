mock_provider "google" {}

variables {
  project_id           = "example-project"
  artifact_bucket_name = "example-private-artifacts"
  terraform_executor   = "serviceAccount:terraform@example-project.iam.gserviceaccount.com"
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
    condition     = google_artifact_registry_repository.cluster_internal_images.format == "DOCKER" && google_artifact_registry_repository.cluster_internal_images.location == "southamerica-west1" && google_artifact_registry_repository.cluster_internal_images.repository_id == "cluster-internal-images" && google_artifact_registry_repository.cluster_internal_images.deletion_policy == "PREVENT"
    error_message = "Bootstrap must own the protected private Docker repository in the configured Santiago location."
  }
  assert {
    condition     = toset(google_project_iam_custom_role.artifact_registry_repository_iam_manager.permissions) == toset(["artifactregistry.repositories.get", "artifactregistry.repositories.getIamPolicy", "artifactregistry.repositories.setIamPolicy"])
    error_message = "The executor's custom Artifact Registry role must contain only repository lookup and IAM-policy permissions."
  }
  assert {
    condition     = google_artifact_registry_repository_iam_member.terraform_executor_manager.project == "example-project" && google_artifact_registry_repository_iam_member.terraform_executor_manager.location == "southamerica-west1" && google_artifact_registry_repository_iam_member.terraform_executor_manager.repository == google_artifact_registry_repository.cluster_internal_images.name && google_artifact_registry_repository_iam_member.terraform_executor_manager.role == google_project_iam_custom_role.artifact_registry_repository_iam_manager.name && nonsensitive(google_artifact_registry_repository_iam_member.terraform_executor_manager.member) == "serviceAccount:terraform@example-project.iam.gserviceaccount.com" && issensitive(google_artifact_registry_repository_iam_member.terraform_executor_manager.member)
    error_message = "The executor's repository IAM manager role must be an additive grant scoped to the designated repository."
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
