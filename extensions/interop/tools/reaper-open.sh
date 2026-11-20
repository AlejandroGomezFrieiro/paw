#!/bin/sh
# reaper-open.sh <project.rpp> <dump.txt> [build.lua]: open a project in the
# real REAPER and write what REAPER read from it (reaper-dump.lua says the
# format). With build.lua, REAPER runs that ReaScript in a new project
# instead, saves the project as <project.rpp>, then writes what it holds.
#
# REAPER runs in a sandbox: bubblewrap with a fresh HOME and configuration
# folder, no network and no access to the home folder, on a private Xvfb,
# with dummy audio. It never reads or writes the configuration of a REAPER
# that the user has. The program is $PAW_REAPER (the `reaper` launcher of
# an installed REAPER). Exit status 77 when it, Xvfb or bwrap is missing.
set -u
rpp=$(realpath -m "$1") dump=$(realpath -m "$2") build=${3:+$(realpath "$3")}
here=$(cd "$(dirname "$0")" && pwd)
bin=${PAW_REAPER:-}
[ -n "$bin" ] && [ -x "$bin" ] || { echo "reaper-open: set PAW_REAPER to the reaper program" >&2; exit 77; }
command -v Xvfb >/dev/null && command -v bwrap >/dev/null || { echo "reaper-open: needs Xvfb and bwrap" >&2; exit 77; }
sb=$(mktemp -d "${TMPDIR:-/tmp}/reaper-open.XXXXXX")
[ -n "${REAPER_KEEP:-}" ] || trap 'rm -rf "$sb"' EXIT
mkdir -p "$sb/home" "$sb/cfg/REAPER/Scripts" "$sb/run"
chmod 700 "$sb/run"
printf '[REAPER]\nlinux_audio_mode=2\nsplashscreen=0\n[verchk]\nlastt=%s\n' "$(date +%s)" > "$sb/cfg/REAPER/reaper.ini"
cp "$here/reaper-dump.lua" "$sb/cfg/REAPER/Scripts/__startup.lua"
rm -f "$dump"
mkdir -p "$(dirname "$dump")"
n=$((300 + $$ % 200))
while [ -e "/tmp/.X11-unix/X$n" ]; do n=$((n + 1)); done
Xvfb ":$n" -screen 0 1280x800x24 -nolisten tcp >/dev/null 2>&1 &
xs=$!
i=0; while [ ! -e "/tmp/.X11-unix/X$n" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
dir=$(dirname "$rpp")
outdir=$(dirname "$dump")
mode=--ro-bind extra=""
if [ -n "$build" ]; then mode=--bind extra="--ro-bind $build $build --setenv RPP_BUILD $build"; fi
setsid bwrap --ro-bind /nix /nix --ro-bind /etc /etc --ro-bind-try /bin /bin --ro-bind-try /usr /usr \
  --ro-bind-try /run/current-system /run/current-system --proc /proc --dev /dev --tmpfs /tmp --tmpfs /home \
  --bind "$sb" "$sb" $mode "$dir" "$dir" --bind "$outdir" "$outdir" $extra \
  --ro-bind "/tmp/.X11-unix/X$n" "/tmp/.X11-unix/X$n" \
  --setenv HOME "$sb/home" --setenv XDG_CONFIG_HOME "$sb/cfg" --setenv XDG_RUNTIME_DIR "$sb/run" \
  --setenv DISPLAY ":$n" --setenv RPP_FILE "$rpp" --setenv RPP_DUMP "$dump" \
  --unsetenv WAYLAND_DISPLAY --unsetenv XAUTHORITY --unsetenv SSH_AUTH_SOCK --unsetenv DBUS_SESSION_BUS_ADDRESS \
  --unshare-ipc --unshare-net --unshare-uts --die-with-parent \
  "$bin" -cfgfile "$sb/cfg/REAPER/reaper.ini" -nosplash -newinst > "$sb/stdout" 2>&1 &
app=$!
i=0
while [ ! -e "$dump" ] && [ $i -lt "${REAPER_WAIT:-600}" ]; do sleep 0.1; i=$((i + 1)); done
# The script asked REAPER to quit; give it a moment, then make sure.
j=0; while kill -0 $app 2>/dev/null && [ $j -lt 30 ]; do sleep 0.1; j=$((j + 1)); done
kill -- -$app 2>/dev/null; sleep 0.2; kill -9 -- -$app 2>/dev/null
kill $xs 2>/dev/null
[ -e "$dump" ] || { echo "reaper-open: REAPER wrote nothing" >&2; cat "$sb/stdout" >&2; exit 1; }
