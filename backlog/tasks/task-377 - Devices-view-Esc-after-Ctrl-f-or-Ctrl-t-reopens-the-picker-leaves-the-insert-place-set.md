---
id: TASK-377
title: >-
  Devices view: Esc after Ctrl-f or Ctrl-t reopens the picker leaves the insert
  place set
status: To Do
assignee: []
created_date: '2026-11-24T15:31:00Z'
labels:
  - bug
  - keys
  - agent:worker
milestone: m-16
dependencies:
  - TASK-283
priority: low
ordinal: 446000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the review of the devices view keys (2026-11-24). pick_at opens the picker with a spec, and its on_cancel clears `adding`. When the user switches source with Ctrl-f or Ctrl-t, the picker opens again by name, and Esc then leaves `adding` set: a later device added from another view on the same part goes to the old place. Fix so each way of closing the picker with no choice clears it, with a real-key test.
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
