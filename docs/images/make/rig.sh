#!/bin/sh
# The recording rig for the GIFs in docs/images. A scene script sources it
# and calls its functions. The functions do not drive paw directly: they
# write a tape for VHS (github.com/charmbracelet/vhs), which runs paw in a
# terminal of its own (xterm.js in a headless browser) and records it. So
# the rig needs no display. make.sh runs each scene, and then gif.py adds
# the caption and the key bar.
#
#   rig_start          start the tape: the terminal's size, font and colors
#   term_start         paw in that terminal. With CONFIG, that configuration
#                      folder instead of --clean. With EDIT, Neovim on that
#                      file in a pane above paw (tmux). With PAW_HOME, that
#                      folder as the program's home (`~`, never yours: a
#                      scratch folder when unset). With PLUGINS, the plugins
#                      on CLAP_PATH and the other paths (set them all, so that
#                      no plugin of yours is scanned).
#   rec_start name     show and record from here, into $WORK/name.mp4
#   cap "text"         the caption from now on
#   rec_stop           stop the recording, and run the tape
#   shot name.png      a screenshot, into $WORK
#   still name.png     a screenshot that make.sh copies next to the GIFs
#   key, keys, typ     keys and text, as VHS sends them. While the rig
#                      records, they also go to the key bar (gif.py).
#   pause seconds      wait
#   pane up|down       move the keyboard to the pane above or below (EDIT)
#   ctl '<lua>'        run Lua in paw at this time of the tape. It returns
#                      nothing: the tape runs after the scene script ends.
#
# The rig keeps a time line of the tape (TT, in seconds). VHS sends each key
# and does each pause in real time. Thus the captions and the keys of the
# bar get their times from the tape, and ctl runs at its time beside VHS.
#
# A scene fails with the reason, and make.sh stops with a status that is not
# 0, when a key has no VHS command, when VHS fails (paw did not start, or a
# Wait timed out), when paw gives an error message, or when the recording
# is missing.
#
# With CHECK=1 (make.sh --check), the tape has no output, a pause is 0.3 s
# at most and text is typed fast. The scene fails on the same errors.
HERE=${MAKE:?run the scenes through make.sh}
SCENE=${SCENE:?run the scenes through make.sh}
ROOT=$(cd "$HERE/../../.." && pwd)
WORK=${WORK:-$ROOT/target/test-scratch/media}
D=$WORK/home
rm -rf "$D"; mkdir -p "$D/home" "$WORK"
# Sockets need a short path: the folder of the checkout can be too deep.
RUN=$(mktemp -d "${TMPDIR:-/tmp}/paw-rig.XXXXXX") || exit 1
export XDG_CACHE_HOME=$D XDG_STATE_HOME=$D XDG_DATA_HOME=$D XDG_RUNTIME_DIR=$RUN XDG_CONFIG_HOME=$D/config
export DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/bus
unset WAYLAND_DISPLAY DISPLAY XAUTHORITY SSH_AUTH_SOCK TMUX
# The program: PAW_BIN when it is set (a folder with paw in it), else the
# release build of this checkout.
BIN=${PAW_BIN:-$ROOT/target/release}
SOCK=$RUN/k.sock
TERM_SIZE=1120x700
# The song every scene starts from; the scenes load extensions on top.
DEMO="dofile('examples/demo-song.lua')"
# The scenes of the window (gui-*.sh) give this size to rig_start, which
# refuses it: paw-gui is paused, and VHS records a terminal only.
GUI_SIZE=1280x800
# The terminal starts with the eight bars across: 11 cells a bar.
TUI_DEMO="$DEMO paw.opt.zoom = 2.75"
TUI_NOTATION="$TUI_DEMO paw.ext.load('extensions/notation') require('notation').space = 14"

TAPE=$WORK/$SCENE.tape
ERRORS=$WORK/$SCENE.errors
SCHEDULE=$WORK/$SCENE.ctl
: > "$ERRORS"
: > "$SCHEDULE"
# TT: the time of the tape in seconds, from the first screen of paw.
# TWALL: the clock when TT changed last (see ctl).
TT=0
TWALL=0

