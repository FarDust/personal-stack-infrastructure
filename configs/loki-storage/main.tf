# Prefix-scoped Loki identity; as decided in docs/adr/loki_gcs_prefix_identity_adr.md
locals {
  enabled = var.loki_storage_folder_path != ""
}

resource "google_service_account" "loki" {
  count = local.enabled ? 1 : 0

  project      = var.project_id
  account_id   = var.loki_service_account_id
  display_name = "Loki cluster storage"
  description  = "Stores Loki chunks and TSDB index under one managed folder of the shared artifact bucket."
}

resource "google_storage_managed_folder" "loki" {
  count = local.enabled ? 1 : 0

  bucket          = var.artifact_bucket_name
  name            = var.loki_storage_folder_path
  deletion_policy = "PREVENT"
  force_destroy   = false
}

# Managed-folder IAM is the enforced prefix boundary: the role applies only to objects whose
# names start with the folder path, including listing with that prefix.
resource "google_storage_managed_folder_iam_member" "loki_object_admin" {
  count = local.enabled ? 1 : 0

  bucket         = google_storage_managed_folder.loki[0].bucket
  managed_folder = google_storage_managed_folder.loki[0].name
  role           = "roles/storage.objectAdmin"
  member         = "serviceAccount:${google_service_account.loki[0].email}"
}
