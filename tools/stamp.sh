#!/bin/sh
# Prints the hash of the sources of a paw binary in ROOT (default: this
# checkout), with uncommitted changes: a line "rust <hash>" and a line
# "runtime <hash>" for the Lua that the build compiles in.
#
#   tools/stamp.sh [ROOT]
root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
cd "$root" && git rev-parse --show-toplevel > /dev/null || exit 1
hash_of() {
  git ls-files -d -- "$@" > "$tmp.gone"
  git ls-files -co --exclude-standard -- "$@" | sort -u | grep -vxF -f "$tmp.gone" > "$tmp.files"
  git hash-object --stdin-paths < "$tmp.files" | paste "$tmp.files" - | sha256sum | cut -c1-16
}
tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp" "$tmp.gone" "$tmp.files"' EXIT
echo "rust $(hash_of Cargo.toml Cargo.lock .cargo crates)"
echo "runtime $(hash_of runtime tlconfig.lua)"
