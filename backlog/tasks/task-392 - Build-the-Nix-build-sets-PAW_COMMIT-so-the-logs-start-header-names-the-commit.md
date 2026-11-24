---
id: TASK-392
title: >-
  Build: the Nix build sets PAW_COMMIT so the log's start header names the
  commit
status: To Do
assignee: []
created_date: '2026-11-24T19:13:00Z'
labels:
  - agent:worker
dependencies: []
priority: low
ordinal: 461000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-391 (2026-11-24): the start header of paw.log says 'commit unknown' in a Nix build. flake.nix sets PAW_COMMIT from self.rev (or self.dirtyRev) at build time; a cargo build in the dev shell gets it from git when it can.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A Nix build's paw.log header names the commit; a dirty tree says so
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
