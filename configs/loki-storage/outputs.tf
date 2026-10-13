output "service_account_email" {
  description = "The Loki object-storage service account principal."
  value       = try(google_service_account.loki[0].email, null)
  sensitive   = true
}

output "managed_folder_path" {
  description = "The managed folder that scopes the Loki identity."
  value       = try(google_storage_managed_folder.loki[0].name, null)
  sensitive   = true
}
