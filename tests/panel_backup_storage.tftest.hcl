mock_provider "google" {}

variables {
  enabled     = true
  project_id  = "example-project"
  bucket_name = "example-private-bucket"
  folder_path = "12345678-1234-1234-1234-123456789abc/"
}

run "dedicated_identity_is_scoped_to_one_folder" {
  command = plan
  module {
    source = "./configs/panel-backup-storage"
  }

  assert {
    condition     = length(google_service_account.panel_backup) == 1 && length(google_storage_managed_folder_iam_member.panel_backup) == 1 && google_storage_managed_folder.panel_backup[0].name == var.folder_path
    error_message = "A dedicated identity must have exactly one managed-folder grant."
  }
  assert {
    condition     = google_storage_managed_folder.panel_backup[0].deletion_policy == "PREVENT" && !google_storage_managed_folder.panel_backup[0].force_destroy
    error_message = "The managed folder must be protected from deletion."
  }
  assert {
    condition = google_project_iam_custom_role.panel_backup[0].permissions == toset([
      "storage.objects.create", "storage.objects.get", "storage.objects.delete", "storage.objects.list",
      "storage.multipartUploads.create", "storage.multipartUploads.abort", "storage.multipartUploads.listParts"
    ])
    error_message = "Only the approved object and multipart permissions may be granted."
  }
}

run "disabled_creates_nothing" {
  command = plan
  module {
    source = "./configs/panel-backup-storage"
  }
  variables {
    enabled     = false
    folder_path = ""
  }
  assert {
    condition     = length(google_service_account.panel_backup) == 0 && length(google_storage_managed_folder.panel_backup) == 0 && length(google_storage_managed_folder_iam_member.panel_backup) == 0
    error_message = "Disabled configuration must create no identity, folder, or grant."
  }
}

run "rejects_unscoped_folder" {
  command = plan
  module {
    source = "./configs/panel-backup-storage"
  }
  variables {
    folder_path = "backups/"
  }
  expect_failures = [var.folder_path]
}

run "rejects_enabled_empty_folder" {
  command = plan
  module {
    source = "./configs/panel-backup-storage"
  }
  variables {
    folder_path = ""
  }
  expect_failures = [google_storage_managed_folder.panel_backup]
}

run "provision_before_revocation" {
  command = apply
  module {
    source = "./configs/panel-backup-storage"
  }
}

run "revocation_retains_folder_and_disables_identity" {
  command = plan
  module {
    source = "./configs/panel-backup-storage"
  }
  variables {
    grant_enabled = false
  }
  assert {
    condition     = google_service_account.panel_backup[0].disabled && length(google_storage_managed_folder_iam_member.panel_backup) == 0 && length(google_storage_managed_folder.panel_backup) == 1 && length(google_project_iam_custom_role.panel_backup) == 1
    error_message = "Revocation must disable the account and remove its grant while retaining protected resources."
  }
}
