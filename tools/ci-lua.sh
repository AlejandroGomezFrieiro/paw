#!/bin/sh
# Run the Lua suite with a binary and stub from the same build in CI.
set -eu

profile=${1:?usage: ci-lua.sh dev|release [suite options]}
shift
case "$profile" in
  dev | release) ;;
  *) echo "unknown cargo profile: $profile" >&2; exit 2 ;;
esac

export INSTA_UPDATE=no SCCACHE_CACHE_SIZE=2G
cargo build --locked --jobs 2 --profile "$profile" -p paw-tui -p paw-mcp -p chain-lsp
cargo build --locked --jobs 2 --profile "$profile" -p paw-plugins --example stub_clap
COLORTERM=truecolor TMPDIR=/tmp PAW_TEST_PROFILE=$profile tests/tools/suite.sh "$@"
