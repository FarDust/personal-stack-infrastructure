variable "project_id" {
  type        = string
  description = "The project in which shared artifact storage will be provisioned."
  sensitive   = true
}

variable "artifact_bucket_location" {
  type        = string
  description = "The region in which shared artifact storage will be provisioned."
  sensitive   = true
}

variable "artifact_bucket_name" {
  type        = string
  description = "The shared private artifact bucket name supplied by Terraform Cloud."
  sensitive   = true
}

variable "artifact_bucket_writers" {
  type        = map(string)
  description = "Non-secret aliases mapped to approved object-access principals."
  sensitive   = true
  nullable    = false

  validation {
    condition     = alltrue([for principal in values(var.artifact_bucket_writers) : can(regex("^(user|serviceAccount|group):[^\\s]+@[^\\s]+$", principal))])
    error_message = "Use explicit user, group or service-account email principals; public grants are not allowed."
  }
}
