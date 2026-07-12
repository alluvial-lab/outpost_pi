---
id: rebrand-readme-acknowledgements-section
created: 2026-07-12
updated: 2026-07-12
tags: [rebrand, docs, legal]
---

# README missing Acknowledgements / "Based on" section

## Context

The `epic-rebrand-to-outpost-pi` locked an ethical provenance bar: credit the
original author/project wherever it makes sense — LICENSE, NOTICE, README.
The provenance feature (now done) delivered LICENSE + NOTICE but explicitly
deferred the README section to the mechanical-rename story. The
mechanical-rename story renamed the README wordmark but did NOT add an
acknowledgements section. So the README credit gap remains.

## What's needed

Add an "Acknowledgements" or "Based on" section to the root `README.md`
crediting `remote_pi` / Jacob Moura as the foundation the fork was built on.
One sentence is sufficient — match the NOTICE tone:

> Outpost-Pi is a fork built on [remote_pi](https://github.com/jacobaraujo7/remote_pi) by Jacob Moura, MIT-licensed.

## Severity

Important (not blocking). The legal floor (MIT copyright + permission text in
LICENSE) is met; the NOTICE credits the origin. The README credit is the
ethical bar the epic locked. Small, one-line addition.

## Found by

Review of `epic-rebrand-to-outpost-pi-provenance` (2026-07-12).
