output "provider_name" {
  description = "Full publisher-specific workload identity provider name for GitHub Actions."
  value       = google_iam_workload_identity_pool_provider.github_image_publisher.name
  sensitive   = true
}

output "attribute_condition" {
  description = "Exact publisher admission condition for private verification."
  value       = google_iam_workload_identity_pool_provider.github_image_publisher.attribute_condition
  sensitive   = true
}

output "iam_member" {
  description = "Publisher-specific workload identity principal set."
  value       = google_service_account_iam_member.github_image_publisher.member
  sensitive   = true
}
