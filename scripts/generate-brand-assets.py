#!/usr/bin/env python3
"""Regenerate Outpost-Pi raster brand assets from the canonical mark SVG."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from brand_contract import MarkGeometry, load_mark_geometry

ROOT = Path(__file__).resolve().parents[1]
SUPERSAMPLE = 4
MARK_GEOMETRY = load_mark_geometry(ROOT / "branding/logo-foreground.svg")
DARK_BG = "#0D1210"
DARK_INK = "#E4EFE8"
DARK_ACCENT = "#74CC9C"
WHITE = "#FFFFFF"
MUTED = "#89978D"


def draw_mark(
    size: int,
    *,
    background: str | None,
    geometry: MarkGeometry,
    ink: str | None = None,
    accent: str | None = None,
) -> Image.Image:
    """Render canonical mark geometry at 4× and downsample it."""
    ink = ink or geometry.ink
    accent = accent or geometry.accent
    min_x, min_y, view_width, view_height = geometry.view_box
    scale_x = size * SUPERSAMPLE / view_width
    scale_y = size * SUPERSAMPLE / view_height
    canvas_size = size * SUPERSAMPLE
    mode = "RGB" if background else "RGBA"
    fill = background if background else (0, 0, 0, 0)
    image = Image.new(mode, (canvas_size, canvas_size), fill)
    draw = ImageDraw.Draw(image)

    def point(x: float, y: float) -> tuple[int, int]:
        return (
            round((x - min_x) * scale_x),
            round((y - min_y) * scale_y),
        )

    scale = min(scale_x, scale_y)
    stroke = round(geometry.stroke_width * scale)
    radius = stroke // 2
    for x1, y1, x2, y2 in geometry.edge_segments:
        a, b = point(x1, y1), point(x2, y2)
        draw.line((a, b), fill=ink, width=stroke)
        if geometry.stroke_linecap == "round":
            for x, y in (a, b):
                draw.ellipse(
                    (x - radius, y - radius, x + radius, y + radius), fill=ink
                )

    hub = geometry.hub
    draw.rounded_rectangle(
        (*point(hub.x, hub.y), *point(hub.x + hub.width, hub.y + hub.height)),
        radius=round(hub.radius * scale),
        fill=accent,
    )
    for peer in geometry.peers:
        cx, cy = point(peer.cx, peer.cy)
        rr = round(peer.radius * scale)
        draw.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=ink)

    return image.resize((size, size), Image.Resampling.LANCZOS)


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def save_existing_mark(
    path: Path,
    *,
    background: str | None,
    preserve_alpha: bool = False,
) -> None:
    """Render the canonical mark at an existing PNG's dimensions."""
    with Image.open(path) as existing:
        size = existing.width
        existing_mode = existing.mode
    image = draw_mark(
        size,
        background=background,
        geometry=MARK_GEOMETRY,
    )
    if preserve_alpha and existing_mode == "RGBA" and image.mode == "RGB":
        image = image.convert("RGBA")
    save_png(image, path)


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
            draw_mark(
                size,
                background=None,
                geometry=MARK_GEOMETRY,
            ),
            android / density / "ic_launcher_foreground.png",
        )
        save_png(
            draw_mark(
                size,
                background=None,
                geometry=MARK_GEOMETRY,
                ink=WHITE,
                accent=WHITE,
            ),
            android / density / "ic_launcher_monochrome.png",
        )

    ios = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for path in ios.glob("*.png"):
        with Image.open(path) as existing:
            size = existing.width
        save_png(
            draw_mark(
                size,
                background=DARK_BG,
                geometry=MARK_GEOMETRY,
            ),
            path,
        )

    macos = ROOT / "cockpit/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for path in macos.glob("*.png"):
        with Image.open(path) as existing:
            size = existing.width
        save_png(
            draw_mark(
                size,
                background=DARK_BG,
                geometry=MARK_GEOMETRY,
            ),
            path,
        )

    windows_icon = ROOT / "cockpit/windows/runner/resources/app_icon.ico"
    draw_mark(
        256,
        background=DARK_BG,
        geometry=MARK_GEOMETRY,
    ).save(
        windows_icon,
        format="ICO",
        sizes=[
            (16, 16),
            (24, 24),
            (32, 32),
            (48, 48),
            (64, 64),
            (128, 128),
            (256, 256),
        ],
    )

    cockpit_logo = ROOT / "cockpit/assets/branding/cockpit_logo.png"
    save_existing_mark(cockpit_logo, background=DARK_BG)

    linux_icons = ROOT / "cockpit/linux/runner/resources"
    for path in sorted(linux_icons.glob("app_icon*.png")):
        save_existing_mark(path, background=DARK_BG)

    cockpit_web = ROOT / "cockpit/web"
    save_existing_mark(cockpit_web / "favicon.png", background=None)
    for path in sorted((cockpit_web / "icons").glob("Icon-*.png")):
        is_maskable = path.name.startswith("Icon-maskable-")
        save_existing_mark(
            path,
            background=DARK_BG if is_maskable else None,
            preserve_alpha=is_maskable,
        )

    for size in (16, 32):
        save_png(
            draw_mark(
                size,
                background=DARK_BG,
                geometry=MARK_GEOMETRY,
            ),
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
    mark = draw_mark(
        260 * scale,
        background=None,
        geometry=MARK_GEOMETRY,
    )
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
    for path, content in (
        (ROOT / "site/public/logo.svg", full),
        (ROOT / "site/src/app/icon.svg", full),
    ):
        path.write_text(content)


def main() -> None:
    render_icons()
    render_banner()
    copy_svg_assets()


if __name__ == "__main__":
    main()
