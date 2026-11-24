---
id: TASK-108
title: A customized BrowserPod image for the docs
status: Done
assignee: []
created_date: '2026-11-22T11:00:00Z'
updated_date: '2026-11-22T14:33:00Z'
labels:
  - web
  - docs
  - interactive
milestone: m-9
dependencies: []
priority: high
ordinal: 111000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A pod image prepared for the docs: paw built for wasm32-browserpod (the TASK-54 patch made proper: cfg-gated, not a patch), the demo projects and course states preloaded, a fixed terminal size, the audio bridge (fetch -> SharedArrayBuffer -> AudioWorklet) wired, and a small JS API so a docs page can open paw at a given state (a project, a lesson, a scope) and send keys for 'show me'. Built reproducibly in Nix; versioned with paw. Read first: web/browserpod/ on branch worktree-agent-a0f1e73fe5e27369b, backlog/docs/designs/web.md (BrowserPod section), the browserpod skill.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 paw builds for wasm32-browserpod-linux-musl from the tree with no patch: target-specific dependencies and cfg(target_vendor = "browserpod") in the code; the native build, clippy and the Rust tests do not change
- [x] #2 nix build .#paw-pod builds the pod image (paw for the pod, an ext2 home image with the demo song, the bundled extensions and the course, the page files and a manifest with the paw version and hashes); nix build --rebuild gives the same bytes
- [x] #3 From a local static server, the image boots in headless Chromium with BrowserPod's userImage: paw draws the demo song in a fixed 100x30 terminal, whatever the size of the page
- [x] #4 A JS API (paw-pod.js) opens paw at a project, a lesson of the course or a scope (:narrow), and sendKeys types keys in Vim notation; a headless test checks each state and that an arrow key moves the cursor (the split-Esc fix of TASK-106 in the pod)
- [x] #5 The audio bridge: in the pod, paw's audio backend 'page' sends the engine's blocks over HTTP to the page, a SharedArrayBuffer ring and an AudioWorklet play them; while the demo song plays, the worklet gets sound that is not silent, with the underruns counted and reported
- [x] #6 One small demo page boots nothing from BrowserPod's CDN until a button is pressed, shows the Powered by BrowserPod credit, and the docs of web/browserpod say how to build, test and embed the image
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done on branch worktree-agent-a4c624b254b4bfc11 (commits f9f3df27, 7979ff17, merge 08244805, b5f30d36, 2fa45360). Not Done: the owner sets it after the merge.

What is done (all 6 criteria):
- cfg(target_vendor = "browserpod") replaces the TASK-54 patch: target dependencies in Cargo.toml (mlua lua52 in a pod; no paw-plugins, cpal or ALSA there; paw-core, paw-tui, paw-gui add cpal, midi and device natively), runtime/lua/paw/portable.lua (the prelude), api::lua_integer/wide_integer, crates/paw-tui/src/plugins.rs. Native clippy has no new warnings; Rust tests and the full suite pass.
- Audio backend page (crates/paw-engine/src/backend/page.rs): clock thread -> rtrb -> sender thread -> POST http://audio.paw/pcm; the page fetch -> SharedArrayBuffer ring -> AudioWorklet. 2 native tests against a fake page.
- Nix: packages paw-pod, paw-pod-bin, dev shell browserpod (web/browserpod/default.nix). The pack and the nightly come from release files with hashes, no rustup. The crates come offline from web/browserpod/Cargo.lock (lock.sh pins libc, rustix and mio for the pack). nix build --rebuild gives the same bytes for both.
- The image: home.ext2 for BrowserPod.boot({ userImage }) (paw, PAW_HOME with the bundled extensions, the demo song with the regions Chords and Melody), the page files, manifest.json (version, rev, hashes).
- site/paw-pod.js: boot, open({project|lesson|scope|keys|lua}), sendKeys in Vim notation, a fixed 100x30 terminal, audio.start/stats. demo.html loads nothing from BrowserPod before Start and shows the credit.
- web/browserpod/test.sh: headless Chromium with and without the isolation headers. Every check passes on the Nix image. Start to running is 3.0-3.8 s; open scope or lesson is 1.0-1.8 s; the site sends 25.7 MB (home.ext2 is read in ranges). Sound: 0 underruns in 3 s on a quiet machine, and 1 to 13 under external load.
- Docs: web/browserpod/README.md (external), docs/reference/programs.md, nix-package.md, source-tree.md, AGENTS.md, Vale lists.

Findings: the pod's tty keeps the size that the terminal had when BrowserPod made it, so paw-pod.js sizes the element first. Process is a thenable whose then returns nothing. The spike had no split-Esc workaround to remove, and <Up> works through keys::Joiner.

What is left (not started, milestone deprioritized):
- TASK-107 embeds the API in the course pages.
- A step of a lesson as a state (open lesson N at step M).
- Less underrun under load: a larger prefill, or a pace from the page.
- home.ext2 is 100 MB with 64 MB free: a smaller free space would make the file smaller. The site sends 26 MB either way.
- Report the fixed tty size and the split escape sequences to BrowserPod (owner's account).
<!-- SECTION:NOTES:END -->
