#!/usr/bin/env bash
# Two builds of paw that differ in the allocator, in turns: the slices of
# the help index (help.lua) and the slow-key warnings of `j` on the large
# project (drive.py's `repeat`, --budget 5).
#
#   nix develop .#profile -c bench/profile/allocator.sh <paw glibc> <paw mimalloc> [pairs]
#
# Give two binaries of the same profile: one of a commit before mimalloc
# became the global allocator, and one after. pairs is 5 if not given.
# CORES (default 16-23) and LOCK (default /tmp/claude-1000/paw-measure.lock,
# or $XDG_RUNTIME_DIR/paw-measure.lock) can be set, as in run.sh.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 2 ] || { sed -n '2,11p' "$0" >&2; exit 2; }
glibc="$(realpath "$1")"
mimalloc="$(realpath "$2")"
pairs="${3:-5}"
lock="${LOCK:-/tmp/claude-1000/paw-measure.lock}"
[ -d "$(dirname "$lock")" ] || lock="${XDG_RUNTIME_DIR:-/tmp}/paw-measure.lock"
cores="${CORES:-16-23}"

# mimalloc writes its options at the start when MIMALLOC_VERBOSE is set:
# a check that each binary has the allocator that its name says.
has_mimalloc() { MIMALLOC_VERBOSE=1 "$1" --version 2>&1 | grep -q '^mimalloc:'; }
if has_mimalloc "$glibc"; then echo "$glibc uses mimalloc: give a binary from before the change" >&2; exit 1; fi
if ! has_mimalloc "$mimalloc"; then echo "$mimalloc does not use mimalloc" >&2; exit 1; fi

# The median, smallest and largest value of each field of the JSON lines
# in a file, for one label.
summary() {
  python3 - "$1" <<'EOF'
import json, sys
rows = {}
for line in open(sys.argv[1]):
    label, rec = line.split(" ", 1)
    for k, v in json.loads(rec).items():
        rows.setdefault(k, {}).setdefault(label, []).append(v)
for k, by in rows.items():
    cells = []
    for label in ("glibc", "mimalloc"):
        v = sorted(by.get(label, []))
        cells.append(f"{label} {v[len(v) // 2]} ({v[0]} to {v[-1]})" if v else f"{label} -")
    print(f"{k}: " + " | ".join(cells))
EOF
}

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
echo "load at the start: $(cut -d' ' -f1-3 /proc/loadavg)"

echo "== the help index, $pairs pairs, no project"
for _ in $(seq "$pairs"); do
  for label in glibc mimalloc; do
    if [ "$label" = glibc ]; then paw="$glibc"; else paw="$mimalloc"; fi
    line="$(PAW="$paw" flock "$lock" taskset -c "$cores" python3 "$here/headless.py" "$here/help.lua" 2>/dev/null | grep '^{' | tail -1)"
    echo "$label $line" >> "$out"
  done
done
summary "$out"

echo "== j on the large project, --budget 5, $pairs pairs"
flock "$lock" taskset -c "$cores" python3 "$here/compare.py" "$glibc" "$mimalloc" "$pairs" \
  repeat --keys j --times 20 --budget 5
echo "load at the end: $(cut -d' ' -f1-3 /proc/loadavg)"
