---
id: TASK-385
title: 'Bug: the ruler draws a meter change two cells after the bar where it starts'
status: To Do
assignee: []
created_date: '2026-11-24T17:38:00Z'
labels:
  - bug
  - ux
  - tui
  - agent:worker
milestone: m-15
dependencies: []
priority: high
ordinal: 454000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Screenshot: backlog/assets/ruler-meter-misaligned.png

A 6/8 section starts at bar 47. The section row, the cursor and the grid line of bar 47 start at one column, but the ruler's meter marker (a double bar and '6...') is about two cells to the right, after the bar number '47'. The owner (2026-11-24): this kind of ruler, cursor and grid misalignment is very disorienting.

Likely cause: the time axis (runtime/lua/paw/axis.tl, tools/zoomlint.lua) gives one column, and the ruler then moves the marker sideways so that it does not cover the bar number. Check this first.

Rule to keep: every mark that names a time (ruler ticks and bar numbers, meter and tempo markers, section and region starts, clip edges, the cursor, the playhead, the loop and time selection edges) is drawn at the column the time axis gives for that time. When a label does not fit there, the label moves or shortens; the mark itself never moves.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The meter marker of the screenshot's case sits in the column of bar 47 (a golden screen with a meter change at a bar whose number is drawn)
- [ ] #2 A test walks one screen with meter changes, tempo changes, sections, clips, the cursor and the playhead at several zoom levels, and checks for each mark that its column equals axis column(time); it reads the frame, not the code
- [ ] #3 When the marker and the bar number collide, the bar number (or the marker's text) gives way, never the marker's column
- [ ] #4 Any other mark that the new test finds off its column is fixed in this ticket or filed with its case
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
