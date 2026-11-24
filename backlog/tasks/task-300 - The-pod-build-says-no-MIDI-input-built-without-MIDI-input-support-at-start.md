---
id: TASK-300
title: 'The pod build says ''no MIDI input: built without MIDI input support'' at start'
status: To Do
assignee: []
created_date: '2026-11-23T14:00:00Z'
updated_date: '2026-11-23T20:12:00Z'
labels: []
milestone: m-0
dependencies: []
priority: low
ordinal: 362000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In the BrowserPod build paw shows this on the message line at start-up (TASK-93 and TASK-107 agents). A build without MIDI input should stay quiet about it at start and say it only when the user asks for MIDI input.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The pod build starts with no MIDI message; :midi or a MIDI command says it is not in this build
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
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Fixed by the branch of TASK-107 (worktree-agent-af409ea433257b7b0: no MIDI warnings without MIDI). Set Done when TASK-107 lands in batch 19.

PO 2026-11-23 (after batch 18+19): TASK-107 is on main (2a9405b9): the engine and the session know when a build has no MIDI ports, and the pod starts with no MIDI warning. Not checked: that :midi or a MIDI command says it is not in this build. Check it in the pod, then set Done or keep only that half.
<!-- SECTION:NOTES:END -->
