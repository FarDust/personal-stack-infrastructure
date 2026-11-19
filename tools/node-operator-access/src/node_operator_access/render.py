"""Render the remote bootstrap and revert scripts (run as root on the node, idempotent, self-validating).

Order matters: the sshd restriction is written, validated and reloaded BEFORE the account, its key
and its sudoers file exist, so no failure can leave a key login without the source restriction.
Every `sshd -T` check captures the output first and greps it afterwards: under `set -o pipefail`
a `sshd -T | grep -q` pipeline fails whenever grep exits early and sshd dies of SIGPIPE (exit 141).
Decision record: docs/adr/asset_connector_overseer_access_adr.md
"""

import re
import shlex

from node_operator_access.model import OperatorAccess

BACKUP_MARKER = "NODE_OPERATOR_ACCESS_BACKUP="
_BACKUP_DIR = re.compile(r"^/var/backups/node-operator-access-[0-9]{8}T[0-9]{6}Z$")

# AllowUsers values accumulate across the Match blocks that apply. From the permitted source on
# the node's tailnet address both blocks apply (overseer + nobody-matches-this, so overseer is
# allowed); from anywhere else only the second applies and nobody-matches-this admits no one.
# Mixing AllowUsers with DenyUsers would deny every login.
SSHD_DROPIN = """Match User overseer Address {src} LocalAddress {laddr}
    AllowUsers overseer
    AuthenticationMethods publickey
Match User overseer
    AllowUsers nobody-matches-this
    AuthenticationMethods publickey
"""

# Paths are prefixed with $ROOT so the tests can run the real script inside a temporary tree;
# the CLI always renders ROOT=''.
_PRELUDE = r"""#!/bin/bash
set -euo pipefail
ROOT=@ROOT@
DROP=$ROOT/etc/ssh/sshd_config.d/overseer-restrict.conf
SUDOERS=$ROOT/etc/sudoers.d/90-overseer-nopasswd
AUTHKEYS=$ROOT/home/overseer/.ssh/authorized_keys
SSHD_CONFIG=$ROOT/etc/ssh/sshd_config

# Restore what the backup holds and remove what it does not: sudoers and key first, the account
# when this tool created it (marker file), the sshd restriction last. Safe to run more than once.
rollback() {
  echo "rolling back from $BK" >&2
  if [ -e "$BK$SUDOERS" ]; then cp -a "$BK$SUDOERS" "$SUDOERS"; else rm -f "$SUDOERS"; fi
  if [ -e "$BK/created-user" ]; then
    if id overseer >/dev/null 2>&1; then userdel --remove --force overseer; fi
  elif [ -e "$BK$AUTHKEYS" ]; then
    cp -a "$BK$AUTHKEYS" "$AUTHKEYS"
  else
    rm -f "$AUTHKEYS"
  fi
  if [ -e "$BK$DROP" ]; then cp -a "$BK$DROP" "$DROP"; else rm -f "$DROP"; fi
  sshd -t && systemctl reload ssh
}
"""

_APPLY = r"""SRC=@SRC@
KEY=@KEY@
BK=$ROOT/var/backups/node-operator-access-$(date -u +%Y%m%dT%H%M%SZ)
TSIP=$(tailscale ip -4)
TSIP=${TSIP%%$'\n'*}
[[ "$TSIP" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "tailnet address not available" >&2; exit 1; }
id atelo >/dev/null 2>&1 || { echo "atelo account missing; create it first" >&2; exit 1; }

mkdir -p "$BK"
echo "@MARKER@${BK#"$ROOT"}"
for f in "$DROP" "$SUDOERS" "$AUTHKEYS" "$SSHD_CONFIG"; do
  if [ -e "$f" ]; then cp -a --parents "$f" "$BK"; fi
done
on_exit() { if [ "$1" -ne 0 ]; then rollback; fi; }
trap 'on_exit $?' EXIT

# 1. Restriction first: written, validated and live before any credential exists.
install -d -m 0755 "$ROOT/etc/ssh/sshd_config.d"
cat >"$DROP" <<SSHD
@DROPIN@SSHD
chmod 0644 "$DROP"
sshd -t
effective() { sshd -T -C "user=$1,host=x,addr=$2,laddr=$TSIP,lport=22"; }
out=$(effective overseer "$SRC")
grep -qx 'allowusers overseer' <<<"$out" || { echo "drop-in denies the permitted source" >&2; exit 1; }
out=$(effective overseer 192.0.2.1)
if grep -qx 'allowusers overseer' <<<"$out"; then
  echo "drop-in allows an unexpected source" >&2; exit 1
fi
out=$(effective atelo 192.0.2.1)
if grep -q '^allowusers' <<<"$out"; then
  echo "atelo affected by the drop-in" >&2; exit 1
fi
systemctl reload ssh

# 2. Account, key and sudo, behind the restriction that is already enforced.
if ! id overseer >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --comment "Operator account" overseer
  touch "$BK/created-user"
fi
passwd -l overseer >/dev/null
install -d -m 0700 -o overseer -g overseer "$ROOT/home/overseer/.ssh"
printf '%s\n' "$KEY" >"$AUTHKEYS"
chown overseer:overseer "$AUTHKEYS"
chmod 0600 "$AUTHKEYS"

tmp=$(mktemp)
echo 'overseer ALL=(ALL) NOPASSWD:ALL' >"$tmp"
visudo -cf "$tmp"
install -m 0440 -o root -g root "$tmp" "$SUDOERS"
rm -f "$tmp"
echo "operator access applied; backup in $BK"
"""

_REVERT = r"""BK=$ROOT@BK@
[ -d "$BK" ] || { echo "backup $BK not found" >&2; exit 1; }
rollback
echo "operator access reverted from $BK"
"""


def _prelude(root: str) -> str:
    return _PRELUDE.replace("@ROOT@", shlex.quote(root))


def render_script(access: OperatorAccess, *, root: str = "") -> str:
    """Bootstrap script; prints `NODE_OPERATOR_ACCESS_BACKUP=<dir>` and reverts itself on failure."""
    body = (
        _APPLY.replace("@DROPIN@", SSHD_DROPIN.format(src="$SRC", laddr="$TSIP"))
        .replace("@SRC@", shlex.quote(access.source_ip))
        .replace("@KEY@", shlex.quote(access.public_key))
        .replace("@MARKER@", BACKUP_MARKER)
    )
    return _prelude(root) + body


def render_revert_script(backup_dir: str, *, root: str = "") -> str:
    """Revert script for a backup directory printed by the bootstrap script."""
    if not _BACKUP_DIR.fullmatch(backup_dir):
        raise ValueError(f"not a node-operator-access backup directory: {backup_dir!r}")
    return _prelude(root) + _REVERT.replace("@BK@", shlex.quote(backup_dir))


def parse_backup_dir(stdout: str) -> str | None:
    """Backup directory announced by the bootstrap script, or None when it never got that far."""
    for line in stdout.splitlines():
        if line.startswith(BACKUP_MARKER):
            candidate = line.removeprefix(BACKUP_MARKER).strip()
            if _BACKUP_DIR.fullmatch(candidate):
                return candidate
    return None
