---
id: TASK-55
title: Step input from a MIDI keyboard (insert mode grammar)
status: Done
assignee: []
created_date: '2026-11-22T04:30:00Z'
updated_date: '2026-11-22T04:43:00Z'
labels:
  - insert-mode
  - midi
  - design
milestone: m-4
dependencies: []
priority: high
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design (then build after owner approval) how insert mode takes notes from a MIDI keyboard or other controller step by step, not recording: each key pressed (or chord: keys held together) enters notes at the pencil and the pencil steps on. Questions: how it composes with the pencil grammar (h/l edges, ={dur}, <CR>, <Space> rest, c chords, ., x, <BS>); the step length (current grid, ={dur} typed on the computer keyboard, or controller keys/pads/pedal mapped to durations, rests, tie, back); chords by holding keys (release of the last key commits); velocity from the key or fixed; a sustain pedal or a spare key as rest/tie/back; MIDI learn for those controls; which input is listened to (the track's input, a chosen device) and that it never records or plays through unless monitoring is on; the same in the notation view and the vocal editor; feedback (the note sounds through the track, the status line shows what will be entered); Lua API so extensions add controller mappings; tests with a virtual MIDI input (--audio null, ALSA seq or the test input). Prior art: Sibelius/Dorico/MuseScore step entry, Logic step input keyboard, REAPER step input, Vim's insert mode. Output: backlog/docs/designs/step-input.md with the grammar table and owner questions.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design written: backlog/docs/designs/step-input.md (owner approval needed before building).

Recommendation: `I` in the piano roll is step input from any MIDI controller: the pencil of insert mode with the controller giving the pitches. A key or a chord held together fills the pen; the release of the last key closes the chord; the next key keeps it and enters after it. All pencil keys still work (= sets the sticky step, Space rests a step, BS takes back, x replays, . again, c chords, counts repeat). Esc writes all as one undo step. Velocity from the key. Listens to the active clip track's midi_input (else all ports); the note sounds through that track; nothing records; nothing enters while playing. Controller controls via paw.step.bind (rest, tie, back, dur.N, dot, triplet, keys=...), user state by port, consumed by a new generic engine input filter; pedal default: rest with no key held, tie with keys held; :step.learn. Views register with paw.step.target (roll in core; notation and vocal editor in their extensions). Remove the computer-keyboard piano (roll_insert=keys, pianoroll.keys) and the old :notes.step_input. Plan: 7 parts (S, M, M, M, S-M, S, S). 10 owner questions in the doc.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Design done and approved (all recommended answers, 2026-11-22): backlog/docs/designs/step-input.md. Build split into TASK-57..63.
<!-- SECTION:FINAL_SUMMARY:END -->
