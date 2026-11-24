---
id: TASK-231.2
title: 'osc extension: transport, faders and markers over OSC, with feedback'
status: To Do
assignee: []
created_date: '2026-11-23T07:12:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - extensions
milestone: m-14
dependencies:
  - TASK-231.1
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-231
priority: low
ordinal: 282000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A tablet with TouchOSC or Open Stage Control plays, stops, records, moves faders, mutes, solos and jumps to markers, and shows the playhead time and the track names.

**What to build.** An extension `osc` with a map of addresses in the style of Ardour (for example `/transport_play`, `/strip/fader <ssid> <value>`), feedback of the state at a set rate, and a picker that shows the clients. Each action from OSC is one undo step and gives feedback, as a key does (rule 6). A fader sweep is one undo step.

**Core or extension.** Extension.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test over a loopback socket: /transport_play starts the transport; /strip/fader moves the fader of the track and one sweep is one undo step
- [ ] #2 Lua test: after a fader move in paw, the client socket gets the feedback message
- [ ] #3 The README names every command, key and address; the README test passes
- [ ] #4 No test uses a real tablet or another machine
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
