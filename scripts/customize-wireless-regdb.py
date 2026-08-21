#!/usr/bin/env python3
"""Replace every country regulatory block with the Flint 2 custom template.

The OpenWrt wireless-regdb package still performs the actual db.txt ->
regulatory.db compilation with its pinned db2fw.py.  This helper only rewrites
its textual input immediately before that compile step.
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
TOP_LEVEL_RE = re.compile(r"^(?:country\s+[A-Z0-9]{2}:|wmmrule\s+)")


def is_comment(line: str) -> bool:
    return line.lstrip().startswith("#")


def transform(lines: list[str]) -> tuple[list[str], int]:
    out: list[str] = []
    countries = 0
    i = 0

    while i < len(lines):
        line = lines[i]

        if is_comment(line):
            i += 1
            continue

        match = COUNTRY_RE.match(line.rstrip("\n"))
        if match:
            cc = match.group(1)
            countries += 1
            out.append(f"country {cc}:\n")
            out.extend(f"{rule}\n" for rule in TEMPLATE_LINES)
            out.append("\n")

            # Consume the complete original country body.  This deliberately
            # also discards blank/comment lines inside the block so a source
            # update cannot leave an orphaned regulatory rule behind.
            i += 1
            while i < len(lines):
                candidate = lines[i]
                if TOP_LEVEL_RE.match(candidate):
                    break
                i += 1
            continue

        out.append(line)
        i += 1

    return out, countries


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input_db.txt> <output_db.txt>", file=sys.stderr)
        return 2

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    original = input_path.read_text(encoding="utf-8").splitlines(keepends=True)
    transformed, country_count = transform(original)

    if country_count < 1:
        print("wireless-regdb customization failed: no country blocks found", file=sys.stderr)
        return 1

    rendered = "".join(transformed)
    if "(5150 - 5350 @ 160), (36)" not in rendered or "(5925 - 7125 @ 320), (36)" not in rendered:
        print("wireless-regdb customization failed: template validation failed", file=sys.stderr)
        return 1

    output_path.write_text(rendered, encoding="utf-8")
    print(f"customized wireless-regdb: replaced {country_count} country blocks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
