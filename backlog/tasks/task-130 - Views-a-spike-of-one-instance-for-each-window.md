---
id: TASK-130
title: 'Views: a spike of one instance for each window'
status: Done
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels:
  - architecture
  - lua-review
milestone: m-2
dependencies:
  - TASK-126
priority: medium
ordinal: 142000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On the piano roll, make the layout give each window its own instance of the view (`__index` to the view table), in place of the swap of `window_state` fields by `layout.bind`. Add `paw.ui.instance(name)` and `paw.ui.instance_of(win)` for readers outside the view. Measure the change in lines and in the time of a frame, and write a short design with a recommendation for all views and for the contract `View`.

Read first: backlog/docs/designs/architecture-review-lua.md, the finding L6 and its proposal P8.

Overlaps: TASK-6.2 (more window state comes; decide before or with it).
Dependencies: P4.

Owner decisions (2026-11-22): the review's recommendations are accepted. notation and utau are not ported to Teal: they move to Rust as native extensions later (a separate ticket).

Note: TASK-6.2 (folds, merged) added per-window state in screen.json. The spike builds on it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 a branch with the piano roll on instances and its tests passing
- [ ] #2 a design note with the recommendation and the list of extension views that change
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Spike done (2026-11-23). Branch worktree-agent-a45f8a1b8868242eb, commits 578b7a60 (spike), 23d854ce (merge of main 6c3286a3), 0ae575b3 (stamp reads the instance; tests/frames.lua reads render, not rawget). Design note: backlog/docs/designs/window-instances.md.

AC1: the piano roll is on instances (window_instances = true): paw/layout.tl gives each window a table of the window_state fields with __index to the view; bind sets a pointer. paw.ui.views.pianoroll is a proxy to the bound window's instance, so the 81 readers do not change. paw.ui.instance(name) and paw.ui.instance_of(win) added. roll_clips.lua keeps its window state (edited, context_shown) in the instance. Tests: suite filters roll, piano, window, seat, scene, stamp, frames, notation, snippet, musicops, articul, step, mouse, layout, clip, note, edited, context pass; the 3 failures left also fail on main (vocal editor curves; narrowing under the window filter; tutor lesson 4 under the roll filter). New test: each piano roll edits its own set of clips (fails with main's roll_clips on the branch); window_state test checks instance/instance_of.

AC2: the design note has the recommendation (merge the branch; window_instances opt-in now, default when the last runtime view moves; then readers move to paw.ui.instance, then the proxy and bind go) and the list of extension views that change (launcher: none; notation: window_keep locals move; roll readers in articulations, musicops, tutor, notation: none while the proxy stays).

Numbers (shared dev binary, under load 6.6 to 8.9): frame p50 the same within spread (two rolls 0.54-0.83 ms main, 0.55-0.84 ms branch; render runs 1.1 per frame on both); bind of the other window 1.3-2.7 us main, 0.7-1.3 us branch; a read through the proxy 28-57 ns vs 1.1-1.8 ns. Lines: +290 / -58 (the swap stays for the other views; about 130 lines of layout.tl go when all views move).

Orchestrator 2026-11-23: the branch merges (batch 6): it fixes two rolls sharing one set of edited clips. Follow-up: TASK-177.
<!-- SECTION:NOTES:END -->
