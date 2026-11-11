# ADR: Private asset CDN on the tailnet (asset connector)

Status: accepted (owner decision and approval of the design, 2026-11-11). Implementation: `configs/asset-connector`, tested in `tests/asset_connector.tftest.hcl`.

All deployment identifiers (project, region, zone, bucket, hostnames, principals) are Terraform Cloud workspace variables or private notes; this document uses placeholders such as `<region>`, `<bucket>` and `<tailnet-host>`.

## Context

A travelling user reaches the application origin over a long path (hundreds of milliseconds round trip, worse through relays). Heavy, immutable assets (images, tiles, bundles) dominate transfer time. The owner accepts a private cloud bucket behind a tailnet connector, but only if the whole design stays in the free tier, with no public bucket, no public route and no third-party CDN.

## Decision

An internal CDN for tailnet clients, made of three parts.

1. **One private regional bucket** in a free-tier region (`<region>` is one of us-west1, us-central1, us-east1). Uniform bucket-level access, public access prevention enforced, versioning off, abort-incomplete-multipart lifecycle rule.
2. **A caching reverse proxy on one e2-micro** in the same region, joined to the tailnet with a tag, with no external IPv4 address. It reads the bucket through its attached service account (object viewer on the bucket, no keys) and serves HTTPS only to tailnet peers.
3. **Out-of-band operations**: a Typer CLI for sync, warm and purge, and Prometheus-scrapable text endpoints.

### Multi-tenant contract

- Layout: `<bucket>/<tenant>/<content-hashed-name>`. A tenant is a project slug (for example the first tenant is the travel route app). `bootstrap/` is reserved for pinned binaries and is never served.
- Objects are immutable and named by content hash. Each tenant publishes a manifest object (`manifest.json`, short `Cache-Control`) listing hashed names, sizes and hashes; clients and the warm CLI read it.
- Writers: one service account per tenant, granted object user on the bucket with an IAM condition on the tenant prefix. Extra writer principals per tenant come from a workspace variable. No keys are created; writers use workload identity or approved user credentials.
- Readers: the connector service account only (object viewer). Browsers never talk to the bucket.
- Initial hostname: the connector's tailnet node name (the tailnet-issued certificate covers it). A friendlier name under the private cluster domain, with its own certificate (DNS-01 on the cluster) and DNS record, is a documented follow-up; the cluster domain currently resolves through a wildcard to the cluster manager, so that record must be explicit. DNS is not changed by this PR.
- Public URL shape: `https://<cdn-host>/<tenant>/<hashed-name>`. The CDN name is a record under the private cluster domain that points to the connector's tailnet address; resolution stays on the tailnet DNS path with no aliases or split-DNS.
- Request authorisation: tailnet policy only. The connector exposes nothing to the internet except the WireGuard UDP port.

### Network design (no paid IPv4, no NAT)

- Dual-stack subnet with `ipv6_access_type = EXTERNAL` and Private Google Access. The instance has an external IPv6 address and no `access_config`, so it has no billable external IPv4 and needs no Cloud NAT.
- Firewall: ingress UDP 41641 from `::/0` for direct tailnet paths, nothing else. Control plane, relay servers and the Google APIs are reached over IPv6 and Private Google Access.
- The VM boots without any package mirror. Tailscale (pinned static tarball) and nginx (the pinned Debian package pair) are staged under `bootstrap/` in the bucket and verified by SHA-256 before install. Hashes come from the publishers (Tailscale release checksum, Debian signed archive).
- The tailnet auth key (one-time, tagged, pre-authorized) is issued by the tailnet workflow into a sensitive workspace variable and written by Terraform as a write-only Secret Manager version, so it is not stored in Terraform state. The VM identity has accessor on that one secret, and the boot script waits (bounded retries) until the staged packages and the key exist. No Tailscale deploy credential is held in OpenBao or trust-agent.
- HTTPS certificate: the tailnet-issued certificate for the node name, renewed weekly. This needs HTTPS certificates enabled on the tailnet (it is).

### Caching behaviour (nginx)

