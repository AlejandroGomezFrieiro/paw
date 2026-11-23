#!/usr/bin/env bash
# Run every case of abuse.lua in its own process, with a time limit and a
# memory limit, and report crashes, hangs and broken results.
#   bench/abuse.sh [paw binary] [seconds per case]
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
paw="${1:-$here/../target/release/paw}"
limit="${2:-60}"
export BENCH_TMP="${BENCH_TMP:-/tmp/paw-bench}"
# paw runs sealed from the machine as in the tests: a scratch home, XDG and
# runtime folders, no plugin folders (tests/tools/env.sh).
ROOT="$(cd "$here/.." && pwd)"
PAW_TEST_SCRATCH="$BENCH_TMP/sealed"
. "$ROOT/tests/tools/env.sh"

bad=0
while IFS= read -r name; do
  # 8 GB of address space: an absurd allocation fails instead of taking the machine.
  log="$BENCH_TMP/abuse-case.log"
  (ulimit -v 8000000; timeout "$limit" "$paw" --clean --no-plugins -l "$here/abuse.lua" "$name") > "$log" 2>&1
  code=$?
  line=$(grep '^{' "$log" | tail -1)
  if [ "$code" = 124 ]; then
    echo "{\"workload\":\"abuse\",\"case\":\"$name\",\"outcome\":\"BAD\",\"detail\":\"hung: killed after ${limit} s\"}"
    bad=$((bad + 1))
  elif [ -z "$line" ]; then
    why=$(grep -v '^\s' "$log" | tail -2 | tr '\n"' ' \x27' | cut -c1-300)
    echo "{\"workload\":\"abuse\",\"case\":\"$name\",\"outcome\":\"BAD\",\"detail\":\"exit $code: $why\"}"
    bad=$((bad + 1))
  else
    echo "$line"
    case "$line" in *'"outcome":"BAD"'*) bad=$((bad + 1)) ;; esac
  fi
done < <("$paw" --clean --no-plugins -l "$here/abuse.lua" list 2>/dev/null)
echo "abuse: $bad bad" >&2
[ "$bad" = 0 ]
