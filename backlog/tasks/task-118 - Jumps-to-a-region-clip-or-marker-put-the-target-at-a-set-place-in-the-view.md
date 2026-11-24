---
id: TASK-118
title: Jumps to a region, clip or marker put the target at a set place in the view
status: Done
assignee: []
created_date: '2026-11-22T15:50:00Z'
updated_date: '2026-11-22T18:17:00Z'
labels:
  - ux
  - navigation
milestone: m-4
dependencies: []
priority: high
ordinal: 130000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner, 2026-11-22: moving to a region puts the cursor there, but the view is not aligned, so the target sits too far to the right and the owner has to scroll a lot to centre the view. Goal: a move that lands off screen (or far from the visible part) scrolls the view so the target is at a fixed place: by default near the left edge with a small margin, so the region or clip reads to its right; an option chooses 'center'. A move that stays on screen does not scroll (as now). Covers the arrange view first, then the piano roll and other timeline views through the same code. Neovim reference: 'sidescrolloff', zs/ze/zz-like keys.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Real-keys test: a jump to a region that starts off screen puts the region start at the left margin (the option's default), and the region's first bars are visible
- [ ] #2 Option paw.opt.jumpview = 'left' | 'center' (and a margin option if needed); 'center' puts the target in the middle; documented in options.md
- [ ] #3 A move that stays inside the visible part does not scroll
- [ ] #4 Covers region, clip and marker jumps, search n/N, marks, :@bar and G/gg in the arrange view; the piano roll uses the same rule
- [ ] #5 Keys to put the cursor's column at the left, middle or right of the view exist (as zs/zz/ze or the paw equivalent), documented in keys.md
- [ ] #6 Docs follow; Vale 0; the existing scroll and frames tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a04640424f62c876c. draw.jump_scroll (one rule for arrange and piano roll), paw.opt.jumpview left|center, jumpmargin 6, keys zs/ze, zz unrounded. Test in tests/arrange_scene.lua.

Revised (2026-11-22): alignment by kind of move, not distance. Jumps (anything that pushes the jump list; ]' [' ]r [r now do) align with jumpview/jumpmargin when the target is off screen or in the last quarter of the view; steps (h l w b e) scroll just enough. Tests: arrange_scene (marker 2 beats past the edge, l past the edge, ze), roll_scene (* off screen). Full suite passed.
<!-- SECTION:NOTES:END -->
