locals {
  trust_profile               = "image-publisher-${var.repository_id}"
  attribute_condition         = <<-EOT
    assertion.repository_id == ${jsonencode(var.repository_id)} &&
    assertion.repository == ${jsonencode(var.repository)} &&
    assertion.event_name == "push" &&
    assertion.workflow_ref == ${jsonencode("${var.repository}/${var.workflow_path}@")} + assertion.ref &&
    assertion.job_workflow_ref == ${jsonencode("${var.repository}/${var.trusted_workflow_path}@refs/heads/main")} &&
    (assertion.ref == "refs/heads/main" || assertion.ref.matches("^refs/tags/v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))
  EOT
  workload_identity_pool_name = "projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/github-${var.workload_identity_pool_id}"
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_iam_workload_identity_pool_provider" "github_image_publisher" {
  project                            = var.project_id
  workload_identity_pool_id          = "github-${var.workload_identity_pool_id}"
  workload_identity_pool_provider_id = "github-${var.workload_identity_provider_id}"
  display_name                       = "GitHub image publisher"
  description                        = "GitHub OIDC provider for reviewed image publication"
  attribute_condition                = local.attribute_condition

  attribute_mapping = {
    "attribute.trust_profile" = jsonencode(local.trust_profile)
    "google.subject"          = jsonencode("image-publisher:${var.repository_id}")
  }

  oidc {
    allowed_audiences = []
    issuer_uri        = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_image_publisher" {
  service_account_id = var.service_account_id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.workload_identity_pool_name}/attribute.trust_profile/${local.trust_profile}"

  depends_on = [google_iam_workload_identity_pool_provider.github_image_publisher]
}
