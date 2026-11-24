---
id: TASK-320
title: >-
  Video lanes and the monitor view: half blocks or kitty graphics, thumbnails in
  the arrange view (VD)
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-24T14:22:00Z'
labels:
  - agent:builder
milestone: m-18
dependencies:
  - TASK-316
  - TASK-23
references:
  - architecture/decisions/0023-video-in-the-terminal.md
  - architecture/decisions/0018-parts-and-typed-lanes.md
  - architecture/decisions/0003-one-view-two-frontends.md
priority: low
ordinal: 387000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle VD of backlog/docs/designs/architecture-plan.md V2.7 step 11 (phase 6). A lane of base video. A monitor view draws frames with half blocks, or with the kitty graphics protocol where the terminal has it; the arrange view shows a video lane with clip names, times and thumbnails where images work (ADR 0023). A change of paw-scene can stop the build of the paused window: report it.

This ticket has a title and a description only. The product owner adds the acceptance criteria when its phase starts, from backlog/docs/designs/architecture-plan.md and the ADRs in the references. One Opus agent does the bundle.
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Lane heads: the head video (design: backlog/docs/designs/lane-heads.md)

Time motions (ADR 0036 proposed, backlog/docs/designs/time-motions.md): LA a lane kind declares its time base and atom, lane rows use paw.timegrid and the motion layer; TK take and comp edges are objects for w/b/e, comp ranges exact; VD grid=frame and the frame atom; PR1 the roll's grid follows the song's bars, cursor in song ticks (TASK-329).
<!-- SECTION:NOTES:END -->
