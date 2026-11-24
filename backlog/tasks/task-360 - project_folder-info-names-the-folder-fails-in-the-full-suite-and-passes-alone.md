---
id: TASK-360
title: >-
  project_folder: ':info names the folder' fails in the full suite and passes
  alone
status: Done
assignee: []
created_date: '2026-11-24T12:25:00Z'
updated_date: '2026-11-24T14:15:00Z'
labels:
  - bug
  - tests
  - agent:worker
dependencies: []
priority: high
ordinal: 429000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Full suite on main c3157735 (2026-11-24, nextest runner): tests/project_folder.lua:603 ':info names the folder: got false, want true'. Alone (suite.sh only "imported as a part that refers to it") it passes. The assertion searches a 120x40 ui_snapshot for the whole folder path (lib .. '/parts/Lead'); the comment says a long path goes on the line under its label. Suspect: the path length (scratch names now carry the part name, and the full run's scratch differs) makes the path wrap or be cut, so the result depends on the machine's folder names. A test must not depend on the length of a path: assert on what :info holds (a field, or the path read back after joining wrapped lines), not on a screen search. Also check whether :info itself cuts a long path (a UX bug).
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
On local main 88f1462d (2026-11-24). Cause: :info hard-wraps a long path; the test searched one line for the whole path, so a long TMPDIR failed it. The test reads the path across wrapped rows. :info shows every character. Follow-up idea (low): wrap long paths at '/'.
<!-- SECTION:NOTES:END -->
