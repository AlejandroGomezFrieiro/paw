#!/usr/bin/env bash
# Audits paw-mcp with mcpscore, a checker of MCP servers, and fails when the
# score falls under the gate. mcpscore and its date are pinned, so the score
# changes only when the server changes.
#
#   tools/mcpscore.sh                       audit; exit 3 when under the gate
#   tools/mcpscore.sh --changed-since REV   audit only if the diff from REV
#                                           touches paw-mcp or what it builds from
#
# The binaries come from target/debug, or from PAW_MCP_BIN and PAW_BIN. The
# script does not build them. PAW_MCPSCORE_MIN changes the gate, for example
# to prove that the gate fails.
#
# mcpscore is Python from PyPI, and uvx fetches it. The flake check has no
# network and nixpkgs has no package of mcpscore's dependencies (mcp 2.3,
# httpx2), so this check runs before a push and in the merge checks, not in
# `nix flake check`.
#
# The run is sealed: the environment of tests/tools/env.sh, a scratch home
# and uv cache, and a kernel of its own with --audio null --clean
# --no-plugins and a scratch root.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VERSION=1.34.0
# uv resolves mcpscore's dependencies as they were on this day.
PINNED_DATE=2026-11-24
# The gate, in points. mcpscore's own --fail-under compares a percent that it
# rounds to a whole number, and 162 of 166 rounds to 98 % as 163 does. So the
# script compares the points, and the loss of one point fails. Raise the
# number when a change raises the score.
MIN_SCORE=${PAW_MCPSCORE_MIN:-163}

# The files that change what paw-mcp serves: the crates that it builds from
# (cargo tree), the API sources and the Lua runtime that it embeds as its
# references, and the versions of all the dependencies.
changed_inputs() {
  local base=$1 crates
  crates=$(cargo tree -p paw-mcp -e normal,build --prefix none --format "{p}" --offline |
    sed -n "s|.*($ROOT/\(crates/[^)]*\))\$|\1|p" | sort -u)
  # shellcheck disable=SC2086
  git diff --name-only "$base" -- Cargo.lock Cargo.toml crates/paw-mcp \
    crates/paw-core/src/api runtime/lua $crates
}

if [ "${1:-}" = "--changed-since" ]; then
  [ -n "${2:-}" ] || { echo "mcpscore: --changed-since needs a revision" >&2; exit 1; }
  if [ -z "$(changed_inputs "$2")" ]; then
    echo "mcpscore: skipped, the diff from $2 does not touch paw-mcp or its inputs"
    exit 0
  fi
fi

MCP_BIN=${PAW_MCP_BIN:-$ROOT/target/debug/paw-mcp}
KERNEL_BIN=${PAW_BIN:-$ROOT/target/debug/paw}
for bin in "$MCP_BIN" "$KERNEL_BIN"; do
  [ -x "$bin" ] || { echo "mcpscore: no binary $bin; build it first (cargo build -p paw-mcp -p paw-tui)" >&2; exit 1; }
done

if command -v uvx >/dev/null; then
  uvx=(uvx)
else
  uvx=(nix shell nixpkgs#uv -c uvx)
fi

PAW_TEST_SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/paw-mcpscore.XXXXXX")
trap 'rm -rf "$PAW_TEST_SCRATCH"' EXIT
export PAW_TEST_SCRATCH
# env.sh reads variables that may be unset.
set +u
# shellcheck source=tests/tools/env.sh
. "$ROOT/tests/tools/env.sh"
set -u
export UV_CACHE_DIR=$PAW_TEST_SCRATCH/uv
mkdir -p "$PAW_TEST_SCRATCH/root"

# mcpscore reads its own options before --stdio and gives the rest to the
# server. An exit that is not 0 means that the audit did not run. The final
# score goes to stderr, so the report keeps both streams.
report=$PAW_TEST_SCRATCH/report.txt
"${uvx[@]}" --exclude-newer "$PINNED_DATE" "mcpscore==$VERSION" \
  --stdio "$MCP_BIN" --spawn --paw "$KERNEL_BIN" --root "$PAW_TEST_SCRATCH/root" \
  -- --audio null --clean --no-plugins 2>&1 | tee "$report" || {
  echo "mcpscore: the audit did not run (exit $?): uv, the network to PyPI or the server failed; see the lines above" >&2
  exit 1
}

score=$(sed -n 's|^Audit finished\. Final score: \([0-9]*\)/[0-9]*$|\1|p' "$report")
if [ -z "$score" ]; then
  echo "mcpscore: the report has no final score" >&2
  exit 1
fi
if [ "$score" -lt "$MIN_SCORE" ]; then
  echo "mcpscore: gate failed: score $score is under $MIN_SCORE; the lines with ❌ give the rules" >&2
  exit 3
fi
echo "mcpscore: gate passed: score $score, gate $MIN_SCORE"
