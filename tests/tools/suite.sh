#!/bin/sh
# Run the Lua end-to-end suite on the release build (or on $PAW_TEST_BIN).
#
#   tests/tools/suite.sh                  every test, without plugins
#   tests/tools/suite.sh plugins          with the dev shell's test plugins
#   tests/tools/suite.sh plugins "words"  only some tests, with the plugins
#                                         (PAW_PLUGIN_SANDBOX=0 loads them in-process)
#   tests/tools/suite.sh only "loop on"   the tests whose name holds the words
#   tests/tools/suite.sh -j 2 ...         the same in 2 paw processes (4 at most),
#                                         each with a share of the test files
#
# Prints the tests that failed and the last line ("all passed" or "N failed");
# the whole output is in target/test-scratch/suite.out.
. "$(dirname "$0")/env.sh"
cd "$ROOT" || exit 1
jobs=1
if [ "$1" = "-j" ]; then
  jobs=$2
  shift 2
fi
case "$jobs" in
  1 | 2 | 3 | 4) ;;
  *)
    echo "suite.sh: -j takes 1 to 4, not $jobs" >&2
    exit 2
    ;;
esac
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
if [ "$jobs" -gt 1 ]; then
  # Each shard is this script again, with its own scratch folders (and so
  # its own XDG folders) and every Nth part of the test files (suite.lua).
  pids=""
  k=1
  while [ "$k" -le "$jobs" ]; do
    PAW_TEST_SHARD=$k/$jobs PAW_TEST_SCRATCH=$SCRATCH/shard$k "$0" "$@" > /dev/null 2>&1 &
    pids="$pids $!"
    k=$((k + 1))
  done
  code=0
  for pid in $pids; do
    wait "$pid" || code=1
  done
  failed=0
  : > "$out"
  k=1
  while [ "$k" -le "$jobs" ]; do
    shard_out=$SCRATCH/shard$k/suite.out
    cat "$shard_out" >> "$out"
    n=$(tail -1 "$shard_out" | sed -n 's/^\([0-9]*\) failed$/\1/p')
    case "$(tail -1 "$shard_out")" in
      "all passed") ;;
      *) failed=$((failed + ${n:-1})) ;;
    esac
    k=$((k + 1))
  done
  grep -A8 "^FAIL" "$out"
  if [ "$failed" -eq 0 ] && [ "$code" -eq 0 ]; then
    printf '\nall passed\n' | tee -a "$out" | tail -1
  else
    printf '\n%d failed\n' "$failed" | tee -a "$out" | tail -1
    code=1
  fi
  exit $code
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
      "$0" --clean -l tests/suite.lua ${1+"$1"}' "$BIN/paw" ${2:+"$2"} > "$out" 2>&1 ;;
  only)
    "$BIN/paw" --clean --no-plugins -l tests/suite.lua "$2" > "$out" 2>&1 ;;
  *)
    "$BIN/paw" --clean --no-plugins -l tests/suite.lua > "$out" 2>&1 ;;
esac
code=$?
grep -A8 "^FAIL" "$out"
tail -1 "$out"
exit $code
