#!/usr/bin/env python3
"""Append an opt-in BJ profile without changing existing wireless-regdb rules.

The OpenWrt wireless-regdb package still performs the actual db.txt ->
regulatory.db compilation with its pinned db2fw.py. This helper preserves all
existing country profiles and only appends BJ when that country is absent.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

TEMPLATE_LINES = (
    "    (755 - 902 @ 2), (36)",
    "    (902 - 904 @ 2), (36)",
    "    (904 - 920 @ 16), (36)",
    "    (920 - 928 @ 8), (36)",
    "    (2400 - 2483.5 @ 40), (36)",
    "    (2474 - 2494 @ 20), (36)",
    "    (4910 - 4990 @ 40), (36)",
    "    (5150 - 5350 @ 160), (36)",
    "    (5470 - 5730 @ 160), (36)",
    "    (5730 - 5850 @ 80), (36)",
    "    (5850 - 5895 @ 40), (36)",
    "    (5925 - 7125 @ 320), (36)",
    "    (57000 - 71000 @ 2160), (44)",
)

COUNTRY_RE = re.compile(r"^country\s+([A-Z0-9]{2}):.*$")


def transform(lines: list[str]) -> tuple[list[str], bool]:
    """Return the unchanged source, adding BJ only if it does not exist."""
    countries = [COUNTRY_RE.match(line.rstrip("\n")) for line in lines]
    if any(match and match.group(1) == "BJ" for match in countries):
        return lines, False

    out = list(lines)
    if out and not out[-1].endswith("\n"):
        out[-1] = f"{out[-1]}\n"
    if out and out[-1].strip():
        out.append("\n")
    out.append("country BJ:\n")
    out.extend(f"{rule}\n" for rule in TEMPLATE_LINES)
    return out, True


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input_db.txt> <output_db.txt>", file=sys.stderr)
        return 2

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    original = input_path.read_text(encoding="utf-8").splitlines(keepends=True)
    transformed, added = transform(original)

    rendered = "".join(transformed)
    if "country BJ:\n" not in rendered or "    (5150 - 5350 @ 160), (36)\n" not in rendered or "    (5925 - 7125 @ 320), (36)\n" not in rendered:
        print("wireless-regdb customization failed: BJ template validation failed", file=sys.stderr)
        return 1

    output_path.write_text(rendered, encoding="utf-8")
    print(f"customized wireless-regdb: {'added' if added else 'retained'} country BJ")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
