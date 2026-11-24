---
id: TASK-146
title: 'Kernel: a manual clock, one turn of the loop, and quiescence for the tests'
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T13:48:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-143
priority: high
ordinal: 158000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/test-suite-review.md, findings T3 and T4, ticket P2. backlog/docs/designs/testing-practices.md, R13 (deterministic simulation; a seed for the order of work comes later on this seam).

Today schedule time is wall time everywhere (147 reads of `api.now()`, 56 timer sites, 127 `Instant::now` in crates). A test cannot step the kernel loop, and cannot tell "not yet" from "never": `T.until_` polls every 5 ms for 30 s.

What to do (owner decisions 2026-11-22: own trait, not the crate; Option A):
- A small trait `Clock` in `paw-core` with `now()` (a `Duration` since the start) and two adapters, `WallClock` and `ManualClock` (an `AtomicU64` of nanoseconds). One `Arc<dyn Clock>` for the process, given to each reader as an argument or a field, not as a global. `paw --clock manual` selects it.
- Readers of schedule time take the clock: `api.now()`, the timers (`api/timers.rs`), the bake settle, the file watch, the state lanes, the autosave interval.
- `api.now()` becomes the schedule clock. A new `api.real_ms()` gives wall time for budgets. Move the budget readers to it: `limit.tl`, `slices.tl`, `profile.tl`, the slice end of `help.tl`, the timings of `derived.tl`, `paw.opt.budget_ms`, `doctor/report.lua`, `notation/bench.lua` (about 25 sites in 8 files).
- Move the body of the loop in `api.wait` into `Shared::turn()`. Add `api.step()` (one turn) and `api.pending()` (the work in flight, by kind; each subsystem reports its own count).
- In `tests/suite.lua`: `T.settle()`, `T.advance(ms)`, `T.advance_until(cond, what, ms)`. `T.until_` fails at quiescence with "nothing is left to do, and <what> is false". Under the manual clock, `paw.wait(ms)` advances virtual time and settles. One stall guard of wall time in the runner, for all tests. The runner starts paw with `--clock manual`.
- The product part of the lint of TASK-143: `api.now()` in a budget reader fails, and `api.real_ms()` outside the list fails.

Read first: backlog/docs/designs/test-suite-review.md, sections 1 ("What the product code does with time", "The kernel loop in a test"), 3.2 (seams A, B, C), 4 (T3, T4), 9 (questions 2 and 7). .claude/skills/rust-skills.

Overlaps: TASK-114 (the help slices read api.real_ms), TASK-79 (done; budget_ms reads api.real_ms), TASK-121 (the leak check can list timers due on the manual clock).

Size: L.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The test of bake/scheduler.rs runs with no sleep
- [ ] #2 The suite passes with --clock manual; the tests that need real time are marked live
- [ ] #3 T.until_ on a condition that never holds fails at once with "nothing is left to do"
- [ ] #4 The double click, the utau audition throttle and the stretch preview each have a test with T.advance
- [ ] #5 docs/reference/api.md documents api.real_ms, api.step and api.pending; the how-to page documents the helpers
- [ ] #6 The skills .claude/skills/lua-testing and .claude/skills/rust-testing name the new helpers and commands in the same commit.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Coordinator merge hung in custom_clips (slow kind). Finding: paw.limit, the watchdog thread, clip_kind_limit and the socket limit already read the wall clock; the test passes on the manual clock alone and in the full plugins suite. Process limits (TONE3000 auth runs, TONE3000 curl jobs, vinput grace) moved to api.real_ms. Rebased onto main 7228146b: 1dfbe30c (part 2) + a104d552 (fixes: snippets test on T.advance_until, audition throttle test notes in view). Full suite.sh plugins on shared binary cd367da1 + dev runtime: no hang; manual pass 1 failed (audition test, fixed after), live pass all passed. clock.lua job-poll test and search live grep need the TURNS_AT_ONE_INSTANT Rust build.

Landed on main in batch 17 (deb79a0f), with the merge fixes of 2026-11-23 (clock rounding, export leader domain, goldens, MCP render_stems).
<!-- SECTION:NOTES:END -->
