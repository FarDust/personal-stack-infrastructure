# Storage permission bootstrap

This separate Terraform root prepares an existing automation service account to
create and manage the designated artifact bucket, and it is the sole Terraform
state owner for the private Docker Artifact Registry repository. Run it through
a separate reviewed HCP Terraform workspace before planning or applying the main
configuration. Supply deployment identifiers as sensitive workspace inputs.

The bootstrap grants:

- A custom project role containing only `storage.buckets.create`.
- Conditional `roles/storage.admin` with an exact bucket resource-name match.
- The private `cluster-internal-images` Docker repository in
  `southamerica-west1`, unless the validated location or repository ID inputs
  select different values.
- A custom role containing only `artifactregistry.repositories.get`,
  `artifactregistry.repositories.getIamPolicy`, and
  `artifactregistry.repositories.setIamPolicy`, granted additively at that
  repository to the main Terraform executor.

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
