---
id: TASK-234.2
title: Warp markers at the onsets of a clip, in one command
status: To Do
assignee: []
created_date: '2026-11-23T07:13:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-S
  - media
  - ux
milestone: m-14
dependencies:
  - TASK-234.1
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-234
priority: medium
ordinal: 290000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** One command puts a warp marker at each hit of a clip, so that `:clip.warp snap` then moves the hits to the grid.

**What to build.** `:clip.warp onsets [sensitivity]` puts a warp marker at each onset of the clip (in its time range). A count or `+` and `-` in the adjust panel (`<Space>.`) changes the sensitivity, and the markers change with it (one undo step for the whole command). The message says how many markers it put. `K` on the clip describes the markers.

**Core or extension.** Core: it extends `:clip.warp`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: :clip.warp onsets on a generated drum clip puts one marker per hit, and u removes all of them in one step
- [ ] #2 Test with real keys: <Space>. then + changes the sensitivity and the count of markers changes; Esc keeps the last result
- [ ] #3 The message gives the count of markers; a clip with no onset gives a clear message
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
