---
id: TASK-235
title: Ripple edits move automation, markers and tempo with the clips
status: To Do
assignee: []
created_date: '2026-11-23T07:13:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - editing
  - blocked-by-plan
milestone: m-14
dependencies:
  - TASK-315
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: medium
ordinal: 293000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician deletes two bars of an intro, and everything after it moves up: the clips, the automation, the markers, the tempo changes. Today the clips move and the rest stays, so the automation and the markers are two bars off.

**Other DAWs.** REAPER has ripple per track and ripple of all tracks (with markers and envelopes). The design doc says "Ripple edit: none" (matrix and gap 6). **That claim is wrong.**

**paw now (checked 2026-11-23).** paw has ripple:
- `paw.opt.ripple = true` (docs/reference/options.md, grammar.md): a delete of time closes the gap and a paste moves the music after it. runtime/lua/paw/edit.tl `A.ripple` moves the clips of each track in the range.
- `:d!`, `:m!` and `:co!` on an Ex range ripple (runtime/lua/paw/ex.tl).
What is missing: `A.ripple` moves clips only. docs/reference/limits.md: "`d`, `m` and `co` move clips, not the automation, tempo changes or markers in the range." The utau README says that its curves do not follow a ripple delete. No key turns ripple on or off, and nothing on the screen shows it.

**What to build.**
- Ripple moves the automation points of the tracks that it moves, after the cut.
- A ripple of all tracks (for example `paw.opt.ripple = "all"`): a delete or paste of time on any track moves every track, the markers, the regions, the tempo map and the time signatures after the cut. A time range of whole tracks uses it at once.
- Extensions follow: an `edit.ripple` event (or a hook) gives the cut and the shift, so that utau curves and other `meta` follow.
- A key toggles ripple (off, tracks, all), by the key rule (docs/reference/key-rule.md: a toggle, not a motion), and the status line shows the mode while it is on.

**Core or extension.** Core: ripple and the Ex ranges are core, and the model owns automation, markers and tempo.

**Size.** M. Two subtasks if it is more than a day: automation and the event first, then the mode "all" with the key.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: with ripple on, d over two bars of a time range moves the automation points after the cut back by two bars on the same tracks; u restores all in one step
- [ ] #2 Test with real keys: in the mode all, a delete of time on one track moves the clips of every track, the markers, the regions and the tempo changes after the cut
- [ ] #3 Test: :2,3d! moves the automation as the operator does
- [ ] #4 Test: an extension that listens to the ripple event gets the cut and the shift (one test with a stub listener)
- [ ] #5 Test with real keys: the toggle key cycles off, tracks, all, and the status line shows the mode; :lua =paw.keyrule.broken() lists nothing new
- [ ] #6 docs/reference/grammar.md, options.md and limits.md say it; the utau README line on ripple is fixed or kept true; Vale reports 0 alerts
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
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Wait for CV (curve lanes). After LA and CV, automation is a lane of kind curve, so a ripple moves every lane of a part in one rule; the automation part of this ticket would be built twice now. The markers, tempo and ripple-of-all parts can go with it then. ADR 0026, 0027. Unblocked by: CV.
<!-- SECTION:NOTES:END -->
