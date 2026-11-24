---
id: TASK-154
title: 'Engine: one integration-test binary'
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T11:14:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies: []
priority: low
ordinal: 166000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/testing-practices.md, practice R9, gap G7, ticket BT3.

`crates/paw-engine/tests` has 13 files, and each links `paw-engine` again. Move them into `tests/it/main.rs` with a module for each area. Keep `no_alloc.rs` as its own binary: it sets a global allocator for its process.

Read first: backlog/docs/designs/testing-practices.md, sections 2.1 (R9), 6 (BT3).

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The same test names pass
- [x] #2 The link time of cargo nextest run -p paw-engine --no-run is lower (number in the commit, for information)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done on branch worktree-agent-adbfe1e2c248873d4, commit 2cb36c4c (main 8e91e5b0 merged in, up to date). The 12 files of crates/paw-engine/tests are modules of tests/it/main.rs; no_alloc.rs stays a separate binary. Shared SR and send in tests/it/common.rs (6 copies removed). 45 tests before and after; names get a module prefix (clips::x). Skill rust-testing, tests/timing-allowed.txt, a paw-core comment and bench/RESULTS.md name the new paths. AC2 link time: not measured (agents do not build); orchestrator measures cargo nextest run -p paw-engine --no-run before/after and can amend the commit.

Merged to main in batch 15 (2f970bba); full suite and checks passed.

Code merged in batch 15 (2f970bba). Left: the measurement in its criteria (orchestrator runs it on the build).

2026-11-23: link time 2.61-2.78 s before, 2.04-2.12 s after, in bench/RESULTS.md (7228146b).
<!-- SECTION:NOTES:END -->
