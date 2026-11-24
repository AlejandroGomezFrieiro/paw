---
id: TASK-232
title: 'Control surfaces: Mackie Control and Launchpad work out of the box'
status: To Do
assignee: []
created_date: '2026-11-23T07:12:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-L
  - extensions
  - midi
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 283000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician uses a control surface: faders with motors, transport keys, a jog wheel, a grid of pads with lights. It must work as in other DAWs, without a binding of each control by hand.

**Other DAWs.** Ardour has Mackie Control, Push 2, Launchpad and generic MIDI maps; REAPER has Mackie Control and HUI (design doc, gap 3 of section 4.1, matrix row "Control surfaces").

**paw now (checked 2026-11-23).** MIDI learn (docs/reference/learn.md, runtime/lua/paw/learn.lua) binds a knob to a control, and a pad to a button that an extension adds (`paw.learn.trigger`, used by the clip launcher). No button can run an Ex command (play, record, undo), and no extension speaks a control surface protocol.

**What to build.** The subtasks.

**Core or extension.** The generic learn of commands is core (learn is core). Each surface protocol is an extension. Surfaces use SysEx for displays and modes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each subtask is done
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
