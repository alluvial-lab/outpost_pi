# Pattern: Canonical Mark Rasterization Fan-Out

## Rationale

One canonical brand geometry fans out to many platform-specific raster assets
(Android densities, iOS/macOS catalogs, Windows ICO sizes, Linux/web icons,
site favicons, banner). A single supersampled renderer owns the geometry and
resampling quality; platform edges own only dimensions, alpha rules, and
output encoding. This prevents per-surface redraw drift (the pre-v2.0 bug
class where launcher icons were byte-identical to upstream art because each
surface was sourced independently).

## When to use

Whenever one canonical visual asset must produce many platform-specific files
with exact dimension/alpha contracts. Run the generator
(`scripts/generate-brand-assets.py`) after any geometry change and commit the
full regenerated set — hash-diff the outputs against upstream where provenance
matters.

## When not to use

Not for one-off illustrations or screenshots; those have single consumers and
no dimension matrix. Do not re-encode the geometry per surface to "tweak" one
asset — change the canonical source and regenerate all.

## Examples

### Example 1: one shared supersampled draw, many surfaces

**File:** `scripts/generate-brand-assets.py:19-56` (shared `draw_mark` with
supersampling + LANCZOS), fanned out at `:79-96` (Android densities),
`:98-115` (iOS/macOS catalogs), `:117-121` (Windows multi-size ICO),
`:124-138` (cockpit/Linux/web), `:140-145` (site favicons), `:158-191`
(banner reuse).

```python
def render_surface(path: Path, size: int, background: str | None) -> None:
    save_png(draw_mark(size, background=background,
                       ink=DARK_INK, accent=DARK_ACCENT), path)
```

## Known drift risks

- `draw_mark` re-encodes the Constellation III geometry in Python rather than
  reading the canonical `branding/` SVG described as source of truth in
  `branding/README.md:4-5`; `site/src/app/opengraph-image.tsx:37-46` embeds
  the geometry a third time independently. Three encodings of one mark is a
  future drift surface.
