---
id: TASK-241
title: 'Clip launcher: follow actions (next, random, stop after N bars)'
status: To Do
assignee: []
created_date: '2026-11-23T07:15:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-M
  - extensions
  - launcher
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 303000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** In a live set, a clip plays four bars and then the next clip of the column starts by itself, or a random one, or the clip stops. A musician builds a set that changes without a press for each change.

**Other DAWs.** Ableton Live and Bitwig have follow actions; Ardour has cue markers that trigger clips (design doc, gap 10, section 4.2 "Clip launcher: no follow actions", section 4.4 "Cue markers").

**paw now (checked 2026-11-23).** extensions/launcher: slots, scenes, quantize, launch modes, legato, capture (`C`). docs/reference/limits.md: "No follow actions (a clip that launches the next clip, or a random clip, after some bars)." TASK-23 (clip kinds) does not cover follow actions.

**What to build.**
- A follow action for each slot: after N bars (or N loops), do one of: stop, play again, next slot, previous slot, first slot, a random slot, any other slot (not this one), a named slot. A second action with a chance (A 70 %, B 30 %).
- Random choices use a seed that the project keeps, so a render of a capture is the same each time (tests are deterministic).
- A key in the session view edits the follow action of the slot at the cursor (on the local leader, by the key rule). The slot shows a mark when it has one.
- The follow action is data of the extension in the slot clip `meta`. The core plays clips; the extension decides the next launch.
- Optional, in this ticket if small: a marker kind on the ruler that launches a scene when the playhead passes it (the cue markers of Ardour).

**Core or extension.** Extension (launcher). It needs no core change: the extension launches clips with `paw.api.cue`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test on stepped engine blocks: a slot with next after 2 bars launches the next slot at bar 3, with no sleep in the test
- [ ] #2 Lua test: with a fixed seed, the random action picks the same sequence each time
- [ ] #3 Test with real keys: the follow action key on a slot sets it, the slot shows the mark, and u removes it in one step
- [ ] #4 A project with follow actions opens and plays without the extension (the timeline plays)
- [ ] #5 The README names the new keys and commands; the README test passes
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
