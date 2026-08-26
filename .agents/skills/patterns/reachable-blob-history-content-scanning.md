# Pattern: Reachable-Blob History Content Scanning

## Rationale

A history safety check based on diffs or path names can miss content that exists
only in a merge parent, a binary blob, or a reachable tag. Enumerate the unique
blob objects reachable from the requested public revisions and inspect their
bytes directly. Keep the scan bounded and report object identifiers or safe
paths, not the matched secret/network literal.

## When to use

Use when a repository guard must prove that forbidden content is absent from
committed history:

1. Validate the requested revisions and enumerate their reachable objects.
2. Type-filter and deduplicate blob ids before reading contents.
3. Inspect each blob through `git cat-file` (including binary bytes) with a
   bounded worker count and a full pipe that preserves producer errors.
4. Combine blob-content results with history-path and commit-message scans, and
   emit only bounded identifiers in diagnostics.

## When not to use

Do not use a working-tree grep as a history proof, and do not rely on textual
diffs when merge ancestry or binary data matters. Do not materialize every blob
to disk or print matching content. For current tracked content, the cheaper
tree scan is sufficient; use reachable-object enumeration for committed history.

## Examples

### Enumerate unique reachable blobs

**File:** `scripts/check-public-exposure.sh:158-170`

```bash
blob_ids="$(git -C "$repo_root" rev-list --objects "$@" |
  awk '{print $1}' | sort -u |
  git -C "$repo_root" cat-file --batch-check='%(objectname) %(objecttype)' |
  awk '$2 == "blob" {print $1}')"
```

This sees every blob reachable from the requested revision or public ref,
including objects not represented by a simple linear diff.

### Scan blob bytes without writing content to disk

**File:** `scripts/check-public-exposure.sh:173-204`

```bash
xargs -P "$scan_jobs" -n 1 bash -c '
  set -o pipefail
  git -C "$PUBLIC_EXPOSURE_REPO_ROOT" cat-file blob "$1" |
    grep -a -E "$PUBLIC_EXPOSURE_NETWORK_REGEX" >/dev/null
  status=$?
  if (( status == 0 )); then printf "%s\\n" "$1"; exit 0; fi
  if (( status == 1 )); then exit 0; fi
  exit "$status"
' _
```

`grep -a` treats binary blobs as bytes, `xargs -P` bounds concurrency, and the
full pipe avoids `grep -q` SIGPIPE false negatives under `pipefail`.

### Merge and binary fixtures prove the reachable-object boundary

**File:** `scripts/check-public-exposure.test.sh:105-127`

```bash
expect_bounded_failure 'merge-only history network literal' "$merge_value" \
  'history content:' "$SCANNER" --history HEAD "$merge_repo"

expect_bounded_failure 'binary-blob history network literal' "$binary_value" \
  'history content:' "$SCANNER" --history HEAD "$binary_repo"
```

These fixtures retain forbidden content only in reachable merge ancestry or a
binary blob, exactly the cases a diff-only scanner can miss.

### All public heads and tags share the history scanner

**File:** `scripts/check-public-exposure.sh:258-278`

```bash
while IFS= read -r ref; do
  [[ -n "$ref" ]] && refs+=("$ref")
done < <(git -C "$repo_root" for-each-ref --format='%(refname)' refs/heads refs/tags)

scan_history "$repo_root" "${refs[@]}"
```

A mirror-wide run reuses the same reachable-blob proof across every public
head and tag instead of checking only the default branch.

## Common violations

- Searching only `git diff`, which omits merge-only and binary representations.
- Enumerating paths but never reading the blob object that holds historical
  content.
- Running unbounded one-process-per-blob scans or storing blob contents in a
  temporary directory.
- Printing the matched value rather than its safe object/path identifier.

## Related

- `content-free-diagnostic-categories.md` — bounds what a history guard may
  report when it rejects content.
- `break-it-proof-regression-discipline.md` — keeps merge and binary fixtures
  failing after future guard changes.

## Index entry

- **reachable-blob-history-content-scanning**: Enumerate unique blobs reachable from public revisions and scan their bytes directly, including merge and binary history.
