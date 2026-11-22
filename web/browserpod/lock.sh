#!/usr/bin/env bash
# Write web/browserpod/Cargo.lock: the lock of the pod build.
#
#   nix develop .#browserpod -c web/browserpod/lock.sh
#
# BrowserPod's Rust pack patches libc, rustix and linux-raw-sys at fixed
# versions. A patch applies only to the version in the lock, so the pod
# build uses Cargo.lock with these crates set back to the pack's versions
# (and mio, whose newest release needs a newer libc). Run this script
# after each change to Cargo.lock: the pod build fails with --locked while
# the two locks differ in another crate.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
lock="$repo/web/browserpod/Cargo.lock"
cargo="${BP_CARGO:-cargo}"
# The pack's cargo has no --lockfile-path: pin in Cargo.lock, keep the
# result, and put Cargo.lock back.
saved="$(mktemp)"
cp "$repo/Cargo.lock" "$saved"
trap 'cp "$saved" "$repo/Cargo.lock"; rm -f "$saved"' EXIT
cd "$repo"
update() { "$cargo" update "$@"; }
update -p mio --precise 1.2.4
update -p libc --precise 0.2.189
# Only rustix 1, if Cargo.lock has an older rustix too.
rustix=$(sed -n '/^name = "rustix"$/{n;s/^version = "\(1\.[^"]*\)"$/\1/p}' Cargo.lock | grep -vx 1.1.4 | head -1 || true)
[ -z "$rustix" ] || update -p "rustix@$rustix" --precise 1.1.4
cp Cargo.lock "$lock"
echo "wrote $lock"
