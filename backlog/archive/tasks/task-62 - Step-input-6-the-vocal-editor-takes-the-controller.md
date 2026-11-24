---
id: TASK-62
title: 'Step input 6: the vocal editor takes the controller'
status: To Do
assignee: []
created_date: '2026-11-22T04:43:00Z'
updated_date: '2026-11-22T12:38:00Z'
labels:
  - step-input
  - insert-mode
  - utau
milestone: m-4
dependencies:
  - TASK-60
priority: low
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: `I` in the vocal editor starts step input from the MIDI controller. Each key adds one note at the cursor, one step long, with the default lyric, and the cursor steps on to its end. The singing engine sings the note, as it does for a placed note.

User-visible behavior:
- The step is `2 * note_grid` (what `i` gives), or what `=` sets.
- A vocal track sings one note at a time: a chord enters its highest note, and paw says so once in the session.
- `<Space>` rests one step, `<BS>` takes the last note back, `Esc` ends. The controller's actions of TASK-60 (rest, back, dur.N) work.
- The whole insert is one undo step. Nothing enters while the transport plays.
- The lyric is the default lyric of a new note (owner decision Q8). A queue of lyrics from the lyric sheet comes later (not here).

How: the utau extension registers a target with `paw.step.target("utau", spec)`. The core knows nothing of vocals.

Read first:
- backlog/docs/designs/step-input.md: "The vocal editor", and "Owner decisions" (Q8).
- extensions/utau/lua/utau/editor.lua (`view:edit`, `view:move`, `view:toggle_note`, `view:step_note`), extensions/utau/lua/utau/editor_keys.lua (`emap`; check that `I` is free in the vocal editor), extensions/utau/lua/utau/audition.lua.
- runtime/lua/paw/step.tl and `contracts.StepTarget`.
- extensions/utau/README.md, extensions/utau/tests.lua; .claude/skills/paw-extension.

Depends on: TASK-60.
Do not touch: core files, the notation extension (TASK-61).

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test in extensions/utau/tests.lua with real keys: I, then C4 and E4 one after the other add two notes with the default lyric; the cursor is at the end of the second
- [ ] #2 Test: C4 and G4 held together add one note, G4, and the message comes once
- [ ] #3 Test: Esc, then u removes every note of the insert (one undo step)
- [ ] #4 Test: <Space> moves the cursor one step and adds nothing
- [ ] #5 extensions/utau/README.md names I in the vocal editor, and the README test passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Combined into TASK-61 (owner, 2026-11-22).
<!-- SECTION:NOTES:END -->
