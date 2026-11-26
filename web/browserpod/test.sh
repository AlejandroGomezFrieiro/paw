#!/usr/bin/env bash
# Test the pod image in headless Chromium, on a local server.
#
#   web/browserpod/test.sh SITE [OUT.json] [--no-headers] [--pages-path] [--course | --site]
#
# SITE is the built image (`nix build .#paw-pod`, then ./result). With
# --course, SITE is the website with the pod (`nix build .#website-live`),
# and test-course.mjs does each lesson of the course page with its
# buttons. With --site, SITE is the same, and test-site.mjs tries the
# landing page (its recorded session, Try paw, the sound) and two how-to
# guides with a live paw. The test
# loads BrowserPod's runtime and its base disk from BrowserPod's CDN, as
# any visitor of the page does; nothing else leaves the machine. With
# --no-headers the server sends no isolation headers, as GitHub Pages, and
# the service worker isolates the page. With --pages-path, the site is
# under the repository path, not /. puppeteer-core is installed once into
# target/browserpod/node. Chromium and Node come from nixpkgs.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
site="$(realpath "$1")"
out="$(realpath -m "${2:-$repo/target/browserpod/test.json}")"
extra=()
prefix="" script=test.mjs page=demo.html
for flag in "${@:3}"; do
  case "$flag" in
    --no-headers) extra=(--no-headers) ;;
    --pages-path)
      repository=${GITHUB_REPOSITORY:-paw}
      prefix=${repository##*/}/
      ;;
    --course) script=test-course.mjs page=docs/tutorials/course/in-the-browser.html ;;
    --site) script=test-site.mjs page=index.html ;;
    *) echo "unknown flag $flag" >&2; exit 2 ;;
  esac
done
node_dir="$repo/target/browserpod/node"
tool() { nix build --inputs-from "$repo" --no-link --print-out-paths "nixpkgs#$1"; }
node="$(tool nodejs)/bin"
export CHROMIUM="${CHROMIUM:-$(tool chromium)/bin/chromium}"
export PATH="$node:$PATH"
if [ ! -d "$node_dir/node_modules/puppeteer-core" ]; then
  mkdir -p "$node_dir"
  (cd "$node_dir" && npm init -y >/dev/null && npm install --ignore-scripts --no-audit --no-fund puppeteer-core@24.43.1)
fi
cp "$here/$script" "$node_dir/$script"
scratch="$(mktemp -d)"
server=
trap '
  if [ -n "$server" ]; then
    kill "$server" 2>/dev/null || true
    wait "$server" 2>/dev/null || true
  fi
  rm -rf "$scratch"
' EXIT
served="$scratch/served"
: > "$served"
if [ -n "$prefix" ]; then
  ln -s "$site" "$scratch/${prefix%/}"
  site="$scratch"
fi
# Listen on a free port and wait for the server to print the URL.
mkfifo "$scratch/ready"
PAW_SERVE_LOG="$served" python3 "$here/serve.py" "$site" 0 "${extra[@]}" > "$scratch/ready" &
server=$!
read -r base < "$scratch/ready"
mkdir -p "$(dirname "$out")"
cd "$node_dir"
code=0
timeout 1800 node "$script" "$base$prefix$page" "$out" || code=$?
# What this site sent, by file (BrowserPod's own files come from its CDN).
echo "bytes served by this site:"
awk '{ n[$1] += $2; t += $2 } END { for (f in n) printf "  %-22s %10d\n", f, n[f]; printf "  %-22s %10d\n", "total", t }' "$served"
exit $code
