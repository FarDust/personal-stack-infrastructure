mock_provider "google" {}

variables {
  project_id              = "example-project"
  region                  = "us-west1"
  zone                    = "us-west1-b"
  bucket_name             = "example-assets"
  cors_origin             = "https://app.example.test"
  tailscale_version       = "1.0.0"
  tailscale_sha256        = "0000000000000000000000000000000000000000000000000000000000000000"
  nginx_version           = "1.0.0"
  nginx_deb_sha256        = "0000000000000000000000000000000000000000000000000000000000000000"
  nginx_common_deb_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
  tenants = {
    example-app = { writers = ["user:operator@example.com"] }
  }
  billing_account_id = "example-billing"
}

run "private_bucket_and_scoped_identity" {
  command = plan
  module {
    source = "./configs/asset-connector"
  }
  assert {
    condition     = google_storage_bucket.assets.public_access_prevention == "enforced" && google_storage_bucket.assets.uniform_bucket_level_access && !google_storage_bucket.assets.versioning[0].enabled
    error_message = "The asset bucket must be private, uniformly controlled and unversioned."
  }
  assert {
    condition     = google_storage_bucket_iam_member.connector_reader.role == "roles/storage.objectViewer"
    error_message = "The VM identity may only read objects."
  }
}

run "tenant_writers_are_prefix_scoped" {
  command = plan
  module {
    source = "./configs/asset-connector"
  }
  assert {
    condition     = length(google_storage_bucket_iam_member.tenant_writer) == 2 && alltrue([for m in google_storage_bucket_iam_member.tenant_writer : m.role == "roles/storage.objectUser" && length(m.condition) == 1])
    error_message = "Every tenant writer grant must carry a prefix condition."
  }
}

run "reject_public_tenant_writer" {
  command = plan
  module {
    source = "./configs/asset-connector"
  }
  variables {
    tenants = {
      example-app = { writers = ["allUsers"] }
    }
  }
  expect_failures = [var.tenants]
}

run "ipv6_only_free_tier_vm" {
  command = plan
  module {
    source = "./configs/asset-connector"
  }
  assert {
    condition     = google_compute_instance.connector.machine_type == "e2-micro" && length(google_compute_instance.connector.network_interface[0].access_config) == 0
    error_message = "The VM must be an e2-micro without an external IPv4 address."
  }
  assert {
    condition     = google_compute_subnetwork.connector.ipv6_access_type == "EXTERNAL" && google_compute_subnetwork.connector.private_ip_google_access
    error_message = "The subnet must be dual-stack with external IPv6 and Private Google Access."
  }
  assert {
    condition     = alltrue([for a in google_compute_firewall.tailscale_direct.allow : a.protocol == "udp" && a.ports == tolist(["41641"])])
    error_message = "Only the Tailscale WireGuard port may be opened."
  }
}

run "reject_region_outside_free_tier" {
  command = plan
  module {
    source = "./configs/asset-connector"
  }
  variables {
    region = "southamerica-west1"
  }
  expect_failures = [var.region]
}

run "reject_wildcard_origin" {
  command = plan
  module {
    source = "./configs/asset-connector"
  }
  variables {
    cors_origin = "https://*.example.test"
  }
  expect_failures = [var.cors_origin]
}
