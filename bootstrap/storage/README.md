# Storage permission bootstrap

This separate Terraform root prepares an existing automation service account to
create and manage the designated artifact bucket, and it is the sole Terraform
state owner for the private Docker Artifact Registry repository. Run it through
a separate reviewed HCP Terraform workspace before planning or applying the main
configuration. Supply deployment identifiers as sensitive workspace inputs.

The bootstrap grants:

- A custom project role containing only `storage.buckets.create`.
- Conditional `roles/storage.admin` with an exact bucket resource-name match.
- The private Docker repository, whose location and repository ID come from the
  `cluster_artifact_registry_location` and `cluster_artifact_registry_repository_id`
  workspace variables.
- A custom role containing only `artifactregistry.repositories.get`,
  `artifactregistry.repositories.getIamPolicy`, and
  `artifactregistry.repositories.setIamPolicy`, granted additively at that
  repository to the main Terraform executor.

- The private PYTHON repository (location and repository ID come from the sensitive
  workspace variables `python_artifact_registry_location` and
  `python_artifact_registry_repository_id`; there are no defaults), protected with
  `deletion_policy = "PREVENT"`, plus the same repository-scoped IAM manager
  role for the main executor. The main root adds only additive reader and writer
  members (`python_artifact_registry_writers` / `python_artifact_registry_readers`
  Terraform Cloud variables); consumers pin the explicit index and authenticate
  with ADC/OAuth tokens, never static keys. Apply this bootstrap workspace before the main
  workspace: the main root reads the repository through a data source and its plan
  fails with a not-found error until the repository exists. Python registry cost
  is storage and egress only (first 0.5 GB free at Google's published rates; a few
  wheels stay well under the USD 30 ceiling).

Creation is authorized against the project, so the bucket-name condition alone
cannot authorize creation. The creation-only role can create other new buckets
in the same project; it does not grant access to existing data. The conditional
management grant is limited to the designated bucket. Review any pre-existing
runtime privileges separately rather than claiming these grants remove them.

Artifact Registry repository creation is authorized against its location
parent, so it is performed by this isolated bootstrap root rather than the main
executor. The main root reads the bootstrap-owned repository and maintains only
additive writer and reader repository IAM members. It must not create or destroy
the repository and must not grant the executor a project-level Artifact Registry
role. In particular, do not use `roles/artifactregistry.admin`.

Use an authorized bootstrap identity with role/policy administration permission.
Prefer a short-lived token delivered directly into a sensitive environment input
for the reviewed run. Keep refresh credentials and service-account keys out of
the workspace and source. Remove temporary authentication after terminal results.

Require a full exact-revision speculative plan, passing CI and review, and an
approvable normal plan for the merged revision. Verify the resulting role and
conditional memberships before applying the main bucket configuration. Keep
runtime receipts and principal values in private operational records.
