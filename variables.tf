variable "github_repository_owner" {
  type        = string
  description = "GitHub repository owner permitted to authenticate; supplied by Terraform Cloud."
  sensitive   = true
  nullable    = false
}

variable "gcp_region" {
  type        = string
  description = "The region in which the resources will be provisioned."
  default     = "us-central1"
  sensitive   = false
}

variable "project_id" {
  type        = string
  description = "The ID of the project in which the resources will be provisioned."
  sensitive   = true
}

variable "identity_pool_id" {
  type        = string
  description = "The ID of the Identity pool."
  sensitive   = true
}

variable "identity_provider_id" {
  type        = string
  description = "The ID of the Identity pool provider."
  sensitive   = true
}

variable "federated_github_users" {
  type = map(object({
    name                 = string
    display_name         = string
    description          = string
    allowed-repositories = list(string)
  }))
  description = "The Github users to federate."
  sensitive   = false
}

variable "github_image_publisher" {
  type = object({
    federated_user_key            = string
    workload_identity_provider_id = string
    repository                    = string
    repository_id                 = string
    workflow_path                 = string
  })
  description = "GitHub identity and workflow contract for the image publisher."
  sensitive   = false
  nullable    = false
}

variable "artifact_bucket_name" {
  type        = string
  description = "The shared private artifact bucket name supplied by Terraform Cloud."
  sensitive   = true
}

variable "artifact_bucket_location" {
  type        = string
  description = "Shared artifact bucket location supplied by Terraform Cloud."
  sensitive   = true
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", lower(var.artifact_bucket_location)))
    error_message = "Provide a regional location identifier and review its cost before deployment."
  }
}

variable "artifact_bucket_writers" {
  type        = map(string)
  description = "Non-secret role aliases mapped to approved IAM user, group or service-account principals. Values are supplied by Terraform Cloud."
  sensitive   = true
  nullable    = false
}

variable "workspace_backup_folder_paths" {
  type        = map(string)
  description = "Sensitive aliases mapped to the two private workspace backup folder paths, supplied by Terraform Cloud."
  default     = {}
  sensitive   = true
  nullable    = false

  validation {
    condition = length(var.workspace_backup_folder_paths) == 0 || (
      length(var.workspace_backup_folder_paths) == 2 &&
      length(toset(values(var.workspace_backup_folder_paths))) == 2 &&
      alltrue([
        for path in values(var.workspace_backup_folder_paths) :
        can(regex("^backups/workspaces/[a-z0-9][a-z0-9-]*/$", path))
      ])
    )
    error_message = "Configure exactly two distinct lowercase workspace backup paths under backups/workspaces/, each with a trailing slash."
  }
}

variable "workspace_backup_writer_service_account_id" {
  type        = string
  description = "The generic account ID for the workspace-backup writer identity."
  default     = "workspace-backup-writer"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.workspace_backup_writer_service_account_id))
    error_message = "Use a 6-30 character lowercase service-account ID with letters, numbers, and hyphens."
  }
}

variable "cluster_artifact_registry_location" {
  type        = string
  description = "Artifact Registry location for private cluster Docker images, supplied by Terraform Cloud."
  default     = "southamerica-west1"
  sensitive   = false
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
  sensitive   = false
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,62}$", var.cluster_artifact_registry_repository_id))
    error_message = "The repository ID must be 3-63 lowercase letters, numbers, or hyphens and start with a letter."
  }
}

variable "cluster_artifact_registry_writers" {
  type        = map(string)
  description = "Non-secret aliases mapped to approved Artifact Registry writer principals. Values are supplied by Terraform Cloud."
  default     = {}
  sensitive   = true
  nullable    = false

  validation {
    condition     = alltrue([for principal in values(var.cluster_artifact_registry_writers) : can(regex("^(user|serviceAccount|group):[^\\s]+@[^\\s]+$", principal))])
    error_message = "Use explicit user, group or service-account email principals; public grants are not allowed."
  }
}

variable "cluster_artifact_registry_readers" {
  type        = map(string)
  description = "Non-secret aliases mapped to approved Artifact Registry reader principals. Values are supplied by Terraform Cloud."
  default     = {}
  sensitive   = true
  nullable    = false

  validation {
    condition     = alltrue([for principal in values(var.cluster_artifact_registry_readers) : can(regex("^(user|serviceAccount|group):[^\\s]+@[^\\s]+$", principal))])
    error_message = "Use explicit user, group or service-account email principals; public grants are not allowed."
  }
}
