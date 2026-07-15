# Packaging & Release — Cockpit

Build/packaging runbook for the 3 platforms. Basis for the CI job
(`.github/workflows/cockpit-release.yml`, plan 43 step 3). Reference plan:
[`../../plan/43-cockpit-packaging.md`](../../plan/43-cockpit-packaging.md).

## Identity (step 1 — done)

| Item | Value |
|---|---|
| App ID (macOS bundle id / Linux app id) | `dev.kevoun.outpostpi.cockpit` |
| Display name | **Outpost-Pi Cockpit** |
| Binary | `cockpit` (Linux/Windows) / `Cockpit` (macOS) — **not** renamed |
| Team ID (Apple) | operator-owned, supplied via `APPLE_TEAM_ID` secret (not yet provisioned) |
| Version (SSOT) | `version:` in `pubspec.yaml` (`x.y.z+n`) |

> **One-way bundle-ID cutover.** Moving from the inherited
> `work.jacobmoura.cockpit` to `dev.kevoun.outpostpi.cockpit` means existing
> Cockpit installs **cannot upgrade in place** — macOS treats the new bundle ID
> as a different application. Users on the inherited build must **uninstall
> the old Cockpit and install the new one manually**. This is distinct from the
> separate disabled-self-update state below (which is about appcast
> publication, not the bundle-ID change).

- macOS: `PRODUCT_BUNDLE_IDENTIFIER` in `macos/Runner/Configs/AppInfo.xcconfig`;
  `CFBundleDisplayName` in `Info.plist`; **Hardened Runtime** enabled in Release
  (`ENABLE_HARDENED_RUNTIME = YES`, notarization requirement) with
  `Release.entitlements` (sandbox off — compatible with Developer ID).
- Windows: `CompanyName`/`ProductName`/`LegalCopyright` in
  `windows/runner/Runner.rc`; version comes from `FLUTTER_VERSION_*` defines
  (injected during build; `#else "1.0.0"` is only a fallback).
- Linux: `.desktop` + hicolor icons + `dev.kevoun.outpostpi.cockpit.metainfo.xml`
  (AppStream), installed through `linux/CMakeLists.txt`.

## Tool

[Fastforge](https://pub.dev/packages/fastforge) (successor to the discontinued
`flutter_distributor`):

```bash
dart pub global activate fastforge
```

Config: `distribute_options.yaml` (Cockpit root) + one `make_config.yaml` per
format. **Note the Fastforge path convention**: configs live in
`<platform>/packaging/<format>/make_config.yaml` (hardcoded in the loader), **not**
in `packaging/<platform>/...` as the plan diagram suggested:

```
macos/packaging/dmg/make_config.yaml
windows/packaging/exe/make_config.yaml
linux/packaging/deb/make_config.yaml
linux/packaging/rpm/make_config.yaml
```

## macOS — build + sign + DMG + notarize + staple (end to end)

Validated locally on 2026-06-12 (DMG accepted by Gatekeeper). Prerequisites:
a Developer ID Application identity supplied through CI secrets and the App Store
Connect API key. Set `APPLE_SIGNING_IDENTITY` to that identity for a local release.
CI reads `APPLE_SIGNING_IDENTITY` and `APPLE_TEAM_ID` from repository secrets and
fails closed before certificate import if either is absent; no signing identity is
committed to this repository.

