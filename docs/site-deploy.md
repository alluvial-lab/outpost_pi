# Site + landing stubs — deploy runbook

Current-state runbook for the public web surface: `outpost-pi.kevoun.com`
(the Outpost-Pi site, Next standalone) plus static landing stubs for
`kevoun.com` and `dev.kevoun.com`. Target: one unprivileged Proxmox LXC with
Caddy terminating TLS; no other infrastructure.

Security posture (deliberate):

- The LXC holds **no secrets, no tailnet membership, no repo access** — it
  serves static files and the built Next app. Compromise impact is
  defacement; it cannot reach the relay (tailnet-only) or this dev VM.
- Stubs are zero-JS, zero-external-asset pages; CSP locks them to
  `default-src 'none'`. Strict headers at Caddy for all three hosts.
- `outpost-pi.kevoun.com/.well-known/assetlinks.json` (ships in the site
  build) anchors Android App Links pairing. **Ordering rule: the site must
  be live before an app/extension rollout that relies on pairing deep
  links.** **Signing-key rotation must update `assetlinks.json` in the same
  change** or pairing links stop verifying (fails safe: the app rejects
  unverified origins; QR scan + manual paste pairing never touch the site).

## 1. Provision the LXC

- Debian 12 template, unprivileged, 1 vCPU / 1 GB RAM / 8 GB disk.
- Network: reachable on 80/443 from the internet (DNS A/AAAA records for
  all three hosts → its address; port-forward on the router if NAT'd).
  HTTP-01 (port 80) must stay reachable — Caddy's TLS issuance depends on it.
- SSH (or console) access restricted to LAN/tailnet admin hosts.
- Packages: `curl`, `rsync` (deploy), Node 20 (nodesource) for the Next
  standalone server, `caddy` (official repo).

## 2. Layout

```
/opt/outpost-site/        # Next standalone bundle (from step 3)
/var/www/kevoun.com/      # stub: site/stubs/kevoun.com/index.html
/var/www/dev.kevoun.com/  # stub: site/stubs/dev.kevoun.com/index.html
/etc/caddy/Caddyfile
```

## 3. Build + deploy the site (from the dev VM)

From the repo root on the dev VM:

```bash
cd site && corepack pnpm install --frozen-lockfile && corepack pnpm build
# Assemble the standalone bundle:
rm -rf /tmp/site-deploy && mkdir -p /tmp/site-deploy
cp -r .next/standalone/. /tmp/site-deploy/
cp -r .next/static /tmp/site-deploy/.next/static
cp -r public /tmp/site-deploy/public
rsync -av --delete /tmp/site-deploy/ <lxc>:/opt/outpost-site/
rsync -av ../stubs/ <lxc>:/var/www/   # copies kevoun.com/ and dev.kevoun.com/
```

The standalone build is self-contained (node_modules included); the LXC only
needs the Node runtime.

## 4. systemd unit — `/etc/systemd/system/outpost-site.service`

```ini
[Unit]
Description=Outpost-Pi site (Next standalone)
After=network.target

[Service]
WorkingDirectory=/opt/outpost-site
Environment=PORT=3000
Environment=HOSTNAME=127.0.0.1
ExecStart=/usr/bin/node server.js
Restart=on-failure
# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/outpost-site/.next

[Install]
WantedBy=multi-user.target
```

`systemctl enable --now outpost-site`.

## 5. Caddyfile

```caddyfile
kevoun.com, dev.kevoun.com {
	root * /var/www/{host}
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
	reverse_proxy 127.0.0.1:3000
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		X-Content-Type-Options "nosniff"
		X-Frame-Options "DENY"
		Referrer-Policy "strict-origin-when-cross-origin"
	}
}
```

Notes: no CSP is imposed on the Next app at Caddy (the app owns its own
policy); stubs get the lock-tight CSP — `style-src 'unsafe-inline'` only
covers the single inline stylesheet, no scripts exist. `file_server`
without `browse` never lists directories. `systemctl reload caddy` after
edits; Caddy obtains certificates on first hit.

## 6. Verify

```bash
curl -sI https://kevoun.com                       # 200 + headers
curl -sI https://dev.kevoun.com                   # 200 + headers
curl -sI https://outpost-pi.kevoun.com            # 200 via node
curl -s https://outpost-pi.kevoun.com/.well-known/assetlinks.json | head
```

App Links (after installing a release-signed build):
`adb shell pm verify-app-links --re-verify dev.kevoun.outpostpi` then
`adb shell pm get-app-links dev.kevoun.outpostpi` (expect `verified`), and
open a dummy `https://outpost-pi.kevoun.com/pair#...` link — it must open
the app, not a chooser. These checks are part of `docs/release-uat.md`.

## Redeploys

Repeat step 3; the standalone server picks up new files on restart
(`systemctl restart outpost-site`). Stub-only changes: just the stubs
rsync line. The exposure guard (`scripts/check-public-exposure.sh`) covers
repo content at build time; host hardening is standard LXC hygiene.
