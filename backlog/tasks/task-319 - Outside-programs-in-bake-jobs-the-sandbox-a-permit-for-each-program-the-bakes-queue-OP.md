---
id: TASK-319
title: >-
  Outside programs in bake jobs: the sandbox, a permit for each program, the
  :bakes queue (OP)
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-24T14:22:00Z'
labels:
  - agent:builder
  - security
  - media
  - bundle
milestone: m-18
dependencies:
  - TASK-316
  - TASK-10.1
references:
  - architecture/decisions/0029-outside-programs-in-bake-jobs.md
  - architecture/decisions/0015-plugins-in-helper-processes.md
  - architecture/decisions/0025-render-with-provenance.md
priority: medium
ordinal: 386000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle OP of backlog/docs/designs/architecture-plan.md V2.12 (phase 6). An outside program runs only in a bake job, in a helper with a scratch HOME, a working folder in the project cache, and no network unless the extension declares it. Progress and cancel; one queue :bakes that the user can order. The question "allow this program?" comes one time for each program in each project; the Permit is kept in $XDG_STATE_HOME/paw/permits.json, not in the project (V2.16 P3). Opening a project never starts an outside program. A missing program: the lane keeps its last bake with an absent mark, and K names what to install. Tests use a stub program built in the repository and a scratch state folder (ADR 0029).

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
