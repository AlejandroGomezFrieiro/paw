#!/usr/bin/env bash
# The check of the architecture documentation (the folder architecture/ at
# the top of the main checkout). It changes no file. SKILL.md, part 7, tells
# what each check guards.
#
#   .claude/skills/architecture/archlint.sh            check the folder
#   .claude/skills/architecture/archlint.sh -v         also print each note
#   .claude/skills/architecture/archlint.sh <dir>      check another folder
#
# Errors (exit 1):
#   link      a relative Markdown link to a file that does not exist
#   cite      a cited `path:line` whose file does not exist or is too short
#   adr       an ADR with no status, a status that is not known, no date,
#             a number used two times, a "superseded by" to no ADR, or an
#             ADR that decisions/README.md does not list
#   target    an item of a "Target" part that names no ticket and no bundle
#   ticket    a ticket id that the Backlog does not have
#   groma     a `groma:<id>` that the Groma map does not have
# Notes (no failure, counted; -v prints them):
#   noticket  a target item that names a bundle but no ticket yet
#
# The folder is local and git does not keep it. An agent in a worktree finds
# it from the common git folder, which is in the main checkout.
set -uo pipefail

verbose=0
if [ "${1:-}" = -v ]; then
  verbose=1
  shift
fi
if [ $# -ge 1 ]; then
  arch=$(cd "$1" && pwd) || exit 2
else
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    echo "archlint: not in a git checkout; give the folder as an argument" >&2
    exit 2
  }
  arch=$(cd "$common/.." && pwd)/architecture
fi
if [ ! -d "$arch" ]; then
  echo "archlint: no folder $arch (the documentation is local to the owner's machine)" >&2
  exit 2
fi
root=$(cd "$arch/.." && pwd)
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
bl="$root/backlog"
groma="$root/groma"

errors=0
notes=0
err() {
  echo "error: $1: $2"
  errors=$((errors + 1))
}
note() {
  [ "$verbose" -eq 1 ] && echo "note: $1: $2"
  notes=$((notes + 1))
}
rel() { echo "${1#"$root"/}"; }

mapfile -t files < <(find "$arch" -name '*.md' | sort)

# 1. Links. Each relative link resolves from the folder of its file.
for f in "${files[@]}"; do
  dir=$(dirname "$f")
  while IFS=: read -r n target; do
    case "$target" in
      http:* | https:* | mailto:* | '#'*) continue ;;
    esac
    path=${target%%#*}
    [ -z "$path" ] && continue
    [ -e "$dir/$path" ] || err link "$(rel "$f"):$n: $target"
  done < <(grep -noE '\]\([^)[:space:]]+\)' "$f" | sed -E 's/^([0-9]+):\]\((.*)\)$/\1:\2/')
done

# 2. Citations: `some/path.ext:123` or `some/path.ext:12-34`, from the checkout.
for f in "${files[@]}"; do
  while IFS=: read -r n cite; do
    path=${cite%%:*}
    line=${cite#*:}
    line=${line%%-*}
    if [ ! -f "$root/$path" ]; then
      err cite "$(rel "$f"):$n: $path does not exist"
    elif [ "$(wc -l <"$root/$path")" -lt "$line" ]; then
      err cite "$(rel "$f"):$n: $path has fewer than $line lines"
    fi
  done < <(grep -noE '`[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+(-[0-9]+)?`' "$f" | tr -d '`')
done

# 3. ADRs: decisions/NNNN-title.md with front matter.
declare -A seen=()
index="$arch/decisions/README.md"
for f in "$arch"/decisions/[0-9][0-9][0-9][0-9]-*.md; do
  [ -e "$f" ] || continue
  base=$(basename "$f")
  num=${base%%-*}
  if [ -n "${seen[$num]:-}" ]; then err adr "$base: number $num is also ${seen[$num]}"; fi
  seen[$num]=$base
  front=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } NR > 1 { print }' "$f")
  status=$(printf '%s\n' "$front" | sed -n 's/^status: *//p')
  case "$status" in
    proposed | accepted | rejected | deprecated) ;;
    "superseded by "[0-9][0-9][0-9][0-9])
      by=${status#superseded by }
      # A portable glob test: the glob stays as it is when no file matches.
      found=0
      for match in "$arch/decisions/$by"-*.md; do
        [ -e "$match" ] && found=1 && break
      done
      [ "$found" -eq 1 ] || err adr "$base: superseded by $by, which does not exist"
      ;;
    "") err adr "$base: no status" ;;
    *) err adr "$base: status '$status' is not known" ;;
  esac
  printf '%s\n' "$front" | grep -qE '^date: [0-9]{4}-[0-9]{2}-[0-9]{2}$' || err adr "$base: no date (YYYY-MM-DD)"
  [ -f "$index" ] && ! grep -qF "($base)" "$index" && err adr "$base: decisions/README.md does not list it"
