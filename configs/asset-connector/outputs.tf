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

output "tailscale_authkey_secret" {
  description = "Secret Manager secret that receives the Tailscale auth key out of band."
  value       = google_secret_manager_secret.tailscale_authkey.secret_id
  sensitive   = true
}
