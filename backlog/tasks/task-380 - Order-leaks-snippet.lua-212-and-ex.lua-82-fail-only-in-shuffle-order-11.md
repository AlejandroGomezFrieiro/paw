---
id: TASK-380
title: 'Order leaks: snippet.lua:212 and ex.lua:82 fail only in shuffle order 11'
status: In Progress
assignee: []
created_date: '2026-11-24T16:08:00Z'
updated_date: '2026-11-24T16:23:00Z'
labels:
  - test
  - flaky
  - agent:worker
dependencies: []
priority: high
ordinal: 449000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Both pass alone. Found in suite.sh plugins with PAW_TEST_SHUFFLE=11. Find the state that an earlier test leaves (see lua-testing: the state a test makes and puts back) and fix the test that leaks it.
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
Started 2026-11-24: branch order-leaks, base 9f3f2f5c.
<!-- SECTION:NOTES:END -->
