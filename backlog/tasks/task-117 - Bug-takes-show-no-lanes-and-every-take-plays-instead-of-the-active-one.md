---
id: TASK-117
title: 'Bug: audio takes show no lanes, and every take plays instead of the active one'
status: Done
assignee: []
created_date: '2026-11-22T15:27:00Z'
updated_date: '2026-11-22T16:59:00Z'
labels:
  - bug
  - takes
  - recording
milestone: m-3
dependencies: []
priority: high
ordinal: 129000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner, 2026-11-22, highest priority: choosing a take has no visual indication (the stacked take rows are gone), and on playback all takes play at the same time instead of the active one. An agent reproduces it with real keys, finds the change that caused it (between the pushed e730151b and main), fixes it and adds a regression test for each symptom.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner, 2026-11-22: the problem is AUDIO recording (not MIDI): takes made going round a loop, and recording again over the same range; keep all takes, and an easy way to work with them. Agent redirected to audio, both ways of recording.
<!-- SECTION:NOTES:END -->
