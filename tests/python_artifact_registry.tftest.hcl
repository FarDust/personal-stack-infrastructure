mock_provider "google" {}

variables {
  project_id = "example-project"
  cluster_artifact_registry_writers = {
    publisher = "serviceAccount:publisher@example-project.iam.gserviceaccount.com"
  }
  cluster_artifact_registry_readers = {
    cluster = "serviceAccount:cluster@example-project.iam.gserviceaccount.com"
  }
  cluster_artifact_registry_location      = "southamerica-west1"
  cluster_artifact_registry_repository_id = "python-internal"
}

run "python_repository_grants_are_additive_and_repository_scoped" {
  command = plan
  module {
    source = "./configs/artifact-registry"
  }

  assert {
    condition     = data.google_artifact_registry_repository.cluster_internal_images.repository_id == "python-internal" && data.google_artifact_registry_repository.cluster_internal_images.location == "southamerica-west1"
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
