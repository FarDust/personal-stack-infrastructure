# Storage permission bootstrap

This separate Terraform root prepares an existing automation service account
to create and manage one designated artifact bucket. Run it through a separate
reviewed HCP Terraform workspace before applying the main storage configuration.
Supply all deployment identifiers as sensitive workspace inputs.

The bootstrap grants:

- A custom project role containing only `storage.buckets.create`.
- Conditional `roles/storage.admin` with an exact bucket resource-name match.

Creation is authorized against the project, so the bucket-name condition alone
cannot authorize creation. The creation-only role can create other new buckets
in the same project; it does not grant access to existing data. The conditional
management grant is limited to the designated bucket. Review any pre-existing
runtime privileges separately rather than claiming these grants remove them.

Use an authorized bootstrap identity with role/policy administration permission.
Prefer a short-lived token delivered directly into a sensitive environment input
for the reviewed run. Keep refresh credentials and service-account keys out of
the workspace and source. Remove temporary authentication after terminal results.

Require a full exact-revision speculative plan, passing CI and review, and an
approvable normal plan for the merged revision. Verify the resulting role and
conditional memberships before applying the main bucket configuration. Keep
runtime receipts and principal values in private operational records.
