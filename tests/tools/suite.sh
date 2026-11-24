#!/bin/sh
# Run the Lua end-to-end suite on the release build (or on $PAW_TEST_BIN).
#
#   tests/tools/suite.sh                  every test, without plugins, in 4 paw
#                                         processes
#   tests/tools/suite.sh plugins          with the dev shell's test plugins
#   tests/tools/suite.sh plugins "words"  only some tests, with the plugins
#                                         (PAW_PLUGIN_SANDBOX=0 loads them in-process)
#   tests/tools/suite.sh only "loop on"   the tests whose name holds the words
#   tests/tools/suite.sh only fold "K o"  the tests whose name holds any of
#                                         the words (one paw for all)
#
# Options go before the words above:
#
#   -j 2           the same in 2 paw processes (1 to 4), each with a share
#                  of the test files; if not given, 4 for a run of every
#                  test, and 1 for only, plugins or repeat
#   repeat 20      run the tests 20 times in each paw, and stop after the
#                  first run that fails: it finds a flaky test
#   --shuffle 7    run the test files, and the tests in each file, in the
#                  order that the seed 7 gives (the same seed gives the same
#                  order); with no number, a new seed, which it prints
#
# A run waits for a slot of the machine before it starts: one full run at a
# time, and up to $PAW_SUITE_SLOTS (3) `only` runs beside it. Many paw
# processes at once used up the threads of the machine, and it restarted.
# The slots are lock files in $PAW_SUITE_LOCKS (a folder in $TMPDIR).
#
# Prints the tests that failed and the last line ("all passed" or "N failed");
# the whole output is in target/test-scratch/suite.out. It also writes
# target/test-scratch/times.txt (the wall time of each test file, the slowest
# first) and target/test-scratch/suite.tap (each test with its result and the
# reason of a skip, in the TAP format, for CI).
. "$(dirname "$0")/env.sh"
cd "$ROOT" || exit 1
jobs=
jobs_given=
while :; do
  case "$1" in
    -j)
      jobs=$2
      jobs_given=1
      shift 2
      ;;
    repeat)
      case "$2" in
        "" | *[!0-9]*)
          echo "suite.sh: repeat takes a number, not '$2'" >&2
          exit 2
          ;;
      esac
      export PAW_TEST_REPEAT="$2"
      shift 2
      ;;
    --shuffle)
      case "$2" in
        "" | *[!0-9]*)
          PAW_TEST_SHUFFLE=$(($(date +%s) % 100000))
          shift
          ;;
        *)
          PAW_TEST_SHUFFLE=$2
          shift 2
          ;;
      esac
      export PAW_TEST_SHUFFLE
      ;;
    *) break ;;
  esac
done
# A shard is this script again (below). A shard that starts shards of its
# own starts processes without end and stops the machine. So a shard runs
# with one process, and it refuses a -j of more than 1.
if [ -n "$PAW_TEST_SHARD" ]; then
  if [ -n "$jobs_given" ] && [ "$jobs" != 1 ]; then
    echo "suite.sh: a shard does not start shards" >&2
    exit 2
  fi
  jobs=1
fi
# Without -j, a full run uses 4 processes. A run of some tests (only,
# plugins) or a repeat uses 1: the slots of the machine count on it.
if [ -z "$jobs_given" ]; then
  jobs=1
  [ -z "$1" ] && [ -z "$PAW_TEST_REPEAT" ] && jobs=4
fi
case "$jobs" in
  1 | 2 | 3 | 4) ;;
  *)
    echo "suite.sh: -j takes 1 to 4, not $jobs" >&2
    exit 2
    ;;
