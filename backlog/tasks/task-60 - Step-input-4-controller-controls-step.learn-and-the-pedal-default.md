---
id: TASK-60
title: 'Step input 4: controller controls, :step.learn and the pedal default'
status: Done
assignee: []
created_date: '2026-11-22T04:43:00Z'
updated_date: '2026-11-22T12:52:00Z'
labels:
  - step-input
  - insert-mode
  - midi
milestone: m-4
dependencies: []
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the user maps a key, pad or pedal of a MIDI controller to a step-input action, so that rests, ties and note values come from the controller and not from the computer keyboard. The sustain pedal works with no setup.

User-visible behavior:
- `paw.step.bind(source, action)`. `source` is `{ port, channel, note | cc }`; `port` and `channel` are optional. Actions: `rest`, `tie`, `back`, `erase`, `again`, `legato`, `dur.1` `dur.2` `dur.4` `dur.8` `dur.16` `dur.32`, `dot`, `triplet`, `octave.up`, `octave.down`, `chord` (held: the keys join one chord across releases), `finish`, or `{ keys = "=8t" }` (types those keys of the pencil). Also `{ down = "rest", held = "tie" }` for a pedal. `paw.step.unbind(source)`, `paw.step.bindings()`, `paw.step.action(name, fn)` (a new action from an extension).
- The default of the sustain pedal (cc 64): down with no key held is a rest; down while keys are held makes them one step longer (a tie). `paw.step.unbind({ cc = 64 })` removes it.
- `:step.learn {action}` waits for the next key, pad or pedal of the controller and binds it, by port, channel and note or cc. `Tab` completes the actions. `Esc` stops the wait.
- `:step.controls` lists the bindings in a picker; `<A-d>` removes one (as `:recent` does).
- The bindings are the user's, not the song's: `state_dir/step-controls.json`, written by `:step.learn` and by a removal, read at the start. Bindings from `init.lua` stay in memory only. `--clean` reads and writes nothing.
- A mapped control is consumed: while a target listens, paw sets the filter `api.engine_midi_filter("step", rules)` from the bindings, so the control does not sound, does not record and does not enter a note. When no target listens, the filter is removed. The title shows the action for a moment (`rest`, `back`).
- The target contract grows: `contracts.StepTarget` gets `actions: {string: function(count: integer)}`. An action that a target does not have says `not here: <action>`. The piano roll's target does each action with the pencil's own functions (`<Space>`, `<BS>`, `x`, `.`, `<CR>`, `=N`, `K`, `J`).

Read first:
- backlog/docs/designs/step-input.md: "Durations, rests and ties from the controller", "Which device, and nothing recorded", "What you hear and see" (consumed controls), "The Lua extension point", "Tests", and "Owner decisions (2026-11-22)" (Q7 pedal, Q9 user state).
- runtime/lua/paw/step.tl (`heard`, the target registry, `current`), runtime/lua/paw/contracts.tl (`StepTarget`, near line 1131).
- runtime/lua/paw/roll_draw.tl (the step target near line 1899, and the pencil keys it calls).
- crates/paw-core/src/api/engine.rs (`engine_midi_filter`), runtime/lua/paw/types.tl (`MidiFilterRule`), crates/paw-engine/src/midi_filter.rs.
- runtime/lua/paw/learn.lua (how learn waits for a control), runtime/lua/paw/recent.lua (a state file under `env.state_dir`, nothing under `--clean`).
- tests/step_input.lua (the helpers `typed` and the injection from test ports).
- .claude/skills/teal.

Depends on: TASK-58, TASK-59 (merged).
Do not touch: the notation and utau extensions (TASK-61, TASK-62), the engine (the filter exists). TASK-17 also changes roll_draw.tl (the `key` registry): keep to the step target.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys (tests/step_input.lua): I, then the pedal down from port Test Keys with no key held enters a rest of one step; the pedal down while C4 is held makes C4 one step longer; Esc writes one undo step and u removes it all
- [ ] #2 Test: :step.learn rest, then note 36 from port Test Pads binds it; the next note 36 from Test Pads enters a rest, no note, and a Lua device on the track gets no note; note 36 from Test Keys still enters C2
- [ ] #3 Test: a binding { keys = '=8t' } sets the step to an eighth triplet, and the STEP title shows it
- [ ] #4 Test: a binding made by :step.learn is in state_dir/step-controls.json and comes back after paw.step reads the file again; under --clean nothing is read or written
- [ ] #5 Test: :step.controls lists the bindings, and a removal there changes the file
- [ ] #6 Test: an action that a target does not have says 'not here: <action>'
- [ ] #7 contracts.tl types the actions with no any; tools/tlcheck.sh passes; docs/reference/api.md is generated again; docs/reference/piano-roll.md lists the actions and commands; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a4153ed2fcf83010f, commit 6f51edf6 (main merged after it). paw.step.bind/unbind/bindings/action, pedal default (cc 64: rest / tie), :step.learn (Tab, Esc), :step.controls (Alt-d), state_dir/step-controls.json (none under --clean), engine filter 'step' while a target listens, title flash, contracts.StepTarget.actions, roll_draw.tie and roll_draw.value. Docs: piano-roll.md, keys.md, api.md. Tests: 6 new in tests/step_input.lua. Not Done: owner merges.
<!-- SECTION:NOTES:END -->
