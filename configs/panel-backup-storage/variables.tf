variable "enabled" {
  type     = bool
  nullable = false
}

variable "grant_enabled" {
  type     = bool
  default  = true
  nullable = false
}

variable "project_id" {
  type      = string
  sensitive = true
  nullable  = false
}

variable "bucket_name" {
  type      = string
  sensitive = true
  nullable  = false
}

variable "folder_path" {
  type      = string
  sensitive = true
  nullable  = false

  validation {
    condition     = var.folder_path == "" || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/$", var.folder_path))
    error_message = "Use an empty value or one lowercase server UUID followed by a slash."
  }
}

variable "service_account_id" {
  type     = string
  default  = "panel-backup-writer"
  nullable = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_id))
    error_message = "Use a valid 6-30 character service-account ID."
  }
}
