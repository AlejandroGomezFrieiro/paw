---
id: TASK-54
title: 'Web: evaluate BrowserPod as a second path'
status: Done
assignee: []
created_date: '2026-11-22T04:29:00Z'
updated_date: '2026-11-23T06:19:00Z'
labels:
  - web
  - wasm
  - hosting
milestone: m-0
dependencies: []
priority: medium
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BrowserPod (browserpod.io, Leaning Technologies) is a Linux-like kernel in Wasm: stock rustc/cargo build unmodified Rust for wasm32-browserpod-linux-musl with std, threads, subprocesses, files, and /dev/tty in a page terminal. It could run paw-tui with far less porting than our emscripten plan (TASK-30/32): sockets, processes and termios may just work. Unknowns to test in a spike: crossterm raw mode, SIGWINCH and poll; our C deps (LuaJIT cannot JIT-compile in Wasm: still PUC Lua 5.2 from TASK-29; ALSA/pipewire gated); AUDIO: nothing documented (no Web Audio/AudioWorklet path); we would need a bridge from a pod process to an AudioWorklet in the page. Constraints: needs COOP/COEP headers (no service-worker workaround documented, check with our coi-sw from the spike); runtime and disk images load from their CDN; self-hosting/vendoring needs an Enterprise licence; free Community licence requires a visible 'Powered by BrowserPod' credit; outbound fetch only without an API key; open-source Edge grant available. Output: a spike (minimal crossterm program, then paw-tui with --audio null) and a comparison section in backlog/docs/designs/web.md: BrowserPod vs emscripten (effort, size, start time, audio, licence, hosting on github.io).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Spike done 2026-11-22. Branch worktree-agent-a0f1e73fe5e27369b, commit 8922521e (web/browserpod: build.sh, run.sh, crossterm and audio-bridge probes, paw-browserpod.patch 183 lines, page, puppeteer driver). Design: backlog/docs/designs/web.md, section 'BrowserPod (TASK-54)'. Worked: crossterm raw mode, keys, poll; paw-tui --audio null with the demo song drawn in the page terminal, j/k/h/l, Space Space, :q! (mlua lua52 on target, LuaJIT for build.rs, a Lua 5.2 prelude, engine/listen without audio defaults, 4 int-width casts, lilv/dl stub archives). Wall: BrowserPod libc has no setjmp; fixed with LLVM wasm sjlj lowering + a 35-line runtime (sjlj/rt.c). coi service worker works (no headers). Audio: pod HTTP -> page custom fetch() -> SAB ring -> AudioWorklet played 4.94 s sine, 0 underruns. Did not work: escape sequences split (ESC alone, so arrows/Alt/F-keys broken in crossterm), no resize, no input to a custom terminal, libc/rustix pins needed. Numbers: paw 23.0 MB raw / 4.7 MB brotli + BrowserPod 5.8 MB from CDN; first frame 3.1-5.6 s; key p50 6.5-7.9 ms; CPU idle 3-5 %, playing 4.5-7 % of one core; RSS 1.45 GB. Recommendation: both - BrowserPod for a docs demo (credit, CDN behind a button, after an ESC reader), emscripten for the full app (offline, size, start, real-time audio, no CDN/licence dependency). Official BrowserPod skill (leaningtech/skills f782b75e, MIT) installed unchanged in ~/.claude/skills/browserpod with LICENSE and SOURCE.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
paw-tui runs in BrowserPod (branch worktree-agent-a0f1e73fe5e27369b, 8922521e, web/browserpod/ + a 183-line patch); audio bridge via fetch->SAB->AudioWorklet works; ~10.5 MB first visit, ~3 s to first frame, keys ~8 ms. Recommendation: BrowserPod for the docs demo, emscripten for the full app. Results JSON in backlog/docs/designs/browserpod-results/.
<!-- SECTION:FINAL_SUMMARY:END -->
