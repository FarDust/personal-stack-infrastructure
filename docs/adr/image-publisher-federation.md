# Dedicated GitHub image-publisher federation

## Context

The image-publisher service account already exists in the shared GitHub workload
identity pool and has repository-scoped Artifact Registry writer access. Its
original impersonation member trusted every token admitted by the pool's general
GitHub provider for one repository. That provider checks repository ownership,
but it does not bind image publication to one workflow, event, immutable
repository identity, or stable release-ref policy.

## Decision

Keep the existing pool and service account, but remove the image publisher's
repository member from the general provider. Create a dedicated provider in the
same pool whose admission condition requires all of the following:

- the exact immutable GitHub repository ID and matching `owner/repository` name;
- the `push` event;
- `.github/workflows/image.yml` running at the caller's exact ref;
- either `refs/heads/main` or an exact stable `vMAJOR.MINOR.PATCH` tag.

The provider maps the constant `attribute.trust_profile` value
`image-publisher-v1`. The existing service account grants
`roles/iam.workloadIdentityUser` only to that attribute principal set. The
general provider does not map the attribute, so its identities cannot use the
new member.

The public root input identifies the intended publisher account and repository.
Root composition verifies that this account has exactly that one repository,
then passes an empty repository list to the general module while preserving the
service-account resource and state address. Deployment-specific provider and
service-account values remain sensitive outputs.

## Alternatives

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

Applying the change removes one broad service-account IAM member and creates one
provider plus one narrower member. It does not replace the pool, service account,
or Artifact Registry grant and adds no recurring service charge. The workflow
must use the new provider output; the general provider no longer authorizes the
publisher after apply.

## Verification

Mocked Terraform tests assert the exact claim condition, exclusive attribute
mapping, principal-set member, preservation of the service account, removal of
only the publisher's general member, and rejection of missing or mismatched root
configuration. A full non-targeted Terraform Cloud plan must confirm the expected
one removal and two additions without replacement before merge or apply.
