---
id: TASK-122
title: >-
  Looping: one clear way to loop a time selection, clear names, and a visible
  loop state
status: Done
assignee: []
created_date: '2026-11-22T18:19:00Z'
updated_date: '2026-11-22T20:23:00Z'
labels:
  - ux
  - transport
  - loop
milestone: m-4
dependencies: []
priority: high
ordinal: 134000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner, 2026-11-22: it is not clear how to make a loop over the time selection; there are clip.loop, region.loop, transport.loop and the gl operator, their descriptions do not help, and the owner gets confused. There is also no visual sign of whether looping is on or off while playing or recording.

What to do:
- Names: the playback loop and a clip that repeats its content are different things. Rename clip.loop to clip.repeat (no compatibility needed before a release) and describe it as 'the clip repeats its notes or sound when you make it longer; not the playback loop'. transport.loop toggles the playback loop; region.loop sets the playback loop to the region; describe each in those words.
- One clear way: v (or V over tracks) to select time, then gl sets the playback loop to the selection and turns looping on, and says so ('loop: bars 5 to 9, on'). gl with a motion does the same (gl ar = the region, gl ic = the clip). Add :loop with a range (:'<,'>loop, :5,9loop, :loop off). The which-key hint and K on gl explain it.
- Visible state: the ruler draws the loop range bright when looping is on and dim when it is off; the status line shows a loop mark with the range when on (and nothing or a dim mark when off), the same while playing and recording; the window's toolbar toggle shows the state. One view, two frontends: the scene carries it.
- Docs: a short how-to 'Loop a part of the song' fix (it exists: docs/how-to/loop-a-part-of-the-song.md) and the key and command references.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Real-keys test: v over bars 5 to 8, gl: the loop is 5 to 9 and on, and the message says so; gl ar loops the region
- [ ] #2 :'<,'>loop, :5,9loop and :loop off work (tests)
- [ ] #3 clip.loop is clip.repeat everywhere (code, menus, docs); the descriptions of clip.repeat, region.loop, transport.loop and gl say what they do in the user's words
- [ ] #4 The ruler shows the loop bright when on and dim when off, in the terminal and in the scene (scene_parity), also while playing and recording (test)
- [ ] #5 The status line shows the loop state and range while on; documented in status-line.md
- [ ] #6 The how-to and references are updated; Vale 0
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-ab5b612283a0d8591. Commits: 79827843 (the feature: gl/transport.loop_beats/:loop with a range, on/off, clip.loop renamed to clip.repeat, the ruler band bright on and dim off, descriptions, how-to and references), merges of main (7961af21 and e770d109), 6988efa6 (the status line shows the loop only while on; ui.lua's test expects no loop when off, and every project has a default range 0-16, so a dim mark was always there). Full suite before 6988efa6: 2 failures, ui.lua status line (fixed by 6988efa6) and frames.lua 'after an audition... meter at rest' (passes alone, a load-dependent frame test, not in this ticket's files). Area tests pass with the shared binary + dev runtime. Orchestrator to run at the merge: full suite, cargo test -p paw-gui (chrome.rs hint), apidoc check from a release build.

Merged to main in 7ae25570 (batch 1, 2026-11-22): dev build, full suite with plugins passed, nextest paw-core/paw-scene passed.
<!-- SECTION:NOTES:END -->
