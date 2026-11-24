---
id: TASK-9
title: 'perform: smart articulation and dynamics extension'
status: To Do
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-24T14:22:00Z'
labels:
  - extensions
  - midi
  - owner-decision
  - blocked-by-plan
milestone: m-18
dependencies:
  - TASK-316
references:
  - architecture/decisions/0025-render-with-provenance.md
priority: low
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design done, awaits owner approval (9 open questions, 7 numbers to verify): rule/template-based articulation + dynamics + CC generation, live mode while writing MIDI (\ei per track, :set perform_live). Design: backlog/docs/designs/perform.md. Implement only after approval.
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-23: live performance is not a priority.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): PF: perform becomes a producer of tier kernel with provenance (architecture-plan.md V2.13, ADR 0025). Unblocked by: RD, then the owner.
<!-- SECTION:NOTES:END -->
