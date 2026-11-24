---
id: TASK-49
title: 'Owner: answer the platforms questions'
status: To Do
assignee: []
created_date: '2026-11-21T19:52:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - platforms
  - owner-decision
milestone: m-1
dependencies: []
priority: low
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
10 questions with recommended answers in backlog/docs/designs/platforms.md (order Linux, macOS Apple Silicon, Windows; Nix stays dev reference; named pipes; no utau engine in archives; no AU in m-1; unsigned until 1.0; ASIO as a feature; minimums macOS 14.4, Windows 10 22H2, Ubuntu 22.04 glibc). Design: backlog/docs/designs/platforms.md.
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
Owner decided 2026-11-21: targets now = Unix (Linux + macOS) terminal, egui window, web; Windows low priority but designed for.

Owner 2026-11-23: delay until more milestones are finished.
<!-- SECTION:NOTES:END -->
