#!/bin/sh
# Make the pictures again, from the release build:
#
#   cargo build --release && docs/images/make/make.sh [set or scene...]
#
# PAW_BIN=<folder> takes paw from that folder instead of target/release.
# The skill in .claude/skills/paw-gifs gives the rules for a scene.
#
# With no argument, the core's pictures in docs/images (the README's). An
# extension's name makes that extension's, from the scenes in
# extensions/<name>/images/make into extensions/<name>/images; `all` makes
# the core's and every extension's. A scene's name (tui-arrange) makes that
# one alone.
#
# Each scene (tui-*.sh, gui-*.sh, stills.sh) drives the real program on a
# private X display (RIG_DISPLAY, 177 unless set) with xdotool, as
# tests/tools/gui.sh does, and records the screen; gif.py makes the GIF,
# with the caption and the keys typed in a bar under it. All of them start
# from examples/demo-song.lua. A cast scene (cast-*.sh) records paw in a
# pseudo-terminal instead, with cast.py, into an asciicast that the website
# plays (tools/website/paw-cast.js). Nothing touches your display, sound or MIDI
# devices. The positions the pointer goes to are for the demo song at the
# sizes rig.sh sets; a change to the window's layout means changing them.
# NOCOPY=1 leaves the results in target/test-scratch/media.
HERE=$(cd "$(dirname "$0")" && pwd)
if ! command -v wezterm >/dev/null || ! command -v gifsicle >/dev/null || [ -z "$CURSORS" ]; then
  CURSORS=$(nix build nixpkgs#vanilla-dmz --no-link --print-out-paths)/share/icons
  export CURSORS
  exec nix shell nixpkgs#wezterm nixpkgs#gifsicle nixpkgs#bc nixpkgs#xdotool nixpkgs#openbox \
    nixpkgs#imagemagick nixpkgs#ffmpeg-full nixpkgs#python3 nixpkgs#neovim -c "$0" "$@"
fi
ROOT=$(cd "$HERE/../../.." && pwd)
WORK=${WORK:-$ROOT/target/test-scratch/media}
MAKE=$HERE
export WORK MAKE
mkdir -p "$WORK"

# make_set dir out: every scene in dir, the GIFs and stills into out.
make_set() {
  for script in "$1"/tui-*.sh "$1"/gui-*.sh "$1"/cast-*.sh "$1"/stills.sh; do
    [ -f "$script" ] && scene "$script" "$2"
  done
}
scene() {
  name=$(basename "$1" .sh)
  echo "$name"
  rm -f "$WORK/$name.mkv" "$WORK/$name.cast"
  : > "$WORK/stills.list"
  sh "$1" || exit 1
  if [ -f "$WORK/$name.mkv" ]; then
    python3 "$HERE/gif.py" "$name" || exit 1
    [ -z "$NOCOPY" ] && cp "$WORK/$name.gif" "$2/$name.gif"
  fi
  if [ -f "$WORK/$name.cast" ] && [ -z "$NOCOPY" ]; then cp "$WORK/$name.cast" "$2/$name.cast"; fi
  # The stills the scene took on the way (rig.sh's `still`).
  if [ -z "$NOCOPY" ]; then
    while read -r still; do cp "$WORK/$still" "$2/$still"; done < "$WORK/stills.list"
  fi
}

[ $# -eq 0 ] && set -- core
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
        [ -z "$found" ] && { echo "no set or scene $arg"; exit 1; }
        scene "$found" "$(dirname "$found")/.."
      fi ;;
  esac
done
