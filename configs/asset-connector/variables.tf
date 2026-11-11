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
    condition     = can(regex("^https://[^/*\\s\"{}]+$", var.cors_origin))
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

variable "caddy_version" {
  type        = string
  description = "Pinned Caddy release staged under bootstrap/ in the bucket."
  nullable    = false
}

variable "caddy_sha512" {
  type        = string
  description = "SHA-512 of the pinned Caddy linux_amd64 tarball, from the release checksums file."
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{128}$", var.caddy_sha512))
    error_message = "Provide a lowercase hex SHA-512."
  }
}

variable "rclone_version" {
  type        = string
  description = "Pinned rclone release (for example v1.2.3) staged under bootstrap/ in the bucket."
  nullable    = false
}

variable "rclone_sha256" {
  type        = string
  description = "SHA-256 of the pinned rclone linux-amd64 package, from the signed release checksums."
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.rclone_sha256))
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
    condition     = alltrue([for t in nonsensitive(keys(var.tenants)) : can(regex("^[a-z][a-z0-9-]{1,19}[a-z0-9]$", t))])
    error_message = "Tenant prefixes are lowercase slugs of 3 to 21 characters."
  }
  validation {
    condition     = !contains(nonsensitive(keys(var.tenants)), "bootstrap")
    error_message = "The bootstrap prefix is reserved for pinned binaries."
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

variable "tailscale_client_id" {
  type        = string
  description = "Client id of the Tailscale federated identity that trusts the VM identity (tag, preauthorized, auth_keys scope only)."
  sensitive   = true
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{6,64}$", var.tailscale_client_id))
    error_message = "Provide the federated identity client id."
  }
}
