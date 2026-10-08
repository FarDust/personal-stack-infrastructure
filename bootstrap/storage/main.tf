terraform {
  required_version = ">= 1.16.3, < 2.0.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.46.1"
    }
  }
}

provider "google" {
  project = var.project_id
}

resource "google_project_iam_custom_role" "bucket_creator" {
  project     = var.project_id
  role_id     = "artifactBucketCreator"
  title       = "Artifact bucket creator"
  description = "Create new buckets without access to existing bucket data."
  permissions = ["storage.buckets.create"]
  stage       = "GA"
}

resource "google_project_iam_member" "bucket_creator" {
  project = var.project_id
  role    = google_project_iam_custom_role.bucket_creator.name
  member  = var.terraform_executor
}

resource "google_project_iam_member" "bucket_manager" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = var.terraform_executor

  condition {
    title       = "artifact_bucket_only"
    description = "Manage only the designated artifact bucket."
    expression  = "resource.name == ${jsonencode("projects/_/buckets/${var.artifact_bucket_name}")}"
  }
}

resource "google_artifact_registry_repository" "cluster_internal_images" {
  project         = var.project_id
  location        = var.cluster_artifact_registry_location
  repository_id   = var.cluster_artifact_registry_repository_id
  description     = "Private Docker images for internal cluster services"
  format          = "DOCKER"
  deletion_policy = "PREVENT"
}

resource "google_project_iam_custom_role" "artifact_registry_repository_iam_manager" {
  project     = var.project_id
  role_id     = "artifactRegistryRepositoryIamManager"
  title       = "Artifact Registry repository IAM manager"
  description = "Read the designated repository and maintain its additive IAM policy."
  permissions = [
    "artifactregistry.repositories.get",
    "artifactregistry.repositories.getIamPolicy",
    "artifactregistry.repositories.setIamPolicy",
  ]
  stage = "GA"
}

resource "google_artifact_registry_repository_iam_member" "terraform_executor_manager" {
  project    = google_artifact_registry_repository.cluster_internal_images.project
  location   = google_artifact_registry_repository.cluster_internal_images.location
  repository = google_artifact_registry_repository.cluster_internal_images.name
  role       = google_project_iam_custom_role.artifact_registry_repository_iam_manager.name
  member     = var.terraform_executor
}