now() { date +%s.%N; }
calc() { awk "BEGIN { printf \"%.3f\", $1 }"; }
rig_fail() { echo "$SCENE: $1" >&2; exit 1; }
tape() { printf '%s\n' "$*" >> "$TAPE"; }
advance() { TT=$(calc "$TT + $1"); TWALL=$(now); }
# A time in seconds as VHS reads it.
ms() { awk "BEGIN { printf \"%dms\", $1 * 1000 + 0.5 }"; }
# A text in the quotes of a VHS string: a quote character that the text
# does not contain.
quoted() {
  case $1 in
    *'"'*) ;;
    *) printf '"%s"' "$1"; return ;;
  esac
  case $1 in
    *"'"*) ;;
    *) printf "'%s'" "$1"; return ;;
  esac
  case $1 in
    *'`'*) rig_fail "VHS cannot type a text that has the three quote characters: $1" ;;
  esac
  printf '`%s`' "$1"
}

rig_start() {
  [ -z "$1" ] || [ "$1" = "$TERM_SIZE" ] || rig_fail "the rig records the terminal only: the window scenes need paw-gui, which is paused"
  SIZE=$TERM_SIZE
  rm -f "$TAPE"
  tape "Set Shell bash"
  tape "Set Width ${SIZE%x*}"
  tape "Set Height ${SIZE#*x}"
  tape "Set FontFamily \"FiraCode Nerd Font\""
  tape "Set FontSize 16"
  tape "Set Theme \"Catppuccin Mocha\""
  tape "Set Padding 0"
  tape "Set Margin 0"
  tape "Set Framerate 20"
  tape "Set CursorBlink false"
  tape "Set TypingSpeed 60ms"
  tape "Hide"
  trap 'rig_stop' EXIT
  trap 'exit 130' INT TERM
}
# At the end of the scene script: run the tape if rec_stop did not, then
# stop what is left of paw and of the ctl runner, and remove $RUN.
rig_stop() {
  status=$?
  trap - EXIT
  if [ "$status" = 0 ] && [ -z "$RAN" ]; then
    (run_tape)
    status=$?
  fi
  stop_schedule
  [ -f "$RUN/paw.pid" ] && kill "$(cat "$RUN/paw.pid")" 2>/dev/null
  # The browser of VHS can outlive VHS for a few seconds. Each process of
  # the tape has $RUN in its arguments (VHS gets $RUN as its TMPDIR).
  pkill -f "$RUN/" 2>/dev/null
  i=0
  while pgrep -f "$RUN/" >/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  pkill -9 -f "$RUN/" 2>/dev/null
  rm -rf "$RUN"
  exit "$status"
}

term_start() {
  cd "$ROOT" || exit 1
  [ -x "$BIN/paw" ] || rig_fail "no paw program in $BIN (set PAW_BIN)"
  home=${PAW_HOME:-$D/home}
  # The Lua that runs first. Each error message of paw goes to $ERRORS, so
  # that the scene fails. paw stops when ~ is not the folder that the rig
  # gave, because a scene can change the files in ~.
  cat > "$RUN/setup.lua" <<LUA
local messages = require('paw.messages')
local function keep(message)
  if message.level == 'error' then
    local file = io.open([[$ERRORS]], 'a')
    file:write(message.text, '\n')
    file:close()
  end
end
for _, message in ipairs(messages.list) do keep(message) end
local show = messages.show
messages.show = function(message) keep(message) if show then show(message) end end
if os.getenv('HOME') ~= [[$home]] then
  io.stderr:write('the rig: ~ is not ' .. [[$home]] .. '\n')
  os.exit(3)
end
${SETUP:-$DEMO}
LUA
  {
    echo "cd '$ROOT' || exit 1"
    echo "echo \$\$ > '$RUN/paw.pid'"
    echo "export HOME='$home' COLORTERM=truecolor"
    printf "exec '%s' %s %s --audio null --listen '%s' -e \"dofile('%s')\"\n" "$BIN/paw" \
      "${CONFIG:+--config '$CONFIG'}$([ -z "$CONFIG" ] && echo --clean)" \
      "$([ -z "$PLUGINS" ] && echo --no-plugins)" "$SOCK" "$RUN/setup.lua"
  } > "$RUN/paw.sh"
  start=$RUN/paw.sh
  if [ -n "$EDIT" ]; then
    # Neovim above, paw below, in tmux, and the keyboard in Neovim. The
    # status line of Neovim names the file as it is in a home folder, not by
    # the scratch folder of the scene.
    cat > "$RUN/tmux.conf" <<'CONF'
set -g status off
set -sg escape-time 0
set -g default-terminal xterm-256color
set -as terminal-features ',xterm-256color:RGB'
set -g pane-border-style fg=#313244
set -g pane-active-border-style fg=#313244
CONF
    cat > "$RUN/nvim.sh" <<NVIM
exec nvim --clean -c 'set nu' -c 'cd %:h' -c 'set statusline=~/.config/paw/init.lua\\ %m%=%l,%c' '$EDIT'
NVIM
    echo "exec tmux -S '$RUN/tmux.sock' -f '$RUN/tmux.conf' new-session 'sh $RUN/nvim.sh' \\; split-window -v -l 70% 'sh $RUN/paw.sh' \\; select-pane -t 0" > "$RUN/edit.sh"
    start=$RUN/edit.sh
  fi
  tape "Type@1ms $(quoted "clear; exec sh '$start'")"
  tape "Enter"
  # The first screen: the status line of paw gives the tempo.
  tape "Wait+Screen@30s /[0-9]+ bpm/"
  tape "Sleep 500ms"
  advance 0.5
}

