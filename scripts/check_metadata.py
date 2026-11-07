#!/usr/bin/env python3
"""Check the App Store listing in fastlane/ before upload: Apple's length limits, required files,
leftover TODOs, screenshot sizes, and that the support/privacy URLs open.

Usage: check_metadata.py [--offline]   (--offline skips the URL check)
"""

from __future__ import annotations

import json
import struct
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FL = ROOT / "fastlane"
META = FL / "metadata"

# Apple's limits (characters).
LIMITS = {"name.txt": 30, "subtitle.txt": 30, "keywords.txt": 100, "promotional_text.txt": 170,
          "description.txt": 4000, "release_notes.txt": 4000}
REQUIRED = ["name.txt", "description.txt", "keywords.txt", "support_url.txt", "privacy_url.txt"]
# Screenshot sizes App Store Connect accepts for the two device classes we ship.
SIZES = {(1284, 2778): "iPhone 6.5\"", (1320, 2868): "iPhone 6.9\"", (1290, 2796): "iPhone 6.9\"",
         (2064, 2752): "iPad 13\"", (2048, 2732): "iPad 12.9\""}

errors: list[str] = []
warnings: list[str] = []


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip() if path.exists() else ""


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def url_opens(url: str) -> bool:
    try:
        req = urllib.request.Request(url, method="GET", headers={"User-Agent": "accretion-metadata-check"})
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status < 400
    except Exception:
        return False


def main() -> None:
    offline = "--offline" in sys.argv
    locales = sorted(p for p in META.iterdir() if p.is_dir() and p.name != "review_information")
    if not locales:
        errors.append("no locales in fastlane/metadata/")
    urls: set[str] = set()
    for loc in locales:
        for name in REQUIRED:
            if not text(loc / name):
                errors.append(f"{loc.name}/{name}: missing or empty")
        for name, limit in LIMITS.items():
            value = text(loc / name)
            if len(value) > limit:
                errors.append(f"{loc.name}/{name}: {len(value)} characters, limit {limit}")
        kw = text(loc / "keywords.txt")
        if ", " in kw:
            warnings.append(f"{loc.name}/keywords.txt: spaces after commas waste the 100-character limit")
        for name in ("support_url.txt", "privacy_url.txt", "marketing_url.txt"):
            if value := text(loc / name):
                urls.add(value)

    for path in sorted(META.rglob("*.txt")):
        if "TODO" in text(path):
            errors.append(f"{path.relative_to(META)}: still has TODO")

    rating = json.loads((FL / "rating.json").read_text(encoding="utf-8"))
    if rating.get("ageRatingOverrideV2") is None:
        errors.append("rating.json: ageRatingOverrideV2 missing")

    shots = FL / "screenshots"
    if shots.exists():
        for png in sorted(shots.rglob("*.png")):
            size = png_size(png)
            if size not in SIZES:
                errors.append(f"screenshots/{png.relative_to(shots)}: {size[0]}×{size[1]} is not an App Store size")
        for loc in locales:
            if not list((shots / loc.name).glob("*.png")):
                warnings.append(f"screenshots/{loc.name}/ is empty")
    else:
        warnings.append("fastlane/screenshots/ does not exist yet: run `make store-screenshots`")

    if not offline:
        for url in sorted(urls):
            if not url_opens(url):
                errors.append(f"URL does not open: {url}")

    for w in warnings:
        print(f"  ! {w}")
    for e in errors:
        print(f"  ✗ {e}")
    if errors:
        sys.exit(f"{len(errors)} problem(s) in the store listing")
    print(f"  ✓ store listing OK ({', '.join(l.name for l in locales)})")


if __name__ == "__main__":
    main()