esac
# Take a slot of the machine (see the top). File descriptor 9 holds the
# lock: the shards and the paw processes keep it open until they end.
take_slot() {
  command -v flock > /dev/null || return 0
  locks=${PAW_SUITE_LOCKS:-${TMPDIR:-/tmp}/paw-suite-locks}
  mkdir -p "$locks"
  if [ "$1" = only ]; then
    n=${PAW_SUITE_SLOTS:-3}
    k=1
    while [ "$k" -le "$n" ]; do
      exec 9> "$locks/only$k"
      flock -n 9 && return 0
      k=$((k + 1))
    done
    echo "suite.sh: waiting for one of the $n slots of the other only runs" >&2
    exec 9> "$locks/only1"
  else
    exec 9> "$locks/full"
    flock -n 9 && return 0
    echo "suite.sh: waiting for the other full run to end" >&2
  fi
  flock 9
}
[ -z "$PAW_TEST_SHARD" ] && take_slot "$1"
[ -n "$PAW_TEST_SHUFFLE" ] && [ -z "$PAW_TEST_SHARD" ] && echo "shuffle seed $PAW_TEST_SHUFFLE"
# The runner (tests/suite.lua) adds to the files of the run: each run
# starts them again.
export PAW_TEST_OUT=$SCRATCH
rm -f "$SCRATCH/times.txt" "$SCRATCH/tap.lines" "$SCRATCH/suite.tap"
# The stub plugin that some tests load is a cargo example, which a plain
# `cargo build` does not make: build it here, so that a test never loads a
# stub that an older checkout left in target/. With PAW_TEST_BIN (a binary
# that another checkout built, for example a dev build of main), the stub
# comes from beside that binary, and nothing is built here. A shard does not
# build: the script that started it did.
if [ -n "$PAW_TEST_BIN" ]; then
  export PAW_TEST_STUB=$BIN/examples/libstub_clap.so
elif [ -z "$PAW_TEST_SHARD" ]; then
  cargo build --release -q -p paw-plugins --example stub_clap || exit 1
fi
out=$SCRATCH/suite.out

# Show what a person must read, write suite.tap, print the last line, and
# exit: 0 when no test failed, else 1. $1 is the code of the paw processes,
# $2 the number of failed tests that their outputs give.
finish() {
  grep -A8 "^FAIL" "$out"
  grep "^quarantined\|(quarantined, and it passed\|^repeat: " "$out"
  # TAP: the version, the plan (the number of results), then the results.
  if [ -f "$SCRATCH/tap.lines" ]; then
    {
      echo "TAP version 13"
      echo "1..$(grep -c '^\(not \)\?ok ' "$SCRATCH/tap.lines")"
      cat "$SCRATCH/tap.lines"
    } > "$SCRATCH/suite.tap"
  fi
  if [ "$2" -eq 0 ] && [ "$1" -eq 0 ]; then
    printf '\nall passed\n' | tee -a "$out" | tail -1
    exit 0
  fi
  failed=$2
  [ "$failed" -eq 0 ] && failed=1
  printf '\n%d failed\n' "$failed" | tee -a "$out" | tail -1
  exit 1
}

if [ "$jobs" -gt 1 ]; then
  # Each shard is this script again, with its own scratch folders (and so
  # its own XDG folders) and every Nth part of the test files (suite.lua).
  pids=""
  k=1
  while [ "$k" -le "$jobs" ]; do
    PAW_TEST_SHARD=$k/$jobs PAW_TEST_SCRATCH=$SCRATCH/shard$k "$0" -j 1 "$@" > /dev/null 2>&1 &
    pids="$pids $!"
    k=$((k + 1))
  done
  code=0
  for pid in $pids; do
    wait "$pid" || code=1
  done
  failed=0
  : > "$out"
  : > "$SCRATCH/tap.lines"
  k=1
  while [ "$k" -le "$jobs" ]; do
    shard=$SCRATCH/shard$k
    cat "$shard/suite.out" >> "$out"
    cat "$shard/tap.lines" >> "$SCRATCH/tap.lines" 2> /dev/null
    n=$(tail -1 "$shard/suite.out" | sed -n 's/^\([0-9]*\) failed$/\1/p')
    case "$(tail -1 "$shard/suite.out")" in
      "all passed") ;;
      *) failed=$((failed + ${n:-1})) ;;
    esac
    k=$((k + 1))
  done
  # Each test file runs in one shard: the times only need an order.
  cat "$SCRATCH"/shard*/times.txt 2> /dev/null | sort -rn > "$SCRATCH/times.txt"
  finish "$code" "$failed"
