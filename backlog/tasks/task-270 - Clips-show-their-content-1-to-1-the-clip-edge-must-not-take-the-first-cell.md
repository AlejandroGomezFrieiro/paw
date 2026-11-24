---
id: TASK-270
title: 'Clips show their content 1 to 1: the clip edge must not take the first cell'
status: Done
assignee: []
created_date: '2026-11-23T08:01:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels:
  - ux
milestone: m-15
dependencies: []
priority: high
ordinal: 334000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-23: 'MIDI clips have a small gap between the beginning and the first note. Clips should be a 1-to-1 (abstracted) representation of the underlying MIDI file.' Today the clip's left edge mark ▏ is drawn in the clip's first cell, so a note on the clip's first beat loses that cell (at zoom 1 the whole first beat, at zoom 4 a quarter of it). Audio waveforms lose the first cell the same way, and frozen and subproject blocks too. Show the edge without taking a cell of content (a color or a style change of the first cell, a cell that holds both, or the name row only), so each cell of a clip shows the notes or sound of exactly its time. Screens: scratchpad/screens/ui.txt (text) and the owner's page of colored frames; script scratchpad/screens/ui.lua (run with tests/tools/run.sh --clean --no-plugins --audio null --headless -l <script>, SHOTS_OUT, SHOTS_DIR).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A golden screen test with real keys: a clip whose first note is on its first beat shows that note in the clip's first cell, at zoom 1 and zoom 4; the same for an audio clip's waveform
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a45844c497718bc2b, commit 2579aeba. The clip role (runtime/lua/paw/roles/arrange.tl) draws the start hairline, and a subproject block's end line, on the name row only; the stopped playhead over a clip's body (runtime/lua/paw/views/arrange.tl, draw_playhead) now shades the column (PlayheadShade, keeps the cells) in place of a hairline that hid the first cell of clips at the song start. Golden test in tests/ui.lua with real keys (gg0, zizi): first_cell_zoom1/zoom4 (MIDI clips at beat 0 and 4, audio clip at beat 1). ascii.txt re-blessed. Docs: docs/reference/arrange-view.md. Not changed: repeat notches of looped clips and warp marks still take a body cell.

Merged to main in batch 15 (2f970bba); full suite and checks passed.
<!-- SECTION:NOTES:END -->
