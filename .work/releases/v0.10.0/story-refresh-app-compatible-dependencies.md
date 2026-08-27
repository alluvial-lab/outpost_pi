---
id: story-refresh-app-compatible-dependencies
kind: story
stage: done
tags: [app, deps]
parent: feature-stack-currency-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# App: refresh compatible dependency set (17 locked updates incl. KGP-patched image_picker/url_launcher)

Apply the 17 compatible locked updates identified in feature-stack-currency-review §4 (incl. image_picker + url_launcher KGP-compatible patches). flutter pub upgrade within constraints; analyze + full suite green.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

## Closure

- Stage: `done`; updated `2026-08-27`.
- Lock refresh: `flutter pub upgrade` changed the 17 compatible main-package
  locks: `code_assets` 1.0.0→1.2.1, `cross_file` 0.3.5+2→0.3.5+5,
  `dio_web_adapter` 2.1.2→2.2.1, `flutter_plugin_android_lifecycle` 2.0.34→2.0.35,
  `gpt_markdown` 1.1.8→1.2.1, `hooks` 1.0.3→2.0.2,
  `image_picker_android` 0.8.13+17→0.8.13+19, `jni` 1.0.0→1.0.3,
  `jni_flutter` 1.0.1→1.0.2, `lucide_icons_flutter` 3.1.15→3.1.17,
  `objective_c` 9.3.0→9.5.0, `package_config` 2.2.0→3.0.0,
  `path_provider_linux` 2.2.1→2.2.2, `url_launcher_android` 6.3.30→6.3.32,
  `uuid` 4.5.3→4.6.0, `vector_graphics` 1.2.2→1.2.3, and
  `vector_graphics_compiler` 1.2.5→1.3.0. The full lock refresh also moved
  test-only transitive `vm_service` 15.2.0→15.3.0, added `jni_util` 1.0.0,
  and removed unused `glob` 2.1.3 and `native_toolchain_c` 0.17.6.
- The KGP-compatible Android patches are included: `image_picker_android`
  0.8.13+17→0.8.13+19 and `url_launcher_android` 6.3.30→6.3.32. The
  `gpt_markdown` 1.2.1 API deprecation was handled by switching the app's
  inline-code renderer from `highlightBuilder` to `inlineCodeBuilder`, with
  no visual styling change. `app/pubspec.yaml` constraints were unchanged.
- Deferred constraint changes remain separate work: `app_settings` 5.2.0→9.0.0,
  `flutter_secure_storage` 9.2.4→11.0.0, `go_router` 17.5.0→18.0.0,
  `package_info_plus` 9.0.1→10.2.1, and `share_plus` 10.1.4→13.3.0.
- Verification: `flutter analyze` reported no issues; the full command
  `flutter test --exclude-tags e2e --concurrency=2` passed 984/984 tests.
