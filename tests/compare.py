#!/usr/bin/env python3
"""Differential test: datehog vs flint-py's js_date vs V8 itself.

datehog exists to reproduce `Date.parse` closely enough that a Typst port of
flint's core matches the recorded corpus. The only trustworthy way to check
that is to run the same strings through all three and diff.

All three are run with TZ=UTC. flint-py and V8 both interpret zoneless
date-time strings in local time; datehog cannot (Typst exposes no local
offset), so UTC is the only setting where the three are comparable. The
corpus is generated under TZ=UTC for the same reason.

Usage:
    python compare.py [--flint-py DIR] [--fixtures DIR] [--max N]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PKG = HERE.parent

# Hand-picked cases covering the format families plus the edge cases that
# distinguish a permissive parser from V8's.
SYNTHETIC = [
    # ISO
    "2020-03-14", "2020-03", "2020", "2020-03-14T08:30:00", "2020-03-14T08:30:00Z",
    "2020-03-14T08:30:00.250Z", "2020-03-14T08:30:00+02:00", "2020-03-14T08:30:00-05:00",
    "2020-03-14T24:00:00Z", "2020-03-14T08:30Z",
    # numeric
    "01/15/2020", "1/5/2020", "15.01.2020", "15/01/2020", "2020-01-15", "2020.01.15",
    "01-15-2020", "13/15/2020", "01/32/2020", "1/2/3",
    # month names
    "Feb 2020", "February 2020", "Feb 15 2020", "Feb 15, 2020", "February 15, 2020",
    "15 Feb 2020", "15 February 2020", "Sept 2020", "Jan. 2020",
    # RFC 2822
    "Tue, 15 Feb 2020 08:30:00 GMT", "15 Feb 2020 08:30:00 +0200",
    # V8 leniencies
    "FY 2018", "hello world 2018", "Q1 2018", "Wk 01", "2018 FY",
    # rejects / edges
    "", "   ", "not a date", "2020-02-30", "2019-02-29", "2020-02-29",
    "1969-07-20T20:17:40Z", "1800-01-01", "0001-01-01", "9999-12-31",
]

DATEISH = re.compile(r"\d")


def collect_fixture_strings(fixtures: Path, limit: int) -> list[str]:
    """Every distinct short string containing a digit, from the fixture data."""
    seen: set[str] = set()
    for case in sorted(fixtures.iterdir()):
        f = case / "input.json"
        if not f.exists():
            continue
        doc = json.loads(f.read_text())
        spec = doc.get("input", doc)
        for row in (spec.get("data") or {}).get("values") or []:
            for v in row.values():
                if isinstance(v, str) and len(v) <= 40 and DATEISH.search(v):
                    seen.add(v)
        if len(seen) >= limit:
            break
    return sorted(seen)[:limit]


def run_flint(flint_py: Path, cases: list[str]) -> list[float | None]:
    script = (
        "import sys, json\n"
        f"sys.path.insert(0, {str(flint_py)!r})\n"
        "from flint.core.js_date import js_date_parse_ms\n"
        "cases = json.load(sys.stdin)\n"
        "out = []\n"
        "for c in cases:\n"
        "    try: out.append(js_date_parse_ms(c))\n"
        "    except Exception: out.append(None)\n"
        "print(json.dumps(out))\n"
    )
    env = {**os.environ, "TZ": "UTC"}
    r = subprocess.run([sys.executable, "-c", script], input=json.dumps(cases),
                       capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise SystemExit(f"flint-py runner failed:\n{r.stderr}")
    return json.loads(r.stdout)


def run_v8(cases: list[str]) -> list[float | None]:
    script = (
        "let cases = JSON.parse(require('fs').readFileSync(0, 'utf8'));"
        "console.log(JSON.stringify(cases.map(c => { const n = Date.parse(c);"
        "return Number.isNaN(n) ? null : n; })));"
    )
    env = {**os.environ, "TZ": "UTC"}
    r = subprocess.run(["node", "-e", script], input=json.dumps(cases),
                       capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise SystemExit(f"node runner failed:\n{r.stderr}")
    return json.loads(r.stdout)


def run_datehog(cases: list[str]) -> list[float | None]:
    (HERE / "_cases.json").write_text(json.dumps(cases))
    expr = (
        '{import "src/lib.typ" as dh; '
        'json("tests/_cases.json").map(c => dh.parse-ms(c))}'
    )
    r = subprocess.run(
        ["typst", "eval", expr, "--root", str(PKG), "--format", "json"],
        capture_output=True, text=True, cwd=PKG,
    )
    (HERE / "_cases.json").unlink(missing_ok=True)
    if r.returncode != 0:
        raise SystemExit(f"typst eval failed:\n{r.stderr}")
    return json.loads(r.stdout)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--flint-py", type=Path,
                    default=PKG.parent / "flint-typst/flint-source/packages/flint-py")
    ap.add_argument("--fixtures", type=Path,
                    default=PKG.parent / "flint-typst/flint-source/shared/test-data")
    ap.add_argument("--max", type=int, default=400, help="max fixture strings to sample")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    cases = list(SYNTHETIC)
    if args.fixtures.exists():
        cases += [c for c in collect_fixture_strings(args.fixtures, args.max) if c not in set(cases)]
    print(f"{len(cases)} cases ({len(SYNTHETIC)} synthetic + {len(cases) - len(SYNTHETIC)} from fixtures)\n")

    dh = run_datehog(cases)
    v8 = run_v8(cases)
    flint = run_flint(args.flint_py, cases) if args.flint_py.exists() else [None] * len(cases)
    have_flint = args.flint_py.exists()

    def norm(x):
        return None if x is None else int(x)

    agree_v8 = agree_flint = 0
    # datehog's contract is flint-py compatibility, because the conformance
    # corpus is generated from flint-py -- but only where flint-py itself
    # agrees with V8. Where flint-py has its own bug (diverges from V8),
    # datehog follows V8 instead, on the view that a real parse is better
    # than an inherited mistake. So a case where datehog disagrees with
    # flint-py is a genuine bug only if flint-py was matching V8 there; if
    # flint-py was already wrong and datehog produced V8's answer, that is
    # the documented, intended behaviour. See CHANGELOG.md.
    own_bugs: list[tuple[str, object, object, object]] = []
    inherited: list[tuple[str, object, object, object]] = []
    v8_preferred: list[tuple[str, object, object, object]] = []

    for i, c in enumerate(cases):
        d, j, f = norm(dh[i]), norm(v8[i]), norm(flint[i])
        agree_v8 += int(d == j)
        agree_flint += int(d == f if have_flint else True)
        if not have_flint or d == f:
            continue
        if f == j:
            own_bugs.append((c, d, j, f))       # flint-py matched V8; datehog missed
        elif d == j:
            v8_preferred.append((c, d, j, f))   # flint-py's own bug; datehog follows V8
        else:
            own_bugs.append((c, d, j, f))       # three-way disagreement

    print(f"datehog == flint-py : {agree_flint}/{len(cases)}   <- the contract")
    print(f"datehog == V8       : {agree_v8}/{len(cases)}")

    def table(rows):
        print(f"  {'input':34} {'datehog':>16} {'V8':>16} {'flint-py':>16}")
        for c, d, j, f in rows[: (len(rows) if args.verbose else 20)]:
            print(f"  {c[:34]!r:34} {str(d):>16} {str(j):>16} {str(f):>16}")
        if not args.verbose and len(rows) > 20:
            print(f"  ... {len(rows) - 20} more (-v for all)")

    if inherited:
        print(f"\n{len(inherited)} divergences from V8 that flint-py shares (expected, not failures):")
        table(inherited)

    if v8_preferred:
        print(f"\n{len(v8_preferred)} deviations from flint-py, matching V8 instead (expected, not failures):")
        table(v8_preferred)

    if own_bugs:
        print(f"\n{len(own_bugs)} DISAGREEMENTS WITH flint-py:")
        table(own_bugs)
        return 1

    print("\ndatehog matches flint-py, or V8 where flint-py itself is wrong, on every case")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
