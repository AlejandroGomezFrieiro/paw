---
id: TASK-138
title: 'Notation in Rust 3: MusicXML, LilyPond and the files'
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
priority: low
ordinal: 150000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Move import and export to Rust: musicxml.lua (2,052 lines), lilypond.lua, write.lua, export.lua, files.lua. A Rust crate for MusicXML can replace the hand-written reader; check what crates exist (rust-skills, paw-crates.md).

Read first: the design note of TASK-135, backlog/docs/designs/architecture-review-lua.md (L10), backlog/docs/designs/architecture-review.md (E1, E6, owner decisions), and the README of the extension.

Rules: MIDI is the truth (the extension keeps its own data in meta and never owns clip data); the project opens and plays without the extension; keys, commands and views stay in Lua over the paw API (rule 2: one view, two frontends); each action is one undo step with a message; a key stays well under 100 ms.

Owner, 2026-11-22: do not start. This milestone is planned and refined only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tests_musicxml passes unchanged, and each fixture gives the same file bytes or a documented difference
- [ ] #2 The export commands of the README work as before
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
