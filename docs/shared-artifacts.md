# Shared artifact storage and delivery

## Configuration

The root composes the private artifact bucket through `configs/storage`.
The bucket's name is supplied by the sensitive Terraform Cloud variable
`artifact_bucket_name`; there is no hardcoded deployment name.
The independently configurable `artifact_bucket_location` selects the bucket
region without changing the provider's existing `gcp_region` setting.

Choose deployment locations using workload locality, service availability, and
cost. The public cost fixture models one regional storage scenario; it is not a
record of deployed resources, personal location, or measured usage. Actual
deployment identifiers and operational receipts belong in private configuration
and records, not in this document.

The bucket is shared by agent and cluster workloads, not owned by one DVC project.
Use `gs://<artifact_bucket_name>/dvc/<project-slug>/` for each DVC project.
Other artifacts use separately owned
project prefixes such as `artifacts/<project-slug>/`. These are object-name
prefixes, not provisioned folders or independent IAM boundaries. Keep deletion
and garbage collection scoped to the owning project; never run them against the
shared bucket root.

`github_repository_owner` is required and sensitive, with no default. The
federation provider restricts its mapped repository owner to that input. Its
expression retains the existing trailing newline to avoid a value-only diff.
An existing non-sensitive state value can produce a sensitivity-only planned
update: compare raw before/after values privately, rather than interpreting the
UI's replacement of visible text with a hidden value as removal of the condition.

## Shared federation module contract

