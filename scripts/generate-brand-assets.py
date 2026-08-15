#!/usr/bin/env python3
"""Regenerate Outpost-Pi raster brand assets from the locked mark geometry."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SUPERSAMPLE = 4
DARK_BG = "#0D1210"
DARK_INK = "#E4EFE8"
DARK_ACCENT = "#74CC9C"
WHITE = "#FFFFFF"
MUTED = "#89978D"


def draw_mark(
    size: int,
    *,
    background: str | None,
    ink: str,
    accent: str,
) -> Image.Image:
    """Render the canonical 1024-unit mark at 4× and downsample it."""
    scale = size * SUPERSAMPLE / 1024
    canvas_size = size * SUPERSAMPLE
    mode = "RGB" if background else "RGBA"
    fill = background if background else (0, 0, 0, 0)
    image = Image.new(mode, (canvas_size, canvas_size), fill)
    draw = ImageDraw.Draw(image)

    def point(x: float, y: float) -> tuple[int, int]:
        return (round(x * scale), round(y * scale))

    stroke = round(34 * scale)
    radius = stroke // 2
    for start, end in [((398, 564), (695, 385)), ((398, 564), (633, 693))]:
        a, b = point(*start), point(*end)
        draw.line((a, b), fill=ink, width=stroke)
        for x, y in (a, b):
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=ink)

    draw.rounded_rectangle(
        (*point(314, 480), *point(482, 648)),
        radius=round(25 * scale),
        fill=accent,
    )
    for x, y, r in ((695, 385, 63), (633, 693, 71)):
        cx, cy = point(x, y)
        rr = round(r * scale)
        draw.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=ink)

    return image.resize((size, size), Image.Resampling.LANCZOS)


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def render_icons() -> None:
    android = ROOT / "app/android/app/src/main/res"
    densities = {
        "mipmap-mdpi": 108,
        "mipmap-hdpi": 162,
        "mipmap-xhdpi": 216,
        "mipmap-xxhdpi": 324,
        "mipmap-xxxhdpi": 432,
    }
    for density, size in densities.items():
        save_png(
            draw_mark(size, background=None, ink=DARK_INK, accent=DARK_ACCENT),
            android / density / "ic_launcher_foreground.png",
        )
        save_png(
            draw_mark(size, background=None, ink=WHITE, accent=WHITE),
            android / density / "ic_launcher_monochrome.png",
        )

    ios = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for path in ios.glob("*.png"):
        with Image.open(path) as existing:
            size = existing.width
        save_png(
            draw_mark(size, background=DARK_BG, ink=DARK_INK, accent=DARK_ACCENT),
            path,
        )

    macos = ROOT / "cockpit/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for path in macos.glob("*.png"):
        with Image.open(path) as existing:
            size = existing.width
        save_png(
            draw_mark(size, background=DARK_BG, ink=DARK_INK, accent=DARK_ACCENT),
            path,
        )

    windows_icon = ROOT / "cockpit/windows/runner/resources/app_icon.ico"
    draw_mark(256, background=DARK_BG, ink=DARK_INK, accent=DARK_ACCENT).save(
        windows_icon,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    for size in (16, 32):
        save_png(
            draw_mark(size, background=DARK_BG, ink=DARK_INK, accent=DARK_ACCENT),
            ROOT / f"site/public/favicon-{size}.png",
        )


def fit_font(path: str, text: str, target_size: int, max_width: int) -> ImageFont.FreeTypeFont:
    size = target_size
    while size > 8:
        font = ImageFont.truetype(path, size)
        left, _, right, _ = font.getbbox(text)
        if right - left <= max_width:
            return font
        size -= 1
    return ImageFont.truetype(path, size)


def render_banner() -> None:
    scale = SUPERSAMPLE
    image = Image.new("RGB", (1280 * scale, 640 * scale), DARK_BG)
    draw = ImageDraw.Draw(image)
    mark = draw_mark(260 * scale, background=None, ink=DARK_INK, accent=DARK_ACCENT)
    image.alpha_composite(mark, (96 * scale, 190 * scale)) if image.mode == "RGBA" else image.paste(
        mark, (96 * scale, 190 * scale), mark
    )

    regular_path = "/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf"
    bold_path = "/usr/share/fonts/truetype/noto/NotoSansMono-Bold.ttf"
    wordmark = ImageFont.truetype(bold_path, 88 * scale)
    tagline = fit_font(
        regular_path,
        "your agents, in your pocket — the beacon is lit",
        30 * scale,
        800 * scale,
    )
    url = ImageFont.truetype(regular_path, 24 * scale)
    draw.text((420 * scale, 220 * scale), "outpost_pi", font=wordmark, fill=DARK_INK)
    draw.text(
        (424 * scale, 342 * scale),
        "your agents, in your pocket — the beacon is lit",
        font=tagline,
        fill=MUTED,
    )
    draw.text(
        (424 * scale, 425 * scale),
        "github.com/alluvial-lab/outpost_pi",
        font=url,
        fill=DARK_ACCENT,
    )
    save_png(
        image.resize((1280, 640), Image.Resampling.LANCZOS),
        ROOT / "branding/banner.png",
    )


def copy_svg_assets() -> None:
    full = (ROOT / "branding/logo-full-dark.svg").read_text()
    foreground = (ROOT / "branding/logo-foreground.svg").read_text()
    for path, content in (
        (ROOT / "site/public/logo.svg", full),
        (ROOT / "site/src/app/icon.svg", full),
        (ROOT / "site/public/logo-foreground.svg", foreground),
    ):
        path.write_text(content)


def main() -> None:
    render_icons()
    render_banner()
    copy_svg_assets()


if __name__ == "__main__":
    main()
