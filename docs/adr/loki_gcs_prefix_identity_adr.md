# ADR: Prefix-scoped Google identity for Loki object storage

Status: accepted, 2026-10-13. Implemented by `configs/loki-storage` and the `noncurrent_version_expiry` input of `configs/storage`.

## Context

Grafana Loki on the homelab Swarm keeps chunks and its TSDB index on a node-local volume and needs a durable object store. The shared artifact bucket (regional, uniform bucket-level access, public-access prevention enforced, versioning on, 7-day soft delete) is the intended target under the object-name prefix `loki/cluster/`. Loki needs to create, read, list and delete objects there (chunks, index files, compactor deletion). The only existing cluster credential with bucket access, the rclone volume identity, can read and delete every prefix, including workspace backups. An internet-fed log parser must not hold that key.

## Decision

1. Create a dedicated service account (`loki-cluster-storage`, overridable).
2. Create the managed folder `loki/cluster/` and grant `roles/storage.objectAdmin` to that account **at the managed folder** with an additive IAM member. No bucket-level, project-level or custom-role grant is made.
3. Add a bucket lifecycle rule scoped by `matchesPrefix` to `loki/cluster/` that deletes `ARCHIVED` (noncurrent) versions 3 days after they become noncurrent.
4. Deliver the credential as one service-account JSON key created outside Terraform and placed only in the cluster Docker secret `loki_gcs_sa_key`.

## Why a managed folder instead of an IAM condition

Managed folders are first-class IAM resources. A role granted on one applies to the objects whose names start with the folder path, including listing with that prefix, and the grant cannot reach other prefixes. An object-role IAM condition on `resource.name.startsWith(".../objects/loki/cluster/")` also limits get, create and delete, but `storage.objects.list` is evaluated against the bucket resource, so a prefix condition cannot authorize listing; the repository already uses a condition only for the delete-only Restic lock role, where listing is not needed. Loki's compactor and index listing require list, so the managed folder is the mechanism that actually enforces the boundary. The intended post-apply test (not yet run when this ADR was written; its result is recorded in the PR and the Verification section) checks that writes, reads, listing and deletes succeed under `loki/cluster/` and are denied under other prefixes and on the bucket root.

## Credential type: static key, not workload identity federation

Federation through the `gcp-workload-federation` Keycloak realm needs a subject-token refresher for each Swarm service, and the realm is behind its production gates. A token-refresher dependency recently failed for 9 hours for Grafana to Loki on this cluster; making durable log storage depend on a refresher would turn that into data loss risk. A key for a service account with a single folder-scoped role has a bounded blast radius: it cannot reach other prefixes, cannot administer IAM or the bucket and cannot be used outside the folder. The key is created out of band (not in Terraform state, which would also hold it in plain text), streamed into a Docker secret over SSH standard input, never written to disk or a repository, labeled, and rotated by creating a new version, switching the service, deleting the old secret and deleting the old key id. Revisit when the federation realm clears its gates.

## Lifecycle and retention

Loki's compactor deletes expired chunks, which versioning turns into noncurrent versions that soft delete then retains for another 7 days. Without a rule the bucket keeps all of them. The rule deletes noncurrent versions under `loki/cluster/` after 3 days (`loki_noncurrent_version_days`), leaving a short recovery window plus the 7-day soft delete. It never touches live objects or other prefixes. The bucket had no lifecycle rules when this was written, so the in-place update replaces nothing. Cost impact is below a few cents per month for the roughly 2 GiB data set.

## Alternatives rejected

- Reusing the rclone volume identity: reaches every prefix.
- IAM condition on `resource.name` at bucket level: cannot authorize list, see above.
- Key created by `google_service_account_key`: stores the private key in Terraform state.
- Federation with a refresher: fragile for storage on the data path.
- A bucket per service: a new bucket for a few gigabytes adds management and cost with no stronger boundary than the folder.

## Consequences and residual risk

- The folder `loki/cluster/` also contains the scheduled Loki archive (`loki/cluster/backup/`) written by the rclone volume identity. The Loki identity can overwrite or delete those objects; versioning plus soft delete keep a recovery window and the lifecycle rule applies to them. Move Loki's data to a narrower sub-prefix (for example `loki/cluster/data/`) in its configuration to avoid reading or deleting archives (IAM does not enforce that sub-prefix, since the folder and the lifecycle rule cover all of `loki/cluster/`); this ADR deliberately keeps the folder at the requested `loki/cluster/` rather than assuming a layout.
- The managed folder uses `deletion_policy = "ABANDON"`: Terraform never deletes the folder or its objects. Setting `loki_storage_folder_path` to an empty value, or changing it, removes the folder and its IAM member from Terraform management and revokes the identity's access while the objects stay in the bucket. A `PREVENT` policy would make that decommissioning apply fail.
- The folder takes its bucket name from `module.storage`, so a fresh deployment creates the bucket first.
- A leaked key remains valid until deleted. Rotate on any exposure and at least yearly.

## Verification

Mocked Terraform tests (`tests/loki_storage.tftest.hcl`) assert folder-only objectAdmin, the dedicated principal, rejection of paths outside `loki/`, a prefix-scoped archived-version rule and no rule by default. After the reviewed apply, impersonation of the account and the delivered key is used to check create, read, list and delete under `loki/cluster/` and denial on `dvc/`, `loki/other/` and the bucket root. Results are recorded in the PR once executed.
