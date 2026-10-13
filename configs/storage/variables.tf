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

variable "noncurrent_version_expiry" {
  type = map(object({
    prefix = string
    days   = number
  }))
  description = "Aliases mapped to an object-name prefix and the days after which its noncurrent versions are deleted."
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for rule in values(var.noncurrent_version_expiry) : rule.prefix != "" && rule.days >= 1])
    error_message = "Each expiry rule needs a non-empty object-name prefix, so it cannot cover the whole bucket, and at least one day."
  }
}
