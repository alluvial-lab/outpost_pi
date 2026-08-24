---
id: gate-security-capture-upload-disk-quota
kind: story
stage: done
tags: [security]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: security
created: 2026-08-24
updated: 2026-08-25
---

# Bound cumulative disk use for delivered debug captures

## Severity
High

## Domain
Input Validation & Injection / Data Protection

## Finding
The capture-upload boundary limits one in-memory upload to 2 MiB and one
in-flight upload, but every successful upload is committed under a fresh
filename with no retained-file count, cumulative-byte quota, replacement
policy, or rate limit. An authenticated paired owner can therefore submit
valid captures serially until the Pi user's filesystem is exhausted. This
direct write path does not require an agent tool approval and can impair the
repository, Pi session, and other processes owned by the user.

## Location
`pi-extension/src/actions/capture_upload_handler.ts:268-280`

## Evidence
```ts
const filename = `app-capture-${iso}-${idTail}.bin`;
// ...
await rename(temp, destination);
// ...
return `debug/${filename}`;
```

The schema-owned ceilings cover only chunk bytes, per-upload total bytes, and
concurrent uploads (`protocol/schema/app-pi-client.schema.json:228-230`); none
bounds cumulative files or retained bytes.

## Suggested fix scope
Define a schema/config-owned retention policy for capture files (for example,
one latest capture or a small count/byte budget per room), enforce it under a
single serialized commit boundary, and fail closed or safely prune only
handler-owned regular files. Add repeated-upload tests proving retained count
and bytes stay bounded, including concurrent/finalizing and symlink/non-regular
file cases.

## Implementation
- Execution capability: `sol/high` (caller-selected for security-sensitive filesystem work).
- Added schema-owned 8 MiB cumulative and 16-files-per-day retention ceilings. Capture commits are process-serialized; after each atomic rename, oldest handler-owned regular captures are pruned by canonical filename timestamp.
- Retention ignores matching symlinks and directories, removes the just-written file if post-write enforcement fails, and reports any pruning in the delivered Pi note.
- Regression tests repeatedly deliver maximum-size and same-day captures, assert retained bytes/count remain bounded, and prove matching symlink/directory entries are untouched.
- Verification: capture-upload suite 15/15 pass; protocol schema/codegen suite 7/7 pass.
- Adjacent issues parked: none.
