# Documentation index

## Storage and access

- [Shared artifacts](shared-artifacts.md): bucket, federation, registry, cost and delivery workflow.
- [Workspace backup storage](workspace-backup-storage.md): managed-folder backup writer.
- [ADR: Loki prefix-scoped identity](adr/loki_gcs_prefix_identity_adr.md): service account, managed folder, credential type and lifecycle for Loki. Implemented in `configs/loki-storage`, `configs/storage` (`noncurrent_version_expiry`), tested in `tests/loki_storage.tftest.hcl`.
