#!/bin/sh
# Make the GIFs again, from the release build:
#
#   cargo build --release && nix run .#gifs -- [--check] [set or scene...]
#
# The flake's app `gifs` runs this file with VHS and the other tools that
# it needs. Run as docs/images/make/make.sh, it starts the app. PAW_BIN=<folder>
# takes paw from that folder instead of target/release. The skill in
# .claude/skills/paw-gifs gives the rules for a scene.
#
# With no argument, the core's GIFs in docs/images (the README's). The name
# of an extension makes the GIFs of that extension, from the scenes in
# extensions/<name>/images/make into extensions/<name>/images. `all` makes
# the core's and those of each extension. The name of a scene (tui-arrange)
# makes that one alone.
#
# Each scene (tui-*.sh) writes a tape for VHS through rig.sh. VHS runs paw
# in a terminal in a headless browser and records it, and gif.py makes the
# GIF, with the caption and a bar of the keys typed. Each scene starts from
# examples/demo-song.lua. A cast scene (cast-*.sh) records paw in a
# pseudo-terminal with cast.py, into an asciicast that the website plays
# (tools/website/paw-cast.js). Nothing touches your display, sound or MIDI
# devices. The scenes of the window (gui-*.sh, stills.sh) need paw-gui,
# which is paused: a set skips them. NOCOPY=1 leaves the results in
# target/test-scratch/media.
#
# --check runs each scene (all tui-* scenes when none is named) with no
# recording, and fails when a key cannot be sent or paw gives an error.
#
# The status is 0 only when each scene that ran did all that it must: a
# GIF for each scene that records, within the budget of gif.py.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
if [ -z "$PAW_GIFS_APP" ]; then
  exec nix run "$ROOT#gifs" -- "$@"
fi
WORK=${WORK:-$ROOT/target/test-scratch/media}
MAKE=$HERE
export WORK MAKE
mkdir -p "$WORK"

CHECK=
if [ "$1" = "--check" ]; then
  CHECK=1
  shift
  [ $# -eq 0 ] && set -- all
fi
export CHECK
[ $# -eq 0 ] && set -- core

FAILED=
SKIPPED=
COUNT=0
START=$(date +%s)

# make_set dir out: each scene in dir, the GIFs and stills into out.
make_set() {
  for script in "$1"/tui-*.sh "$1"/cast-*.sh "$1"/gui-*.sh "$1"/stills.sh; do
    [ -f "$script" ] || continue
    case $(basename "$script") in
      gui-* | stills.sh) echo "$(basename "$script" .sh): skipped: the window (paw-gui) is paused" ;;
      cast-*) [ -z "$CHECK" ] && scene "$script" "$2" ;;
      *) scene "$script" "$2" ;;
    esac
  done
}
# scene script out: run one scene, make its GIF and copy the results.
scene() {
  name=$(basename "$1" .sh)
  echo "$name"
  COUNT=$((COUNT + 1))
  rm -f "$WORK/$name.mp4" "$WORK/$name.gif" "$WORK/$name.cast" "$WORK/$name.tape"
  : > "$WORK/stills.list"
  if ! SCENE=$name sh "$1"; then
    FAILED="$FAILED $name"
    return
  fi
  case $name in
    cast-*)
      [ -s "$WORK/$name.cast" ] || { echo "$name: cast.py wrote no $name.cast" >&2; FAILED="$FAILED $name"; return; }
      [ -z "$NOCOPY" ] && cp "$WORK/$name.cast" "$2/$name.cast"
      return ;;
  esac
  # A scene that exits before the rig starts says why: it needs a program
  # or a file that this computer does not have.
  if [ ! -f "$WORK/$name.tape" ]; then
    SKIPPED="$SKIPPED $name"
    return
  fi
  [ -n "$CHECK" ] && return
  if grep -q "^Output " "$WORK/$name.tape"; then
    if ! python3 "$HERE/gif.py" "$name"; then
      FAILED="$FAILED $name"
      return
    fi
    [ -z "$NOCOPY" ] && cp "$WORK/$name.gif" "$2/$name.gif"
  fi
  # The stills that the scene took on the way (rig.sh's `still`).
  while read -r still; do
    if [ ! -s "$WORK/$still" ]; then
      echo "$name: VHS wrote no $still" >&2
      FAILED="$FAILED $name"
    elif [ -z "$NOCOPY" ]; then
      cp "$WORK/$still" "$2/$still"
    fi
  done < "$WORK/stills.list"
}

for arg in "$@"; do
  case "$arg" in
    core) make_set "$HERE" "$HERE/.." ;;
    all)
      make_set "$HERE" "$HERE/.."
      for dir in "$ROOT"/extensions/*/images/make; do make_set "$dir" "$dir/.."; done ;;
    *)
      if [ -d "$ROOT/extensions/$arg/images/make" ]; then
        make_set "$ROOT/extensions/$arg/images/make" "$ROOT/extensions/$arg/images"
      else
        found=$(ls "$HERE/$arg.sh" "$ROOT"/extensions/*/images/make/"$arg.sh" 2>/dev/null | head -1)
        if [ -z "$found" ]; then
          echo "no set or scene $arg" >&2
          FAILED="$FAILED $arg"
        else
          scene "$found" "$(dirname "$found")/.."
          # A scene asked for by its name must not be skipped.
          case " $SKIPPED " in *" $arg "*) FAILED="$FAILED $arg" ;; esac
        fi
      fi ;;
  esac
done

echo "$COUNT scenes in $(($(date +%s) - START)) s${SKIPPED:+, skipped:$SKIPPED}"
if [ -n "$FAILED" ]; then
  echo "failed:$FAILED" >&2
  exit 1
fi
