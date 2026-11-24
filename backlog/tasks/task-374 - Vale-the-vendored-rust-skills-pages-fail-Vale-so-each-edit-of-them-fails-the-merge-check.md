---
id: TASK-374
title: >-
  Vale: the vendored rust-skills pages fail Vale, so each edit of them fails the
  merge check
status: To Do
assignee: []
created_date: '2026-11-24T14:30:00Z'
labels:
  - docs
  - tooling
  - agent:worker
milestone: m-7
dependencies: []
priority: low
ordinal: 443000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-11-24: the merge check ran Vale on the changed rust-skills files: 306 errors in 4 files (README, SKILL.md, two rule pages), and old untouched rule pages fail too (34 errors in 2 files). partlint already skips .claude/skills/rust-skills/rules/. Decide: exclude the vendored upstream text from Vale in .vale.ini (with the reason), and keep the paw-written rules checked; or fix them. Vale must report 0 on every file it checks.
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
