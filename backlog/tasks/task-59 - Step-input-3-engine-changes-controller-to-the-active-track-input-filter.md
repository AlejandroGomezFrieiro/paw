---
id: TASK-59
title: 'Step input 3: engine changes (controller to the active track, input filter)'
status: Done
assignee: []
created_date: '2026-11-22T04:43:00Z'
updated_date: '2026-11-22T08:57:00Z'
labels:
  - step-input
  - insert-mode
  - midi
  - engine
  - rust
milestone: m-4
dependencies: []
priority: high
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Rust: the active clip's track plays the controller even when another track is armed; a generic input filter so mapped controls neither sound nor enter (no lock, no allocation on the audio thread). Rust unit tests. Size M. Design: backlog/docs/designs/step-input.md.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a959cd1af2e0942b0, commit e663c0a8. API for TASK-57/58: paw.api.engine_follow_always(track|nil) (the track plays MIDI input also while another track is armed, in place of engine_follow's selected track); paw.api.engine_midi_filter(name, rules|nil) with rules {port?, channel?, note|cc} (filtered controls neither sound nor record; midi.in events get filtered = true; lists kept per name). Engine: paw_engine::midi_filter, Msg::SetMidiFilter (boxed swap, old to garbage, no alloc on audio thread; held keys still release). Tests: Rust unit (midi_filter, engine midi_in, sync follow), no_alloc covers it, Lua test in tests/record_mix.lua. Docs: reference/midi.md, reference/recording.md, api.md regenerated.
<!-- SECTION:NOTES:END -->
