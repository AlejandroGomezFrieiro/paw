---
id: TASK-234.4
title: Detect the tempo of an audio clip, and use it for the clip or the song
status: To Do
assignee: []
created_date: '2026-11-23T07:13:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-S
  - media
milestone: m-14
dependencies:
  - TASK-234.1
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-234
priority: low
ordinal: 292000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** paw reads the tempo of a loop, so that the clip follows the song tempo with no manual entry, or so that the song takes the tempo of a recording.

**paw now.** `:clip.tempo 100` sets the source tempo by hand; `:clip.tempo` alone takes the tempo of the song at the clip start (docs/reference/stretch.md).

**What to build.** `:clip.tempo detect` sets the source tempo from the measurement and turns on follow the tempo. `:tempo from clip` sets the song tempo at the cursor from the clip. Both are one undo step and say the tempo and the confidence. A low confidence asks for confirmation.

**Core or extension.** Core: it extends `:clip.tempo` and `:tempo`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: :clip.tempo detect on a generated loop at 96 BPM sets the source tempo to 96 and the clip follows the song tempo
- [ ] #2 Test: :tempo from clip sets the song tempo at the cursor; u undoes it in one step
- [ ] #3 Test: a clip with no clear tempo gives a message with the low confidence and changes nothing until the user confirms
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
