---
id: idea-hot-reload-filtered-test-isolation
created: 2026-08-25
updated: 2026-08-25
tags: [testing, pi-extension]
---

Running `corepack pnpm exec vitest run src/extension.test.ts -t "hot-reload"` in the gate-cruft helper-removal verification selected nine hot-reload tests but failed the quiescing case before reaching its intended assertion: the routed message received `session_mismatch` instead of the expected hot-reload `internal_error`. The full Pi-extension suite subsequently passed all 59 files and 1,086 tests, so this appears to be filtered-run/order-dependent fixture state rather than a product regression. Preserve the evidence and investigate making the hot-reload group independently selectable.
