---
id: TASK-173
title: >-
  Clip writer: a note very far in time makes encode write billions of
  clockstamps or overflow
status: Done
assignee: []
created_date: '2026-11-22T22:47:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels: []
milestone: m-12
dependencies: []
priority: high
ordinal: 185000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-159 (not fixed). A clip with origin near i64::MIN or a note at about 1e15 beats makes clipfile::encode write billions of clockstamps (hang, out of memory) or overflow in span and sequence_words. The model allows such times. Needs a design choice: a range for note times checked at the model boundary (paw.api, file readers), or an encoder that writes far gaps in a bounded number of words. TASK-156's round-trip properties may hit it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Saving a clip with a note at 1e15 beats ends in bounded time and memory, and either keeps the note or refuses the edit with a clear message
- [ ] #2 A regression test for each case, and the fuzz target clip_file also runs encode
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design: a range at the model boundary plus a writer that refuses, not a new encoding of far gaps. model::MAX_BEATS = 1e6 beats (about 139 hours at 120 BPM): note starts and ends, controller moves and clip lengths stay within it. Reason: a musician never reaches it, the MIDI Clip File spec has no bounded way to write a far gap (a Delta Clockstamp holds 2^20-1 ticks, about 17 beats), and paw: text for a skip would make other programs misplace the notes. In range, a clip file has at most about 120 000 clockstamps (< 1 MB) and no tick count overflows. Clips in range read and write the same bytes as before. Where: check_notes moved from session to model (edits and Project::validate use the same rule), Control::problem, check_clip, check_clip_opts and clip_set length check the range; clipfile::encode now returns Result and refuses a far time (backstop for any edit path that misses the check, and for paw.api.midi2_write, which did no checks); clipfile::decode refuses a file with a far time; fuzz target clip_file also runs encode and expects it to succeed for every clip that decode accepts. Tests: clipfile/far_times.rs (3 Rust tests), tests/model.lua 'times up to a million beats...'. Docs: docs/reference/project-files.md. Branch worktree-agent-a18b2af2197c20e95, commit fbe5fa60 (merges TASK-159). TASK-156 props.rs and TASK-155 clipfile tests call encode: they need .expect()/.unwrap() at merge; TASK-156 generators must stay within MAX_BEATS.
<!-- SECTION:NOTES:END -->
