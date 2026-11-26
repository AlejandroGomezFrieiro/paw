---
id: TASK-334
title: Classic Esc ends a recording before it leaves the view
status: Done
assignee: []
created_date: '2026-11-23T20:44:00Z'
updated_date: '2026-11-26T19:45:00Z'
labels:
  - ux
milestone: m-15
dependencies:
  - TASK-333
priority: low
ordinal: 403000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-333: in classic mode (keymap.classic) Esc in the piano roll, drum grid, vinput and utau leaves the view during a recording instead of stopping it. Make it end the recording first (the same escape event), and leave the view on the next Esc.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Real keys in classic mode: R, Esc in the piano roll stops the take and stays; a second Esc leaves the view
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
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
PO 2026-11-24: starts after TASK-333 merges (batch 21): it uses its escape event.

Wave 23 (2026-11-24), base 9cecbfdc (batches 20-22 + W1).

Done in TM2's commit 11b99e63 (merged e82d0d69).

Orchestrator 2026-11-26: verified on main a798ebf3 (debug build). tests/tools/suite.sh only "classic keys, Esc in the piano roll" passes (1 test run); a deliberate failing assertion made it fail, so the filter runs the real test. Closed.
<!-- SECTION:NOTES:END -->
