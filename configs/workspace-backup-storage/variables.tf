variable "project_id" {
  type        = string
  description = "The project that owns the shared backup bucket."
  sensitive   = true
  nullable    = false
}

variable "artifact_bucket_name" {
  type        = string
  description = "The shared bucket that contains managed workspace backup folders."
  sensitive   = true
  nullable    = false
}

variable "workspace_backup_folder_paths" {
  type        = map(string)
  description = "Sensitive aliases mapped to the two managed workspace backup folder paths."
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

variable "writer_service_account_id" {
  type        = string
  description = "The generic account ID for the managed workspace-backup writer identity."
  default     = "workspace-backup-writer"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.writer_service_account_id))
    error_message = "Use a 6-30 character lowercase service-account ID with letters, numbers, and hyphens."
  }
}
