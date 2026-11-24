---
id: TASK-95.2
title: >-
  paw-model 2: Document without session helpers, undo without the disk writer,
  path and clock as arguments
status: To Do
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - architecture
  - rust
  - paw-model
milestone: m-10
dependencies: []
parent_task_id: TASK-95
priority: medium
ordinal: 264000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-95 (the paw-model crate). Its part-2 agent named these blockers of the crate. It can run beside TASK-95.1.

Today Document (crates/paw-core/src/session/document/) still needs parts of the session:
- Helpers and option types in session.rs and its submodules: de, de_meta, holds, finite, sorted, check_controls, check_fade, TrackOpts, ClipOpts, ClipKind, CustomSet, the stretching checks, ports, midi_out::parse.
- session::undo::Undo holds UndoFile, which owns the writer thread.
- clip_add calls std::path::absolute, and the checkpoint calls Instant::now.

What to build: move the helpers and option types that Document uses next to Document (or into the model). Split UndoFile into the undo tree state (in Document) and the disk writer (in Session). Give the path and the time to Document as arguments or through a clock trait, so that a test can give them. No change of behavior.

Read first: TASK-95 (description and the part-2 notes), crates/paw-core/src/session.rs, session/document/, session/undo.rs, .claude/skills/rust-skills.

Depends on: part 2 of TASK-95 on main.
Do not touch: the Lua API; the audio engine.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 session/document/ uses nothing of session.rs or its other submodules (git grep for super:: and crate::session paths)
- [ ] #2 Document has no thread, no std::path::absolute and no Instant::now; a Rust test gives it a fixed time
- [ ] #3 The Rust tests of paw-core and the Lua suite pass with no change of behavior
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-95.1 (owner: fewer, larger tickets). Its criteria and text are in TASK-95.1.
<!-- SECTION:NOTES:END -->
