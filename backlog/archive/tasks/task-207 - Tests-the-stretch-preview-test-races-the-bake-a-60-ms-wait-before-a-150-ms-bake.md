---
id: TASK-207
title: >-
  Tests: the stretch preview test races the bake (a 60 ms wait before a 150 ms
  bake)
status: To Do
assignee: []
created_date: '2026-11-23T06:05:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels: []
milestone: m-12
dependencies:
  - TASK-146
priority: medium
ordinal: 219000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
tests/stretch.lua 'a clip plays a rough preview until its stretch is made, then the stretch' waits paw.wait(60) and expects clip.preview still true, because a bake starts 150 ms after the request at the soonest. Under load the wait runs past 150 ms and the bake is done: 'still the preview: got nil, want true'. Seen twice on 2026-11-23 (TASK-204's run, batch 11's full suite); not caused by either. Fix: hold the bake (a scheduler pause, or the manual clock of TASK-146) so the test checks the preview state, not a race. Then remove its line from tests/quarantine.txt.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The test passes with the bake held: it checks the preview state, not a race against the bake's delay
- [ ] #2 Its line in tests/quarantine.txt is gone
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board review 2026-11-23: the test is in tests/quarantine.txt on main (8fd57eaa). The fix needs T.advance from part 2 of TASK-146. Also part of TASK-149 (stretch.lua is in its third part). Note: since 54864130 the files name no local ticket; the quarantine line names the fix.

PO 2026-11-23: dependency on TASK-146 added (the fix needs T.advance). TASK-149.3 (stretch.lua) can take it in.

2026-11-23: TASK-270's agent saw 'a long stretched clip is heard at once, while its sound is still being made' fail once under load in a 'clip' run, pass alone. Same family as this flake (stretch preview against bake time); TASK-146's manual clock may fix both.

PO 2026-11-23: merged into TASK-149.3 (owner: fewer, larger tickets). Its criteria and text are in TASK-149.3.
<!-- SECTION:NOTES:END -->
