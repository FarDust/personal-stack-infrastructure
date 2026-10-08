output "writer_service_account_email" {
  description = "The managed backup-writer service account principal."
  value       = try(google_service_account.workspace_backup_writer[0].email, null)
  sensitive   = true
}

output "managed_folder_paths" {
  description = "The managed workspace backup folder paths."
  value       = values(google_storage_managed_folder.workspace_backup)[*].name
  sensitive   = true
}
