output "signer_service_account_email" {
  description = "Dedicated identity to authorize as a Developer in the Wallet issuer console."
  value       = one(google_service_account.wallet_signer[*].email)
  sensitive   = true
}
