---
id: TASK-77.2
title: 'Derived D2: The piano roll context'
status: Done
assignee: []
created_date: '2026-11-22T15:23:00Z'
updated_date: '2026-11-22T22:41:00Z'
labels:
  - performance
  - derived
milestone: m-3
dependencies:
  - TASK-77.1
  - TASK-113
parent_task_id: TASK-77
priority: medium
ordinal: 121000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
D2 of the derived-data design. `roll_clips.context` becomes a memo node with the context clips' content and place as its key, not `edits`. Work with TASK-113.

Read first: backlog/docs/designs/derived.md, part 4 (the design) and row D2 of part 5; part 2 (inventory) and part 3 (measurements) for the consumer.

Owner decisions (2026-11-22): the design is approved; Q1 no mark in the views (the status line shows the job only after 1 s, K on a chord says "reading"); Q2 paw.derived stays internal in D1 to D5 and becomes public in D6; Q3 no user option for memory, fixed limits per kind shown by :checkhealth derived.

Measure with the spread, on the bench project, against main at the time, measured under external load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: With the roll open, an edit of the active clip does not make the context again (`stats().made` stays). Real keys: `x` on a note in the roll.
- [ ] #2 Number to meet: Roll frame after a note edit: 1.5 times a roll frame after `j` or less (12.5 ms against 5 ms today).
- [ ] #3 Docs follow the change; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a5930017b963f07d5 (commit 984ebce5, main merged in bf1c8356). New Teal module runtime/lua/paw/roll_context.tl: roll.context (memo, key = the roll's request: active clip and start, edited ids, span, toggles, options, scope; inputs = context clips with place and stamp, early cutoff), roll.track (family: colour, drums, group of a track), roll.track_clips (family: a track's MIDI clips). roll_clips.lua delegates tracks()/context() to it; the per-window cache and the edits/generation key are gone. roll_clips.sounding reads harmony.at as it stands (Q1), so a roll frame no longer finishes the chord reading; tests/harmony.lua and extensions/snippets/tests.lua read the chords first or wait for the new reading. Test: tests/multitrack.lua 'an edit of the roll's own notes keeps the notes behind them...' (x in the roll: made stays; an edit of a context clip: made +1). Numbers (roll view frame, bench project, wall time, taskset 16-23, load 7-10): after x/u 7.7-8.1 ms vs 7.1 ms after j/k (ratio 1.08-1.15); main 17.5-25.1 vs 4.5-6.5 ms. Docs: roll-clips.md, api.md (generated). Window part: none needed.

Merged to main (batch 3, 2026-11-23): dev build, nextest paw-core/engine/tui, full suite with plugins passed. At the merge: tests/suite.lua stamp check joined with TASK-121's runner; roll_context.tl's local paw renamed (strict tl check).
<!-- SECTION:NOTES:END -->