done

# 4. Target items. A part whose heading starts with "Target" holds target
# items: each list item at the left margin and each table row of the part.
# The part ends at the next heading of the same level or higher.
for f in "${files[@]}"; do
  case "$f" in "$arch"/decisions/*) continue ;; esac
  # An item is a list item at the left margin with its wrapped lines, or
  # a table row. A table row just before a separator row is a header.
  awk -v file="$(rel "$f")" '
    function judge() {
      if (item != "" && item !~ /TASK-[[:digit:]]/) {
        kind = (item ~ /bundle [A-Z][A-Z0-9]*/) ? "noticket" : "target"
        print kind "\t" file ":" at ": " substr(first, 1, 70)
      }
      item = ""
    }
    function begin(line) {
      judge()
      item = line
      first = line
      at = NR
    }
    /^```/ { judge(); fence = !fence; next }
    fence { next }
    /^#+ / {
      judge()
      level = length($1)
      title = substr($0, level + 2)
      if (in_target && level <= tlevel) in_target = 0
      if (title ~ /^Target/) { in_target = 1; tlevel = level }
      next
    }
    !in_target { next }
    /^\| *:?-/ { item = ""; next }
    /^- / || /^\| / { begin($0); next }
    /^  / && item ~ /^- / { item = item " " $0; next }
    { judge() }
    END { judge() }
  ' "$f"
done >"$tmp"
while IFS=$'\t' read -r kind msg; do
  if [ "$kind" = noticket ]; then note noticket "$msg"; else err target "$msg"; fi
done <"$tmp"

# 5. Ticket ids exist in the Backlog (open, done or archived).
if [ -d "$bl" ]; then
  mapfile -t known < <(find "$bl" -name 'task-*.md' -printf '%f\n' | sed -E 's/^task-([0-9.]+) .*/\1/' | sort -u)
  declare -A have=()
  for k in "${known[@]}"; do have[$k]=1; done
  for f in "${files[@]}"; do
    while IFS=: read -r n id; do
      id=${id#TASK-}
      id=${id%.}
      [ -n "${have[$id]:-}" ] || err ticket "$(rel "$f"):$n: TASK-$id"
    done < <(grep -noE 'TASK-[[:digit:]]+(\.[[:digit:]]+)?' "$f")
  done
fi

# 6. Groma ids exist in the map.
if [ -d "$groma" ]; then
  declare -A ids=()
  while read -r id; do ids[$id]=1; done < <(grep -rhoE '^  id: [A-Za-z0-9._-]+' "$groma" | sed 's/^  id: //')
  for f in "${files[@]}"; do
    while IFS=: read -r n id; do
      id=${id#groma:}
      [ -n "${ids[$id]:-}" ] || err groma "$(rel "$f"):$n: $id"
    done < <(grep -noE 'groma:[A-Za-z0-9._-]*[A-Za-z0-9]' "$f")
  done
fi

echo "archlint: $errors errors, $notes notes in $(rel "$arch")"
[ "$errors" -eq 0 ]
