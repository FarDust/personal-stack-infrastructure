mock_provider "google" {}

variables {
  project_id           = "example-project"
  artifact_bucket_name = "example-private-artifacts"
  workspace_backup_folder_paths = {
    first  = "backups/workspaces/example-a/"
    second = "backups/workspaces/example-b/"
  }
}

run "workspace_backup_writer_is_folder_scoped" {
  command = plan

  module {
    source = "./configs/workspace-backup-storage"
  }

  assert {
    condition     = length(google_storage_managed_folder.workspace_backup) == 2 && alltrue([for folder in values(google_storage_managed_folder.workspace_backup) : folder.deletion_policy == "PREVENT" && !folder.force_destroy])
    error_message = "Workspace backup managed folders must be protected from Terraform deletion."
  }

  assert {
    condition     = length(google_storage_managed_folder_iam_member.workspace_backup_reader) == 2 && alltrue([for grant in values(google_storage_managed_folder_iam_member.workspace_backup_reader) : grant.role == "roles/storage.objectViewer"])
    error_message = "The writer must receive reader access only at each managed backup folder."
  }

  assert {
    condition     = length(google_storage_managed_folder_iam_member.workspace_backup_creator) == 2 && alltrue([for grant in values(google_storage_managed_folder_iam_member.workspace_backup_creator) : grant.role == "roles/storage.objectCreator"])
    error_message = "The writer must receive creator access only at each managed backup folder."
  }

  assert {
    condition     = google_project_iam_custom_role.workspace_backup_lock_deleter[0].permissions == toset(["storage.objects.delete"]) && alltrue([for grant in values(google_storage_bucket_iam_member.workspace_backup_lock_deleter) : startswith(grant.condition[0].expression, "resource.type == \"storage.googleapis.com/Object\" && resource.name.startsWith(\"projects/_/buckets/example-private-artifacts/objects/backups/workspaces/") && endswith(grant.condition[0].expression, "/locks/\")")])
    error_message = "Only the custom delete permission may be granted, and only to Restic lock prefixes."
  }
}

run "rejects_unscoped_or_incomplete_workspace_backup_paths" {
  command = plan

  module {
    source = "./configs/workspace-backup-storage"
  }

  variables {
    workspace_backup_folder_paths = {
      only = "backups/workspaces/example-a/"
    }
  }

  expect_failures = [var.workspace_backup_folder_paths]
}
