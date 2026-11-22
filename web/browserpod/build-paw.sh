#!/usr/bin/env bash
# Build paw for a BrowserPod pod (target wasm32-browserpod-linux-musl).
#
#   build-paw.sh SRC OUT
#
# SRC is a copy of the source tree that the build may change: its
# Cargo.lock becomes web/browserpod/Cargo.lock (see lock.sh). OUT is the
# file to write. BP_PACK is BrowserPod's Rust pack, installed (bin/cargo,
# bin/wasm32-browserpod-linux-musl-clang). The flake's derivation
# `paw-pod-bin` runs this script with the pack and the crates offline
# (web/browserpod/default.nix).
set -euo pipefail
src="$(cd "$1" && pwd)"
out="$(realpath -m "$2")"
pack="${BP_PACK:?BP_PACK names the BrowserPod Rust pack}"
here="$src/web/browserpod"
target=wasm32-browserpod-linux-musl
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# setjmp and longjmp for Lua: LLVM's lowering to WebAssembly exceptions,
# and sjlj.c for the functions that it calls.
eh="-mexception-handling -mllvm -wasm-enable-eh -mllvm -wasm-use-legacy-eh=false -mllvm -wasm-enable-sjlj"
# shellcheck disable=SC2086
"$pack/bin/$target-clang" -O2 -c "$here/sjlj.c" -o "$work/sjlj.o" $eh
export CFLAGS_wasm32_browserpod_linux_musl="$eh -D_setjmp=setjmp -D_longjmp=longjmp"
export CARGO_TARGET_WASM32_BROWSERPOD_LINUX_MUSL_RUSTFLAGS="-C link-arg=$work/sjlj.o --remap-path-prefix=$src=/paw"
export CARGO_PROFILE_RELEASE_STRIP=true
# The pack's rustc knows the target; cargo would take the first on PATH.
export RUSTC="$pack/bin/rustc" RUSTC_WRAPPER=
cp "$here/Cargo.lock" "$src/Cargo.lock"
cd "$src"
"$pack/bin/cargo" build --release --locked ${BP_OFFLINE:+--offline} -j "${BP_JOBS:-4}" \
  -p paw-tui --target "$target"
mkdir -p "$(dirname "$out")"
cp "target/$target/release/paw" "$out"
