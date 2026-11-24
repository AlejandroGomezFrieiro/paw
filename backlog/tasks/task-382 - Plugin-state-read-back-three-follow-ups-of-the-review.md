---
id: TASK-382
title: 'Plugin state read back: three follow-ups of the review'
status: To Do
assignee: []
created_date: '2026-11-24T16:31:00Z'
labels:
  - engine
  - test
  - agent:worker
dependencies: []
priority: low
ordinal: 451000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the Opus review of the stepped-plugins branch (ADR 0040).
1. An undo file across sessions: next_load_id does not read history.states(), so an old id in the undo file can be given again (session 1: ]m, u before the read back, quit; session 2: the next ]m gets the same id, and its read back writes into that dead branch step). Start last_load from the largest id in history.states().
2. timers.rs: the map_or(0, ...) fallback after try_borrow_mut and try_borrow is dead code (the next session.borrow() would panic first). Remove it or write why it is safe.
3. A test with real keys of ]m, u, then a load that sets the state at once (:plugstate.load or a factory preset).
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
