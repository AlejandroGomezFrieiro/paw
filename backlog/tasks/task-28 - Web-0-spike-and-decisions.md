---
id: TASK-28
title: 'Web 0: spike and decisions'
status: Done
assignee: []
created_date: '2026-11-21T19:32:00Z'
updated_date: '2026-11-23T06:19:00Z'
labels:
  - web
  - wasm
milestone: m-0
dependencies: []
priority: medium
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Prove paw can run in a browser and record the choices, with numbers (binary size, start time, audio latency, CPU). Known hard points: LuaJIT has no WebAssembly backend (choose PUC Lua 5.1/5.4 via mlua vendored, or another VM; Teal output is plain Lua 5.1 so it should run; FFI code such as dsp.lua needs a non-FFI path); threads need cross-origin isolation (COOP/COEP); no fork, sockets or native plugins; target wasm32-unknown-unknown or emscripten. Output: a design doc in backlog/docs/designs/web.md and a demo page that starts the kernel and plays a sine.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Spike done 2026-11-21 (branch worktree-agent-aaf6d472254f591da, commit bf3331cd). Verdict: feasible, ~6-9 weeks for TASK-29..33/35/36. paw-engine builds for wasm32-unknown-unknown (3 native-neutral changes) and plays in an AudioWorklet in headless Chromium: 577 KB wasm (232 KB gzip), 9-14 ms to a playing engine, ~17 us per 128-frame callback (native 16.5 us). The whole Lua runtime runs on PUC Lua (mlua lua52/lua54, no Rust change, ~60-line prelude): suite 1503 ok/213 failed on 5.2, 1450/265 on 5.4 (111 of those are 3.0-vs-3 formatting). PUC Lua 5-7x slower than LuaJIT on pure Lua, x2 more in wasm; whole-program redraw/edit only 1.0-1.7x. Decisions: Lua 5.2 in the browser, LuaJIT native; one wasm32-unknown-emscripten module with shared memory (kernel on a worker, engine on a Wasm Audio Worklet); xterm.js fed by paw-tui bytes; OPFS via WASMFS; COOP/COEP by service worker (proven). openDAW studied (AGPL: patterns only). Design: backlog/docs/designs/web.md
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Feasible (~6-9 agent-weeks for TASK-29..33,35,36). Engine builds for wasm32 and plays in an AudioWorklet (232 KB gzip, 0.65% of the callback budget). PUC Lua 5.2 runs paw (1503/1782 tests natively; rest FFI/utau/env). Spike branch worktree-agent-aaf6d472254f591da (bf3331cd), not merged. Design: backlog/docs/designs/web.md.
<!-- SECTION:FINAL_SUMMARY:END -->
