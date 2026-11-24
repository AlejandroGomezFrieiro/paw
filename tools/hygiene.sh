#!/bin/sh
# The checks of the files that git keeps, cheap enough for each commit
# (.githooks/pre-commit) and part of `nix flake check` (check `hygiene`):
#
# - No leftover of a patch or merge tool (*.orig, *.rej): a merge by hand
#   once committed five of them.
# - No id of a ticket or a milestone of the task board, outside the board
#   (backlog/) and the architecture map (groma/). A comment or a page says
#   what the work is: a ticket id goes stale when the ticket is archived,
#   and the architecture folder that tickets name is local to the owner's
#   machine.
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
ids=$(files | grep -vE '^(backlog|groma)/' | tr '\n' '\0' | xargs -0 grep -nIE 'TASK-[0-9]|\(m-[0-9]+\)' 2> /dev/null)
if [ -n "$ids" ]; then
  echo "hygiene: a kept file outside the board names a ticket or a milestone; say what the work is instead:"
  echo "$ids"
  bad=1
fi
# The board and the map are public: no path of a machine's home or of an
# agent's scratch folder.
homes=$(files | grep -E '^(backlog|groma)/' | tr '\n' '\0' | xargs -0 grep -nIE '/hom[e]/[a-z]+/|/tmp/claud[e]-[0-9]' 2> /dev/null)
if [ -n "$homes" ]; then
  echo "hygiene: the board names a path of a home or a scratch folder; remove it:"
  echo "$homes"
  bad=1
fi
[ "$bad" -eq 0 ] && echo "hygiene: no leftovers and no ids of the board outside it"
exit "$bad"
