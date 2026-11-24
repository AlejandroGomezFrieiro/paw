---
id: TASK-260
title: Fewer abandoned LuaJIT traces on the first keys
status: To Do
assignee: []
created_date: '2026-11-23T07:50:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:worker
milestone: m-10
dependencies: []
priority: low
ordinal: 324000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-195 (bench/RESULTS.md section on first-press keys). About 30% of the traces LuaJIT starts on the scope keys are abandoned: loops left in root traces, closures (UCLO, FNEW), varargs, returns to a lower frame. Find the hottest abandon sites with bench/profile/drive.py's traces counts and --vmstates, and change the code style there where the count of abandons goes down beyond the spread. Also watch: the trace count grows by about 150 per round of scope keys, so a long session can still fill the 8000-trace cache.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 bench/RESULTS.md names the top abandon sites and the change for each, with traces started/abandoned before and after (load-independent counts)
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
PO 2026-11-23 (merge of small tickets): left alone. It is the follow-up of TASK-195, which is running; start it after TASK-195 merges.

2026-11-23: moved from m-3 to m-10 so m-3 can close after the TASK-80 and TASK-164 measurements (orchestrator's call; low priority, speed only).

PO 2026-11-23 (after batch 16): TASK-195 is Done and on main (runtime/lua/paw/jit.tl). This ticket can start; it is low priority in m-10.
<!-- SECTION:NOTES:END -->
