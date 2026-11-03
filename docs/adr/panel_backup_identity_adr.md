# Panel backup identity

## Context

The panel stores backup objects under a server UUID followed by the backup UUID. Its S3-compatible integration needs object and multipart permissions. The target bucket is shared, so bucket-wide object access would expose unrelated data.

## Decision

Create a dedicated service account and a managed folder for one configured server UUID. Bind a custom role to that folder only, containing object create, get, list and delete plus multipart create, abort and list-parts. The bucket and UUID are sensitive workspace inputs. Empty configuration avoids initial creation; once created, retain the folder path and set `panel_backup_grant_enabled` false to disable the account and remove its folder grant without deleting protected resources. A second server requires an independently reviewed scope change.

HMAC key creation and custody are outside Terraform: the one-time secret must not enter Terraform state. The deployment workflow provisions it only after approved secure custody is ready. The service account cannot administer IAM or HMAC keys.

## Alternatives

Bucket-level object roles would grant access to unrelated objects. Sharing an existing identity would combine unrelated trust boundaries. Both are rejected. Bucket-level multipart listing is excluded until a verified consumer operation needs it.

## Consequences

The managed folder and custom role have deletion protection. When the configured panel bucket is the shared artifact bucket, its UUID prefix receives a lifecycle rule deleting only noncurrent versions after one day. Existing lifecycle rules are preserved. The bucket's soft-delete policy then applies independently; it does not shorten live backup retention. Real XML multipart interoperability, sibling-prefix denial and restore behavior require live verification after the reviewed apply.

## Verification

Terraform tests cover disabled configuration, scope, permissions and invalid paths. Before apply, review a full Terraform Cloud plan and cost; afterwards test allowed operations in the folder and denial in a sibling prefix without removing unrelated data.
