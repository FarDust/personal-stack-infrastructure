mock_provider "google" {}

variables {
  project-id           = "example-project"
  identity-pool-name   = "projects/123456/locations/global/workloadIdentityPools/example-pool"
  name                 = "example"
  display_name         = "Example"
  description          = "validates legacy bindings"
  allowed-repositories = ["example-owner/example-repository"]
  legacy-repositories  = ["example-owner/example-repository"]
}

run "existing_single_repository" {
  command = plan
  module {
    source = "./.terraform/modules/github-identity-federation/modules/github-identity-federation/federated-github-user"
  }
  providers = {
    google = google
  }
  assert {
    condition     = output.iam_binding_count == 1 && output.iam_member_count == 0
    error_message = "The existing one-repository IAM address must remain unchanged."
  }
}

run "reject_conflicting_authoritative_bindings" {
  command = plan
  module {
    source = "./.terraform/modules/github-identity-federation/modules/github-identity-federation/federated-github-user"
  }
  providers = {
    google = google
  }
  variables {
    legacy-repositories = ["example-owner/first", "example-owner/second"]
  }
  expect_failures = [var.legacy-repositories]
}

run "duplicate_repository_is_one_binding" {
  command = plan
  module {
    source = "./.terraform/modules/github-identity-federation/modules/github-identity-federation/federated-github-user"
  }
  providers = {
    google = google
  }
  variables {
    legacy-repositories = ["example-owner/example-repository", "example-owner/example-repository"]
  }
  assert {
    condition     = output.iam_binding_count == 1 && output.iam_member_count == 0
    error_message = "Duplicate entries must continue to represent one binding."
  }
}
