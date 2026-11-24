---
id: TASK-390
title: 'Terminal: a slow terminal does not block the kernel thread'
status: To Do
assignee: []
created_date: '2026-11-24T18:01:00Z'
labels:
  - agent:builder
dependencies: []
priority: low
ordinal: 459000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the TASK-384 audit (2026-11-24). A terminal that reads slowly (a tmux client with a full buffer) blocks the kernel thread on the write of a frame. Fix: a writer thread where the latest frame wins. Also, low priority: a resize during a draw can show one wrapped frame; and a terminal without mode 2026 tears (optional DECRQM query).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A frame write to a terminal that does not read does not stop keys or the engine; a test with a pseudo-terminal that is not read
- [ ] #2 Only the latest frame is written when frames come faster than the terminal reads
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
