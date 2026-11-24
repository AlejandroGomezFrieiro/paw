#!/bin/sh
# The recording rig for the pictures in docs/images: a private X display
# (never yours) with a window manager that shows one undecorated, maximized
# window. Sourced by the scene scripts; run them through make.sh.
#
#   rig_start [WxH]    start Xvfb and openbox: the terminal's size, or the window's
#   gui_start          a kernel with the demo song, and the window on it
#   term_start         the terminal UI in WezTerm (see wezterm.lua); with
#                      CONFIG, that configuration directory instead of
#                      --clean, with EDIT, Neovim on that file in a pane
#                      above it, with PAW_HOME that as the program's home
#                      (`~`; never yours, a scratch folder when unset), and
#                      with PLUGINS the plugins on CLAP_PATH and the rest
#                      scanned (set the paths, so that none of yours are)
#   rec_start name     record the screen into $WORK/name.mkv
#   cap "text"         the caption from now on
#   rec_stop           stop recording
#   shot name.png      a screenshot, into $WORK
#   still name.png     a still for the set: a screenshot that make.sh copies
#   key, typ           keys, by xdotool; while recording they are written down
#                      for the key-cast in the GIF's corner (gif.py)
#   glide, drag, stroke, rclick: the pointer
#   ctl '<lua>'        run Lua in the kernel
#
# Every terminal scene is the same terminal (TERM_SIZE, wezterm.lua's font
# and colours) and every window scene the same window (GUI_SIZE), so that the
# pictures read as one set.
HERE=${MAKE:?run the scenes through make.sh}
ROOT=$(cd "$HERE/../../.." && pwd)
WORK=${WORK:-$ROOT/target/test-scratch/media}
D=$WORK/home
rm -rf "$D"; mkdir -p "$D/home" "$WORK"
export XDG_CACHE_HOME=$D XDG_STATE_HOME=$D XDG_DATA_HOME=$D XDG_RUNTIME_DIR=$D XDG_CONFIG_HOME=$D/config
export DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/bus
unset WAYLAND_DISPLAY XAUTHORITY
export DISPLAY=:${RIG_DISPLAY:-177}
[ -n "$CURSORS" ] && export XCURSOR_PATH=$CURSORS XCURSOR_THEME=Vanilla-DMZ XCURSOR_SIZE=24
# The program: PAW_BIN when it is set (a folder with paw in it), else the
# release build of this checkout.
BIN=${PAW_BIN:-$ROOT/target/release}
SOCK=$D/k.sock
TERM_SIZE=1120x700
GUI_SIZE=1280x800
# The song every scene starts from; the scenes load extensions on top.
DEMO="dofile('examples/demo-song.lua')"
NOTATION="$DEMO paw.ext.load('extensions/notation')"
# The terminal starts with the eight bars across: 11 cells a bar.
TUI_DEMO="$DEMO paw.opt.zoom = 2.75"
TUI_NOTATION="$TUI_DEMO paw.ext.load('extensions/notation') require('notation').space = 14"
# The window starts with the eight bars across, beside the device panel:
# x = 241 + 22 a beat; the parts' rows 90 high.
GUI_DEMO="$DEMO paw.frontend.layout_set({ zoom = 22, row_height = 90 })"

