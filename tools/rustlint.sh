#!/bin/sh
# The checks of the Rust code that clippy does not do, cheap enough for each
# commit (.githooks/pre-commit) and part of `nix flake check` (check
# `rustlint`):
#
# - No free function that gives a constant, such as a serde default
#   `fn one() -> f64 { 1.0 }`. A type with `Default` says the default.
# - No free `is_zero`, `is_one`, `is_false` or `is_true` helper, such as a
#   serde skip. paw-core's `model::serde_util::is_default` does the job.
# - No module of paw-core's model names the session, the sync, the API or
#   the kernel: the model is the lowest layer of the kernel.
#
#   tools/rustlint.sh        check, and print each file and line at fault
cd "$(dirname "$0")/.." || exit 1
if git rev-parse --git-dir > /dev/null 2>&1; then
  files() { git ls-files 'crates/*.rs' 'extensions/*.rs'; }
else
  files() { find crates extensions -name '*.rs' | sed 's|^\./||'; }
fi
bad=0
constants=$(files | while read -r f; do
  awk -v f="$f" '
    /^(pub(\(crate\))? )?fn [a-z_0-9]+\(\) -> [A-Za-z0-9]+ \{$/ { at = FNR; next }
    at && FNR == at + 1 && /^ +(true|false|-?[0-9][0-9._]*)$/ { next }
    at && FNR == at + 2 && /^\}$/ { print f ":" at; at = 0; next }
    { at = 0 }
  ' "$f"
done)
if [ -n "$constants" ]; then
  echo "rustlint: a function gives a constant; give its type a Default:"
  echo "$constants"
  bad=1
fi
helpers=$(files | tr '\n' '\0' | xargs -0 grep -nE '^(pub(\(crate\))? )?fn is_(zero|one|false|true)[a-z_0-9]*\(' 2> /dev/null)
if [ -n "$helpers" ]; then
  echo "rustlint: a helper tests one value; use serde_util::is_default:"
  echo "$helpers"
  bad=1
fi
layers=$(files | grep -E '^crates/paw-core/src/model(\.rs|/)' | tr '\n' '\0' |
  xargs -0 grep -nE 'crate::(sync|session|api|kernel)\b' 2> /dev/null)
if [ -n "$layers" ]; then
  echo "rustlint: the model names a higher layer of paw-core:"
  echo "$layers"
  bad=1
fi
[ "$bad" -eq 0 ] && echo "rustlint: no constant functions, no one-value helpers, the model stays low"
exit "$bad"
