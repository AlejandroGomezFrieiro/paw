---
id: TASK-232.1
title: 'MIDI learn: a button runs any command (play, record, undo, marker)'
status: To Do
assignee: []
created_date: '2026-11-23T07:12:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-S
  - midi
  - ux
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-232
priority: medium
ordinal: 284000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A pad or a button of any MIDI controller starts the transport, records, undoes, adds a marker or runs any command. Today a button can only press a button that an extension adds (docs/reference/learn.md).

**What to build.** `:learn command <ex command>` waits for a button and binds it to the Ex command. `paw.learn.bind(source, { target = "command", command = "transport.toggle" })` in Lua. `:learn.list` shows it. The binding is part of the project, as other bindings are.

**Core or extension.** Core: learn is core, and the target is generic.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: :learn command transport.toggle, then an injected note-on from paw.midi.inject_ump starts the transport, and a second one stops it
- [ ] #2 Test: the binding saves with the project and undo removes it
- [ ] #3 Test: a binding to an unknown command gives a clear message at the press, not a stack trace
- [ ] #4 docs/reference/learn.md says it
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
