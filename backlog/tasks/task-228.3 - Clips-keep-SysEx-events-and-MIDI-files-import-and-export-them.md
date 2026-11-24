---
id: TASK-228.3
title: Clips keep SysEx events, and MIDI files import and export them
status: To Do
assignee: []
created_date: '2026-11-23T07:11:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - midi
milestone: m-14
dependencies:
  - TASK-228.1
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-228
priority: low
ordinal: 272000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A song that sets up a hardware synth with SysEx at its start keeps that data. A MIDI file with SysEx imports and exports with it. MIDI is the truth (AGENTS.md rule 4), so the clip keeps the event, not an extension.

**paw now.** crates/paw-core/src/clipfile.rs (`.midi2` clip files) keeps notes and controls. The clip model (crates/paw-core/src/model.rs) has no SysEx. runtime/lua/paw/midifile.tl counts SysEx as "skipped" on import, and `:export` writes none.

**What to build.**
- A SysEx event in a MIDI clip, at a beat, with its bytes. The `.midi2` file keeps it as SysEx7 data packets, as the MIDI Clip File specification allows.
- The engine plays it to the MIDI output of the track at its time (with a buffer made before, so the audio thread does not allocate).
- MIDI file import keeps SysEx events (F0 and F7) in the clip of their track; `:export` writes them.
- The piano roll shows a mark at the beat of a SysEx event. `K` on it describes it (its length, the first bytes).

**Core or extension.** Core: the clip model and the engine.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: a clip with a SysEx event saves to .midi2 and loads back with the same bytes
- [ ] #2 Lua test: a MIDI file with a SysEx imports it into the clip, and :export writes it back (bytes equal)
- [ ] #3 Rust test with the Output fake: the engine sends the SysEx at its frame; tests/no_alloc.rs passes
- [ ] #4 Test with real keys: K on the mark in the piano roll describes the event
- [ ] #5 One undo step for each edit; the import message no longer counts sysex as skipped
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
