---
id: TASK-313
title: >-
  Built-in clip kinds through the public API: the arrange view draws every clip
  kind by its look (B6)
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-10
dependencies:
  - TASK-306
  - TASK-309
references:
  - architecture/decisions/0010-extension-clip-kinds.md
  - architecture/decisions/0018-parts-and-typed-lanes.md
priority: medium
ordinal: 380000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle B6 of backlog/docs/designs/architecture-plan.md V2.11 (phase 4). The built-in clip kinds (midi, audio, nest, curve) draw through the same API as the clip kinds of extensions, so there is one path in the arrange view. TASK-23 parts B2, B3 and E1 move here. Do not run it beside TK: both change views/arrange*.tl.

This ticket has a title and a description only. The product owner adds the acceptance criteria when its phase starts, from backlog/docs/designs/architecture-plan.md and the ADRs in the references. One Opus agent does the bundle.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 (from TASK-23 AC 2, parts B2 and E1) A comments clip shows its look in the arrange view; K and Enter work (test with real keys)
- [ ] #2 (from TASK-23 AC 6, part B3) A part kind with clip_kind makes lanes of that clip kind; a part kind with no strip makes a folder that does not sum (test)
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
PO 2026-11-23 (plan V2 bundles): AC 1 and 2 came from TASK-23 (parts B2, E1 and B3). The product owner adds the rest of the criteria when phase 4 starts.

Lane heads: the heads curve, tempo and the nest return row through the public API; the header halves of draw_lane_row and draw_tempo_row leave arrange.tl (design: backlog/docs/designs/lane-heads.md)
<!-- SECTION:NOTES:END -->
