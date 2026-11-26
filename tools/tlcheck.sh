#!/bin/sh
# Type-checks every Teal file of the source tree with the strict check of
# tools/tlcheck.lua: `paw.lang.check`, the compiler in the program, with
# tlconfig.lua. Every error and every warning fails. The test suite and the
# flake's `teal` check run the same check, so the three agree. A change of
# Teal needs no build: any binary checks the files of this checkout.
#
#   tools/tlcheck.sh            with the paw of tests/tools/run.sh, in the test environment
#   tools/tlcheck.sh <paw>      with that binary, in the environment it is given (the flake)
#
# Exits 1 when a file has a problem, and prints each one.
cd "$(dirname "$0")/.." || exit 1
if [ -n "$1" ]; then
  exec "$1" --clean --no-plugins -l tools/tlcheck.lua
fi
exec tests/tools/run.sh --clean --no-plugins -l tools/tlcheck.lua
