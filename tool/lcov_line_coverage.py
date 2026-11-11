#!/usr/bin/env python3
"""Line coverage from an lcov tracefile, with the regression floor check.

The Test job once installed lcov with apt-get just to read its summary, and that
step hung on a stalled package mirror. The total is computed here from the
tracefile instead: every LF (lines found) and LH (lines hit) record is summed,
which is what `lcov --summary` reports for the same file.

    python3 tool/lcov_line_coverage.py --min 25.5 coverage/lcov.info

Exit codes: 0 when coverage is at or above the floor (or no floor is given),
1 when it is below the floor, and 2 when the tracefile cannot be read or has no
instrumented lines.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Iterable, Optional, Sequence, Tuple


def line_totals(lines: Iterable[str]) -> Tuple[int, int]:
    """Returns (lines hit, lines found), summed over every record in a tracefile."""
    hit = 0
    found = 0
    for raw in lines:
        line = raw.strip()
        if line.startswith("LF:"):
            found += int(line[3:])
        elif line.startswith("LH:"):
            hit += int(line[3:])
    return hit, found


def percent(hit: int, found: int) -> float:
    return 100.0 * hit / found


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Line coverage from an lcov tracefile, with a floor check."
    )
    parser.add_argument(
        "tracefile",
        type=Path,
        nargs="?",
        default=Path("coverage/lcov.info"),
        help="the lcov tracefile (default: coverage/lcov.info)",
    )
    parser.add_argument(
        "--min",
        type=float,
        default=None,
        help="fail when line coverage is below this percentage",
    )
    args = parser.parse_args(argv)

    try:
        with args.tracefile.open(encoding="utf-8") as trace:
            hit, found = line_totals(trace)
    except OSError as err:
        print(f"Cannot read {args.tracefile}: {err}", file=sys.stderr)
        return 2
    if found == 0:
        print(f"{args.tracefile} has no instrumented lines", file=sys.stderr)
        return 2

    pct = percent(hit, found)
    print(f"Line coverage: {pct:.2f}% ({hit} of {found} lines)")
    if args.min is not None and pct < args.min:
        print(
            f"Coverage {pct:.2f}% fell below the {args.min}% regression floor",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
