"""Render the remote bootstrap script (run as root on the node, idempotent, self-validating)."""

from node_operator_access.model import OperatorAccess

# Same AllowUsers keyword in both Match blocks: the first value wins. Mixing AllowUsers with
# DenyUsers denies every login (see docs/adr/asset_connector_overseer_access_adr.md).
_TEMPLATE = r"""#!/bin/bash
set -euo pipefail
SRC='@SRC@'
KEY='@KEY@'
TS=$(date -u +%Y%m%dT%H%M%SZ)
BK=/var/backups/node-operator-access-$TS
DROP=/etc/ssh/sshd_config.d/overseer-restrict.conf
SUDOERS=/etc/sudoers.d/90-overseer-nopasswd
TSIP=$(tailscale ip -4 | head -n1)
[[ "$TSIP" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "tailnet address not available" >&2; exit 1; }
id atelo >/dev/null 2>&1 || { echo "atelo account missing; create it first" >&2; exit 1; }

mkdir -p "$BK"
for f in "$DROP" "$SUDOERS" /home/overseer/.ssh/authorized_keys /etc/ssh/sshd_config; do
  if [ -e "$f" ]; then cp -a --parents "$f" "$BK"; fi
done
rollback() {
  echo "rolling back from $BK" >&2
  if [ -e "$BK$DROP" ]; then cp -a "$BK$DROP" "$DROP"; else rm -f "$DROP"; fi
  if [ -e "$BK$SUDOERS" ]; then cp -a "$BK$SUDOERS" "$SUDOERS"; else rm -f "$SUDOERS"; fi
  sshd -t && systemctl reload ssh
}
on_exit() { if [ "$1" -ne 0 ]; then rollback; fi; }
trap 'on_exit $?' EXIT

id overseer >/dev/null 2>&1 || useradd --create-home --shell /bin/bash --comment "Operator account" overseer
passwd -l overseer >/dev/null
install -d -m 0700 -o overseer -g overseer /home/overseer/.ssh
printf '%s\n' "$KEY" >/home/overseer/.ssh/authorized_keys
chown overseer:overseer /home/overseer/.ssh/authorized_keys
chmod 0600 /home/overseer/.ssh/authorized_keys

tmp=$(mktemp)
echo 'overseer ALL=(ALL) NOPASSWD:ALL' >"$tmp"
visudo -cf "$tmp"
install -m 0440 -o root -g root "$tmp" "$SUDOERS"
rm -f "$tmp"

install -d -m 0755 /etc/ssh/sshd_config.d
cat >"$DROP" <<SSHD
Match User overseer Address $SRC LocalAddress $TSIP
    AllowUsers overseer
    AuthenticationMethods publickey
Match User overseer
    AllowUsers nobody-matches-this
    AuthenticationMethods publickey
SSHD
chmod 0644 "$DROP"

sshd -t
sshd -T -C "user=overseer,host=x,addr=$SRC,laddr=$TSIP,lport=22" | grep -qx 'allowusers overseer'
if sshd -T -C "user=overseer,host=x,addr=192.0.2.1,laddr=$TSIP,lport=22" | grep -qx 'allowusers overseer'; then
  echo "drop-in allows an unexpected source" >&2; exit 1
fi
if sshd -T -C "user=atelo,host=x,addr=192.0.2.1,laddr=$TSIP,lport=22" | grep -q '^allowusers'; then
  echo "atelo affected by the drop-in" >&2; exit 1
fi
systemctl reload ssh
echo "operator access applied; backup in $BK"
"""


def render_script(access: OperatorAccess) -> str:
    return _TEMPLATE.replace("@SRC@", access.source_ip).replace("@KEY@", access.public_key)
