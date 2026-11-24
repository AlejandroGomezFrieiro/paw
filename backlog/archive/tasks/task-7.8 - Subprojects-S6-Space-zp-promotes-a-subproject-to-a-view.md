---
id: TASK-7.8
title: 'Subprojects S6: <Space>zp promotes a subproject to a view'
status: To Do
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T12:38:00Z'
labels:
  - nest
  - subprojects
milestone: m-2
dependencies:
  - TASK-7.7
parent_task_id: TASK-7
priority: medium
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
- [ ] #1 Test with real keys: a subproject with two tracks, two regions, a lane on its return row and its own 6/8 meter; <Space>zp: two song tracks in a group Ballad at the row's place, the clips and regions at song positions, the lane combined, 6/8 in the song's map; the window is in the view Song › Ballad
- [ ] #2 Test: a plugin device inside is the same instance after promote (no reload: its id and state stay)
- [ ] #3 Test: u gives back the project before promote (the same canonical text)
- [ ] #4 Test: a render before and after promote is the same
- [ ] #5 subprojects.md and keys.md say it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Combined into TASK-7.6 (owner, 2026-11-22).
<!-- SECTION:NOTES:END -->
