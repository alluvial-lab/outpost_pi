# Pattern: Break-It-Proof Regression Discipline

## Rationale

A regression check that only passes on the current implementation may be
unobservably weak. After fixing a defect, deliberately reintroduce the smallest
old failure (or inject the forbidden input) and require the check to fail with
the intended bounded evidence. Revert the scratch mutation before closure.
This is complementary to a failure-first regression test: failure-first
reproduces the old boundary in a normal test, while break-it proof validates
that the guard itself still has teeth after later fix waves.

## When to use

Use for contract parsers, exposure guards, migration boundaries, and other
checks whose value is rejecting bad state:

1. Record the repaired invariant and the exact command/test that enforces it.
2. Mutate one protected input or temporarily restore the removed behavior.
3. Assert failure, the relevant diagnostic category, and that sensitive input is
   not echoed where bounded diagnostics are part of the contract.
4. Restore the mutation and rerun the clean check before committing.

## When not to use

Do not leave a mutation in the working tree, weaken assertions to accommodate
it, or use a synthetic mutation unrelated to the defect. Do not replace normal
behavioral coverage with a break-it proof; it is a guard-strength check, not a
substitute for the contract test.

## Examples

### Stale generated fixture must fail the synchronizer

**File:** `scripts/test_brand_contract.py:34-45`

```python
self.assertTrue(_sync.sync_contracts(check=True))
fixture_path.write_text("stale\n")
self.assertFalse(_sync.sync_contracts(check=True))
```

The test intentionally breaks the generated contract after establishing a
clean pass, proving the freshness guard rejects drift rather than merely
accepting the checked-in fixture.

### Unsupported contract grammar must fail closed

**File:** `scripts/test_brand_contract.py:48-62`

```python
unsupported = self.tokens + "\n:root { --color-accent: #FFFFFF; }\n"
with self.assertRaisesRegex(ContractError, "outside the canonical contract"):
    build_theme_fixture(unsupported)

malformed = self.foreground.replace(
    'stroke="#E4EFE8"',
    'stroke="#E4EFE8" transform="translate(10 0)"',
)
```

The scratch selector and unexpected SVG attribute restore the former drift
vectors and require the parser to reject both.

### History exposure fixtures must fail on forbidden committed content

**File:** `scripts/check-public-exposure.test.sh:83-127`

```bash
expect_pass 'redacted current tree' "$SCANNER" --tree "$history_repo"
expect_bounded_failure 'history-only network literal' "$tailnet_value" \
  'history content:' "$SCANNER" --history HEAD "$history_repo"

expect_bounded_failure 'merge-only history network literal' "$merge_value" \
  'history content:' "$SCANNER" --history HEAD "$merge_repo"
expect_bounded_failure 'binary-blob history network literal' "$binary_value" \
  'history content:' "$SCANNER" --history HEAD "$binary_repo"
```

The current tree is clean, then old content is deliberately reintroduced in
ordinary, merge-only, and binary blobs; each old exposure must fail closed
without printing the forbidden value.

### Concurrent store-open repair was proven against the unfixed behavior

**File:** `cockpit/test/core/data/json_state_store_test.dart:49-66`

```dart
final firstOpening = factory.open('concurrent');
final secondOpening = factory.open('concurrent');
final first = await firstOpening;
final second = await secondOpening;
expect(identical(first, second), isTrue);
```

The release's recorded break-it run temporarily removed the in-flight-open
cache and observed this assertion fail before restoring the fix; the test then
proved the repaired factory shares one instance and one flush lifecycle.

## Common violations

- Claiming a guard has coverage without showing that the old failure makes the
  guard fail.
- Mutating several unrelated inputs at once, making a failure impossible to
  attribute.
- Checking only a nonzero exit code when the guard promises bounded,
  content-free diagnostics.
- Forgetting to restore the mutation and rerun the clean path.

## Related

- `failure-first-regression-tests.md` — expresses the original failure boundary
  and repaired invariant in the ordinary regression suite.
- `content-free-diagnostic-categories.md` — defines the bounded diagnostic
  evidence that exposure and parser break-it proofs must preserve.

## Index entry

- **break-it-proof-regression-discipline**: Reintroduce one old failure, require the guard to fail with bounded evidence, then restore and rerun the clean path.
