---
id: TASK-7.2
title: 'Subprojects S2a: copies share compiled events'
status: Done
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T13:25:00Z'
labels:
  - nest
  - subprojects
  - performance
  - engine
milestone: m-2
dependencies: []
parent_task_id: TASK-7
priority: medium
ordinal: 2500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: when the same notes play in several places, paw compiles them one time and the engine shares one event list. Today an edit inside a nest compiles every copy again: 1.9 ms at 96 notes and 17.5 ms at 384 notes per copy, 90 to 350 times a plain edit (nest.md section 8, the N0 spike). Subprojects (TASK-7.4), linked clips (TASK-85.1) and plain duplicates all gain.

What to build (the design change of section 8):
- Copies keep a stable identity across syncs, and the compiled events are cached by what they are made from (the shared runs of notes), not by the clip id.
- The engine's clip parts take a beat offset (`paw_engine::Part`), so that every instance shares one `Arc<[MidiEv]>` and plays it from its own start.
- A cut at the start of a window shifts the notes (and leaves out notes before it): measure it, as N0 did not.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Section 8 ("N0 results"). crates/paw-core/src/sync/clips.rs (`Parts`, `SentClip`, `Piece`, `pieces_of`), crates/paw-core/src/sync/mod.rs, crates/paw-core/src/model/notes.rs (runs), crates/paw-engine/src/clip.rs (`Part` near line 357, `PartEdit`), crates/paw-engine/src/engine/regions.rs, bench/nest.sh (the N0 benchmark), crates/paw-engine/tests/clips.rs, tests/no_alloc.rs, .claude/skills/rust-skills.

Depends on: nothing. It can start now, beside the view parts.
Do not touch: `clip_list` in session/clips.rs (TASK-14), the engine's process loop (TASK-16, TASK-80).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: 100 duplicates of a 384-note clip; one note edit compiles the events one time (a test counter of compiles)
- [ ] #2 bench/nest.sh: an edit with 100 copies costs at most 2 times a plain edit (it was 90 to 350 times); numbers with spread in bench/RESULTS.md
- [ ] #3 A render is bit-identical before and after the change (the render tests and a Rust test with copies, loops and cut windows)
- [ ] #4 crates/paw-engine/tests/no_alloc.rs passes; the engine's memory for 1 000 copies is about one event list
- [ ] #5 cargo test --release -p paw-core and -p paw-engine pass; the Lua suite passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-aea5a28d8aec5319c (commit edd5230f, merged with main in fca4d315). The sync compiles MIDI events from the clip's start, cached by what they are made from (runs by identity, controls, length, loop) in sync::clips::Compiled; paw_engine::Part::with_offset plays a shared Arc<[MidiEv]> from each copy's start. AC1 test an_edit_of_notes_that_copies_share_compiles_them_once (100 copies, 1 compile; 1000 copies hold one list per piece = AC4). AC3: test copies_that_share_events_play_as_events_compiled_in_place (copies, loops, cut windows, short) + a paw render before/after byte-identical. AC2 partly met: bench/nest.sh 100 copies x 384 notes, edit of shared notes 1.886 -> 0.057 ms = 2.3x a plain edit (sync alone 1.8x); at 96 notes 3.4x (sync alone 2.3x); remaining ~0.3 us per copy (copy remade, its engine part, its event). Numbers in bench/RESULTS.md. no_alloc, paw-core, paw-engine and the plugins suite pass (one help timing test failed under load 60-85 and passes alone).
<!-- SECTION:NOTES:END -->
