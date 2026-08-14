FROM node:24-bookworm-slim

WORKDIR /workspace/pi-extension

# Source and the already-installed dependency graph are bind-mounted by
# docker-compose.test.yml. Keeping the image as a narrow host adapter avoids a
# second package install and ensures the SDK runtime under test is the repo's
# exact pinned installation.
# Shell wrapper: MODE-B forensics — an entrypoint-level marker printed before
# node even evaluates the module. If a wedged run's pi-host log lacks
# ENTRYPPOINT-BOOT lines for the restarting generations, the process never
# started (docker/runner level); if present but no [e2e-pi-host] booting line,
# node died during module import (capture stderr below).
CMD ["sh", "-c", "echo ENTRYPPOINT-BOOT $(date -u +%H:%M:%S.%3N); exec node --import tsx test/support/e2e_pi_host_server.ts"]
