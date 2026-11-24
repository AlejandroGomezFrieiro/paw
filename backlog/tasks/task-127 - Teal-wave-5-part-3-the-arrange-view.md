---
id: TASK-127
title: 'Teal wave 5, part 3: the arrange view'
status: Done
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels:
  - architecture
  - lua-review
milestone: m-2
dependencies:
  - TASK-125
priority: medium
ordinal: 139000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port `views/arrange.lua`, `views/arrange_mouse.lua` and `roles/arrange.lua`. Split `view:render` (352 lines) and `header` (208 lines) by part. Delete the 5 stand-in `Arrange` records.

Read first: backlog/docs/designs/architecture-review-lua.md, the finding L3 and its proposal P5.

Overlaps: TASK-22.
Dependencies: P3.

Owner decisions (2026-11-22): the review's recommendations are accepted. notation and utau are not ported to Teal: they move to Rust as native extensions later (a separate ticket).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 as P3, for these files
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a0be6114b9e664f3b, commit 8e635f8c (on merge d717f1e3 of TASK-184). views/arrange, views/arrange_mouse, roles/arrange ported to Teal; new views/arrange_track.tl (header parts and clips). render 352 -> 73 lines, header 208 -> 63. Shared types in contracts.tl: ArrangeView, ArrangeLayer, ArrangeGeometry, LabelMark, ButtonMark, SwitchMark, KnobMark, PlayheadMark. Stand-ins removed in scope, ex, diagnostic, vzoom, pick/project, pick/sources. mouse.Handlers is now an interface. 0 any / 0 Untyped in new modules; any-allowed.txt stays 54. Tests (arrange, clip, track column, scope, fold, lane, tempo, frontend) pass unchanged. paw-gui gestures.rs:779-780 include_str needs .tl paths when the window restarts.

Merged batch 8 (f5adec5e) as e0fe4054: welcome page of TASK-168 ported to arrange.tl; pianoroll uses contracts.ButtonMark/PlayheadMark; layers-allowed moved 1 frontend read to views.arrange_track. Words pass except two failures that come from the batch: api_boundary empty-path save (TASK-157 needs a new binary) and 5 layer problems of the piano roll.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
