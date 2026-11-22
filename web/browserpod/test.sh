#!/usr/bin/env bash
# Test the pod image in headless Chromium, on a local server.
#
#   web/browserpod/test.sh SITE [OUT.json] [--no-headers]
#
# SITE is the built image (`nix build .#paw-pod`, then ./result). The test
# loads BrowserPod's runtime and its base disk from BrowserPod's CDN, as
# any visitor of the page does; nothing else leaves the machine. With
# --no-headers the server sends no isolation headers, as GitHub Pages, and
# coi.js isolates the page. puppeteer-core is installed once into
# target/browserpod/node. Chromium and Node come from nixpkgs.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
site="$(realpath "$1")"
out="$(realpath -m "${2:-$repo/target/browserpod/test.json}")"
extra="${3:-}"
node_dir="$repo/target/browserpod/node"
tool() { nix build --no-link --print-out-paths "nixpkgs#$1" | head -1; }
node="$(tool nodejs)/bin"
export CHROMIUM="${CHROMIUM:-$(tool chromium)/bin/chromium}"
export PATH="$node:$PATH"
if [ ! -d "$node_dir/node_modules/puppeteer-core" ]; then
  mkdir -p "$node_dir"
  (cd "$node_dir" && npm init -y >/dev/null && npm install --ignore-scripts --no-audit --no-fund puppeteer-core@24.43.1)
fi
cp "$here/test.mjs" "$node_dir/test.mjs"
port=$((20000 + RANDOM % 20000))
served="$(mktemp)"
PAW_SERVE_LOG="$served" python3 "$here/serve.py" "$site" "$port" $extra >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; wait $server 2>/dev/null; rm -f "$served"' EXIT
sleep 0.5
cd "$node_dir"
code=0
timeout 600 node test.mjs "http://127.0.0.1:$port/demo.html" "$out" || code=$?
# What this site sent, by file (BrowserPod's own files come from its CDN).
echo "bytes served by this site:"
awk '{ n[$1] += $2; t += $2 } END { for (f in n) printf "  %-22s %10d\n", f, n[f]; printf "  %-22s %10d\n", "total", t }' "$served"
exit $code
