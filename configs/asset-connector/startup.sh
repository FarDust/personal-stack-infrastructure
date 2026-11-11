#!/bin/bash
# Idempotent boot script of the asset CDN node. IPv6-only VM: every download goes to
# storage.googleapis.com through Private Google Access, never through an apt mirror.
# Decision record: docs/adr/asset_connector_adr.md
set -euo pipefail

MD=http://metadata.google.internal/computeMetadata/v1
mdv() { curl -fsS -H 'Metadata-Flavor: Google' "$MD/$1"; }

BUCKET=$(mdv instance/attributes/asset-bucket)
CORS=$(mdv instance/attributes/asset-cors-origin)
TAG=$(mdv instance/attributes/ts-tag)
TSV=$(mdv instance/attributes/ts-version)
TSSHA=$(mdv instance/attributes/ts-sha256)
NGV=$(mdv instance/attributes/nginx-version)
NGSHA=$(mdv instance/attributes/nginx-deb-sha256)
NGCSHA=$(mdv instance/attributes/nginx-common-sha256)
TENANTS=$(mdv instance/attributes/asset-tenants)
SECRET=$(mdv instance/attributes/ts-authkey-secret)
PROJECT=$(mdv project/project-id)

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

fetch_authkey_once() {
  curl -fsS -H "Authorization: Bearer $(token)" \
    "https://secretmanager.googleapis.com/v1/projects/$PROJECT/secrets/$SECRET/versions/latest:access" \
    | sed -E 's/.*"data": *"([^"]+)".*/\1/' | base64 -d >"$work/authkey"
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ ! -x /usr/local/bin/tailscaled ]; then
  fetch "bootstrap/tailscale_${TSV}_amd64.tgz" "$work/ts.tgz"
  echo "$TSSHA  $work/ts.tgz" | sha256sum -c -
  tar -xzf "$work/ts.tgz" --strip-components=1 -C /usr/local/bin \
    "tailscale_${TSV}_amd64/tailscale" "tailscale_${TSV}_amd64/tailscaled"
fi

if ! command -v nginx >/dev/null; then
  fetch "bootstrap/nginx-common_${NGV}_all.deb" "$work/nginx-common.deb"
  fetch "bootstrap/nginx_${NGV}_amd64.deb" "$work/nginx.deb"
  echo "$NGCSHA  $work/nginx-common.deb" | sha256sum -c -
  echo "$NGSHA  $work/nginx.deb" | sha256sum -c -
  DEBIAN_FRONTEND=noninteractive dpkg -i "$work/nginx-common.deb" "$work/nginx.deb"
fi

cat >/etc/systemd/system/tailscaled.service <<'UNIT'
[Unit]
Description=Tailscale node agent
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=41641
RuntimeDirectory=tailscale
StateDirectory=tailscale
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now tailscaled

if ! /usr/local/bin/tailscale status --json | grep -q '"BackendState": "Running"'; then
  retry fetch_authkey_once
  chmod 600 "$work/authkey"
  /usr/local/bin/tailscale up --auth-key="file:$work/authkey" --hostname=asset-connector \
    --advertise-tags="$TAG" --accept-dns=false --ssh=false
fi

FQDN=$(/usr/local/bin/tailscale status --json | grep -m1 '"DNSName"' | sed -E 's/.*"DNSName": *"([^"]+)\.".*/\1/')

# Tailnet certificate for the node name; renewed weekly by a timer.
mkdir -p /etc/asset-cdn/tls /run/asset-cdn /var/lib/asset-cdn /var/cache/asset-cdn
cat >/usr/local/bin/asset-cdn-cert <<CERT
#!/bin/bash
set -euo pipefail
/usr/local/bin/tailscale cert --cert-file /etc/asset-cdn/tls/cert.pem --key-file /etc/asset-cdn/tls/key.pem $FQDN
chmod 640 /etc/asset-cdn/tls/key.pem
chgrp www-data /etc/asset-cdn/tls/key.pem
if systemctl is-active --quiet nginx; then systemctl reload nginx; fi
CERT
chmod 755 /usr/local/bin/asset-cdn-cert
/usr/local/bin/asset-cdn-cert

# Short-lived bearer for the bucket, refreshed from the VM identity (no keys on disk).
cat >/usr/local/bin/asset-cdn-token <<TOKEN
#!/bin/bash
set -euo pipefail
t=\$(curl -fsS -H 'Metadata-Flavor: Google' $MD/instance/service-accounts/default/token | sed -E 's/.*"access_token":"([^"]+)".*/\1/')
umask 027
printf 'proxy_set_header Authorization "Bearer %s";\n' "\$t" >/run/asset-cdn/auth.conf.tmp
chgrp www-data /run/asset-cdn/auth.conf.tmp
mv /run/asset-cdn/auth.conf.tmp /run/asset-cdn/auth.conf
if systemctl is-active --quiet nginx; then systemctl reload nginx; fi
TOKEN
chmod 755 /usr/local/bin/asset-cdn-token
/usr/local/bin/asset-cdn-token

