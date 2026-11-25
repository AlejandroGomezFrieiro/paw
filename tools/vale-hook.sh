#!/usr/bin/env bash
# Shared edit hook for Claude Code and Pi. Vale alerts return exit code 2.
set -uo pipefail
file=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("tool_input") or {}).get("file_path") or (d.get("tool_response") or {}).get("filePath") or "")')
case "$file" in *.md|flake.nix|*/flake.nix) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0
root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0
case "$file" in
  flake.nix|*/flake.nix)
    [ -f "$root/tools/vale-hook.sh" ] || exit 0
    [ "$(realpath -- "$file")" = "$root/flake.nix" ] || exit 0
    if command -v alejandra >/dev/null 2>&1; then
      exec alejandra "$root/flake.nix"
    fi
    cd "$root" || exit 1
    exec nix fmt -- flake.nix
    ;;
esac
[ -x "$root/tools/vale.sh" ] && [ -f "$root/.vale.ini" ] || exit 0
case "$file" in "$root"/target/*|"$root"/.claude/*|"$root"/CLAUDE.md) exit 0 ;; esac
out=$("$root/tools/vale.sh" --output=line --no-exit "$file" 2>&1)
if [ -n "$out" ]; then
  {
    echo "Vale found alerts in $file (fix them: .claude/skills/diataxis-docs/SKILL.md; plain-writing for external pages, STE for internal text):"
    while IFS= read -r line; do
      printf '%s\n' "${line#"$root"/}"
    done <<< "$out"
  } >&2
  exit 2
fi
exit 0
