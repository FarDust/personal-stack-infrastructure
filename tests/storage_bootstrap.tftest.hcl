mock_provider "google" {}

variables {
  project_id           = "example-project"
  artifact_bucket_name = "example-private-artifacts"
  terraform_executor   = "serviceAccount:terraform@example-project.iam.gserviceaccount.com"
}

run "creation_only_and_bucket_scoped_management" {
  command = plan
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
