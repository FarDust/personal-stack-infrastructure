# Impersonated Python registry token reader

## Context

A self-hosted CI worker outside GCP and GitHub needs to install private
packages from the existing Python repository. GitHub OIDC federation
(`python_federated_reader.tf`) does not apply to that worker. The cluster
already holds one existing credential for an existing storage service account,
which `python_artifact_registry_readers` grants repository-scoped
`roles/artifactregistry.reader`. Handing that credential to every CI job would
spread a long-lived secret that also carries the account's storage grants.

The cluster trust-agent can hold one credential and hand out short-lived
tokens. It needs a target identity that can only read the Python repository.

## Decision

The main workspace declares `python_registry_token_readers`, a sensitive map
(empty by default) from neutral aliases to a dedicated `account_id`, an optional
display name and an alias map of `token_minters`. For each alias this root
creates:

- one service account, with no key;
- one `roles/artifactregistry.reader` member on the Python repository only,
  using the same location and repository inputs as the other Python readers;
- one `roles/iam.serviceAccountTokenCreator` member on that service account per
  minter.

Minters must be explicit `serviceAccount:` principals; users, groups and public
principals are rejected. The trust-agent impersonates the reader with the
minter credential and issues access tokens with a 600 second lifetime to the CI
worker. The lifetime is chosen by the caller of `generateAccessToken`; the IAM
default is 3600 seconds and the maximum without an organization policy change is
3600 seconds, so the shorter lifetime is enforced by the trust-agent request.

Lifecycle preconditions reject a reader whose principal (derived from its
account ID and the project) appears in any registry reader or writer map,
bucket writer list, asset-tenant writer list or the Wallet signer list managed
by this root, an account ID shared with the Wallet, Loki or backup-writer
identities, and a reader listed as its own minter. Principals computed by the
shared federation module are not compared, because their emails are known only
after apply; the distinct account ID keeps the reader separate from them.
Minters may live in another project; chained impersonation between two reader
aliases is allowed but grants nothing beyond repository read access. Account IDs, minter
principals and the project stay in workspace variables; resource addresses only
contain aliases.

## Alternatives

- **Static key for a new reader account.** Simplest consumer, but adds a second
  long-lived secret to distribute and rotate. Rejected: keys are excluded from
  this repository's flows.
- **Distribute the existing cluster credential to CI jobs.** Gives every job the
  storage account's broader grants. Rejected.
- **Keycloak workload federation realm.** The intended keyless path for
  non-GitHub workloads, but the realm remains dormant behind its own production
  gates recorded in the operator's private decision record ("Keycloak GCP
  workload federation boundary"). When it is
  promoted, the minter alias can be replaced by a federated principal by
  changing the variable value; this configuration stays.
- **Project-level token creator.** Would let the minter impersonate every
  account in the project. Rejected in favour of a member on the single reader
  account.

## Consequences

The minter already reads the repository, so impersonating a reader-only
account adds no new resource permission; it adds a narrower, short-lived
credential for consumers. Compromise of the minter credential still allows
reading the repository, as it does today. The reader has no project-level
roles from this root; out-of-band or inherited grants are outside its
configuration and must be reviewed live. The IAM Service Account Credentials
API must be enabled in the project for token minting. Service accounts and IAM
members have no recurring cost.

This is an additive, backward-compatible capability (MINOR under Semantic
Versioning).

## Verification

`tests/python_registry_token_reader.tftest.hcl` covers the repository-scoped
reader, the token-creator member, empty default, multiple minters, user and
public minters, missing minters, malformed aliases and account IDs, duplicated
account IDs, overlap with every plan-time privileged map, account ID reuse and
self-minting. Before deployment, review a full HCP plan with exactly one
service account, one repository reader member and one token-creator member per
minter, and no other changes. After apply, verify the service-account policy
lists only the minter as token creator, the repository policy lists the reader,
and the project policy holds no role for the reader; then mint a token through
the minter and run a locked install.
