---
id: TASK-237.1
title: >-
  Audio clip view: open an audio clip, move on its waveform, trim, split, fade
  and gain
status: To Do
assignee: []
created_date: '2026-11-23T07:13:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - media
  - views
  - ux
  - blocked-by-plan
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-237
priority: medium
ordinal: 296000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**What to build.** `Enter` on an audio clip in the arrange view opens the view (as `Enter` on a MIDI clip opens the piano roll). The view shows the waveform of the clip over its full width (a picture where the terminal shows pictures, cells elsewhere), the fades, the gain parts and a time ruler.
- Motions only move (key rule): `h` `l` by the grid, `w` `b` `e` by the next and previous peak or zero crossing, `0` `$` to the clip edges, zoom with the same keys as the arrange view.
- The operators and keys of the arrange view work at the cursor: split, trim to the cursor, fades (`\fi`, `\fo`), gain of a part (`+` `-` change the main value, the gain), `:clip.normalize`.
- `K` describes the point at the cursor (time, level). `Esc` cancels a pending operator. `q` or `:q` closes the view.
- Each edit is one undo step and says what it did.

**Core or extension.** Core (see the parent ticket).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: Enter on an audio clip opens the view; l moves the cursor one grid step; $ goes to the clip end
- [ ] #2 Test: the scene of the view is the same for the terminal and for a scene client (golden screen in the terminal)
- [ ] #3 :lua =paw.keyrule.broken() lists nothing new
- [ ] #4 bench/ has an entry: the time of a key in the view on a clip of 10 minutes, with the spread (no speed assertion in a test)
- [ ] #5 Test with real keys: S at the cursor splits the clip (as in the arrange view), \fi fades in to the cursor, + raises the gain of the part, and u undoes each in one step
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
