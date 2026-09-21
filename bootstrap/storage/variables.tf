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
