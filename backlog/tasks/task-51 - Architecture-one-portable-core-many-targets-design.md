---
id: TASK-51
title: 'Architecture: one portable core, many targets (design)'
status: To Do
assignee: []
created_date: '2026-11-21T20:46:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - architecture
  - platforms
  - web
milestone: m-1
dependencies: []
priority: medium
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design the architecture that lets paw build for every target from one codebase. Owner decision (2026-11-21): targets NOW are Unix (Linux + macOS) terminal, the egui window, and the web (wasm); Windows is LOW priority but the design must let it fit later without a rewrite; Android/others later.
Scope of the design:
- Layers: a portable core (project model, engine, scenes, Lua runtime API) with no OS calls; a platform layer of traits (dirs, processes/sandbox, local IPC, shared memory + doorbell, audio, MIDI, file watching, clock/random, terminal I/O) with implementations per target (linux, macos, web; windows later); frontends (terminal via a byte stream, egui, web page) on the scene protocol.
- The Lua VM as a build choice (LuaJIT native, PUC Lua 5.2 for web/JIT-less targets) with one compatibility prelude and FFI paths gated.
- Process model per target: native = kernel + plugin helper processes + sockets; web = one module, kernel on a Web Worker, engine in an AudioWorklet, no plugin processes; how the same kernel API covers both.
- Cargo layout: crates, features (pipewire, lv2, plugins, luajit/lua52), target cfgs; what CI checks per target.
- Plugin hosting as an optional capability (native CLAP/VST3/LV2; web: built-in + future Wasm devices TASK-1, WebCLAP as prior art).
- Migration order from today's code with small parts, keeping Linux unchanged at each step.
Inputs: backlog/docs/designs/platforms.md (TASK-37 audit, P1-P20) and backlog/docs/designs/web.md (TASK-28 spike, openDAW notes). Output: backlog/docs/designs/architecture.md, refined tickets under m-0 and m-1, owner questions with recommendations.
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
Owner 2026-11-21: Windows = WSL2 running the Linux build; Windows-native plugins via a bridge helper from WSL without wine (TASK-52); macOS plugins native on the macOS build (TASK-53). The platform layer must still allow a native Windows port later.

Architecture review 2026-11-22 (backlog/docs/designs/architecture-review.md): inputs for architecture.md: TASK-95 (Document out of Session, then paw-model with no OS calls: the first piece of the portable core), TASK-99 (Shared in parts, host services behind 'native'), F9 (compile-time modules vs traits) and the table of platform seams, TASK-97 (DeviceProvider: plugin hosting as an optional provider, WebAssembly devices as another).

Owner, 2026-11-22: the design of this ticket rewrites the m-0 and m-1 tickets (Web 1 to 8, Platforms) with acceptance criteria.

From TASK-164 (2026-11-23): mimalloc is the global allocator of paw-tui on native targets; cargo tree shows it on x86_64 windows-msvc too, built with cc and no system library. The web build and BrowserPod keep the default allocator.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): ADR 0016 (one portable core) is accepted. In plan V2 the portable model is paw-model (TASK-95.1, TASK-95.3); the event loop (TASK-292, TASK-294) gives one turn for the web and native builds. Keep this ticket for the m-0 and m-1 ticket rewrite.
<!-- SECTION:NOTES:END -->
