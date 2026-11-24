---
id: TASK-373
title: >-
  archlint: a bundle marked done in the roadmap has all its tickets Done, and
  the other way round
status: To Do
assignee: []
created_date: '2026-11-24T14:30:00Z'
labels:
  - tooling
  - architecture
  - agent:worker
milestone: m-6
dependencies: []
priority: medium
ordinal: 442000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Retro 2026-11-24: the roadmap marked HD and TM2 done while TASK-323 and TASK-328 were In Progress, and nothing caught it. Extend .claude/skills/architecture/archlint.sh: for each bundle row of architecture/13-roadmap.md that names tickets, compare its state with backlog (backlog task <id> --plain, Status). Report each mismatch as an error. Test it with a fixture roadmap and a fixture board.
<!-- SECTION:DESCRIPTION:END -->

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
