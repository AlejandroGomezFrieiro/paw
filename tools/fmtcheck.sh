#!/bin/sh
# Says how many Lua and Teal files the formatters would change: StyLua with
# stylua.toml for `.lua`, cerulean (`ceru`) for `.tl`, each as close to
# paw's style as it goes. It changes no file, and it exits 0: the tree is
# not formatted with them (docs/explanation/about-teal.md says why). The
# flake's `format` check runs it.
#
#   tools/fmtcheck.sh            the counts
#   tools/fmtcheck.sh -v         and the files
cd "$(dirname "$0")/.." || exit 1
# cerulean reads its settings from tlconfig.lua, which cyan checks for
# unknown keys: they are flags here.
ceru_flags="--indent 2 --line-length 120 --no-sort-requires"
lua=$(stylua --check --output-format summary . 2>&1 | grep -c '\.lua$')
# shellcheck disable=SC2086
tl=$(find runtime config extensions -name '*.tl' ! -path 'runtime/lua/paw/events/kernel.tl' | sort \
  | xargs ceru --check $ceru_flags 2>&1 | grep -c 'would reformat\|formatting skipped')
echo "format: StyLua would change $lua Lua files, cerulean $tl Teal files (nothing is changed)"
if [ "$1" = "-v" ]; then
  stylua --check --output-format summary . 2>&1
  # shellcheck disable=SC2086
  find runtime config extensions -name '*.tl' ! -path 'runtime/lua/paw/events/kernel.tl' | sort | xargs ceru --check $ceru_flags 2>&1
fi
exit 0
