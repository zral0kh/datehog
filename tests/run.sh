#!/usr/bin/env bash
# datehog test suite.
#
#   ./tests/run.sh          unit tests + calendar differential
#   ./tests/run.sh --all    also the V8 / flint-py differential (needs node)
set -euo pipefail
cd "$(dirname "$0")/.."

PY=${PY:-python3}
fail=0

echo "== unit tests =="
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Every check is an assert and nothing renders, so `eval` (no layout, no PDF)
# is enough -- `--in` runs the file for its side effects, `"ok"` is just an
# expression to evaluate once it has.
if typst eval --root . --in tests/test.typ '"ok"' >/dev/null 2>"$out/err"; then
  echo "   pass"
else
  sed 's/^/   /' "$out/err"
  fail=1
fi

echo
echo "== calendar differential (vs Python's datetime) =="
if $PY tests/civil_differential.py; then :; else fail=1; fi

if [[ "${1:-}" == "--all" ]]; then
  echo
  echo "== parser differential (vs V8 and flint-py) =="
  if $PY tests/compare.py; then :; else fail=1; fi
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "all suites passed"
else
  echo "FAILURES"
fi
exit $fail
