mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789"
    }
  }
}

variables {
  project_id                    = "example-project"
  workload_identity_pool_id     = "example-pool"
  workload_identity_provider_id = "example-publisher"
  service_account_id            = "projects/example-project/serviceAccounts/publisher@example-project.iam.gserviceaccount.com"
  repository                    = "example-owner/example-publisher"
  repository_id                 = "1412600981"
  workflow_path                 = ".github/workflows/image.yml"
  trusted_workflow_path         = ".github/workflows/publish-image.yml"
}

run "publisher_provider_uses_exact_claim_contract" {
  command = plan
  module {
    source = "./configs/github-image-publisher"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github_image_publisher.workload_identity_pool_id == "github-example-pool" && google_iam_workload_identity_pool_provider.github_image_publisher.workload_identity_pool_provider_id == "github-example-publisher"
    error_message = "The publisher provider must use its own stable provider ID inside the existing GitHub pool."
  }

  assert {
    condition     = nonsensitive(google_iam_workload_identity_pool_provider.github_image_publisher.attribute_condition) == <<-EOT
      assertion.repository_id == "1412600981" &&
      assertion.repository == "example-owner/example-publisher" &&
      assertion.event_name == "push" &&
      assertion.workflow_ref == "example-owner/example-publisher/.github/workflows/image.yml@" + assertion.ref &&
      assertion.job_workflow_ref == "example-owner/example-publisher/.github/workflows/publish-image.yml@refs/heads/main" &&
      (assertion.ref == "refs/heads/main" || assertion.ref.matches("^refs/tags/v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))
    EOT
    error_message = "The publisher provider must require the immutable repository, push event, exact caller workflow, trusted reusable workflow on main, and an allowed publication ref."
  }

  assert {
    condition = google_iam_workload_identity_pool_provider.github_image_publisher.attribute_mapping == tomap({
      "attribute.trust_profile" = "\"image-publisher-1412600981\""
      "google.subject"          = "\"image-publisher:1412600981\""
    })
    error_message = "The publisher provider must expose a repository-specific trust profile and a bounded subject."
  }

  assert {
    condition     = google_service_account_iam_member.github_image_publisher.role == "roles/iam.workloadIdentityUser" && google_service_account_iam_member.github_image_publisher.member == "principalSet://iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/github-example-pool/attribute.trust_profile/image-publisher-1412600981"
    error_message = "Only identities admitted by the publisher provider's exclusive trust profile may impersonate the publisher account."
  }

  assert {
    condition     = issensitive(output.provider_name) && issensitive(output.attribute_condition)
    error_message = "The deployment-specific provider name and condition must remain sensitive outputs."
  }
}

run "reject_non_workflow_path" {
  command = plan
  module {
    source = "./configs/github-image-publisher"
  }
  variables {
    workflow_path = "scripts/publish.sh"
  }
  expect_failures = [var.workflow_path]
}

run "reject_non_reusable_workflow_path" {
  command = plan
  module {
    source = "./configs/github-image-publisher"
  }
  variables {
    trusted_workflow_path = "scripts/publish.sh"
  }
  expect_failures = [var.trusted_workflow_path]
}

run "reject_non_numeric_repository_id" {
  command = plan
  module {
    source = "./configs/github-image-publisher"
  }
  variables {
    repository_id = "repository-id"
  }
  expect_failures = [var.repository_id]
}

run "reject_oversized_repository_id" {
  command = plan
  module {
    source = "./configs/github-image-publisher"
  }
  variables {
    repository_id = "123456789012345678901"
  }
  expect_failures = [var.repository_id]
}

run "reject_invalid_provider_id" {
  command = plan
  module {
    source = "./configs/github-image-publisher"
  }
  variables {
    workload_identity_provider_id = "bad_provider"
  }
  expect_failures = [var.workload_identity_provider_id]
}
