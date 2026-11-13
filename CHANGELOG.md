# Changelog

This repository's releases follow Semantic Versioning once tagged.

## [Unreleased]

### Added

- Dedicated federated Python repository readers selected by neutral account aliases (backward-compatible MINOR capability; default disabled).

- Prefix-scoped expiry of noncurrent panel backup versions in the shared bucket, preserving other prefixes and soft deletion.

- Optional dedicated panel backup identity scoped to one managed folder, without storing HMAC secrets in Terraform state.

- `configs/loki-storage`: dedicated Loki service account with `roles/storage.objectAdmin` on the managed folder `loki/cluster/` only.
- `noncurrent_version_expiry` input of `configs/storage`: prefix-scoped deletion of noncurrent versions, applied to `loki/cluster/` after 3 days.
- ADR `docs/adr/loki_gcs_prefix_identity_adr.md` and documentation index.
