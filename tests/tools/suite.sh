#!/bin/sh
# Run the Lua end-to-end suite on the release build (or on $PAW_TEST_BIN).
#
#   tests/tools/suite.sh                  every test, 4 parts at a time
#   tests/tools/suite.sh only "loop on"   the tests whose name holds the words
#   tests/tools/suite.sh only fold "K o"  the tests whose name holds any of
#                                         the words, 1 part at a time
#   tests/tools/suite.sh plugins          with the dev shell's test plugins,
#                                         in one paw
#   tests/tools/suite.sh plugins "words"  only some tests, with the plugins
#                                         (PAW_PLUGIN_SANDBOX=0 loads them in-process)
#
# Options go before the words above:
#
#   -j 2           run 2 parts at a time (1 to 4); if not given, 4 for a run
#                  of every test, and 1 for only, plugins or repeat
#   repeat 20      run the tests of each part 20 times in its paw, and stop
#                  after the first run that fails: it finds a flaky test
#   --shuffle 7    run the tests of each part in the order that the seed 7
#                  gives (the same seed gives the same order); with no
#                  number, a new seed, which it prints
#
# A part is a test file of tests/, or the test files of one extension. The
# Lua suite is the test binary of tests/harness: cargo nextest runs each
# part in a paw of its own, with the limits of .config/nextest.toml (the
# profiles lua and lua-one). The plugins run does not use it: it needs the
# plugin folders of the dev shell in place of the empty ones of env.sh.
#
# Prints what nextest reports (the parts that fail, run long or leak), the
# quarantined tests, and the last line ("all passed" or "N failed"). The
# output of each part is in target/test-scratch/parts/<part>/suite.out, and
# all of it in target/test-scratch/suite.out. nextest writes
# target/nextest/<profile>/junit.xml (each part, its result and its time).
. "$(dirname "$0")/env.sh"
cd "$ROOT" || exit 1
# A paw of the suite has PAW_TEST_IN_SUITE. A test that starts the suite
# again would start paw processes without end, and stop the machine.
if [ -n "$PAW_TEST_IN_SUITE" ]; then
  echo "suite.sh: the suite does not start inside a run of the suite" >&2
  exit 2
fi
jobs=
while :; do
  case "$1" in
    -j)
      jobs=$2
      case "$jobs" in
        1 | 2 | 3 | 4) ;;
        *)
          echo "suite.sh: -j takes 1 to 4, not $jobs" >&2
          exit 2
          ;;
      esac
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
      echo "shuffle seed $PAW_TEST_SHUFFLE"
      ;;
    *) break ;;
  esac
done
# The stub plugin that some tests load is a cargo example, which a plain
# `cargo build` does not make: build it here, so that a test never loads a
# stub that an older checkout left in target/. With PAW_TEST_BIN (a binary
# that another checkout built, for example a dev build of main), env.sh
# takes the stub from beside that binary, and nothing is built here.
if [ -z "$PAW_TEST_BIN" ]; then
  cargo build --release -q -j 4 -p paw-plugins --example stub_clap || exit 1
fi
out=$SCRATCH/suite.out

# Print the quarantined tests of the output and the last line, and exit: 0
# when the run passed, else 1. $1 is the code of the run.
finish() {
  grep "^quarantined\|(quarantined, and it passed\|^repeat: " "$out"
  # Each pass ends with "all passed" or "N failed": the last line adds them.
  failed=$(sed -n 's/^\([0-9]*\) failed$/\1/p' "$out" | awk '{ n += $1 } END { print n + 0 }')
  if [ "$1" -eq 0 ] && [ "$failed" -eq 0 ]; then
    printf '\nall passed\n'
    exit 0
  fi
  # A part that hung, leaked or did not start fails with no count.
  [ "$failed" -eq 0 ] && failed=1
  printf '\n%d failed\n' "$failed"
  exit 1
}

if [ "$1" = plugins ]; then
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
  PAW_TEST_IN_SUITE=1 PAW_SCRATCH_HOME=$SCRATCH/home PAW_BUNDLES=$SCRATCH/bundles $dev sh -c '
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
    [ "$manual" -eq 0 ] && [ "$live" -eq 0 ]' "$BIN/paw" ${2:+"$2"} > "$out" 2>&1
  code=$?
  grep -A8 "^FAIL" "$out"
  finish "$code"
fi

# The words of `only` go to the harness in one variable, one word on each
# line. A run of some tests, or a repeat, runs one part at a time (the
# profile lua-one); a run of every test, four (the profile lua).
profile=lua
if [ "$1" = only ]; then
  shift
  PAW_TEST_WORDS=$(printf '%s\n' "$@")
  export PAW_TEST_WORDS
  profile=lua-one
fi
[ -n "$PAW_TEST_REPEAT" ] && profile=lua-one
rm -rf "$SCRATCH/parts"
cargo nextest run --cargo-quiet --build-jobs 4 --no-tests warn -p paw-lua-suite --profile "$profile" ${jobs:+--test-threads "$jobs"}
code=$?
cat "$SCRATCH"/parts/*/suite.out > "$out" 2> /dev/null
finish "$code"
