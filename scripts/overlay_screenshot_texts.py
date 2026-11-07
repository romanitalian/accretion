#!/usr/bin/env python3
"""Overlay marketing text on framed screenshots only."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFilter, ImageFont


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Overlay text on framed/plain/{device}/*.png into "
            "framed/<style>/{device}/*.png (layout D)."
        )
    )
    parser.add_argument(
        "--dir",
        required=True,
        help="Screenshot run root (contains framed/plain/{iphone,ipad}/)",
    )
    parser.add_argument("--config", required=True, help="JSON config path")
    parser.add_argument(
        "--style",
        required=True,
        help="Output style folder under framed/ (e.g. texted_easy, texted_hard_grad)",
    )
    parser.add_argument(
        "--background-color",
        default="",
        help="Override background color in hex format (#RRGGBB)",
    )
    parser.add_argument(
        "--gradient-start",
        default="",
        help="Optional diagonal gradient start color (#RRGGBB), top-right corner",
    )
    parser.add_argument(
        "--gradient-end",
        default="",
        help="Optional diagonal gradient end color (#RRGGBB), bottom-left corner",
    )
    parser.add_argument(
        "--font-scale",
        type=float,
        default=1.0,
        help="Scale factor for top text font size (e.g. 1.5)",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"Config file not found: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}")


def validate_items(data: dict[str, Any]) -> dict[str, list[str]]:
    items = data.get("items")
    if not isinstance(items, list):
        raise SystemExit("Config key 'items' must be a list")

    mapping: dict[str, list[str]] = {}
    for idx, item in enumerate(items, 1):
        if not isinstance(item, dict):
            raise SystemExit(f"Config item #{idx} must be an object")

        input_name = item.get("input")
        lines = item.get("lines")
        if not isinstance(input_name, str) or not input_name.strip():
            raise SystemExit(f"Config item #{idx}: 'input' must be non-empty string")
        if not isinstance(lines, list) or not lines:
            raise SystemExit(f"Config item #{idx}: 'lines' must be non-empty list")
        if not all(isinstance(line, str) and line.strip() for line in lines):
            raise SystemExit(f"Config item #{idx}: each value in 'lines' must be text")
        mapping[input_name] = [line.strip() for line in lines]

    return mapping


def parse_hex_color(hex_color: str) -> tuple[int, int, int, int]:
    value = hex_color.strip().lstrip("#")
    if len(value) != 6:
        raise ValueError(f"Expected RGB color, got: {hex_color}")
    r = int(value[0:2], 16)
    g = int(value[2:4], 16)
    b = int(value[4:6], 16)
    return (r, g, b, 255)


def get_font(font_size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial Bold.ttf",
    ]
    for path in candidates:
        font_path = Path(path)
        if font_path.exists():
            return ImageFont.truetype(str(font_path), font_size)
    return ImageFont.load_default()


def calc_line_height(font: ImageFont.ImageFont) -> int:
    left, top, right, bottom = font.getbbox("Ag")
    return max(1, bottom - top)


def sample_background_rgb(image: Image.Image) -> tuple[int, int, int]:
    rgb = image.convert("RGB")
    width, height = rgb.size
    points = [
        (max(0, int(width * 0.03)), max(0, int(height * 0.03))),
        (min(width - 1, int(width * 0.97)), max(0, int(height * 0.03))),
        (max(0, int(width * 0.03)), min(height - 1, int(height * 0.97))),
        (min(width - 1, int(width * 0.97)), min(height - 1, int(height * 0.97))),
    ]
    sampled = [rgb.getpixel(p) for p in points]
    r = sum(p[0] for p in sampled) // len(sampled)
    g = sum(p[1] for p in sampled) // len(sampled)
    b = sum(p[2] for p in sampled) // len(sampled)
    return (r, g, b)


def color_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> int:
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def detect_phone_top_y(
    image: Image.Image,
    bg_rgb: tuple[int, int, int],
    color_threshold: int,
    width_change_ratio: float,
) -> int:
    rgb = image.convert("RGB")
    width, height = rgb.size
    min_changed_pixels = max(20, int(width * width_change_ratio))

    # Skip top edge noise and start scanning from 2% height.
    start_y = max(0, int(height * 0.02))
    for y in range(start_y, height):
        changed = 0
        for x in range(width):
            px = rgb.getpixel((x, y))
            if color_distance(px, bg_rgb) > color_threshold:
                changed += 1
        if changed >= min_changed_pixels:
            return y

    # Fallback: assume phone starts around center if detection fails.
    return int(height * 0.5)


def compose_on_bright_background(image: Image.Image, defaults: dict[str, Any]) -> Image.Image:
    rgba = image.convert("RGBA")
    width, height = rgba.size

    enabled = bool(defaults.get("composeOnBrightBackground", True))
    if not enabled:
        return rgba

    background_color = parse_hex_color(str(defaults.get("backgroundColor", "#11A9F2")))
    matte_threshold = int(defaults.get("whiteMatteThreshold", 10))
    top_banner_ratio = float(defaults.get("topBannerRatio", 0.2))
    side_padding_ratio = float(defaults.get("sidePaddingRatio", 0.05))
    bottom_padding_ratio = float(defaults.get("bottomPaddingRatio", 0.04))

    top_banner_px = max(0, int(height * top_banner_ratio))
    side_padding_px = max(0, int(width * side_padding_ratio))
    bottom_padding_px = max(0, int(height * bottom_padding_ratio))

    available_w = max(1, width - side_padding_px * 2)
    available_h = max(1, height - top_banner_px - bottom_padding_px)

    scale = min(available_w / width, available_h / height)
    resized_w = max(1, int(width * scale))
    resized_h = max(1, int(height * scale))

    cleaned = strip_edge_matte(rgba, threshold=matte_threshold)
    resized = cleaned.resize((resized_w, resized_h), Image.Resampling.LANCZOS)
    gradient_start_hex = str(defaults.get("gradientStart", "")).strip()
    gradient_end_hex = str(defaults.get("gradientEnd", "")).strip()
    if gradient_start_hex and gradient_end_hex:
        canvas = build_diagonal_gradient(
            size=(width, height),
            start_color=parse_hex_color(gradient_start_hex),
            end_color=parse_hex_color(gradient_end_hex),
        )
    else:
        canvas = Image.new("RGBA", (width, height), background_color)

    paste_x = (width - resized_w) // 2
    paste_y = top_banner_px + max(0, (available_h - resized_h) // 2)
    canvas.alpha_composite(resized, dest=(paste_x, paste_y))
    return canvas


def strip_edge_matte(image: Image.Image, threshold: int) -> Image.Image:
    """Remove edge-connected near-white matte while keeping inner whites."""
    rgba = image.convert("RGBA")
    rgb = rgba.convert("RGB")
    work = rgb.copy()
    marker = (1, 2, 3)
    corners = [
        (0, 0),
        (work.width - 1, 0),
        (0, work.height - 1),
        (work.width - 1, work.height - 1),
    ]

    for corner in corners:
        if work.getpixel(corner) != marker:
            ImageDraw.floodfill(work, corner, marker, thresh=threshold)

    src_alpha = rgba.getchannel("A").tobytes()
    marked = work.tobytes()
    marker_bytes = bytes(marker)
    pixel_count = rgba.width * rgba.height
    out_alpha = bytearray(pixel_count)
    for idx in range(pixel_count):
        pos = idx * 3
        if marked[pos : pos + 3] == marker_bytes:
            out_alpha[idx] = 0
        else:
            out_alpha[idx] = src_alpha[idx]
    alpha = Image.frombytes("L", rgba.size, bytes(out_alpha))
    rgba.putalpha(alpha)
    return rgba


def build_diagonal_gradient(
    size: tuple[int, int],
    start_color: tuple[int, int, int, int],
    end_color: tuple[int, int, int, int],
) -> Image.Image:
    width, height = size
    den = max(1, (width - 1) + (height - 1))
    gradient = Image.new("RGBA", size)
    pixels = gradient.load()

    for y in range(height):
        for x in range(width):
            t = ((width - 1 - x) + y) / den
            r = int(start_color[0] + (end_color[0] - start_color[0]) * t)
            g = int(start_color[1] + (end_color[1] - start_color[1]) * t)
            b = int(start_color[2] + (end_color[2] - start_color[2]) * t)
            pixels[x, y] = (r, g, b, 255)
    return gradient


def draw_text(
    image: Image.Image,
    lines: list[str],
    defaults: dict[str, Any],
) -> Image.Image:
    rgba = compose_on_bright_background(image=image, defaults=defaults)
    width, height = rgba.size
    min_dim = min(width, height)

    font_size_ratio = float(defaults.get("fontSizeRatio", 0.06))
    top_padding_ratio = float(defaults.get("topPaddingRatio", 0.075))
    line_spacing_ratio = float(defaults.get("lineSpacingRatio", 0.24))
    min_top_padding_ratio = float(defaults.get("minTopPaddingRatio", 0.05))
    phone_gap_ratio = float(defaults.get("phoneGapRatio", 0.035))
    bg_change_threshold = int(defaults.get("bgChangeThreshold", 72))
    row_change_ratio = float(defaults.get("rowChangeRatio", 0.12))
    font_size = max(24, int(min_dim * font_size_ratio))

    text_color_hex = str(defaults.get("textColor", "#FFFFFF"))
    shadow_color_hex = str(defaults.get("shadowColor", "#000000"))
    shadow_opacity = float(defaults.get("shadowOpacity", 0.2))
    shadow_blur = int(defaults.get("shadowBlurRadius", 4))
    shadow_offset_x = int(defaults.get("shadowOffsetX", 0))
    shadow_offset_y = int(defaults.get("shadowOffsetY", 4))

    font = get_font(font_size)
    draw = ImageDraw.Draw(rgba)

    line_height = calc_line_height(font)
    line_gap = int(line_height * line_spacing_ratio)
    block_height = line_height * len(lines) + line_gap * (len(lines) - 1)
    preferred_y = int(height * top_padding_ratio)
    min_y = int(height * min_top_padding_ratio)

    bg_rgb = sample_background_rgb(rgba)
    phone_top_y = detect_phone_top_y(
        image=rgba,
        bg_rgb=bg_rgb,
        color_threshold=bg_change_threshold,
        width_change_ratio=row_change_ratio,
    )
    max_text_bottom = max(min_y + block_height, phone_top_y - int(height * phone_gap_ratio))
    max_y = max(min_y, max_text_bottom - block_height)
    y = max(min_y, min(preferred_y, max_y))

    text_color = parse_hex_color(text_color_hex)
    shadow_rgb = parse_hex_color(shadow_color_hex)
    shadow_alpha = max(0, min(255, int(255 * shadow_opacity)))
    shadow_color = (shadow_rgb[0], shadow_rgb[1], shadow_rgb[2], shadow_alpha)

    shadow_layer = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)

    for idx, line in enumerate(lines):
        text_w = int(draw.textlength(line, font=font))
        x = (width - text_w) // 2
        line_y = y + idx * (line_height + line_gap)
        shadow_draw.text(
            (x + shadow_offset_x, line_y + shadow_offset_y),
            line,
            font=font,
            fill=shadow_color,
        )

    if shadow_blur > 0:
        shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=shadow_blur))

    merged = Image.alpha_composite(rgba, shadow_layer)
    final_draw = ImageDraw.Draw(merged)

    for idx, line in enumerate(lines):
        text_w = int(final_draw.textlength(line, font=font))
        x = (width - text_w) // 2
        line_y = y + idx * (line_height + line_gap)
        final_draw.text((x, line_y), line, font=font, fill=text_color)

    return merged.convert("RGB")


def main() -> int:
    args = parse_args()
    run_dir = Path(args.dir)
    config_path = Path(args.config)
    style = args.style.strip().strip("/")
    if not style:
        raise SystemExit("--style must be a non-empty folder name")

    if not run_dir.exists() or not run_dir.is_dir():
        raise SystemExit(f"Screenshot directory not found: {run_dir}")

    plain_root = run_dir / "framed" / "plain"
    if not plain_root.is_dir():
        raise SystemExit(
            f"framed/plain not found under: {run_dir}. "
            "Run screenshot-with-frameit first."
        )

    data = load_json(config_path)
    defaults = data.get("defaults") if isinstance(data.get("defaults"), dict) else {}
    if args.background_color:
        parse_hex_color(args.background_color)
        defaults = dict(defaults)
        defaults["backgroundColor"] = args.background_color
    if args.gradient_start or args.gradient_end:
        if not (args.gradient_start and args.gradient_end):
            raise SystemExit("Both --gradient-start and --gradient-end must be provided")
        parse_hex_color(args.gradient_start)
        parse_hex_color(args.gradient_end)
        defaults = dict(defaults)
        defaults["gradientStart"] = args.gradient_start
        defaults["gradientEnd"] = args.gradient_end
    if args.font_scale <= 0:
        raise SystemExit("--font-scale must be greater than 0")
    if args.font_scale != 1.0:
        defaults = dict(defaults)
        base_ratio = float(defaults.get("fontSizeRatio", 0.06))
        defaults["fontSizeRatio"] = base_ratio * args.font_scale
    mapping = validate_items(data)

    input_files: list[tuple[str, Path]] = []
    for device in ("iphone", "ipad"):
        device_dir = plain_root / device
        if not device_dir.is_dir():
            continue
        for src in sorted(p for p in device_dir.glob("*.png") if p.is_file()):
            input_files.append((device, src))

    if not input_files:
        raise SystemExit(
            f"No screenshots matched framed/plain/{{iphone,ipad}}/*.png in: {run_dir}. "
            "Nothing to process."
        )

    processed = 0
    missing_config = 0

    for device, src in input_files:
        lines = mapping.get(src.name)
        if not lines:
            missing_config += 1
            print(f"warning: no text mapping for {src.name}", file=sys.stderr)
            continue

        out_dir = run_dir / "framed" / style / device
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / src.name
        image = Image.open(src)
        result = draw_text(image=image, lines=lines, defaults=defaults)
        result.save(out_path, format="PNG")
        processed += 1
        rel = out_path.relative_to(run_dir)
        print(f"processed: framed/plain/{device}/{src.name} -> {rel}")

    skipped = len(input_files) - processed
    print(
        "summary:"
        f" style={style}"
        f" processed={processed}"
        f" skipped={skipped}"
        f" missing_config={missing_config}"
    )

    if processed == 0:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
