---
id: TASK-193
title: >-
  paw-gui: the glyph test and two comments name the arrange modules' old .lua
  paths
status: To Do
assignee: []
created_date: '2026-11-23T01:56:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels: []
milestone: m-13
dependencies: []
priority: low
ordinal: 205000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-127 (2026-11-23) moved runtime/lua/paw/views/arrange.lua, views/arrange_mouse.lua and roles/arrange.lua to .tl. crates/paw-gui/src/gestures.rs:779-780 include_str!s the old paths in a #[cfg(test)] glyph test, so it will not compile; gestures.rs:208 and timeline.rs:1 name them in comments. The window is paused: do this when the work on the window starts again. Check the piano roll paths too after TASK-126.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 cargo test -p paw-gui compiles with the .tl paths
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
