---
id: TASK-323
title: >-
  Lane heads: paw.heads, the default head from pieces, lit flags, head keys and
  the height rule (HD)
status: In Progress
assignee: []
created_date: '2026-11-23T17:01:00Z'
updated_date: '2026-11-24T06:29:00Z'
labels:
  - bundle
milestone: m-17
dependencies:
  - TASK-304
references:
  - backlog/docs/designs/lane-heads.md
  - architecture/decisions/0034-lane-heads-by-kind.md
priority: high
ordinal: 392000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/lane-heads.md (sections 4-12, 13.1 row HD). contracts.tl records; paw/heads.tl, paw/heads/pieces.tl, paw/heads/default.tl; the pieces from arrange_track.tl; heads.draw in arrange.tl; head on paw.track_kinds and paw.clip_kinds; the choice and fallback; lit flags; head keys in a scope; the wish and the height rule; kept cells; hits for the mouse; paw.opt.head_pictures, paw.opt.head_limit; the extension skill and the API reference. Size M, one Opus agent. After W1, before LA; not in a batch with LA, B6 or TK (views/arrange*.tl).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Golden screens of the default head at 60, 100 and 140 columns (audio part with input, sends, four rows; MIDI part) give today's cells; the only change is the narrow badge space
- [ ] #2 A test head in a test extension (rows 3, text, a localleader key): golden screen; unloading the extension gives the default head and the row stays
- [ ] #3 A head that fails: the default head on the row and one message, no stack trace (real keys)
- [ ] #4 Lit flags: a head without chips; M on its row shows M; K says muted
- [ ] #5 Head keys: the key runs on the head's row only; define refuses a clash with a message naming the user
- [ ] #6 Height: a head wishing 3 rows is one j/k step; a wish change below the cursor keeps the cursor's screen line
- [ ] #7 Redraw: after j, paw.heads.draws grows by two
- [ ] #8 Mouse: arrange_mouse tests pass with hits (M, meter drag, in)
- [ ] #9 Half-block golden screen of a head with a picture at paw.opt.graphics = false
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
Rows build on the one time axis (ADR 0035, TASK-325): no row computes a column from a beat on its own.

PO 2026-11-23: owner order: HD comes after W1 (TASK-304) and before LA (TASK-309); LA depends on it.

Wave 23 (2026-11-24), base 9cecbfdc (batches 20-22 + W1).

Merged in the merge tree (af168218, 2026-11-24). Deferred: pieces takes, stack, value, source, lanes, picture (TK, M4, B6, RD, LA); head on clip kinds (LA, owner question: wait for LA, recommended); :checkhealth for heads that are out. Not checked: keys of a bundled extension that is not loaded when a head is defined.
<!-- SECTION:NOTES:END -->
