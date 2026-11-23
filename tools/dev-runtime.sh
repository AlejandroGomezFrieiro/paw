#!/bin/sh
# Makes a Lua runtime folder from this checkout's runtime/lua, with each Teal
# module compiled to Lua, for a paw binary that another checkout built:
#
#   tools/dev-runtime.sh [out]        default: target/dev-runtime
#   PAW_RUNTIME=target/dev-runtime <binary> ...
#
# The kernel finds the modules under `$PAW_RUNTIME/lua` before the runtime
# that is built into the binary (kernel.rs), and the bundled extensions under
# the current directory (ext.lua). So a change of Lua or Teal needs no build:
# one binary of main serves the tests of many checkouts. A change of Rust
# still needs a build of that checkout.
#
# The Lua is the same as the build makes (crates/paw-core/build.rs): Teal for
# Lua 5.1, no compat code (tlconfig.lua). `cyan gen` checks the types first,
# in one process for all the modules. The .tl stays beside its .lua: the Lua
# has no comments, and the search picker of the Lua API reads the doc
# comments from the .tl (doc_of in runtime/lua/paw/pick/project.tl), as the
# built runtime gives it the .tl as the source. `require` loads only the .lua.
cd "$(dirname "$0")/.." || exit 1
out=${1:-target/dev-runtime}
rm -rf "$out"
mkdir -p "$out"
cp -a runtime/lua "$out/lua"
# shellcheck disable=SC2046
if ! log=$(cyan --quiet --color never --wdisable redeclaration gen $(find "$out/lua" -name '*.tl' ! -name '*.d.tl' | sort) 2>&1); then
  echo "$log"
  exit 1
fi
echo "runtime: $out ($(find "$out/lua" -name '*.lua' | wc -l) Lua modules)"
