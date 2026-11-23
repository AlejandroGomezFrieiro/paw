#!/usr/bin/env bash
# Run the benchmark matrix on this DAW and, if it has been built, on the
# Tracktion Engine driver. Appends JSON lines to bench/results/<name>.jsonl and
# prints a summary.
#
#   nix develop -c bench/run.sh [name] [quick]
#
# Build first:  nix develop -c cargo build --release -p paw-tui
#               bench/tracktion/build.sh          (optional, for the comparison)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
name="${1:-$(date +%Y%m%d-%H%M%S)}"
quick="${2:-}"
paw="$root/target/release/paw"
te="$root/third_party/build-te_bench/te_bench_artefacts/Release/te_bench"
[ -x "$te" ] || te=""
reps="${REPS:-3}"

export BENCH_TMP="${BENCH_TMP:-/tmp/paw-bench}"
mkdir -p "$here/results"
# Keep both programs away from the machine: a scratch home, XDG and runtime
# folders, no plugin folders, as in the tests (tests/tools/env.sh).
ROOT=$root
PAW_TEST_SCRATCH="$BENCH_TMP/sealed"
. "$root/tests/tools/env.sh"
out="$here/results/$name.jsonl"

d() { "$paw" --clean --no-plugins -l "$here/$1" "${@:2}" 2>/dev/null | grep '^{' >> "$out" || echo "FAILED: paw $*" >&2; }
t() { [ -n "$te" ] && { "$te" "$@" 2>/dev/null | grep '^{' >> "$out" || echo "FAILED: te_bench $*" >&2; }; return 0; }

# The audio file both engines play.
"$paw" --clean --no-plugins -e "dofile('$here/lib.lua').wav()" -l /dev/null >/dev/null 2>&1 || true
wav="$BENCH_TMP/bench-2s.wav"
[ -f "$wav" ] || { echo "cannot make $wav" >&2; exit 1; }

if [ -n "$quick" ]; then
  tracks_list="1 10 100"; edits_list="100 1000"
else
  tracks_list="1 10 100 500"; edits_list="100 1000 5000"
fi

echo "render" >&2
for r in $(seq "$reps"); do
  for n in $tracks_list; do
    for spec in "audio 0 0" "audio 1 1" "midi 0 0" "midi 1 0" "midi 1 1"; do
      # Tracktion's 4OSC is slow enough single-threaded that 500 tracks of it
      # take minutes; it is run with all cores only.
      d render.lua "$n" ${spec} 16
      if ! { [ "$n" = 500 ] && [[ "$spec" == midi* ]]; }; then t render "$n" ${spec} 1 16 "$wav"; fi
      t render "$n" ${spec} "$(nproc)" 16 "$wav"
    done
  done
done

echo "blocks" >&2
for spec in "10 midi 1 1 128 5" "100 midi 1 1 128 5" "100 midi 1 1 128 5 edit" "500 audio 1 1 256 5" "500 audio 1 1 256 5 edit"; do
  d blocks.lua ${spec}
done
# Tracktion's blocks are called back to back through its hosted audio device,
# not on a real-time clock; there is no editing variant.
for spec in "10 midi 1 1 X 128" "100 midi 1 1 X 128" "500 audio 1 1 X 256"; do
  t blocks ${spec/X/1} 5 "$wav"
  t blocks ${spec/X/$(nproc)} 5 "$wav"
done

echo "edit" >&2
for r in $(seq "$reps"); do
  for n in $edits_list; do
    d edit.lua clips "$n"; d edit.lua clips "$n" nosync; t edit "$n"
    d edit.lua notes "$n"; d edit.lua notes "$n" nosync; t notes "$n"
  done
  for n in 10 100 500 1000; do d edit.lua scale "$n"; d edit.lua turn "$n"; done
done

echo "save/load and memory" >&2
for r in $(seq "$reps"); do
  for n in 10 100 500; do
    d saveload.lua "$n" 8; t saveload "$n" 8 "$BENCH_TMP"
  done
done
for n in 100 500; do
  d memory.lua project "$n" 8 1000; t memory "$n" 8 1000
done
d memory.lua churn 30

echo "startup" >&2
"$here/startup.sh" "$paw" "$te" 10 >> "$out"

"$paw" --clean --no-plugins -l "$here/summarize.lua" "$out"
