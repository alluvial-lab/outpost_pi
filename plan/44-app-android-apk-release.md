# 44 — App: distribuição mobile — lojas (App Store + Play Store) e APK direto

## Contexto

O app mobile (`app/`) tem o iOS na App Store (plano de submissão próprio) e o
Android na **Play Store**, que **continua como canal**. Este plano adiciona um
canal extra no Android: **APK direto**, no mesmo modelo do plano 43 (cockpit) —
GitHub Release em tag própria, asset baixável, ofertado na `/download` do site.

### Decisões (2026-06-12)

| Tema | Decisão |
|---|---|
| Canal | APK assinado como asset de GitHub Release. ⚠️ **Revisão 2026-06-12**: a **Play Store é MANTIDA** como canal — o APK direto é **adicional**, não substituto ("não precisamos subir pras lojas" ≠ "sair da loja"). Site oferta os dois caminhos (loja + `/download`). O aviso de update in-app pode aparecer mesmo pra instalação vinda da loja — **sem** detecção de origem de instalação (decisão do usuário: não tem problema) |
| Tag | **`app-v<versão>`** (separada da `cockpit-v*`; versão bate com `app/pubspec.yaml`) |
| Nome do asset | **`RemotePi.apk`** (+ `SHA256SUMS`) |
| Assinatura | Keystore release `remotepi-release.jks` (alias `remotepi`). Original guardado no iCloud (`~/Library/Mobile Documents/com~apple~CloudDocs/Flutterando/RemotePi/Android/`), cópia de trabalho gitignored em `app/android/signing/` |
| Secrets | `ANDROID_KEYSTORE` (jks base64), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` — **cadastrados em 2026-06-12** |
| Builds de loja | ⚠️ **Correção 2026-06-12 (via agente do App)**: distribuição é **dupla** — além do APK direto, o app vai pras **duas lojas** (iOS App Store + Android Play Store, que consome **AAB**). Artefatos store-ready buildados e verificados em `1.1.0+5`: IPA assinado Apple Distribution, AAB assinado release e APK release. Builds de loja são fluxo à parte (manual/agente do App); o `app-release.yml` segue cobrindo só o APK direto |

## Como funciona

`.github/workflows/app-release.yml` (escrito em 2026-06-12, YAML validado):
valida tag↔pubspec → restaura keystore/`key.properties` dos secrets →
`flutter build apk --release` → **verifica o fingerprint SHA-256 do
certificado do APK contra o keystore** (o Gradle do app cai silenciosamente
pra debug keys se o `key.properties` faltar — o job falha nesse caso) → cria
a release `app-v*` com `RemotePi.apk` + `SHA256SUMS` (`--latest=false`).

## Manifest do app (espelho do contrato do plano 43)

O workflow gera e anexa um `latest.json` próprio do app — **mesmo schema** do
cockpit (passo 4 do plano 43), com 1 artefato:

```json
{ "version": "1.1.0", "date": "…", "notes": "…",
  "artifacts": [ { "platform": "android", "arch": "universal", "format": "apk",
                   "url": "…/releases/download/app-v1.1.0/RemotePi.apk",
                   "sha256": "…", "size": 0 } ] }
```

Gate manual idêntico ao do cockpit: colocar o `latest.json` em
`/Users/flutterando/app/data/` no host do rp-s3 (volume `/data/app`, já no
docker-compose) → servido em
`https://rp-s3.jacobmoura.work/downloads/app/latest.json`.

## Passos

### 1. Manifest no workflow + volume no rp-s3 (raiz)

> **Status 2026-06-12**: feito — `app-release.yml` gera/anexa o `latest.json`
> e o compose do rp-s3 montou `/data/app`.

### 2. Seção do app na página `/download` do site (site/)

Nova seção "Remote Pi — App (Android)" consumindo o manifest do app (URL
configurável, mock + fallback gracioso, mesmo pattern do cockpit). Instruções:
baixar `RemotePi.apk`, permitir instalação de apps desconhecidos, sha256.

**Aceite**: `pnpm lint && pnpm build` verdes; seção renderiza do mock quando o
manifest não existe.

### 3. Aviso de update in-app no Android (app/)

Espelho do passo 7 do plano 43, **Android-only** (iOS atualiza pela App
Store): check silencioso do manifest no startup, card discreto com fechar,
dispensa persistida por versão, toque baixa o `RemotePi.apk` direto (fallback
página `/download`).

**Aceite**: `flutter analyze` zero issues; testes unit de semver/parse;
nada aparece em iOS nem com manifest indisponível/igual/menor.

## Definition of Done

- [x] Secrets Android cadastrados no repo
- [x] Workflow `app-release.yml` escrito e validado (sintaxe), gerando `latest.json` + APK + SHA256SUMS
- [x] Volume `/data/app` no rp-s3
- [x] Seção do APK na página `/download` do site
- [x] Aviso de update in-app no Android (card dispensável, download direto)
- [ ] Primeira release real: tag `app-v1.1.0` → APK na release, assinatura verificada, instala num aparelho; manifest no rp-s3 e site/card anunciando
- [x] Artefatos store-ready verificados em `1.1.0+5` (IPA Apple Distribution + AAB release) — builds manuais via agente do App
- [ ] Submissões nas lojas (App Store Connect / Play Console) — fluxo do usuário
