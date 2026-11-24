---
id: TASK-142
title: 'utau in Rust 3: the Lua side becomes thin, and the engine question'
status: To Do
assignee: []
created_date: '2026-11-22T19:05:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - rust-port
  - extensions
milestone: m-11
dependencies:
  - TASK-135
  - TASK-140
  - TASK-141
priority: low
ordinal: 154000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After U1 and U2, the Lua part of utau keeps only keys, commands and views (editor_keys.lua, gui*.lua, strips.lua, step.tl). Write down, for the owner, whether the engine itself should move from C# to Rust: OpenUtau.Core is C#, so this is a rewrite of its phonemizers and renderers or a new engine. Recommendation to give with the facts: keep the C# engine.

Read first: the design note of TASK-135, backlog/docs/designs/architecture-review-lua.md (L10), backlog/docs/designs/architecture-review.md (E1, E6, owner decisions), and the README of the extension.

Rules: MIDI is the truth (the extension keeps its own data in meta and never owns clip data); the project opens and plays without the extension; keys, commands and views stay in Lua over the paw API (rule 2: one view, two frontends); each action is one undo step with a message; a key stays well under 100 ms.

Owner, 2026-11-22: do not start. This milestone is planned and refined only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No Lua module of utau does logic that the Rust side also does
- [ ] #2 A short note for the owner on the engine (C# or Rust), with the size of the work
- [ ] #3 The README names every command and key; Vale reports 0 alerts
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
