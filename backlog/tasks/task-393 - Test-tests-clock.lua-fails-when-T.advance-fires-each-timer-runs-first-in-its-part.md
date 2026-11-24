---
id: TASK-393
title: >-
  Test: tests/clock.lua fails when 'T.advance fires each timer' runs first in
  its part
status: To Do
assignee: []
created_date: '2026-11-24T19:22:00Z'
labels:
  - agent:worker
dependencies: []
priority: medium
ordinal: 462000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-391 (2026-11-24), already on base 39e07dcf: with only that test first, after api.settle() at startup timers_due is 1 and timers 2, so the test sees a due timer it did not make. Reproduce: run tests/clock.lua 30 times under -j4 with the test first (fails on run 1). Find the startup timer that is still due after settle (a deferred job of the runtime) and make settle drain it, or make the test wait for an empty queue first. No retries.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tests/clock.lua passes 30 of 30 under -j4 with that test first
<!-- AC:END -->

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
