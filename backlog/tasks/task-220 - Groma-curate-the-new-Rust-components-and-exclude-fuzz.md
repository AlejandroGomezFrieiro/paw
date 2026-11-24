---
id: TASK-220
title: 'Groma: curate the new Rust components and exclude fuzz/'
status: To Do
assignee: []
created_date: '2026-11-23T06:42:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - groma
  - tools
milestone: m-7
dependencies: []
priority: low
ordinal: 248000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-209: a scan added 75 components (new Rust files, fuzz/), 4 new containers (paw-remote, paw-clip-file, paw-project-folder, paw-terminal-keys) and about 35 Rust components in 'Unidentified container'. Exclude /fuzz/ in groma/config.json and curate the rest.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 groma/config.json excludes /fuzz/, and a scan creates no fuzz component
- [ ] #2 No Rust component is left in Unidentified container; the four new containers have a title and a description
- [ ] #3 Two scans in a row report created 0; git status shows no change of files that git tracks
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
PO 2026-11-23: criteria added. Size: S. Local tool: groma/ is not committed.
<!-- SECTION:NOTES:END -->