```bash
cd cockpit

# 1. Universal build (x86_64 + arm64 — Flutter macOS release default).
: "${APPLE_SIGNING_IDENTITY:?Set APPLE_SIGNING_IDENTITY before signing}"
flutter build macos --release
APP="build/macos/Build/Products/Release/Cockpit.app"

# 2. Sign the .app with Developer ID + Hardened Runtime + Release entitlements.
codesign --force --deep --options runtime --timestamp \
  --entitlements macos/Runner/Release.entitlements \
  --sign "$APPLE_SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"   # check

# 3. Build the DMG (hdiutil — no dependencies; Fastforge maker uses `appdmg`
#    through npm, an alternative for CI). Layout: app + /Applications shortcut.
mkdir -p dist
STAGE=$(mktemp -d); cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
DMG="dist/OutpostPiCockpit-1.0.0-macos-universal.dmg"
hdiutil create -volname "Outpost-Pi Cockpit" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

# 4. Sign the DMG.
codesign --force --timestamp \
  --sign "$APPLE_SIGNING_IDENTITY" "$DMG"

# 5. Notarize (App Store Connect API key) and wait.
#    Supply the API key path/key-id/issuer via CI secrets or a local env; do
#    not commit operator credentials to the repository.
xcrun notarytool submit "$DMG" \
  --key "${APPLE_API_KEY_FILE:?Set APPLE_API_KEY_FILE to the .p8 path}" \
  --key-id "${APPLE_API_KEY_ID:?Set APPLE_API_KEY_ID}" \
  --issuer "${APPLE_API_ISSUER:?Set APPLE_API_ISSUER}" \
  --wait

# 6. Staple the ticket and validate.
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"   # → "accepted / Notarized Developer ID"
```

> **CI**: the Apple secrets are supplied as repository secrets
> (`MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `APPLE_API_KEY_ID`,
> `APPLE_API_ISSUER`, `APPLE_API_KEY`, `APPLE_SIGNING_IDENTITY`,
> `APPLE_TEAM_ID`). On the runner, import the `.p12` into a temporary keychain
> and write the `.p8` to a file before running the steps above. The operator's
> Developer ID is **not yet provisioned** — the workflow fails closed until
> these secrets exist. No signing identity or credential is committed to this
> repository.

## Windows — Inno Setup (`.exe`)

**Cannot be built on Mac.** CI `windows` job (`windows-latest`):

```bash
flutter build windows --release
fastforge package --platform windows --targets exe   # uses windows/packaging/exe/make_config.yaml
```

No signing at this stage (SmartScreen warning documented on the site). Artifact:
`OutpostPiCockpit-Setup-<v>-windows-x64.exe`.

## Linux — `.deb` + `.rpm` (x86_64 and arm64)

**Cannot be built on Mac.** CI jobs `linux-x64` (`ubuntu-24.04`) and `linux-arm64`
(`ubuntu-24.04-arm`):

```bash
sudo apt-get install -y rpm   # rpmbuild, to generate .rpm on Ubuntu runner
flutter build linux --release
fastforge package --platform linux --targets deb
fastforge package --platform linux --targets rpm
```

Runtime dependencies declared in `make_config.yaml` (GTK3 + base libs). **CI
pending work** (step 3): run `ldd` on the generated bundle to confirm/expand deps, and
validate installation in `ubuntu:24.04` (deb) and `fedora:40` (rpm) containers — this was
not possible on this Mac (no Linux build; Docker present but stopped).

## Self-update (currently disabled)

Auto-update appcasts are not currently published or deployed. Therefore, the runtime
does not configure feeds for macOS or Windows and uses `NoopSelfUpdater` on all
platforms. Cockpit updates depend on a new manual installation until appcast publication
resumes.

Windows appcast generation is also explicitly disabled in the release workflow. The
locked `auto_updater_windows` 1.0.0 plugin initializes WinSparkle 0.8.1 without calling
`win_sparkle_set_app_build_version()`. WinSparkle therefore reads the current version
from the executable's `VERSIONINFO` string (`x.y.z+n` from `Runner.rc`); a bare `+n`
appcast version is not paired with that domain. Re-enable Windows appcast generation
only after a Windows smoke proves that the chosen integration accepts a higher build
number and rejects an equal or lower one.

An inherited 1.5.1 Windows installation sorts above the reset 0.x marketing version and
must be replaced by one manual Outpost-Pi installation before any future 0.x update
contract can apply. The pipeline continues to generate the Windows installer needed for
that cutover.

## Next steps (plan 43)

- Step 3: `.github/workflows/cockpit-release.yml` (trigger `cockpit-v*`). **Done**
  (+ plan 47 self-update: `.app.zip` + signed appcasts).
- Step 4: `latest.json` layout on the VPS.
- Step 5: downloads page in `site/`.
- Step 6: release runbook (bump `version:` → tag → CI → smoke test).
