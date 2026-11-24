---
id: TASK-332
title: >-
  Arrange ruler and lanes: the playhead cap keeps the bar number visible, and
  lane points draw over grid lines
status: To Do
assignee: []
created_date: '2026-11-23T20:18:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:worker
milestone: m-15
dependencies: []
priority: low
ordinal: 401000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-325: the playhead cap on the ruler hides the bar number when the playhead stands on it (2 at zoom 2), and a lane point in the same cell as a bar line is hidden under the line (4.375 at zoom 2). Data draws over decoration: points over grid lines; the cap does not hide the label (for example the label stays and the cap goes to the tick row). Before/after screens and goldens.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A golden screen with the playhead on a bar shows the bar number
- [ ] #2 A golden screen with a lane point on a bar line shows the point
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
