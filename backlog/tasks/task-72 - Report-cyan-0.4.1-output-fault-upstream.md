---
id: TASK-72
title: Report cyan 0.4.1 output fault upstream
status: To Do
assignee: []
created_date: '2026-11-22T06:42:00Z'
updated_date: '2026-11-24T14:21:00Z'
labels:
  - teal
  - tooling
  - agent:worker
milestone: m-8
dependencies: []
priority: low
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
cyan check stops printing after the first file with an error (exit code still right). paw patches one line in nix/lua-tools.nix. Report upstream (teal-language/cyan) with a minimal repro; drop the patch when fixed. Owner may prefer to file it personally.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An issue with a minimal repro is open upstream (teal-language/cyan), or the owner chose to file it
- [ ] #2 When a fixed cyan is in nixpkgs, the patch in nix/lua-tools.nix goes
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
