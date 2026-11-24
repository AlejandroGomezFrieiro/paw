---
id: TASK-77.9
title: 'Derived D9: Frozen tracks: up to date or stale'
status: Done
assignee: []
created_date: '2026-11-22T15:23:00Z'
updated_date: '2026-11-23T06:36:00Z'
labels:
  - performance
  - derived
milestone: m-3
dependencies:
  - TASK-77.1
  - TASK-10
parent_task_id: TASK-77
priority: medium
ordinal: 128000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
D9 of the derived-data design. After the provenance of the kept bakes in the media design (`input_key`), the freeze node's key is the track's content key (its clips, devices, the tracks that feed it). Depends on the media tickets.

Read first: backlog/docs/designs/derived.md, part 4 (the design) and row D9 of part 5; part 2 (inventory) and part 3 (measurements) for the consumer.

Owner decisions (2026-11-22): the design is approved; Q1 no mark in the views (the status line shows the job only after 1 s, K on a chord says "reading"); Q2 paw.derived stays internal in D1 to D5 and becomes public in D6; Q3 no user option for memory, fixed limits per kind shown by :checkhealth derived.

Measure with the spread, on the bench project, against main at the time, measured under external load.

Depends also on the media tickets that add the provenance of kept bakes (`input_key`, media.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: An edit inside a frozen track marks it stale with the reason ("Drums changed since: devices"), and `K` says so. An undo makes it up to date again.
- [ ] #2 Number to meet: The check costs 0.1 ms or less for each edit (one key compare).
- [ ] #3 Docs follow the change; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a049604f331d1658a, commit 00a7d3a9 (base d5127487).

Missing on main: the media tickets (TASK-10, M4 to M12) are not done. No Provenance or input_key of kept bakes exists (only bake/store.rs input_key for cache entries). This ticket builds only what it needs: paw/bake_state.tl makes a content key in Lua (one stamp each for clips, devices, automation, mix, tempo, from the kernel stamps and the fields of clips, devices, lanes). The freeze keeps it in meta: frozen = { file, key }. When media M4+ adds Provenance, the key can move to the kernel's input_key.

What changed: paw.freeze.describe(track) (K line: 'frozen, up to date', 'frozen, stale: Drums changed since: devices', 'held in Strings, which is frozen, ...'); two paw.derived nodes freeze.members and freeze.key (no change in derived.tl); modal.lua info shows the line; docs/reference/freezing.md, how-to freeze-a-heavy-track.md, api.md regenerated.

For TASK-7.13: bake_state.make takes a Scope {tracks, own, from, to}; bake_state.describe(name, saved, now) gives the stale words.

AC1: tests/scope.lua 'an edit inside a frozen track makes it stale with the reason, K says so, and u makes it up to date' (real keys: :freeze, K, <Space>dd j+, n, u, K). Also a table test of the parts and a count test (freeze.key not made again after an edit elsewhere).
AC2: bench/RESULTS.md 2026-11-23 TASK-77.9: an edit inside the freeze shows no measurable difference against main (p50 0.23-0.25 ms vs 0.23-0.26 ms), so the check per edit is below 0.1 ms; the remake of the key on K costs 0.29-0.45 ms p50 on the bench project. Measured under external load.
AC3: Vale 0 alerts on the changed pages.
Gaps: the key does not hold a plugin's saved state (only its parameters) and the list of audio edits (only their count).

PO 2026-11-23: the gaps (plugin saved state and the edit list not in the key) go to TASK-214.
<!-- SECTION:NOTES:END -->
