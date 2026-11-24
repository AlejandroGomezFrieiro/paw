#!/bin/sh
# Sets Done each ticket whose merge is on main, and commits the board.
#
#   tools/board-sync.sh [--dry-run] [<since>]
#
# A merge commit whose subject starts with "Merge TASK-<n>" (or names more
# tickets: "Merge TASK-<a>, TASK-<b>: ...") lands those tickets. A merge that
# lands part of a ticket says "Merge part of TASK-<n>", and the script
# leaves that ticket as it is. The script reads
# the merges on the first-parent line of main after <since> (default: the
# commit of the last sync, kept in .git/board-synced), sets each named
# ticket Done with a note that names the merge, and commits backlog/.
# A ticket that is already Done is left as it is, so a second run does
# nothing. .githooks/post-merge runs it after each merge or fast-forward
# of main.
cd "$(git rev-parse --show-toplevel)" || exit 1
command -v backlog > /dev/null || { echo "board-sync: no backlog command; the board is not changed" >&2; exit 0; }
dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "board-sync: not on main; the board is not changed" >&2; exit 0; }
mark="$(git rev-parse --git-common-dir)/board-synced"
since=${1:-$(cat "$mark" 2> /dev/null)}
range=HEAD
[ -n "$since" ] && range="$since..HEAD"
git log --first-parent --merges --format='%h %s' "$range" | grep -E '^[0-9a-f]+ Merge TASK-' |
  while read -r sha subject; do
    ids=$(printf '%s\n' "$subject" | sed 's/:.*//' | grep -oE 'TASK-[0-9]+(\.[0-9]+)*')
    for id in $ids; do
      status=$(backlog task "$id" --plain 2> /dev/null | sed -n 's/^Status: *//p' | head -1)
      [ -z "$status" ] && { echo "board-sync: $id (merge $sha) is not on the board" >&2; continue; }
      case $status in *Done*) continue ;; esac
      echo "board-sync: $id Done (merge $sha)"
      [ "$dry" -eq 1 ] && continue
      backlog task edit "$id" -s Done --append-notes "On main in merge $sha ($(date +%F)), set Done by tools/board-sync.sh." > /dev/null
    done
  done
[ "$dry" -eq 1 ] && exit 0
git rev-parse HEAD > "$mark"
# The commit is made with a scratch index: inside the post-merge hook git
# refuses a commit of some paths, and other staged files must stay out.
if [ -n "$(git status --porcelain -- backlog)" ]; then
  index=$(mktemp)
  GIT_INDEX_FILE=$index git read-tree HEAD
  GIT_INDEX_FILE=$index git add backlog
  tree=$(GIT_INDEX_FILE=$index git write-tree)
  rm -f "$index"
  old=$(git rev-parse HEAD)
  new=$(git commit-tree "$tree" -p "$old" -m "Board: the tickets of the merges on main are Done")
  git update-ref -m "board-sync" refs/heads/main "$new" "$old"
  git reset -q -- backlog
  git rev-parse HEAD > "$mark"
  echo "board-sync: board committed ($(git rev-parse --short HEAD))"
fi
