---
id: TASK-389
title: >-
  Terminal: give the terminal back after a crash signal, a stop and in paw
  attach
status: To Do
assignee: []
created_date: '2026-11-24T18:01:00Z'
labels:
  - agent:builder
dependencies: []
priority: medium
ordinal: 458000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the TASK-384 audit (2026-11-24). (1) SIGSEGV, SIGBUS or SIGABRT (for example from an in-process plugin) leaves raw mode, the alternate screen and mouse reporting on. Fix: the SIGTERM handler's async-signal-safe restore for these signals, then re-raise. (2) paw attach has no panic hook: a panic leaves the alternate screen. (3) SIGSTOP then SIGCONT can lose raw mode and the screen; on SIGCONT enter raw mode and the alternate screen again and repaint.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After SIGABRT and SIGSEGV, the terminal is out of raw mode, off the alternate screen and without mouse reporting; a test in a pseudo-terminal
- [ ] #2 A panic in paw attach gives the terminal back and prints its message; a test
- [ ] #3 After SIGSTOP and SIGCONT, the frame is whole again; a test
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
