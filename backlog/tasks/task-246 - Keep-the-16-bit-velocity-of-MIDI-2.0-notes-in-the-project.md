---
id: TASK-246
title: Keep the 16-bit velocity of MIDI 2.0 notes in the project
status: To Do
assignee: []
created_date: '2026-11-23T07:15:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-M
  - midi
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 308000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician plays a MIDI 2.0 keyboard. The 16-bit velocity of each note is kept in the project and plays back as played. MIDI is the truth (AGENTS.md rule 4), so the project must not drop the resolution.

**Other DAWs.** Few DAWs keep MIDI 2.0 velocity yet. The design doc proposes it (section 4.2, "MIDI 2.0: 16-bit velocity in the project", low).

**paw now (checked 2026-11-23).** `Note.velocity` is `u8` (crates/paw-core/src/model.rs). docs/reference/limits.md: "The velocity of a note stays seven bits (1 to 127) in the project. The sixteen bits of MIDI 2.0 reach and leave the engine." The `.midi2` clip file (crates/paw-core/src/clipfile.rs) writes MIDI 2.0 note-ons, which have 16 bits.

**What to build.** The note keeps 16 bits. The Lua API keeps velocity as 1 to 127 for scripts (with a fraction or a second field for the fine part, chosen by the implementer and written in the docs), so extensions do not break. Recording, the clip file and the engine keep the full value. The piano roll shows and edits the 7-bit value; `+` and `-` change it by whole steps.

**Core or extension.** Core: the model and the engine.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: a recorded MIDI 2.0 note-on with velocity 0x8123 saves to .midi2 and loads back with 0x8123
- [ ] #2 Rust test: the engine sends the same 16-bit velocity to a UMP output (Output fake)
- [ ] #3 Lua test: note.velocity still reads 1 to 127 for scripts, and the full value is readable as the docs say
- [ ] #4 limits.md loses the line; docs/reference/midi.md says it
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
