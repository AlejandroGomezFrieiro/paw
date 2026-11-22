#!/usr/bin/env bash
# A Claude Code hook (.claude/settings.json): after an edit of a Markdown file
# in this repository, or in one of its worktrees, run Vale on it. Errors go
# back to the agent (exit 2), to fix before it goes on.
set -uo pipefail
file=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("tool_input") or {}).get("file_path") or (d.get("tool_response") or {}).get("filePath") or "")')
case "$file" in *.md) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0
root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -x "$root/tools/vale.sh" ] && [ -f "$root/.vale.ini" ] || exit 0
case "$file" in "$root"/target/*|"$root"/.claude/*|"$root"/CLAUDE.md) exit 0 ;; esac
out=$("$root/tools/vale.sh" --minAlertLevel=error --output=line --no-exit "$file" 2>&1)
if [ -n "$out" ]; then
  {
    echo "Vale found errors in $file (fix them: .claude/skills/diataxis-docs/SKILL.md; plain-writing for external pages, STE for internal text):"
    echo "$out" | sed "s|^$root/||"
  } >&2
  exit 2
fi
exit 0
