---
id: TASK-307
title: >-
  Piano roll UX: the default MIDI editor, designed with golden screens (PR,
  design only)
status: To Do
assignee: []
created_date: '2026-11-23T16:01:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-15
dependencies: []
references:
  - architecture/decisions/0022-modifier-stack-ux.md
  - architecture/decisions/0026-takes-and-comps-for-every-lane.md
  - architecture/decisions/0018-parts-and-typed-lanes.md
  - architecture/decisions/0003-one-view-two-frontends.md
  - backlog/docs/designs/architecture-plan.md
priority: medium
ordinal: 370000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle PR of the architecture plan, version 2 (backlog/docs/designs/architecture-plan.md V2.10 m-15, V2.15). The owner (round 5.4): the piano roll is the default MIDI editor, not the only one, and its UX needs its own refinement. The owner puts UX first: study real screens and make golden screens before a build.

Design only. No code. The result is a design document in backlog/docs/designs/ for the owner. TASK-75.5 (M5) builds on it.

Read first: the skill .claude/skills/architecture (after batch 19 it is on main), architecture/08-concepts.md and 13-roadmap.md, the ADRs in the references, and backlog/docs/designs/architecture-plan.md (the sections that this ticket names). An Opus agent does the whole bundle in one branch, with its tests and docs in the same commits. Also docs/reference/piano-roll.md, docs/reference/key-rule.md and backlog/docs/designs/midi-modifier-stacks.md.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A study of the piano roll today from real screens (scratchpad/screens/shots.lua), with what to keep and what to change
- [ ] #2 Golden screens (text, at 80 and 120 columns) for: the ink and the ghosts of a stack (\m), the takes and the comp of a MIDI lane, the lyrics and the producer controls of a note, and a second editor of the same clip kind
- [ ] #3 Keys for each new action under the key rule, with each conflict listed
- [ ] #4 A design document in backlog/docs/designs/ with the questions for the owner, each with a recommendation
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
Lane heads, for PR2: reuse the pieces name, badge, value and ctx:line for the roll's lane names, not the paw.heads registry (design: backlog/docs/designs/lane-heads.md)

Time motions (ADR 0036 proposed, backlog/docs/designs/time-motions.md): LA a lane kind declares its time base and atom, lane rows use paw.timegrid and the motion layer; TK take and comp edges are objects for w/b/e, comp ranges exact; VD grid=frame and the frame atom; PR1 the roll's grid follows the song's bars, cursor in song ticks (TASK-329).

PO 2026-11-23: time motions (ADR 0036, proposed; backlog/docs/designs/time-motions.md 3.1 and 8): the piano roll's grid and cursor go to song ticks (TM3, TASK-329). Design the roll on paw.timegrid and the motion rules, and show an off-grid note in its cell in the golden screens.
<!-- SECTION:NOTES:END -->
