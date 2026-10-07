---
id: gate-security-v0.13.0-wake-spoofing
kind: story
stage: done
tags: [pi-extension, bug]
parent: null
depends_on: []
release_binding: v0.13.0
gate_origin: security
created: 2026-10-05
updated: 2026-10-05
---

# gate-security v0.13.0: relay-impersonation wake bypass + slash-leading PC labels

## Findings (deep scanner, cross-model; both verified with production code in-memory)

1. **[high] `_relay` origin bypasses sibling validation** — a malicious relay
   or cleartext-WS MITM could submit `from_pc: "_relay"` with
   `envelope.from: "/spoofed-local@peer"` and arbitrary content;
   `_propagateTransportError` forwarded it verbatim into the local broker,
   and the wake's address heuristic classified it LOCAL → forged wake
   (amplified only in sessions combining wake with skip-permissions).
2. **[medium] slash-leading base64 fallback PC labels** — unnamed-PC labels
   are raw base64 pubkey prefixes (siblings.ts), and base64 permits a
   leading `/`: `/wAAAAAA:/tmp/remote@peer` passed `startsWith("/")` and
   classified local.

## Fixes (in-gate)

- **Ingress validation** (broker_remote.ts): `from_pc="_relay"` is now
  accepted ONLY for genuine relay transport errors (`from === "_relay"`,
  `body.type === "transport_error"`, string recipient). Anything else
  claiming that origin is dropped and logged — the branch that skips
  sibling validation now validates the envelope itself. Fails closed.
- **Wake predicate** (wake.ts): `isLocalPeerAddress` now derives from the
  canonical `parseAddress` (no pc-label ⟺ local) instead of the
  startsWith("/") shape test; `_relay` system envelopes are never
  wake-eligible. Fail-closed edge documented: a local name containing a
  literal colon parses as prefixed and loses wake eligibility (buffered
  only — availability, not security).
- Regressions: broker_remote spoof-drop test (forged sender under `_relay`,
  both body shapes); slash-leading-label + `_relay` + colon-name wake tests.

## Deferred (parked, per medium routing)

Provenance-threading through the delivery path (MeshNode.onMessage carrying
an explicit local/remote origin from the broker injection site instead of
parsing at the consumer) — the structurally strongest form; recorded as
backlog `idea-wake-provenance-threading`.

## Verification

typecheck + targeted 71/71 (incl. both regressions) + build; full suite run
recorded in the release body.
