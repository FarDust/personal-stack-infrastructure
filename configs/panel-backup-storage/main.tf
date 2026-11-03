resource "google_service_account" "panel_backup" {
  count        = var.enabled ? 1 : 0
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "Panel backup writer"
  description  = "Writes and restores backups in the configured managed folder."
}

resource "google_project_iam_custom_role" "panel_backup" {
  count       = var.enabled ? 1 : 0
  project     = var.project_id
  role_id     = "panelBackupObjects"
  title       = "Panel backup objects"
  description = "Object and multipart operations for panel backups."
  permissions = [
    "storage.objects.create",
    "storage.objects.get",
    "storage.objects.delete",
    "storage.objects.list",
    "storage.multipartUploads.create",
    "storage.multipartUploads.abort",
    "storage.multipartUploads.listParts",
  ]
  deletion_policy = "PREVENT"
}

resource "google_storage_managed_folder" "panel_backup" {
  count           = var.enabled ? 1 : 0
  bucket          = var.bucket_name
  name            = var.folder_path
  deletion_policy = "PREVENT"
  force_destroy   = false

  lifecycle {
    precondition {
      condition     = var.folder_path != "" && length(var.bucket_name) >= 3
      error_message = "An enabled panel backup identity requires a bucket and exact server folder."
    }
  }
}

resource "google_storage_managed_folder_iam_member" "panel_backup" {
  count          = var.enabled ? 1 : 0
  bucket         = google_storage_managed_folder.panel_backup[0].bucket
  managed_folder = google_storage_managed_folder.panel_backup[0].name
  role           = google_project_iam_custom_role.panel_backup[0].name
  member         = "serviceAccount:${google_service_account.panel_backup[0].email}"
}
