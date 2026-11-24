---
id: TASK-248
title: 'interop: open an Ardour session'
status: To Do
assignee: []
created_date: '2026-11-23T07:16:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-M
  - extensions
  - interop
  - blocked-by-plan
milestone: m-14
dependencies:
  - TASK-312
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 310000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician on Linux moves an old song from Ardour (or Mixbus) into paw: tracks, audio regions with their positions, fades and gain, MIDI regions, markers, tempo and meter, and the plugins where paw has them.

**Other DAWs.** Ardour imports from other sessions; Non Timeline reads Ardour 1 to 3 sessions; REAPER imports other projects (design doc, gap 7 and section 4.1 rank 8, matrix row "Foreign session import").

**paw now (checked 2026-11-23).** extensions/interop opens REAPER `.rpp` and DAWproject (`lua/interop/rpp`, `lua/interop/dawproject`) through `paw.formats`. No Ardour reader. The core has `paw.xml` for XML.

**What to build.** In the interop extension, a reader for Ardour session folders (`.ardour` XML, versions 6 to 9): tracks and buses, playlists (the active one), audio and MIDI regions with offset, length, fades and gain, sends, markers and ranges, the tempo map and meters, and LV2, VST3 and CLAP plugins by their ids with their state where the format allows. Media files stay where they are (no copy) until `:media.collect`. A message lists what it could not read. Export to Ardour is out of scope.

**Core or extension.** Extension (interop): not all users need it, and `paw.formats` lets an extension register a format (docs/explanation/about-core-and-extensions.md).

**Out of scope.** AAF and OMF: an owner decision (see the report of m-14).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test: a small Ardour session (a fixture of XML and short generated WAV files in the repository) opens with its tracks, regions at the right beats, fades, a send, markers and the tempo map
- [ ] #2 Lua test: an unknown plugin is listed in the message, and the project opens and plays without it
- [ ] #3 The project opens as a new unsaved project and never writes into the Ardour folder
- [ ] #4 The README names the format and the command; the README test passes; docs/how-to/move-a-song-to-another-daw.md says it
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
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Wait for MX. The reader must write parts, lanes, strips, buses and sends of the project graph (ADR 0018, 0024, 0027), not today's tracks. The rpp and DAWproject readers of extensions/interop move with MX too. Unblocked by: MX.
<!-- SECTION:NOTES:END -->
