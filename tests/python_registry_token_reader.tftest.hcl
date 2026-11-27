mock_provider "google" {}

variables {
  github_repository_owner                 = "example-owner"
  project_id                              = "example-project"
  identity_pool_id                        = "example-pool"
  identity_provider_id                    = "example-provider"
  artifact_bucket_name                    = "example-private-artifacts"
  artifact_bucket_location                = "example-region1"
  artifact_bucket_writers                 = {}
  cluster_artifact_registry_location      = "example-region1"
  cluster_artifact_registry_repository_id = "example-images"
  python_artifact_registry_location       = "example-region1"
  python_artifact_registry_repository_id  = "example-python"
  loki_storage_folder_path                = ""
  asset_connector_tailscale_client_id     = "example-client-id"
  asset_connector_region                  = "us-west1"
  asset_connector_zone                    = "us-west1-b"
  asset_connector_bucket_name             = "example-assets"
  asset_connector_cors_origin             = "https://app.example.test"
  asset_connector_tailscale_version       = "1.0.0"
  asset_connector_tailscale_sha256        = "0000000000000000000000000000000000000000000000000000000000000000"
  asset_connector_caddy_version           = "2.0.0"
  asset_connector_caddy_sha512            = "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
  asset_connector_rclone_version          = "v1.0.0"
  asset_connector_rclone_sha256           = "0000000000000000000000000000000000000000000000000000000000000000"
  asset_connector_tenants                 = { example-app = { writers = [] } }
  federated_github_users = {
    secrets = {
      name                 = "secrets"
      display_name         = "Existing identity"
      description          = "Existing identity"
      allowed-repositories = ["example-owner/example-secrets"]
    }
  }
  python_registry_token_readers = {
    ci_reader = {
      account_id    = "example-token-reader"
      token_minters = { cluster = "serviceAccount:example-minter@example-project.iam.gserviceaccount.com" }
    }
  }
}

run "reader_is_repository_scoped_and_minter_is_token_creator_only" {
  command = plan

  assert {
    condition     = length(google_service_account.python_registry_token_reader) == 1 && google_service_account.python_registry_token_reader["ci_reader"].account_id == "example-token-reader"
    error_message = "One dedicated reader account must be created per alias."
  }

  assert {
    condition     = length(google_artifact_registry_repository_iam_member.python_registry_token_reader) == 1 && google_artifact_registry_repository_iam_member.python_registry_token_reader["ci_reader"].role == "roles/artifactregistry.reader" && google_artifact_registry_repository_iam_member.python_registry_token_reader["ci_reader"].repository == var.python_artifact_registry_repository_id && google_artifact_registry_repository_iam_member.python_registry_token_reader["ci_reader"].location == var.python_artifact_registry_location
    error_message = "The reader must receive read access on the Python repository only."
  }

  assert {
    condition     = length(google_service_account_iam_member.python_registry_token_minter) == 1 && google_service_account_iam_member.python_registry_token_minter["ci_reader/cluster"].role == "roles/iam.serviceAccountTokenCreator" && google_service_account_iam_member.python_registry_token_minter["ci_reader/cluster"].member == "serviceAccount:example-minter@example-project.iam.gserviceaccount.com"
    error_message = "Only the named minter may create tokens for the reader account."
  }
}

run "disabled_by_default" {
  command = plan
  variables {
    python_registry_token_readers = {}
  }
  assert {
    condition     = length(google_service_account.python_registry_token_reader) == 0 && length(google_artifact_registry_repository_iam_member.python_registry_token_reader) == 0 && length(google_service_account_iam_member.python_registry_token_minter) == 0
    error_message = "An empty map must leave existing deployments unchanged."
  }
}

run "multiple_minters_get_one_member_each" {
  command = plan
  variables {
    python_registry_token_readers = {
      ci_reader = {
        account_id = "example-token-reader"
        token_minters = {
          cluster = "serviceAccount:example-minter@example-project.iam.gserviceaccount.com"
          backup  = "serviceAccount:other-minter@example-project.iam.gserviceaccount.com"
        }
      }
    }
  }
  assert {
    condition     = length(google_service_account_iam_member.python_registry_token_minter) == 2 && length(google_artifact_registry_repository_iam_member.python_registry_token_reader) == 1
    error_message = "Each minter needs one token-creator member on the same reader."
  }
}

run "reject_user_minter" {
  command = plan
  variables {
    python_registry_token_readers = {
      ci_reader = {
        account_id    = "example-token-reader"
        token_minters = { person = "user:operator@example.com" }
      }
    }
  }
  expect_failures = [var.python_registry_token_readers]
}