# Monthly egress and cache hit ratio from the access log, exposed for Prometheus on /_egress.
cat >/usr/local/bin/asset-cdn-stats <<'STATS'
#!/bin/bash
set -euo pipefail
ym=$(date -u +%Y-%m)
zcat -f /var/log/nginx/cdn.log* 2>/dev/null | awk -v ym="$ym" '
  substr($1,1,7)==ym { bytes+=$3; if ($4=="HIT"||$4=="STALE"||$4=="UPDATING"||$4=="REVALIDATED") hit++; else if ($4=="MISS"||$4=="EXPIRED"||$4=="BYPASS") miss++ }
  END {
    printf "# TYPE asset_cdn_egress_bytes_month gauge\nasset_cdn_egress_bytes_month %d\n", bytes
    printf "# TYPE asset_cdn_egress_free_ratio gauge\nasset_cdn_egress_free_ratio %.4f\n", bytes/1073741824
    printf "# TYPE asset_cdn_cache_hit_ratio gauge\nasset_cdn_cache_hit_ratio %.4f\n", (hit+miss>0)?hit/(hit+miss):0
  }' >/var/lib/asset-cdn/egress.prom.tmp
mv /var/lib/asset-cdn/egress.prom.tmp /var/lib/asset-cdn/egress.prom
STATS
chmod 755 /usr/local/bin/asset-cdn-stats

TENANT_RE=$(printf '%s' "$TENANTS" | tr ',' '|')
rm -f /etc/nginx/sites-enabled/default
cat >/etc/nginx/conf.d/asset-cdn.conf <<NGINX
proxy_cache_path /var/cache/asset-cdn levels=1:2 keys_zone=assets:10m max_size=6g inactive=90d use_temp_path=off;
log_format cdn '\$time_iso8601 \$status \$bytes_sent \$upstream_cache_status "\$request" \$request_time';
resolver 169.254.169.254 valid=300s ipv6=off;

server {
	listen 443 ssl http2;
	listen [::]:443 ssl http2;
	server_name $FQDN;
	ssl_certificate /etc/asset-cdn/tls/cert.pem;
	ssl_certificate_key /etc/asset-cdn/tls/key.pem;
	access_log /var/log/nginx/cdn.log cdn;
	server_tokens off;

	location = /healthz { default_type text/plain; return 200 "ok\n"; }
	location = /_status { stub_status; }
	location = /_egress { alias /var/lib/asset-cdn/egress.prom; default_type text/plain; }

	location ~ ^/(?<tenant>$TENANT_RE)/(?<obj>.*[^/])\$ {
		limit_except GET HEAD OPTIONS { deny all; }
		if (\$request_method = OPTIONS) {
			add_header Access-Control-Allow-Origin "$CORS" always;
			add_header Access-Control-Allow-Methods "GET, HEAD, OPTIONS" always;
			add_header Access-Control-Allow-Headers "Range, If-None-Match" always;
			add_header Access-Control-Max-Age 86400 always;
			return 204;
		}
		set \$upstream storage.googleapis.com;
		include /run/asset-cdn/auth.conf;
		proxy_set_header Host storage.googleapis.com;
		proxy_set_header Cookie "";
		slice 4m;
		proxy_set_header Range \$slice_range;
		proxy_cache assets;
		proxy_cache_key \$uri\$slice_range;
		proxy_cache_valid 200 206 1h;
		proxy_cache_lock on;
		proxy_cache_lock_timeout 30s;
		proxy_cache_background_update on;
		proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
		proxy_http_version 1.1;
		proxy_ssl_server_name on;
		proxy_hide_header x-goog-hash;
		proxy_hide_header x-guploader-uploadid;
		add_header Access-Control-Allow-Origin "$CORS" always;
		add_header Access-Control-Expose-Headers "Content-Length, Content-Range, ETag, Accept-Ranges" always;
		add_header Vary Origin always;
		add_header X-Cache \$upstream_cache_status always;
		proxy_pass https://\$upstream/$BUCKET/\$tenant/\$obj;
	}

	location / { return 404; }
}
NGINX

cat >/etc/systemd/system/asset-cdn-maint.service <<'UNIT'
[Service]
Type=oneshot
ExecStart=/usr/local/bin/asset-cdn-token
ExecStart=/usr/local/bin/asset-cdn-stats
UNIT
cat >/etc/systemd/system/asset-cdn-maint.timer <<'UNIT'
[Timer]
OnBootSec=5min
OnUnitActiveSec=30min

[Install]
WantedBy=timers.target
UNIT
cat >/etc/systemd/system/asset-cdn-cert.service <<'UNIT'
[Service]
Type=oneshot
ExecStart=/usr/local/bin/asset-cdn-cert
UNIT
cat >/etc/systemd/system/asset-cdn-cert.timer <<'UNIT'
[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
UNIT

/usr/local/bin/asset-cdn-stats
nginx -t
systemctl daemon-reload
systemctl enable --now asset-cdn-maint.timer asset-cdn-cert.timer nginx
systemctl reload nginx
