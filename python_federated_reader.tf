variable "python_artifact_registry_federated_readers" {
  description = "Non-secret aliases of dedicated accounts in federated_github_users receiving Python repository read access. Configure identities privately in HCP Terraform."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for alias in var.python_artifact_registry_federated_readers :
      alias != "secrets" && can(regex("^[a-z][a-z0-9_]*$", alias)) && try(
        length(var.federated_github_users[alias].allowed-repositories) == 1 &&
        can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.federated_github_users[alias].allowed-repositories[0])) &&
        split("/", var.federated_github_users[alias].allowed-repositories[0])[0] == var.github_repository_owner,
        false
      )
    ])
    error_message = "Select existing dedicated account aliases, each with exactly one repository under the configured owner; the secrets identity is not a package reader."
  }
}

# Federation and account lifecycle remain owned by the pinned shared module.
# See docs/adr/python_federated_reader_adr.md.
resource "google_artifact_registry_repository_iam_member" "python_federated_reader" {
  for_each   = toset([for alias in var.python_artifact_registry_federated_readers : alias if alias != null && alias != ""])
  project    = var.project_id
  location   = var.python_artifact_registry_location
  repository = var.python_artifact_registry_repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${module.github-identity-federation.federated-github-users[each.key].federated-user.email}"

  lifecycle {
    precondition {
      condition = !contains(concat(
        values(var.python_artifact_registry_writers),
        values(var.cluster_artifact_registry_writers),
        values(var.artifact_bucket_writers),
        ["serviceAccount:${module.github-identity-federation.federated-github-users["secrets"].federated-user.email}"],
        [for email in compact([
          module.workspace_backup_storage.writer_service_account_email,
          module.loki_storage.service_account_email
        ]) : "serviceAccount:${email}"]
      ), "serviceAccount:${module.github-identity-federation.federated-github-users[each.key].federated-user.email}")
      error_message = "A dedicated package reader must not also hold a writer, storage administration, backup writer, or secrets grant managed by this root. Review effective IAM separately for external grants."
    }
  }
}