- `proxy_cache` on the 10 GB standard boot disk (6 GB cap), 4 MB `slice` so range requests and resumed downloads fill and hit cache per slice, `proxy_cache_lock` so concurrent misses make one upstream read, `proxy_cache_background_update` and stale-on-error/timeout/5xx so the node keeps serving through bucket or network hiccups.
- Hashed objects carry `Cache-Control: public, max-age=31536000, immutable` as object metadata, set by the uploader; nginx honours it. Manifests carry a short max-age with stale-while-revalidate.
- No compression module: JPEG/WebP pass through byte-identical. ETag and Last-Modified pass through. CORS allows one configured origin, GET, HEAD, OPTIONS, and the Range header.
- Only the configured tenant prefixes are routed; other paths return 404, directory-style paths return 404, non-read methods are rejected.
- Access log: `/var/log/nginx/cdn.log`, rotated by the stock logrotate policy, with the upstream cache status.

### Observability

- `/healthz` (liveness), `/_status` (nginx `stub_status`) and `/_egress` (text metrics: monthly bytes sent, fraction of the free egress used, cache hit ratio from the log), all reachable only over the tailnet. The planned scrape: the cluster's Prometheus scrapes `/_egress` directly and `/_status` through the stock nginx exporter; scrape configuration is added later by the cluster owners and is not part of this change.
- Logging stays inside the free quota: the node writes local logs only (no Ops Agent), so Cloud Logging ingestion is not used.

### Cost guards

Free-tier limits relied on (Google free-tier page, checked 2026-11-11): one non-preemptible e2-micro in us-west1/us-central1/us-east1, 30 GB-months standard disk, 1 GB per month egress from North America to most destinations, 5 GB-months regional storage in those regions, 5,000 class A and 50,000 class B operations.

- **The metered path is VM egress to clients, not the bucket read.** Bucket to VM in the same region is free. A cache hit therefore protects latency, class B operation count and resilience; it does not reduce the bytes sent to clients. The egress budget is set by how many clients download how much: assume 45 MB assets times 8 travellers times about 2 full downloads, about 0.7 GB per month, which fits in 1 GB with a thin margin. Larger tenants need a decision before onboarding.
- Alerts: a Cloud Monitoring policy on the VM's daily sent bytes, with the threshold configurable (default 25 MiB per day, about 0.75 GB per month), a labelled budget alert (default 5 USD) and a monthly report from `/_egress`. The `/_egress` ratio can drive a Grafana alert at 0.8.
- Expected hit ratio after warm-up: above 0.9 for hashed assets because each object is fetched from the bucket once per cache lifetime; the ratio measures bucket reads, not client egress.
- Rollback: `terraform destroy` of the module and removal of the DNS record. The application keeps serving from its origin; the asset base URL is configuration in the manifest.

## Alternatives considered

- Public bucket or a third-party CDN: rejected by the owner (no public path).
- Forwarder without cache: simpler, but loses range resume, stale serving and single-flight misses.
- Caddy as the proxy: no built-in cache without a custom build; nginx's cache, slice and stale handling are first-class and ship as a distro package.
- External IPv4 or Cloud NAT: about 3.7 USD per month or more; not accepted unless the IPv6-only design fails with evidence and the owner approves.
- Packages through a mirror at boot: depends on mirror reachability over IPv6; staging pinned artifacts in the private bucket removes that dependency.
- Tailscale Serve or a Cloud Run service: Cloud Run is not tailnet-reachable without extra components.

## Consequences

- The connector is a single node; a failure falls back to the origin through the application's fallback.
- Pinned artifacts must be re-staged and their hashes updated in workspace variables when upgrading.
- The startup script is a deliberate shell exception: it is a boot-time launcher and a unit-file generator with no business logic; behaviour lives in nginx and systemd.
- Costs depend on usage: egress beyond 1 GB per month is billed at the standard rate (about 0.12 USD per GB, unverified).
- Tailnet policy needs a tag owner entry and a grant for the tag (not applied by this change).

## Verification

- `terraform test` covers: private bucket flags, reader-only VM identity, prefix-conditioned writer grants, rejection of public writers, no external IPv4, dual-stack subnet with Private Google Access, single open UDP port, free-tier region and origin validation.
- The rendered nginx configuration is syntax-checked (`nginx -t`) and exercised in a container: health, status, tenant routing, 404 and method rejection, CORS preflight and cache behaviour.
- Throwaway apply (small, destroyed after): node joins the tailnet, shows a direct or relayed IPv6 path, reads the bucket, serves a cached object with a hit on the second request, and egress counters move.
