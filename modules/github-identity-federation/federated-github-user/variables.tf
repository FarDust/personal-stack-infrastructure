variable "project-id" {
  type        = string
  description = "The project ID to create the service account in."
  sensitive   = true
}

variable "identity-pool-name" {
  type        = string
  description = "The identity pool to use for the federated user"
  sensitive   = true
}

variable "name" {
  type        = string
  description = "Name of the federated user"
  sensitive   = true
}

variable "display_name" {
  type        = string
  description = "Display name of the federated user"
  sensitive   = false
}

variable "description" {
  type        = string
  description = "Description of the federated user"
  sensitive   = false
}

variable "allowed-repositories" {
  type        = list(string)
  description = "A list of repositories to allow the federated user to access"
  sensitive   = false

  validation {
    condition     = length(distinct(var.allowed-repositories)) <= 1
    error_message = "The preserved legacy IAM binding supports at most one distinct repository per account. Migrate the IAM resource layout before configuring multiple repositories."
  }
}
