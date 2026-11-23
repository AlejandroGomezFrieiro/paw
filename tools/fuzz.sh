#!/bin/sh
# Builds or runs the fuzz targets of fuzz/ (cargo-fuzz, libFuzzer): the
# readers of what comes from outside paw. This is the nightly tier, and it
# runs in CI only, not on the shared machine (testing-practices.md, owner
# 2026-11-22).
#
#   tools/fuzz.sh build      build each target, and run none
#   tools/fuzz.sh [RUNS]     run each target for RUNS inputs (default 200000)
#
# Needs cargo-fuzz and a nightly Rust: a nightly `cargo` on the PATH, or
# `RUSTUP_TOOLCHAIN=nightly` with rustup. The dev shell has neither.
#
# Each target starts from its seeds (fuzz/seeds/<target>, in git) and the
# corpus that earlier runs kept (fuzz/corpus/<target>, not in git). A
# failure leaves its input in fuzz/artifacts/<target>/ and the script exits
# 1. A crash becomes a ticket and a plain regression test in the crate of
# the code that crashed (the skill rust-testing); the target stays as it is.
set -eu
cd "$(dirname "$0")/.."
mode=${1:-200000}
if [ "$mode" = build ]; then
  exec cargo fuzz build
fi
status=0
for target in $(cargo fuzz list); do
  mkdir -p "fuzz/corpus/$target"
  # A count of runs, not a time: the same work each night. An input that
  # takes 60 s is a hang and fails the run.
  cargo fuzz run "$target" "fuzz/corpus/$target" "fuzz/seeds/$target" -- \
    -runs="$mode" -timeout=60 || status=1
done
exit "$status"
