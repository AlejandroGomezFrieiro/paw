---
id: TASK-63
title: 'Step input 7: how-to, reference and tutor'
status: Done
assignee: []
created_date: '2026-11-22T04:43:00Z'
updated_date: '2026-11-22T13:27:00Z'
labels:
  - step-input
  - insert-mode
  - docs
milestone: m-4
dependencies:
  - TASK-60
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: a musician finds out how to enter notes from a MIDI keyboard, one note or chord at a time, and finds every key and command of step input in the reference.

What to write:
- A how-to guide: docs/how-to/enter-notes-from-a-midi-keyboard.md, with its test in tests/guides_howto.lua (the steps run with notes injected from a test port). It covers: choose the input of the track, `I`, play notes and chords, `=` for the value, `<Space>` rests, `<BS>`, the pedal, `:step.learn` for a pad, `Esc`. It links the notation and vocal editor READMEs where TASK-61 and TASK-62 are merged.
- docs/reference/piano-roll.md: the step input section complete (keys, the title, `step_velocity`, `:step.input`, `:step.learn`, `:step.controls`, the pedal default).
- docs/reference/keys.md (rows for `I` in the piano roll), docs/reference/options.md (`step_velocity`), a link from docs/reference/midi.md and from docs/how-to/connect-a-midi-keyboard.md.
- A step in the tutor's piano roll lesson (extensions/tutor/lua/tutor/lessons/pianoroll.lua). Make the course again with the generator; do not edit docs/tutorials/course by hand.
- The key bar lines of step input (runtime/lua/paw/keybar.lua), if TASK-58 did not add them.
- docs/README.md lists the new guide.

Read first: .claude/skills/diataxis-docs and .claude/skills/plain-writing (external pages use plain writing); backlog/docs/designs/step-input.md; the commits of TASK-58 and TASK-60; tests/guides_howto.lua (the form of a guide test); extensions/tutor/tests.lua.

Depends on: TASK-60.
Do not touch: code, except keybar.lua lines.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 docs/how-to/enter-notes-from-a-midi-keyboard.md exists, and its steps run in tests/guides_howto.lua
- [ ] #2 piano-roll.md, keys.md, options.md and midi.md tell about step input; docs/README.md lists the guide
- [ ] #3 The tutor lesson has a step input step; extensions/tutor/tests.lua passes; the course is generated again
- [ ] #4 nix develop -c tools/vale.sh on the changed files reports 0 errors
- [ ] #5 The report gives the search for old words (roll_insert, notes.step_input, 'as a piano') in README.md, docs/, extensions and .claude/skills, and no stale sentence is left
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a37e8dab1b12bad73, commit e8b8e093 (main merged after). New how-to enter-notes-from-a-midi-keyboard.md with test in tests/guides_howto.lua; links in connect guide, midi.md, docs/README.md; tutor pianoroll lesson has two step input steps; course regenerated. Reference (piano-roll, keys, options) and keybar were already done by TASK-57/58/60.
<!-- SECTION:NOTES:END -->
