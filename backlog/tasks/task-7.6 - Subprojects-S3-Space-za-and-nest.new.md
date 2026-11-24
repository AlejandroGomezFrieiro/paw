---
id: TASK-7.6
title: >-
  Subprojects S3-S6: <Space>za and :nest.new, the return row and blocks,
  <Space>zp promotes
status: Done
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T18:59:00Z'
labels:
  - nest
  - subprojects
milestone: m-2
dependencies:
  - TASK-7.3
parent_task_id: TASK-7
priority: medium
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Combined ticket (owner, 2026-11-22): one agent builds TASK-7.6, TASK-7.7, TASK-7.8 in order, with one build, one suite run and one merge. Commit after each part.

Goal: the user adds a subproject with its own tracks in one action: the owner's case of a slow 6/8 piano section in a 4/4 metal song.

User-visible behavior (nest.md 3.7 "Making one", "The 6/8 piano section, end to end"; Q19, Q20, Q22):
- `<Space>za`, `:nest.new [name] [bars] [meter]`: over the selection, the region at the cursor, or `[bars]` (default 8) from the cursor's bar. paw adds a return row below the cursor's track with one empty block, and the window enters the subproject with one empty track (`paw.opt.nest_track`, by default an instrument track as a new project has).
- With a meter (`Ballad 8 6/8`), paw writes the meter into the song's map over the span, and the song's meter back after it, so the song's bar numbers count the section's bars.
- Inside a subproject that follows the song's tempo, `:tempo` changes the song's map at the mapped place and says so: `the song's tempo at bar 33`.
- One undo step. The message says what it did.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Section 3.7. runtime/lua/paw/nest.tl (S1a, S1b), runtime/lua/paw/tempo.tl (`:tempo`, `:timesig`), the `<Space>z` domain in runtime/lua/paw/defaults/keys.lua (V2), runtime/lua/paw/commands.tl.

Depends on: TASK-7.3, TASK-7.4.
Do not touch: own tempo and `meter=own` (TASK-7.11), drawing of blocks (TASK-7.7).

Size: M.

## Part of TASK-7.7: Subprojects S4-S5: the return row, blocks, K, :nest.list and stems

Goal: the user sees and mixes a subproject in the song: its blocks on its return row, its tracks in place, a description, a list, and stems when he wants them. Parts S4 and S5 of nest.md.

User-visible behavior (nest.md 3.7, 4.5, 4.8; Q23):
- The arrange view draws each block on the return row: a frame, the name once, a `⧉` mark, and a small view of what plays.
- `za` on the return row opens the subproject's tracks under it, in place, in the song's time. Edits there are edits of the subproject.
- `K` on a block: `nest Ballad · 6/8 · 8 bars · follows the tempo · 2 tracks · 1 instance · live`.
- `:nest.list`: the subprojects, their blocks and the unused ones; choose one to enter it.
- `:nest.outputs stems`: one return row for each subproject track, in a group under the subproject's row, made and named by the command. `:nest.outputs master` goes back to one row. One undo step each.
- The window frontend draws the same scene.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.7, 4.5, 4.8. runtime/lua/paw/views/arrange.lua (clip drawing), runtime/lua/paw/groups.tl (a fold in place), tests/arrange_scene.lua, the paw-gui arrange drawing; the S3 commit.

Depends on: TASK-7.6.
Do not touch: promote (TASK-7.8).

Size: M.

## Part of TASK-7.8: Subprojects S6: <Space>zp promotes a subproject to a view

Goal: `<Space>zp`, `:nest.promote` promotes a subproject to a view: its tracks, clips, regions, lanes, devices and the rest come back into the song, and a view takes its place in the navigation, so the user does not lose his place. One undo step. `:nest.promote!` also promotes the subprojects inside it.

What comes back: every row of the table of nest.md 3.9 (tracks in a group named after the subproject at the place of its return row; clips at song positions, cut at the block's window; markers and regions as children of a region named after it; automation, with the master's lanes on the group track and lanes combined in dB with the return row's; the same device instances, with no plugin reload; fader in dB added, pan of the return row; sends; the meter into the song's map; the key on the region as `region.key` (TASK-18 reads it); named scopes and folds translated; the subproject itself stays while other blocks play it, and goes to `unused/nests/` at save when none does). Own tempo is in TASK-7.11.

The view that remains: a scope of the group's tracks x the region's time (`Song › Ballad`). When the window was inside the subproject, it is now inside the view, at the same place.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.8 ("Regions and subprojects"), 3.9, 4.6 (`unnest`), Q8, Q21, Q24, Q27. runtime/lua/paw/nest.tl, crates/paw-core/src/session/devices.rs (device ids kept), runtime/lua/paw/markers.tl, runtime/lua/paw/scope.tl.

Depends on: TASK-7.7.
Do not touch: saving a view (TASK-7.9, TASK-7.10).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 (7.6) Test with real keys: the 6/8 example of nest.md 3.7, steps 1 to 8 (33|, <Space>za Ballad 8 6/8, :tempo 60, a piano with notes, zw, play), then a render that has the piano in bars 33 to 40
- [ ] #2 (7.6) Test: after <Space>za with 6/8, the song's map has 6/8 at bar 33 and 4/4 at bar 41
- [ ] #3 (7.6) Test: :tempo 60 inside gives the message with the song's bar, and the song's tempo map has the change
- [ ] #4 (7.6) Test: u removes the subproject, its row and the meter changes in one step
- [ ] #5 (7.6) keys.md and a subprojects reference page (new docs/reference/subprojects.md) say it; Vale 0 errors
- [ ] #6 (7.7) Test: the block is drawn with its frame, name and ⧉ in the terminal and in the scene (tests/arrange_scene.lua, paw-gui tests)
- [ ] #7 (7.7) Test with real keys: za on the return row shows the subproject's tracks under it; an edit there changes the subproject
- [ ] #8 (7.7) Test: K on a block gives the text above
- [ ] #9 (7.7) Test: :nest.outputs stems makes a row for each track; the sum of the stems renders as the stereo return did; :nest.outputs master and u restore
- [ ] #10 (7.7) subprojects.md and keys.md say it; Vale 0 errors
- [ ] #11 (7.8) Test with real keys: a subproject with two tracks, two regions, a lane on its return row and its own 6/8 meter; <Space>zp: two song tracks in a group Ballad at the row's place, the clips and regions at song positions, the lane combined, 6/8 in the song's map; the window is in the view Song › Ballad
- [ ] #12 (7.8) Test: a plugin device inside is the same instance after promote (no reload: its id and state stay)
- [ ] #13 (7.8) Test: u gives back the project before promote (the same canonical text)
- [ ] #14 (7.8) Test: a render before and after promote is the same
- [ ] #15 (7.8) subprojects.md and keys.md say it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Follow-ups (commit 500f999f, merged main f1ed4042): :nest.new with its own meter moves the rest of the song (clips, lane points, markers/regions, tempo and meter points after the section) by the difference, in the same undo step, and says 'the rest of the song moved N beats earlier/later'. Promote gives the subproject's key to the region it makes (when it differs from the song's key). Tests in tests/nest.lua with real keys; docs/reference/subprojects.md and limits.md updated. Full suite (plugins) all passed; nest and jump tests pass after the merge of main 998ab907.
<!-- SECTION:NOTES:END -->
