#!/bin/sh
# paw.sh <mode> <view> <label> <secs>: paw playing the demo song
# (examples/demo-song.lua) in a loop with --audio null, and the CPU of each
# of its processes and of its display server over <secs> seconds.
#
# Modes:
#   tui-pty    paw in a pty (script), 187x56, no terminal emulator
#   tui-xterm  paw in xterm (DejaVu Sans Mono 10, 187x56) on a private Xvfb
#   tui-wez    paw in wezterm (GPU) on a private headless weston
#   gui-sw     paw-gui --renderer software (llvmpipe, LP_NUM_THREADS=4) on
#              a private Xvfb
#   gui-gpu    paw-gui on a private headless weston on the graphics card
# Views: arrange, mixer, roll (the keys' clip alone), devices, split (piano
# roll and mixer), session (extensions/launcher), notation
# (extensions/notation).
#
# Environment:
#   BIN      the folder of paw and paw-gui (default: target/release)
#   W, H     the window's size (default 1500x960; window modes only)
#   CORES    the cores to pin to (default 16-23)
#   OUT      where results go (default $BENCH_TMP/daws, BENCH_TMP default
#            /tmp/paw-bench)
#   WESTON   the weston binary (default: weston from PATH)
#   SETTLE   seconds before the measurement (default 8); STILL=1 does not
#            play; EXTRA is Lua run after the setup
#
# paw runs with --clean --no-plugins, its XDG_* folders and HOME in a
# scratch folder, no session bus, and a display of its own.
# Writes $OUT/results/<label>/cpu.txt: one line "name pct rss_mb" for each
# process (paw or kernel, gui, xterm, wezterm, server), "bytes b0 b1 t0 t1"
# (what the terminal received) and "load <load1>"; the terminal's output
# in ts; the window's PAW_GUI_STATS lines in stderr.
C=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$C/../.." && pwd)
BIN=${BIN:-$REPO/target/release}
mode=$1 view=$2 label=$3 secs=$4
[ -n "$secs" ] || { echo "usage: paw.sh <mode> <view> <label> <secs>" >&2; exit 2; }
W=${W:-1500} H=${H:-960}
CORES=${CORES:-16-23}
OUT=${OUT:-${BENCH_TMP:-/tmp/paw-bench}/daws}
out=$OUT/results/$label
rm -rf "$out"; mkdir -p "$out"
X=$OUT/xdg/$label
rm -rf "$X"; mkdir -p "$X/state" "$X/cache" "$X/config" "$X/data"
# The runtime folder holds sockets, whose paths must stay short.
R=$(mktemp -d /tmp/paw-run.XXXXXX); chmod 700 "$R"
export XDG_STATE_HOME=$X/state XDG_CACHE_HOME=$X/cache XDG_CONFIG_HOME=$X/config XDG_DATA_HOME=$X/data XDG_RUNTIME_DIR=$R
unset SSH_AUTH_SOCK; export DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/bus HOME=$X
unset WAYLAND_DISPLAY DISPLAY XAUTHORITY

song="dofile('$REPO/examples/demo-song.lua')"
case $mode in gui-*) song="$song; paw.frontend.layout_set({width=$W,height=$H})" ;; esac
play="$song; paw.api.transport_set('loop_enabled', true)"
[ -z "$STILL" ] && play="$play; paw.api.transport_play()"
keys="local keys; for _, p in ipairs(paw.parts()) do if p.name == 'Keys' then keys = p end end"
roll="$keys; paw.commands.exec('e roll://' .. keys:clips()[1].id)"
case $view in
  arrange) setup="$play" ;;
  mixer) setup="$play; paw.commands.exec('view.toggle mixer')" ;;
  devices) setup="$play; paw.commands.exec('view.toggle devices')" ;;
  roll) setup="$play; $roll; paw.commands.exec('only')" ;;
  split) setup="$play; $roll; paw.commands.exec('view.toggle mixer')" ;;
  session) setup="$play; paw.ext.load('$REPO/extensions/launcher'); paw.commands.exec('view.toggle session')" ;;
  notation) setup="$play; paw.ext.load('$REPO/extensions/notation'); $roll; paw.commands.exec('only'); paw.commands.exec('notation'); paw.commands.exec('only')" ;;
  *) echo "unknown view $view" >&2; exit 2 ;;
esac
[ -n "$EXTRA" ] && setup="$setup; $EXTRA"
args="--clean --no-plugins --audio null"

# The paw process writes its pid; the terminal's output is kept in ts.
cat > "$out/paw.sh" <<EOF
#!/bin/sh
echo \$\$ > $out/paw.pid
exec $BIN/paw $args -e "$setup"
EOF
cat > "$out/inner.sh" <<EOF
#!/bin/sh
exec script -q -f -c "sh $out/paw.sh" $out/ts
EOF
chmod +x "$out/paw.sh" "$out/inner.sh"

