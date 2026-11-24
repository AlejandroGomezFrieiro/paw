---
id: TASK-367
title: >-
  Spike: unkernel in place of BrowserPod for paw in the browser, with the user's
  files and plugins
status: To Do
assignee: []
created_date: '2026-11-24T13:48:00Z'
updated_date: '2026-11-24T14:21:00Z'
labels:
  - research
  - web
  - agent:builder
milestone: m-0
dependencies: []
priority: medium
ordinal: 436000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-24: https://github.com/pithings/unkernel may replace BrowserPod (web/browserpod/: build-paw.sh, make-image.sh, site/paw-pod.js, paw-live.js, demo.html; tools/website/live.*; runtime/lua/paw/portable.lua). Goal: the doc examples and 'try paw in the browser' connect to the user's filesystem and can use plugins.
Research questions: 1. What unkernel is (kernel model, syscalls, threads, sockets, licence, maturity, release cadence, who maintains it). 2. Can it run paw's headless kernel (Rust, LuaJIT FFI, a Unix socket, threads, the null audio backend) and the terminal frontend in a page? What must change in paw (wasm32-wasi target? native x86 emulation?). 3. User files: File System Access API (showDirectoryPicker) or OPFS mapped into the guest; read and write a project folder; browser support (Chromium vs Firefox/Safari). 4. Plugins: which kinds could run (Lua extensions yes; CLAP/LV2/VST3 native .so need x86 emulation or a wasm build; WebAudio/AudioWorklet for sound). 5. Compared with BrowserPod: boot time, image size, licence and attribution, networking, cost. 6. A spike plan: the smallest proof (paw --headless --audio null in unkernel, one doc example run, one folder opened from disk), its steps and risks, and the go/no-go criteria. Report only; no code. Then the owner decides.
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Each acceptance criterion is met, and the notes give its evidence
- [ ] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [ ] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [ ] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [ ] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [ ] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [ ] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [ ] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Revised 2026-11-24 after the owner's pointer to https://trynix.dev (fzakaria/trynix, docs/gui.md): unkernel's aarch64 guest boots any nixpkgs closure from cache.nixos.org or a cache served next to the page; Wayland/X11 GUI programs open as windows (WebGL2 for GL); sound works (first click; PulseAudio programs play). Verdict now: WORTH A SPIKE, after the next push. The aarch64 paw build is cheap (flake, served as a cache); sound path exists. Open-source plugins in nixpkgs with aarch64-linux builds (Surge XT, LSP, x42, Dragonfly) should load; closed x86/Windows VSTs cannot. Main risk: emulator speed for real-time audio. Spike (paw-builder): 1. flake aarch64-linux paw as a static cache next to a test page on unkernel/trynix; 2. demo-song first screen, key time vs 100 ms; 3. play with Surge XT, count underruns (use trynix's emubench); 4. File System Access folder bridge into the guest's 9p mount, read+write a project. Go: keys <100 ms, no underruns on demo-song with one synth, folder round trip in Chromium. Also: GPL-2.0 review of distributing unkernel.

PO 2026-11-24: TASK-370 holds the folder bridge as its own goal (works with BrowserPod or unkernel, OPFS fallback). Step 4 of this spike only tests the bridge on unkernel; reuse the design of TASK-370 when it exists.
<!-- SECTION:NOTES:END -->
