#!/bin/sh
# Checks that every Lua file is formatted with StyLua (stylua.toml) and
# every Teal file with cerulean (`ceru`, the flags below). It changes no
# file. The flake's `format` check runs it.
#
#   tools/fmtcheck.sh            check: exits 1 and names the files to format
#   tools/fmtcheck.sh fix        format them
#
# cerulean's output is not valid Teal for limit.tl, pick.tl and ui.tl: it
# skips them, and so does this check. Generated files are left out.
cd "$(dirname "$0")/.." || exit 1
# cerulean reads its settings from tlconfig.lua, which cyan checks for
# unknown keys: they are flags here.
ceru_flags="--indent 2 --line-length 120 --no-sort-requires"
teal_files() {
  find runtime config extensions tools -name '*.tl' ! -path 'runtime/types/*' ! -path 'runtime/lua/paw/events/kernel.tl' \
    ! -path 'runtime/lua/paw/limit.tl' ! -path 'runtime/lua/paw/pick.tl' ! -path 'runtime/lua/paw/ui.tl' | sort
}
if [ "$1" = "fix" ]; then
  stylua .
  # shellcheck disable=SC2086
  teal_files | xargs ceru $ceru_flags
  exit 0
fi
status=0
if ! out=$(stylua --check --output-format summary . 2>&1); then
  echo "$out" | grep '\.lua$' | sed 's/^/not formatted (StyLua): /'
  status=1
fi
# shellcheck disable=SC2086
out=$(teal_files | xargs ceru --check $ceru_flags 2>&1 | grep 'would reformat')
if [ -n "$out" ]; then
  echo "$out" | sed 's/^/not formatted (cerulean): /'
  status=1
fi
[ $status -eq 0 ] && echo "format: every Lua and Teal file is formatted"
[ $status -eq 1 ] && echo "format: run tools/fmtcheck.sh fix"
exit $status
