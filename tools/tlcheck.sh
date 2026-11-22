#!/bin/sh
# Type-checks every Teal file of the source tree with tlconfig.lua: the
# runtime's modules, runtime/types, the example configuration and the
# extensions. One `cyan check` does all of them in one process (`tl check`
# once for each file checked the modules that a file requires again for
# each file: fifteen times slower). The flake's `teal` check and the dev
# shell run it with the cyan of nix/lua-tools.nix, on the Teal of nixpkgs
# (the version the program contains, runtime/lua/tl.lua); the test suite
# runs the same check with the compiler in the program (`paw.lang.check`).
#
#   tools/tlcheck.sh [cyan]     the `cyan` program to run (default: on the PATH)
#
# Exits 1 when a file has an error, and prints each error and warning.
cyan=${1:-cyan}
cd "$(dirname "$0")/.." || exit 1
# A module of an extension finds the extension's other modules: each
# extension's `lua/` is on the path (their modules are named after the
# extension, so they do not collide).
includes=$(find extensions -mindepth 2 -maxdepth 2 -type d -name lua | sort | sed 's/^/-I /')
# Each module takes the `paw` global through `local paw = (_G as ...).paw`
# (the teal skill), which Teal warns of as a redeclaration in sixty files:
# that warning is off here. The suite's strict check (`paw.lang.check`)
# still reports a shadowed local.
# shellcheck disable=SC2046,SC2086
if ! out=$("$cyan" --quiet --color never --wdisable redeclaration $includes check $(find runtime config extensions -name '*.tl' | sort) 2>&1); then
  echo "$out"
  exit 1
fi
echo "tl check: no errors"
