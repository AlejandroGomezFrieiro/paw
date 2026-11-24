---
id: TASK-247
title: 'Export tags: ISRC, composer, copyright, disc number and lyrics'
status: To Do
assignee: []
created_date: '2026-11-23T07:15:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-S
  - render
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 309000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician who releases a song needs its ISRC, the composer, the copyright, the lyrics and the disc number in the exported file, as distributors and players read them.

**Other DAWs.** REAPER writes ISRC, composer, lyrics and more in its render metadata (design doc, section 4.2 "Tags: no ISRC, lyrics", low).

**paw now (checked 2026-11-23).** crates/paw-core/src/session/tags.rs: title, artist, album, track, year, genre, comment and a cover. docs/reference/limits.md: "Tags are text only: no lyrics, ISRC, composer, disc number or replay gain."

**What to build.** New fields in `project.meta.tags`: `isrc` (checked: 12 characters, the ISRC form), `composer`, `copyright`, `disc`, `lyrics` (text; with the utau or notation lyrics as a source only if the user asks). Each format writes what it can: ID3 (TSRC, TCOM, TCOP, TPOS, USLT), Vorbis comments, FLAC, WAV INFO and BWF where they exist. The render dialog and `:tags` edit them. TASK-222 keeps tags as they are, so this ticket is apart from it.

**Core or extension.** Core: the render writes the tags.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: a FLAC and an MP3 render (the MP3 test skips with a reason when ffmpeg is absent in the sealed environment) carry the ISRC, composer, copyright, disc and lyrics; a reader in the test reads them back
- [ ] #2 Test: a bad ISRC gives a clear message and is not saved
- [ ] #3 docs/reference/render.md (or export.md) and limits.md say it; Vale reports 0 alerts
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
