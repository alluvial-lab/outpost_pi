---
id: story-app-ios-signing-ownership-cutover
kind: story
stage: implementing
tags: [rebrand, app, release, security]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-15
---

# Remove the inherited Apple team from active app distribution

## Review finding

**Severity:** Blocker

The distribution-ownership feature claims to close the remaining boundary so a
future release cannot publish as the upstream author, and its prescribed broad
ownership grep expects the inherited team ID to be absent outside historical
records. The active app distribution surface still hard-codes the same inherited
Apple team removed from Cockpit:

- `app/ios/ExportOptions.plist:10` selects team `U843T2P7A2` for App Store export;
- `app/ios/Runner.xcodeproj/project.pbxproj:496,679,702` selects that team for the Runner build configurations;
- `app/store_listing.md:8` presents it as the current Apple team;
- the identity plugin example Xcode project repeats the inherited team.

The live site still links the iOS App Store listing. Without an explicit owned
transfer/provisioning contract, this leaves an active release path that can sign
or export under the upstream team and directly contradicts the feature brief.

## Required outcome

- Establish the operator-owned iOS signing/distribution contract: parameterize or
  replace the inherited development team in active build/export configuration,
  and fail closed when operator-owned provisioning is absent.
- Remove the inherited team from current store-listing guidance and generated
  example metadata, or document a verified operator-owned transfer if the
  numeric team is no longer inherited (with durable evidence/rationale).
- Keep the public App Store availability claim only if the listing and signing
  path are operator-owned; otherwise mark that channel unavailable until the
  transfer/provisioning is complete.
- Re-run the distribution ownership grep across `app/`, `cockpit/`, `.github/`,
  and `site/`, distinguishing harmless fake path fixtures from active signing
  metadata.
- Run app analyze/tests and an appropriate no-codesign iOS project/config smoke.
