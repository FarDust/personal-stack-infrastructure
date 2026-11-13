mock_provider "google" {
  mock_resource "google_service_account" {
    override_during = plan
    defaults = {
      name  = "projects/example-project/serviceAccounts/example-wallet-signer@example-project.iam.gserviceaccount.com"
      email = "example-wallet-signer@example-project.iam.gserviceaccount.com"
    }
  }
}

variables {
  project_id                = "example-project"
  signer_service_account_id = "example-wallet-signer"
  signer_members            = ["user:traveler@example.invalid"]
}

run "signing_is_scoped_to_one_identity_and_one_permission" {
  command = plan

  module {
    source = "./configs/wallet-signing"
  }

  assert {
    condition     = google_project_iam_custom_role.wallet_blob_signer[0].permissions == toset(["iam.serviceAccounts.signBlob"])
    error_message = "The custom role must allow signing only, without token minting, key creation, or impersonation."
  }

  assert {
    condition     = length(google_service_account_iam_member.wallet_blob_signer) == 1 && google_service_account_iam_member.wallet_blob_signer[0].service_account_id == google_service_account.wallet_signer[0].name && google_service_account_iam_member.wallet_blob_signer[0].member == "user:traveler@example.invalid"
    error_message = "The caller grant must target the dedicated service account, not the entire project."
  }

  assert {
    condition     = output.signer_service_account_email == "example-wallet-signer@example-project.iam.gserviceaccount.com"
    error_message = "Issuer setup must receive the dedicated signer's actual email."
  }
}

run "empty_signers_provision_nothing" {
  command = plan

  module {
    source = "./configs/wallet-signing"
  }

  variables {
    signer_members = []
  }

  assert {
    condition     = length(google_service_account.wallet_signer) == 0 && length(google_service_account_iam_member.wallet_blob_signer) == 0 && length(google_project_iam_custom_role.wallet_blob_signer) == 0
    error_message = "No signing resources may be created without an explicit caller."
  }
}

run "rejects_public_principal" {
  command = plan

  module {
    source = "./configs/wallet-signing"
  }

  variables {
    signer_members = ["allUsers"]
  }

  expect_failures = [var.signer_members]
}

run "rejects_missing_signing_identity" {
  command = plan

  module {
    source = "./configs/wallet-signing"
  }

  variables {
    signer_service_account_id = ""
  }

  expect_failures = [var.signer_service_account_id]
}
