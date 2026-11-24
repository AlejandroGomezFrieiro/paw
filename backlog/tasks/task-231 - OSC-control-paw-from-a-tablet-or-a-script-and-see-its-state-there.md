---
id: TASK-231
title: 'OSC: control paw from a tablet or a script, and see its state there'
status: To Do
assignee: []
created_date: '2026-11-23T07:12:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-L
  - extensions
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 280000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician controls paw from a tablet (TouchOSC, Open Stage Control), a lighting desk or a script, and the tablet shows the state of paw (playhead, track names, faders, mute).

**Other DAWs.** Ardour and REAPER have OSC servers (design doc, gap 3 of section 4.1, matrix row "OSC").

**paw now (checked 2026-11-23).** The research doc said "OSC: none". That is true for control. But the model already has OSC output for custom clips: crates/paw-core/src/model/custom.rs keeps signals `{ kind = "osc", port, address, args }`, and TASK-23 (parts C1 to C3, m-5) adds the signal thread that sends them through `rosc`. No Lua API reads or sends UDP. `paw ctl` (docs/reference/ctl.md) is a socket of paw, not OSC.

**What to build.** The subtasks: a generic OSC port in the core, then an `osc` extension with a map of addresses.

**Core or extension.** The OSC port (UDP, encode and decode) is core because Lua has no sockets and two parts need it (the clip signals of TASK-23 and this extension). The address map is an extension: not all users need it (docs/explanation/about-core-and-extensions.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each subtask is done
- [ ] #2 A how-to guide tells how to use paw from TouchOSC or Open Stage Control; Vale reports 0 alerts
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
