---
id: TASK-206
title: Codebase improvement run (untangle-codebase skill)
status: To Do
assignee: []
created_date: '2026-11-23T06:04:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:worker
milestone: m-10
dependencies:
  - TASK-6
  - TASK-7
  - TASK-95
  - TASK-96
  - TASK-97
  - TASK-98
  - TASK-99
  - TASK-132
  - TASK-149
  - TASK-177
  - TASK-208
  - TASK-215
  - TASK-218
  - TASK-260
  - TASK-164
priority: low
ordinal: 218000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After m-2, m-3, m-10 (its other tickets) and m-12 are finished, run the skill .claude/skills/untangle-codebase over the whole codebase. The skill has disable-model-invocation, so the owner starts it (/untangle-codebase), or the orchestrator follows its steps by hand on the owner's word. Its step 1 asks the owner which additions to do (remove comments that only restate the code; remove tests that would not catch a real bug). Keep to AGENTS.md: paw-gui stays paused, tests stay sealed, at most 6 agents, the orchestrator builds.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The owner starts the run (/untangle-codebase) or gives his word for the orchestrator to follow its steps; the answers to its step 1 are in the notes
- [ ] #2 Each part of the run merges with the full Lua suite, the Rust tests and nix flake check passing; paw-gui is not changed
- [ ] #3 The 91 Rust duplicate findings of groma lint (TASK-25) are each fixed or given a reason
- [ ] #4 The notes list what changed in each part, and the docs that name moved files are fixed; Vale reports 0 alerts
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
Board review 2026-11-23: last in m-10. The dependencies are the other m-10 tickets and the epics of m-2 and m-12 that are left; m-3 has no epic, so check that its tickets are Done before the start. Priority low until then.

PO 2026-11-23 (after batch 14): dependencies on TASK-215 and TASK-218 added, so that this run is last in m-10 (owner). TASK-6 is Done.

PO 2026-11-23 (after batch 16): dependencies on TASK-260 (it moved to m-10) and TASK-164 (the last ticket of m-3) added, so that this run stays last.
<!-- SECTION:NOTES:END -->
