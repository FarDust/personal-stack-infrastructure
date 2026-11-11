# Free-tier asset connector: private bucket plus an IPv6-only e2-micro on the tailnet.
# Decision record: docs/adr/asset_connector_adr.md

locals {
  labels = {
    app             = "asset-connector"
    purpose         = "assets"
    asset-connector = "true"
  }
}

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "billingbudgets" {
  count              = var.billing_account_id == null ? 0 : 1
  project            = var.project_id
  service            = "billingbudgets.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_storage_bucket" "assets" {
  project                     = var.project_id
  name                        = var.bucket_name
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  # Assets are a reproducible copy of the origin, so rollback may delete them.
  force_destroy = true
  labels        = local.labels

  versioning {
    enabled = false
  }

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}

resource "google_service_account" "connector" {
  project      = var.project_id
  account_id   = "asset-connector"
  display_name = "Asset connector VM"
  description  = "Reads the private asset bucket and the Tailscale auth-key secret; no keys."
}

resource "google_storage_bucket_iam_member" "connector_reader" {
  bucket = google_storage_bucket.assets.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.connector.email}"
}

# One writer identity per tenant, limited to its own prefix; no keys are created.
resource "google_service_account" "tenant_writer" {
  for_each     = nonsensitive(toset(keys(var.tenants)))
  project      = var.project_id
  account_id   = "asset-w-${each.key}"
  display_name = "Asset writer ${each.key}"
  description  = "Writes only under its own prefix of the asset bucket; no keys."
}

locals {
  tenant_writers = merge(
    { for t in nonsensitive(keys(var.tenants)) : "${t}/own" => { tenant = t, member = "serviceAccount:${google_service_account.tenant_writer[t].email}" } },
    merge([for t in nonsensitive(keys(var.tenants)) : { for i, w in var.tenants[t].writers : "${t}/extra-${i}" => { tenant = t, member = w } }]...)
  )
}

resource "google_storage_bucket_iam_member" "tenant_writer" {
  for_each = nonsensitive(toset(keys(local.tenant_writers)))
  bucket   = google_storage_bucket.assets.name
  role     = "roles/storage.objectUser"
  member   = local.tenant_writers[each.key].member

  condition {
    title      = "prefix-${local.tenant_writers[each.key].tenant}"
    expression = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.assets.name}/objects/${local.tenant_writers[each.key].tenant}/\")"
  }
}

resource "google_secret_manager_secret" "tailscale_authkey" {
  project   = var.project_id
  secret_id = "asset-connector-tailscale-authkey"
  labels    = local.labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.secretmanager]
}

# The key arrives through a sensitive workspace variable and is written as a write-only
# secret version, so it never lands in Terraform state. Until it exists the VM waits.
resource "google_secret_manager_secret_version" "tailscale_authkey" {
  count                  = var.tailscale_authkey == "" ? 0 : 1
  secret                 = google_secret_manager_secret.tailscale_authkey.id
  secret_data_wo         = var.tailscale_authkey
  secret_data_wo_version = 1
}

resource "google_secret_manager_secret_iam_member" "connector_authkey" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.tailscale_authkey.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.connector.email}"
}

resource "google_compute_network" "connector" {
  project                 = var.project_id
  name                    = "asset-connector"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "connector" {
  project                  = var.project_id
  name                     = "asset-connector"
  region                   = var.region
  network                  = google_compute_network.connector.id
  ip_cidr_range            = "10.201.0.0/28"
  stack_type               = "IPV4_IPV6"
  ipv6_access_type         = "EXTERNAL"
  private_ip_google_access = true
}

# Only the WireGuard port of the tailnet client, over IPv6, for direct paths. HTTPS is never exposed.
resource "google_compute_firewall" "tailscale_direct" {
  project   = var.project_id
  name      = "asset-connector-tailscale-direct"
  network   = google_compute_network.connector.name
  direction = "INGRESS"

  source_ranges = ["::/0"]
  target_tags   = ["asset-connector"]

  allow {
    protocol = "udp"
    ports    = ["41641"]
  }
}

resource "google_compute_instance" "connector" {
  project                   = var.project_id
  name                      = "asset-connector"
  zone                      = var.zone
  machine_type              = "e2-micro"
  allow_stopping_for_update = true
  tags                      = ["asset-connector"]
  labels                    = local.labels

  boot_disk {
    initialize_params {
      image  = "debian-cloud/debian-12"
      size   = 10
      type   = "pd-standard"
      labels = local.labels
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.connector.id
    stack_type = "IPV4_IPV6"

    # IPv6 only: no access_config, so no billable external IPv4 address.
    ipv6_access_config {
      network_tier = "PREMIUM"
    }
  }

  service_account {
    email  = google_service_account.connector.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    preemptible       = false
    automatic_restart = true
  }

  metadata = {
    block-project-ssh-keys = "true"
    asset-bucket           = google_storage_bucket.assets.name
    asset-cors-origin      = var.cors_origin
    ts-tag                 = var.tailscale_tag
    ts-version             = var.tailscale_version
    ts-sha256              = var.tailscale_sha256
    caddy-version          = var.caddy_version
    caddy-sha512           = var.caddy_sha512
    rclone-version         = var.rclone_version
    rclone-sha256          = var.rclone_sha256
    asset-tenants          = join(",", nonsensitive(sort(keys(var.tenants))))
    ts-authkey-secret      = google_secret_manager_secret.tailscale_authkey.secret_id
  }

  metadata_startup_script = file("${path.module}/startup.sh")

  depends_on = [
    google_storage_bucket_iam_member.connector_reader,
    google_secret_manager_secret_iam_member.connector_authkey,
  ]
}

resource "google_billing_budget" "connector" {
  count           = var.billing_account_id == null ? 0 : 1
  billing_account = var.billing_account_id
  display_name    = "asset-connector"

  budget_filter {
    projects = ["projects/${var.project_id}"]
    labels = {
      asset-connector = "true"
    }
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 1.0
  }

  depends_on = [google_project_service.billingbudgets]
}

resource "google_monitoring_notification_channel" "egress" {
  count        = var.notification_email == null ? 0 : 1
  project      = var.project_id
  display_name = "asset-connector egress"
  type         = "email"
  labels = {
    email_address = var.notification_email
  }
}

# Egress from the VM is the metered path (1 GiB per month free). Cache hits do not shrink it,
# so the guard watches the bytes the VM sends and the VM publishes its own monthly total.
resource "google_monitoring_alert_policy" "egress" {
  project      = var.project_id
  display_name = "asset-connector daily egress"
  combiner     = "OR"
  user_labels  = local.labels

  conditions {
    display_name = "VM sent bytes per day"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/network/sent_bytes_count\" AND resource.type=\"gce_instance\" AND metadata.user_labels.asset-connector=\"true\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.daily_egress_alert_mib * 1048576
      duration        = "0s"

      aggregations {
        alignment_period     = "86400s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = [for c in google_monitoring_notification_channel.egress : c.id]
}