rig_start() {
  SIZE=${1:-$TERM_SIZE}
  Xvfb "$DISPLAY" -screen 0 "${SIZE}x24" >/dev/null 2>&1 &
  XVFB=$!
  sleep 1
  mkdir -p "$D/config/openbox"
  cat > "$D/config/openbox/rc.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <focus><focusNew>yes</focusNew><followMouse>no</followMouse></focus>
  <applications>
    <application class="*" type="normal"><decor>no</decor><maximized>yes</maximized><focus>yes</focus></application>
  </applications>
</openbox_config>
XML
  openbox --config-file "$D/config/openbox/rc.xml" >/dev/null 2>&1 &
  WM=$!
  sleep 0.7
  xsetroot -solid "#11111b" -cursor_name left_ptr 2>/dev/null
  trap 'rig_stop' EXIT INT TERM
}
rig_stop() {
  [ -n "$REC" ] && rec_stop
  [ -n "$APP" ] && kill $APP 2>/dev/null
  [ -n "$KERNEL" ] && kill $KERNEL 2>/dev/null
  sleep 0.4
  kill $WM $XVFB 2>/dev/null
}
gui_start() {
  cd "$ROOT" || exit 1
  POINTER=1
  "$BIN/paw" --headless --clean --no-plugins --audio null --listen "$SOCK" \
    -e "${SETUP:-$GUI_DEMO}" 2>"$D/kernel.err" &
  KERNEL=$!
  sleep 2
  "$BIN/paw-gui" --socket "$SOCK" >"$D/gui.out" 2>&1 &
  APP=$!
  sleep 3.5
  xdotool mousemove 640 600
}
term_start() {
  cd "$ROOT" || exit 1
  POINTER=0
  # Nothing of the session this is run from: not its agent, not its mux.
  unset SSH_AUTH_SOCK WEZTERM_UNIX_SOCKET WEZTERM_PANE
  wezterm --config-file "$HERE/wezterm.lua" start --always-new-process --cwd "$ROOT" -- \
    env HOME="${PAW_HOME:-$D/home}" "$BIN/paw" ${CONFIG:+--config "$CONFIG"} $([ -z "$CONFIG" ] && echo --clean) $([ -z "$PLUGINS" ] && echo --no-plugins) \
    --audio null --listen "$SOCK" \
    -e "${SETUP:-$DEMO}" >"$D/term.out" 2>&1 &
  APP=$!
  sleep 6
  xdotool mousemove 4000 4000
}
app_stop() { kill $APP $KERNEL 2>/dev/null; APP=; KERNEL=; sleep 1; rm -f "$SOCK"; }

now() { date +%s.%N; }
since() { echo "$(now) - $1" | bc -l; }
rec_start() {
  NAME=$1
  : > "$WORK/$NAME.caps"
  : > "$WORK/$NAME.keys"
  START=$(now)
  ffmpeg -loglevel error -y -f x11grab -draw_mouse $POINTER -framerate 20 -video_size "$SIZE" -i "$DISPLAY" \
    -c:v libx264rgb -crf 0 -preset ultrafast "$WORK/$NAME.mkv" &
  REC=$!
  sleep 1
  T0=$(now)
  # Where the scene starts in the recording: ffmpeg takes a moment to start.
  echo "$(since "$START") - 0.15" | bc -l > "$WORK/$NAME.lead"
}
rec_stop() { cap ""; kill -INT $REC 2>/dev/null; wait $REC 2>/dev/null; REC=; }
cap() { printf '%s\t%s\n' "$(since "$T0")" "$1" >> "$WORK/$NAME.caps"; }
# What the key-cast shows: a key by its xdotool name, typed text as it is.
cast() { [ -n "$REC" ] && printf '%s\t%s\t%s\n' "$(since "$T0")" "$1" "$2" >> "$WORK/$NAME.keys"; }
shot() { import -window root "$WORK/$1"; }
still() { shot "$1"; echo "$1" >> "$WORK/stills.list"; }
ctl() { "$BIN/paw" ctl --socket "$SOCK" eval "$1"; }
key() { for k in "$@"; do cast key "$k"; xdotool key "$k"; sleep 0.06; done; }
typ() { cast "type ${TYPE_DELAY:-110}" "$1"; xdotool type --delay "${TYPE_DELAY:-110}" "$1"; }
pause() { sleep "$1"; }
# Keys one at a time with a pause after each: keys 0.4 j j w.
keys() { p=$1; shift; for k in "$@"; do key "$k"; sleep "$p"; done; }
# Move the pointer there in steps, so that the recording shows it travel.
glide() {
  eval "$(xdotool getmouselocation --shell)"
  n=${3:-12}; i=1
  while [ $i -le $n ]; do
    xdotool mousemove $(( X + ($1 - X) * i / n )) $(( Y + ($2 - Y) * i / n ))
    sleep 0.018; i=$((i + 1))
  done
}
# drag x1 y1 x2 y2 [button]
drag() {
  glide $1 $2; sleep 0.1; xdotool mousedown ${5:-1}; sleep 0.1
  glide $3 $4 12; sleep 0.15; xdotool mouseup ${5:-1}; sleep 0.2
}
# A right click held long enough to be one (menus open on release).
rclick() { glide $1 $2; pause 0.3; xdotool mousedown 3; sleep 0.12; xdotool mouseup 3; pause 0.6; }
# A stroke through several points with the button held: stroke x y x y ...
stroke() {
  glide $1 $2; pause 0.15; xdotool mousedown 1; pause 0.12; shift 2
  while [ $# -ge 2 ]; do glide $1 $2 14; shift 2; done
  pause 0.15; xdotool mouseup 1; pause 0.3
}
