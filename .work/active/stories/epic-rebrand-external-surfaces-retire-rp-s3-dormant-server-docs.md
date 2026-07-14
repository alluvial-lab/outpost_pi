---
id: epic-rebrand-external-surfaces-retire-rp-s3-dormant-server-docs
kind: story
stage: implementing
tags: [rebrand, rp-s3, docs]
parent: epic-rebrand-external-surfaces-retire-rp-s3
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Mark rp-s3 dormant and make its compose template fork-local

Implement Unit 3 of the parent feature.

## Scope

- Change `rp-s3/docker-compose.yml` to use
  `outpost-pi-rp-s3:latest`, not `jacobmoura7/rp-s3:latest`.
- Replace `/Users/flutterando/...` bind paths with configurable, portable
  local-data defaults (for example `RP_S3_COCKPIT_DATA_DIR` and
  `RP_S3_APP_DATA_DIR`) while retaining read-only product mounts.
- Rework `rp-s3/README.md` around current truth: the server is dormant and is
  not currently deployed. Retain routes/local configuration only as future
  self-hosted-distribution reference; remove Jacob's hostname, VPS language,
  and paths.
- Retain `rp-s3/build-docker.sh` as a local image build helper, but make clear
  that it does not deploy the dormant server.

## Acceptance criteria

- [ ] Compose has no old Docker namespace or Jacob VPS path.
- [ ] README and build script state the service is not currently deployed.
- [ ] No retired rp-s3 hostname remains in the three files.
- [ ] `docker compose config` passes if Docker Compose is available; otherwise
  record the unavailable prerequisite.
