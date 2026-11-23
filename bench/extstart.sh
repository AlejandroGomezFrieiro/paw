#!/usr/bin/env bash
# The startup time with every bundled extension in the configuration, when
# the extensions load at once and when they wait for their first use.
#   bench/extstart.sh [runs]
# It starts paw `runs` times (default 20) for each configuration, in the
# environment of the tests (tests/tools/env.sh), with a scratch
# configuration folder. The binary is $PAW_TEST_BIN/paw, or
# target/release/paw. $PAW_RUNTIME gives a runtime made with
# tools/dev-runtime.sh. Each line gives the median, the minimum and the
# maximum in ms. The cache of compiled Teal is filled before the runs.
set -euo pipefail
runs="${1:-20}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PAW_TEST_SCRATCH="$ROOT/target/bench-extstart"
. "$ROOT/tests/tools/env.sh"
cd "$ROOT"
BIN=${PAW_TEST_BIN:-$ROOT/target/release}
mkdir -p "$XDG_CONFIG_HOME/paw"
echo 'paw.api.quit(0)' > "$SCRATCH/quit.lua"

# The configuration: no extension (`none`), or each bundled extension
# through `paw.ext.load_bundled` (`load`) or `paw.ext.use` (`use`).
config() {
  cat > "$XDG_CONFIG_HOME/paw/init.lua" <<EOF
for _, name in ipairs(paw.ext.bundled()) do
  if "$1" == "load" then paw.ext.load_bundled(name) elseif "$1" == "use" then paw.ext.use(name) end
end
EOF
}

# Median, minimum and maximum wall time, in ms, of `runs` starts.
measure() {
  local times=()
  for _ in $(seq "$runs"); do
    local t0 t1
    t0=$(date +%s%N)
    "$BIN/paw" --audio null --no-plugins -l "$SCRATCH/quit.lua" > /dev/null 2>&1
    t1=$(date +%s%N)
    times+=("$(( (t1 - t0) / 1000 ))")
  done
  printf '%s\n' "${times[@]}" | sort -n |
    awk '{a[NR]=$1} END {printf "median %.1f  min %.1f  max %.1f", a[int((NR+1)/2)]/1000, a[1]/1000, a[NR]/1000}'
}

for way in none load use; do
  config "$way"
  # One start to fill the cache of compiled Teal.
  "$BIN/paw" --audio null --no-plugins -l "$SCRATCH/quit.lua" > /dev/null 2>&1
  echo "$way: $(measure)"
done
rm -f "$XDG_CONFIG_HOME/paw/init.lua"
