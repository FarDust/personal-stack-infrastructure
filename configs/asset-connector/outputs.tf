output "bucket_name" {
  description = "The private asset bucket."
  value       = google_storage_bucket.assets.name
  sensitive   = true
}

output "service_account_email" {
  description = "The VM identity; it holds object read on the asset bucket only."
  value       = google_service_account.connector.email
  sensitive   = true
}

output "service_account_unique_id" {
  description = "Numeric id of the VM identity; it is the subject claim of the tailnet federated identity."
  value       = google_service_account.connector.unique_id
  sensitive   = true
}
