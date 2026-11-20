#!/bin/sh
# `tl check` on every Teal file of the source tree, with tlconfig.lua: the
# runtime's modules, runtime/types, the example configuration and the
# extensions. The flake's `teal` check runs it with the Teal of nixpkgs (the
# version the program contains, runtime/lua/tl.lua); the test suite runs the
# same check with the compiler in the program (`paw.lang.check`).
#
#   tools/tlcheck.sh [tl]     the `tl` program to run (default: tl on the PATH)
#
# Exits 1 when a file has an error, and prints each error.
tl=${1:-tl}
cd "$(dirname "$0")/.." || exit 1
status=0
for file in $(find runtime config extensions -name '*.tl' | sort); do
  # A module of an extension finds the extension's other modules.
  dir=$(echo "$file" | sed -n 's#^\(extensions/[^/]*\)/.*#\1/lua#p')
  if ! out=$("$tl" check ${dir:+-I "$dir"} "$file" 2>&1); then
    echo "$out" | grep -v "^ *$" | grep -v "^=*$"
    status=1
  fi
done
[ $status -eq 0 ] && echo "tl check: no errors"
exit $status
