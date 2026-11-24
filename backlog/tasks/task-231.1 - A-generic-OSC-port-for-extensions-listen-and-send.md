---
id: TASK-231.1
title: A generic OSC port for extensions (listen and send)
status: To Do
assignee: []
created_date: '2026-11-23T07:12:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - api
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-231
priority: low
ordinal: 281000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** An extension receives and sends OSC messages.

**paw now.** No Lua API for UDP or OSC. TASK-23 (part C2) plans a signal thread that sends OSC with `rosc` for custom clips. Share the encoder and the thread, so that paw has one OSC part.

**What to build.**
- `paw.osc.listen(port)` gives an `osc.in` event with the address, the arguments and the sender. `paw.osc.send(host, port, address, args)` sends.
- The socket runs on a thread of its own; the kernel gets messages as events and never waits.
- Listen on 127.0.0.1 by default. Another address needs an explicit setting, because OSC has no authentication.

**Core or extension.** Core, generic: it names no address of any program.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test: a message sent with paw.osc.send to a paw.osc.listen port on 127.0.0.1 arrives as an osc.in event with the same address and arguments (a loopback socket of the test, no other machine)
- [ ] #2 Test: a bad packet gives one message and no event
- [ ] #3 Rust test: encode and decode of int, float, string and blob arguments round-trip
- [ ] #4 The API doc comments say it; docs/reference/api.md is generated again
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
