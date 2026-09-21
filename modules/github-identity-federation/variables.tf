variable "github_repository_owner" {
  type        = string
  description = "GitHub repository owner permitted to authenticate through this provider."
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.github_repository_owner) <= 39 && can(regex("^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$", var.github_repository_owner))
    error_message = "Provide a GitHub owner name of at most 39 characters, using alphanumeric groups separated by single hyphens."
  }
}

variable "federated-github-users" {
  type = map(object({
    name                 = string
    display_name         = string
    description          = string
    allowed-repositories = list(string)
  }))
  description = "A map of federated users to create"
  sensitive   = false
}

variable "project-id" {
  type        = string
  description = "The project ID to create the service account in."
  sensitive   = true
}

variable "landing-identity-pool-id" {
  type        = string
  description = "The identity pool to use for the federated user"
  sensitive   = true
}

variable "identity-provider-id" {
  type        = string
  description = "The identity provider to use for the federated user"
  sensitive   = true
}
