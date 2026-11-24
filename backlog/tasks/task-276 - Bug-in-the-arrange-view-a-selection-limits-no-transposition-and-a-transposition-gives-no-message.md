---
id: TASK-276
title: >-
  Bug: in the arrange view, a selection limits no transposition, and a
  transposition gives no message
status: Done
assignee: []
created_date: '2026-11-23T08:26:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels:
  - bug
  - ux
milestone: m-2
dependencies: []
priority: high
ordinal: 338000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while making the tour GIF (2026-11-23). In the arrange view, vib then 12<C-a> transposes the whole clip, not only the selected bar (checked headless: all 12 notes went up 12). No message says what changed (the status line kept 'pasted 16 beats'). Each clip's small piano roll scales to its own pitch range, so the change does not show on screen either.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With a time selection in the arrange view, <C-a>/<C-x> and + - change only the notes inside it (test with real keys)
- [x] #2 Every transposition gives a message: how many notes, by how much, in which clips
- [x] #3 Test with real keys: without a selection, <C-a> on a clip still transposes the whole clip by one semitone; a count (12<C-a>) moves by 12
- [x] #4 keys.md and the arrange reference say what a selection limits; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done on branch worktree-agent-a6c27a309fe2eab7d, commit 8e35affd (on main 23350734). The cause was edit.arrange.transpose (runtime/lua/paw/edit.tl), not only clip.transpose: the visual keys already gave it the selection, but it moved every note of each clip that reached into the region. Now it moves the notes that start in the region (a looped clip's note when a repeat starts there; whole tracks and clips chosen one by one keep every note) and says 'moved 4 notes up 12 semitones in Keys' (names up to three clips, else a count), or warns 'no notes to move there'. clip.transpose gives the clip as region.clips, so the classic <C-a> and :clip.transpose move the whole clip. AC3 note: with the default keys, <C-a> without a selection is the track volume by the key rule; only the classic keys transpose the clip, so the test uses paw.opt.keys = classic. Test: tests/modal.lua 'a transposition in the arrange view moves the notes of the selection only...', golden tests/screens/modal/transpose_a_bar.txt. Docs: keys.md, arrange-view.md.

Merged to main in batch 16 (cd367da1); full suite and checks passed after three merge fixes.
<!-- SECTION:NOTES:END -->
