mock_provider "google" {}

variables {
  project-id           = "example-project"
  identity-pool-name   = "projects/123456/locations/global/workloadIdentityPools/example-pool"
  name                 = "example"
  display_name         = "Example"
  description          = "validates legacy bindings"
  allowed-repositories = ["example-owner/example-repository"]
}

run "existing_single_repository" {
  command = plan
  module {
    source = "./modules/github-identity-federation/federated-github-user"
  }
  assert {
    condition     = length(google_service_account_iam_binding.github-federated-user-repository-binding) == 1
    error_message = "The existing one-repository IAM address must remain unchanged."
  }
}

run "reject_conflicting_authoritative_bindings" {
  command = plan
  module {
    source = "./modules/github-identity-federation/federated-github-user"
  }
  variables {
    allowed-repositories = ["example-owner/first", "example-owner/second"]
  }
  expect_failures = [var.allowed-repositories]
}

run "duplicate_repository_is_one_binding" {
  command = plan
  module {
    source = "./modules/github-identity-federation/federated-github-user"
  }
  variables {
    allowed-repositories = ["example-owner/example-repository", "example-owner/example-repository"]
  }
  assert {
    condition     = length(google_service_account_iam_binding.github-federated-user-repository-binding) == 1
    error_message = "Duplicate entries must continue to represent one binding."
  }
}
