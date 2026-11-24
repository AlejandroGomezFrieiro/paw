---
id: TASK-125
title: 'Teal wave 5, part 1: keymap, keyrule, keybar'
status: Done
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-22T23:53:00Z'
labels:
  - architecture
  - lua-review
milestone: m-4
dependencies: []
priority: high
ordinal: 137000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port `keymap.lua` (1 597 lines), `keyrule.lua` and `keybar.lua` to Teal. Split registers and macros, and marks and jumps, into their own files under `keymap/`. Export `mode_changed` as a descriptor. Make `lookup` use a table of prefixes. Delete the 14 stand-in `Keymap` records and the entries of `any-allowed.txt` that go.

Read first: backlog/docs/designs/architecture-review-lua.md, the finding L3 and its proposal P3.

Overlaps: TASK-22 (split it), TASK-17.
Dependencies: none. Do it when no branch changes `keymap.lua`.

Owner decisions (2026-11-22): the review's recommendations are accepted. notation and utau are not ported to Teal: they move to Rust as native extensions later (a separate ticket).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 no `any` and no `Untyped` in the new modules
- [ ] #2 the 14 stand-ins are gone
- [ ] #3 the suite passes with no test changed
- [ ] #4 the migration table of the Teal explanation and the teal skill say what the port found
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-aabc11cf8b51eca0b, commits d7dcd38a (port), 71187f2c (merge main), 44472ac8 (shada comment). keymap.lua (1,597 lines) is keymap.tl plus keymap/registers.tl and keymap/marks.tl; keyrule and keybar are Teal; 3,021 lines of Teal. lookup uses a prefix table per mode and scope. paw.keymap.mode_changed is the descriptor (5 modules use it). 14 Keymap stand-ins and 4 Keybar stand-ins gone. any-allowed.txt 49 to 47 (paw.keymap, paw.keyrule). No any or Untyped in the new modules. No test changed. Checks: tlcheck, apidoc check exit 0, luacheck 0, fmtcheck, vale 0. Test groups: the only failures (rulerplus chord, search pickers, utau vocal-editor selection/curves, tutor lesson 4, narrowing) fail the same way on main's runtime with the shared binary, and pass when run alone. Bench g<Esc> 2.2-2.9 us to 1.1-1.2 us; j k unchanged (about 41 us).

Merged to main (batch 4, 2026-11-23): dev build, apidoc regenerated, nextest paw-core/engine/tui/mcp (400) and the full suite with plugins passed. At the merge: vzoom.tl's Paw record names the keymap (TASK-125 took it out of partial.Paw).
<!-- SECTION:NOTES:END -->
