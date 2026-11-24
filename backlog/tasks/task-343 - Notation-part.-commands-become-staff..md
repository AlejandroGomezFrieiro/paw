---
id: TASK-343
title: 'Notation: :part.* commands become :staff.*'
status: To Do
assignee: []
created_date: '2026-11-24T06:09:00Z'
updated_date: '2026-11-24T07:59:00Z'
labels:
  - notation
  - ux
  - agent:worker
milestone: m-17
dependencies: []
priority: medium
ordinal: 412000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-24: after W1 the notation extension's :part.* commands clash in name with the core :part.* commands. Rename them :staff.* (commands, keys help, README/doc pages, tests, the tutor if it names them). No compatibility alias (no release yet).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The notation extension defines no :part.* command; :staff.* gives the same actions
- [ ] #2 Its README and doc/ pages name the new commands; the extension doc test passes
- [ ] #3 partlint, Vale and the notation tests pass
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
