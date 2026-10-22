mock_provider "google" {}

variables {
  project_id           = "example-project"
  artifact_bucket_name = "example-private-artifacts"
}

override_resource {
  target          = google_service_account.loki
  override_during = plan
  values = {
    email = "loki-cluster-storage@example-project.iam.gserviceaccount.com"
  }
}

run "loki_identity_is_folder_scoped" {
  command = plan

  module {
    source = "./configs/loki-storage"
  }

  assert {
    condition     = google_storage_managed_folder.loki[0].name == "loki/cluster/" && google_storage_managed_folder.loki[0].deletion_policy == "ABANDON" && !google_storage_managed_folder.loki[0].force_destroy
    error_message = "The Loki managed folder must never be deleted by Terraform, so disabling or moving it leaves the objects."
  }

  assert {
    condition     = google_storage_managed_folder_iam_member.loki_object_admin[0].role == "roles/storage.objectAdmin" && google_storage_managed_folder_iam_member.loki_object_admin[0].managed_folder == "loki/cluster/"
    error_message = "Object administration must be granted only at the managed folder."
  }

  assert {
    condition     = google_storage_managed_folder_iam_member.loki_object_admin[0].member == "serviceAccount:loki-cluster-storage@example-project.iam.gserviceaccount.com"
    error_message = "The folder grant must name only the dedicated service account."
  }
}

run "loki_module_has_one_service_account_and_only_folder_iam" {
  command = plan

  module {
    source = "./configs/loki-storage"
  }

  assert {
    condition     = length(google_service_account.loki) == 1 && length(google_storage_managed_folder_iam_member.loki_object_admin) == 1
    error_message = "Exactly one dedicated service account and one folder grant are expected."
  }
}

run "empty_path_disables_loki_identity" {
  command = plan

  module {
    source = "./configs/loki-storage"
  }

  variables {
    loki_storage_folder_path = ""
  }

  assert {
    condition     = length(google_service_account.loki) == 0 && length(google_storage_managed_folder.loki) == 0 && length(google_storage_managed_folder_iam_member.loki_object_admin) == 0
    error_message = "An empty path must create no identity and no grant."
  }
}

run "rejects_path_outside_loki_namespace" {
  command = plan

  module {
    source = "./configs/loki-storage"
  }

  variables {
    loki_storage_folder_path = "dvc/gpu-idle-lab/"
  }

  expect_failures = [var.loki_storage_folder_path]
}

run "rejects_missing_trailing_slash" {
  command = plan

  module {
    source = "./configs/loki-storage"
  }

  variables {
    loki_storage_folder_path = "loki/cluster"
  }

  expect_failures = [var.loki_storage_folder_path]
}

run "lifecycle_rule_is_prefix_scoped_to_noncurrent_versions" {
  command = plan

  module {
    source = "./configs/storage"
  }

  variables {
    artifact_bucket_location = "example-region1"
    artifact_bucket_writers  = {}
    noncurrent_version_expiry = {
      loki = {
        prefix = "loki/cluster/"
        days   = 3
      }
    }
  }

  assert {
    condition     = length(google_storage_bucket.shared_artifacts.lifecycle_rule) == 1 && alltrue([for rule in google_storage_bucket.shared_artifacts.lifecycle_rule : alltrue([for action in rule.action : action.type == "Delete"]) && alltrue([for cond in rule.condition : cond.with_state == "ARCHIVED" && length(cond.matches_prefix) == 1 && contains(cond.matches_prefix, "loki/cluster/") && cond.days_since_noncurrent_time == 3])])
    error_message = "The rule must delete only archived versions under the Loki prefix."
  }
}

run "no_lifecycle_rule_by_default" {
  command = plan

  module {
    source = "./configs/storage"
  }

  variables {
    artifact_bucket_location = "example-region1"
    artifact_bucket_writers  = {}
  }

  assert {
    condition     = length(google_storage_bucket.shared_artifacts.lifecycle_rule) == 0
    error_message = "The bucket must have no lifecycle rule unless one is requested."
  }
}

run "rejects_bucket_wide_lifecycle_rule" {
  command = plan

  module {
    source = "./configs/storage"
  }

  variables {
    artifact_bucket_location = "example-region1"
    artifact_bucket_writers  = {}
    noncurrent_version_expiry = {
      all = {
        prefix = ""
        days   = 3
      }
    }
  }

  expect_failures = [var.noncurrent_version_expiry]
}
