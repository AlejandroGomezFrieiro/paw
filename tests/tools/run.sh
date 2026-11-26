#!/bin/sh
# Run paw by hand in the test environment (tests/tools/env.sh): scratch
# home and XDG folders, no plugin of the machine, no desktop bus.
#
#   tests/tools/run.sh --clean --no-plugins -l tools/apidoc.lua check
#
# The binary is the one that env.sh's paw_ready gives: a paw of this
# checkout's sources, built if there is none.
. "$(dirname "$0")/env.sh"
cd "$ROOT" || exit 1
paw_ready || exit 1
exec "$BIN/paw" "$@"
