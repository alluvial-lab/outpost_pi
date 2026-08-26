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

merge_repo="$TMP_ROOT/merge-history"
init_repo "$merge_repo"
printf 'base fixture\n' > "$merge_repo/incident.txt"
git -C "$merge_repo" add incident.txt
git -C "$merge_repo" commit -q -m 'add merge fixture'
merge_base_branch="$(git -C "$merge_repo" branch --show-current)"
git -C "$merge_repo" switch -q -c merge-side
printf 'side clean\n' > "$merge_repo/incident.txt"
git -C "$merge_repo" add incident.txt
git -C "$merge_repo" commit -q -m 'side clean edit'
git -C "$merge_repo" switch -q "$merge_base_branch"
printf 'main clean\n' > "$merge_repo/incident.txt"
git -C "$merge_repo" add incident.txt
git -C "$merge_repo" commit -q -m 'main clean edit'
git -C "$merge_repo" merge --no-ff merge-side >/dev/null 2>&1 || true
merge_value="100.$(printf '106').7.$(printf '52')"
printf 'resolved=%s\n' "$merge_value" > "$merge_repo/incident.txt"
git -C "$merge_repo" add incident.txt
git -C "$merge_repo" commit -q -m 'resolve merge with fixture'
merge_commit="$(git -C "$merge_repo" rev-parse HEAD)"
test "$(git -C "$merge_repo" rev-list --parents -n 1 HEAD | awk '{print NF}')" = 3
git -C "$merge_repo" switch -q -c merge-remove "$merge_commit^1"
git -C "$merge_repo" rm -q incident.txt
git -C "$merge_repo" commit -q -m 'prepare merge removal'
git -C "$merge_repo" switch -q "$merge_base_branch"
git -C "$merge_repo" merge --no-ff merge-remove >/dev/null 2>&1 || true
git -C "$merge_repo" rm -q incident.txt
git -C "$merge_repo" commit -q -m 'merge remove fixture'
test "$(git -C "$merge_repo" rev-list --parents -n 1 HEAD | awk '{print NF}')" = 3
expect_bounded_failure 'merge-only history network literal' "$merge_value" \
  'history content:' "$SCANNER" --history HEAD "$merge_repo"

binary_repo="$TMP_ROOT/binary-history"
init_repo "$binary_repo"
binary_value="192.$(printf '168').50.$(printf '24')"
printf 'prefix\0relay=%s\0suffix\n' "$binary_value" > "$binary_repo/incident.bin"
git -C "$binary_repo" add incident.bin
git -C "$binary_repo" commit -q -m 'introduce binary fixture'
printf 'redacted binary fixture\n' > "$binary_repo/incident.bin"
git -C "$binary_repo" add incident.bin
git -C "$binary_repo" commit -q -m 'redact binary fixture'
expect_bounded_failure 'binary-blob history network literal' "$binary_value" \
  'history content:' "$SCANNER" --history HEAD "$binary_repo"

filename_repo="$TMP_ROOT/filename"
init_repo "$filename_repo"
filename_value="100.$(printf '106').7.$(printf '53')"
printf 'relay=%s\n' "$filename_value" > "$filename_repo/incident-$filename_value.txt"
git -C "$filename_repo" add -- incident-"$filename_value".txt
expect_bounded_failure 'network literal in filename' "$filename_value" \
  'tree content: incident-' "$SCANNER" --tree "$filename_repo"

mirror_repo="$TMP_ROOT/history.git"
git clone -q --mirror "$history_repo" "$mirror_repo"
expect_bounded_failure 'public mirror history' "$tailnet_value" \
  'history content:' "$SCANNER" --all-public-refs "$mirror_repo"

printf 'public-exposure fixture tests: PASS\n'
