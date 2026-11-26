#!/bin/sh
# Shows who holds the cargo slots and the suite slots, and the last N cargo
# runs with their wait (default 8).
#
#   tools/queue.sh [N]
here=$(cd "$(dirname "$0")" && pwd)
. "$here/queue-defaults.sh"
echo "cargo: $PAW_CARGO_SLOTS slots of $PAW_CARGO_JOBS jobs ($PAW_CARGO_LOCKS/cargo)"
"$PAW_HEAVY" --status --pool cargo --slots "$PAW_CARGO_SLOTS" --dir "$PAW_CARGO_LOCKS"
held=0
total=0
for slot in "$PAW_CARGO_LOCKS"/slot*; do
  [ -f "$slot" ] || continue
  total=$((total + 1))
  flock -n "$slot" true || held=$((held + 1))
done
echo "suite: $held of $total paw slots held"
log=$PAW_CARGO_LOCKS/cargo.log
[ -s "$log" ] || exit 0
echo "last cargo runs (waited, ran, exit, command, folder):"
tail -n "${1:-8}" "$log" | python3 -I -c '
import json, sys
for line in sys.stdin:
    r = json.loads(line)
    ran = "-" if r["ran_ms"] is None else "%.0fs" % (r["ran_ms"] / 1000)
    print("  %5.0fs %6s %4s  %s  (%s)" % (r["waited_ms"] / 1000, ran, r["exit"], r["command"].split("/")[-1][:70], r["cwd"]))
'
