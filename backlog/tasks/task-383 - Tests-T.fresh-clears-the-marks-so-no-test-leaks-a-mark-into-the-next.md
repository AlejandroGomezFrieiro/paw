---
id: TASK-383
title: 'Tests: T.fresh clears the marks, so no test leaks a mark into the next'
status: To Do
assignee: []
created_date: '2026-11-24T16:46:00Z'
labels:
  - test
  - agent:worker
dependencies: []
priority: medium
ordinal: 452000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the review of the order-leaks fix. Marks survive T.fresh: tests/pick.lua leaked mark q (fixed per test), tests/ex.lua:74-76 and :458 set marks a and b and never remove them, and tests/marks.lua:15 clears marks by hand. Clear all marks in T.fresh (the product-level reset), then drop the per-test cleanups that it makes useless. Also from the review: a snippet added from an extension's callback or timer has no owner, so paw.ext.unload does not remove it; say so in the doc of paw.snippet or find the owner another way.
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
