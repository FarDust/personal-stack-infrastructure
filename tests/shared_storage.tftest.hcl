mock_provider "google" {}

variables {
  project_id               = "example-project"
  artifact_bucket_name     = "example-private-artifacts"
  artifact_bucket_location = "us-central1"
  artifact_bucket_writers = {
    agent   = "user:operator@example.com"
    cluster = "serviceAccount:storage@example-project.iam.gserviceaccount.com"
  }
}

run "shared_storage_and_private_aliases" {
  command = plan
  module {
    source = "./configs/storage"
  }
  assert {
    condition     = google_storage_bucket.shared_artifacts.public_access_prevention == "enforced" && google_storage_bucket.shared_artifacts.uniform_bucket_level_access
    error_message = "The shared bucket must remain private with uniform access."
  }
  assert {
    condition     = length(google_storage_bucket_iam_member.artifact_writer) == 2 && google_storage_bucket_iam_member.artifact_writer["cluster"].role == "roles/storage.objectUser"
    error_message = "Approved aliases must produce additive bucket-scoped object-user grants."
  }
  assert {
    condition     = nonsensitive(output.dvc_base_url) == "gs://example-private-artifacts/dvc" && issensitive(output.dvc_base_url)
    error_message = "DVC must have a separate sensitive namespace URL."
  }
  assert {
    condition     = google_storage_bucket.shared_artifacts.versioning[0].enabled && !google_storage_bucket.shared_artifacts.force_destroy
    error_message = "Versioning must remain enabled and force destruction disabled."
  }
}

run "reject_public_writer" {
  command = plan
  module {
    source = "./configs/storage"
  }
  variables {
    artifact_bucket_writers = { public = "allUsers" }
  }
  expect_failures = [var.artifact_bucket_writers]
}

run "reject_all_authenticated_users" {
  command = plan
  module {
    source = "./configs/storage"
  }
  variables {
    artifact_bucket_writers = { public = "allAuthenticatedUsers" }
  }
  expect_failures = [var.artifact_bucket_writers]
}
