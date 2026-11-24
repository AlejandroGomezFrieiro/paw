---
id: TASK-351
title: 'Dev tools: the Lua suite runs under cargo-nextest'
status: Done
assignee: []
created_date: '2026-11-24T10:53:00Z'
updated_date: '2026-11-24T14:15:00Z'
labels:
  - agent:builder
  - quality
  - foundation
dependencies: []
priority: high
ordinal: 420000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-24: set up the dev tools now to avoid rewrites. Replace the hand-made sharding, slots, TAP, repeat and shuffle of tests/tools/suite.sh with cargo-nextest. A small test crate (for example tests/lua-harness, harness = false, libtest-mimic) lists each Lua test file of tests/suite.lua (and the extensions' test files) as one test; each test runs one paw process (--clean --no-plugins --clock manual --audio step, then the live pass) on PAW_TEST_BIN with the sealed environment of tests/tools/env.sh, and fails with the runner's FAIL text. nextest gives the parallelism and the caps: .config/nextest.toml test-groups (max-threads) replace the suite slots, a profile for the full run, one for 'only' (a filter expression on the test name, so the words of 'only' still work), --partition for CI, slow-timeout and leak-timeout, JUnit output, retries off (a flake is a bug: quarantine stays tests/quarantine.txt, read by the harness). Keep: tests/suite.lua as the in-process runner of one file, T.* helpers, goldens, quarantine, the sealed env. suite.sh becomes a thin wrapper of cargo nextest (same commands for agents and docs) or is removed with every doc and skill updated. Base: after TASK-149 (shard guard) merges.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 cargo nextest run -p <harness> runs the whole Lua suite; a filter runs the tests of some words; the full run's wall time is no worse than suite.sh -j 4 (note it, do not test it)
- [x] #2 No hand-made sharding or slot code is left; parallelism and caps are in .config/nextest.toml
- [x] #3 Quarantine, the sealed environment, PAW_TEST_BIN and the live pass work as before; a test that leaks or hangs fails with a clear message
- [x] #4 docs/how-to/run-the-tests.md, the skills paw-code part 7 and lua-testing, .orchestrator-independent docs and flake.nix's suite check use the new command
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
On local main 679e088c (2026-11-24, not pushed; the owner did the fast-forward, .claude/skills is protected in the sandbox). Full run before the review fixes: 185 s new vs 208 s old, the same failures as main (TASK-357). Review fixes: T.scratch_id, default profile leaves the suite out, harness guard and parts-rule tests, no list paw with --exact. Merge-check of 501fcfd5: clean, 726/726, 24/24 parts. Proposed ADR text in the agent report: to file.
<!-- SECTION:NOTES:END -->
