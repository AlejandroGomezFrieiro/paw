---
id: TASK-250
title: 'Lua devices: their own latency and a saved state'
status: To Do
assignee: []
created_date: '2026-11-23T07:16:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-M
  - devices
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 314000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician writes a look-ahead limiter, a pattern arpeggiator or a step sequencer as a Lua device. The look-ahead needs its latency to be compensated, and the arpeggiator needs its pattern saved with the project.

**Other DAWs.** REAPER JSFX have latency (`pdc_delay`), state (serialize) and their own windows (design doc, section 4.2 "Lua devices: no window, no block-rate params, no own latency", low).

**paw now (checked 2026-11-23).** crates/paw-luadev, docs/reference/lua-devices.md. docs/reference/limits.md: Lua devices have no window of their own, no parameter moves inside a block, no state other than parameter values, one stereo output, and no latency of their own for delay compensation.

**What to build.**
- `dev.latency` (frames), read after `init` and after each parameter change; the engine delay compensation (docs/reference/engine.md) uses it as it uses a plugin latency.
- `dev.save()` and `dev.load(data)`: a plain value that the project keeps with the device and that undo restores, as a plugin state.
- A window drawn by the script and moves inside a block stay out: each is a separate ticket if users ask.

**Core or extension.** Core: Lua devices are run by the core (crates/paw-luadev), and the delay compensation is in the engine.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: a Lua device with dev.latency = 64 in parallel with a dry path renders aligned (null test: the difference is silent)
- [ ] #2 Lua test: a device that keeps a pattern in dev.save gets it back in dev.load after save, reopen and undo
- [ ] #3 docs/reference/lua-devices.md and limits.md say it; Vale reports 0 alerts
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
