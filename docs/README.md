# Documentation index

## Storage and access

- [ADR: panel backup identity](adr/panel_backup_identity_adr.md): dedicated managed-folder identity and HMAC custody boundary.

- [Shared artifacts](shared-artifacts.md): bucket, federation, registry, cost and delivery workflow.
- [Workspace backup storage](workspace-backup-storage.md): managed-folder backup writer.
- [Personal Wallet signing](wallet-signing.md): optional keyless pass signing and issuer setup.
- [ADR: Wallet signing](adr/wallet_signing_adr.md): dedicated identity, signing-only permission and verification boundary.
- [ADR: Loki prefix-scoped identity](adr/loki_gcs_prefix_identity_adr.md): service account, managed folder, credential type and lifecycle for Loki. Implemented in `configs/loki-storage`, `configs/storage` (`noncurrent_version_expiry`), tested in `tests/loki_storage.tftest.hcl`.
