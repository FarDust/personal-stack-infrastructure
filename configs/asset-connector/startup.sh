#!/bin/bash
# Idempotent boot script of the asset CDN node: a local mirror of the tenant prefixes served by
# Caddy over the tailnet. IPv6-only VM: every download goes to storage.googleapis.com through
# Private Google Access, never through a package mirror.
# Decision record: docs/adr/asset_connector_adr.md
set -euo pipefail

MD=http://metadata.google.internal/computeMetadata/v1
mdv() { curl -fsS -H 'Metadata-Flavor: Google' "$MD/$1"; }

BUCKET=$(mdv instance/attributes/asset-bucket)
CORS=$(mdv instance/attributes/asset-cors-origin)
TAG=$(mdv instance/attributes/ts-tag)
TSV=$(mdv instance/attributes/ts-version)
TSSHA=$(mdv instance/attributes/ts-sha256)
CADV=$(mdv instance/attributes/caddy-version)
CADSHA=$(mdv instance/attributes/caddy-sha512)
RCV=$(mdv instance/attributes/rclone-version)
RCSHA=$(mdv instance/attributes/rclone-sha256)
TENANTS=$(mdv instance/attributes/asset-tenants)
CLIENTID=$(mdv instance/attributes/ts-client-id)
AUDIENCE=$(mdv instance/attributes/ts-audience)

token() { mdv instance/service-accounts/default/token | sed -E 's/.*"access_token":"([^"]+)".*/\1/'; }

# Wait on observed conditions (staged object, issued key); the retry count only bounds a failure.
retry() { # command...
  local n=0
  until "$@"; do
    n=$((n + 1))
    if [ "$n" -ge 720 ]; then echo "gave up waiting for: $*" >&2; return 1; fi
    sleep 60
  done
}

fetch_once() { # object-name destination
  local obj
  obj=$(printf '%s' "$1" | sed 's#/#%2F#g')
  curl -fsS -H "Authorization: Bearer $(token)" -o "$2" \
    "https://storage.googleapis.com/storage/v1/b/$BUCKET/o/$obj?alt=media"
}
fetch() { retry fetch_once "$1" "$2"; }

# Join with a Google-issued ID token for the VM identity, exchanged by Tailscale workload identity
# federation for a one-time tagged key. No key or secret is stored anywhere.
join_once() {
  local idt
  idt=$(mdv "instance/service-accounts/default/identity?audience=${AUDIENCE}&format=full")
  /usr/local/bin/tailscale up --client-id="${CLIENTID}?ephemeral=false&preauthorized=true"     --id-token="$idt" --hostname=asset-connector --advertise-tags="$TAG" --accept-dns=false --ssh=false
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ ! -x /usr/local/bin/tailscaled ]; then
  fetch "bootstrap/tailscale_${TSV}_amd64.tgz" "$work/ts.tgz"
  echo "$TSSHA  $work/ts.tgz" | sha256sum -c -
  tar -xzf "$work/ts.tgz" --strip-components=1 -C /usr/local/bin \
    "tailscale_${TSV}_amd64/tailscale" "tailscale_${TSV}_amd64/tailscaled"
fi

if [ ! -x /usr/local/bin/caddy ]; then
  fetch "bootstrap/caddy_${CADV}_linux_amd64.tar.gz" "$work/caddy.tgz"
  echo "$CADSHA  $work/caddy.tgz" | sha512sum -c -
  tar -xzf "$work/caddy.tgz" -C /usr/local/bin caddy
fi

if ! command -v rclone >/dev/null; then
  fetch "bootstrap/rclone-${RCV}-linux-amd64.deb" "$work/rclone.deb"
  echo "$RCSHA  $work/rclone.deb" | sha256sum -c -
  dpkg -i "$work/rclone.deb"
fi

id caddy >/dev/null 2>&1 || useradd --system --home /var/lib/caddy --create-home --shell /usr/sbin/nologin caddy

# TS_PERMIT_CERT_UID lets the caddy user obtain the tailnet certificate for the node name.
cat >/etc/systemd/system/tailscaled.service <<'UNIT'
[Unit]
Description=Tailscale node agent
After=network-online.target
Wants=network-online.target

[Service]
Environment=TS_PERMIT_CERT_UID=caddy
ExecStart=/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=41641
RuntimeDirectory=tailscale
StateDirectory=tailscale
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now tailscaled

ts_status=$(/usr/local/bin/tailscale status --json 2>/dev/null || true)
if ! grep -q '"BackendState": "Running"' <<<"$ts_status"; then
  retry join_once
fi

FQDN=$(/usr/local/bin/tailscale status --json | grep -m1 '"DNSName"' | sed -E 's/.*"DNSName": *"([^"]+)\.".*/\1/')

mkdir -p /srv/assets/releases /srv/status /var/lib/asset-cdn /etc/caddy
[ -e /srv/assets/current ] || { mkdir -p /srv/assets/releases/empty; ln -sfn /srv/assets/releases/empty /srv/assets/current; }
echo "ok last_sync=never" >/srv/status/healthz
: >/srv/status/metrics.prom
: >/srv/status/mirror.prom
chmod -R a+rX /srv

