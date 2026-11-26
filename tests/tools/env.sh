# Sourced by the scripts beside it, and by bench/. Everything a test run
# writes goes under the checkout's own `target/test-scratch` (or
# $PAW_TEST_SCRATCH), never into the home directory, and the window is only
# ever shown on a private display. A script outside tests/tools sets ROOT to
# the checkout first.
ROOT=${ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
SCRATCH=${PAW_TEST_SCRATCH:-$ROOT/target/test-scratch}
mkdir -p "$SCRATCH/xdg" "$SCRATCH/shots"
export XDG_CACHE_HOME=$SCRATCH/xdg/cache XDG_STATE_HOME=$SCRATCH/xdg/state
export XDG_DATA_HOME=$SCRATCH/xdg/data XDG_CONFIG_HOME=$SCRATCH/xdg/config
# A test never finds the plugins of the machine: the plugin folders are an
# empty folder, and the home is a scratch one, so neither ~/.clap nor ~/.vst3
# is searched. A bundle in ~/.vst3 can be a yabridge bridge, which starts wine
# in the owner's prefix. `suite.sh plugins` gives its own known plugins.
# WINEPREFIX is a scratch one in case a bridge loads anyway.
# Cargo keeps its own home (the registry), which the stub build needs.
mkdir -p "$SCRATCH/home" "$SCRATCH/no-plugins"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export HOME=$SCRATCH/home
export CLAP_PATH=$SCRATCH/no-plugins VST3_PATH=$SCRATCH/no-plugins LV2_PATH=$SCRATCH/no-plugins
export LADSPA_PATH=$SCRATCH/no-plugins DSSI_PATH=$SCRATCH/no-plugins VST3_PRESET_PATH=$SCRATCH/no-plugins
export WINEPREFIX=$SCRATCH/wine
# The user name is not the owner's, so that no test finds the owner's
# /etc/profiles/per-user folder. git reads no configuration of the system.
export USER=paw-test LOGNAME=paw-test GIT_CONFIG_NOSYSTEM=1
# A paw that is not told where to listen opens its control socket in the
# runtime folder, where the owner's paw listens: the tests get their own.
# It is short, for a socket path must fit in 108 bytes, and one checkout
# always gets the same one.
XDG_RUNTIME_DIR=${TMPDIR:-/tmp}/paw-run-$(printf %s "$SCRATCH" | cksum | cut -d' ' -f1)
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export XDG_RUNTIME_DIR
# tests/suite.lua refuses to run without this: only these scripts (and
# the sealed::seal helper of the Rust tests) give the environment above.
export PAW_TEST_ENV=1
# The window asks the desktop for its file dialogs over the session bus:
# a test must never reach the real desktop's, where a dialog would open
# in front of the person at the machine.
# Only tests/tools/live.sh keeps the bus, for the keyring, in a run that
# opens no window.
export DBUS_SESSION_BUS_ADDRESS="${PAW_TEST_BUS:-unix:path=/nonexistent/bus}"
# Checkouts tested side by side each need a display number of their own.
PAW_TEST_DISPLAY=${PAW_TEST_DISPLAY:-96}
export PATH="$ROOT/tools/bin:$PATH" PAW_ROOT="$ROOT"
case "${PAW_TEST_PROFILE:-dev}" in
  dev) PROFILE_DIR=debug ;;
  release) PROFILE_DIR=release ;;
  *)
    echo "env.sh: PAW_TEST_PROFILE is dev or release, not $PAW_TEST_PROFILE" >&2
    exit 2
    ;;
esac
BIN=${PAW_TEST_BIN:-$ROOT/target/$PROFILE_DIR}
export PAW_TEST_STUB=${PAW_TEST_STUB:-$BIN/examples/libstub_clap.so}

paw_ready() {
  if [ -n "$PAW_TEST_IN_SUITE" ] || [ "$PAW_TEST_STAMP" = off ]; then return 0; fi
  want=$("$ROOT/tools/stamp.sh" "$ROOT") || return 1
  want_rust=$(echo "$want" | sed -n 's/^rust //p')
  rust_of() { sed -n 's/^rust //p' "$1/paw.stamp" 2> /dev/null; }
  if [ -n "$PAW_TEST_BIN" ]; then
    if [ "$(rust_of "$BIN")" != "$want_rust" ]; then
      echo "env.sh: $BIN/paw was not built from the Rust sources of $ROOT (paw.stamp)." >&2
      echo "Unset PAW_TEST_BIN, and the tests build this checkout, or build that binary again." >&2
      return 1
    fi
  else
    main=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2> /dev/null)
    main=${main%/.git}
    BIN=
    for dir in "$ROOT/target/$PROFILE_DIR" "$main/target/$PROFILE_DIR"; do
      if [ "$(rust_of "$dir")" = "$want_rust" ] && [ -f "$dir/examples/libstub_clap.so" ]; then
        BIN=$dir
        break
      fi
    done
    if [ -z "$BIN" ]; then
      BIN=$ROOT/target/$PROFILE_DIR
      echo "env.sh: building paw (${PAW_TEST_PROFILE:-dev} profile) in $ROOT" >&2
      (cd "$ROOT" && cargo build -q --profile "${PAW_TEST_PROFILE:-dev}" -p paw-tui -p paw-mcp -p chain-lsp &&
        cargo build -q --profile "${PAW_TEST_PROFILE:-dev}" -p paw-plugins --example stub_clap) || return 1
      echo "$want" > "$BIN/paw.stamp"
    fi
  fi
  export PAW_TEST_BIN=$BIN PAW_TEST_STUB=$BIN/examples/libstub_clap.so
  have_runtime=$(sed -n 's/^runtime //p' "$BIN/paw.stamp" 2> /dev/null)
  want_runtime=$(echo "$want" | sed -n 's/^runtime //p')
  if [ -z "$PAW_RUNTIME" ] && [ "$have_runtime" != "$want_runtime" ]; then
    runtime=$ROOT/target/dev-runtime
    if [ "$(cat "$runtime/stamp" 2> /dev/null)" != "$want_runtime" ]; then
      echo "env.sh: making the runtime of $ROOT (tools/dev-runtime.sh)" >&2
      "$ROOT/tools/dev-runtime.sh" "$runtime" > /dev/null || return 1
      echo "$want_runtime" > "$runtime/stamp"
    fi
    export PAW_RUNTIME=$runtime
  fi
}
