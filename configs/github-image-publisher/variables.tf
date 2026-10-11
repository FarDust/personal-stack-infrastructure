variable "project_id" {
  type        = string
  description = "Google Cloud project that owns the existing GitHub identity pool."
  sensitive   = true
  nullable    = false
}

variable "workload_identity_pool_id" {
  type        = string
  description = "Suffix of the existing GitHub workload identity pool ID."
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.workload_identity_pool_id) <= 25 && can(regex("^[a-z0-9][a-z0-9-]{2,24}$", var.workload_identity_pool_id))
    error_message = "Use a 3-25 character lowercase pool suffix containing letters, numbers, or hyphens."
  }
}

variable "workload_identity_provider_id" {
  type        = string
  description = "Suffix of the dedicated GitHub image-publisher provider ID."
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.workload_identity_provider_id) <= 25 && can(regex("^[a-z0-9][a-z0-9-]{2,24}$", var.workload_identity_provider_id))
    error_message = "Use a 3-25 character lowercase provider suffix containing letters, numbers, or hyphens."
  }
}

variable "service_account_id" {
  type        = string
  description = "Full resource name of the existing publisher service account."
  sensitive   = true
  nullable    = false

  validation {
    condition     = can(regex("^projects/[^/]+/serviceAccounts/[^/]+@[^/]+\\.iam\\.gserviceaccount\\.com$", var.service_account_id))
    error_message = "Provide a full Google service-account resource name."
  }
}

variable "repository" {
  type        = string
  description = "Exact GitHub repository allowed to publish images."
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.repository))
    error_message = "Provide one exact GitHub repository in owner/name form."
  }
}

variable "repository_id" {
  type        = string
  description = "Immutable numeric GitHub repository ID allowed to publish images."
  nullable    = false

  validation {
    condition     = length(var.repository_id) <= 20 && can(regex("^[1-9][0-9]*$", var.repository_id))
    error_message = "Provide the immutable numeric GitHub repository ID using at most 20 digits."
  }
}

variable "workflow_path" {
  type        = string
  description = "Repository-relative GitHub Actions workflow path allowed to publish."
  nullable    = false

  validation {
    condition     = can(regex("^\\.github/workflows/[A-Za-z0-9_.-]+\\.ya?ml$", var.workflow_path))
    error_message = "Provide one workflow file below .github/workflows with a .yml or .yaml extension."
  }
}

variable "trusted_workflow_path" {
  type        = string
  description = "Repository-relative reusable workflow path that owns authenticated publication on main."
  nullable    = false

  validation {
    condition     = can(regex("^\\.github/workflows/[A-Za-z0-9_.-]+\\.ya?ml$", var.trusted_workflow_path))
    error_message = "Provide one reusable workflow file below .github/workflows with a .yml or .yaml extension."
  }
}