# Mirror: checksum sync of every tenant prefix into a fresh hard-linked release, then an atomic
# symlink swap. A failed sync leaves the previous release serving.
cat >/usr/local/bin/asset-cdn-sync <<SYNC
#!/bin/bash
set -euo pipefail
root=/srv/assets
cur=\$(readlink -f \$root/current)
new=\$root/releases/\$(date -u +%Y%m%dT%H%M%SZ).\$\$
cp -al "\$cur" "\$new"
trap 'rm -rf "\$new"' ERR
for t in ${TENANTS//,/ }; do
  mkdir -p "\$new/\$t"
  rclone sync ":googlecloudstorage:$BUCKET/\$t" "\$new/\$t" --gcs-env-auth --gcs-bucket-policy-only --checksum --transfers 4 --retries 3
done
chmod -R a+rX "\$new"
ln -sfn "\$new" \$root/current.tmp
mv -T \$root/current.tmp \$root/current
for old in \$(ls -1d \$root/releases/* | grep -v -e "\$new" -e "\$cur" || true); do rm -rf "\$old"; done
now=\$(date +%s)
echo "ok last_sync=\$now" >/srv/status/healthz
files=\$(find "\$new" -type f | wc -l)
bytes=\$(du -sb "\$new" | cut -f1)
cat >/srv/status/mirror.prom <<PROM
asset_cdn_mirror_last_success_unix \$now
asset_cdn_mirror_files \$files
asset_cdn_mirror_bytes \$bytes
PROM
chmod a+r /srv/status/*
SYNC
chmod 755 /usr/local/bin/asset-cdn-sync

# Monthly egress from the primary interface counter (what the cloud meters), kept across reboots.
cat >/usr/local/bin/asset-cdn-egress <<'EGRESS'
#!/bin/bash
set -euo pipefail
iface=$(ls /sys/class/net | grep -v -e '^lo$' -e '^tailscale' | head -1)
tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes")
ym=$(date -u +%Y-%m)
state=/var/lib/asset-cdn/egress.state
read -r s_ym s_tx s_total 2>/dev/null <"$state" || { s_ym=$ym; s_tx=$tx; s_total=0; }
[ "$s_ym" = "$ym" ] || { s_ym=$ym; s_total=0; }
if [ "$tx" -ge "$s_tx" ]; then s_total=$((s_total + tx - s_tx)); else s_total=$((s_total + tx)); fi
echo "$s_ym $tx $s_total" >"$state"
{
  echo "asset_cdn_egress_bytes_month $s_total"
  awk -v t="$s_total" 'BEGIN { printf "asset_cdn_egress_free_ratio %.4f\n", t/1073741824 }'
  cat /srv/status/mirror.prom
} >/srv/status/metrics.prom.tmp
chmod a+r /srv/status/metrics.prom.tmp
mv /srv/status/metrics.prom.tmp /srv/status/metrics.prom
EGRESS
chmod 755 /usr/local/bin/asset-cdn-egress

path_matchers=$(for t in ${TENANTS//,/ }; do printf '/%s/* ' "$t"; done)
# One tailnet site: tenant prefixes only, read-only, no compression, immutable cache headers.
cat >/etc/caddy/Caddyfile <<CADDY
{
	admin off
	servers {
		metrics
	}
}

$FQDN {
	@tenants path $path_matchers
	@manifest path */manifest.json
	@write not method GET HEAD OPTIONS
	@preflight method OPTIONS

	handle /healthz {
		root * /srv/status
		rewrite * /healthz
		header Content-Type text/plain
		file_server
	}
	handle /_stats {
		root * /srv/status
		rewrite * /metrics.prom
		header Content-Type text/plain
		file_server
	}
	handle /_metrics {
		metrics
	}
	handle @tenants {
		handle @write {
			respond 403
		}
		header Access-Control-Allow-Origin "$CORS"
		header Access-Control-Expose-Headers "Content-Length, Content-Range, ETag, Accept-Ranges"
		header Vary Origin
		handle @preflight {
			header Access-Control-Allow-Methods "GET, HEAD, OPTIONS"
			header Access-Control-Allow-Headers "Range, If-None-Match"
			header Access-Control-Max-Age 86400
			respond 204
		}
		handle @manifest {
			header Cache-Control "no-cache"
			root * /srv/assets/current
			file_server
		}
		handle {
			header Cache-Control "public, max-age=31536000, immutable"
			root * /srv/assets/current
			file_server
		}
	}
	handle {
		respond 404
	}
}
CADDY

cat >/etc/systemd/system/caddy.service <<'UNIT'
[Unit]
Description=Caddy asset mirror server
After=tailscaled.service
Wants=tailscaled.service

[Service]
User=caddy
Environment=XDG_DATA_HOME=/var/lib/caddy
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/caddy run --config /etc/caddy/Caddyfile
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/asset-cdn-sync.service <<'UNIT'
[Service]
Type=oneshot
ExecStart=/usr/local/bin/asset-cdn-sync
ExecStartPost=/usr/local/bin/asset-cdn-egress
UNIT
cat >/etc/systemd/system/asset-cdn-sync.timer <<'UNIT'
[Timer]
OnBootSec=1min
OnUnitActiveSec=30min

[Install]
WantedBy=timers.target
UNIT
cat >/etc/systemd/system/asset-cdn-egress.service <<'UNIT'
[Service]
Type=oneshot
ExecStart=/usr/local/bin/asset-cdn-egress
UNIT
cat >/etc/systemd/system/asset-cdn-egress.timer <<'UNIT'
[Timer]
OnBootSec=1min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT

/usr/local/bin/caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl daemon-reload
systemctl enable --now caddy asset-cdn-sync.timer asset-cdn-egress.timer
