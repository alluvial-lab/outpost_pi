---
id: gate-security-capture-upload-chunk-amplification
kind: story
stage: implementing
tags: [security]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: security
created: 2026-08-24
updated: 2026-08-24
---

# Bound capture-upload chunk and event-count amplification

## Severity
Medium

## Domain
Input Validation & Injection

## Finding
The upload boundary caps bytes per chunk and bytes per upload but sets no
minimum decoded chunk size and no maximum sequence/chunk count. A valid 2 MiB
capture can consequently be split into 2,097,152 one-byte frames. Each frame
runs base64 validation and a buffer write and emits an acknowledgement, allowing
an authenticated paired owner to amplify one bounded upload into millions of
relay/extension operations. Final JSONL validation likewise has no event-count
ceiling, so a 2 MiB file can force hundreds of thousands of synchronous
`JSON.parse` calls on the extension event loop.

## Location
`pi-extension/src/actions/capture_upload_handler.ts:168-190`

## Evidence
```ts
if (!decodedLength || decodedLength > CAPTURE_UPLOAD_MAX_CHUNK_BYTES) {
  // rejects zero/oversize, but accepts a one-byte chunk
}
active.receivedBytes += decodedLength;
active.nextSequence += 1;
sender.send(/* one ack per chunk */);
```

The accepted behavior is explicitly exercised at
`pi-extension/src/actions/capture_upload_handler.test.ts:223` (`writes many
one-byte chunks into the declared preallocated total`).

## Suggested fix scope
Add schema-owned maximum chunk/event counts (or require full-sized chunks except
the final chunk), reject impossible sequence counts before processing, and
bound JSONL event validation work. Keep the app uploader compatible with the
new invariant and add adversarial tests at the exact count boundaries plus a
large-valid-capture test demonstrating bounded event-loop work.
