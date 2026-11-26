#!/usr/bin/env bash
set -euo pipefail

install_root=$(realpath "${1:?usage: cargo-install-smoke.sh INSTALL-ROOT VERSION}")
version=${2:?give the Cargo package version}
runner=$(cd "$(dirname "$0")" && pwd)/run.sh
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/outside"
unset PAW_HOME PAW_EXTENSIONS PAW_RUNTIME

run() {
  ROOT="$scratch/outside" TMPDIR="$scratch" PAW_TEST_SCRATCH="$scratch/state" \
    PAW_TEST_BIN="$install_root/bin" PAW_TEST_STAMP=off "$runner" "$@"
}

actual=$(run --version)
if [ "$actual" != "paw $version" ]; then
  printf 'expected paw %s, got %s\n' "$version" "$actual" >&2
  exit 1
fi

# A Cargo install has no separate runtime directory.
printf '%s\n' 'assert(paw.api.engine_get().backend == "null")' > "$scratch/check.lua"
run --clean --no-plugins --audio null --no-listen -l "$scratch/check.lua"
