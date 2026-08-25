---
status: folded
folded_into: feature-fresh-session-shutdown-and-recoverable-delivery
id: backlog-recoverable-delivery-resend-contract
created: 2026-08-11
updated: 2026-08-11
tags: [pi-extension, app]
---

# Recoverable delivery / app resend-on-reconnect contract

## Origin
gate-tests T3 (v0.4.0); deferred. Pairs with backlog-new-session-teardown-session-shutdown.

## Location
pi-extension/src/index.ts:2248-2252, 2552-2557; app/lib/data/sync/sync_service.dart:786-846, 1267-1307.

## Issue
Once agent_settled establishes the quiescing fence, a newly arriving user message must not reach Pi and must get semantics letting the operator retry after restart. Currently _sendDeliveryError emits internal_error and SyncService treats correlated non-delivery_pending errors as failed sends; reconnect resends only held UserMessageSubmitted events. The recoverable behavior is unimplemented and unasserted by any app/extension seam test.

## Work
Decide and implement an explicit recoverable error + app resend-on-reconnect (or permanently document the limitation). Add an integration test: send a pending app message as settlement enters quiescing -> prove no SDK delivery -> pass through SyncService -> reconnect -> assert the chosen recovery contract.
