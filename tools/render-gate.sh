#!/bin/sh
# The render gate: renders the demo song and the other songs that the repo
# keeps, and compares the SHA-256 of each file with
# tests/render-gate/hashes.sha256. A change of the engine or of a device that
# alters one sample fails, and the output names the file.
#
#   tools/render-gate.sh            check the hashes
#   tools/render-gate.sh --update   keep the new hashes (a change that is meant
#                                   to alter the sound; say why in the commit
#                                   message)
#
# It runs in the test environment (tests/tools/env.sh) on the paw that
# env.sh gives: a dev build of this checkout's sources. It takes a few seconds.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/tools/env.sh"
cd "$ROOT" || exit 1
paw_ready || exit 1
KEPT=tests/render-gate/hashes.sha256
WORK=$SCRATCH/render-gate
rm -rf "$WORK"
mkdir -p "$WORK"
"$BIN/paw" --clean --no-plugins --audio null --no-listen -l tools/render-gate.lua "$WORK" > "$WORK/render.out" 2>&1 \
  || { cat "$WORK/render.out"; echo "render-gate: the render failed" >&2; exit 2; }
(cd "$WORK" && sha256sum -- *.wav) > "$WORK/now.sha256"
if [ "$1" = "--update" ]; then
  mkdir -p tests/render-gate
  cp "$WORK/now.sha256" "$KEPT"
  echo "render-gate: kept $(wc -l < "$KEPT") hashes in $KEPT"
  exit 0
fi
[ -f "$KEPT" ] || { echo "render-gate: no $KEPT (run with --update)" >&2; exit 2; }
# The kept list and the new one must name the same files, so a song that
# leaves the gate is noticed too.
if ! (cd "$WORK" && sha256sum --check --quiet "$ROOT/$KEPT") 2> "$WORK/check.err" \
  || [ "$(wc -l < "$KEPT")" != "$(wc -l < "$WORK/now.sha256")" ]; then
  cat "$WORK/check.err" >&2
  echo "render-gate: the sound changed (see the files above). If it is meant, run tools/render-gate.sh --update and say why in the commit message." >&2
  exit 1
fi
echo "render-gate: $(wc -l < "$KEPT") files render bit-identical"
