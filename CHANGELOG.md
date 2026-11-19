# Changelog

This repository's releases follow Semantic Versioning once tagged.

## [Unreleased]

### Added

- `tools/node-operator-access`: idempotent `atelo`/`overseer` operator-account bootstrap with sshd simulation, backup and rollback for nodes outside Terraform. `apply` takes `--overseer-public-key-file` and `--overseer-private-key-file` (the overseer key pair; the sudo account's key comes from the ssh alias), reverts through the CLI when the post-apply `overseer` login fails, and `revert --backup-dir` removes an `overseer` account it created.

### Fixed

- `sshd -T` checks in `tools/node-operator-access` and the asset connector startup script capture the output before `grep`: under `set -o pipefail` an early-exiting `grep -q` made `sshd` die of SIGPIPE (exit 141), so every check failed and the drop-in was always rolled back (first seen on an Oracle micro node, 2026-11-19, reverted cleanly).

- `configs/asset-connector`: optional key-only `overseer` operator account with passwordless sudo, restricted by sshd to one tailnet source address (backward-compatible MINOR capability; default disabled). ADR `docs/adr/asset_connector_overseer_access_adr.md`.

- Dedicated federated Python repository readers selected by neutral account aliases (backward-compatible MINOR capability; default disabled).

- Prefix-scoped expiry of noncurrent panel backup versions in the shared bucket, preserving other prefixes and soft deletion.

- Optional dedicated panel backup identity scoped to one managed folder, without storing HMAC secrets in Terraform state.

- `configs/loki-storage`: dedicated Loki service account with `roles/storage.objectAdmin` on the managed folder `loki/cluster/` only.
- `noncurrent_version_expiry` input of `configs/storage`: prefix-scoped deletion of noncurrent versions, applied to `loki/cluster/` after 3 days.
- ADR `docs/adr/loki_gcs_prefix_identity_adr.md` and documentation index.
