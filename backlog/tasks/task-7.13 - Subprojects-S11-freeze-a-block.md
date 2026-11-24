---
id: TASK-7.13
title: 'Subprojects S11: freeze a block'
status: Done
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-23T07:01:00Z'
labels:
  - nest
  - subprojects
  - freeze
milestone: m-2
dependencies:
  - TASK-7.3
  - TASK-7.11
parent_task_id: TASK-7
priority: medium
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: `:freeze` on a block renders what it plays into a kept file, so that its devices rest; an edit inside marks it stale.

What to build (nest.md 4.4 "Freeze", "Recursion"; Q11; media.md 2.7, 2.8 kept bakes, 2.9 scheduler):
- The bake key: `BLAKE3("paw.nest/1" ‖ canonical nest text, nests inside by their keys ‖ play ‖ tempo slice over [offset, offset+length+tail] in follow ‖ rate ‖ plugin names and versions)`. Blocks at places with the same tempo share one bake.
- The bake runs through the bake scheduler and is kept in `media/baked/` (it needs the plugins).
- A frozen block plays the file; the nest's devices rest when no live block uses them. While the bake runs, the block plays live.
- An edit inside marks it stale: `K` and the status line say so. `:unfreeze` plays it live again.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Section 4.4. backlog/docs/designs/media.md sections 2.7 to 2.9, 15; crates/paw-core/src/freeze.rs, crates/paw-core/src/bake/, docs/reference/freezing.md; the S2b and S10 commits.

Depends on: TASK-7.3 (it absorbed TASK-7.4), TASK-7.11 (it absorbed TASK-7.12). The stale state of a frozen track comes with TASK-77.9: use the same words and the same check for a block.
Do not touch: track freeze, beyond what both share.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test: a frozen block renders the same as the live block (the tolerance of the track freeze tests)
- [x] #2 Test: an edit inside makes K and the status line say stale; :freeze again makes it current
- [x] #3 Test: two blocks at places with the same tempo use one bake file
- [x] #4 Test: :unfreeze plays it live again; u works for each
- [x] #5 freezing.md and subprojects.md say it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a806bd9e2fa038b79 (reset onto the TASK-77.9 branch, main e46ecc13 merged), commits b474b2bf and merge 4c08ac70.
Rust (paw-core): freeze.rs block_file/map_block_file/block_sound/block_alone; RenderOpts.block; sync/nests.rs: a frozen block places nothing, the row plays its file as an audio clip (also inside a nest through place()), Placed::resting -> sync holds the nest's tracks (Played::Held); keep.rs and media.rs keep and relink the file. Lua: new runtime/lua/paw/freeze_block.tl (paw.freeze_block: freeze, unfreeze, frozen, describe, key, stale); :freeze/:unfreeze in freeze.lua act on the block at the cursor; status line component 'frozen' (stale: Ballad); K line in modal.lua; nest.describe ends 'frozen'. Key in Lua via bake_state (same parts and words as a frozen track), file media/baked/<name>-<id>.wav, id includes the sample rate.
Tests needing the orchestrator build: tests/scope.lua three block tests (AC1+AC4, AC2, AC3); cargo nextest -p paw-core freeze:: and sync::tests::a_frozen_block_plays_its_file_and_its_subproject_rests.
Gaps: only blocks of the song can be frozen; a pass-mode stem block is refused (freeze the row); sync render like the track freeze (no background); BLAKE3/plugin versions not in the key (Lua stamp, as TASK-77.9); a nest placed only inside a resting nest is not held.

Coordinator 2026-11-23: the branch is ready for merge and waits for the coordinator's build. Not Done until it merges.

PO 2026-11-23: the gaps have tickets: TASK-213 (a block inside a subproject, a stem block, a subproject placed only by a resting one), TASK-214 (bake in the background through the scheduler, and a key with plugin versions and state; waits for TASK-10).

PO 2026-11-23 check of main 8e91e5b0: tests/scope.lua has the three block tests (render as live with :unfreeze and u, stale in K and the status line, one bake file for two blocks at the same tempo); sync test a_frozen_block_plays_its_file_and_its_subproject_rests; freezing.md 'Frozen blocks of subprojects' and subprojects.md say it; Vale 0 on both. All criteria met. The gaps have TASK-213 and TASK-214.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged in b177b6e9. :freeze and :unfreeze act on a block of a subproject. The block plays a kept file in media/baked, its subproject rests, and an edit inside makes it stale in K and the status line. Follow-ups: TASK-213, TASK-214.
<!-- SECTION:FINAL_SUMMARY:END -->
