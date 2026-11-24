---
id: TASK-358
title: >-
  folds: a hop onto a closed block keeps the old wanted time, so a count of j/k
  lands at the wrong column
status: Done
assignee: []
created_date: '2026-11-24T11:58:00Z'
updated_date: '2026-11-24T14:15:00Z'
labels:
  - bug
  - keys
  - ux
  - agent:worker
dependencies: []
priority: medium
ordinal: 427000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-357 (2026-11-24): tests/folds.lua:354 fails since the motion layer merge (11b99e63): j and k keep the wanted time; after h l l h the cursor reads 'Bass 16' but the wanted time is still 28, so k2j lands on 28 (got 'Lead 28', want 'Lead 16'). Proposed: a horizontal move that lands on a closed block sets the wanted time to the block start (as Vim sets curswant on a horizontal move). Check against docs/reference/key-rule.md and the motion tests; real keys in the test.
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
On local main c3157735 (2026-11-24, not pushed). Rule: the wanted time is the asked tick (a scope clamp keeps it, Vim's curswant); a hop onto a closed block sets it to where the cursor lands. Review: merge; soft findings fixed (no-op assertion removed, real-key j-onto-block guard). Merge-check: clippy, ast-grep, machete clean, 726/726, 60/60 key and motion tests.

Correction 43080c81: j onto a closed block keeps the wanted time (Bass 28); bfe1ffe2's test expectation was wrong; the test was missed because 'only' matches names. merge-check now runs each changed test part whole.
<!-- SECTION:NOTES:END -->
