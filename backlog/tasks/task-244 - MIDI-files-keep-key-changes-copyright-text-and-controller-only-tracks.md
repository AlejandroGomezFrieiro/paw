---
id: TASK-244
title: MIDI files keep key changes, copyright, text and controller-only tracks
status: To Do
assignee: []
created_date: '2026-11-23T07:15:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-M
  - midi
milestone: m-14
dependencies:
  - TASK-247
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: medium
ordinal: 306000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician imports a MIDI file from a score program or a website and keeps its key changes, its copyright line, its text and the controller moves of a track with no notes (a track of CC only, often the expression of a part). An export gives these back.

**Other DAWs.** Rosegarden, MusE and REAPER keep key signatures and text (design doc, section 4.2: "MIDI file import loses sysex, key signature, text").

**paw now (checked 2026-11-23).** runtime/lua/paw/midifile.tl counts and drops key signatures (0x59), text (0x01), copyright (0x02), program and device names, SMPTE offsets and SysEx (`META_SKIPPED`). docs/reference/limits.md: "paw does not import controller moves on a channel or track with no notes" and "The project has no place for them".
**That last claim is stale for key signatures.** The project has a place: a marker named `key D minor` is a key change, and `project.key` is the key of the song (docs/reference/harmony.md, TASK-18). Tags (crates/paw-core/src/session/tags.rs: title, artist, album, track, year, genre, comment, cover) can take the copyright in the comment or in a new field.

**What to build.**
- Import: a key signature at tick 0 sets `project.key`; a later one becomes a `key <name>` marker. Copyright and the first text events go to the tags (a `copyright` field, see the tags ticket). A track or channel with controller moves and no notes gets a clip with those controls.
- Export (`:export song.mid`): key markers and `project.key` become key signatures; the copyright tag becomes a copyright event.
- The import message no longer counts what it now keeps.
- SysEx is in the SysEx clip ticket, not here.

**Core or extension.** Core: MIDI files are core (docs/explanation/about-core-and-extensions.md: "and MIDI files").
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test: a MIDI file (written by the test) with a key signature of D minor at bar 1 and Bb major at bar 9 imports as project.key D minor and a marker key Bb major at bar 9
- [ ] #2 Lua test: :export song.mid of that project writes both key signatures, and an import of the result gives the same keys
- [ ] #3 Lua test: a track with CC 11 moves and no notes imports as a clip with those controls
- [ ] #4 Lua test: the copyright event goes into the tags and back out on export
- [ ] #5 limits.md (the MIDI files part) and docs/how-to/import-audio-and-midi-files.md say what is kept; Vale reports 0 alerts
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
