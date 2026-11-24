---
id: TASK-222.2
title: >-
  Export E2+E6: channels=auto, and :bounce with track and time ranges at
  tap=post (replaces :track.bounce)
status: Done
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T13:48:00Z'
labels: []
milestone: m-2
dependencies:
  - TASK-222.1
  - TASK-223
parent_task_id: TASK-222
priority: high
ordinal: 255000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/export.md (TASK-222), approved by the owner 2026-11-23 with all its recommendations: one command :export; stems = groups, tracks = one file per track; :export tracks taps post; mono (L+R)/2; channels stereo by default, auto in the stems and tracks presets; replace files freely in renders/, elsewhere after the plan or with !; tail 2 s; presets project > init.lua > built-in; :export project inside a subproject's scope replaces :nest.export; :utau.freeze moves onto :freeze later. No compatibility before a release: remove what overlaps. Read the design section of this part before you start.

This part: channels=stereo|mono|auto; mono is (L+R)/2. Size S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: channels=mono writes one channel of (left + right) / 2; a mono source in the center keeps its level
- [ ] #2 Test: channels=auto writes one channel when the two sides are equal to the bit over the whole file, and two channels for the same source panned off center or through a stereo device
- [ ] #3 channels=stereo stays the default; render.md tells the -6 dB sum and what the pan does; Vale reports 0 alerts
- [ ] #4 (TASK-222.6) Test: :bounce on a track writes a new audio track below it at tap=post, mutes the old track, is one undo step, and the message names the new track; through the master the song sounds the same (the tolerance of the freeze tests)
- [ ] #5 (TASK-222.6) Test: :t2,t4bounce and :t'<,'>bounce bounce those tracks to one new track; :'<,'>bounce bounces only the time of the selection
- [ ] #6 (TASK-222.6) Test: :bounce tap=pre gives the new track the fader, pan and sends of the old one
- [ ] #7 (TASK-222.6) :track.bounce is gone; <Space>tb bounces; the docs that named :track.bounce say :bounce; Vale reports 0 alerts
- [ ] #8 (Owner 2026-11-23) Test: a bounce of a time range mutes the old clips only inside that range, and the muted parts show it on screen and in K
- [ ] #9 Test: a bounce of a track in a group with a device sounds the same through the group and the master as the original (TASK-223 left this case to tap=post)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a45d62151ce970eee, commits 90dadaec (channels) and 3d3a4f6e (bounce). Kernel: RenderOpts.channels is an enum Channels {stereo, mono, auto}; auto renders through the raw file and writes 1 channel when L and R are equal to the bit over the file; the result gives the channels written. paw.bounce moved to paw/bounce.tl (Teal): paw.bounce(track, opts) = paw.bounce.track, paw.bounce.tracks(ids, opts); tap=post default, tap=pre copies volume, pan, sends and volume/pan automation (one track only); time range; new file name when taken (audio cache keys by path). :bounce in defaults/project.lua (range=true), <Space>tb (n and x), track menu runs bounce; :track.bounce gone. chosen_tracks moved to defaults/common.lua. Docs: render.md (Mono and stereo, Bounce), ex.md, keys.md, freezing.md, limits.md, how-to freeze, api.md regenerated. Tests: media.lua mono/auto test needs the Rust build; scope.lua three bounce tests pass on the shared binary. Not done: a time-range bounce still mutes the whole old track, as the design says.

Owner change (range bounce mutes only the range): commit b1a88be4 on the same branch. Clips are cut at the range edges (paw.edit.arrange.clear), the parts inside muted with meta.bounced = new track id; outside clips are muted only during the render (no doubled tail). K says 'muted by a bounce: “X” plays it'. Muted clips show ⊘ (x in ASCII) before the name in the arrange view. Test 'a bounce of bars mutes only those bars...' (null outside bars 5-8, one u, golden tests/screens/scope/bounce_bars.txt, K text).

d1694da5: a range bounce plays the notes across its edges whole. The render runs from temporary whole clips of the notes that start in the range (to their end) and the notes held at its start (from where they start); the held notes leave the part before the range, and the bounced clip starts where the first held note starts. Each note sounds in one place, so the whole song nulls under 1e-5 against the live render (test with notes across both edges). A looped clip or a block is still cut at the edges.

PO 2026-11-23 (after batch 16): criteria 8 and 9 added for the merge check: the owner's decision of today (a range bounce mutes only that range, visibly; commit b1a88be4) and the grouped-track case that TASK-223 left open.

Landed on main in batch 17 (deb79a0f), with the merge fixes of 2026-11-23 (clock rounding, export leader domain, goldens, MCP render_stems).
<!-- SECTION:NOTES:END -->
