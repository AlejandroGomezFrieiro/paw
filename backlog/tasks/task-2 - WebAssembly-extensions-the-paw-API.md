---
id: TASK-2
title: WebAssembly extensions (the paw API)
status: To Do
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-24T14:22:00Z'
labels:
  - wasm
  - extensions
milestone: m-18
dependencies:
  - TASK-1
priority: low
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extensions written in languages that compile to Wasm calling the paw API (commands, keys, views, hooks), after Wasm devices. Typed bindings generated from the same source as paw.d.tl. Depends on: WebAssembly devices.
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
Architecture review 2026-11-22 (backlog/docs/designs/architecture-review.md, E4 and E6): a smaller first step than the whole API: WebAssembly bakers, a third adapter of bake::Bake (scheduler.rs:75; Native and Helper today, media.md 2.9): an extension's render op as a module export, run on worker threads, portable to the web where helpers do not exist. TASK-104 (needs in manifests) is the declarative half of capabilities; real limits come from the imports a Wasm extension gets. Recommended: no Rust dylib extensions in the kernel (no stable ABI).
<!-- SECTION:NOTES:END -->
