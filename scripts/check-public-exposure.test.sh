#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCANNER="$SCRIPT_DIR/check-public-exposure.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/outpost-public-exposure.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

init_repo() {
  local repo="$1"

  git init -q "$repo"
  git -C "$repo" config user.name 'Exposure Guard Test'
  git -C "$repo" config user.email 'exposure-guard@example.invalid'
  printf 'clean fixture\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m 'clean root'
}

expect_pass() {
  local label="$1"
  shift

  if ! "$@" > "$TMP_ROOT/output" 2>&1; then
    printf 'FAIL: %s unexpectedly failed\n' "$label" >&2
    cat "$TMP_ROOT/output" >&2
    return 1
  fi
}

expect_bounded_failure() {
  local label="$1"
  local forbidden_value="$2"
  local expected_diagnostic="$3"
  shift 3

  if "$@" > "$TMP_ROOT/output" 2>&1; then
    printf 'FAIL: %s unexpectedly passed\n' "$label" >&2
    return 1
  fi
  if [[ "$(<"$TMP_ROOT/output")" == *"$forbidden_value"* ]]; then
    printf 'FAIL: %s printed forbidden incident content\n' "$label" >&2
    return 1
  fi
  if [[ "$(<"$TMP_ROOT/output")" != *"$expected_diagnostic"* ]]; then
    printf 'FAIL: %s did not emit the expected bounded diagnostic\n' "$label" >&2
    printf '%s\n' "$(<"$TMP_ROOT/output")" >&2
    return 1
  fi
}

clean_repo="$TMP_ROOT/clean"
init_repo "$clean_repo"
expect_pass 'clean tree' "$SCANNER" --tree "$clean_repo"
expect_pass 'clean history' "$SCANNER" --history HEAD "$clean_repo"

path_repo="$TMP_ROOT/path"
init_repo "$path_repo"
printf 'fixture only\n' > "$path_repo/.env.runtime"
git -C "$path_repo" add -f .env.runtime
expect_bounded_failure 'forbidden tracked path' 'fixture only' \
  'forbidden tracked path: .env.runtime' "$SCANNER" --tree "$path_repo"

tree_repo="$TMP_ROOT/tree"
init_repo "$tree_repo"
lan_value="192.$(printf '168').50.$(printf '23')"
printf 'relay=%s\n' "$lan_value" > "$tree_repo/incident.txt"
git -C "$tree_repo" add incident.txt
expect_bounded_failure 'current-tree network literal' "$lan_value" \
  'tree content: incident.txt' "$SCANNER" --tree "$tree_repo"

history_repo="$TMP_ROOT/history"
init_repo "$history_repo"
tailnet_value="100.$(printf '106').7.$(printf '41')"
printf 'relay=%s\n' "$tailnet_value" > "$history_repo/incident.txt"
git -C "$history_repo" add incident.txt
git -C "$history_repo" commit -q -m 'introduce fixture'
printf 'redacted fixture\n' > "$history_repo/incident.txt"
git -C "$history_repo" add incident.txt
git -C "$history_repo" commit -q -m 'redact fixture'
expect_pass 'redacted current tree' "$SCANNER" --tree "$history_repo"
expect_bounded_failure 'history-only network literal' "$tailnet_value" \
  'history content:' "$SCANNER" --history HEAD "$history_repo"

mirror_repo="$TMP_ROOT/history.git"
git clone -q --mirror "$history_repo" "$mirror_repo"
expect_bounded_failure 'public mirror history' "$tailnet_value" \
  'history content:' "$SCANNER" --all-public-refs "$mirror_repo"

printf 'public-exposure fixture tests: PASS\n'
