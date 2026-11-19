# ADR: Operator access to the asset connector (`overseer`)

Status: proposed (owner decision 2026-11-19: every machine has an `atelo` and an `overseer` account). Implementation: `configs/asset-connector` (`startup.sh`, `overseer_*` variables), tested in `tests/asset_connector.tftest.hcl`. Extends [asset_connector_adr.md](asset_connector_adr.md).

All identifiers (the operator public key, the source address, hostnames) are Terraform Cloud workspace variables; this document uses placeholders such as `<operator-source-ip>` and `<connector-tailnet-ip>`.

## Context

The connector accepts SSH only through OS Login (the owner's Google identity), with project SSH keys blocked and Tailscale SSH off. Agents that operate the other nodes use a second account, `overseer`, with a dedicated key and passwordless sudo. The connector has no such account, so an agent has no break-glass path that does not depend on a Google session.

## Decision

1. Keep OS Login as the owner's way in. Nothing changes in `enable-oslogin`, `block-project-ssh-keys` or `--ssh=false`.
2. The boot script creates a local account `overseer` when two optional metadata values are present (`overseer-ssh-pubkey`, `overseer-source-ip`, fed by two workspace variables that must be set together):
   - password locked (`passwd -l`), so the key is the only credential;
   - `/etc/sudoers.d/90-overseer-nopasswd` (`NOPASSWD: ALL`, mode 0440, validated with `visudo -cf` before install);
   - `authorized_keys` with the public half of a dedicated ed25519 pair made for this host only (the private half stays on the operator machine);
   - `/etc/ssh/sshd_config.d/overseer-restrict.conf`: `Match User overseer Address <operator-source-ip> LocalAddress <connector-tailnet-ip>` sets `AllowUsers overseer`; `Match User overseer` sets `AllowUsers nobody-matches-this`; both blocks set `AuthenticationMethods publickey`. The same keyword sits in both blocks on purpose: `AllowUsers` in one block and `DenyUsers` in the other denies every connection, because different keywords do not override each other. The connector tailnet address is read at boot from `tailscale ip -4`.
3. The script validates before it reloads: `sshd -t`, `sshd -T -C` for the permitted source (must list `allowusers overseer`) and for a documentation address (must not). A failing check removes the drop-in and fails the boot script; sshd keeps the previous configuration.
4. The IP restriction is part of the model, not an add-on: `overseer` is root-equivalent, so it is key-only, source-restricted and bound to the tailnet interface address.
5. `atelo` with password plus OTP is not provisioned here. The OTP pattern needs a per-user TOTP secret and a password hash on the host; either would live in Terraform state or instance metadata, which would store the second factor next to the first. The owner's OS Login identity fills the `atelo` role on this host. Revisit with Secret Manager plus a one-time enrolment if a local `atelo` is wanted.

## Alternatives

- Project-wide or instance `ssh-keys` metadata: rejected; it bypasses OS Login and is blocked on purpose.
- OS Login for a second Google identity with sudo (`roles/compute.osAdminLogin`): needs a user or service account and IAM changes; rejected for agents because it ties break-glass to Google sessions.
- Tailscale SSH: disabled by design on this host.

## Consequences

- Risk: `overseer` is root-equivalent. Mitigations: key only, one source address, tailnet interface address only, no public SSH port (the only public rule is UDP 41641), an explicit tailnet grant for the operator machine (tailnet repository). Existing wildcard member grants still reach tcp/22 of the tag, so the sshd `Match` is the enforcing layer, not the tailnet policy.
- The startup script runs on boot only. The VM is not restarted by this change; to apply on the running VM, run `sudo google_metadata_script_runner startup` as the OS Login user (the script is idempotent). Metadata updates do not recreate the instance (`allow_stopping_for_update` is not needed for metadata).
- Rollback: unset the two workspace variables and apply (metadata removed), then on the host `userdel -r overseer`, remove `/etc/sudoers.d/90-overseer-nopasswd` and `/etc/ssh/sshd_config.d/overseer-restrict.conf`, `systemctl reload ssh`. The script does not remove the account when the metadata disappears.

## Verification

- `terraform fmt -check`, `terraform validate`, `terraform test` (key and source together, ed25519 only, tailnet source only, absent by default).
- `sshd -T -C user=overseer,addr=<operator-source-ip>,laddr=<ip>` lists `allowusers overseer` and `authenticationmethods publickey`; other source or local addresses list only the nobody entry (simulated 2026-11-19 with OpenSSH 9.6 and the drop-in included from a main file).
- After apply and boot: login as `overseer` with the dedicated key from the operator machine, `sudo -n true`, and a refused login from another source.
