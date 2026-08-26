"""Parse and project the checked-in Outpost-Pi brand contracts.

This module intentionally understands only the small CSS and SVG grammar used by
our canonical design files. A changed grammar is an actionable contract error,
not an invitation to silently produce a partial projection.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import math
from pathlib import Path
import re
import xml.etree.ElementTree as ET


class ContractError(ValueError):
    """Report malformed canonical brand input at the projection boundary."""


@dataclass(frozen=True)
class RoundedRect:
    x: float
    y: float
    width: float
    height: float
    radius: float


@dataclass(frozen=True)
class Circle:
    cx: float
    cy: float
    radius: float


@dataclass(frozen=True)
class MarkGeometry:
    view_box: tuple[float, float, float, float]
    edge_path: str
    stroke_width: float
    stroke_linecap: str
    hub: RoundedRect
    peers: tuple[Circle, ...]
    ink: str
    accent: str
    edge_segments: tuple[tuple[float, float, float, float], ...]


SHARED_THEME_ROLES: tuple[tuple[str, str], ...] = (
    ("bgPrimary", "--color-bg-primary"),
    ("bgSecondary", "--color-bg-secondary"),
    ("bgTertiary", "--color-bg-tertiary"),
    ("textPrimary", "--color-text-primary"),
    ("textSecondary", "--color-text-secondary"),
    ("textLink", "--color-text-link"),
    ("textLinkHover", "--color-text-link-hover"),
    ("border", "--color-border"),
    ("borderStrong", "--color-border-strong"),
    ("accent", "--color-accent"),
    ("accentHover", "--color-accent-hover"),
    ("accentMuted", "--color-accent-muted"),
    ("onAccent", "--color-on-accent"),
    ("success", "--color-success"),
    ("successBg", "--color-success-bg"),
    ("warning", "--color-warning"),
    ("warningBg", "--color-warning-bg"),
    ("error", "--color-error"),
    ("errorBg", "--color-error-bg"),
    ("info", "--color-info"),
    ("infoBg", "--color-info-bg"),
)

# These are color declarations in the canonical file that are deliberately
# surface-local and therefore not emitted into the cross-surface fixture.
_KNOWN_COLOR_VARIABLES = {
    css_name
    for _, css_name in SHARED_THEME_ROLES
} | {
    "--color-bg-inverse",
    "--color-text-inverse",
}

_HEX_RE = re.compile(r"#[0-9a-fA-F]{6}\Z")
_RGBA_RE = re.compile(
    r"rgba\(\s*(?P<red>\d{1,3})\s*,\s*(?P<green>\d{1,3})\s*,\s*"
    r"(?P<blue>\d{1,3})\s*,\s*(?P<alpha>(?:0|1|0?\.\d+))\s*\)\Z",
    re.IGNORECASE,
)
_NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
_EDGE_RE = re.compile(
    rf"\s*M\s*(?P<x1>{_NUMBER})\s+(?P<y1>{_NUMBER})\s*"
    rf"L\s*(?P<x2>{_NUMBER})\s+(?P<y2>{_NUMBER})\s*"
    rf"M\s*(?P<x3>{_NUMBER})\s+(?P<y3>{_NUMBER})\s*"
    rf"L\s*(?P<x4>{_NUMBER})\s+(?P<y4>{_NUMBER})\s*\Z"
)


def _canonical_color(value: str, *, selector: str, token: str) -> str:
    value = value.strip()
    if _HEX_RE.fullmatch(value):
        return value.upper()
    match = _RGBA_RE.fullmatch(value)
    if match is None:
        raise ContractError(
            f"Unsupported non-color value for {token} in {selector}: {value!r}; "
            "expected #RRGGBB or rgba(r, g, b, a)"
        )
    channels = tuple(int(match.group(channel)) for channel in ("red", "green", "blue"))
    if any(channel > 255 for channel in channels):
        raise ContractError(f"Invalid channel in {token} for {selector}: {value!r}")
    alpha = float(match.group("alpha"))
    if not 0 <= alpha <= 1:
        raise ContractError(f"Invalid alpha in {token} for {selector}: {value!r}")
    alpha_text = format(alpha, ".15g")
    return f"rgba({channels[0]}, {channels[1]}, {channels[2]}, {alpha_text})"


def _remove_css_comments(css: str) -> str:
    return re.sub(r"/\*.*?\*/", "", css, flags=re.DOTALL)


def _selector_block(css: str, pattern: re.Pattern[str], selector: str) -> str:
    matches = list(pattern.finditer(css))
    if len(matches) != 1:
        raise ContractError(
            f"Expected exactly one supported {selector} declaration block; found "
            f"{len(matches)}"
        )
    return matches[0].group("body")


def _parse_css_declarations(body: str, *, selector: str) -> dict[str, str]:
    declarations: dict[str, str] = {}
    for raw_declaration in body.split(";"):
        declaration = raw_declaration.strip()
        if not declaration:
            continue
        if ":" not in declaration:
            raise ContractError(
                f"Unsupported declaration in {selector}: {declaration!r}"
            )
        name, raw_value = declaration.split(":", 1)
        name = name.strip()
        value = raw_value.strip()
        if not name.startswith("--"):
            raise ContractError(
                f"Unsupported declaration in {selector}: {declaration!r}"
            )
        if not re.fullmatch(r"--[a-z0-9-]+", name):
            raise ContractError(f"Unsupported token name in {selector}: {name!r}")
        if name in declarations:
            raise ContractError(f"Duplicate token {name} in {selector}")
        declarations[name] = value
        if name.startswith("--color-") and name not in _KNOWN_COLOR_VARIABLES:
            raise ContractError(f"Unsupported color token {name} in {selector}")
    return declarations


def _parse_css_mode(body: str, *, selector: str) -> dict[str, str]:
    declarations = _parse_css_declarations(body, selector=selector)
    result: dict[str, str] = {}
    for role, css_name in SHARED_THEME_ROLES:
        if css_name not in declarations:
            raise ContractError(f"Missing token {css_name} in {selector}")
        result[role] = _canonical_color(
            declarations[css_name], selector=selector, token=css_name
        )
    return result


def _reject_css_outside_supported_grammar(
    css: str, *, accepted_patterns: tuple[tuple[re.Pattern[str], str], ...]
) -> None:
    """Reject any CSS syntax outside the explicitly supported contract grammar."""
    spans: list[tuple[int, int]] = []
    for pattern, selector in accepted_patterns:
        matches = list(pattern.finditer(css))
        if len(matches) != 1:
            raise ContractError(
                f"Expected exactly one supported {selector} declaration block; found "
                f"{len(matches)}"
            )
        spans.append(matches[0].span())

    imports = list(re.finditer(r"@import\s+url\([^)]*\)\s*;", css))
    if len(imports) != 1:
        raise ContractError(
            f"Expected exactly one supported @import declaration; found {len(imports)}"
        )
    spans.append(imports[0].span())

    masked = list(css)
    for start, end in spans:
        masked[start:end] = " " * (end - start)
    remainder = "".join(masked).strip()
    if remainder:
        raise ContractError(
            "Unsupported CSS grammar outside the canonical contract blocks: "
            f"{remainder[:120]!r}"
        )


def build_theme_fixture(tokens_css: str) -> dict[str, object]:
    """Build the deterministic cross-surface theme fixture from canonical CSS."""
    css = _remove_css_comments(tokens_css)
    dark_pattern = re.compile(
        r"(?P<selector>:root\s*,\s*:root\[data-theme\s*=\s*['\"]dark['\"]\])"
        r"\s*\{(?P<body>[^{}]*)\}"
    )
    light_pattern = re.compile(
        r"(?P<selector>:root\[data-theme\s*=\s*['\"]light['\"]\])"
        r"\s*\{(?P<body>[^{}]*)\}"
    )
    media_pattern = re.compile(
        r"@media\s*\(\s*prefers-color-scheme\s*:\s*dark\s*\)\s*\{\s*"
        r":root:not\(\[data-theme\s*=\s*['\"]light['\"]\]\)\s*\{"
        r"(?P<body>[^{}]*)\}\s*\}"
    )
    _reject_css_outside_supported_grammar(
        css,
        accepted_patterns=(
            (dark_pattern, ':root, :root[data-theme="dark"]'),
            (light_pattern, ':root[data-theme="light"]'),
            (media_pattern, '@media dark :root:not([data-theme="light"])'),
        ),
    )
    dark_body = _selector_block(
        css, dark_pattern, ':root, :root[data-theme="dark"]'
    )
    light_body = _selector_block(
        css, light_pattern, ':root[data-theme="light"]'
    )
    dark = _parse_css_mode(
        dark_body, selector=":root, :root[data-theme=\"dark\"]"
    )
    light = _parse_css_mode(light_body, selector=":root[data-theme=\"light\"]")

    media_matches = list(
        re.finditer(
            r"@media\s*\(\s*prefers-color-scheme\s*:\s*dark\s*\)\s*\{\s*"
            r":root:not\(\[data-theme\s*=\s*['\"]light['\"]\]\)\s*\{"
            r"(?P<body>[^{}]*)\}\s*\}",
            css,
        )
    )
    if len(media_matches) != 1:
        raise ContractError(
            "Expected exactly one supported dark prefers-color-scheme block; "
            f"found {len(media_matches)}"
        )
    media_dark = _parse_css_mode(
        media_matches[0].group("body"),
        selector="@media dark :root:not([data-theme=\"light\"])",
    )
    for role in dark:
        if media_dark[role] != dark[role]:
            raise ContractError(
                f"Token {role} differs between the dark root and prefers-color-scheme "
                "dark blocks"
            )

    return {
        "schemaVersion": 1,
        "source": ".mockups/design-system/tokens.css",
        "wcagAaNormalText": 4.5,
        "modes": {"dark": dark, "light": light},
    }


def _float(value: str, *, attribute: str, element: str) -> float:
    try:
        parsed = float(value)
    except ValueError as error:
        raise ContractError(
            f"Invalid {attribute} on canonical SVG {element}: {value!r}"
        ) from error
    if not math.isfinite(parsed):
        raise ContractError(f"Non-finite {attribute} on canonical SVG {element}")
    return parsed


def _required_attribute(element: ET.Element, name: str, *, label: str) -> str:
    value = element.attrib.get(name)
    if value is None or not value.strip():
        raise ContractError(f"Canonical SVG {label} is missing required {name!r}")
    return value.strip()


def _svg_color(value: str, *, label: str) -> str:
    if not _HEX_RE.fullmatch(value):
        raise ContractError(
            f"Canonical SVG {label} has unsupported color {value!r}; expected #RRGGBB"
        )
    return value.upper()


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _assert_allowed_attributes(
    element: ET.Element, allowed: set[str], *, label: str
) -> None:
    """Reject semantic SVG attributes outside the canonical element grammar."""
    unexpected = sorted(set(element.attrib) - allowed)
    if unexpected:
        raise ContractError(
            f"Canonical SVG {label} has unsupported attribute(s): "
            f"{', '.join(unexpected)}"
        )


def _inside_view_box(
    x: float,
    y: float,
    width: float,
    height: float,
    view_box: tuple[float, float, float, float],
    *,
    label: str,
) -> None:
    min_x, min_y, box_width, box_height = view_box
    max_x = min_x + box_width
    max_y = min_y + box_height
    if x < min_x or y < min_y or x + width > max_x or y + height > max_y:
        raise ContractError(f"Canonical SVG {label} falls outside the viewBox")


def load_mark_geometry(path: Path) -> MarkGeometry:
    """Load and validate the restricted Constellation III foreground SVG."""
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError) as error:
        raise ContractError(f"Unable to parse canonical SVG {path}: {error}") from error
    if _local_name(root.tag) != "svg":
        raise ContractError(f"Canonical SVG {path} must have an svg root")
    _assert_allowed_attributes(
        root, {"viewBox", "width", "height"}, label="root"
    )

    raw_view_box = _required_attribute(root, "viewBox", label="root")
    view_values = raw_view_box.split()
    if len(view_values) != 4:
        raise ContractError("Canonical SVG viewBox must contain four numbers")
    view_box = tuple(
        _float(value, attribute="viewBox", element="root") for value in view_values
    )
    if view_box[2] != 1024 or view_box[3] != 1024:
        raise ContractError(
            f"Canonical SVG viewBox must be 1024 by 1024, got {raw_view_box!r}"
        )

    elements = [element for element in root.iter() if element is not root]
    unsupported = [
        _local_name(element.tag)
        for element in elements
        if _local_name(element.tag) not in {"path", "rect", "circle"}
    ]
    if unsupported:
        raise ContractError(
            f"Canonical SVG contains unsupported element(s): {', '.join(unsupported)}"
        )
    paths = [element for element in elements if _local_name(element.tag) == "path"]
    rects = [element for element in elements if _local_name(element.tag) == "rect"]
    circles = [element for element in elements if _local_name(element.tag) == "circle"]
    if len(paths) != 1 or len(rects) != 1 or len(circles) != 2:
        raise ContractError(
            "Canonical SVG must contain exactly one path, one rounded rectangle, "
            f"and two peer circles (got path={len(paths)}, rect={len(rects)}, "
            f"circle={len(circles)})"
        )

    path_element = paths[0]
    _assert_allowed_attributes(
        path_element,
        {"d", "stroke", "stroke-width", "stroke-linecap"},
        label="edge path",
    )
    edge_path = _required_attribute(path_element, "d", label="edge path")
    edge_match = _EDGE_RE.fullmatch(edge_path)
    if edge_match is None:
        raise ContractError(
            "Canonical SVG edge path must contain exactly two M…L line segments"
        )
    edge_numbers = [float(edge_match.group(name)) for name in edge_match.groupdict()]
    edge_segments = (
        tuple(edge_numbers[0:4]),
        tuple(edge_numbers[4:8]),
    )
    for index, (x1, y1, x2, y2) in enumerate(edge_segments, start=1):
        _inside_view_box(
            min(x1, x2),
            min(y1, y2),
            abs(x2 - x1),
            abs(y2 - y1),
            view_box,
            label=f"edge {index}",
        )
    stroke_width = _float(
        _required_attribute(path_element, "stroke-width", label="edge path"),
        attribute="stroke-width",
        element="edge path",
    )
    if stroke_width <= 0:
        raise ContractError("Canonical SVG edge path stroke-width must be positive")
    stroke_linecap = _required_attribute(
        path_element, "stroke-linecap", label="edge path"
    )
    if stroke_linecap != "round":
        raise ContractError(
            f"Canonical SVG edge path must use round caps, got {stroke_linecap!r}"
        )
    ink = _svg_color(
        _required_attribute(path_element, "stroke", label="edge path"),
        label="edge path stroke",
    )

    rect = rects[0]
    _assert_allowed_attributes(
        rect,
        {"x", "y", "width", "height", "rx", "ry", "fill"},
        label="hub",
    )
    rect_x = _float(_required_attribute(rect, "x", label="hub"), attribute="x", element="hub")
    rect_y = _float(_required_attribute(rect, "y", label="hub"), attribute="y", element="hub")
    rect_width = _float(
        _required_attribute(rect, "width", label="hub"), attribute="width", element="hub"
    )
    rect_height = _float(
        _required_attribute(rect, "height", label="hub"),
        attribute="height",
        element="hub",
    )
    radius = _float(
        _required_attribute(rect, "rx", label="hub"), attribute="rx", element="hub"
    )
    ry = rect.attrib.get("ry")
    if ry is not None and _float(ry, attribute="ry", element="hub") != radius:
        raise ContractError("Canonical SVG hub must have equal rx and ry")
    if min(rect_width, rect_height, radius) <= 0:
        raise ContractError("Canonical SVG hub dimensions and radius must be positive")
    if radius > min(rect_width, rect_height) / 2:
        raise ContractError("Canonical SVG hub radius exceeds its bounds")
    _inside_view_box(
        rect_x, rect_y, rect_width, rect_height, view_box, label="hub rectangle"
    )
    accent = _svg_color(
        _required_attribute(rect, "fill", label="hub"), label="hub fill"
    )

    peers: list[Circle] = []
    for index, circle in enumerate(circles, start=1):
        _assert_allowed_attributes(
            circle, {"cx", "cy", "r", "fill"}, label=f"peer {index}"
        )
        cx = _float(
            _required_attribute(circle, "cx", label=f"peer {index}"),
            attribute="cx",
            element=f"peer {index}",
        )
        cy = _float(
            _required_attribute(circle, "cy", label=f"peer {index}"),
            attribute="cy",
            element=f"peer {index}",
        )
        circle_radius = _float(
            _required_attribute(circle, "r", label=f"peer {index}"),
            attribute="r",
            element=f"peer {index}",
        )
        if circle_radius <= 0:
            raise ContractError(f"Canonical SVG peer {index} radius must be positive")
        _inside_view_box(
            cx - circle_radius,
            cy - circle_radius,
            circle_radius * 2,
            circle_radius * 2,
            view_box,
            label=f"peer {index}",
        )
        circle_ink = _svg_color(
            _required_attribute(circle, "fill", label=f"peer {index}"),
            label=f"peer {index} fill",
        )
        if circle_ink != ink:
            raise ContractError(
                f"Canonical SVG peer {index} fill must match edge ink {ink}"
            )
        peers.append(Circle(cx=cx, cy=cy, radius=circle_radius))

    return MarkGeometry(
        view_box=view_box,
        edge_path=edge_path,
        stroke_width=stroke_width,
        stroke_linecap=stroke_linecap,
        hub=RoundedRect(
            x=rect_x,
            y=rect_y,
            width=rect_width,
            height=rect_height,
            radius=radius,
        ),
        peers=tuple(peers),
        ink=ink,
        accent=accent,
        edge_segments=edge_segments,
    )


def _same_number(left: float, right: float) -> bool:
    return math.isclose(left, right, rel_tol=0.0, abs_tol=1e-9)


def validate_mark_projection(
    path: Path,
    canonical: MarkGeometry,
    *,
    expected_view_box: tuple[float, float, float, float],
    expected_transform: str | None = None,
) -> None:
    """Validate one branding SVG's mark primitives against the canonical geometry."""
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError) as error:
        raise ContractError(f"Unable to parse brand projection {path}: {error}") from error
    if _local_name(root.tag) != "svg":
        raise ContractError(f"Brand projection {path} must have an svg root")
    _assert_allowed_attributes(root, {"viewBox", "width", "height"}, label=str(path))
    raw_view_box = _required_attribute(root, "viewBox", label=str(path))
    view_values = raw_view_box.split()
    if len(view_values) != 4:
        raise ContractError(f"Brand projection {path} viewBox must contain four numbers")
    view_box = tuple(
        _float(value, attribute="viewBox", element=str(path)) for value in view_values
    )
    if any(not _same_number(actual, expected) for actual, expected in zip(view_box, expected_view_box)):
        raise ContractError(
            f"Brand projection {path} has viewBox {raw_view_box!r}; "
            f"expected {' '.join(_number(value) for value in expected_view_box)}"
        )

    elements = [element for element in root.iter() if element is not root]
    paths = [element for element in elements if _local_name(element.tag) == "path"]
    circles = [element for element in elements if _local_name(element.tag) == "circle"]
    rounded_rects = [
        element
        for element in elements
        if _local_name(element.tag) == "rect" and "rx" in element.attrib
    ]
    if len(paths) != 1 or len(circles) != 2 or len(rounded_rects) != 1:
        raise ContractError(
            f"Brand projection {path} must contain one mark path, one rounded "
            f"hub, and two peer circles (got path={len(paths)}, "
            f"hub={len(rounded_rects)}, circle={len(circles)})"
        )

    mark_groups = [
        element
        for element in elements
        if _local_name(element.tag) == "g"
        and any(
            descendant is not element
            and _local_name(descendant.tag) in {"path", "circle", "rect"}
            and (
                _local_name(descendant.tag) != "rect"
                or "rx" in descendant.attrib
            )
            for descendant in element.iter()
        )
    ]
    if expected_transform is None:
        if mark_groups:
            raise ContractError(f"Brand projection {path} wraps the mark unexpectedly")
    else:
        if len(mark_groups) != 1:
            raise ContractError(f"Brand projection {path} must have one mark group")
        group = mark_groups[0]
        _assert_allowed_attributes(group, {"transform"}, label=f"{path} mark group")
        transform = _required_attribute(group, "transform", label=f"{path} mark group")
        if transform != expected_transform:
            raise ContractError(
                f"Brand projection {path} has unsupported mark transform {transform!r}"
            )

    path_element = paths[0]
    _assert_allowed_attributes(
        path_element,
        {"d", "stroke", "stroke-width", "stroke-linecap"},
        label=f"{path} edge path",
    )
    if _required_attribute(path_element, "d", label=f"{path} edge path") != canonical.edge_path:
        raise ContractError(f"Brand projection {path} edge path drifted from canonical geometry")
    projection_stroke = _float(
        _required_attribute(path_element, "stroke-width", label=f"{path} edge path"),
        attribute="stroke-width",
        element=f"{path} edge path",
    )
    if not _same_number(projection_stroke, canonical.stroke_width):
        raise ContractError(f"Brand projection {path} stroke width drifted from canonical geometry")
    if _required_attribute(path_element, "stroke-linecap", label=f"{path} edge path") != canonical.stroke_linecap:
        raise ContractError(f"Brand projection {path} stroke linecap drifted from canonical geometry")

    hub = rounded_rects[0]
    _assert_allowed_attributes(
        hub,
        {"x", "y", "width", "height", "rx", "ry", "fill"},
        label=f"{path} hub",
    )
    hub_values = (
        _float(_required_attribute(hub, "x", label=f"{path} hub"), attribute="x", element=str(path)),
        _float(_required_attribute(hub, "y", label=f"{path} hub"), attribute="y", element=str(path)),
        _float(_required_attribute(hub, "width", label=f"{path} hub"), attribute="width", element=str(path)),
        _float(_required_attribute(hub, "height", label=f"{path} hub"), attribute="height", element=str(path)),
        _float(_required_attribute(hub, "rx", label=f"{path} hub"), attribute="rx", element=str(path)),
    )
    canonical_hub = (
        canonical.hub.x,
        canonical.hub.y,
        canonical.hub.width,
        canonical.hub.height,
        canonical.hub.radius,
    )
    if any(not _same_number(actual, expected) for actual, expected in zip(hub_values, canonical_hub)):
        raise ContractError(f"Brand projection {path} hub geometry drifted from canonical geometry")
    if "ry" in hub.attrib and not _same_number(
        _float(hub.attrib["ry"], attribute="ry", element=str(path)), canonical.hub.radius
    ):
        raise ContractError(f"Brand projection {path} hub ry drifted from canonical geometry")

    for index, (circle, peer) in enumerate(zip(circles, canonical.peers), start=1):
        _assert_allowed_attributes(
            circle,
            {"cx", "cy", "r", "fill"},
            label=f"{path} peer {index}",
        )
        actual = (
            _float(_required_attribute(circle, "cx", label=f"{path} peer {index}"), attribute="cx", element=str(path)),
            _float(_required_attribute(circle, "cy", label=f"{path} peer {index}"), attribute="cy", element=str(path)),
            _float(_required_attribute(circle, "r", label=f"{path} peer {index}"), attribute="r", element=str(path)),
        )
        expected = (peer.cx, peer.cy, peer.radius)
        if any(not _same_number(left, right) for left, right in zip(actual, expected)):
            raise ContractError(
                f"Brand projection {path} peer {index} geometry drifted from canonical geometry"
            )


