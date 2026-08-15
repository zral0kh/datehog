#!/usr/bin/env python3
"""Check datehog's calendar arithmetic against Python's `datetime` module.

The unit tests in `test.typ` pin specific dates. This walks a much wider range
— every month boundary across four centuries, plus the leap-year edges — and
compares day counts, weekdays and ISO rendering against a reference
implementation. Hinnant's algorithms are exact, so any disagreement is a
transcription error, which is exactly the kind of bug spot-checks miss.

Usage:
    python civil_differential.py [--years 1600 2400]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
PKG = HERE.parent
EPOCH = date(1970, 1, 1)


def build_cases(y0: int, y1: int) -> list[tuple[int, int, int]]:
    """First, middle and last day of every month, plus Feb 28/29 everywhere."""
    out: list[tuple[int, int, int]] = []
    for y in range(y0, y1 + 1):
        for m in range(1, 13):
            last = (date(y + (m == 12), (m % 12) + 1, 1) - timedelta(days=1)).day
            for d in {1, 15, last}:
                out.append((y, m, d))
        out.append((y, 2, 28))
        try:
            date(y, 2, 29)
            out.append((y, 2, 29))
        except ValueError:
            pass
    return sorted(set(out))


def run_typst(cases: list[tuple[int, int, int]]) -> list[dict]:
    (HERE / "_civil.json").write_text(json.dumps([list(c) for c in cases]))
    expr = (
        '{'
        'import "src/civil.typ": days-from-civil, civil-from-days, weekday-from-days;'
        'import "src/moment.typ": from-parts, to-iso;'
        'json("tests/_civil.json").map(c => {'
        '  let (y, m, d) = (c.at(0), c.at(1), c.at(2));'
        '  let days = days-from-civil(y, m, d);'
        '  (days: days, back: civil-from-days(days),'
        '   weekday: weekday-from-days(days), iso: to-iso(from-parts(y, m, d)))'
        '})'
        '}'
    )
    r = subprocess.run(
        ["typst", "eval", expr, "--root", str(PKG), "--format", "json"],
        capture_output=True, text=True, cwd=PKG,
    )
    (HERE / "_civil.json").unlink(missing_ok=True)
    if r.returncode != 0:
        print(r.stderr, file=sys.stderr)
        raise SystemExit("typst eval failed")
    return json.loads(r.stdout)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--years", nargs=2, type=int, default=(1600, 2400), metavar=("FROM", "TO"))
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    cases = build_cases(*args.years)
    got = run_typst(cases)

    bad: list[str] = []
    for (y, m, d), g in zip(cases, got):
        ref_days = (date(y, m, d) - EPOCH).days
        if g["days"] != ref_days:
            bad.append(f"{y:04d}-{m:02d}-{d:02d}: days {g['days']} != {ref_days}")
            continue
        if tuple(g["back"]) != (y, m, d):
            bad.append(f"{y:04d}-{m:02d}-{d:02d}: civil-from-days -> {tuple(g['back'])}")
        ref_wd = date(y, m, d).isoweekday()
        if g["weekday"] != ref_wd:
            bad.append(f"{y:04d}-{m:02d}-{d:02d}: weekday {g['weekday']} != {ref_wd}")
        ref_iso = datetime(y, m, d, tzinfo=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        if g["iso"] != ref_iso:
            bad.append(f"{y:04d}-{m:02d}-{d:02d}: iso {g['iso']} != {ref_iso}")

    print(f"   {len(cases)} dates checked over {args.years[0]}-{args.years[1]}")
    if bad:
        print(f"   {len(bad)} MISMATCHES")
        for line in bad[: (len(bad) if args.verbose else 15)]:
            print(f"     {line}")
        if not args.verbose and len(bad) > 15:
            print(f"     ... {len(bad) - 15} more (-v for all)")
        return 1
    print("   pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
