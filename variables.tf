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

variable "gpu_idle_lab_dvc_bucket_name" {
  type        = string
  description = "The private GCS bucket name for GPU Idle Lab DVC artifacts."
  sensitive   = true
}

variable "gpu_idle_lab_dvc_location" {
  type        = string
  description = "DVC bucket location supplied by Terraform Cloud, independently of the provider region."
  nullable    = false
}