def _number(value: float) -> str:
    if value == int(value):
        return str(int(value))
    return format(value, ".15g")


def render_mark_typescript(mark: MarkGeometry) -> str:
    """Render the checked-in TypeScript geometry projection."""
    min_x, min_y, width, height = mark.view_box
    view_box = " ".join(_number(value) for value in (min_x, min_y, width, height))
    peer_lines = ",\n".join(
        f"    {{ cx: {_number(peer.cx)}, cy: {_number(peer.cy)}, "
        f"radius: {_number(peer.radius)} }}"
        for peer in mark.peers
    )
    return (
        "// Generated by scripts/sync-brand-contracts.py; do not edit.\n"
        "export const constellationMark = {\n"
        f'  viewBox: "{view_box}",\n'
        f'  edgePath: "{mark.edge_path}",\n'
        f"  strokeWidth: {_number(mark.stroke_width)},\n"
        f'  strokeLinecap: "{mark.stroke_linecap}",\n'
        "  hub: {\n"
        f"    x: {_number(mark.hub.x)},\n"
        f"    y: {_number(mark.hub.y)},\n"
        f"    width: {_number(mark.hub.width)},\n"
        f"    height: {_number(mark.hub.height)},\n"
        f"    radius: {_number(mark.hub.radius)},\n"
        "  },\n"
        "  peers: [\n"
        f"{peer_lines}\n"
        "  ],\n"
        f'  ink: "{mark.ink}",\n'
        f'  accent: "{mark.accent}",\n'
        "} as const;\n"
    )


def render_theme_json(fixture: dict[str, object]) -> str:
    """Render the theme fixture with stable key and role ordering."""
    return json.dumps(fixture, indent=2, ensure_ascii=False) + "\n"
