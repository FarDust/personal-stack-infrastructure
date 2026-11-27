variable "python_registry_token_readers" {
  description = "Neutral aliases of dedicated Python repository reader accounts that named minter principals may impersonate for short-lived access tokens. Account IDs and minter principals are configured privately in HCP Terraform; empty disables the capability."
  type = map(object({
    account_id    = string
    display_name  = optional(string, "Python registry token reader")
    token_minters = map(string)
  }))
  default   = {}
  sensitive = true
  nullable  = false

  validation {
    condition = alltrue([
      for alias, reader in var.python_registry_token_readers :
      can(regex("^[a-z][a-z0-9_]*$", alias)) &&
      can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", reader.account_id)) &&
      length(reader.token_minters) >= 1 &&
      alltrue([for minter_alias, minter in reader.token_minters :
        can(regex("^[a-z][a-z0-9_]*$", minter_alias)) &&
        can(regex("^serviceAccount:[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z0-9.-]+\\.iam\\.gserviceaccount\\.com$", minter))
      ])
    ])
    error_message = "Each reader needs a lowercase alias, a 6-30 character service-account ID and at least one aliased minter that is an explicit serviceAccount: principal; users, groups and public principals cannot mint tokens."
  }

  validation {
    condition     = length(distinct([for reader in values(var.python_registry_token_readers) : reader.account_id])) == length(var.python_registry_token_readers)
    error_message = "Each token reader alias needs its own service-account ID."
  }
}

locals {
  # Only neutral aliases become resource keys; account IDs and principals stay in sensitive values.
  python_registry_token_reader_aliases = nonsensitive(toset(keys(var.python_registry_token_readers)))
  python_registry_token_minter_keys = nonsensitive(toset(flatten([
    for alias, reader in var.python_registry_token_readers : [
      for minter_alias in keys(reader.token_minters) : "${alias}/${minter_alias}"
    ]
  ])))

  # The provider reports the email only after apply; it is derived from the account ID so preconditions hold at plan time.
  # Domain-scoped project IDs are not supported by this derivation.
  python_registry_token_reader_principals = {
    for alias, reader in var.python_registry_token_readers :
    alias => "serviceAccount:${reader.account_id}@${var.project_id}.iam.gserviceaccount.com"
  }

  python_registry_token_reader_privileged_principals = concat(
    values(var.python_artifact_registry_writers),
    values(var.python_artifact_registry_readers),
    values(var.cluster_artifact_registry_writers),
    values(var.artifact_bucket_writers),
    flatten([for tenant in values(var.asset_connector_tenants) : tenant.writers]),
    var.wallet_signer_members,
  )
}

# Keyless, repository-scoped reader impersonated by a named minter; see docs/adr/python_registry_token_reader_adr.md.
resource "google_service_account" "python_registry_token_reader" {
  for_each = local.python_registry_token_reader_aliases

  project      = var.project_id
  account_id   = var.python_registry_token_readers[each.key].account_id
  display_name = var.python_registry_token_readers[each.key].display_name
  description  = "Reads the private Python repository only; impersonated for short-lived access tokens, no keys."

  lifecycle {
    precondition {
      condition     = !contains(local.python_registry_token_reader_privileged_principals, local.python_registry_token_reader_principals[each.key])
      error_message = "A token reader must not appear in a registry reader or writer map, a bucket or asset-tenant writer list, or the Wallet signer list managed by this root; it has one state owner and read-only access."
    }
    precondition {
      condition     = !contains(compact([var.wallet_signer_service_account_id, var.loki_service_account_id, var.workspace_backup_writer_service_account_id]), var.python_registry_token_readers[each.key].account_id)
      error_message = "A token reader needs its own service-account ID, distinct from the Wallet signer, Loki and backup writer identities."
    }
    precondition {
      condition     = !contains(values(var.python_registry_token_readers[each.key].token_minters), local.python_registry_token_reader_principals[each.key])
      error_message = "A token reader cannot be its own minter."
    }
  }
}

resource "google_artifact_registry_repository_iam_member" "python_registry_token_reader" {
  for_each = local.python_registry_token_reader_aliases

  project    = var.project_id
  location   = var.python_artifact_registry_location
  repository = var.python_artifact_registry_repository_id
  role       = "roles/artifactregistry.reader"
  member     = google_service_account.python_registry_token_reader[each.key].member
}

resource "google_service_account_iam_member" "python_registry_token_minter" {
  # Keys are "<reader alias>/<minter alias>"; the alias validation forbids "/".
  for_each = local.python_registry_token_minter_keys

  service_account_id = google_service_account.python_registry_token_reader[split("/", each.key)[0]].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = var.python_registry_token_readers[split("/", each.key)[0]].token_minters[split("/", each.key)[1]]
}

output "python_registry_token_reader_emails" {
  description = "Token reader service-account emails by neutral alias, for the minter's impersonation target."
  value       = { for alias, account in google_service_account.python_registry_token_reader : alias => account.email }
  sensitive   = true
}
