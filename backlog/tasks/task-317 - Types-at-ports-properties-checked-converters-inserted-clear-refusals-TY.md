---
id: TASK-317
title: 'Types at ports: properties checked, converters inserted, clear refusals (TY)'
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-17
dependencies:
  - TASK-312
references:
  - architecture/decisions/0028-typed-lanes-and-converters.md
priority: medium
ordinal: 384000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle TY of backlog/docs/designs/architecture-plan.md V2.7 step 8 (phase 5). Ports declare the stream type that they need (base kind plus properties). paw inserts a converter when one exists, or refuses with a message that names the missing property (ADR 0028). Live converters are built-in devices with no allocation (mono, stereo; V2.16 P6); others are tier bake. TASK-240 (wide buses) builds on the channels property.

This ticket has a title and a description only. The product owner adds the acceptance criteria when its phase starts, from backlog/docs/designs/architecture-plan.md and the ADRs in the references. One Opus agent does the bundle.
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
