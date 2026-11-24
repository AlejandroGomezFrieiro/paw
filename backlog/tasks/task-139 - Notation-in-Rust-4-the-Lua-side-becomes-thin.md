---
id: TASK-139
title: 'Notation in Rust 4: the Lua side becomes thin'
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
  - TASK-136
  - TASK-137
  - TASK-138
priority: low
ordinal: 151000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After N1 to N3, the Lua part of notation keeps only keys, commands, views and popovers: keys.lua, part_keys.lua, tui.lua, gui.lua, popover.lua, operators.lua, step.tl. Port the Lua that stays to Teal where it is more than glue. Delete the Lua that moved.

Read first: the design note of TASK-135, backlog/docs/designs/architecture-review-lua.md (L10), backlog/docs/designs/architecture-review.md (E1, E6, owner decisions), and the README of the extension.

Rules: MIDI is the truth (the extension keeps its own data in meta and never owns clip data); the project opens and plays without the extension; keys, commands and views stay in Lua over the paw API (rule 2: one view, two frontends); each action is one undo step with a message; a key stays well under 100 ms.

Owner, 2026-11-22: do not start. This milestone is planned and refined only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No Lua module of notation does music logic that the Rust side also does (a review list in the ticket notes)
- [ ] #2 All notation tests pass; the README and doc/ pages name every command and key, and Vale reports 0 alerts
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
