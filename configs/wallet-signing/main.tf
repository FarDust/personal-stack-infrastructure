locals {
  enabled = nonsensitive(length(var.signer_members)) > 0
}

resource "google_service_account" "wallet_signer" {
  count = local.enabled ? 1 : 0

  project      = var.project_id
  account_id   = var.signer_service_account_id
  display_name = "Personal Wallet pass signer"
  description  = "Keyless signing identity for personal Google Wallet passes."
}

resource "google_project_iam_custom_role" "wallet_blob_signer" {
  count = local.enabled ? 1 : 0

  project     = var.project_id
  role_id     = "walletPassBlobSigner"
  title       = "Wallet Pass Blob Signer"
  description = "Signs Wallet pass bytes without creating keys or minting access tokens."
  permissions = ["iam.serviceAccounts.signBlob"]
}

resource "google_service_account_iam_member" "wallet_blob_signer" {
  count = nonsensitive(length(var.signer_members))

  service_account_id = google_service_account.wallet_signer[0].name
  role               = google_project_iam_custom_role.wallet_blob_signer[0].name
  member             = var.signer_members[count.index]
}
