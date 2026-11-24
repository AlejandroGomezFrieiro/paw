---
id: TASK-335
title: Extension split kinds go when the extension unloads
status: Done
assignee: []
created_date: '2026-11-23T21:01:00Z'
updated_date: '2026-11-24T09:58:00Z'
labels:
  - agent:builder
milestone: m-16
dependencies:
  - TASK-301
priority: medium
ordinal: 404000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From A1 (TASK-301): Kinds::unload exists, but nothing calls it for split kinds that an extension declared with paw.chain.define_kind (owner Owner::Extension). Call it from the extension unload path, so the kind goes and a split of it becomes absent (it keeps its bytes).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A test extension defines a split kind; :ext.unload removes it; a project split of that kind loads as absent and saves the same bytes
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
PO 2026-11-24: starts after A1 (TASK-301) merges: Kinds::unload and paw.chain.define_kind come from it. Size S: give it to the agent of a nearby bundle (G2 or CL2 follow-up).

Wave 23 (2026-11-24), base 9cecbfdc (batches 20-22 + W1).

Done in 9f4916ff (test in tests/chain.lua).

On local main (795c22ca, 2026-11-24, not pushed). Review fixes done; merge-check green: lints, clippy 0, nextest 676/676, suite words incl. golden all passed.
<!-- SECTION:NOTES:END -->
