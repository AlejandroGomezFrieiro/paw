---
id: TASK-340
title: >-
  The plugins pass of the suite: plugstate, Surge XT snapshot and the plugin
  setting guide fail
status: To Do
assignee: []
created_date: '2026-11-24T03:00:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:worker
milestone: m-12
dependencies: []
priority: medium
ordinal: 409000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen by the EL2 agent on 2026-11-24 in 'tests/tools/suite.sh plugins' (scratch HOME): 6 plugstate tests fail (same on the batch 22 merge binary); 'a plugin takes a snapshot back at rest…' fails with 'vst3:Surge XT: u gives B back to the plugin: got 0, want 1' (same on c04f8ae9, before EL2); 'guide: find and change a setting inside a plugin' fails with guides_howto.lua:435 'attempt to concatenate local want (a nil value)' (same before EL2). Find each cause; fix at the source.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 suite.sh plugins passes apart from the quarantined tests
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
