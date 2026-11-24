---
id: TASK-324
title: 'utau: the vocal head with the singer''s picture and \s'
status: To Do
assignee: []
created_date: '2026-11-23T17:01:00Z'
updated_date: '2026-11-24T14:22:00Z'
labels:
  - agent:worker
milestone: m-18
dependencies:
  - TASK-323
references:
  - backlog/docs/designs/lane-heads.md
priority: low
ordinal: 393000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/lane-heads.md section 6 (the vocal sketch) and screens 8.2. The picture comes from the singer's image field of the OpenUtau protocol (extensions/utau/lua/utau/proto.lua:278); check that real singers fill it (stub engine in tests, never the owner's data).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Golden screens 8.2: default and wide with half blocks, narrow and one row without a picture
- [ ] #2 \s on a vocal row chooses the singer; on another row it does nothing
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