run "reject_public_minter" {
  command = plan
  variables {
    python_registry_token_readers = {
      ci_reader = {
        account_id    = "example-token-reader"
        token_minters = { everyone = "allUsers" }
      }
    }
  }
  expect_failures = [var.python_registry_token_readers]
}

run "reject_reader_without_minter" {
  command = plan
  variables {
    python_registry_token_readers = {
      ci_reader = {
        account_id    = "example-token-reader"
        token_minters = {}
      }
    }
  }
  expect_failures = [var.python_registry_token_readers]
}

run "reject_malformed_account_id" {
  command = plan
  variables {
    python_registry_token_readers = {
      ci_reader = {
        account_id    = "Bad_ID"
        token_minters = { cluster = "serviceAccount:example-minter@example-project.iam.gserviceaccount.com" }
      }
    }
  }
  expect_failures = [var.python_registry_token_readers]
}

run "reject_malformed_alias" {
  command = plan
  variables {
    python_registry_token_readers = {
      "CI-Reader" = {
        account_id    = "example-token-reader"
        token_minters = { cluster = "serviceAccount:example-minter@example-project.iam.gserviceaccount.com" }
      }
    }
  }
  expect_failures = [var.python_registry_token_readers]
}

run "reject_shared_account_id" {
  command = plan
  variables {
    python_registry_token_readers = {
      ci_reader = {
        account_id    = "example-token-reader"
        token_minters = { cluster = "serviceAccount:example-minter@example-project.iam.gserviceaccount.com" }
      }
      other_reader = {
        account_id    = "example-token-reader"
        token_minters = { cluster = "serviceAccount:example-minter@example-project.iam.gserviceaccount.com" }
      }
    }
  }
  expect_failures = [var.python_registry_token_readers]
}

run "reject_reader_already_python_writer" {
  command = plan
  variables {
    python_artifact_registry_writers = { publisher = "serviceAccount:example-token-reader@example-project.iam.gserviceaccount.com" }
  }
  expect_failures = [google_service_account.python_registry_token_reader]
}

run "reject_reader_already_in_reader_map" {
  command = plan
  variables {
    python_artifact_registry_readers = { legacy = "serviceAccount:example-token-reader@example-project.iam.gserviceaccount.com" }
  }
  expect_failures = [google_service_account.python_registry_token_reader]
}

run "reject_reader_as_image_writer" {
  command = plan
  variables {
    cluster_artifact_registry_writers = { image_publisher = "serviceAccount:example-token-reader@example-project.iam.gserviceaccount.com" }
  }
  expect_failures = [google_service_account.python_registry_token_reader]
}

run "reject_reader_as_bucket_writer" {
  command = plan
  variables {
    artifact_bucket_writers = { uploader = "serviceAccount:example-token-reader@example-project.iam.gserviceaccount.com" }
  }
  expect_failures = [google_service_account.python_registry_token_reader]
}

run "reject_reader_as_asset_tenant_writer" {
  command = plan
  variables {
    asset_connector_tenants = { example-app = { writers = ["serviceAccount:example-token-reader@example-project.iam.gserviceaccount.com"] } }
  }
  expect_failures = [google_service_account.python_registry_token_reader]
}

run "reject_reader_as_wallet_signer" {
  command = plan
  variables {
    wallet_signer_service_account_id = "example-wallet-signing"
    wallet_signer_members            = ["serviceAccount:example-token-reader@example-project.iam.gserviceaccount.com"]
  }
  expect_failures = [google_service_account.python_registry_token_reader]
}

run "reject_account_id_shared_with_loki" {
  command = plan
  variables {
    loki_service_account_id = "example-token-reader"
  }
  expect_failures = [google_service_account.python_registry_token_reader]
}

run "reject_account_id_shared_with_backup_writer" {
  command = plan
  variables {
    workspace_backup_writer_service_account_id = "example-token-reader"
  }
  expect_failures = [google_service_account.python_registry_token_reader]
}

run "reject_self_minting" {
  command = plan
  variables {
    python_registry_token_readers = {
      ci_reader = {
        account_id    = "example-token-reader"
        token_minters = { self = "serviceAccount:example-token-reader@example-project.iam.gserviceaccount.com" }
      }
    }
  }
  expect_failures = [google_service_account.python_registry_token_reader]
}

run "existing_cluster_reader_may_be_the_minter" {
  command = plan
  variables {
    python_artifact_registry_readers = { cluster = "serviceAccount:example-minter@example-project.iam.gserviceaccount.com" }
  }
  assert {
    condition     = length(google_service_account_iam_member.python_registry_token_minter) == 1
    error_message = "A minter that already reads the repository keeps its grant and gains impersonation of the reader only."
  }
}