fi
case "$1" in
  plugins)
    # Plugins that are not in nixpkgs come in by their package's store
    # path (PAW_TEST_TONE3000, PAW_TEST_SOUNDSHED, PAW_TEST_MUSIO, and the
    # examples of extensions/plugstate/tests_frameworks.lua), or by one
    # bundle (a path that ends in .vst3, .clap or .lv2). The plugins get a
    # scratch home: some write beside it, not only to XDG_CONFIG_HOME.
    mkdir -p "$SCRATCH/home"
    rm -rf "$SCRATCH/bundles"
    mkdir -p "$SCRATCH/bundles/clap" "$SCRATCH/bundles/vst3" "$SCRATCH/bundles/lv2"
    # In the dev shell already (direnv, nix develop), the plugins' variables are
    # set: no second `nix develop`.
    dev="nix develop -c"
    [ -n "$IN_NIX_SHELL" ] && dev=""
    # shellcheck disable=SC2086
    PAW_SCRATCH_HOME=$SCRATCH/home PAW_BUNDLES=$SCRATCH/bundles $dev sh -c '
      export HOME=$PAW_SCRATCH_HOME
      for pkg in "$PAW_TEST_TONE3000" "$PAW_TEST_SOUNDSHED" "$PAW_TEST_MUSIO" "$PAW_TEST_DRAGONFLY" "$PAW_TEST_ILDAEIL" \
          "$PAW_TEST_NEURALNOTE" "$PAW_TEST_DECENTSAMPLER" "$PAW_TEST_AMPLOCKER" "$PAW_TEST_DRUMLOCKER" "$PAW_TEST_MTPDK" \
          "$PAW_TEST_GUITARIX" "$PAW_TEST_RATATOUILLE" "$PAW_TEST_VOLUM" "$PAW_TEST_UGRITONE" \
          "$PAW_TEST_GUITARCATCHER" "$PAW_TEST_CIRCVIT"; do
        case "$pkg" in
          "") ;;
          *.vst3|*.clap|*.lv2) ln -sf "$pkg" "$PAW_BUNDLES/${pkg##*.}/" ;;
          *) PAW_TEST_PLUGINS=$PAW_TEST_PLUGINS:$pkg/lib ;;
        esac
      done
      PAW_TEST_PLUGINS=$PAW_TEST_PLUGINS:$PAW_BUNDLES
      export CLAP_PATH=$(echo $PAW_TEST_PLUGINS | sed "s#:#/clap:#g")/clap
      export LV2_PATH=$(echo $PAW_TEST_PLUGINS | sed "s#:#/lv2:#g")/lv2
      export VST3_PATH=$(echo $PAW_TEST_PLUGINS | sed "s#:#/vst3:#g")/vst3
      "$0" --clean --clock manual --audio step -l tests/suite.lua ${1+"$1"}
      manual=$?
      PAW_TEST_LIVE=1 "$0" --clean -l tests/suite.lua ${1+"$1"}
      live=$?
      [ "$manual" -eq 0 ] && [ "$live" -eq 0 ]' "$BIN/paw" ${2:+"$2"} > "$out" 2>&1 ;;
  *)
    # The tests run on the manual clock (`T.advance` moves it) and the
    # stepped audio backend (the engine plays as the clock moves). Then the
    # live tests, which need real time, run in a second paw on the wall
    # clock (`opts.live` in tests/suite.lua).
    # The words of `only` go to the runner as one argument, one word on
    # each line.
    words=""
    if [ "$1" = only ]; then
      shift
      words=$(printf '%s\n' "$@")
    fi
    "$BIN/paw" --clean --no-plugins --clock manual --audio step -l tests/suite.lua ${words:+"$words"} > "$out" 2>&1
    manual=$?
    PAW_TEST_LIVE=1 "$BIN/paw" --clean --no-plugins -l tests/suite.lua ${words:+"$words"} >> "$out" 2>&1
    live=$?
    [ "$manual" -eq 0 ] && [ "$live" -eq 0 ] ;;
esac
code=$?
# Each pass ends with "all passed" or "N failed": the last line adds them.
finish "$code" "$(sed -n 's/^\([0-9]*\) failed$/\1/p' "$out" | awk '{ n += $1 } END { print n + 0 }')"
