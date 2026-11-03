# Keyless personal Wallet pass signing

## Context

Personal development passes need a Google Wallet issuer and signed save links.
The issuer console is independent from the cloud project. Downloading a service
account key would create unnecessary secret custody for an occasional operation.

## Decision

An optional module creates one dedicated signing identity. A custom role contains only
`iam.serviceAccounts.signBlob`; additive caller grants bind that role to the
service account resource. The module provisions nothing when its explicit caller
list is empty. Project, account identifier, and caller identities come from the
owning workspace; deployment identifiers stay out of this public repository.

The caller uses existing approved credentials and the already available IAM
Credentials API with the Google Auth remote signer. Google retains the private
key. The service account must separately be granted
Developer access in the user's Google Wallet issuer console. Demo-mode recipients
must be authorized issuer users or configured test accounts. No project-wide role,
static service-account key, token-minting permission, or public principal is added.

## Alternatives

Downloaded JSON keys increase custody and rotation work. The predefined Token
Creator role includes permissions beyond the `signBlob` operation used here.
Reusing unrelated service accounts would conflate infrastructure and ticketing
authority. A dedicated signing-only identity is the smallest matching boundary.

## Consequences

This module has no compute or storage resources and no recurring provisioned
capacity. API invocation charges, if applicable, depend on usage. The module does
not manage project APIs or grant service-administration permission. Enabling the
Wallet REST API is a separate prerequisite only when its REST operations are
actually used; issuing and saving an embedded signed JWT was verified without
enabling that API in the signing project. A personal copy of a transport barcode does not
make this identity the rail operator, and changes to the source reservation must
be reflected in the saved pass by its consumer workflow.

## Verification

Mocked Terraform tests check the exact permission set, service-account resource
scope, output identity, disabled state, required identity, and rejection of public
principals. Before applying, review a full Terraform Cloud plan for the intended
revision and its cost signal. After applying, inspect the dedicated identity's
IAM policy and exercise remote signing with the intended caller
without logging its token or the resulting bearer save URL.

## Superseded API-management attempt

The initial revision also declared two project-service resources. Its full plan
contained five additions, but the apply could create only the three signing
resources: the main executor lacked `serviceusage.services.list` for both API
resources. The failed API resources never entered state. Rather than widen the
executor or bootstrap unused REST access, this revision removes those declarations.
The consumer then proved remote signing and an actual saved Wallet pass through
Google's signed-link flow. The corrective complete plan must show zero resource
changes, preserving the signing resources and existing API configuration.

## Sources

- [Google Wallet REST authentication](https://developers.google.com/wallet/generic/getting-started/auth/rest)
- [Google Auth remote IAM signer](https://google-auth.readthedocs.io/en/latest/reference/google.auth.iam.html)
- [IAM Credentials signBlob](https://cloud.google.com/iam/docs/reference/credentials/rest/v1/projects.serviceAccounts/signBlob)
