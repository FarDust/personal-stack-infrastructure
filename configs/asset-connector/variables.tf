variable "project_id" {
  type        = string
  description = "The project that hosts the asset connector."
  sensitive   = true
}

variable "region" {
  type        = string
  description = "Free-tier compute and storage region (us-west1, us-central1 or us-east1); supplied by Terraform Cloud."
  sensitive   = true
  nullable    = false

  validation {
    condition     = contains(["us-west1", "us-central1", "us-east1"], var.region)
    error_message = "Only the three Always Free regions keep the connector inside the free tier."
  }
}

variable "zone" {
  type        = string
  description = "Zone inside the chosen region; supplied by Terraform Cloud."
  sensitive   = true
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Provide a zone identifier such as <region>-<letter>."
  }
}

variable "bucket_name" {
  type        = string
  description = "Private asset bucket name; supplied by Terraform Cloud."
  sensitive   = true
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_.-]{2,62}$", var.bucket_name))
    error_message = "Provide a valid, globally unique bucket name."
  }
}

variable "cors_origin" {
  type        = string
  description = "The single HTTPS origin allowed to read assets from the browser."
  sensitive   = true
  nullable    = false

  validation {
    condition     = can(regex("^https://[^/*\\s]+$", var.cors_origin))
    error_message = "Use one explicit https origin without a wildcard or path."
  }
}

variable "tailscale_tag" {
  type        = string
  description = "Tailscale ACL tag the connector advertises."
  default     = "tag:asset-connector"
  nullable    = false

  validation {
    condition     = can(regex("^tag:[a-z][a-z0-9-]*$", var.tailscale_tag))
    error_message = "Use a tag such as tag:asset-connector."
  }
}

variable "tailscale_version" {
  type        = string
  description = "Pinned Tailscale static release staged under bootstrap/ in the bucket."
  nullable    = false
}

variable "tailscale_sha256" {
  type        = string
  description = "SHA-256 of the pinned Tailscale amd64 tarball, from the release publisher."
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.tailscale_sha256))
    error_message = "Provide a lowercase hex SHA-256."
  }
}

variable "nginx_version" {
  type        = string
  description = "Pinned Debian nginx package version staged under bootstrap/ in the bucket."
  nullable    = false
}

variable "nginx_deb_sha256" {
  type        = string
  description = "SHA-256 of the staged nginx amd64 package."
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.nginx_deb_sha256))
    error_message = "Provide a lowercase hex SHA-256."
  }
}

variable "nginx_common_deb_sha256" {
  type        = string
  description = "SHA-256 of the staged nginx-common package."
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.nginx_common_deb_sha256))
    error_message = "Provide a lowercase hex SHA-256."
  }
}

variable "tenants" {
  type = map(object({
    writers = list(string)
  }))
  description = "Project prefixes served by the CDN, each with extra writer principals besides its own writer service account."
  sensitive   = true
  nullable    = false

  validation {
    condition     = alltrue([for t in nonsensitive(keys(var.tenants)) : can(regex("^[a-z][a-z0-9-]{1,20}$", t))])
    error_message = "Tenant prefixes are lowercase slugs of at most 21 characters."
  }
  validation {
    condition     = alltrue(flatten([for t in var.tenants : [for w in t.writers : can(regex("^(user|serviceAccount|group):[^\\s]+@[^\\s]+$", w))]]))
    error_message = "Use explicit user, group or service-account principals; public grants are not allowed."
  }
}

variable "notification_email" {
  type        = string
  description = "Recipient of the egress alert; null leaves the alert without a notification channel."
  default     = null
  sensitive   = true
}

variable "daily_egress_alert_mib" {
  type        = number
  description = "Daily VM egress that raises the alert (the free tier is 1 GiB per month)."
  default     = 25
  nullable    = false
}

variable "billing_account_id" {
  type        = string
  description = "Billing account for the connector budget alert; null skips the budget."
  default     = null
  sensitive   = true
}

variable "budget_usd" {
  type        = number
  description = "Monthly budget alert for resources labelled as the connector."
  default     = 5
  nullable    = false

  validation {
    condition     = var.budget_usd > 0 && var.budget_usd <= 20
    error_message = "Keep the connector budget positive and within the 20 USD monthly cap."
  }
}

variable "tailscale_authkey" {
  type        = string
  description = "One-time tagged pre-authorized Tailscale key, written by a CI workflow into a sensitive workspace variable; empty until it is issued."
  default     = ""
  sensitive   = true
  nullable    = false
}
