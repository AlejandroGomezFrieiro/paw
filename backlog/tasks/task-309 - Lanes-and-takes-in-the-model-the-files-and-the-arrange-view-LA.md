---
id: TASK-309
title: Lanes and takes in the model, the files and the arrange view (LA)
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-24T14:20:00Z'
labels:
  - agent:builder
  - architecture
  - lanes
  - bundle
milestone: m-17
dependencies:
  - TASK-306
  - TASK-323
references:
  - architecture/decisions/0018-parts-and-typed-lanes.md
  - architecture/decisions/0019-lanes-are-the-truth.md
  - architecture/decisions/0026-takes-and-comps-for-every-lane.md
  - architecture/decisions/0032-project-folder-of-parts-and-lanes.md
priority: high
ordinal: 375000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle LA of backlog/docs/designs/architecture-plan.md V2.2, V2.5, V2.6 and V2.7 step 3 (phase 3). Part.clips becomes lanes, one for each clip kind, each with takes (Role::Source). clip.meta.takes becomes takes of the lane; the comp of takes.tl becomes a Comp. The folder gets lanes/<lane>/takes/<take>/ (ADR 0032). The arrange view draws lanes under the part header. The engine does not change: the sync gives the same clip list. paw.api.part_get gives lanes. A lane has a Stack field (M4 runs it). Render of M1 makes a source take with provenance from now on. LA also rewrites docs/explanation/about-midi-as-the-truth.md as lanes are the truth (ADR 0019, D4). Merge LA before B3: both change the project folder code.

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
Lane heads (HD, TASK-323) merges first: lane and merged rows on heads, default.part and default.lane, :lane.head (meta.head, one undo step), za on a part row (design: backlog/docs/designs/lane-heads.md)

Rows build on the one time axis (ADR 0035, TASK-325): no row computes a column from a beat on its own.

Time motions (ADR 0036 proposed, backlog/docs/designs/time-motions.md): LA a lane kind declares its time base and atom, lane rows use paw.timegrid and the motion layer; TK take and comp edges are objects for w/b/e, comp ranges exact; VD grid=frame and the frame atom; PR1 the roll's grid follows the song's bars, cursor in song ticks (TASK-329).

PO 2026-11-24: from D4 (TASK-302): tools/website/landing.md keeps the heading 'MIDI is the truth' and the link to about-midi-as-the-truth.md. When LA rewrites that page, change the landing heading too.
<!-- SECTION:NOTES:END -->
