#!/usr/bin/env bash
# Make the pod image of paw: the home image that BrowserPod mounts on
# /home (`BrowserPod.boot({ userImage })`), the page files, and a manifest.
#
#   make-image.sh SRC NATIVE_PAW POD_PAW OUT [REV]
#
# SRC is the source tree, NATIVE_PAW paw for this machine (it writes the
# demo projects), POD_PAW paw for the pod (build-paw.sh), REV the git
# revision. OUT is a directory that gets:
#
#   home.ext2               the home image
#   files.txt               what the home image holds
#   paw-pod.js, paw-live.js, audio-worklet.js, coi.js, coi-sw.js, demo.html
#   manifest.json           the paw version, the revision, the BrowserPod
#                           version, and the SHA-256 of each file
#
# The home image holds, under user/:
#
#   bin/paw                 paw for the pod
#   paw/extensions/         the bundled extensions, without pictures and
#                           native sources (PAW_HOME, for :tutor and the like)
#   paw/examples/           the example scripts
#   projects/demo-song/     the demo song as a project, with two regions
#
# Every file gets the same time and owner, so that the same input makes
# the same bytes. e2fsprogs reads the time from E2FSPROGS_FAKE_TIME.
set -euo pipefail
src="$(cd "$1" && pwd)"
native="$(realpath "$2")"
pod="$(realpath "$3")"
out="$(realpath -m "$4")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
home="$work/home"
user="$home/user"
mkdir -p "$user/bin" "$user/paw" "$user/projects" "$out"

install -m 755 "$pod" "$user/bin/paw"
(cd "$src" && find extensions examples -type f \
  ! -name '*.gif' ! -name '*.png' ! -name '*.cs' ! -name '*.rs' \
  ! -name '*.nix' ! -name '*.sh' ! -name '.gitignore' ! -path '*/tests/*' \
  -print0 | sort -z | xargs -0 -I{} install -D -m 644 {} "$user/paw/{}")

# The demo projects, written by paw on this machine, in a home of its own.
scratch="$work/scratch"
mkdir -p "$scratch"
(cd "$src" && env -i PATH="$PATH" HOME="$scratch" XDG_CONFIG_HOME="$scratch/config" \
  XDG_DATA_HOME="$scratch/data" XDG_STATE_HOME="$scratch/state" XDG_CACHE_HOME="$scratch/cache" \
  XDG_RUNTIME_DIR="$scratch/run" \
  "$native" --clean --no-plugins --audio null -l web/browserpod/make-home.lua "$user/projects")

(cd "$home" && find . -mindepth 1 | sort) > "$out/files.txt"
find "$home" -exec touch -h -d @1 {} +
# The pod's user is 1000 (`id` in a pod).
size_kb=$(( $(du -sk "$home" | cut -f1) * 5 / 4 + 65536 ))
rm -f "$out/home.ext2"
E2FSPROGS_FAKE_TIME=1 mke2fs -q -t ext2 -b 4096 -m 0 -N 4096 \
  -U 00000000-0000-4000-8000-000000000108 -E root_owner=1000:1000,hash_seed=00000000-0000-4000-8000-000000000108 \
  -d "$home" "$out/home.ext2" "${size_kb}k"
echo "wrote $out/home.ext2"

# The page files and the manifest.
for f in paw-pod.js paw-live.js audio-worklet.js coi.js coi-sw.js demo.html; do
  install -m 644 "$src/web/browserpod/site/$f" "$out/$f"
done
version=$(sed -n '/^\[workspace.package\]/,/^\[/{s/^version = "\(.*\)"$/\1/p}' "$src/Cargo.toml")
browserpod=$(sed -n 's/^export const BROWSERPOD_VERSION = "\(.*\)";$/\1/p' "$src/web/browserpod/site/paw-pod.js")
{
  printf '{\n  "version": "%s",\n  "rev": "%s",\n  "browserpod": "%s",\n  "image": "home.ext2",\n  "files": {\n' \
    "$version" "${5:-unknown}" "$browserpod"
  first=1
  for f in home.ext2 paw-pod.js paw-live.js audio-worklet.js coi.js coi-sw.js demo.html; do
    [ $first = 1 ] || printf ',\n'
    first=0
    printf '    "%s": "%s"' "$f" "$(sha256sum "$out/$f" | cut -d' ' -f1)"
  done
  printf '\n  }\n}\n'
} > "$out/manifest.json"
echo "wrote $out/manifest.json"
