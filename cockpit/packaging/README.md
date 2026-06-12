# Empacotamento & Release — Cockpit

Runbook de build/empacotamento das 3 plataformas. Base pro job de CI
(`.github/workflows/cockpit-release.yml`, plano 43 passo 3). Plano de
referência: [`../../plan/43-cockpit-packaging.md`](../../plan/43-cockpit-packaging.md).

## Identidade (passo 1 — feito)

| Item | Valor |
|---|---|
| App ID (macOS bundle id / Linux app id) | `work.jacobmoura.cockpit` |
| Nome de exibição | **Remote Pi Cockpit** |
| Binário | `cockpit` (Linux/Windows) / `Cockpit` (macOS) — **não** renomeado |
| Team ID (Apple) | `U843T2P7A2` |
| Versão (SSOT) | `version:` do `pubspec.yaml` (`x.y.z+n`) |

- macOS: `PRODUCT_BUNDLE_IDENTIFIER` em `macos/Runner/Configs/AppInfo.xcconfig`;
  `CFBundleDisplayName` em `Info.plist`; **Hardened Runtime** ligado no Release
  (`ENABLE_HARDENED_RUNTIME = YES`, exigência da notarização) com
  `Release.entitlements` (sandbox off — compatível com Developer ID).
- Windows: `CompanyName`/`ProductName`/`LegalCopyright` em
  `windows/runner/Runner.rc`; versão vem dos defines `FLUTTER_VERSION_*`
  (injetados em build; o `#else "1.0.0"` é só fallback).
- Linux: `.desktop` + ícones hicolor + `work.jacobmoura.cockpit.metainfo.xml`
  (AppStream), instalados via `linux/CMakeLists.txt`.

## Ferramenta

[Fastforge](https://pub.dev/packages/fastforge) (sucessor do `flutter_distributor`,
descontinuado):

```bash
dart pub global activate fastforge
```

Config: `distribute_options.yaml` (raiz do cockpit) + um `make_config.yaml` por
formato. **Atenção à convenção de path do Fastforge**: os configs ficam em
`<plataforma>/packaging/<formato>/make_config.yaml` (hardcoded no loader), **não**
em `packaging/<plataforma>/...` como o diagrama do plano sugeria:

```
macos/packaging/dmg/make_config.yaml
windows/packaging/exe/make_config.yaml
linux/packaging/deb/make_config.yaml
linux/packaging/rpm/make_config.yaml
```

## macOS — build + sign + DMG + notarize + staple (ponta a ponta)

Validado localmente em 2026-06-12 (DMG aceito pelo Gatekeeper). Pré-requisitos:
identidade **"Developer ID Application: Jacob Moura (U843T2P7A2)"** no Keychain e
a API key do App Store Connect.

```bash
cd cockpit

# 1. Build universal (x86_64 + arm64 — default do Flutter macOS release).
flutter build macos --release
APP="build/macos/Build/Products/Release/Cockpit.app"

# 2. Assina o .app com Developer ID + Hardened Runtime + entitlements de Release.
codesign --force --deep --options runtime --timestamp \
  --entitlements macos/Runner/Release.entitlements \
  --sign "Developer ID Application: Jacob Moura (U843T2P7A2)" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"   # checagem

# 3. Monta o DMG (hdiutil — sem dependências; o maker do Fastforge usa `appdmg`
#    via npm, alternativa pra CI). Layout: app + atalho /Applications.
mkdir -p dist
STAGE=$(mktemp -d); cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
DMG="dist/RemotePiCockpit-1.0.0-macos-universal.dmg"
hdiutil create -volname "Remote Pi Cockpit" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

# 4. Assina o DMG.
codesign --force --timestamp \
  --sign "Developer ID Application: Jacob Moura (U843T2P7A2)" "$DMG"

# 5. Notariza (App Store Connect API key) e aguarda.
xcrun notarytool submit "$DMG" \
  --key /Users/jacob/Documents/CockpitApp/AuthKey_3Y2J8MA3M4.p8 \
  --key-id 3Y2J8MA3M4 \
  --issuer a76c76e6-a413-449e-926c-f2c30d5645c4 \
  --wait

# 6. Grampeia o ticket e valida.
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"   # → "accepted / Notarized Developer ID"
```

> **CI**: os 5 secrets Apple já estão no repo (`MACOS_CERT_P12`,
> `MACOS_CERT_PASSWORD`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, `APPLE_API_KEY`).
> No runner, importar o `.p12` num keychain temporário e escrever a `.p8` num
> arquivo antes de rodar os passos acima.

## Windows — Inno Setup (`.exe`)

**Não buildável no Mac.** Job `windows` do CI (`windows-latest`):

```bash
flutter build windows --release
fastforge package --platform windows --targets exe   # usa windows/packaging/exe/make_config.yaml
```

Sem assinatura nesta fase (aviso do SmartScreen documentado no site). Artefato:
`RemotePiCockpit-Setup-<v>-windows-x64.exe`.

## Linux — `.deb` + `.rpm` (x86_64 e arm64)

**Não buildável no Mac.** Jobs `linux-x64` (`ubuntu-24.04`) e `linux-arm64`
(`ubuntu-24.04-arm`) do CI:

```bash
sudo apt-get install -y rpm   # rpmbuild, pra gerar .rpm em runner Ubuntu
flutter build linux --release
fastforge package --platform linux --targets deb
fastforge package --platform linux --targets rpm
```

Deps de runtime declaradas nos `make_config.yaml` (GTK3 + libs base). **Pendência
de CI** (passo 3): rodar `ldd` no bundle gerado pra confirmar/expandir as deps, e
validar instalação em containers `ubuntu:24.04` (deb) e `fedora:40` (rpm) — não
foi possível neste Mac (sem build Linux; Docker presente mas parado).

## Próximos passos (plano 43)

- Passo 3: `.github/workflows/cockpit-release.yml` (trigger `cockpit-v*`).
- Passo 4: layout/`latest.json` na VPS.
- Passo 5: página de downloads no `site/`.
- Passo 6: runbook de release (bump `version:` → tag → CI → smoke test).
