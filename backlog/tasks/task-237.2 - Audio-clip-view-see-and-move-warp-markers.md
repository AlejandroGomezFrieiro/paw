---
id: TASK-237.2
title: 'Audio clip view: see and move warp markers'
status: To Do
assignee: []
created_date: '2026-11-23T07:13:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-S
  - media
  - views
  - ux
  - blocked-by-plan
milestone: m-14
dependencies:
  - TASK-237.1
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-237
priority: low
ordinal: 297000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**What to build.** In the audio clip view: warp markers show on the waveform; `gw` puts one at the cursor, `gW` removes the nearest, `]w` and `[w` go to the next and previous marker (motions), `<` and `>` move the marker at the cursor in time (key rule: `< >` are time). With the onset ticket done, the onsets show as faint marks, and `:clip.warp onsets` works in the view.

**Core or extension.** Core.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: gw puts a marker at the cursor, ]w goes to it, > moves it one grid step later, u undoes the move in one step
- [ ] #2 Test: after :clip.warp onsets the onsets show in the view (golden screen)
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
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): The audio clip view is an editor of the clip kind audio (paw.editor.define, bundle B7) and draws the built-in kind through the API (bundle B6). architecture-plan.md V2.10 m-14. ADR 0018. Unblocked by: B6 and B7.
<!-- SECTION:NOTES:END -->
