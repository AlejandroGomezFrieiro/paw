---
id: TASK-119
title: 'Takes: the take mark wins over the clip''s name when a clip is short'
status: Done
assignee: []
created_date: '2026-11-22T16:55:00Z'
updated_date: '2026-11-22T20:23:00Z'
labels:
  - takes
  - ux
milestone: m-4
dependencies: []
priority: high
ordinal: 131000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-117: at the default zoom a one-bar clip shows only 'take 1', because its label is cut before the ‹n/m› mark, so ]t and [t show no change on the clip itself. Give the take mark priority: when the label does not fit, show ‹n/m› first, then as much of the name as fits; the same in the window's clip role.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Real-keys test: a one-bar clip with 3 takes at the default zoom shows ‹1/3›, and ]t changes it to ‹2/3›
- [ ] #2 The window's scene has the same text (scene_parity passes)
- [ ] #3 Docs (takes.md) say what the mark shows; Vale 0
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done on branch worktree-agent-ac0109f9a6a0ca196 (commits a25b992c, merge of main 537e71a6, regen). The clip role gets the take mark as its own prop 'mark'; the terminal role (runtime/lua/paw/roles/arrange.lua) and the window (paw-gui timeline.rs) draw 'label ‹n/m›', or '‹n/m› label' where both do not fit. Test: tests/roughedges.lua (one-bar clip, 3 takes, ]t). scene_parity covers a short clip with takes. docs/reference/takes.md has 'The take mark'. Checks: build, tlcheck, apidoc check, fmtcheck, luacheck, Vale 0, suite only roughedges scene_parity takes, cargo test paw-scene paw-gui. Full suite not run (new owner rule: orchestrator runs it).

Merged to main in 7ae25570 (batch 1, 2026-11-22): dev build, full suite with plugins passed, nextest paw-core/paw-scene passed.
<!-- SECTION:NOTES:END -->
