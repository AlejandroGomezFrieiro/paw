---
id: TASK-176
title: 'Linked clips: the roll''s bend marks and A.move_note on a transposed copy'
status: Done
assignee: []
created_date: '2026-11-22T23:10:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels: []
milestone: m-2
dependencies:
  - TASK-85.2
priority: low
ordinal: 188000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-85.2 (branch worktree-agent-a6db0e3056f0f0243). In the piano roll of a copy with a transpose override, roll_draw's bend marks and the legacy A.move_note in frontend.tl still use the stored pitches, so a note's own bend mark may not show. Use Clip:shifted (objects.tl) there too. Also: notes() leaves out a note that the transpose pushes outside 0-127, so a list index is not the clip's index; check the callers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A note's bend mark shows on its played pitch in a transposed copy, by a test with real keys
- [x] #2 A move of a note in a transposed copy through A.move_note (frontend/act/notes.tl) moves it from its played pitch, by a test
- [x] #3 A note that the transpose pushes outside 0 to 127 does not shift the index of the notes after it for the callers of notes(), by a test
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done on branch worktree-agent-a4781f0e5876bd46a, commit 6e5f5911 (on main 8e91e5b0). roll_draw reads/writes controls and notes through the part's shifted handle (also fixed: the pencil stored the played pitch on a transposed copy). A.move_note and drag/stretch held notes use the clip's transpose. Clip:notes always returns places; new Clip:note(place). Callers that indexed by list position fixed (act/notes gestures, pianoroll view:change, edit put). Tests: 3 in tests/clip_overrides.lua, all fail on main's runtime. Lua/Teal only; no Rust.

Possible flake seen by the agent: tests/strips.lua 'an audio clip's waveform is a strip under its cells' failed once in three 'roll' runs and passed alone. Not proven. Watch it in the batch 15 check.

Merged to main in batch 15 (2f970bba); full suite and checks passed.
<!-- SECTION:NOTES:END -->
