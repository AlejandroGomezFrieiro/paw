---
id: TASK-372
title: >-
  Render-equality gate: the demo song and the end-to-end projects render
  bit-identical before and after a change
status: To Do
assignee: []
created_date: '2026-11-24T14:22:00Z'
labels:
  - tests
  - engine
  - agent:worker
milestone: m-10
dependencies: []
priority: high
ordinal: 441000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-24 (model rework rules, architecture/13-roadmap.md): the gate exists before MX starts and before A2's engine work. A tool (tools/render-gate.sh or a flake app) renders examples/demo-song.lua and each end-to-end project with --audio null and a fixed block size, hashes each rendered file, and compares with the hashes kept in the repo (tests/render-gate/*.sha256 or similar). Sealed (tests/tools/env.sh), no timing, no owner files. A change that is meant to alter the sound updates the kept hashes in the same commit, and the commit message says why. Wire it into .orchestrator/merge-check.sh (orchestrator does that) and the paw-code skill part 7; docs/how-to/run-the-tests.md. Prove it: a forced one-sample change in a device makes it fail with the file name. Agents never run e2e.sh: use the projects' files directly with paw's render command, not the e2e runner.
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
