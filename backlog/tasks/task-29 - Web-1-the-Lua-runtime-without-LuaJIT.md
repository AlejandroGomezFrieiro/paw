---
id: TASK-29
title: 'Web 1: the Lua runtime without LuaJIT'
status: To Do
assignee: []
created_date: '2026-11-21T19:32:00Z'
updated_date: '2026-11-23T16:15:00Z'
labels:
  - web
  - wasm
  - lua
milestone: m-0
dependencies:
  - TASK-45
priority: medium
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run runtime/lua/paw and the bundled Lua/Teal extensions on the VM chosen in Web 0; replace or gate FFI uses (dsp.lua, others) with portable code; keep the native build on LuaJIT. The Lua suite passes on the portable VM natively first (a cargo feature), so the browser build has a test bed.
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
Product owner review 2026-11-22: depends on TASK-45. Both change the FFI of dsp.lua; TASK-45 makes it portable first.
<!-- SECTION:NOTES:END -->
