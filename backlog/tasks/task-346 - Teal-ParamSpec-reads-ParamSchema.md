---
id: TASK-346
title: Teal ParamSpec reads ParamSchema
status: In Progress
assignee: []
created_date: '2026-11-24T06:30:00Z'
updated_date: '2026-11-24T15:26:00Z'
labels:
  - api
  - types
  - agent:worker
milestone: m-10
dependencies: []
priority: medium
ordinal: 415000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-96 AC #11 (second half): the Teal ParamSpec of devices reads the ParamSchema that Rust generates (schemars), so one schema serves Rust, the chain host and Teal.
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
Builder report 2026-11-24: there was no Teal ParamSpec. ParamSchema, ParamType, Unit and PropValue are generated from the Rust ParamSchema (schemars, a new optional feature of chain-syntax: owner question), and dsp.lua reads their words.

Owner 2026-11-24: the optional schemars feature of chain-syntax is accepted.
<!-- SECTION:NOTES:END -->
