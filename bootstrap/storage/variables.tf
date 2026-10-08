variable "project_id" {
  type        = string
  description = "Project receiving the narrowly scoped provisioning permissions."
  sensitive   = true
}

variable "artifact_bucket_name" {
  type        = string
  description = "Exact artifact bucket name supplied privately."
  sensitive   = true
}

variable "terraform_executor" {
  type        = string
  description = "Existing Terraform runtime service-account principal."
  sensitive   = true

  validation {
    condition     = can(regex("^serviceAccount:[^\\s]+@[^\\s]+\\.iam\\.gserviceaccount\\.com$", var.terraform_executor))
    error_message = "Supply an explicit service-account principal for the Terraform runtime."
  }
}

variable "cluster_artifact_registry_location" {
  type        = string
  description = "Artifact Registry location for private cluster Docker images."
  default     = "southamerica-west1"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", lower(var.cluster_artifact_registry_location)))
    error_message = "Provide a regional Artifact Registry location and review its cost before deployment."
  }
}

variable "cluster_artifact_registry_repository_id" {
  type        = string
  description = "Artifact Registry repository ID for private cluster Docker images."
  default     = "cluster-internal-images"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,62}$", var.cluster_artifact_registry_repository_id))
    error_message = "The repository ID must be 3-63 lowercase letters, numbers, or hyphens and start with a letter."
  }
}
