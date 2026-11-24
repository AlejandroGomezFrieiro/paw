---
id: TASK-245
title: MIDI export writes per-note bend as MPE
status: To Do
assignee: []
created_date: '2026-11-23T07:15:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-S
  - midi
milestone: m-14
dependencies:
  - TASK-222.10
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 307000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician who plays an MPE controller or writes per-note bends exports a MIDI file and opens it in another program with the bends.

**Other DAWs.** Bitwig and REAPER export MPE as MIDI 1.0 files (design doc, section 4.2 "MIDI 2.0 ... no NRPN form in files", top improvement 5: "an `:export` drops per-note bend").

**paw now (checked 2026-11-23).** docs/reference/limits.md: `:export` "does not write the bend and controllers of a note (MIDI 2.0)". Live MIDI output already has an MPE form (crates/paw-engine/src/midi_form.rs). TASK-222.7 puts MIDI export into the `:export` grammar and keeps these limits.

**What to build.** A word of `:export` for `.mid` (for example `mpe=true`): the notes of a track go out on MPE member channels, each with its own bend, pressure and brightness, with the MPE configuration message at the start. The same converter as the live output, so the two agree.

**Core or extension.** Core: MIDI files are core.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test: a clip with a per-note bend on one note of a chord exports with mpe=true; the bend is on the member channel of that note only
- [ ] #2 Lua test: an import of the exported file into paw gives the bend back on that note
- [ ] #3 Test: without the word, the export is as before
- [ ] #4 limits.md and the export docs say it; Vale reports 0 alerts
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
