---
id: TASK-253
title: Patch and note names of hardware synths (MIDNAM)
status: To Do
assignee: []
created_date: '2026-11-23T07:16:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-S
  - extensions
  - midi
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 317000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician with a hardware synth or a General MIDI module picks a sound by name ("Warm Pad"), not by a program number and a bank, and sees note names of a drum module in the piano roll.

**Other DAWs.** Ardour reads MIDNAM files for patch and note names (design doc, section 4.4 "Hardware synth patch names (MIDNAM)", low).

**paw now (checked 2026-11-23).** docs/how-to/play-a-hardware-synth.md. The articulations extension reads key names only from CLAP plugins (docs/reference/limits.md). paw has `paw.xml` for XML.

**What to build.** An extension that reads MIDNAM files (from a folder of the user, and a few files shipped with the extension: General MIDI, GM2 drums), offers a picker of patches for a track with a MIDI output (one undo step: a program change and bank select at the clip start or as track data), and gives note names to the piano roll keyboard where the core allows it.

**Core or extension.** Extension.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test: the GM MIDNAM file shipped with the extension lists 128 patches in the picker; a choice writes the program change, and u removes it in one step
- [ ] #2 Lua test: the GM2 drum names show on the keyboard of the piano roll for a track with that device
- [ ] #3 No test reads a MIDNAM file of the machine; the README names every command and key
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
