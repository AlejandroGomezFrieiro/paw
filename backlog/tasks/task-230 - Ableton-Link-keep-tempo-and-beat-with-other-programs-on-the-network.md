---
id: TASK-230
title: 'Ableton Link: keep tempo and beat with other programs on the network'
status: To Do
assignee: []
created_date: '2026-11-23T07:11:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - sync
  - owner-decision
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 279000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician jams with friends who use Ableton Live, Bitwig, a phone app or other Link programs on the same network. All of them keep one tempo and one beat phase, with no cables.

**Other DAWs.** Bitwig, Ableton Live and many apps have Link. The design doc lists Link as a gap of lower rank (section 4.1, "Ableton Link and tap tempo: none"). Tap tempo is not a gap: paw has `:tempo.tap` and `<Space>Tt` (docs/reference/tempo.md).

**paw now.** No Link.

**What to build.** Join a Link session (a setting of the machine), follow and set its tempo and its beat phase, and start and stop with it (Link start/stop sync).

**Core or extension.** Core for the clock part (the engine must follow the phase). The Link library is C++ under GPL-2.0 or a paid license. paw is MIT or Apache-2.0. **Owner decision before work starts:** see the implementation notes.

**Tests.** No network in a test. A fake session behind a trait.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test with a fake Link session: a tempo change in the session changes the paw tempo; the beat phase stays aligned at a bar
- [ ] #2 Rust test: start and stop in the fake session move the paw transport
- [ ] #3 No test opens a network socket
- [ ] #4 The owner decision on the license is in the notes before the work starts
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner decision: the Link library (rusty_link binds the C++ library) is GPL-2.0-or-later or a paid license, and paw is MIT OR Apache-2.0. A static link makes the binary GPL. Recommendation: build Link as an optional native part of an extension (Nix package, off in the default build), or skip Link. Do not start before the owner answers.

Owner decision 2026-11-23: build Link as an optional native part of an extension, off by default, so the paw binary stays MIT/Apache.
<!-- SECTION:NOTES:END -->
