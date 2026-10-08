locals {
  enabled                = length(var.workspace_backup_folder_paths) > 0
  workspace_backup_paths = nonsensitive(var.workspace_backup_folder_paths)
}

resource "google_service_account" "workspace_backup_writer" {
  count = local.enabled ? 1 : 0

  project      = var.project_id
  account_id   = var.writer_service_account_id
  display_name = "Workspace backup writer"
  description  = "Writes and restores backup data in managed workspace backup folders."
}

resource "google_project_iam_custom_role" "workspace_backup_lock_deleter" {
  count = local.enabled ? 1 : 0

  project         = var.project_id
  role_id         = "workspaceBackupLockDeleter"
  title           = "Workspace Backup Lock Deleter"
  description     = "Deletes only short-lived workspace backup lock objects when bound with a prefix condition."
  permissions     = ["storage.objects.delete"]
  deletion_policy = "PREVENT"
}

resource "google_storage_managed_folder" "workspace_backup" {
  for_each = local.workspace_backup_paths

  bucket          = var.artifact_bucket_name
  name            = each.value
  deletion_policy = "PREVENT"
  force_destroy   = false
}

resource "google_storage_managed_folder_iam_member" "workspace_backup_reader" {
  for_each = google_storage_managed_folder.workspace_backup

  bucket         = each.value.bucket
  managed_folder = each.value.name
  role           = "roles/storage.objectViewer"
  member         = "serviceAccount:${google_service_account.workspace_backup_writer[0].email}"
}

resource "google_storage_managed_folder_iam_member" "workspace_backup_creator" {
  for_each = google_storage_managed_folder.workspace_backup

  bucket         = each.value.bucket
  managed_folder = each.value.name
  role           = "roles/storage.objectCreator"
  member         = "serviceAccount:${google_service_account.workspace_backup_writer[0].email}"
}

resource "google_storage_bucket_iam_member" "workspace_backup_lock_deleter" {
  for_each = google_storage_managed_folder.workspace_backup

  bucket = var.artifact_bucket_name
  role   = google_project_iam_custom_role.workspace_backup_lock_deleter[0].name
  member = "serviceAccount:${google_service_account.workspace_backup_writer[0].email}"

  condition {
    title       = "workspace_backup_lock_delete_${each.key}"
    description = "Restricts object deletion to the Restic lock prefix for one workspace backup folder."
    expression  = "resource.type == \"storage.googleapis.com/Object\" && resource.name.startsWith(\"projects/_/buckets/${var.artifact_bucket_name}/objects/${each.value.name}locks/\")"
  }
}
