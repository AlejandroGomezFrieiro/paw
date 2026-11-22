#!/usr/bin/env bash
# What expanding nest clips costs the sync layer (crates/paw-core/benches/nest_expand.rs).
#   nix develop -c bench/nest.sh [out.jsonl]
# Builds the bench, then runs it for 100 and 1 000 nest clips of 96 and of
# 384 notes, on CPUs 16-23, one run at a time (a lock shared with other
# measurements of this machine). Each line gets the load average.
set -euo pipefail
out="${1:-/dev/stdout}"
cargo bench -p paw-core --bench nest_expand --no-run 2>/dev/null
bin=$(ls -t target/release/deps/nest_expand-* | grep -v '\.d$' | head -1)
lock="${PAW_MEASURE_LOCK:-/tmp/claude-1000/paw-measure.lock}"
for count in 100 1000; do
  for notes in 96 384; do
    load=$(cut -d' ' -f1-3 /proc/loadavg)
    flock "$lock" taskset -c 16-23 "$bin" "$count" "$notes" 9 |
      sed "s/}\$/,\"load\":\"$load\",\"note\":\"measured under external load\"}/" >> "$out"
  done
done
