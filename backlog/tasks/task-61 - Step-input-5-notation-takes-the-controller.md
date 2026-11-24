---
id: TASK-61
title: 'Step input 5-6: notation and the vocal editor take the controller'
status: Done
assignee: []
created_date: '2026-11-22T04:43:00Z'
updated_date: '2026-11-22T16:14:00Z'
labels:
  - step-input
  - insert-mode
  - notation
milestone: m-4
dependencies:
  - TASK-60
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Combined ticket (owner, 2026-11-22): one agent builds TASK-61, TASK-62 in order, with one build, one suite run and one merge. Commit after each part.

Goal: in notation, every insert mode (`i`, `a`, `I`, `R`) takes notes from the MIDI controller at the pitch played. Chords come from keys held together. `R` changes the pitch of the next note and keeps the rhythm. `I` pushes later music along.

User-visible behavior:
- A key played enters a note at the caret with the chosen value. A key that comes while another is held joins the chord. The release of the last key steps on.
- The spelling comes from the key of the music: in F major, pitch 70 is Bb, not A#.
- The controller's actions (TASK-60) work: rest, tie, back, dur.N, dot, triplet.
- Nothing enters while the transport plays. All of one insert is one undo step, as with the computer keys.

How:
- The notation extension registers a target with `paw.step.target("notation", spec)`: `active` is true in notation's insert modes, `track` is the track of the clip shown, `note` calls a new `view:enter_pitch(pitch, advance)` (as `view:enter(letter, advance)` does, with the pitch played, not the nearest octave), `release` steps on, `actions` map to `enter_rest`, `tie_last`, `backspace`, the value keys `2` to `7`, `.` and `t`.

Read first:
- backlog/docs/designs/step-input.md: "Notation", and "Owner decisions" (Q2: every insert mode takes the controller).
- extensions/notation/lua/notation/init.lua: `view:enter` (near line 1859), `view:tie_last` (1951), `view:enter_rest` (1991), `view:backspace` (2043); the key's spelling in notation's model (`key_pitch`).
- extensions/notation/lua/notation/keys.lua: the insert keys (near lines 926 to 943) and `enter_mode` (near line 1379).
- runtime/lua/paw/step.tl and `contracts.StepTarget` (with the actions of TASK-60).
- extensions/notation/README.md and extensions/notation/doc/reference.md; .claude/skills/paw-extension.
- tests/step_input.lua (how to inject from a test port).

Depends on: TASK-60.
Do not touch: runtime/lua/paw/step.tl (except a fix agreed in TASK-60's ticket), the utau extension (TASK-62).

Size: M.

## Part of TASK-62: Step input 6: the vocal editor takes the controller

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
- [ ] #1 (61) Test in the notation extension (a tests_*.lua file) with real keys: i, then C4, E4 and G4 held and released enter one chord, and the caret steps on; D4 after it is the next note; Esc; u removes all as one step
- [ ] #2 (61) Test: in R, a key changes the pitch of the next note and its rhythm stays
- [ ] #3 (61) Test: in I, a key pushes the later music along by the value
- [ ] #4 (61) Test: in F major, pitch 70 is written Bb
- [ ] #5 (61) Test: the pedal (TASK-60's default) with no key held enters a rest
- [ ] #6 (61) extensions/notation/README.md or doc/reference.md says it, and the test that checks that the README names every key and command passes
- [ ] #7 (62) Test in extensions/utau/tests.lua with real keys: I, then C4 and E4 one after the other add two notes with the default lyric; the cursor is at the end of the second
- [ ] #8 (62) Test: C4 and G4 held together add one note, G4, and the message comes once
- [ ] #9 (62) Test: Esc, then u removes every note of the insert (one undo step)
- [ ] #10 (62) Test: <Space> moves the cursor one step and adds nothing
- [ ] #11 (62) extensions/utau/README.md names I in the vocal editor, and the README test passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a2c52a4785e38b148: 4cd4122e (notation, part 61), then the utau commit (part 62). Notation: extensions/notation/lua/notation/step.tl, tests_step.lua. Utau: extensions/utau/lua/utau/step.tl, tests in tests.lua.
<!-- SECTION:NOTES:END -->
