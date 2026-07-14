# Branding — Outpost-Pi

Official visual identity. Source of truth: SVG files (scalable).
Derived PNGs generated via an external tool when needed.

## Palette

| Color | Hex | Use |
|---|---|---|
| Pure black | `#000000` | Background (full + adaptive icon bg) |
| Pure white | `#FFFFFF` | π symbol (main foreground) |
| Pi blue | `#4FC3F7` | Characteristic dot |

## Files

| File | Content | Recommended use |
|---|---|---|
| `logo-full.svg` | Black background + white π + blue dot | Single-piece logo (favicon, README header, site, app store screenshots) |
| `logo-foreground.svg` | π + dot on transparent background | iOS app icon (with a separate background), Android adaptive icon foreground layer |
| `logo-background.svg` | Solid black 1024×1024 | Android adaptive icon background layer |
| `logo-monochrome.svg` | Complete white silhouette | Android 13+ themed icon (system colors it to match the wallpaper) |
| `banner.svg` / `banner.png` | 1280×640 horizontal banner — π on the left + title + tagline + install command + URL | pi.dev package card (`pi.image` in package.json), GitHub README hero, social preview |

All files: **1024×1024** viewBox, Android-compatible safe zone (~66% center).

## How to convert to PNG

No conversion tool is currently installed in the project. Options for
generating PNGs when needed:

### Via `rsvg-convert` (simplest)

```bash
brew install librsvg
rsvg-convert -w 1024 -h 1024 logo-foreground.svg -o logo-foreground.png
rsvg-convert -w 1024 -h 1024 logo-background.svg -o logo-background.png
rsvg-convert -w 1024 -h 1024 logo-monochrome.svg -o logo-monochrome.png
rsvg-convert -w 1024 -h 1024 logo-full.svg -o logo-full.png
```

### Via ImageMagick

```bash
brew install imagemagick
magick -background none -resize 1024x1024 logo-foreground.svg logo-foreground.png
```

### Via Inkscape (CLI)

```bash
inkscape --export-type=png --export-width=1024 logo-foreground.svg
```

### Via Figma/online

- [https://cloudconvert.com/svg-to-png](https://cloudconvert.com/svg-to-png)
- [https://svgtopng.com](https://svgtopng.com)

## Standard export sizes

Before uploading to a store/site, generate the variants:

| Platform | Size | Source file |
|---|---|---|
| iOS App Icon | 1024×1024 PNG (no alpha) | `logo-full.svg` |
| Android Adaptive (foreground) | 432×432 transparent PNG | `logo-foreground.svg` |
| Android Adaptive (background) | 432×432 PNG (solid color is enough) | `logo-background.svg` |
| Android Themed (monochrome) | 432×432 transparent PNG | `logo-monochrome.svg` |
| Favicon | 32×32, 16×16 PNG | `logo-full.svg` |
| App Store screenshot header | 1200×630 PNG | `logo-full.svg` (compose) |
| npm registry README | 512×512 PNG | `logo-full.svg` |

> Android adaptive icons: both foreground and background occupy a 108dp
> total canvas, but important content must stay within the central 66dp
> (safe zone). The SVGs already respect this proportion (~66% of 1024).

## Updates

Visual changes: edit the SVG (Figma → export SVG is fine). Regenerate derived
PNGs at the points of use (site, app, store).

Before changing the palette or silhouette, update this README with the new
visual-identity version + the reason for the change.
