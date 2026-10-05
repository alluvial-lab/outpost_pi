# Pattern: Diagnostic Schema and Emission Coverage

## Rationale

A typed diagnostic family needs two independent proofs, and neither implies
the other: serialization must obey its field contract (allowed/forbidden
fields, primitive values, string bounds), and real production behavior must
actually emit the event at the right seam with the right discriminants. A
serializer test does not prove an emission exists; an emission test does not
prove the serialized privacy contract. Families that adopt only one proof
drift — registry-validated events nobody emits at a new branch, or
production emissions whose serialized shape was never privacy-checked.

## When to use

Any typed diagnostic/debug-event family with a maintained contract: new
event variants, new emission branches of existing variants, or capture-site
registries that gate release confidence on diagnostic coverage.

## Structure

1. **Schema/registry coverage** (`debug_log_test.dart` style): every variant
   appears in the fixture list (`allVariants()`), the tag allow-list, and the
   exhaustive tagOf switch; the fixture asserts serialized field values,
   forbidden keys, and string caps.
2. **Production-seam assertion** (routing test style): drive the real
   production owner with a recording diagnostic sink and assert the emitted
   fields and the branch discriminant — not merely that the tag appeared.
3. **Required-site registry backstop**: map every required capture site to
   an event that a routing test actually asserted (recorded asserted-events
   set), so deleting a required emission fails the site registry, and a tag
   with no required sites fails the coverage backstop.
4. When two branches emit indistinguishable shapes (e.g. two sources of the
   same event type), isolate their phases with `events.clear()` between them
   and assert each independently.

## Examples

- `ConnCancelEvent` — emission at
  `app/lib/data/transport/connection_manager.dart:2371`; schema at
  `app/test/domain/contracts/debug_log_test.dart` (allow-list, tagOf,
  `allVariants()`); routing assertions incl. site discriminants at
  `app/test/data/debug/debug_capture_routing_test.dart` (re-entrant connect,
  factory checkpoint, supervisor invalidation).
- `LifecycleFailureEvent` — same three-layer structure (schema fixture +
  routing test for the channelClose operation discriminant).
- `WsInEvent` — schema coverage per stage/kind fields; routing assertions
  per preauth/enqueue/dropped branches.

## Anti-patterns

- Adding the tag/switch entries but no fixture instance (serialization and
  privacy checks silently skip the new variant).
- Routing tests that assert a tag without a discriminant — first-occurrence
  selection can pass on the wrong branch's event (see the ConnCancelEvent
  generation-matching correction in gate-tests v0.13.0).
- Registry lists that enumerate tags no routing test ever asserted.

## Distinct from

`content-free-diagnostic-categories` documents WHAT is safe to log; this
pattern documents the paired verification structure that keeps a diagnostic
family honest.
