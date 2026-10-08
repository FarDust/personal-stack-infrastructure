# Workspace Backup Storage

`configs/workspace-backup-storage` creates a dedicated writer identity and two protected Cloud Storage managed folders. Folder paths are sensitive Terraform Cloud input, not repository configuration.

## Contract

- `workspace_backup_folder_paths` contains exactly two values under `backups/workspaces/`, with a trailing slash.
- The writer receives `roles/storage.objectViewer` and `roles/storage.objectCreator` on each managed folder.
- A project custom role grants only `storage.objects.delete`; conditional project bindings restrict it to each folder's `locks/` prefix.
- The module never creates a service-account key. Key custody and runner configuration remain external to Terraform state.

## Operating Gates

- Verify an actual restore before scheduling backups.
- Use a separate, explicitly approved identity for destructive retention or prune maintenance; the writer cannot delete backup snapshots or packs.
- Verify allowed write, read, and prefix-list operations as the writer, plus denied deletion outside `locks/`, before runner adoption.
