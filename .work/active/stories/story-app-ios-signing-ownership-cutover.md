---
id: story-app-ios-signing-ownership-cutover
kind: story
stage: done
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

## Implementation notes

- Files changed: `app/ios/ExportOptions.plist`, both app and identity-example
  `Runner.xcodeproj/project.pbxproj` files, `app/store_listing.md`, `README.md`,
  `docs/DECISIONS.md`, `pi-extension/README.md`, and the three active App Store
  availability surfaces under `site/src/`.
- Removed every committed app/example `DEVELOPMENT_TEAM` and omitted `teamID`
  from the automatic App Store export options. Simulator/no-codesign builds stay
  available, while device/archive signing has no repository default and requires
  the operator to select an owned team. Automatic export can resolve only from
  the team attached to an operator-owned signed archive.
- Marked iOS distribution unavailable until the operator provisions an Apple
  Developer team and owned listing. Future iOS CI must receive the team through
  the `APPLE_TEAM_ID` secret; inherited App Store links and availability claims
  were removed from active public docs/site surfaces.
- Discrepancy from the review prompt: `.github/workflows/app-release.yml` has no
  iOS build/export job; it publishes only the signed Android APK. No speculative
  iOS job was added. The current release path therefore fails closed by having
  no iOS publication channel, and the team remains unset in committed Xcode
  configuration.
- Verification: app `flutter analyze` passed with no issues; site `pnpm lint`
  and `pnpm build` passed; `ExportOptions.plist` and `app-release.yml` parsed;
  the requested inherited-identity grep returned no hits. A full/no-codesign iOS
  build was not run, as required by the task and because this Linux VM has no
  Apple codesigning toolchain.
- Tests added: none (signing metadata and current-state documentation only).
- Adjacent issues parked: none.

## Verification closure (2026-07-15, third pass)

`ExportOptions.plist` parses as an automatic App Store Connect export with no `teamID`; neither the app nor identity-example Xcode project contains `DEVELOPMENT_TEAM`; and the inherited team/author grep is empty across `app/ios/` and `app/store_listing.md`. Public docs/site surfaces consistently mark iOS unavailable until operator-owned provisioning. App analyze and all 698 tests passed. The child checkpoint advanced directly to `done`.
