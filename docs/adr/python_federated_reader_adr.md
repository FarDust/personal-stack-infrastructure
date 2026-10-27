# Dedicated federated Python package reader

## Context

Private package consumers need reproducible dependency installation in GitHub jobs.
The existing pinned federation module owns accounts and additive exact-repository
impersonation memberships; the bootstrap workspace owns registry lifecycle.

## Decision

The main workspace selects non-secret account aliases with
`python_artifact_registry_federated_readers` (empty by default). Add a dedicated
account entry to `federated_github_users` privately, with exactly one allowed
repository under the existing owner. Its only new resource permission is
`roles/artifactregistry.reader` on the existing Python repository. Preserve the
provider owner condition and all existing identities. Account names and repository
identifiers remain private workspace inputs; use a neutral alias in source/state.

## Alternatives

Reusing a cluster key introduces credential distribution. Reusing the secrets
identity couples package installation to broader privileges. Copying client code
creates maintenance drift. An additional federation provider duplicates the
existing maintained mechanism. These alternatives are not selected.

## Consequences

Configure the main workspace only; bootstrap has no change. Keep the selected
account absent from writer maps and other privilege grants. Preserve existing
reader entries and avoid declaring the same principal through both reader paths.
A separate precondition rejects a selected principal already present in the
existing Python reader map, regardless of alias. This keeps one Terraform state
owner for each repository/role/member tuple and prevents one path deleting a
membership still declared by the other.
The reader lifecycle precondition compares the selected service-account email
exported by the shared module against all privileged principals managed by this
root: Python and image registry writers, bucket writers, the secrets account,
backup writer, and Loki administrator. It compares principals, not map aliases,
so a second alias cannot conceal an overlap. Independent operator grants remain
valid; the check rejects selection rather than removing any privilege.
The separate bootstrap workspace's executor grants and out-of-band or inherited
IAM are outside this root's configuration. Before deployment, review effective
IAM for the selected account, including bootstrap, project/folder/organization
grants and impersonation paths. Source validation cannot establish absence of
those privileges. Computed emails can defer the precondition until apply; a
successful speculative plan alone is not proof of least privilege.
This additive capability is a MINOR release change under the repository's
unreleased versioning convention. It provisions no registry or stored content;
download costs still require review under the existing budget gate.

## Verification

Mock tests cover the repository-scoped reader, empty selection, malformed aliases,
wrong owner, multiple repositories, differently aliased writer overlaps, and
duplicate reader ownership.
Existing shared-module tests cover exact repository impersonation and
unchanged owner conditions. Local tests establish source behavior only. Before
deployment, review a full HCP plan for one account, one impersonation member and
one repository reader member, with no unexpected changes. After approved apply,
verify policy and a real GitHub OIDC exchange followed by a clean locked install
in quality and release jobs. No static credential or package publication change
is part of this capability.
