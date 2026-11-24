---
id: TASK-273
title: >-
  Arrange view content: take lanes show their takes, controller moves and linked
  faders show, loop notches and warp marks leave the content cells, and the
  selection size shows
status: Done
assignee: []
created_date: '2026-11-23T08:01:00Z'
updated_date: '2026-11-23T13:48:00Z'
labels:
  - ux
milestone: m-15
dependencies:
  - TASK-270
  - TASK-271
priority: medium
ordinal: 337000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen in the screens: the take lanes under a clip show only the take names; a take's waveform or notes do not show, so a comp is chosen blind. The mark ‹3/3› pushes the name out on a short clip. Also check: in the screen script, s at beat 4 then ]t did not cut the clip into two pieces (bug or wrong keys; find out and fix or correct the script). Screens: scratchpad/screens/ui.txt (text) and the owner's page of colored frames; script scratchpad/screens/ui.lua (run with tests/tools/run.sh --clean --no-plugins --audio null --headless -l <script>, SHOTS_OUT, SHOTS_DIR).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each take lane shows its take's waveform or notes under its time (golden screen)
- [ ] #2 (TASK-272) A golden screen test with real keys for v, V and <C-v>
- [ ] #3 (TASK-274) A clip with controller moves shows them (a mark or a small curve) in the arrange view (golden screen)
- [ ] #4 (TASK-275) A golden screen: a looped clip with a note on each repeat's first beat shows that note in the repeat's first cell; the same for a warp mark over sound
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-aa2860f32103a098e: commits 24ee314b (the work), a137b349 (merge of main cd367da1), 1544a25c (nest golden re-blessed for the new block end). Take lanes are two rows (name + waveform/notes, paw.takes.peaks); short take mark 'rif…‹2›'; repeat notches and warp marks on the name row only; controller-move curve on a MIDI clip's name row (role prop moves); group with linked faders shows ≡; subproject block ends with ▕ (glyph clip_end); status line 'selection' shows 'bars 3–10 · 3 tracks' at every width. The screen script used s (no mapping); S splits, and docs/reference/takes.md and takes.tl said s: fixed. Goldens: tests/screens/ui/take_lanes, selection_time/tracks/block, controller_moves, repeats_and_warps. Not Done until merged.

Landed on main in batch 17 (deb79a0f), with the merge fixes of 2026-11-23 (clock rounding, export leader domain, goldens, MCP render_stems).
<!-- SECTION:NOTES:END -->
