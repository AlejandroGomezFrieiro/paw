---
id: TASK-23
title: 'Clip kinds: remaining parts (B2, B3, E2-E6, C1-C3)'
status: To Do
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-23T23:04:00Z'
labels:
  - clip-kinds
  - blocked-by-plan
milestone: m-5
dependencies:
  - TASK-313
references:
  - architecture/decisions/0018-parts-and-typed-lanes.md
priority: low
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extension-defined clip kinds are built to A1-A6, B1 and D1 (merges CK-A1 to CK-A6, CK-B1, CK-D1): the model, folder save, undo diff, plain-data check, paw.clip_kinds in Teal, pictures in views. The owner approved the design and all 7 recommendations (no compatibility before a release).

Design: backlog/docs/designs/clip-kinds.md (section 6 is the plan, section 8 the decisions). It was in a session scratchpad; the product owner review of 2026-11-22 copied it into the backlog.

Parts left, in the order of section 6.1 of the design:
- A2b: the leftovers of A2: session/clips.rs clip_source_length through playable() (loop on a custom clip with audio sound); model.rs retime for a custom clip's audio sound; a mutable accessor on Sound so that edits, reverse and normalize work on a custom clip's audio sound; a test of the refusal texts.
- B2: the arrange view draws custom clips by `look` (label, marks as roles, strip), `?` for an unknown kind; K and Enter.
- B3: track kind fields `clip_kind` and `mixer`.
- C1: engine signals (paw-engine: SignalEv, Part.signals, the drain in process.rs). Audio thread rules.
- C2: paw-core signal table, the signal thread, OSC through rosc.
- C3: kernel handlers (on_signal, chase, on_stop) and the write guard.
- E1: extensions/comments (the smallest kind; the first useful slice with A1-B2).
- E2: extensions/actions with :trust (after C3).
- E3: extensions/lights (after C2).
- E4: extensions/video, two parts (after D1).
- E5: extensions/pattern as a custom kind, with its migration.
- E6: the docs of section 5 and the rule 4 change.

Make one child ticket for each part when an agent starts it, as TASK-7 and TASK-77 do.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A2b: a custom clip with audio sound loops, retimes, reverses and normalizes; a test covers the refusal texts
- [ ] #2 C1 to C3: a signal comes at its frame across a loop wrap and a seek; an OSC signal reaches a local UDP port; tests/no_alloc.rs passes
- [ ] #3 E2 to E5: each extension has a README that names its commands and keys, and tests; a project with its clips opens and plays without it
- [ ] #4 E6: the docs of section 5 of the design and the rule 4 change are written; Vale reports 0 alerts
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
Product owner review 2026-11-22: rewritten with the parts left (A2b was missing, E1 too), the design copied to backlog/docs/designs/clip-kinds.md, and acceptance criteria.

DAW parity review 2026-11-23 (m-14): two parts of this ticket close parity gaps. E4 (extensions/video, with TASK-10 M10) is the video timeline of Ardour and REAPER. C2 (OSC through rosc) is the OSC output; the m-14 ticket 'OSC: control paw from a tablet' adds a generic OSC port for extensions and should share the encoder and the thread of C2. Source: backlog/docs/designs/daw-feature-comparison.md.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): CK. Parts B2, B3 and E1 move to bundle B6 (AC 2 and 6 go there). E6's rule 4 change is bundle D4. Read the parts left against ADR 0018 (a lane holds one clip kind) and ADR 0019. Unblocked by: B6.

PO 2026-11-24: D4 (TASK-302) is on main, so the rule 4 part of E6 is done.
<!-- SECTION:NOTES:END -->
