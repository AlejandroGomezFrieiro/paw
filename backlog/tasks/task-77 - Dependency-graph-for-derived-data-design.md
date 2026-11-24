---
id: TASK-77
title: Dependency graph for derived data (design)
status: Done
assignee: []
created_date: '2026-11-22T08:09:00Z'
updated_date: '2026-11-22T18:47:00Z'
labels:
  - performance
  - architecture
  - design
milestone: m-3
dependencies:
  - TASK-14
  - TASK-79
priority: high
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: a design, not code. Generalize the approach of HARMONY-FAST (content stamps, work in slices, views read the value as it stands) into one dependency graph for all data derived from the project, so that an edit recomputes only what depends on it, in slices, and never blocks a key. The owner approves the design before any code.

The output is backlog/docs/designs/derived.md, in Simplified Technical English, with:
1. An inventory of every cache of derived data today, in Rust and in Lua: what it derives from, its key (stamp, generation, hash), where it is made invalid, what it costs to make again, and on which thread. At least: the harmony reading (harmony.tl, harmony/song.tl), the clip list cache of TASK-14, the compiled events (crates/paw-core/src/sync/clips.rs), peaks (peaks.rs), stretch bakes and the bake scheduler (crates/paw-core/src/bake/), freeze (freeze.rs), scenes (scene.rs, frontend.tl), LSP diagnostics (runtime/lua/paw/lsp/document.tl), search and grep (grep.tl, query.tl), scope resolution (scope.tl), the region tree (markers.tl), the piano roll and notation layouts.
2. Measurements on bench/profile/project.lua: the cost of one edit today, split by consumer.
3. The design: the node types, keys by content stamp, where the graph lives (Rust, Lua, or both, and why), the invalidation events (the kernel events `clip_changed` and others), work in slices through `paw.slices` (TASK-79), priorities as the bake scheduler has them (playing, visible, background: media.md 2.9), how a view reads the value as it stands (as `paw.harmony.key(beat, latest)`), memory limits.
4. The N0 finding of nest.md section 8 (copies keep a stable identity, and share one compiled event list): how the graph keys copies.
5. A migration plan: one consumer for each ticket, in order, each with a test idea and a number to meet. Name the first consumer.
6. Owner questions only where a real decision is missing.

Read first: runtime/lua/paw/harmony.tl and harmony/song.tl; backlog/docs/designs/media.md sections 2.7 to 2.9; crates/paw-core/src/bake/scheduler.rs; crates/paw-core/src/sync/clips.rs; backlog/docs/designs/nest.md section 8 (N0 results); bench/RESULTS.md (2026-11-21 profile); the merged branches of TASK-14 and TASK-79.

Depends on: TASK-14, TASK-79.
Do not touch: any code. Design only.

Size: M (a design).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 backlog/docs/designs/derived.md has the inventory table, with every cache named in the description and any others found
- [ ] #2 The design gives measured costs of one edit on bench/profile/project.lua, split by consumer
- [ ] #3 The design names the node types, keys, invalidation events, slices, priorities and memory limits, and how copies (nest.md section 8) are keyed
- [ ] #4 The migration plan lists one ticket for each consumer in order, each with a test and a number; the tickets are made in m-3 after the owner approves
- [ ] #5 No file of the repository changes (git status --short is empty)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design approved by the owner 2026-11-22 (Q1-Q3 as recommended); tickets TASK-77.1..77.9 in m-3.

Owner, 2026-11-22: this design ticket stays Done. Its children 77.2 to 77.9 stand alone.
<!-- SECTION:NOTES:END -->
