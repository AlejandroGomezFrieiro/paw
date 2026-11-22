#!/usr/bin/env bash
# Run Vale on paw's documentation with the project's styles:
#
#   tools/vale.sh                      every page (docs/, READMEs, doc/, bench/)
#   tools/vale.sh docs/how-to/*.md     some pages
#   tools/vale.sh --minAlertLevel=suggestion docs/README.md
#
# The style packages come from Nix ($PAW_VALE_STYLES, set by the dev shell);
# the project's own (STE) and its vocabulary are in .vale/styles. Vale takes
# one styles folder, so this joins the two in target/vale-styles.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
# Outside the dev shell (an editor, a hook), take Vale and its styles from
# the dev shell once and keep their paths in target/vale-env.
if [ -z "${PAW_VALE_STYLES:-}" ] || ! command -v vale >/dev/null; then
  env_file=target/vale-env
  if [ ! -s "$env_file" ] || [ flake.nix -nt "$env_file" ] || [ flake.lock -nt "$env_file" ]; then
    mkdir -p target
    nix develop -c bash -c 'printf "PAW_VALE_STYLES=%s\nVALE_BIN=%s\n" "$PAW_VALE_STYLES" "$(command -v vale)"' 2>/dev/null > "$env_file.tmp"
    mv "$env_file.tmp" "$env_file"
  fi
  PAW_VALE_STYLES=$(sed -n 's/^PAW_VALE_STYLES=//p' "$env_file")
  vale_bin=$(sed -n 's/^VALE_BIN=//p' "$env_file")
else
  vale_bin=$(command -v vale)
fi
styles=target/vale-styles.$$
trap 'rm -rf "$styles"' EXIT
rm -rf "$styles"
mkdir -p "$styles"
for d in "$PAW_VALE_STYLES"/* .vale/styles/*; do ln -s "$(realpath "$d")" "$styles/$(basename "$d")"; done
export VALE_STYLES_PATH="$root/$styles"
files=()
opts=()
for a in "$@"; do
  # .vale.ini chooses the styles by the path relative to the root (README.md,
  # docs/**), so a path in the repository becomes relative.
  case "$a" in -*) opts+=("$a") ;; "$root"/*) files+=("${a#"$root"/}") ;; *) files+=("$a") ;; esac
done
if [ ${#files[@]} -eq 0 ]; then
  # bench/RESULTS.md is not checked: it is a dated log of measurements.
  files=(README.md AGENTS.md docs crates/*/README.md extensions/*/README.md extensions/*/doc bench/README.md bench/DAWS.md)
fi
"$vale_bin" --config "$root/.vale.ini" "${opts[@]}" "${files[@]}"
