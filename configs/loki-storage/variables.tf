variable "project_id" {
  type        = string
  description = "The project that owns the shared artifact bucket."
  sensitive   = true
  nullable    = false
}

variable "artifact_bucket_name" {
  type        = string
  description = "The shared bucket that contains the Loki managed folder."
  sensitive   = true
  nullable    = false
}

variable "loki_storage_folder_path" {
  type        = string
  description = "The managed folder that scopes the Loki identity. Empty disables the module."
  default     = "loki/cluster/"
  nullable    = false

  validation {
    condition     = var.loki_storage_folder_path == "" || can(regex("^loki/[a-z0-9][a-z0-9-]*/$", var.loki_storage_folder_path))
    error_message = "Use an empty value or a lowercase path directly under loki/ with a trailing slash, for example loki/cluster/."
  }
}

variable "loki_service_account_id" {
  type        = string
  description = "The generic account ID for the Loki object-storage identity."
  default     = "loki-cluster-storage"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.loki_service_account_id))
    error_message = "Use a 6-30 character lowercase service-account ID with letters, numbers, and hyphens."
  }
}
