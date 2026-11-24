---
id: TASK-233
title: 'Design: how folds, scopes and subprojects look and feel in the terminal'
status: Done
assignee: []
created_date: '2026-11-23T07:12:00Z'
updated_date: '2026-11-23T07:52:00Z'
labels:
  - design
  - ux
milestone: m-2
dependencies: []
priority: high
ordinal: 287000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-23: 'UX is the most important part of this project.' Real screens (scratchpad/screens/shots.txt, made by screens/shots.lua in a sealed run) show what a user sees today when they fold, narrow and make subprojects. Bugs are TASK-226 (regions in a subproject's ruler, negative bar, two numberings). This design covers the rest:
- za on a return row lists the subproject's tracks with nothing that marks them as inside it; the song's own tracks of the same name follow (two Piano rows).
- After :scope.write!, a group leaves the song and the song's own tracks route to the subproject's return row (→ Bridge). The sound is kept, but the user did not ask for it and does not see why.
- K is a box the size of the screen for three lines.
- A block fold is an empty cell named 'Fold 1': no size, no hint of what is in it.
- A scope shows empty bars past its end with a thin mark only.
- Each track is three rows tall, so a song of 7 tracks fills the screen; folds and scopes matter more because of it.
Write backlog/docs/designs/scopes-ux.md: the user's tasks (work on a section, a group, a part of some tracks, reuse a section, bring in a song part), and for each the screens before and after, drawn as real terminal text at 100x30; the marks and words for 'inside a subproject', 'folded', 'narrowed', 'end of scope'; what K shows and how big; what :scope.write and :nest.new do to the song's tracks and groups, with the choices and a recommendation; and the build tickets in order. The owner reviews it before any build.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 backlog/docs/designs/scopes-ux.md covers each task with screens before and after
- [x] #2 Each problem listed above has a decision or a recommendation with the reason
- [x] #3 The build tickets are listed in order with the screens they change
- [x] #4 The owner has reviewed the design
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design written 2026-11-23: backlog/docs/designs/scopes-ux.md (Vale 0 alerts). Screens from sealed runs: scratchpad screens/shots.txt and ux/v1.txt, ux/v2.txt (variants: 8 tracks, zoom out, per-track write, write! of a group in a region, two blocks, nested subproject, split, K, heights 2 and 1).

Main proposals:
- Window bar: the two empty left cells of the ruler show the scope path and the cursor per window (`Verse` / `cur 1.1 @9.1`). The `›` sign in the track column goes. Splits each say where they are.
- Vocabulary: one glyph and one word per idea. `›` path only; `▾`/`▸` open/folded; `⧉` subproject on every row of it; `┆` guide for rows of a subproject under its return row; `@` song bar on screen as in typed input; `┃` end of scope (today only the loop mark `▕`); `×2` and 'places' (not 'instances'); 'subproject' (not 'nest') in K.
- End of a scope: `┃` column, nothing drawn after it, 'end of Verse · zw: the song'.
- za on a return row: `▾⧉ Bridge ×2`, `┆` guide, no song numbers, light header, blank outside blocks, closing line 'end of ⧉Bridge'.
- Group rows show an overview (Ableton); a folded group lists its members; a closed block fold is a frame with name, bars, tracks and keys (takes in TASK-225); default name 'Piano, Pad 9-24'.
- K: a float sized to its text (max 72 cols, half the window), under the cursor; K again to go in; :info keeps the page.
- :scope.write!: keep the song's group; the return row goes into the group (sound kept, no route changes); name any route that changes; several buses: row to master, message names the buses, 'stems' word. :nest.new and :import put the row where o puts a track.
- Track height: auto from 1 to 3 (today 3 to 4).

Bugs found (not in TASK-226): (1) :scope.write! of a view with no time takes all song regions into the subproject (v2 shots O, P). (2) :scope.write! turns the group track into the return row although not all tracks moved in (contradicts subprojects.md). (3) Status line in a nested subproject has no song bar. (4) Narrow split ruler writes 'Verse 251'.

Build tickets in order: UX-1 window bar (S), UX-2 end of scope (S), UX-3 rows of a subproject (M), UX-4 K float (M), UX-5 write! routing + regions bug (M), UX-6 overviews and block fold frame (S), UX-7 auto height 1-3 (XS), UX-8 return row placed like o (XS), UX-9 words and docs (S). Each with T.expect_screen goldens at 100x30.

Nine questions for the owner in section 10, each with a recommendation. AC #4 (owner review) open.

Owner approved all nine recommendations 2026-11-23. Build tickets: TASK-261 TASK-262 TASK-263 TASK-264 TASK-265 TASK-266 TASK-267 TASK-268 TASK-269.
<!-- SECTION:NOTES:END -->
