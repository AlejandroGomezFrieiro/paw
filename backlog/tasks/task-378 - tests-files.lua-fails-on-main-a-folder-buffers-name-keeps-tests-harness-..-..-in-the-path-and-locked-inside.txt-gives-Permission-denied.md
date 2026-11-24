---
id: TASK-378
title: >-
  tests/files.lua fails on main: a folder buffer's name keeps
  tests/harness/../.. in the path, and locked/inside.txt gives Permission denied
status: In Progress
assignee: []
created_date: '2026-11-24T15:47:00Z'
updated_date: '2026-11-24T16:49:00Z'
labels:
  - bug
  - tests
  - agent:worker
milestone: m-12
dependencies: []
priority: high
ordinal: 447000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-11-24, merge tree on e35d8ac5 with the debug binary: cargo nextest -p paw-lua-suite --profile lua -E 'test(=tests/files.lua)' fails. (1) 'a folder is a buffer: folders first, then files, ...' tests/files.lua:125: got paw://files/<scratch>/target/test-scratch/..., want paw://files/<scratch>/tests/harness/../../target/test-scratch/...: the test builds its want from a path that is not canonical, while paw gives the canonical one. (2) a test on locked/inside.txt fails with Permission denied (seen by the typed API builder in its worktree). The full suite passed 182/182 earlier the same day, so find what changed (the suite under nextest, PAW_TEST_SCRATCH, the sandbox) and make the test compare canonical paths and make no assumption the sandbox breaks. A test reads nothing of the machine (tests/tools/env.sh).
<!-- SECTION:DESCRIPTION:END -->

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
2026-11-24 later: in the full merge-check suite run (suite.sh, all parts) tests/files.lua PASSED; it fails when run alone with cargo nextest -p paw-lua-suite --profile lua -E 'test(=tests/files.lua)'. So the failure depends on how the part is started (the scratch path: tests/harness/../.. vs target/merge-scratch), not on the product.

Started 2026-11-24: branch files-path, base 1e19cb1c.
<!-- SECTION:NOTES:END -->