srv=""
case $mode in
  gui-sw|tui-xterm)
    disp=:$((180 + $$ % 10))
    Xvfb $disp -screen 0 "${W}x${H}x24" >/dev/null 2>&1 &
    srv=$!; export DISPLAY=$disp ;;
  gui-gpu|tui-wez)
    export WAYLAND_DISPLAY=wl-paw$$
    ${WESTON:-weston} --backend=headless --renderer=gl --width="$W" --height="$H" --socket=$WAYLAND_DISPLAY --idle-time=0 > "$out/weston.log" 2>&1 &
    srv=$! ;;
  tui-pty) ;;
  *) echo "unknown mode $mode" >&2; exit 2 ;;
esac
sleep 1
[ -n "$srv" ] && taskset -cp "$CORES" $srv >/dev/null

export TERM=xterm-256color PAW_GUI_STATS=1
case $mode in
  gui-sw) LP_NUM_THREADS=${LPT:-4} setsid taskset -c "$CORES" $BIN/paw-gui --renderer software $args -e "$setup" > "$out/stdout" 2> "$out/stderr" &
    app=$! ;;
  gui-gpu) setsid taskset -c "$CORES" $BIN/paw-gui $args -e "$setup" > "$out/stdout" 2> "$out/stderr" &
    app=$! ;;
  tui-pty) setsid taskset -c "$CORES" script -q -f -c "stty cols 187 rows 56; sh $out/paw.sh" "$out/ts" < /dev/null > /dev/null 2> "$out/stderr" &
    app=$! ;;
  tui-xterm) setsid taskset -c "$CORES" xterm -fa 'DejaVu Sans Mono' -fs 10 -geometry 187x56+0+0 -e sh "$out/inner.sh" > "$out/stdout" 2> "$out/stderr" &
    app=$! ;;
  tui-wez) printf 'return { font_size = 10.0, initial_cols = 187, initial_rows = 56, enable_wayland = true, enable_tab_bar = false, front_end = "WebGpu" }\n' > "$X/wez.lua"
    setsid taskset -c "$CORES" wezterm --config-file "$X/wez.lua" start --always-new-process -- sh "$out/inner.sh" > "$out/stdout" 2> "$out/stderr" &
    app=$! ;;
esac
sleep "${SETTLE:-8}"

# The processes to count: paw (or paw-gui and its kernel), the emulator,
# the display server.
case $mode in
  gui-*) gui=$(pgrep -n -s $app -x paw-gui || echo $app)
    pids="gui:$gui kernel:$(pgrep -n -P $gui -x paw)" ;;
  tui-pty) pids="paw:$(cat "$out/paw.pid")" ;;
  tui-xterm) pids="paw:$(cat "$out/paw.pid") xterm:$app" ;;
  tui-wez) pids="paw:$(cat "$out/paw.pid") wezterm:$(pgrep -n -x wezterm-gui -s $app || echo $app)" ;;
esac
[ -n "$srv" ] && pids="$pids server:$srv"
t() { awk '{print $14+$15}' /proc/$1/stat 2>/dev/null || echo 0; }
for p in $pids; do eval "a_${p%%:*}=\$(t ${p#*:})"; done
b0=$(stat -c %s "$out/ts" 2>/dev/null || echo 0); s0=$(date +%s.%N)
sleep "$secs"
for p in $pids; do eval "b_${p%%:*}=\$(t ${p#*:})"; done
b1=$(stat -c %s "$out/ts" 2>/dev/null || echo 0); s1=$(date +%s.%N)
tick=$(getconf CLK_TCK)
for p in $pids; do
  n=${p%%:*} pid=${p#*:}
  eval "a=\$a_$n b=\$b_$n"
  rss=$(awk '/VmRSS/{print $2/1024}' /proc/$pid/status 2>/dev/null)
  echo "$n $a $b $s0 $s1 $tick ${rss:-0}" | awk '{printf "%s %.1f %.0f\n", $1, ($3-$2)/$6/($5-$4)*100, $7}'
done > "$out/cpu.txt"
echo "bytes $b0 $b1 $s0 $s1" >> "$out/cpu.txt"
echo "load $(cut -d' ' -f1 /proc/loadavg)" >> "$out/cpu.txt"

kill -- -$app 2>/dev/null; sleep 0.5; kill -9 -- -$app 2>/dev/null
[ -n "$srv" ] && kill $srv
sleep 0.5
rm -rf "$R"
echo "== $label: $(tr '\n' ' ' < "$out/cpu.txt") $(grep -h 'stats:' "$out/stderr" 2>/dev/null | tail -1 | sed 's/.*stats: //')"
