---
id: TASK-145
title: >-
  Tests: the tiers, the quarantine list, and one Lua runner (binary check, times
  per file, repeat, shuffle, CI file)
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-146
priority: high
ordinal: 157000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/testing-practices.md, practices P4 (tiers) and P5 (flake policy), gaps G10 and G11, ticket BT1, rank 3.

The checks that run before a commit, a merge, a push and a release are spread over AGENTS.md, memory notes and TASK-42. AGENTS.md has the flake policy, and tests/quarantine.txt exists with one entry (the stretch preview test, TASK-207). The runner does not read the file yet: a failure of a listed test still fails the run.

Since commit 54864130 (2026-11-23), tracked files name no local ticket (the board is local). A quarantine line names the fix in words, not a TASK id. This ticket follows that rule.

What to do:
- Write one list of the tiers and their commands in the skill paw-code, and link it from lua-testing and rust-testing: the edit loop (one crate, only); before a commit (the affected tests, the lints); before a push (the full suite, nix flake check, cargo nextest run --profile gate); nightly (fuzz runs, more proptest cases, more seeds of the edit fuzzer, cargo mutants --in-diff, coverage); release (e2e, plugins, platforms). The nightly tier runs in CI only, not on the local machine (owner, 2026-11-22).
- The Lua runner reads tests/quarantine.txt: one line, the full test name, a tab, the fix. It runs a listed test, prints "quarantined" for its failure, and does not fail the run. A line with no fix text fails the runner. A listed test that passes is reported, so that its line can go when the fix is merged.
- Rust: a quarantined test is #[ignore = "quarantine: <the fix>"] and has a line in tests/quarantine.txt. The tier before a push runs the ignored quarantined tests and reports them.
- No retries anywhere (nextest keeps retries = 0).
- Remove the sentence 'The runner does not read this file yet' from tests/quarantine.txt.

Read first: backlog/docs/designs/testing-practices.md, sections 2.4 (P4, P5), 3.2, 6 (BT1). AGENTS.md, 'How to work'. tests/quarantine.txt. tests/tools/suite.sh and tests/suite.lua.

Overlaps: TASK-42 (the release tier and CI, where the nightly tier runs). TASK-151 (repeat and shuffle find a flake).

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The tier list exists in the skill paw-code and names each command of each tier; lua-testing and rust-testing link it
- [x] #2 The Lua runner reads tests/quarantine.txt and prints quarantined for a failure of a listed test, and the run does not fail (a runner test with a fixture test that always fails)
- [x] #3 A quarantine line with no fix text fails the runner with a message that names the line
- [x] #4 A quarantined Rust test is ignored with the fix in its reason, and the tier before a push runs and reports it
- [x] #5 No file that git tracks names a local ticket id (git grep TASK- finds none in the changed files)
- [x] #6 (TASK-151) An old binary with a new runtime fails at the start with a clear message
- [x] #7 (TASK-151) times.txt exists after a run
- [x] #8 (TASK-151) repeat 20 of a test that depends on order or time fails within the 20 runs (shown on one known flake)
- [x] #9 (TASK-151) --shuffle prints its seed, and the same seed gives the same order
- [x] #10 (TASK-151) The CI file lists each test with its result and its skip reason
- [x] #11 (TASK-151) The skills .claude/skills/lua-testing and .claude/skills/rust-testing name the new helpers and commands in the same commit.
- [x] #12 (TASK-151.1) An old binary with a new runtime fails at the start with a clear message (a test of the runner with a wrong stamp)
- [x] #13 (TASK-151.1) cargo test -p paw-tui --test suite and tests/tools/suite.sh run the same runner
- [x] #14 (TASK-151.1) times.txt exists after a run, one line for each file
- [x] #15 (TASK-151.1) The skills lua-testing and rust-testing name the change
- [x] #16 (TASK-151.2) repeat 20 of a test that depends on order fails within the 20 runs (shown on a fixture test that fails on its second run)
- [x] #17 (TASK-151.2) --shuffle prints its seed, and the same seed gives the same order
- [x] #18 (TASK-151.2) The CI file lists each test with its result and its skip reason
- [x] #19 (TASK-151.2) bench/fuzz.lua takes its seed from the command line
- [x] #20 (TASK-151.2) The skills and the how-to page name the new commands; Vale reports 0 alerts
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
Built on branch worktree-agent-a8062e24546374fe4, commit 29d60d1d (on 2f70b19f, with TASK-158). Runner reads tests/quarantine.txt (quarantined/passed reports, a line with no fix fails at the start); binary check against runtime/types/paw.lua; times.txt and suite.tap (TAP) per run; suite.sh repeat N and --shuffle [seed]; suite.rs runs suite.sh; Rust quarantine = ignore + line, checked by tools/testlint.lua, run by tests/tools/quarantine.sh. Tiers and CI matrix in paw-code part 7. bench/fuzz.lua already took its seed from the command line (nightly: seeds 1 to 50). tests/runner.lua tests the runner on fixture folders. Not shown: repeat 20 on the stretch flake failed 0 of 20 on this machine; repeat is shown on a fixture.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (29d60d1d). Runner with tests/quarantine.txt, binary check, times.txt, suite.tap, repeat N, --shuffle [seed]; suite.rs runs suite.sh; Rust quarantine through ignore and testlint; tiers in paw-code part 7; tests/runner.lua tests the runner on fixtures. Repeat is shown on a fixture, not on a real flake.
<!-- SECTION:FINAL_SUMMARY:END -->
