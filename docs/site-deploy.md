# Site + landing stubs — deploy runbook

Current-state runbook for the public web surface: `outpost-pi.kevoun.com`
(the Outpost-Pi site, Next standalone) plus static landing stubs for
`kevoun.com` and `dev.kevoun.com`.

**Topology (operator, 2026-08-26): the existing Caddy edge fronts
everything.** The app LXC is backend-only — tailnet/LAN reachable, never
internet-facing. Stubs are static files served by the edge Caddy directly.
An alternative LXC-local-Caddy variant works but adds a second TLS/public
path for no benefit.

Security posture (deliberate):

- The LXC holds **no secrets, no repo access**, and is not reachable from
  the internet — only from the Caddy host over tailnet/LAN on one port.
  Compromise impact is bounded to the site's content; it cannot reach the
  relay (tailnet-only, separate ACL) or the dev VM.
- Stubs are zero-JS, zero-external-asset pages; CSP locks them to
  `default-src 'none'`. Strict headers at the edge for all three hosts.
- `outpost-pi.kevoun.com/.well-known/assetlinks.json` (ships in the site
  build) anchors Android App Links pairing — Android fetches it over public
  HTTPS through the edge Caddy, which satisfies verification. **Ordering
  rule: the site must be live before an app/extension rollout that relies
  on pairing deep links.** **Signing-key rotation must update
  `assetlinks.json` in the same change** or pairing links stop verifying
  (fails safe: the app rejects unverified origins; QR scan + manual paste
  pairing never touch the site).

## 1. Provision the app LXC

- Debian 12 template, unprivileged, 1 vCPU / 1 GB RAM / 8 GB disk.
- Network: tailnet (or LAN) only. No public 80/443, no port-forwards, no
  DNS records pointing at it.
- Firewall: allow inbound `:3000` **only from the Caddy host's IP**; SSH
  from admin hosts only.
- Packages: `curl`, `rsync` (deploy), Node 20 (nodesource). No Caddy.

## 2. Layout

```
LXC:   /opt/outpost-site/            # Next standalone bundle (step 3)
EDGE:  /srv/stubs/kevoun.com/        # stub: site/stubs/kevoun.com/index.html
EDGE:  /srv/stubs/dev.kevoun.com/    # stub: site/stubs/dev.kevoun.com/index.html
EDGE:  /etc/caddy/Caddyfile          # + blocks below
```

## 3. Build + stage (on the dev VM) — deploy is two-hop

The dev VM has **no network path to the LXC or the edge Caddy** (operator
confirmed 2026-08-26). The operator relays artifacts via their machine
(192.168.50.110):

On the dev VM:

```bash
cd site && corepack pnpm install --frozen-lockfile && corepack pnpm build
rm -rf /tmp/outpost-site-deploy && mkdir -p /tmp/outpost-site-deploy/site
cp -r .next/standalone/. /tmp/outpost-site-deploy/site/
cp -r .next/static /tmp/outpost-site-deploy/site/.next/static
cp -r public /tmp/outpost-site-deploy/site/public
cp -r stubs /tmp/outpost-site-deploy/stubs
# (+ DEPLOY.txt quick instructions)
tar -C /tmp -czf /tmp/outpost-site-deploy.tar.gz outpost-site-deploy
```

Pull the tarball to the operator machine, then from there:

```bash
rsync -av --delete outpost-site-deploy/site/ <lxc>:/opt/outpost-site/
rsync -av outpost-site-deploy/stubs/kevoun.com/ <edge>:/srv/stubs/kevoun.com/
rsync -av outpost-site-deploy/stubs/dev.kevoun.com/ <edge>:/srv/stubs/dev.kevoun.com/
```

The standalone build is self-contained (node_modules included); the LXC only
needs the Node runtime. The `public/` copy is what puts `assetlinks.json`
on the wire. The tarball is a one-shot artifact (rebuildable via this step);
never commit it.

## 4. systemd unit on the LXC — `/etc/systemd/system/outpost-site.service`

```ini
[Unit]
Description=Outpost-Pi site (Next standalone)
After=network.target

[Service]
WorkingDirectory=/opt/outpost-site
Environment=PORT=3000
# Bind the interface the edge Caddy reaches (tailnet IP, or 0.0.0.0 with the
# host firewall restricting source to the Caddy host):
Environment=HOSTNAME=0.0.0.0
ExecStart=/usr/bin/node server.js
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/outpost-site/.next

[Install]
WantedBy=multi-user.target
```

`systemctl enable --now outpost-site`.

## 5. Edge Caddy blocks (add to the existing Caddyfile)

```caddyfile
kevoun.com, dev.kevoun.com {
	root * /srv/stubs/{host}
	file_server
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		X-Content-Type-Options "nosniff"
		X-Frame-Options "DENY"
		Referrer-Policy "no-referrer"
		Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'"
		Permissions-Policy "camera=(), microphone=(), geolocation=()"
	}
}

outpost-pi.kevoun.com {
	reverse_proxy <lxc-tailnet-ip>:3000
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		X-Content-Type-Options "nosniff"
		X-Frame-Options "DENY"
		Referrer-Policy "strict-origin-when-cross-origin"
	}
}
```

Notes: `file_server` without `browse` never lists directories. The stub
CSP allows only the single inline stylesheet; no scripts exist. The edge
Caddy already handles ACME for its domains — adding these host blocks
obtains their certificates automatically on first traffic (its 80/443
reachability is what matters; the LXC has none). `systemctl reload caddy`
after the edit.

## 6. Verify

```bash
curl -sI https://kevoun.com                       # 200 + headers
curl -sI https://dev.kevoun.com                   # 200 + headers
curl -sI https://outpost-pi.kevoun.com            # 200 via edge → LXC
curl -s https://outpost-pi.kevoun.com/.well-known/assetlinks.json | head
```

App Links (after installing a release-signed build):
`adb shell pm verify-app-links --re-verify dev.kevoun.outpostpi` then
`adb shell pm get-app-links dev.kevoun.outpostpi` (expect `verified`), and
open a dummy `https://outpost-pi.kevoun.com/pair#...` link — it must open
the app, not a chooser. These checks are part of `docs/release-uat.md`.

## Redeploys

Rebuild + restage the tarball on the dev VM, pull it, and rsync (the
two-hop flow above); restart the app on the LXC (`systemctl restart
outpost-site`). Stub-only changes: restage stubs + the two stub rsync lines
from the operator machine (no restart — `file_server` reads per request). The exposure guard
(`scripts/check-public-exposure.sh`) covers repo content at build time;
host hardening is standard LXC hygiene.
