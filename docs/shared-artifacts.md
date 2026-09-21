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

## Preserved federation behavior

`modules/github-identity-federation` is a maintained local snapshot of
`terraform-infrastructure` revision
`752db911c1d9cc8d1ce4a665f5d5a1791796bd5d`, with the required owner condition
added. The source is available at
<https://github.com/FarDust/terraform-infrastructure/tree/752db911c1d9cc8d1ce4a665f5d5a1791796bd5d/modules/github-identity-federation>.

Resource addresses, legacy account naming, and repository-scoped IAM binding
semantics are retained. Upgrading directly to a newer upstream revision would
also migrate IAM bindings to IAM members and alter account naming; that is a
separate migration, not part of provisioning artifact storage.

The legacy binding layout accepts at most one distinct allowed repository per
account. Validation rejects multiple repositories before planning because
multiple authoritative bindings for the same role would otherwise overwrite
one another. A future multi-repository migration must explicitly preserve state
addresses and review IAM changes, rather than silently changing this baseline.

## Access and retention

If the existing Terraform runtime lacks storage provisioning permission, use
the separately reviewed [storage bootstrap](../bootstrap/storage/README.md).
It grants creation-only project permission plus management restricted to the
designated bucket; the main configuration remains responsible for the bucket
and consumer access. Keep bootstrap credentials temporary and outside source.

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

The repository's existing service-account/IAM resources add no recurring IAM
service charge. Infracost 0.10.45 classifies the IAM resources as no-price
resources and reports no unsupported resources for this configuration, consistent
with the IAM service pricing. HCP Terraform's incomplete estimate is not used as
the cost gate. Both baseline and head use their checked-in usage model when one
exists. Configure the CI secret `ARTIFACT_BUCKET_LOCATION` from the authoritative
workspace location and verify that the exact-revision remote plan uses that same
value. CI requires the expected bucket resource, complete supported-resource
coverage, and a positive price for the separate populated example. It does not
assert that one fixed dollar total is a realistic bill.

CI compares the proposed incremental model plus the private account baseline
`INFRA_BASELINE_MONTHLY_FORECAST` against `INFRA_MONTHLY_BUDGET`.
`INFRA_BILLING_PERIOD` must identify the current month. Refresh the private
baseline from authorized billing evidence when reviewing deployment or usage
changes; keep billing exports and account-specific observations outside this repo.
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

The committed `tests/*.tftest.hcl` regression suite uses a mocked Google provider
and synthetic identities. It exercises owner-condition preservation and
sensitivity, invalid-owner rejection, legacy binding conflict prevention,
regional-input validation, private shared storage, DVC namespace outputs,
scoped writer aliases, and rejection of public principals. Run `terraform test
-no-color` after initialization; the suite runs in pre-commit and GitHub Actions.
Mocked tests make no Google Cloud changes and do not replace the full remote plan.

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
