---
id: TASK-129
title: 'Events: one owner for each event of the runtime'
status: Done
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels:
  - architecture
  - lua-review
milestone: m-4
dependencies:
  - TASK-125
priority: medium
ordinal: 141000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The emitting module exports the descriptor of each runtime event; other modules import it. A text subscription to a name that no module declares warns once and shows in `:checkhealth events`. `tools/apidoc.lua` writes the runtime rows of the reference page on events from the descriptors.

Read first: backlog/docs/designs/architecture-review-lua.md, the finding L5 and its proposal P7.

Overlaps: none.
Dependencies: P3 for `mode.changed`.

Owner decisions (2026-11-22): the review's recommendations are accepted. notation and utau are not ported to Teal: they move to Rust as native extensions later (a separate ticket).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 one descriptor and one payload record for `option.changed`, `mode.changed`, `startup`, `exit`, `render.*`
- [ ] #2 a test of the warning
- [ ] #3 the page on events is generated for these rows
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a94cd7158c7eda819 (commits 347d5eca main work, 87ed23c2 after merges; merged TASK-125, 6.5, 116, 7.11 and main). paw.options owns option.changed (options.changed/options.Changed; 11 copies gone), paw.events owns startup/exit, paw.render owns render.before/finished (address, qf copies gone; Before.measure added), keymap.mode_changed used by notation/utau; kernel descriptors made with paw.events.event. paw.events.event declares names; paw.on by text with an undeclared name writes one log line (checked at end of startup, then at each paw.on); :checkhealth events lists them. tools/apidoc.lua writes the rows between marks in docs/reference/events.md from exported descriptors (--- The event `name`: when.); apidoc check fails when stale. Test: tests/health.lua 'a handler that waits for an event by a misspelled name...'. Found: articulations subscribed to theme.changed, which nothing sends (removed). Merge note: bench/RESULTS.md and bench/profile/drive.py conflicted between TASK-116 and the TASK-124 text on main; kept both.
<!-- SECTION:NOTES:END -->
