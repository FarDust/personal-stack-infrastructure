# DVC storage and delivery

## Configuration

The root composes the private artifact bucket through `configs/storage`.
The bucket's name is supplied by the sensitive Terraform Cloud variable
`gpu_idle_lab_dvc_bucket_name`; there is no hardcoded deployment name.
The independently configurable `gpu_idle_lab_dvc_location` selects the bucket
region without changing the provider's existing `gcp_region` setting.

The selected workspace location is `southamerica-west1` (Santiago), near the
artifact-consuming workload. This is a new bucket, not a migration of existing
data. The region is an explicit workspace decision, not a claim that the closest
region is always cheapest. Bucket names are explicit deployment inputs; no
broader bucket naming formula was found in the existing infrastructure sources.

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

## Access and retention

The bucket enforces public-access prevention and uniform bucket-level access,
enables versioning, prevents Terraform destruction, and disables force-destroy.
This change grants no new principal access. DVC uses an approved Application
Default Credentials identity whose access must be checked before upload. The
existing GitHub Secret Manager account is not implicitly authorized for storage,
and these CI workflows do not upload DVC data.

No automatic object expiration is introduced. Stored bytes include live objects,
noncurrent versions, and soft-deleted objects; the local artifact quota is not a
remote-storage quota. Review retained bytes before uploads and agree a retention
policy before adding lifecycle deletion.

## Projected monthly cost

`infracost-usage.yml` records the illustrative monthly planning envelope:

| Item | Quantity | Rate | Monthly USD |
| --- | ---: | ---: | ---: |
| Standard storage in Santiago | 5 GiB | 0.03/GiB-month | 0.15 |
| Class A operations | 10,000 | 0.05/10,000 | 0.05 |
| Class B operations | 100,000 | 0.004/10,000 | 0.04 |
| Worldwide egress modeled for artifact downloads | 20 GiB | 0.12/GiB | 2.40 |
| Total | | | **2.64** |

The Google Cloud Billing catalog and Infracost confirmed Santiago's storage
price. Iowa regional Standard storage is 0.02/GiB-month before applicable free
tier, so locality costs approximately 0.05/month extra for this stored volume.
No free-tier discount is assumed for Santiago.

The repository's existing service-account/IAM resources add no recurring IAM
service charge. Infracost does not price the identity pool/provider resources;
their zero cost is based on the IAM service pricing, not inferred from missing
coverage. HCP Terraform's estimate matched zero resources and is not used as
the cost gate.

The modeled repository cost is below the 30 USD/month ceiling. This is a
projection under explicit assumptions, not a hard spending limit or an actual
billing-account total. Taxes, currency conversion, unexpected retained versions,
other applications/projects, and usage above this envelope are not included.
No readable billing export was available to establish aggregate actual spend.
Account-wide remaining budget must be considered before provisioning or expanding
usage; merging configuration is not evidence of an applied resource or paid usage.

Sources:

- <https://cloud.google.com/storage/pricing>
- <https://cloud.google.com/storage/docs/locations>
- <https://cloud.google.com/billing/docs/how-to/catalog-api>
- <https://cloud.google.com/iam/pricing>
- <https://cloud.google.com/storage/docs/object-versioning>
- <https://cloud.google.com/storage/docs/soft-delete>
- <https://www.infracost.io/docs/features/usage_based_resources/>

## Verification and delivery

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
