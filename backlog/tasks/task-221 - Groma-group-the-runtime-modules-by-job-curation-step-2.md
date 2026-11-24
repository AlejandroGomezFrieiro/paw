---
id: TASK-221
title: 'Groma: group the runtime modules by job (curation step 2)'
status: To Do
assignee: []
created_date: '2026-11-23T06:42:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - groma
  - tools
milestone: m-7
dependencies:
  - TASK-206
priority: low
ordinal: 249000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Step 2 of TASK-26's proposal: group the 165 runtime modules (Views, Pickers, LSP client, Roles, Harmony, Defaults...). Waits for TASK-206, which moves modules.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The runtime modules are in groups by job (for example Views, Pickers, LSP client, Roles, Harmony, Defaults) and no runtime module is outside a group
- [ ] #2 Two scans in a row report created 0; git status shows no change of files that git tracks
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
PO 2026-11-23: criteria added; depends on TASK-206, which moves modules.
<!-- SECTION:NOTES:END -->
