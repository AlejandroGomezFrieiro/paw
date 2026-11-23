#!/usr/bin/env bash
# The reliability runs: the fuzzer over several seeds, the abuse cases, a soak.
#   nix develop -c bench/stress.sh [seeds] [steps] [soak minutes]
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
paw="$here/../target/release/paw"
seeds="${1:-20}"
steps="${2:-1500}"
minutes="${3:-3}"
export BENCH_TMP="${BENCH_TMP:-/tmp/paw-bench}"
# paw runs sealed from the machine as in the tests: a scratch home, XDG and
# runtime folders, no plugin folders (tests/tools/env.sh).
ROOT="$(cd "$here/.." && pwd)"
PAW_TEST_SCRATCH="$BENCH_TMP/sealed"
. "$ROOT/tests/tools/env.sh"
failed=0

for seed in $(seq "$seeds"); do
  out=$(timeout 900 "$paw" --clean --no-plugins -l "$here/fuzz.lua" "$seed" "$steps" 2>&1)
  code=$?
  line=$(printf '%s\n' "$out" | grep '^{' | tail -1)
  if [ "$code" != 0 ] || [[ "$line" != *'"failed":false'* ]]; then
    failed=$((failed + 1))
    echo "fuzz seed $seed: exit $code"
    printf '%s\n' "$out" | tail -5
  else
    echo "$line"
  fi
done

"$here/abuse.sh" "$paw" 60 || failed=$((failed + 1))

timeout $((minutes * 60 + 120)) "$paw" --clean --no-plugins -l "$here/soak.lua" "$minutes" || failed=$((failed + 1))

echo "stress: $failed failed" >&2
[ "$failed" = 0 ]
