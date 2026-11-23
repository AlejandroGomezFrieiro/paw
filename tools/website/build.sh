#!/bin/sh
# Builds the website from the repository's Markdown, and checks its links.
#
#   tools/website/build.sh <output-dir>          build into <output-dir>
#   tools/website/build.sh <output-dir> serve    build, then serve and rebuild on change
#   PAW_POD=<pod image> tools/website/build.sh <output-dir>   with paw for the browser in pod/
#
# The Markdown is not changed. The script copies README.md, docs/ and the
# Markdown and pictures of extensions/ into a staging folder with the same
# layout as the repository (README.md is the landing page), writes the sidebar (summary.lua), and runs mdBook.
# `nix build .#website` runs it in a sandbox with no network, and
# `nix develop -c tools/website/build.sh /tmp/paw-site serve` previews it.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
out=${1:?usage: build.sh <output-dir> [serve]}
mode=${2:-build}
REPO_URL=${REPO_URL:-https://github.com/AlejandroGomezFrieiro/custom_daw}
lua=${LUA:-$(command -v lua || command -v luajit)}

mkdir -p "$out"
out=$(cd "$out" && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

cd "$repo"
cp --no-preserve=mode README.md AGENTS.md "$stage/"
cp -r --no-preserve=mode docs "$stage/docs"
find extensions \( -name '*.md' -o -name '*.png' -o -name '*.gif' -o -name '*.svg' -o -name '*.jpg' \) \
  -print0 | xargs -0 cp --no-preserve=mode --parents -t "$stage"
find crates -name README.md -print0 | xargs -0 cp --no-preserve=mode --parents -t "$stage"
chmod -R u+w "$stage"
sed "s|@REPO_URL@|$REPO_URL|g" "$here/book.toml" > "$stage/book.toml"
cp "$here/landing.css" "$here/live.css" "$stage/"
# The site opens on the landing page. It takes the place of README.md in the
# staged tree only, and the README stays as GitHub shows it.
cp "$here/landing.md" "$stage/README.md"
"$lua" "$here/summary.lua" "$stage"

if [ "$mode" = serve ]; then
  # Serving does not rebuild from the repository: stop and run again after an edit.
  exec mdbook serve "$stage" -d "$out/book" -n 127.0.0.1 -p "${PORT:-3000}"
fi

mdbook build "$stage" -d "$out/site"
rm -f "$out/site/book.toml" "$out/site/SUMMARY.md"
# mdBook writes README.md as index.html but links to it as README.html (as
# GitHub names it): keep both names.
find "$out/site" -name index.html | while read -r f; do
  d=$(dirname "$f")
  if [ -e "$stage${d#"$out/site"}/README.md" ]; then cp "$f" "$d/README.html"; fi
done
# mdBook writes "./" in front of the path of an edit link. The landing page
# comes from tools/website/landing.md, and its edit link says so.
find "$out/site" -name '*.html' -print0 | xargs -0 sed -i 's|edit/main/\./|edit/main/|'
for f in "$out/site/index.html" "$out/site/README.html"; do
  sed -i "s|edit/main/README.md|edit/main/tools/website/landing.md|" "$f"
done
# A page with a live paw loads pod/paw-live.js, and the service worker for
# isolation is at the root, so that it can serve each page. PAW_POD is the
# pod image (`nix build .#paw-pod`): without it, the button of such a page
# says that paw for the browser is not on this copy.
mkdir -p "$out/site/pod"
if [ -n "${PAW_POD:-}" ]; then
  cp -r --no-preserve=mode "$PAW_POD"/. "$out/site/pod/"
else
  cp --no-preserve=mode web/browserpod/site/paw-live.js "$out/site/pod/"
fi
cp --no-preserve=mode web/browserpod/site/coi-sw.js "$out/site/"
"$lua" "$here/linkcheck.lua" "$stage" "$out/site" "$repo" "$REPO_URL"
