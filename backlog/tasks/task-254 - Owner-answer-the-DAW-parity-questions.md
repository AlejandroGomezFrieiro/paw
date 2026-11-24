---
id: TASK-254
title: 'Owner: answer the DAW parity questions'
status: Done
assignee: []
created_date: '2026-11-23T07:18:00Z'
updated_date: '2026-11-23T07:52:00Z'
labels:
  - parity
  - owner-decision
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 318000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The DAW parity review (backlog/docs/designs/daw-feature-comparison.md) left questions that only the owner can answer. Each has a recommendation.

1. **Ableton Link (TASK-230).** The Link library is GPL-2.0-or-later or paid; paw is MIT OR Apache-2.0. Recommendation: an optional native part of an extension, off in the default build; or skip Link.
2. **LADSPA.** Old format; most LADSPA plugins have LV2 versions. Recommendation: do not support it.
3. **AAF and OMF import.** Film and post work; a large binary format. Recommendation: do not file now; Ardour import (TASK-248) first.
4. **Spectral edit** (paint out a noise in a spectrogram). Recommendation: do not file now; the spectrogram view (TASK-237.3) first.
5. **LTC** (audio time code). Recommendation: out of scope; MTC (TASK-227.5) covers most sync with film gear.
6. **The order in m-14.** Recommendation: SysEx (TASK-228.1, TASK-228.2) and MIDI clock out (TASK-227.1) first, because surfaces, MMC, MTC and MIDI-CI wait for them; then ripple (TASK-235), automation of sends and mute (TASK-238), MIDI files (TASK-244) and onsets (TASK-234.1, TASK-234.2).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The owner answered each question, and the answers are in the notes of this ticket and of the tickets that they change
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-23: all recommendations. Ableton Link: an optional native part of an extension, off by default (TASK-230). LADSPA: no. AAF/OMF: not now, Ardour import first. Spectral editing: not now, spectrogram view first. LTC: out of scope. Order: SysEx (228.1, 228.2) and MIDI clock out (227.1) first; then ripple (235), send and mute automation (238), MIDI files (244), onsets (234.1, 234.2). Implementation of m-14 still waits for the owner's start.
<!-- SECTION:NOTES:END -->
