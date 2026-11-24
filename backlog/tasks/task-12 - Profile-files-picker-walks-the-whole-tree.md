---
id: TASK-12
title: 'Profile: files picker walks the whole tree'
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-22T05:29:00Z'
labels:
  - performance
  - picker
milestone: m-3
dependencies: []
priority: high
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
<leader>ff keeps the kernel busy up to 10 s in a large folder (pick/sources.tl). Depth/count limits, skip build and VCS folders, walk in slices. Size S.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-aa5aa547289ee3b71, commit 0c84d84a. Files picker walks in 8 ms slices via new PickSource.more hook; options files_limit (20000), files_depth (8), files_skip; skips hidden folders and plain .gitignore names; query line says 'stopped at N entries (files_limit)' / depth. Kernel CPU for <leader>ff + Esc on 9000-file tree: 20.5 / 20.4 ms -> 3.7 ms per round (processor time, shared machine under load, two baseline runs, one after run).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged: picker walks in 8 ms slices with limits; ' ff<Esc>' round 20.5 -> 3.7 ms kernel (one run, load ~12).
<!-- SECTION:FINAL_SUMMARY:END -->
