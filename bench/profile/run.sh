#!/usr/bin/env bash
# Run one scenario of the profile (bench/profile.md) on the shared machine:
# one measurement at a time (a lock), on cores of its own (taskset).
#   nix develop .#profile -c bench/profile/run.sh <scenario> [drive.py options]
# CORES (default 16-23) and LOCK (default /tmp/claude-1000/paw-measure.lock,
# or $XDG_RUNTIME_DIR/paw-measure.lock) can be set.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lock="${LOCK:-/tmp/claude-1000/paw-measure.lock}"
[ -d "$(dirname "$lock")" ] || lock="${XDG_RUNTIME_DIR:-/tmp}/paw-measure.lock"
exec flock "$lock" taskset -c "${CORES:-16-23}" python3 "$here/drive.py" "$@"
