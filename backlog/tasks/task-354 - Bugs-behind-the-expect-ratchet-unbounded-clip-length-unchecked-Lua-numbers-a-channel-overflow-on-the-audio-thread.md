---
id: TASK-354
title: >-
  Bugs behind the expect ratchet: unbounded clip length, unchecked Lua numbers,
  a channel overflow on the audio thread
status: Done
assignee: []
created_date: '2026-11-24T11:01:00Z'
updated_date: '2026-11-24T14:15:00Z'
labels:
  - agent:worker
  - bug
  - quality
dependencies: []
priority: high
ordinal: 423000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the review of TASK-342/348 (2026-11-24). Each is a cast or arithmetic site that the #[expect] debt marks; fix the class (checked conversion or a bound where the value enters), with a test each. (1) paw-core/src/warp.rs:192,221: ((b - a) / BEND_STEP).ceil() as usize with a and b the clip's start and end; no bound on an arrangement clip's length (MAX_BEATS covers notes and controls only): a stretch clip of 1e12 beats from a file or Lua loops ~8e12 steps and pushes into corners (hang or OOM). Bound clip length where it enters (load and clip_set) with a clear message. (2) api/clips.rs:184 (megabytes * 1_048_576.0) as u64 from Lua: negative or NaN gives 0, a size limit nobody asked for: refuse with a message. (3) session/midi_in.rs:480,487: a count-in of 2.5 bars becomes 2 silently: refuse or round with a message. (4) paw-luadev device.rs:385: event.channel - 1 from a value the script writes: i32::MIN overflows and panics on the audio thread in a dev build: checked or saturating, and refuse out-of-range channels when the script writes them. (5) device.rs:468-476: a block with more than MAX_EVENTS events: a non-MIDI-effect device does not pass the extra events downstream (a note-off can be among them): pass them on or keep them like missed.rs does. (6) A test that a MIDI effect does not send the events of a missed block twice. (7) docs/reference/lua-devices.md:105 'an effect passes its input on unchanged': add the MIDI-effect case of a missed block.
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
On local main 5454e5f7 (2026-11-24, not pushed). Four review rounds: spill order (third sorted source), walk bound at its source, spill pushed twice (fixed spilled array), one PART_EVENTS constant. Merge-check: clippy -D clean, ast-grep rules ran and pass, machete clean, nextest 719/719 then 482/482 on the touched crates, suite words all passed, expect debt 631 -> 626. Follow-up: TASK-356 (a drop count of each device).
<!-- SECTION:NOTES:END -->
