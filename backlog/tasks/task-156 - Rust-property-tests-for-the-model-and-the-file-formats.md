---
id: TASK-156
title: 'Rust: property tests for the model and the file formats'
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-145
priority: medium
ordinal: 168000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/testing-practices.md, practice R4, gap G3, ticket BT6, rank 6. Owner, 2026-11-22: proptest as a dev-dependency.

The parsers and the model have example tests only.

What to do: property tests in `paw-core` with proptest: `.midi2` clip decode of encode; the undo file round trip; the XML (DAWproject) round trip of the parts that paw writes; the tempo map (beats to seconds to beats); the attribute map; an undo of a random change gives the old project. Commit `proptest-regressions/`.

Read first: backlog/docs/designs/testing-practices.md, sections 2.1 (R4), 4, 5.1 ("Property tests"), 6 (BT6).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each property is one test
- [ ] #2 The normal run uses the default count of cases (a count, not a timer)
- [ ] #3 The nightly tier runs them with PROPTEST_CASES=10000
- [ ] #4 The skills .claude/skills/lua-testing and .claude/skills/rust-testing name the new helpers and commands in the same commit.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a420e3f0b94bb7ce5, commits a4b9aa6a (work) and b29e8545 (merge main). proptest 1.11 workspace dev-dependency (std only). Six properties, one test each, in <module>/props.rs: clipfile (2: decode of encode on ticks; bytes read and written again), undofile, xml (DAWproject form: indent, 12 digits), attr_map (project file round trip), model (undo/redo of random edits through Arc/Notes/Clips runs), paw-engine tempo (beat to seconds to beat, limit 1e-6). crate::props::config(): default count (256), fixed seed unless PROPTEST_RNG_SEED. Nightly command in rust-testing part 15; TASK-145/TASK-42 must put it in the nightly tier. Found and fixed TASK-169 (non-ASCII meta in .midi2). Not run here (agents do not run cargo test): orchestrator runs cargo nextest run -p paw-core -p paw-engine -E 'test(/::props::/)'. No proptest-regressions files yet: none fail to write them.

Orchestrator: after TASK-155 and 156 are both on main, prune the example tests that a property now covers (clipfile notes_before_the_start_and_overlaps_on_one_key, long_gaps_take_several_clockstamps; parts of tempo ramps_up_and_round_trips).

At the merge with TASK-173 (clipfile::encode now returns Result; clip times limited to ±1e6 beats, model::MAX_BEATS): add .unwrap() to the four encode calls in clipfile/props.rs, and keep the generators' times inside ±1e6 beats.
<!-- SECTION:NOTES:END -->
