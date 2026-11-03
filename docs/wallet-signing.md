# Personal Wallet signing

Set `wallet_signer_service_account_id` and `wallet_signer_members` as sensitive
variables in the main workspace. The caller list accepts explicit user or service
account email principals. An empty list disables provisioning.

Review and apply a complete Terraform Cloud plan. Read the sensitive
`wallet_signer_service_account_email` output through an approved runtime channel
and add that identity as a Developer in the Google Wallet issuer console. Use
Google Auth's IAM signer with the caller's existing credential; keep signed save
links and source barcodes outside public logs and repositories.

Issuer demo mode is sufficient for the issuer's administrators, developers, and
configured test recipients. Saving still uses Google's own confirmation flow.

The boundary and verification contract are in
[the decision record](adr/wallet_signing_adr.md).