# The times of the captions and of the key bar count from rec_start.
since() { calc "$TT - $T0"; }
rec_start() {
  NAME=$1
  [ "$NAME" = "$SCENE" ] || rig_fail "rec_start $NAME: a scene records the GIF of its own name"
  : > "$WORK/$NAME.caps"
  : > "$WORK/$NAME.keys"
  rm -f "$WORK/$NAME.mp4"
  [ -n "$CHECK" ] || tape "Output $NAME.mp4"
  tape "Show"
  T0=$TT
  REC=1
}
rec_stop() {
  cap ""
  tape "Hide"
  REC=
  run_tape || exit 1
}
cap() { [ -n "$REC" ] && printf '%s\t%s\n' "$(since)" "$1" >> "$WORK/$NAME.caps"; }
# What the key bar shows: a key by its name, typed text as it is.
cast() { [ -n "$REC" ] && printf '%s\t%s\t%s\n' "$(since)" "$1" "$2" >> "$WORK/$NAME.keys"; }
shot() { [ -n "$CHECK" ] || tape "Screenshot $1"; }
still() { shot "$1"; echo "$1" >> "$WORK/stills.list"; }

# The VHS command for a key, by its X name (gif.py shows these names as Vim
# writes them).
vhs_key() {
  case $1 in
    ?) printf 'Type %s' "$(quoted "$1")" ;;
    Return) echo Enter ;;
    space) echo Space ;;
    BackSpace) echo Backspace ;;
    Escape | Tab | Up | Down | Left | Right | Home | End | Delete | Insert) echo "$1" ;;
    Page_Up | Prior) echo PageUp ;;
    Page_Down | Next) echo PageDown ;;
    ctrl+?) echo "Ctrl+${1#ctrl+}" ;;
    alt+?) echo "Alt+${1#alt+}" ;;
    shift+Tab) echo "Shift+Tab" ;;
    *)
      char=$(symbol "$1")
      [ -n "$char" ] || return 1
      printf 'Type %s' "$(quoted "$char")" ;;
  esac
}
# The character of the X name of a symbol.
symbol() {
  case $1 in
    exclam) echo '!' ;; quotedbl) echo '"' ;; numbersign) echo '#' ;; dollar) echo '$' ;;
    percent) echo '%' ;; ampersand) echo '&' ;; apostrophe) echo "'" ;; parenleft) echo '(' ;;
    parenright) echo ')' ;; asterisk) echo '*' ;; plus) echo '+' ;; comma) echo ',' ;;
    minus) echo '-' ;; period) echo '.' ;; slash) echo '/' ;; colon) echo ':' ;;
    semicolon) echo ';' ;; less) echo '<' ;; equal) echo '=' ;; greater) echo '>' ;;
    question) echo '?' ;; at) echo '@' ;; bracketleft) echo '[' ;; backslash) echo '\' ;;
    bracketright) echo ']' ;; asciicircum) echo '^' ;; underscore) echo '_' ;; grave) echo '`' ;;
    braceleft) echo '{' ;; bar) echo '|' ;; braceright) echo '}' ;; asciitilde) echo '~' ;;
  esac
}
key() {
  for k in "$@"; do
    command=$(vhs_key "$k") || rig_fail "VHS cannot send the key $k"
    cast key "$k"
    tape "$command"
    advance 0.06
  done
}
typ() {
  delay=${TYPE_DELAY:-110}
  [ -n "$CHECK" ] && [ "$delay" -gt 20 ] && delay=20
  cast "type $delay" "$1"
  tape "Type@${delay}ms $(quoted "$1")"
  advance "$(calc "${#1} * $delay / 1000")"
}
pause() {
  seconds=$1
  [ -n "$CHECK" ] && seconds=$(calc "$seconds < 0.3 ? $seconds : 0.3")
  tape "Sleep $(ms "$seconds")"
  advance "$seconds"
}
# Keys one at a time with a pause after each: keys 0.4 j j w.
keys() { p=$1; shift; for k in "$@"; do key "$k"; pause "$p"; done; }
# tmux moves the keyboard between the panes: its prefix key, then an arrow.
pane() {
  case $1 in
    up) tape "Ctrl+B"; tape "Up" ;;
    down) tape "Ctrl+B"; tape "Down" ;;
    *) rig_fail "pane $1: the direction is up or down" ;;
  esac
  advance 0.12
}
# A ctl call runs beside VHS, at the time of the tape when the scene made
# it. A scene can make ctl calls in a process in the background that sleeps
# (tui-takes does). That process keeps the TT of the time when it started,
# so the clock time since TWALL is added to TT.
ctl() {
  if [ "$TWALL" = 0 ]; then at=$TT; else at=$(calc "$TT + $(now) - $TWALL"); fi
  printf '%s\t%s\n' "$at" "$(printf '%s' "$1" | tr '\n\t' '  ')" >> "$SCHEDULE"
}
# Do the ctl calls at their times. The time starts when paw answers, which
# is about when its first screen comes and TT starts.
run_schedule() {
  i=0
  until "$BIN/paw" ctl --socket "$SOCK" eval "return 1" >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -gt 300 ] && { echo "ctl: paw does not answer on $SOCK" >> "$ERRORS"; return; }
    sleep 0.1
  done
  start=$(now)
  tab=$(printf '\t')
  sort -n "$SCHEDULE" > "$RUN/schedule"
  while IFS=$tab read -r at lua; do
    wait=$(calc "$at - ($(now) - $start)")
    case $wait in -*) ;; *) sleep "$wait" ;; esac
    "$BIN/paw" ctl --socket "$SOCK" eval "$lua" >/dev/null 2>&1 || echo "ctl failed: $lua" >> "$ERRORS"
  done < "$RUN/schedule"
}
# Stop the ctl runner and the sleep that it waits on.
stop_schedule() {
  [ -n "$RUNNER" ] || return 0
  pkill -P "$RUNNER" 2>/dev/null
  kill "$RUNNER" 2>/dev/null
  RUNNER=
}
# Run the tape one time: VHS, with the ctl calls beside it. The browser of
# VHS gets a home of its own in $RUN, not the home of paw.
run_tape() {
  [ -n "$RAN" ] && return 0
  RAN=1
  # VHS fails on a tape that shows no frame. A scene that takes stills only
  # has no Output, so the frames that it shows go nowhere.
  [ -n "$NAME" ] || tape "Show"
  tape "Sleep 300ms"
  if [ -s "$SCHEDULE" ]; then
    # No message from the shell when stop_schedule stops a sleep.
    run_schedule 2>/dev/null &
    RUNNER=$!
  fi
  mkdir -p "$RUN/vhs/tmp"
  (cd "$WORK" && HOME=$RUN/vhs TMPDIR=$RUN/vhs/tmp VHS_NO_SANDBOX=true vhs -q "$SCENE.tape")
  vhs_status=$?
  stop_schedule
  [ "$vhs_status" = 0 ] || rig_fail "VHS failed (status $vhs_status): its message is above"
  if [ -s "$ERRORS" ]; then
    echo "$SCENE: paw gave these errors:" >&2
    sed 's/^/  /' "$ERRORS" >&2
    exit 1
  fi
  if [ -z "$CHECK" ] && [ -n "$NAME" ]; then
    [ -s "$WORK/$NAME.mp4" ] || rig_fail "VHS wrote no recording $WORK/$NAME.mp4"
  fi
  return 0
}
