---
id: TASK-234.3
title: Split an audio clip at its onsets (slices)
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
ordinal: 291000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A drum loop is cut at each hit into clips (slices) that the musician moves, deletes or plays in a new order, or sends to the drum sampler.

**What to build.** `:clip.split onsets [sensitivity]` splits the clip at each onset, as `S` (`:clip.split`) splits at the cursor. One undo step. With the drums extension loaded, a later ticket can map the slices to pads.

**Core or extension.** Core: it extends the clip split of the arrange view.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: the slices keep the gain, the fades at the cuts and the stretch of the clip
- [ ] #2 Test with real keys: :clip.split onsets on a generated clip of four hits gives four clips that start at the hits; u joins them in one step
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
