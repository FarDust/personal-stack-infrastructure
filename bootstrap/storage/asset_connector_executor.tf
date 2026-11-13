# Roles the Terraform runtime needs to create the asset connector (see docs/adr/asset_connector_adr.md).
# Added for the asset connector: review and tighten after the first successful apply.
# Conditions below document intent: the executor also holds project IAM admin and could rewrite
# them, so they are audit value, not a security boundary.
# Nothing here grants owner, editor, organization roles, other buckets or Service Usage: the
# compute API is enabled once outside Terraform, so the executor never receives a role that
# can enable or disable APIs.

locals {
  connector_enabled = var.asset_connector_bucket_name != null
}

# Instances, boot disks and their metadata. Predefined role; the Compute API did not exist in this
# project before the connector, and IAM conditions cannot cover the operation and project
# permissions the role also holds, so the scope is the role itself.
resource "google_project_iam_member" "asset_connector_instance_admin" {
  count   = local.connector_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = var.terraform_executor
}

# Network, subnetwork and firewall lifecycle only: a custom role instead of the predefined
# network admin (routes, addresses, VPN, interconnect, ...).
resource "google_project_iam_custom_role" "asset_connector_network_manager" {
  count       = local.connector_enabled ? 1 : 0
  project     = var.project_id
  role_id     = "assetConnectorNetworkManager"
  title       = "Asset connector network manager"
  description = "Create and manage the connector VPC, subnetwork and firewall rule."
  stage       = "GA"
  permissions = [
    "compute.networks.create",
    "compute.networks.delete",
    "compute.networks.get",
    "compute.networks.list",
    "compute.networks.updatePolicy",
    "compute.networks.use",
    "compute.subnetworks.create",
    "compute.subnetworks.delete",
    "compute.subnetworks.expandIpCidrRange",
    "compute.subnetworks.get",
    "compute.subnetworks.list",
    "compute.subnetworks.setPrivateIpGoogleAccess",
    "compute.subnetworks.update",
    "compute.subnetworks.use",
    "compute.subnetworks.useExternalIp",
    "compute.firewalls.create",
    "compute.firewalls.delete",
    "compute.firewalls.get",
    "compute.firewalls.list",
    "compute.firewalls.update",
    "compute.globalOperations.get",
    "compute.globalOperations.list",
    "compute.regionOperations.get",
    "compute.regionOperations.list",
    "compute.zoneOperations.get",
    "compute.zoneOperations.list",
  ]
}

resource "google_project_iam_member" "asset_connector_network_manager" {
  count   = local.connector_enabled ? 1 : 0
  project = var.project_id
  role    = google_project_iam_custom_role.asset_connector_network_manager[0].name
  member  = var.terraform_executor
}

# Alert policies for the egress guard. The editor role cannot manage notification channels, so the
# connector keeps notification_email unset until a channel role is granted deliberately.
resource "google_project_iam_member" "asset_connector_alert_policy_editor" {
  count   = local.connector_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.alertPolicyEditor"
  member  = var.terraform_executor
}

# Attach the connector identity to the VM: user of that one service account only. Bound on the
# service account resource itself (a project-level condition on the name is not honoured by the
# compute actAs check, which failed on the first attempt).
resource "google_service_account_iam_member" "asset_connector_identity_user" {
  count              = local.connector_enabled ? 1 : 0
  service_account_id = "projects/${var.project_id}/serviceAccounts/asset-connector@${var.project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = var.terraform_executor
}

# Manage the connector bucket and nothing else in Cloud Storage (second binding next to the
# shared artifact bucket binding).
resource "google_project_iam_member" "asset_connector_bucket_manager" {
  count   = local.connector_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/storage.admin"
  member  = var.terraform_executor

  condition {
    title       = "asset_connector_bucket_only"
    description = "Manage only the designated asset connector bucket and its objects."
    expression  = "resource.name == ${jsonencode("projects/_/buckets/${var.asset_connector_bucket_name}")} || resource.name.startsWith(${jsonencode("projects/_/buckets/${var.asset_connector_bucket_name}/objects/")})"
  }
}
