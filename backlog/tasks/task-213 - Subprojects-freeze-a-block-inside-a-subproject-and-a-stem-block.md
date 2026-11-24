---
id: TASK-213
title: 'Subprojects: freeze a block inside a subproject and a stem block'
status: Done
assignee: []
created_date: '2026-11-23T06:36:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels:
  - nest
  - freeze
milestone: m-2
dependencies:
  - TASK-7.13
priority: medium
ordinal: 241000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-7.13 (its agent named these gaps). After TASK-7.13, :freeze on a block works only for a block of the song, in the master mode of its outputs:
- A block inside a subproject cannot be frozen.
- A block in the stems mode of :nest.outputs (pass mode) is refused; the user freezes the row instead.
- A subproject that only a resting (frozen) subproject places is not held: its devices keep running.

What to build: :freeze and :unfreeze act on a block inside a subproject (the bake is of the inner block, in the outer one's time); a stem block freezes to one file for each stem row, or the refusal message names what to do and the reference says why; a subproject placed only by resting subprojects rests too.

Read first: the notes of TASK-7.13 (branch commit b474b2bf); runtime/lua/paw/freeze_block.tl; crates/paw-core/src/freeze.rs (block_file, block_sound, block_alone); crates/paw-core/src/sync/nests.rs (Placed::resting, Played::Held); docs/reference/freezing.md and subprojects.md.

Size: M. Start after TASK-7.13 is set Done.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test: a frozen block inside a subproject renders the same as the live block (the tolerance of the freeze tests), and an edit inside makes it stale
- [x] #2 Test: :freeze on a stem block either freezes each stem or gives a message that says what to do; freezing.md says which
- [x] #3 Rust test (sync): a subproject placed only inside a frozen subproject is held, and plays again when the outer one is unfrozen
- [x] #4 freezing.md and subprojects.md say it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a8070a39ddb2e1d39, commit 6911a224 (on main 8e91e5b0, nothing to merge). Rust (paw-core): freeze::block_path/path_timing, block_alone(project, clip, through) renders a block inside a subproject through the blocks that place it; RenderOpts.through; kernel functions block_path, block_song_beat, block_beat (api/tracks.rs); sync/nests.rs: nests placed by a resting nest rest too, at any depth. Lua: freeze_block.tl keeps meta.frozen.path, key and length in the place's beats, stale() scans all tracks; freeze.lua passes the window's way in. Pass-mode stem blocks stay refused (message names the row); freezing.md says why. Tests needing the build: tests/scope.lua 'a block inside a subproject freezes where the window went in...' (AC1) and ':freeze on a stem block...' (AC2, passes with the shared binary); cargo nextest -p paw-core freeze:: and sync::tests::a_subproject_inside_a_frozen_block_rests_and_plays_again_when_unfrozen (AC3).

Merged to main in batch 15 (2f970bba); full suite and checks passed.
<!-- SECTION:NOTES:END -->
