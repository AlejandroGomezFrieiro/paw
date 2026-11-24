---
id: TASK-128
title: 'Frontend: state and gestures in separate modules; shared note transforms'
status: Done
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels:
  - architecture
  - lua-review
milestone: m-4
dependencies: []
priority: medium
ordinal: 140000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Split `frontend.tl` into `frontend/state.tl` and `frontend/act/<area>.tl`; `paw.frontend.act` stays one table. Add a core Teal module `paw.notes` with pure transforms (quantize with strength, swing and lengths; legato; more as needed). The operator `edit.tl A.quantize`, the gesture `A.quantize_notes` and `musicops.quantize` call it. A gesture with a key equivalent calls the same operation as the key.

Read first: backlog/docs/designs/architecture-review-lua.md, the finding L4 and its proposal P6.

Overlaps: TASK-77.4, TASK-17.
Dependencies: none for the split; the transforms are better after P4.

Owner decisions (2026-11-22): the review's recommendations are accepted. notation and utau are not ported to Teal: they move to Rust as native extensions later (a separate ticket).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 no file of `frontend/` has more than 1 500 lines
- [ ] #2 one implementation of quantize for notes
- [ ] #3 the window tests, `tests/frontend.lua` and `tests/tuimouse.lua` pass with no change of behavior
- [ ] #4 the `musicops` README stays true
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a6746fd18e676fd66, commit 00a282ad on main 07a06cd3 (made again from main's frontend.tl; the old 78f1e4a8 is dropped). frontend.tl split into paw/frontend/: core.tl 759, host.tl, state.tl 909, dialogs.tl, act/{clips 817, notes, window, lanes, routing, tracks, timeline, tempo, devices}. paw.frontend and paw.frontend.act stay one table each. New core module paw.notes: quantize(notes, {grid, strength, swing, lengths, offset, within}); edit.tl A.quantize, ex.tl :quantize, act.quantize_notes and musicops.quantize call it. Legato not moved (no core caller). tools/apidoc.lua takes the shorter module name. Window tests not run (window paused). P6 item 3 done only for quantize.
<!-- SECTION:NOTES:END -->
