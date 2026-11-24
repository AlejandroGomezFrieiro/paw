---
id: TASK-371
title: >-
  mixdiag: 'marks above the arrange view, and the summary' fails on main (no
  mark for the clipping)
status: In Progress
assignee: []
created_date: '2026-11-24T14:20:00Z'
updated_date: '2026-11-24T14:37:00Z'
labels:
  - bug
  - tests
  - agent:worker
dependencies: []
priority: high
ordinal: 440000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-11-24: on main 68a663b1 with the debug binary, extensions/mixdiag/tests.lua:599 fails: 'with a mark for the clipping: mix 5: got false, want true' (the output says 'the master clips at bar 3'). The full suite passed 182/182 on the same tree an hour earlier, so the test is flaky or depends on order or state: a flaky test is a bug in the test (AGENTS.md). Find the cause (diagnosing-bugs: a loop that goes red first), fix it, or quarantine it in tests/quarantine.txt with the fix it waits for. Found by the TASK-366 worker and confirmed by its reviewer.
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
