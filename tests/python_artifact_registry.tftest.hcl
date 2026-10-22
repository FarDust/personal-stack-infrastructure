mock_provider "google" {}

variables {
  project_id = "example-project"
  cluster_artifact_registry_writers = {
    publisher = "serviceAccount:publisher@example-project.iam.gserviceaccount.com"
  }
  cluster_artifact_registry_readers = {
    cluster = "serviceAccount:cluster@example-project.iam.gserviceaccount.com"
  }
  cluster_artifact_registry_location      = "example-region1"
  cluster_artifact_registry_repository_id = "example-python-repo"
}

run "python_repository_grants_are_additive_and_repository_scoped" {
  command = plan
  module {
    source = "./configs/artifact-registry"
  }

  assert {
    condition     = data.google_artifact_registry_repository.cluster_internal_images.repository_id == "example-python-repo" && data.google_artifact_registry_repository.cluster_internal_images.location == "example-region1"
    error_message = "The Python module instance must read the exact bootstrap-owned Python repository."
  }
  assert {
    condition     = google_artifact_registry_repository_iam_member.cluster_internal_image_writer["publisher"].role == "roles/artifactregistry.writer" && google_artifact_registry_repository_iam_member.cluster_internal_image_reader["cluster"].role == "roles/artifactregistry.reader"
    error_message = "Publisher gets writer and cluster consumers get reader, at the repository only."
  }
}

run "python_repository_rejects_public_reader" {
  command = plan
  module {
    source = "./configs/artifact-registry"
  }
  variables {
    cluster_artifact_registry_readers = { public = "allUsers" }
  }
  expect_failures = [var.cluster_artifact_registry_readers]
}

run "python_repository_supports_multiple_readers_without_writer_rights" {
  command = plan
  module {
    source = "./configs/artifact-registry"
  }
  variables {
    cluster_artifact_registry_readers = {
      owner   = "user:owner@example.com"
      cluster = "serviceAccount:cluster@example-project.iam.gserviceaccount.com"
    }
  }

  assert {
    condition     = length(google_artifact_registry_repository_iam_member.cluster_internal_image_reader) == 2 && alltrue([for m in values(google_artifact_registry_repository_iam_member.cluster_internal_image_reader) : m.role == "roles/artifactregistry.reader"])
    error_message = "Each reader alias gets exactly one repository-scoped reader member and no other role."
  }
  assert {
    condition     = length(google_artifact_registry_repository_iam_member.cluster_internal_image_writer) == 1
    error_message = "Adding readers must not add writers."
  }
}
