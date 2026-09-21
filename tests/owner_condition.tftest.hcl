mock_provider "google" {}

variables {
  github_repository_owner  = "example-owner"
  project-id               = "example-project"
  landing-identity-pool-id = "example-pool"
  identity-provider-id     = "example-provider"
  federated-github-users   = {}
}

run "preserve_owner_condition" {
  command = plan
  module {
    source = "./modules/github-identity-federation"
  }
  assert {
    condition     = nonsensitive(google_iam_workload_identity_pool_provider.identity-pool-provider.attribute_condition) == "attribute.repository_owner == \"example-owner\"\n"
    error_message = "The owner condition must preserve its exact expression and newline."
  }
  assert {
    condition     = issensitive(google_iam_workload_identity_pool_provider.identity-pool-provider.attribute_condition)
    error_message = "The owner condition must remain sensitive."
  }
}

run "reject_empty_owner" {
  command = plan
  module {
    source = "./modules/github-identity-federation"
  }
  variables {
    github_repository_owner = ""
  }
  expect_failures = [var.github_repository_owner]
}

run "reject_condition_injection" {
  command = plan
  module {
    source = "./modules/github-identity-federation"
  }
  variables {
    github_repository_owner = "example\" || true || \""
  }
  expect_failures = [var.github_repository_owner]
}

run "reject_invalid_owner_hyphens" {
  command = plan
  module {
    source = "./modules/github-identity-federation"
  }
  variables {
    github_repository_owner = "example--owner-"
  }
  expect_failures = [var.github_repository_owner]
}