The root consumes the shared `github-identity-federation` module directly from
`terraform-infrastructure`, pinned to immutable revision
`132e099a43d302b472863e110f11338833503eb6`, published as signed release
[`v0.1.0`](https://github.com/FarDust/terraform-infrastructure/releases/tag/v0.1.0).
This source pin is not evidence that a consumer apply has occurred. The source is available at
<https://github.com/FarDust/terraform-infrastructure/tree/132e099a43d302b472863e110f11338833503eb6/modules/github-identity-federation>.

This consumer uses the shared module's modern default: one additive IAM member
per allowed repository, without authoritative role bindings. Multiple repositories
are supported. The required sensitive owner condition retains its exact expression
and trailing newline. Existing account names that do not end in `-fa` keep the
`-federated-user` suffix; names already ending in `-fa` are used unchanged.

The library's explicit legacy compatibility tests remain separate from the
consumer's modern-default tests. Modern composition tests assert zero bindings,
one member per repository, owner-condition sensitivity, and account naming.

### Image publishers (GitHub Actions to the private registry)

A GitHub repository that builds images for `cluster-internal-images` gets its own
federated user, so it never shares the project-wide `secrets` account. Configure
that account in the non-secret `federated_github_users` Terraform Cloud variable
with one exact `owner/repository`, then reference its key from the
`github_image_publisher` object together with the immutable numeric repository
ID, dedicated provider ID, caller workflow path, reusable trusted workflow path,
and phased-cutover flag. Root composition verifies the one-repository contract.
Keep `retain_general_provider_access = true` while adding and canarying the
dedicated provider; set it to `false` only in a later reviewed change after the
real publication canary succeeds.

The dedicated provider admits only a `push` from the configured immutable
repository when `.github/workflows/image.yml` runs at the caller's exact ref and
the authenticated reusable job comes from `.github/workflows/publish-image.yml`
at `refs/heads/main`. The ref must be `refs/heads/main` or a stable
`vMAJOR.MINOR.PATCH` tag with no leading zeros, prerelease suffix, or build
metadata. Its constant
`attribute.trust_profile` mapping is absent from the general provider, and the
publisher service account trusts only the corresponding `image-publisher-v1`
principal set. See the
[architecture decision](adr/image-publisher-federation.md) for the boundary and
alternatives.

Grant push access only through the additive `cluster_artifact_registry_writers`
Terraform Cloud variable, as `serviceAccount:<federated account email>`; this
yields one repository-level `roles/artifactregistry.writer` member on
`cluster-internal-images` and nothing at project or organization level. Leave
`cluster_artifact_registry_readers` alone: pulling is a separate identity and a
separate change. The account email does not exist until the federated user is
applied, so deliver this in two reviewed applies: first the federated user, then
the writer variable. Never create a service-account key.

Image-publisher consumers read the private values from the sensitive root outputs
`github_image_publisher_workload_identity_provider` and
`federated_github_service_accounts` and store them as repository variables
(`GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`) for
`google-github-actions/auth` with `id-token: write`. Other GitHub consumers retain
the general `github_workload_identity_provider` output. Keep all values out of
this public repository.

The cutover is two reviewed phases. Phase one creates the dedicated provider and
member while retaining the general-provider member; its full speculative plan
must contain no destroy. Update the repository variable to the dedicated provider
and require a successful real publication through the trusted reusable workflow.
Only then may phase two disable `retain_general_provider_access` and remove the
broad member. A blocked or unverified canary keeps phase two on hold.

### One-time state adoption

Existing authoritative bindings must be forgotten, not destroyed. Supply the
sensitive `federation_member_imports` map privately with an operator alias mapped
to `account_key`, `repository`, and the provider's existing-member import `id`.
Routing keys appear in Terraform addresses; import IDs remain sensitive.
New deployments use the empty default and create normal additive members.

Before transferring ownership, record the current remote state version and live
IAM policy, verify unchanged service-account naming, and finish source review/CI.
A transitional full plan may show the old binding's deletion: never apply it.
With auto-apply disabled and no active or confirmable stale run, initialize the
correct cloud backend, dry-run the exact indexed `terraform state rm` address,
require exactly one match, then remove that association using normal locking.
Do not remove the grant through an IAM API or edit raw state JSON.

Verify that only the binding association disappeared and the live policy stayed
unchanged. A fresh full speculative plan, followed by the merged revision's normal
plan, must show only the expected existing-member import, with no resource
creation, value-changing update, replacement, or destruction. Importing an
unmarked value into a sensitive configuration can show a metadata-only update;
compare raw before/after values privately to distinguish it from an IAM change.
Apply that reviewed import, clear
the private import map, then verify modern state, identical live permissions,
and a full zero-change plan. On failure, inspect the current state before retrying;
do not blindly restore an older snapshot over subsequent writes.

This explicit transfer is needed because the pinned library still declares its
zero-instance compatibility binding resource. Terraform rejects `removed` or
whole-resource `moved` declarations that conflict with that declaration. Exact
deployed repository identifiers stay out of public migration HCL.

## Access and retention

If the existing Terraform runtime lacks storage provisioning permission, use
the separately reviewed [storage bootstrap](../bootstrap/storage/README.md).
It grants creation-only project permission plus management restricted to the
designated bucket; the main configuration remains responsible for the bucket
and consumer access. Keep bootstrap credentials temporary and outside source.

The same bootstrap root is the sole Terraform state owner for the private
Artifact Registry Docker repository and must complete before the main root is
planned or applied. It creates the validated configured
repository, including deletion protection, because repository creation is
authorized at the location parent and cannot be narrowed to an exact repository
name. The main root reads that exact repository and manages only additive
repository-level writer and reader memberships. It does not manage repository
lifecycle.

The main Terraform executor receives an additive repository-scoped custom role
with only `artifactregistry.repositories.get`,
`artifactregistry.repositories.getIamPolicy`, and
`artifactregistry.repositories.setIamPolicy`, which permits that lookup and
additive IAM maintenance. Do not grant it a project-level Artifact Registry
role, including `roles/artifactregistry.admin`. Use a short-lived bootstrap
credential only in the separate reviewed bootstrap workspace and remove it after
the terminal result; keep refresh credentials and service-account keys out of
source and workspace variables.

The bucket enforces public-access prevention and uniform bucket-level access,
enables versioning, prevents Terraform destruction, and disables force-destroy.
Approved identities are supplied through sensitive `artifact_bucket_writers`.
The module grants additive bucket-level `roles/storage.objectUser` memberships,
not project-wide storage administration or public access. Only non-secret map
aliases are exposed as resource keys; principal values remain sensitive.
DVC uses existing approved Application Default Credentials or managed cluster
credentials. No new static service-account key is created or distributed. The
existing federation accounts are not implicitly authorized for storage,
and these CI workflows do not upload DVC data. Verify each consuming identity's
access after provisioning; IAM configuration is not a credential-distribution mechanism.

No automatic object expiration is introduced. Stored bytes include live objects,
noncurrent versions, and soft-deleted objects; the local artifact quota is not a
remote-storage quota. Review retained bytes before uploads and agree a retention
policy before adding lifecycle deletion.

## Projected monthly cost

`infracost-usage.yml` describes initial provisioning: an empty bucket with no
scheduled upload, migration, request, or download workload. Its initial recurring
usage estimate is zero, not a forecast of future operation. One-off management
requests can still incur small charges. This change does not move existing data.

The separate `cost/active-example.yml` is a nonzero sensitivity example that
checks price coverage, not an approved allocation or an account forecast:

| Item | Quantity | Rate | Monthly USD |
| --- | ---: | ---: | ---: |
| Illustrative regional Standard storage | 50 GiB | 0.03/GiB-month | 1.50 |
| Class A operations | 100,000 | 0.05/10,000 | 0.50 |
| Class B operations | 1,000,000 | 0.004/10,000 | 0.40 |
| Worldwide egress modeled for artifact downloads | 100 GiB | 0.12/GiB | 12.00 |
| Total | | | **14.40** |

These quantities are a reproducible pricing fixture, not observed consumption.
Use the Cloud Billing catalog and Infracost to verify rates for the configured
region; keep deployment-specific pricing receipts private. This example assumes
no free-tier discount. Reassess quantities and rates as workloads change.

The repository's service-account, IAM and managed-folder access resources add no
recurring service charge. Infracost can classify those identity/access-control
types as either no-price or unsupported resources; the public fixture allowlists
only those known no-monthly-charge resource types while still requiring the
expected bucket resource and a positive price for the populated example under
the same allowlist. HCP Terraform's incomplete estimate is not used as the cost
gate. Both baseline and head use their checked-in usage model when one exists.
Public PR CI uses a synthetic region and usage inputs only. This checks pricing
coverage, not the actual deployment budget or location, and it does not assert a
realistic bill.

Before deployment, a trusted operator evaluates `cost/budget.jq` from the
reviewed immutable revision using the actual workspace location, incremental
usage, current account forecast, and budget. Its billing period must identify
the current month. Keep real financial inputs out of PR-controlled jobs and
scripts; refresh them from authorized billing evidence privately. Keep billing
exports and account-specific observations outside this repository.
The cost-admission function has synthetic regression cases for empty usage,
remaining budget, excess spending, missing prices, incomplete coverage and stale
periods. A forecast remains uncertain, is not an invoice, and is not a hard cap.

Before onboarding data, replace initial-zero quantities with measured or bounded
unique payloads, object counts, write/delete frequency, and downloads per client.
DVC deduplicates identical content, but noncurrent generations and soft-deleted
bytes remain billable. Same-region Google Cloud access and external clients have
different transfer treatment. Include applicable retrieval, replication, taxes,
and credit assumptions; do not multiply one egress rate across all routes.
Existing tiered storage is not implicitly copied into this Standard bucket.

Sources:

- <https://cloud.google.com/storage/pricing>
- <https://cloud.google.com/storage/docs/locations>
- <https://docs.cloud.google.com/billing/v1/how-tos/catalog-api>
- <https://cloud.google.com/iam/pricing>
- <https://cloud.google.com/storage/docs/object-versioning>
- <https://cloud.google.com/storage/docs/soft-delete>
- <https://www.infracost.io/docs/features/usage_based_resources/>
- <https://doc.dvc.org/user-guide/project-structure/internal-files>

## Verification and delivery

The committed Terraform test suite uses a mocked Google provider and synthetic
identities. It exercises owner-condition preservation and
sensitivity, invalid-owner rejection, legacy binding conflict prevention,
regional-input validation, private shared storage, DVC namespace outputs,
scoped writer aliases, and rejection of public principals. Run `terraform test
-no-color` after initialization; the suite runs in pre-commit and GitHub Actions.
Mocked tests make no Google Cloud changes and do not replace the full remote plan.

Initialize with the default project-local `.terraform` data directory before
running the suite. The root-level federation tests directly exercise the pinned
module installed under `.terraform/modules/github-identity-federation`, because
Terraform test module blocks accept local or registry sources, not Git URLs.
This keeps rejection tests attached to the released module's real validations
instead of copies in a test fixture. Fresh-cache initialization is covered during
verification; retain the root module label when preserving its state addresses.

1. Initialize with the checked-in lock file and run formatting and validation.
2. Run `pre-commit run --all-files`, Gitleaks, and GitGuardian before publication.
3. Publish only reviewed source on a feature branch. Keep credentials, tfvars,
   state, raw plans and local cost reports outside Git.
4. Require GitHub Terraform validation and usage-based Infracost checks for the
   exact PR head. A full HCP Terraform speculative plan must evaluate that same
   revision, with no resource targeting and expected resource changes only.
5. Record the commit, configuration version, run ID, plan actions and cost
   evidence on the PR. A draft-only plan is not evidence for a different commit.
6. Merge the verified head only after checks and review pass. Workspace runs are
   approvable rather than auto-applied, so the merged revision's normal plan can
   be reviewed before applying it.

Normal Terraform output redacts the owner and bucket inputs. Raw plan JSON and
state still contain sensitive values; never publish them as CI artifacts or PR
comments. The Infracost workflow publishes estimates, not Terraform plan JSON.
