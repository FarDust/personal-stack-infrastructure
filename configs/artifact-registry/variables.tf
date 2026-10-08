variable "project_id" {
  type        = string
  description = "The project in which the private cluster image registry will be provisioned."
  sensitive   = true
}

variable "terraform_executor" {
  type        = string
  description = "Existing Terraform runtime service-account principal."
  sensitive   = true

  validation {
    condition     = can(regex("^serviceAccount:[^\\s@]+@[^\\s@]+\\.iam\\.gserviceaccount\\.com$", var.terraform_executor))
    error_message = "Supply an explicit service-account principal for the Terraform runtime."
  }
}

variable "cluster_artifact_registry_location" {
  type        = string
  description = "Artifact Registry location for private cluster Docker images."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", lower(var.cluster_artifact_registry_location)))
    error_message = "Provide a regional Artifact Registry location and review its cost before deployment."
  }
}

variable "cluster_artifact_registry_repository_id" {
  type        = string
  description = "Artifact Registry repository ID for private cluster Docker images."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,62}$", var.cluster_artifact_registry_repository_id))
    error_message = "The repository ID must be 3-63 lowercase letters, numbers, or hyphens and start with a letter."
  }
}

variable "cluster_artifact_registry_writers" {
  type        = map(string)
  description = "Non-secret aliases mapped to approved Artifact Registry writer principals."
  sensitive   = true
  nullable    = false

  validation {
    condition     = alltrue([for principal in values(var.cluster_artifact_registry_writers) : can(regex("^(user|serviceAccount|group):[^\\s]+@[^\\s]+$", principal))])
    error_message = "Use explicit user, group or service-account email principals; public grants are not allowed."
  }
}

variable "cluster_artifact_registry_readers" {
  type        = map(string)
  description = "Non-secret aliases mapped to approved Artifact Registry reader principals."
  sensitive   = true
  nullable    = false

  validation {
    condition     = alltrue([for principal in values(var.cluster_artifact_registry_readers) : can(regex("^(user|serviceAccount|group):[^\\s]+@[^\\s]+$", principal))])
    error_message = "Use explicit user, group or service-account email principals; public grants are not allowed."
  }
}
