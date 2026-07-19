FROM node:24-bookworm-slim

WORKDIR /workspace/pi-extension

# Source and the already-installed dependency graph are bind-mounted by
# docker-compose.test.yml. Keeping the image as a narrow host adapter avoids a
# second package install and ensures the SDK runtime under test is the repo's
# exact pinned installation.
CMD ["node", "--import", "tsx", "test/support/e2e_pi_host_server.ts"]
