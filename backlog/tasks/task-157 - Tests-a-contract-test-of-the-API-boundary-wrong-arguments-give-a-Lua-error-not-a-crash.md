---
id: TASK-157
title: >-
  Tests: a contract test of the API boundary (wrong arguments give a Lua error,
  not a crash)
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T16:34:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies: []
priority: medium
ordinal: 169000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/testing-practices.md, practice P2 (polyglot), gap G6, ticket BT7, rank 4.

Rule 6 ("each failure gives a clear message, not a stack trace") is a property of the whole API. `tests/robust.lua` checks some calls by hand.

What to do: a Lua test that reads the API list (the data that `tools/apidoc.lua` reads) and calls each `paw.api` function with wrong arguments: no arguments, a wrong type for each one, a deleted id, a negative and a huge number, a long string. Each call gives a Lua error with the name of the function in the message, or a documented result. No call panics, aborts, stops answering, or changes the project without an undo step. An allow-list holds the functions that a test cannot call safely (for example the ones that quit), each with a reason.

Read first: backlog/docs/designs/testing-practices.md, sections 2.4 (P1, P2), 4, 6 (BT7).

Overlaps: tests/robust.lua (move its hand checks here where they repeat), TASK-133 (its reader of the API can feed this test).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every API function is called, or is on the allow-list with a reason
- [ ] #2 A panic in a Rust function of the API fails the test with the name of the function
- [ ] #3 Each bug found has its own fix and test
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a4326e4698fb695a9, commits 2f6db015 (work) and cd5c08c2 (merge of main). tests/api_boundary.lua walks every paw.api function (types from the Rust source through tools/apidoc.lua kernel_functions), with NOT_CALLED (reasons) and SHAPES (restores). guarded! in crates/paw-core/src/api/mod.rs: bad-argument errors name paw.api.<name>, a panic becomes 'paw.api.<name> stopped on a bug in paw: ...', paw-tui hooks skip terminal restore and safety copy for it. test_panic(why, inside). Fixes: cell() clamp (grid overflow), tempo bar_length saturating, millis() for timer/sleep/wait/audio_watch, project_save("") refused, hl_set wrapper order. Old walker removed from tests/robust.lua. Needs the new build: the walk, the panic test and the empty-path test fail on the old binary (and the old binary writes project files into the checkout from project_save("")).

Merged batch 7 (f1b087ae) as e86bb15e: nest_reader! guards the nest_* readers, fs_trash keeps trash_root inside guarded!, apidoc patterns find reader!( and nest_reader!(.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.

The reader of the API list is loadfile("tools/apidoc.lua")("module").kernel_functions() or .model() (TASK-133).
<!-- SECTION:NOTES:END -->
