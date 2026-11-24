---
id: TASK-336
title: Side-chain and output-pair latency inside splits
status: To Do
assignee: []
created_date: '2026-11-23T23:40:00Z'
updated_date: '2026-11-24T14:22:00Z'
labels:
  - agent:builder
milestone: m-18
dependencies:
  - TASK-280
priority: low
ordinal: 405000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From G2 (TASK-280). Routing still adds device latencies along the flat device list for side-chain keys and output pairs, so a key taken inside a split can be off in time. Make the before-latency and output lateness follow the GraphPlan paths.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A side-chain key taken inside a late branch lines up with the dry signal to the sample (null test)
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
