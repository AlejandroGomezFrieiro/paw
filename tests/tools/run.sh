#!/bin/sh
# Run paw by hand in the test environment (tests/tools/env.sh): scratch
# home and XDG folders, no plugin of the machine, no desktop bus.
#
#   tests/tools/run.sh --clean --no-plugins -l tools/apidoc.lua check
#
# The binary is $PAW_TEST_BIN/paw, or target/release/paw.
. "$(dirname "$0")/env.sh"
cd "$ROOT" || exit 1
exec "$BIN/paw" "$@"
