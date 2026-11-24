---
id: TASK-77.5
title: 'Derived D5: The LSP document'
status: Done
assignee: []
created_date: '2026-11-22T15:23:00Z'
updated_date: '2026-11-23T00:46:00Z'
labels:
  - performance
  - derived
milestone: m-3
dependencies:
  - TASK-77.1
parent_task_id: TASK-77
priority: medium
ordinal: 124000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
D5 of the derived-data design. `lsp/document.tl` `key_of` becomes a memo node: the clip's stamp and place, the clips that overlap it (from the place index of `harmony.track`, not `clip_list` of every track), `tempo_stamp`, the key node.

Read first: backlog/docs/designs/derived.md, part 4 (the design) and row D5 of part 5; part 2 (inventory) and part 3 (measurements) for the consumer.

Owner decisions (2026-11-22): the design is approved; Q1 no mark in the views (the status line shows the job only after 1 s, K on a chord says "reading"); Q2 paw.derived stays internal in D1 to D5 and becomes public in D6; Q3 no user option for memory, fixed limits per kind shown by :checkhealth derived.

Measure with the spread, on the bench project, against main at the time, measured under external load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: An edit of a clip that does not overlap the document leaves its key as it was, with no `clip_list` call (an API call counter). The midilsp tests pass.
- [ ] #2 Number to meet: `key_of` after an edit elsewhere: 0.5 ms or less (10 to 26 ms today with `build`).
- [ ] #3 Docs follow the change; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
D5 built on branch worktree-agent-a3e24967814880a81, commit 12c1391a. key_of is a paw.derived memo node (lsp.document, span = the clip's place) over one lsp.track node per track (MIDI clips not muted, and name/devices/drums of the track), ctx:tempo (tempo_stamp), the clip and its track; touched limits a track change to the documents it overlaps. Keys of open documents are wanted (kept fresh in slices) and released in close_doc (new derived node:unwant). build reads the overlapping clips from the same node. Deviation: not harmony.track, because it leaves out drum and muted tracks, which the document sends. The music key at the clip's start stays outside the node (paw.harmony.key: providers, markers, project key). Test tests/lsp.lua: edit elsewhere keeps the key with 0 clip_list calls; an overlapping edit changes it. Numbers (bench/RESULTS.md): after a pause 0.09-0.43 ms p50 0.15-0.21, 0 calls (main 3.5-19 ms p50 3.7-3.9, 63 calls); at once 2.0-5.6 ms (main 5.0-19 ms), mostly the chord reading. First key_of 7.5-8.4 ms (main 5.0-5.7).
<!-- SECTION:NOTES:END -->
