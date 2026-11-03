variable "project_id" {
  description = "Project containing the Wallet signing identity and enabled APIs."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "A valid project identifier is required."
  }
}

variable "signer_service_account_id" {
  description = "Dedicated signing service-account identifier, set in the owning workspace."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = length(var.signer_members) == 0 || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.signer_service_account_id))
    error_message = "An enabled signing configuration requires a valid dedicated service-account identifier."
  }
}

variable "signer_members" {
  description = "Explicit user or service-account principals allowed to sign Wallet pass bytes. Empty disables provisioning."
  type        = list(string)
  sensitive   = true
  default     = []

  validation {
    condition     = length(distinct(var.signer_members)) == length(var.signer_members) && alltrue([for member in var.signer_members : can(regex("^(user|serviceAccount):[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", member))])
    error_message = "Use distinct explicit user or serviceAccount email principals; public and group principals are not permitted."
  }
}
