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
