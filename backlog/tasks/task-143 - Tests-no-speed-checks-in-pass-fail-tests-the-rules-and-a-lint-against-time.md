---
id: TASK-143
title: 'Tests: no speed checks in pass/fail tests; the rules and a lint against time'
status: Done
assignee: []
created_date: '2026-11-22T20:26:00Z'
updated_date: '2026-11-22T22:41:00Z'
labels:
  - tests
  - better-testing
milestone: m-3
dependencies: []
priority: high
type: chore
ordinal: 155000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: test-suite-review.md, findings T1 and T2, ticket P1. testing-practices.md, rank 3 and R10 (count work in place of time).

About 25 assertions in the suite compare wall time, processor time or a share of a processor with a limit. They fail under load or in a dev build. Agents then decide "only timing" at each merge.

What to do:
- Remove each speed assertion of the table "What moves to bench" (review, section 3.5). Keep the behavior that it guards. Where cost is the behavior, count the work (compiles, renders, builds). Move the measure to `bench/` where no bench has it yet.
- Move `tests/tools/speed.lua` (`T.quick`, `T.cpu_ms`) to `bench/lib.lua`. Delete `extensions/notation/tests_speed.lua`.
- The e2e speed check of the keys (`tests/e2e/lib.lua:158`, `:320`) becomes a report line, not a failure.
- Write the rules of section 3.1 in `docs/how-to/run-the-tests.md` (external text: plain-writing). Remove the advice to give a wait "the time that the slowest machine needs", and the advice to use `T.quick`. AGENTS.md, prune-tests and the skills lua-testing and rust-testing already have the rules (the Better testing setup commit). Make them name the lint.
- Add `tools/testlint.lua` with `tests/timing-allowed.txt` (one line `<file> <pattern> <count>`, with the counts of today). A count that goes up fails. A count that goes down fails until the line is made smaller. Run it in the suite and in `nix flake check`.

The window is paused (owner, 2026-11-22): do not change, build or test `crates/paw-gui`. The CPU tests of `window.rs` move in the window ticket. The lint skips `crates/paw-gui` until the window work starts again.

Read first: backlog/docs/designs/test-suite-review.md, sections 1 ("Speed assertions in pass/fail tests"), 3.1, 3.4, 3.5, 4 (T1, T2) and 6. .claude/skills/lua-testing and rust-testing.

Overlaps: TASK-114 (the help test stops checking the slice length; TASK-114 measures it in bench/profile). TASK-24 (the e2e speed check). TASK-121 (the format of tests/leaks-allowed.txt).

Size: S to M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No T.quick, T.cpu_ms, os.clock or comparison of a time with a number in a pass/fail test (outside crates/paw-gui)
- [ ] #2 Each removed measure is in bench/ or was there already; the commit names it
- [ ] #3 The lint fails on a new api.sleep( in a test file, and nix flake check runs it
- [ ] #4 tests/timing-allowed.txt exists, with a count for each file and pattern
- [ ] #5 docs/how-to/run-the-tests.md has the rules and no advice that accepts time as pass or fail; Vale reports 0
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a347385efa018b4b1, commit cb03f205 (main merged, already up to date). Removed every speed assertion of review 3.5 outside paw-gui. New bench/heavy.lua holds the moved measures (notation open and moves, picker, search, legato, pattern errors, help slices, utau block). tests/tools/speed.lua deleted (cpu_ms and load in bench/lib.lua), extensions/notation/tests_speed.lua deleted. e2e slowest key is a report line. tools/testlint.lua + tests/timing-allowed.txt + tests/testlint.lua (suite) + flake check testlint. Docs: run-the-tests.md rules; AGENTS.md, lua-testing, rust-testing, prune-tests name the lint. Left for later: remote.rs pace counts and 'at once < 500 ms' (TASK-146/150); offline 'several plugins at once' needs a sandbox count (TASK-148). Rust tests to run: cargo test -p paw-tui --test safety --test remote.

Merged to main (batch 3, 2026-11-23): dev build, nextest paw-core/engine/tui, full suite with plugins passed. At the merge: tests/suite.lua stamp check joined with TASK-121's runner; roll_context.tl's local paw renamed (strict tl check).
<!-- SECTION:NOTES:END -->
