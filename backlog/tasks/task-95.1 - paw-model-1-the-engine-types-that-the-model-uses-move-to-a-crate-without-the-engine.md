---
id: TASK-95.1
title: >-
  paw-model 1+2: engine types to a crate without the engine; Document without
  session helpers, undo without the disk writer, path and clock as arguments
status: Done
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-24T03:24:00Z'
labels:
  - architecture
  - rust
  - paw-model
  - bundle
milestone: m-10
dependencies: []
references:
  - architecture/decisions/0016-portable-core.md
  - backlog/docs/designs/architecture-plan.md
parent_task_id: TASK-95
priority: medium
ordinal: 263000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-95 (the paw-model crate). Its part-2 agent named this as the largest blocker of the crate, and the Groma report of TASK-209 (item 7) found the same.

Today the data model of paw-core uses types of paw-engine: model.rs uses Ctl, EventKind, NoteCtl, SigPoint, TempoMap and TempoPoint; model/nest.rs and model/nest/time.rs use TempoMap, SigPoint and TempoPoint. Also Attr, launch::Quantize, midi_form::Form and value_at. So the model cannot build without the engine.

What to build: move these types and their pure functions into a small crate that has no audio, no threads and no calls to the operating system (the name is your choice, for example paw-music). paw-engine and paw-core both use it. paw-engine re-exports nothing that callers must change twice. No change of behavior.

Read first: TASK-95 (description and notes), backlog/docs/designs/architecture-review.md F1 and F9, crates/paw-engine/src/lib.rs, crates/paw-core/src/model.rs and model/, .claude/skills/rust-skills and its paw-crates.md. The audio thread rules come first.

Do not touch: the Lua API; paw-gui (paused).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The new crate builds with cargo check --target wasm32-unknown-unknown
- [ ] #2 crates/paw-core/src/model.rs and model/ use no paw_engine path (git grep)
- [ ] #3 The Rust tests of paw-engine and paw-core pass, the no_alloc tests too, and the Lua suite passes
- [ ] #4 Docs and skills that name the moved files are searched and fixed; Vale reports 0 alerts
- [ ] #5 (TASK-95.2) session/document/ uses nothing of session.rs or its other submodules (git grep for super:: and crate::session paths)
- [ ] #6 (TASK-95.2) Document has no thread, no std::path::absolute and no Instant::now; a Rust test gives it a fixed time
- [ ] #7 (TASK-95.2) The Rust tests of paw-core and the Lua suite pass with no change of behavior
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Each acceptance criterion is met, and the notes give its evidence
- [ ] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [ ] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [ ] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [ ] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [ ] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [ ] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [ ] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Merged from TASK-95.2 (paw-model 2: Document without session helpers, undo without the disk writer, path and clock as arguments) by the PO on 2026-11-23.

Its description:
Part of TASK-95 (the paw-model crate). Its part-2 agent named these blockers of the crate. It can run beside TASK-95.1.

Today Document (crates/paw-core/src/session/document/) still needs parts of the session:
- Helpers and option types in session.rs and its submodules: de, de_meta, holds, finite, sorted, check_controls, check_fade, TrackOpts, ClipOpts, ClipKind, CustomSet, the stretching checks, ports, midi_out::parse.
- session::undo::Undo holds UndoFile, which owns the writer thread.
- clip_add calls std::path::absolute, and the checkpoint calls Instant::now.

What to build: move the helpers and option types that Document uses next to Document (or into the model). Split UndoFile into the undo tree state (in Document) and the disk writer (in Session). Give the path and the time to Document as arguments or through a clock trait, so that a test can give them. No change of behavior.

Read first: TASK-95 (description and the part-2 notes), crates/paw-core/src/session.rs, session/document/, session/undo.rs, .claude/skills/rust-skills.

Depends on: part 2 of TASK-95 on main.
Do not touch: the Lua API; the audio engine.

PO 2026-11-23: Bundle: the two blockers of the paw-model crate; one agent does both before TASK-95.3. Size L.

PO 2026-11-23 (after batch 14): part 2 of TASK-95 is on main (merge 42c689d6). session/document/ has one file for each area. This ticket can start now. Do not run it at the same time as TASK-96 or TASK-96.2: they change the same files of session/document/.

PO 2026-11-23 (plan V2 bundles): Bundle P95. It can start now on main. Merge it after A1 (TASK-301): both edit model/. W1 needs it merged. EL1 (TASK-292) runs at the same time: give Document the time as a plain value (now); EL1 owns the Clock types. TASK-96 (T96) also edits session/document/: P95 merges first, T96 rebases.

Branch worktree-agent-ae93138aaf2d64997, commits 84f83704 (paw-types) and a0010bb3 (Document without session helpers, undo file on Session, Now argument). AC 1, 2, 4, 5, 6 met; AC 3 and 7: Rust tests pass, the Lua suite waits for a build. Proposed ADR 0033 (paw-types).

Agreement with EL1 (TASK-292): Document::checkpoint takes now: ScheduleTime (crate::clock::ScheduleTime, a newtype over Duration since the start of the clock). The session passes self.now (the time of the turn). move_in_history clears last_sweep and calls checkpoint(ScheduleTime::ZERO). undo.rs last_sweep is Option<(String, ScheduleTime, StateId)>. Sweep merge test: moves_of_one_control_join_one_step_until_a_pause_on_the_schedule_clock (session/document.rs). EL1 owns Clock and ScheduleTime; P95's Now{wall, steady} is rebased onto it.

ADR 0033 (paw-types) accepted by the owner 2026-11-23.

Rebased on 82f0aad0 (batch 21): commits 1e341d4a (paw-types) and 5b6ea56b (Document). Document::checkpoint(now: ScheduleTime, wall: f64): EL1's schedule time for the sweep, the wall time only for the stamp of an undo state. Document::new(wall), undo_reset(wall), Undo::new(project, wall), new_history(project, wall, limits). The session reads history::now(). Now{wall, steady} and the session's Instant dropped. Kinds core deferred to A2 (orphan rule). Lands as batch 22.

PO 2026-11-24: built, waits to merge (batch 21 or 22); status In Progress until it is on main.

On local main in batches 21+22 (4300ace4, 2026-11-24, not pushed). Full suite passed after two fixes (cab47711 a plugin is not work in flight; 4300ace4 the pick test waits for the walk); nix flake check passed.
<!-- SECTION:NOTES:END -->
