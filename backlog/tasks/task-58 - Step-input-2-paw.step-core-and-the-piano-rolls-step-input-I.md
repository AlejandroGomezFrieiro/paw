---
id: TASK-58
title: 'Step input 2: paw.step core and the piano roll''s step input (I)'
status: Done
assignee: []
created_date: '2026-11-22T04:43:00Z'
updated_date: '2026-11-22T09:46:00Z'
labels:
  - step-input
  - insert-mode
  - midi
milestone: m-4
dependencies: []
priority: high
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
I from normal mode starts step input (title STEP); I in the pencil toggles it; a key enters one step with its velocity and steps on; held keys make one chord, last release closes it; = sets the step; the pencil keys work alongside; Esc writes one undo step; listens to the clip track's MIDI input (or all ports); no MIDI input: says why and opens the input list; nothing entered while playing. Tests via paw.midi.inject. Size M. Design: backlog/docs/designs/step-input.md.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done on branch worktree-agent-a3744234bfffba660, commit f299d3d3 (on top of main incl. TASK-59). paw.step (runtime/lua/paw/step.tl): targets (contracts.StepTarget/StepNote), held keys and chords, input rule (track midi_input port/channel else all), paused while playing/recording, ignores e.filtered, no-input reason + MIDI part of the input list (paw.audio.pick), engine_follow_always for the target's track, :step.input, paw.opt.step_velocity. Roll target in roll_draw.tl: I normal/pencil, keep-and-go-on, count, velocity+attr, = sets the step, Space rests by the step (also pencil), BS takes back entry/rest, Ctrl-o keeps step input, STEP title, key bar, Step button. Not done here (later tickets): paw.step.bind/controls/:step.learn/pedal and feeding engine_midi_filter (part 4), notation and vocal targets, how-to guide and tutor lesson. Tests: tests/step_input.lua (3), record_mix test uses real I.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main in 2d8a9808: paw.step (runtime/lua/paw/step.tl) and the piano roll's step input on I (chords by holding, = sets the step, Esc writes one undo step).
<!-- SECTION:FINAL_SUMMARY:END -->
