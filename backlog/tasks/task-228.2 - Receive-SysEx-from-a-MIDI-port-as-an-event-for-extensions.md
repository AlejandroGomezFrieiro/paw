---
id: TASK-228.2
title: Receive SysEx from a MIDI port as an event for extensions
status: To Do
assignee: []
created_date: '2026-11-23T07:11:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-S
  - midi
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-228
priority: medium
ordinal: 271000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** An extension reads what a synth or a control surface sends back: a patch dump, a reply to an identity request, an MMC command.

**paw now.** crates/paw-core/src/session/midi_in.rs gives the `midi.in` event (docs/reference/midi.md) for channel voice messages. `paw.midi.inject_ump(words)` injects a packet as if from a port. A SysEx is lost.

**What to build.** The `midi.in` event, or a new `midi.sysex` event, gives a complete SysEx message (all its bytes, joined from SysEx7 packets or ALSA events) and the port name. A message longer than a limit (for example 64 KB) is dropped with one message to the user.

**Core or extension.** Core: ports are core.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test: SysEx7 packets injected with paw.midi.inject_ump give one event with all the bytes and the port
- [ ] #2 Test: a message over the limit gives one clear message and no event
- [ ] #3 No test opens a real MIDI port: the tests inject packets
- [ ] #4 docs/reference/midi.md says it
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
