---
id: TASK-77.4
title: 'Derived D4: The GUI state'
status: To Do
assignee: []
created_date: '2026-11-22T15:23:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - performance
  - derived
milestone: m-13
dependencies:
  - TASK-77.1
parent_task_id: TASK-77
priority: low
ordinal: 123000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
D4 of the derived-data design. `frontend.state` keeps an entry for each track as a node with the track's fields and its clips' keys as the key; the transport and modes stay as they are. Find why an arrange frame after `frontend.state` costs 9 to 17 ms.

Read first: backlog/docs/designs/derived.md, part 4 (the design) and row D4 of part 5; part 2 (inventory) and part 3 (measurements) for the consumer.

Owner decisions (2026-11-22): the design is approved; Q1 no mark in the views (the status line shows the job only after 1 s, K on a chord says "reading"); Q2 paw.derived stays internal in D1 to D5 and becomes public in D6; Q3 no user option for memory, fixed limits per kind shown by :checkhealth derived.

Measure with the spread, on the bench project, against main at the time, measured under external load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: After a note edit, `frontend.state` makes one track entry (`stats().made` = 1). `cargo test --release -p paw-gui` passes.
- [ ] #2 Number to meet: `frontend.state` after a note edit: 3 ms or less (12 to 41 ms today).
- [ ] #3 Docs follow the change; Vale reports 0 alerts
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
