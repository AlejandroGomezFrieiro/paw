---
id: TASK-1
title: WebAssembly devices
status: To Do
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-24T14:22:00Z'
labels:
  - wasm
  - extensions
  - engine
milestone: m-18
dependencies:
  - TASK-97
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Devices (audio effects/instruments) written in any language that compiles to WebAssembly, run in paw's engine. First step of Wasm support (owner 2026-11-20: Lua extensions stay, Teal for paw's code, Wasm devices first, then Wasm API extensions). Needs: a runtime choice (wasmtime/wasmer), the audio-thread rules (no lock, no allocation, no wait), a device ABI, sandboxing, a spike with numbers.
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
Owner 2026-11-22 accepted the review's recommendations: see 'Owner decisions' at the end of backlog/docs/designs/architecture-review.md.

Product owner review 2026-11-22: depends on TASK-97 (DeviceProvider), as the review says (do TASK-97 before TASK-1).
<!-- SECTION:NOTES:END -->
