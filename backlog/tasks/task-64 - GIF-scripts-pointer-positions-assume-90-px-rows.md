---
id: TASK-64
title: 'GIF scripts: pointer positions assume 90 px rows'
status: To Do
assignee: []
created_date: '2026-11-22T05:24:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - docs
  - gui
  - bug
milestone: m-13
dependencies: []
priority: low
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
docs/images/make/gui-arrange.sh and stills.sh place the pointer for 90-pixel rows, but the window's rows are about 68 px, so the Ctrl-drag copy and the double-click on the melody clip miss: gui-panes.png shows a dragged copy on the Reverb lane instead of the melody in the piano roll. Fix the scripts (or read row positions from the scene/rig row_height) and remake the stills.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 gui-arrange.sh and stills.sh take row positions from the window's row height, not 90 px
- [ ] #2 The stills are made again; gui-panes.png shows the melody in the piano roll
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board review 2026-11-23: moved from m-9 to m-13. gui-arrange.sh and stills.sh run the window (paw-gui), which is paused; this waits until the owner starts the window again.
<!-- SECTION:NOTES:END -->
