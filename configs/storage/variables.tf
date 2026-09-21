variable "project_id" {
  type        = string
  description = "The project in which the DVC bucket will be provisioned."
  sensitive   = true
}

variable "gcp_region" {
  type        = string
  description = "The region in which the DVC bucket will be provisioned."
}

variable "gpu_idle_lab_dvc_bucket_name" {
  type        = string
  description = "The private DVC bucket name supplied by Terraform Cloud."
  sensitive   = true
}
