---
id: TASK-24
title: 'E2E goldens: re-approve after FX1/FX2'
status: To Do
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-24T14:21:00Z'
labels:
  - tests
  - release
  - agent:worker
milestone: m-6
dependencies: []
priority: medium
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The e2e expected outputs changed (FX1/FX2, stems path). Only the E2E builder or the release check runs e2e.sh.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The E2E builder or the release check runs tests/tools/e2e.sh; the changed goldens (FX1, FX2, the renders/ path of stems) are approved again for seeds 1 to 3, each change with its reason
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Better testing (2026-11-22): TASK-143 changes the e2e speed check of the keys (tests/e2e/lib.lua:158 and :320) to a report line, not a failure.

Board review 2026-11-23: still open. tests/e2e/golden has no commit after the FX1 and FX2 merges. Only the release check runs e2e.sh.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): The e2e golden outputs change again after W1, LA and MX (architecture-plan.md V2.8, V2.10 m-6). Approve them one time after MX, or once now and again after each of these bundles.
<!-- SECTION:NOTES:END -->
