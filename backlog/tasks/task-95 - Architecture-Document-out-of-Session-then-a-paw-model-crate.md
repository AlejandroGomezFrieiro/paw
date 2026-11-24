---
id: TASK-95
title: 'Architecture: Document out of Session, then a paw-model crate'
status: To Do
assignee: []
created_date: '2026-11-22T10:38:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-10
dependencies: []
priority: high
ordinal: 98000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: move the model state, the edits and undo out of Session into a Document module that needs no engine, then into a new crate paw-model with no calls to the operating system. Finding F1 of the architecture review (backlog/docs/designs/architecture-review.md).

Today: Session (crates/paw-core/src/session.rs, lines 498 to 568) has 30 fields and 208 public methods in 33 files. Session::new starts the engine, so a Rust test of an edit needs an engine; the session has 18 Rust tests. 45 methods touch only the model.

Parts, one branch each, no change of behavior:
1. session/document.rs: Document { project, undo, next_id, dirty, named, clip_kinds, events, warnings } with edit, edit_named, new_id, undo, redo and the methods that touch only the model. Session keeps pub doc: Document; sync still compares synced with doc.project.
2. One branch for each area (tracks, clips, devices, lanes): its field logic moves to impl Document; what needs the engine stays on Session.
3. Split model.rs into model/project.rs, track.rs, clip.rs, lane.rs, check.rs.
4. Crate paw-model: model, history, attr_map, clipfile, edits, events, Document, and layout/read of session/folder.rs (commit stays in paw-core). CI builds it for wasm32.

Read first: the review, F1 and F9; crates/paw-core/src/session.rs; session/editing.rs; sync/mod.rs (the rule: only sync tells the engine); backlog/docs/designs/web.md (blockers by crate); TASK-51; .claude/skills/rust-skills.

Depends on: the ticket for the paw-core interface (F4) helps; not required.
Do not touch: the audio engine; the Lua API (paw.api stays the same).

Size: L (4 or 5 branches).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Session holds a Document; the methods that touch only the model are on impl Document
- [x] #2 Rust tests of edits and undo run without an engine (no Session::new)
- [ ] #3 paw-model builds with cargo check --target wasm32-unknown-unknown
- [ ] #4 The Lua suite passes with no change of behavior; docs that name session files are searched and fixed
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
Part 2 done on branch worktree-agent-ac951eb572a1ac26a (16 commits 53ae2a7c..3f65bf0a, merge of main 2839f9f7; not merged). Session::edit/edit_named removed: FileCheck::after(Document::changes()) forgets the file answers after any edit. session/document/ now has one file per area with impl Document: tracks (view/field/add/remove/move/set->ControlMove/collect/attr_delay), tempo, notes, links, clips (add with a sound_seconds reader, set, remove, kinds, custom, notes, controls, collect with an is_file check, clip_to_cues, move_cue, check_clip_track), nests, automation (ParamRange argument for plugin ranges), devices (remove/move/set), project (view/field/set with path), undo_tree (tree/limits/current/keep/label/join/keys/adjust_cancel/discard/reset). 78 pub methods on Document. Session keeps thin wrappers: track_set (automation write), clip_add, clip_set, clip_collect, lane_view/list/set/set_points, project_view/field/set; lane_add stays (asks the plugin). paw.api unchanged; api/*.rs call session.doc. New Rust tests with no engine: tracks (ControlMove), clips (audio length from reader; collect skips a missing file), automation (range clamp). Part 3/4 blockers: paw_engine types in model.rs, tempo, attr_map, clipfile, edits, automation value_at; session.rs helpers (de, holds, finite, sorted, check_controls, check_fade, ClipOpts, TrackOpts, ClipKind, CustomSet), session::stretching/ports/midi_out, session::undo::Undo holds UndoFile (writer thread); std::path::absolute in clip_add; Instant::now in checkpoint.

Part 2 done on branch worktree-agent-ac951eb572a1ac26a (3f65bf0a + merge 2839f9f7), batch 14. Blocks to part 3 (the paw-model crate), largest first: (1) paw_engine types in the model (TempoMap, SigPoint, TempoPoint, Ctl, EventKind, NoteCtl, launch quantize, MIDI form; value_at, Attr) must move to an engine-free crate; (2) helpers and option types in session.rs and its submodules (de, de_meta, holds, finite, sorted, check_controls, check_fade, TrackOpts, ClipOpts, CustomSet, stretching checks, ports, midi_out::parse); (3) split UndoFile into the tree state and the disk writer; (4) std::path::absolute and Instant::now in Document become arguments or a clock.

From TASK-209: for part 3, move TempoMap, Attr and the other engine types the model uses into a crate that both the model and paw-engine use.

PO 2026-11-23: the part-3 blockers that the part-2 agent named have subtasks: TASK-95.1 (engine types to a crate without the engine), TASK-95.2 (Document without session helpers, undo without the writer, path and clock as arguments), TASK-95.3 (split model.rs, the paw-model crate, wasm32 check). When part 2 merges, the rest of this ticket is in these three.

Part 2 merged to main in batch 14 (23350734).

PO 2026-11-23 (after batch 14): main has session/document/ with impl Document per area and Session.doc; Rust tests of edits run without an engine (tracks, clips, automation, notes). AC 1 and 2 are met. AC 3 (paw-model for wasm32) and AC 4 (no change of behavior through the whole split) are left; they are TASK-95.1 and TASK-95.3.
<!-- SECTION:NOTES:END -->
