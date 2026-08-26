#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel 2>/dev/null || true)"
MAX_FINDINGS="${PUBLIC_EXPOSURE_MAX_FINDINGS:-50}"

if [[ ! "$MAX_FINDINGS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'public-exposure: PUBLIC_EXPOSURE_MAX_FINDINGS must be a positive integer\n' >&2
  exit 2
fi

# Keep the executable patterns from containing the literal values they reject.
NETWORK_LITERAL_REGEX='(^|[^0-9])(192[.]168[.]50|100[.]106[.]7)[.][0-9]{1,3}([^0-9]|$)'
NETWORK_LITERAL_SANITIZE_REGEX='192[.]168[.]50[.][0-9]{1,3}|100[.]106[.]7[.][0-9]{1,3}'
FORBIDDEN_PATH_REGEX='(^|/)(AGENTS[.]local[.]md|[.]env[^/]*|id_(rsa|dsa|ecdsa|ed25519)|[^/]+[.](pem|key|p12|pfx))$|(^|/)[.]work/session-notes(/|$)'

FINDING_COUNT=0
SUPPRESSION_REPORTED=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-public-exposure.sh [--tree] [repo-root]
  scripts/check-public-exposure.sh --history [revision] [repo-root]
  scripts/check-public-exposure.sh --all-public-refs [mirror-root]

Modes:
  --tree             Scan tracked paths and tracked working-tree content (default).
  --history          Scan one committed revision and its ancestry (default: HEAD).
  --all-public-refs  Scan refs/heads/* and refs/tags/* in a mirror clone.
USAGE
}

sanitize_identifier() {
  local identifier="$1"
  local matched

  while [[ "$identifier" =~ $NETWORK_LITERAL_SANITIZE_REGEX ]]; do
    matched="${BASH_REMATCH[0]}"
    identifier="${identifier/"$matched"/<redacted-network-literal>}"
  done
  printf '%s' "$identifier"
}

report_finding() {
  local category="$1"
  local identifier="$2"

  identifier="$(sanitize_identifier "$identifier")"
  if (( FINDING_COUNT < MAX_FINDINGS )); then
    printf 'public-exposure: %s: %s\n' "$category" "$identifier" >&2
  elif (( SUPPRESSION_REPORTED == 0 )); then
    printf 'public-exposure: additional findings suppressed after %s identifiers\n' "$MAX_FINDINGS" >&2
    SUPPRESSION_REPORTED=1
  fi
  FINDING_COUNT=$((FINDING_COUNT + 1))
}

require_repository() {
  local repo_root="$1"

  if [[ -z "$repo_root" ]] || ! git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'public-exposure: not a Git repository: %s\n' "${repo_root:-<empty>}" >&2
    return 1
  fi
}

scan_tracked_paths() {
  local repo_root="$1"
  local path
  local failed=0

  while IFS= read -r -d '' path; do
    if [[ "$path" =~ $FORBIDDEN_PATH_REGEX ]]; then
      report_finding 'forbidden tracked path' "$path"
      failed=1
    fi
  done < <(git -C "$repo_root" ls-files -z)

  return "$failed"
}

scan_tree_content() {
  local repo_root="$1"
  local matches
  local grep_status
  local path
  local failed=0

  matches="$(git -C "$repo_root" grep --full-name -l -E "$NETWORK_LITERAL_REGEX" -- . 2>/dev/null)"
  grep_status=$?
  if (( grep_status != 0 && grep_status != 1 )); then
    printf 'public-exposure: tree content scan failed (git grep exit %s)\n' "$grep_status" >&2
    return 1
  fi

  if (( grep_status == 0 )); then
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      report_finding 'tree content' "$path"
      failed=1
    done <<< "$matches"
  fi

  return "$failed"
}

scan_tree() {
  local repo_root="$1"
  local failed=0

  if ! scan_tracked_paths "$repo_root"; then
    failed=1
  fi
  if ! scan_tree_content "$repo_root"; then
    failed=1
  fi

  return "$failed"
}

scan_history_paths() {
  local repo_root="$1"
  shift
  local line
  local commit='unknown'
  local failed=0

  while IFS= read -r line; do
    if [[ "$line" == @@* ]]; then
      commit="${line#@@}"
    elif [[ -n "$line" ]] && [[ "$line" =~ $FORBIDDEN_PATH_REGEX ]]; then
      report_finding 'history path' "$commit $line"
      failed=1
    fi
  done < <(git -C "$repo_root" log --full-history --root --no-renames \
    --format='@@%H' --name-only "$@" --)

  return "$failed"
}

scan_history_content() {
  local repo_root="$1"
  shift
  local blob_ids
  local matches
  local xargs_status
  local blob_id
  local scan_jobs="${PUBLIC_EXPOSURE_HISTORY_JOBS:-4}"
  local failed=0

  if [[ ! "$scan_jobs" =~ ^[1-9][0-9]*$ ]]; then
    printf 'public-exposure: PUBLIC_EXPOSURE_HISTORY_JOBS must be a positive integer\n' >&2
    return 1
  fi

  # Diff-based history searches omit merge commits and binary diffs. Enumerate
  # the unique blobs reachable from the requested revisions and inspect their
  # contents directly so the scan covers every committed tree representation.
  blob_ids="$(git -C "$repo_root" rev-list --objects "$@" |
    awk '{print $1}' | sort -u |
    git -C "$repo_root" cat-file --batch-check='%(objectname) %(objecttype)' |
    awk '$2 == "blob" {print $1}')"
  if (( $? != 0 )); then
    printf 'public-exposure: history blob enumeration failed\n' >&2
    return 1
  fi
  if [[ -z "$blob_ids" ]]; then
    return 0
  fi

  # Keep one Git process per worker invocation rather than materializing blob
  # contents on disk. grep -a consumes binary data as bytes and the full pipe
  # avoids SIGPIPE false negatives from grep -q under pipefail.
  matches="$(printf '%s\n' "$blob_ids" |
    env PUBLIC_EXPOSURE_REPO_ROOT="$repo_root" \
      PUBLIC_EXPOSURE_NETWORK_REGEX="$NETWORK_LITERAL_REGEX" \
      xargs -P "$scan_jobs" -n 1 bash -c '
        set -o pipefail
        git -C "$PUBLIC_EXPOSURE_REPO_ROOT" cat-file blob "$1" |
          grep -a -E "$PUBLIC_EXPOSURE_NETWORK_REGEX" >/dev/null
        status=$?
        if (( status == 0 )); then
          printf "%s\\n" "$1"
          exit 0
        fi
        if (( status == 1 )); then
          exit 0
        fi
        exit "$status"
      ' _)"
  xargs_status=$?
  if (( xargs_status != 0 )); then
    printf 'public-exposure: history blob content scan failed (xargs exit %s)\n' \
      "$xargs_status" >&2
    failed=1
  fi

  while IFS= read -r blob_id; do
    [[ -z "$blob_id" ]] && continue
    report_finding 'history content' "$blob_id"
    failed=1
  done <<< "$matches"

  return "$failed"
}

scan_history_messages() {
  local repo_root="$1"
  shift
  local commit
  local message
  local failed=0

  while IFS= read -r commit; do
    [[ -z "$commit" ]] && continue
    message="$(git -C "$repo_root" show -s --format=%B "$commit")"
    if [[ "$message" =~ $NETWORK_LITERAL_REGEX ]]; then
      report_finding 'history commit message' "$commit"
      failed=1
    fi
  done < <(git -C "$repo_root" rev-list "$@")

  return "$failed"
}

scan_history() {
  local repo_root="$1"
  shift
  local revision
  local failed=0

  if (( $# == 0 )); then
    printf 'public-exposure: history scan requires at least one revision\n' >&2
    return 1
  fi
  for revision in "$@"; do
    if ! git -C "$repo_root" rev-parse --verify --quiet "${revision}^{commit}" >/dev/null; then
      printf 'public-exposure: unknown history revision: %s\n' "$revision" >&2
      return 1
    fi
  done

  if ! scan_history_paths "$repo_root" "$@"; then
    failed=1
  fi
  if ! scan_history_content "$repo_root" "$@"; then
    failed=1
  fi
  if ! scan_history_messages "$repo_root" "$@"; then
    failed=1
  fi

  return "$failed"
}

scan_all_public_refs() {
  local repo_root="$1"
  local ref
  local refs=()

  if [[ "$(git -C "$repo_root" rev-parse --is-bare-repository 2>/dev/null)" != 'true' ]] ||
    [[ "$(git -C "$repo_root" config --bool --get remote.origin.mirror 2>/dev/null || true)" != 'true' ]]; then
    printf 'public-exposure: --all-public-refs requires a fresh mirror clone\n' >&2
    return 1
  fi

  while IFS= read -r ref; do
    [[ -n "$ref" ]] && refs+=("$ref")
  done < <(git -C "$repo_root" for-each-ref --format='%(refname)' refs/heads refs/tags)

  if (( ${#refs[@]} == 0 )); then
    printf 'public-exposure: mirror has no public heads or tags\n' >&2
    return 1
  fi

  scan_history "$repo_root" "${refs[@]}"
}

main() {
  local mode="${1:---tree}"
  local repo_root
  local revision_scope
  local failed=0

  case "$mode" in
    --tree)
      shift || true
      repo_root="${1:-$DEFAULT_REPO_ROOT}"
      if (( $# > 1 )); then
        usage >&2
        return 2
      fi
      require_repository "$repo_root" || return 2
      scan_tree "$repo_root" || failed=1
      ;;
    --history)
      shift
      revision_scope="${1:-HEAD}"
      repo_root="${2:-$DEFAULT_REPO_ROOT}"
      if (( $# > 2 )); then
        usage >&2
        return 2
      fi
      require_repository "$repo_root" || return 2
      scan_history "$repo_root" "$revision_scope" || failed=1
      ;;
    --all-public-refs)
      shift
      repo_root="${1:-$DEFAULT_REPO_ROOT}"
      if (( $# > 1 )); then
        usage >&2
        return 2
      fi
      require_repository "$repo_root" || return 2
      scan_all_public_refs "$repo_root" || failed=1
      ;;
    -h|--help)
      usage
      return 0
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac

  if (( failed != 0 )); then
    return 1
  fi
  printf 'public-exposure: PASS (%s)\n' "$mode"
}

main "$@"
