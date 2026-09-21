variable "federation_member_imports" {
  description = "One-time existing grants to adopt, supplied privately. Clear after successful migration; new deployments use the empty default."
  type = map(object({
    account_key = string
    repository  = string
    id          = string
  }))
  default   = {}
  nullable  = false
  sensitive = true
}

import {
  # Routing keys already appear in Terraform resource addresses; IDs stay sensitive.
  for_each = nonsensitive({
    for key, grant in var.federation_member_imports : key => {
      account_key = grant.account_key
      repository  = grant.repository
    }
  })
  to = module.github-identity-federation.module.federated-github-user[each.value.account_key].google_service_account_iam_member.github-federated-user-repository-binding[each.value.repository]
  id = var.federation_member_imports[each.key].id
}
