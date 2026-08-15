---
id: backlog-licensing-binary-notices
created: 2026-08-15
updated: 2026-08-15
tags: [licensing, cockpit, app]
---

# Licensing: binary-distribution notices + third-party license screens

From the adversarial licensing review (2026-08-15) — the two findings too big
to fix inline. Neither blocks the source repo going public; both gate future
Cockpit BINARY releases.

1. **Cockpit native LGPL stack.** media_kit bundles libmpv (+FFmpeg/FriBidi) —
   LGPL-2.1 in the default profile (mpv is GPLv2+ by default). Shipping
   cockpit macOS/Windows/Linux binaries requires: LGPL notices in the
   distribution, corresponding-source availability/offer for the LGPL
   components, and a check that the dynamic-linking/signature model preserves
   replacement rights. The old Windows archive's linked build repos are
   unreachable — verify or rebuild before any redistribution. Do not
   advertise binaries as "MIT-only."
   Also MPL-2.0 `dbus` (via flutter_local_notifications_linux) — MPL needs
   the file-level notice retained; check packaging keeps it.

2. **Third-party licenses screen.** Neither app has LicensePage/about
   surfaces (BSD notice conditions for shadcn_flutter/gpt_markdown; OFL
   courtesy for Space Mono; the LGPL notices above want a home). Add an
   about/licenses screen in app + cockpit (Flutter's showLicensePage with
   LicenseRegistry, or installer-level THIRD_PARTY_NOTICES).

Clean bills already on record: upstream MIT attribution (root LICENSE/NOTICE,
pi-extension/LICENSE), icon pack = vscode-material-icon-theme 5.35.0 MIT with
its LICENSE bundled in the asset dir, fonts (Space Mono/Noto via google_fonts,
OFL-compliant), no viral deps anywhere (per-direct-dep verified).
LicenseRef-proprietary stale markers + identity LICENSE TODO + Runner.rc
phrase fixed in commit history 2026-08-15.
