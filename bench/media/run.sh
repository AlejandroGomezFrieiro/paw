#!/usr/bin/env bash
# The numbers of bench/media.md. Short runs under the shared measure lock,
# pinned to CPUs 16-23 (8 threads: what the hash's rayon pool gets).
#   bench/media/run.sh <bench binary> <data folder>
# The data folder holds t.flac t.mp3 t.m4a src.wav small.wav big8.wav and
# stat/ (10 000 small files); bench/media.md says how they are made.
set -euo pipefail
BIN=${1:?bench binary}
DATA=${2:?data folder}
CPUS=${CPUS:-16-23}
run() { flock /tmp/claude-1000/paw-measure.lock taskset -c "$CPUS" "$BIN" "$@"; }
run stretch
run decode "$DATA/t.flac" "$DATA/t.mp3" "$DATA/t.m4a" "$DATA/src.wav"
run hash "$DATA/small.wav" "$DATA/src.wav" "$DATA/big8.wav"
run stat "$DATA/stat"
