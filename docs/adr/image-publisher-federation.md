# Dedicated GitHub image-publisher federation

## Context

The image-publisher service account already exists in the shared GitHub workload
identity pool and has repository-scoped Artifact Registry writer access. Its
original impersonation member trusted every token admitted by the pool's general
GitHub provider for one repository. That provider checks repository ownership,
but it does not bind image publication to one workflow, event, immutable
repository identity, or stable release-ref policy.

## Decision

Keep the existing pool and service account. Create a dedicated provider in the
same pool whose admission condition requires all of the following:

- the exact immutable GitHub repository ID and matching `owner/repository` name;
- the `push` event;
- `.github/workflows/image.yml` running at the caller's exact ref;
- `.github/workflows/publish-image.yml` running as the reusable job workflow at
  `refs/heads/main`;
- either `refs/heads/main` or an exact stable `vMAJOR.MINOR.PATCH` tag.

The provider maps the repository-specific `attribute.trust_profile` value
`image-publisher-<repository-id>`. The existing service account grants
`roles/iam.workloadIdentityUser` to that attribute principal set. The general
provider does not map the attribute, so its identities cannot use the new
member. During phase one the service account still trusts its existing general-
provider member; trust becomes exclusive to the dedicated provider only after
phase two removes that legacy member.

The public root input identifies the intended publisher account and repository.
Root composition verifies that this account has exactly that one repository,
has the repository-level Artifact Registry writer grant, and uses a provider ID
distinct from the general provider.
During phase one, `retain_general_provider_access = true` keeps the existing
general-provider member while the dedicated provider and member are added. Only
after a real publication canary succeeds through the dedicated provider may a
separate reviewed phase-two change set this value to `false`, passing an empty
repository list to the general module while preserving the service-account
resource and state address. Deployment-specific provider and service-account
values remain sensitive outputs.

## Alternatives

- Authenticating in the tag-local caller workflow would let an off-main tag
  replace the ancestry check before requesting a token. Binding
  `job_workflow_ref` to the reusable workflow on `main` keeps that check in
  reviewed code.
- Adding workflow and ref checks to the shared provider would impose one
  publisher's policy on unrelated GitHub identities and retain a shared trust
  boundary.
- Creating a second pool would isolate the provider but add unnecessary pool
  lifecycle and migration work; provider-level isolation plus an exclusive
  attribute mapping provides the required boundary in the existing pool.
- Granting the dedicated provider through the existing repository attribute
  would still permit identities from the general provider to match the IAM
  member.

## Consequences

Phase one creates one provider plus one narrower member and removes nothing. It
does not replace the pool, service account, existing member, or Artifact Registry
grant and adds no recurring service charge. The workflow then uses the new
provider output for a real publication canary. Phase two removes the broad member
only after that canary succeeds; until then the migration remains intentionally
additive.

## Verification

Mocked Terraform tests assert the exact claim condition including
`job_workflow_ref`, repository-specific attribute mapping, bounded subject,
principal-set member, preservation of the service account, phase-one retention,
phase-two removal of only the publisher's general member, and rejection of
missing, mismatched, colliding, or ungranted root configuration. A phase-one
full non-targeted Terraform Cloud plan must confirm
two additions and no changes or removals before merge or apply. Phase two needs
its own reviewed full plan after the canary evidence exists.
