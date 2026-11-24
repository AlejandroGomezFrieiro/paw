---
id: TASK-7.5
title: 'Subprojects S2c: the transport for plugins inside a subproject'
status: To Do
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T12:38:00Z'
labels:
  - nest
  - subprojects
  - engine
milestone: m-2
dependencies:
  - TASK-7.4
parent_task_id: TASK-7
priority: medium
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: devices inside a subproject see the subproject's bars: bar 1 at the start of its block, with the tempo of the place. Today the engine has one transport for all tracks. This is the one engine change of nest.md 4.4 ("Transport for plugins").

What to build: a per-track transport offset and meter in the engine. CLAP plugins get it in `clap_event_transport`, VST3 plugins in `ProcessContext`, Lua devices in their transport, the built-in tempo-synced devices as they read the transport. No lock and no allocation on the audio thread.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.7 ("Transport for plugins inside"), 4.4. crates/paw-engine/src/tempo.rs (`TempoMap`), crates/paw-engine/src/engine/track.rs, crates/paw-engine/src/host.rs (the transport given to plugins), docs/reference/lua-devices.md (the transport of a Lua device), crates/paw-engine/tests/tempo.rs, .claude/skills/rust-skills.

Depends on: TASK-7.4.
Do not touch: the engine's rest (TASK-16), the quality switch (TASK-80).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: a test device that records its transport sees bar 1, beat 0 at the start of a block at song bar 33, with the song's tempo there; on a song track it sees bar 33
- [ ] #2 Test: a Lua device inside a subproject reads the subproject's bar
- [ ] #3 crates/paw-engine/tests/no_alloc.rs passes
- [ ] #4 docs/reference/lua-devices.md and engine.md say what a device inside a subproject sees; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Combined into TASK-7.3 (owner, 2026-11-22).
<!-- SECTION:NOTES:END -->
