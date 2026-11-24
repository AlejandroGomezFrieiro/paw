---
id: TASK-57
title: 'Step input 1: remove the computer-keyboard piano and the old step input'
status: Done
assignee: []
created_date: '2026-11-22T04:43:00Z'
updated_date: '2026-11-22T09:46:00Z'
labels:
  - step-input
  - insert-mode
milestone: m-4
dependencies: []
priority: high
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Remove roll_insert/keys_once/to_keys (roll_draw.tl), the pianoroll.keys keymap, the pencil's I, :notes.step_input and the Step button (frontend.tl, views/pianoroll*.lua), keybar entries, musicops keys + README, the tutor lesson and its tests (regenerate the course), and the pages listed in the design (piano-roll.md, options.md, keys.md, limits.md, window.md; regenerate api.md and types). Size S. Design: backlog/docs/designs/step-input.md.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done on branch worktree-agent-a3744234bfffba660, commit 038334b9. Removed roll_insert, pianoroll.keys, keys_once/to_keys, view:enter/backspace/set_octave/step/starting_here, the octave option (only the piano used it), the pencil's letter warnings, :notes.step_input, frontend stepping, the old Step button; musicops piano wrap and README; tutor lesson paragraph and tests' view list; welcome line; docs piano-roll/keys/options/limits/window; api.md, types and course regenerated. Tests of removed modes deleted (tests/note_entry.lua, the modal/drawinsert/frontend blocks); ux/articulations/musicops tests moved to the pencil; frontend test now resets the note length it changes.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main in 2d8a9808 (with TASK-58): the computer-keyboard piano and the old step input are removed.
<!-- SECTION:FINAL_SUMMARY:END -->
