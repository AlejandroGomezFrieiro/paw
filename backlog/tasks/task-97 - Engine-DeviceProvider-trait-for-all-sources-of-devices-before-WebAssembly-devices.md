---
id: TASK-97
title: >-
  Engine: DeviceProvider trait for all sources of devices (before WebAssembly
  devices)
status: To Do
assignee: []
created_date: '2026-11-22T10:38:00Z'
updated_date: '2026-11-24T14:22:00Z'
labels:
  - agent:builder
milestone: m-18
dependencies:
  - TASK-301
priority: medium
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: one DeviceProvider trait for every source of device kinds (built-in devices, CLAP/VST3/LV2 with the sandbox, Lua devices, later WebAssembly), in place of the four closures of Registry and the global state of the plugin and Lua device crates. Finding F3 of the architecture review (backlog/docs/designs/architecture-review.md). Do it before TASK-1.

Today: Registry (crates/paw-engine/src/device.rs, lines 776 to 803) holds rescan, add_dir, remove_dir, attach as Option<Rc<dyn Fn>>; paw-tui/src/main.rs (lines 421 to 460) fills them and sets statics (paw_luadev HELPER, sandbox HOST and CACHE, ADDED_DIRS). The helper process picks a Lua device by a "lua:" prefix (main.rs:367).

Change:
1. trait DeviceProvider { name, scan, rescan, add_dir, remove_dir, attach } with default methods; Registry keeps Kinds, posts, aliases and Vec<Box<dyn DeviceProvider>>.
2. PluginProvider (paw-plugins) owns cache path, host command and added folders; sandbox::wrap becomes a step of its scan. LuaProvider (paw-luadev) owns the helper path. No statics left for these.
3. The helper process gets a typed choice (clap subcommand, enum HostKind) in place of the prefix.
4. Controller narrower: fn editor() -> Option<&mut dyn Editor> for the four window methods; fn stats() for health, late_blocks, busy_time.

Read first: the review, F3 and E1; crates/paw-engine/src/device.rs; paw-tui/src/main.rs build_registry and dispatch; paw-plugins/src/lib.rs and sandbox/mod.rs; paw-luadev/src/lib.rs; docs/explanation/about-the-plugin-sandbox.md; .claude/skills/rust-skills.

Keep: the audio-thread rules; tests/no_alloc.rs of paw-engine and paw-plugins pass.
Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Registry has no Option<Rc<dyn Fn>> hooks; providers do scan, rescan, add_dir, remove_dir, attach
- [ ] #2 No process-wide statics for the plugin host command, the plugin cache, the added folders or the Lua helper
- [ ] #3 A Rust test registers a fake provider and makes a device of its kind
- [ ] #4 Plugin, Lua device and sandbox tests pass; no_alloc tests pass; docs that name the old hooks are fixed
- [ ] #5 Each factory entry has an Owner and a KindId<DeviceFamily>; an unload removes the entries of its owner
<!-- AC:END -->

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
Owner 2026-11-22 accepted the review's recommendations: see 'Owner decisions' at the end of backlog/docs/designs/architecture-review.md.

Board review 2026-11-23: still open (Registry keeps its Option<Rc<dyn Fn>> hooks). Priority medium: m-10 comes after m-2, m-3 and m-12 (owner focus). It is high again when the WebAssembly devices (TASK-1) start.

PO 2026-11-23 (plan V2 bundles): Part of WA. The kinds core comes from A1 (TASK-301).
<!-- SECTION:NOTES:END -->
