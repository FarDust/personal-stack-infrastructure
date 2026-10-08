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
  cluster_artifact_registry_repository_id = "cluster-internal-images"
}

run "private_cluster_image_repository" {
  command = plan
  module {
    source = "./configs/artifact-registry"
  }

  assert {
    condition     = data.google_artifact_registry_repository.cluster_internal_images.project == "example-project" && data.google_artifact_registry_repository.cluster_internal_images.location == "southamerica-west1" && data.google_artifact_registry_repository.cluster_internal_images.repository_id == "cluster-internal-images"
    error_message = "The main configuration must read the exact bootstrap-owned private repository."
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.cluster_internal_image_writer["publisher"].project == data.google_artifact_registry_repository.cluster_internal_images.project && google_artifact_registry_repository_iam_member.cluster_internal_image_writer["publisher"].location == data.google_artifact_registry_repository.cluster_internal_images.location && google_artifact_registry_repository_iam_member.cluster_internal_image_writer["publisher"].repository == data.google_artifact_registry_repository.cluster_internal_images.name
    error_message = "Writer memberships must remain scoped to the bootstrap-owned repository."
  }

  assert {
    condition     = length(google_artifact_registry_repository_iam_member.cluster_internal_image_writer) == 1 && google_artifact_registry_repository_iam_member.cluster_internal_image_writer["publisher"].role == "roles/artifactregistry.writer"
    error_message = "Writer aliases must produce additive repository-scoped writer grants."
  }

  assert {
    condition     = length(google_artifact_registry_repository_iam_member.cluster_internal_image_reader) == 1 && google_artifact_registry_repository_iam_member.cluster_internal_image_reader["cluster"].project == data.google_artifact_registry_repository.cluster_internal_images.project && google_artifact_registry_repository_iam_member.cluster_internal_image_reader["cluster"].location == data.google_artifact_registry_repository.cluster_internal_images.location && google_artifact_registry_repository_iam_member.cluster_internal_image_reader["cluster"].repository == data.google_artifact_registry_repository.cluster_internal_images.name && google_artifact_registry_repository_iam_member.cluster_internal_image_reader["cluster"].role == "roles/artifactregistry.reader"
    error_message = "Reader aliases must produce additive repository-scoped reader grants."
  }
}

run "reject_public_writer" {
  command = plan
  module {
    source = "./configs/artifact-registry"
  }
  variables {
    cluster_artifact_registry_writers = { public = "allUsers" }
  }
  expect_failures = [var.cluster_artifact_registry_writers]
}

run "reject_all_authenticated_reader" {
  command = plan
  module {
    source = "./configs/artifact-registry"
  }
  variables {
    cluster_artifact_registry_readers = { public = "allAuthenticatedUsers" }
  }
  expect_failures = [var.cluster_artifact_registry_readers]
}
