---
id: gate-cruft-misnamed-bounded-test-mailbox-shim
kind: story
stage: drafting
tags: [cleanup, relay]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-07-20
updated: 2026-07-19
---

# Remove the misnamed unbounded-channel compatibility shim from relay tests

## Severity
Medium

## Confidence
Medium

## Category
compatibility shim

## Relevance
Release-relevant

## Decision required
no

## Location
`relay/src/lib.rs:13-22`

## Evidence
```rust
pub(crate) mod bounded_mpsc {
    pub(crate) use tokio::sync::mpsc::Receiver as UnboundedReceiver;

    pub(crate) fn unbounded_channel<T>()
    -> (tokio::sync::mpsc::Sender<T>, tokio::sync::mpsc::Receiver<T>) {
        tokio::sync::mpsc::channel(crate::resource_limits::OUTBOUND_QUEUE_CAPACITY)
    }
}
```

## Removal
Migrate relay test fixtures to explicitly named bounded `mpsc::channel` helpers or direct calls, then remove this compatibility module. The current aliases preserve obsolete unbounded names while returning bounded types, obscuring the mailbox guarantee that this release introduced.

## Gate scan context
Scanner execution was inline at the operator's direction, with reduced isolation and no scanner sub-agent.
