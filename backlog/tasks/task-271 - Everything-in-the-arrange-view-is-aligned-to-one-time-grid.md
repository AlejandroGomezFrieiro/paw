---
id: TASK-271
title: Everything in the arrange view is aligned to one time grid
status: Done
assignee: []
created_date: '2026-11-23T08:01:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels:
  - ux
milestone: m-15
dependencies: []
priority: high
ordinal: 335000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-23: 'Everything in the arrange is properly aligned.' Seen in the screens: the timeline starts at column 24 without groups, 25 with a group, 26 in a scope (the › mark), so the grid moves when a group appears or a window narrows; a block's right edge draws beside the grid line (▏▏, two columns); automation lanes use sextant glyphs (🬭 🬋 🬂) that many terminal fonts lack, so the curve can misdraw. Audit the arrange view (ruler, region row, clips, blocks, lanes, take lanes, loop band, selection) for elements that are off the time grid or move it, fix them, and choose a glyph fallback for lanes (paw.opt.ascii and a font check, or a safer default). Coordinate with the UX design tickets (UX-1 removes the › mark from the track column). Screens: scratchpad/screens/ui.txt (text) and the owner's page of colored frames; script scratchpad/screens/ui.lua (run with tests/tools/run.sh --clean --no-plugins --audio null --headless -l <script>, SHOTS_OUT, SHOTS_DIR).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The timeline starts at the same column with and without groups and scopes (golden screens)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a77f8f0b7dabf21c8, commit 3e73d8f4. Track column parts with from_header (signs, fold) take their columns from the headers (beyond 12 columns), so the timeline starts at the same column with and without groups and scopes (golden screens tests/screens/trackcolumn/grid_*.txt). Numbers still come from the timeline. :checkhealth terminal shows the curve characters with advice (braille/line/ascii); default stays sextant. Left to TASK-270: a subproject block's right edge draws ▏ in its last cell (▏▏ beside the grid line); use the right eighth ▕ there or drop it.

Merged to main in batch 15 (2f970bba); full suite and checks passed.
<!-- SECTION:NOTES:END -->
