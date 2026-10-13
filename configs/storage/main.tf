resource "google_storage_bucket" "shared_artifacts" {
  project  = var.project_id
  name     = var.artifact_bucket_name
  location = var.artifact_bucket_location

  lifecycle {
    prevent_destroy = true
  }

  force_destroy               = false
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  # Prefix-scoped cleanup of noncurrent versions; as decided in docs/adr/loki_gcs_prefix_identity_adr.md
  dynamic "lifecycle_rule" {
    for_each = var.noncurrent_version_expiry
    content {
      action {
        type = "Delete"
      }
      condition {
        with_state                 = "ARCHIVED"
        matches_prefix             = [lifecycle_rule.value.prefix]
        days_since_noncurrent_time = lifecycle_rule.value.days
      }
    }
  }

  labels = {
    app     = "infra"
    purpose = "data"
  }
}

resource "google_storage_bucket_iam_member" "artifact_writer" {
  # Only stable, non-secret aliases are exposed as resource keys, never identities.
  for_each = nonsensitive(toset(keys(var.artifact_bucket_writers)))
  bucket   = google_storage_bucket.shared_artifacts.name
  role     = "roles/storage.objectUser"
  member   = var.artifact_bucket_writers[each.key]
}
