#!/bin/sh
# The checks of the files that git keeps, cheap enough for each commit
# (.githooks/pre-commit) and part of `nix flake check` (check `hygiene`):
#
# - No leftover of a patch or merge tool (*.orig, *.rej): a merge by hand
#   once committed five of them.
# - No id of the local task board and no path into it. The board, its
#   milestones and the architecture folder are local to the owner's machine,
#   so a reader of the repository cannot follow such a reference.
#
#   tools/hygiene.sh        check, and print each file and line at fault
cd "$(dirname "$0")/.." || exit 1
if git rev-parse --git-dir > /dev/null 2>&1; then
  files() { git ls-files; }
else
  files() { find . -type f | sed 's|^\./||'; }
fi
bad=0
left=$(files | grep -E '\.(orig|rej)$')
if [ -n "$left" ]; then
  echo "hygiene: git keeps leftovers of a patch or merge tool; remove them:"
  echo "$left"
  bad=1
fi
# The pattern is written so that it does not find itself in this file.
ids=$(files | tr '\n' '\0' | xargs -0 grep -nIE 'TASK-[0-9]|backlo[g]/|\(m-[0-9]+\)' 2> /dev/null)
if [ -n "$ids" ]; then
  echo "hygiene: a kept file names a ticket, a milestone or the local board; say what the work is instead:"
  echo "$ids"
  bad=1
fi
[ "$bad" -eq 0 ] && echo "hygiene: no leftovers and no ids of the local board"
exit "$bad"
