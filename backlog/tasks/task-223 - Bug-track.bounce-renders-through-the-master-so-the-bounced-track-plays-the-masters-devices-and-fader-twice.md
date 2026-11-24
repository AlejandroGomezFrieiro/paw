---
id: TASK-223
title: >-
  Bug: :track.bounce renders through the master, so the bounced track plays the
  master's devices and fader twice
status: Done
assignee: []
created_date: '2026-11-23T07:00:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels:
  - bug
milestone: m-2
dependencies: []
priority: high
ordinal: 251000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the export design (TASK-222). paw.bounce renders the track with the master on (its devices, fader and pan), and the new audio track then plays through the master again. Fix: render a bounce after the track's own fader (tap=post, or master=false today) and test that a bounced track sounds the same as the original through the master. TASK-222's E6 makes this the :bounce command later; this ticket fixes the sound now.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A bounced track, played through the master, matches the original track within the tolerance of the freeze tests
- [x] #2 A test with a master device (a gain) fails on the old code
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed on branch worktree-agent-a3198193e04d5e0c9, commit 51548836. paw.bounce renders with master=false. Test 'a bounced track sounds through the master as the original did' (tests/scope.lua): master gain -6 dB, track fader -6 dB, :track.bounce by keys, sample difference < 1e-5 against live; old code gives 0.025. Docs: render.md Bounce, api.md regenerated. Left: a track in a group is still rendered through the group (tracks= takes what it passes through), and the bounce goes to the group again; tap=post (TASK-222.1/E6) fixes that.

Merged to main in batch 15 (2f970bba); full suite and checks passed.
<!-- SECTION:NOTES:END -->
