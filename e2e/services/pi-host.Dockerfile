FROM node:24-bookworm-slim

WORKDIR /workspace/pi-extension

# Source and the already-installed dependency graph are bind-mounted by
# docker-compose.test.yml. Keeping the image as a narrow host adapter avoids a
# second package install and ensures the SDK runtime under test is the repo's
# exact pinned installation.
# Process-respawn loop, NOT a docker restart policy: /__restart exits the node
# process (process exit is the e2e's reset boundary), and this loop respawns it
# in ~200ms. Exit 75 is the preserving live-lane restart: it gets a two-second
# grace so the local broker observes the old room disconnect before the next
# process reserves the same name. The container itself never exits, so docker's
# restart-policy BACKOFF never engages — with `restart: unless-stopped`,
# consecutive test generations that each lived <10s kept doubling the backoff
# (100ms→51s by restart #10), blowing past the tests' 45s restartForIsolation
# window and wedging every subsequent test ("Connection closed before full
# header").
CMD ["sh", "-c", "while true; do node --import tsx test/support/e2e_pi_host_server.ts; rc=$?; echo \"[e2e-pi-host] process exited rc=$rc — respawning\" >&2; if [ \"$rc\" -eq 75 ]; then sleep 2; else sleep 0.2; fi; done"]
