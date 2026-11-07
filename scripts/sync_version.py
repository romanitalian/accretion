#!/usr/bin/env python3
"""Copy MARKETING_VERSION and APP_BUILD from VERSION.md into project.yml.

Usage:
  sync_version.py          sync only
  sync_version.py bump     add 1 to APP_BUILD in VERSION.md, then sync
  sync_version.py show     print "VERSION (BUILD)"
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION_MD = ROOT / "VERSION.md"
PROJECT_YML = ROOT / "project.yml"
FENCE = "```version-registry"


def block_span(raw: str) -> tuple[int, int]:
    start = raw.find(FENCE)
    if start == -1:
        sys.exit(f"error: {VERSION_MD.name} must contain a {FENCE!r} block")
    body = raw.index("\n", start) + 1
    end = raw.find("```", body)
    if end == -1:
        sys.exit(f"error: unclosed {FENCE!r} block")
    return body, end


def load() -> dict[str, str]:
    raw = VERSION_MD.read_text(encoding="utf-8")
    body, end = block_span(raw)
    data = {}
    for line in raw[body:end].splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        key, sep, value = s.partition("=")
        if not sep:
            sys.exit(f"error: expected KEY=VALUE, got {line!r}")
        data[key.strip()] = value.strip()
    for key in ("MARKETING_VERSION", "APP_BUILD"):
        if key not in data:
            sys.exit(f"error: missing {key} in {VERSION_MD.name}")
    if not re.fullmatch(r"\d+(\.\d+){0,2}", data["MARKETING_VERSION"]):
        sys.exit(f"error: MARKETING_VERSION must look like 1.2.3, got {data['MARKETING_VERSION']!r}")
    if not data["APP_BUILD"].isdigit():
        sys.exit(f"error: APP_BUILD must be digits, got {data['APP_BUILD']!r}")
    return data


def bump() -> None:
    raw = VERSION_MD.read_text(encoding="utf-8")
    body, end = block_span(raw)
    block, n = re.subn(r"^APP_BUILD=(\d+)$", lambda m: f"APP_BUILD={int(m[1]) + 1}", raw[body:end], flags=re.M)
    if n != 1:
        sys.exit("error: APP_BUILD line not found")
    VERSION_MD.write_text(raw[:body] + block + raw[end:], encoding="utf-8")


def sync(data: dict[str, str]) -> None:
    text = PROJECT_YML.read_text(encoding="utf-8")
    new, a = re.subn(r'(MARKETING_VERSION:\s*")[^"]*(")', rf'\g<1>{data["MARKETING_VERSION"]}\2', text)
    new, b = re.subn(r'(CURRENT_PROJECT_VERSION:\s*")[^"]*(")', rf'\g<1>{data["APP_BUILD"]}\2', new)
    if a == 0 or b == 0:
        sys.exit("error: MARKETING_VERSION / CURRENT_PROJECT_VERSION not found in project.yml")
    if new != text:
        PROJECT_YML.write_text(new, encoding="utf-8")
        print(f"project.yml → {data['MARKETING_VERSION']} ({data['APP_BUILD']})")


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "sync"
    if cmd == "bump":
        bump()
    data = load()
    if cmd == "show":
        print(f"{data['MARKETING_VERSION']} ({data['APP_BUILD']})")
        return
    sync(data)


if __name__ == "__main__":
    main()
