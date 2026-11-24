---
id: TASK-7.3
title: >-
  Subprojects S1b-S2c: a subproject is a scope, plays into its return row, with
  its own transport
status: Done
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T16:06:00Z'
labels:
  - nest
  - subprojects
  - views
milestone: m-2
dependencies:
  - TASK-7.1
  - TASK-6.1
  - TASK-7.2
parent_task_id: TASK-7
priority: medium
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Combined ticket (owner, 2026-11-22): one agent builds TASK-7.3, TASK-7.4, TASK-7.5 in order, with one build, one suite run and one merge. Commit after each part.

Goal: a subproject is a scope of kind `nest`. The user enters it, leaves it and moves between subprojects with the same keys as for views. The song does not show a subproject's tracks unless the user enters it.

User-visible behavior (nest.md 3.1, 3.7 "Navigation: one model", 4.8, 4.9):
- `znn` or `<CR>` on a nest clip enters the subproject: the window shows its tracks and its timeline, bars from 1, the song's bars on the thin second row; `zw` goes up; `zW` to the song; `<C-o>` `<C-i>` keep the stack; `]z` `[z` go to the next subproject or block.
- The breadcrumb marks a subproject: `Song › ⧉Ballad › Strings 2.1 (34.1)`.
- `<Space>zz` lists views and subprojects together, marked `view` and `nest`.
- The song's scope hides nest tracks: `paw.scope.tracks()` of the song gives the tracks with no nest. The pickers, `%`, `t*`, the mixer and `paw://tracks` go through the scope. `api.track_list` gets `{ all = true }` for scripts that want every track.
- An edit inside is an edit of the project: one undo tree; the labels of its steps name the nest (`Ballad: add note`).

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.1, 3.4, 3.7, 4.8, 4.9. runtime/lua/paw/scope.tl (kinds, `resolve`, `enter`, `sibling`, `breadcrumb`, `local_bar`), runtime/lua/paw/layout.tl, runtime/lua/paw/statusline.tl, runtime/lua/paw/ruler.tl, the scope picker source, runtime/lua/paw/nest.tl and the S1a commit, docs/reference/narrowing.md.

Depends on: TASK-7.1, TASK-6.1 (V3).
Do not touch: playback (TASK-7.4), the arrange drawing of blocks (TASK-7.7).

Size: M.

## Part of TASK-7.4: Subprojects S2b: a subproject plays into its return row

Goal: a subproject's own tracks play in the song, through its return row. This is the chain mode of nest.md 4.4, for the layout of a subproject with its own row (`NestPlay::Master`).

What to build:
- Sync makes one engine track for each pair (nest track, host track) and for the nest's master, places the nest's clips for each instance (follow time: song beat = clip start + nest beat - offset), cuts them at the instance's window, and routes the master into the host track (the return row), as a track into a bus. The N0 spike showed that a track with clips can also be the output of others (crates/paw-engine/tests/bus_clips.rs).
- Two instances on one return row share the engine tracks. A nest on two rows runs its devices twice (`K` will say so in TASK-7.7).
- Tails ring past the end of a block. A muted nest clip mutes its events, not tails that already play.
- The return row's devices, fader, pan and sends act on the subproject's sound.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.7 ("Its outputs into the song"), 4.4, 8. crates/paw-core/src/sync/mod.rs, sync/clips.rs, sync/routing.rs, sync/mapper.rs, crates/paw-engine/tests/bus_clips.rs; the S1a and S2a commits.

Depends on: TASK-7.1, TASK-7.2.
Do not touch: the transport that plugins see (TASK-7.5), the per-track layout (TASK-7.9).

Size: M.

## Part of TASK-7.5: Subprojects S2c: the transport for plugins inside a subproject

Goal: devices inside a subproject see the subproject's bars: bar 1 at the start of its block, with the tempo of the place. Today the engine has one transport for all tracks. This is the one engine change of nest.md 4.4 ("Transport for plugins").

What to build: a per-track transport offset and meter in the engine. CLAP plugins get it in `clap_event_transport`, VST3 plugins in `ProcessContext`, Lua devices in their transport, the built-in tempo-synced devices as they read the transport. No lock and no allocation on the audio thread.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.7 ("Transport for plugins inside"), 4.4. crates/paw-engine/src/tempo.rs (`TempoMap`), crates/paw-engine/src/engine/track.rs, crates/paw-engine/src/host.rs (the transport given to plugins), docs/reference/lua-devices.md (the transport of a Lua device), crates/paw-engine/tests/tempo.rs, .claude/skills/rust-skills.

Depends on: TASK-7.4.
Do not touch: the engine's rest (TASK-16), the quality switch (TASK-80).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 (7.3) Test with real keys: a project made through the API with a nest of two tracks and one nest clip; znn on the nest clip enters it: the arrange shows the two nest tracks, bars from 1, and the breadcrumb with ⧉; zw leaves; <C-o> enters again
- [ ] #2 (7.3) Test: in the song, paw://tracks, the mixer, t* and the track picker do not show the nest's tracks; api.track_list({ all = true }) does
- [ ] #3 (7.3) Test: <Space>zz lists the nest, marked nest, and choosing it enters it
- [ ] #4 (7.3) Test: an edit inside the nest makes one undo step whose label names the nest; u in the song undoes it
- [ ] #5 (7.3) narrowing.md says it; Vale 0 errors
- [ ] #6 (7.4) Test: a synth in a subproject (made through the API) renders the same as the same synth and notes on a song track at the same place (bit-identical, or below -120 dB with the reason written)
- [ ] #7 (7.4) Test: two blocks of one subproject on the return row play it twice
- [ ] #8 (7.4) Test: a muted block is silent, and a reverb tail inside rings past the end of the block
- [ ] #9 (7.4) Test: the return row's volume and a send to a song reverb act on the subproject's sound
- [ ] #10 (7.4) Test: an edit inside the subproject reaches the engine and compiles one time (S2a's counter)
- [ ] #11 (7.5) Rust test: a test device that records its transport sees bar 1, beat 0 at the start of a block at song bar 33, with the song's tempo there; on a song track it sees bar 33
- [ ] #12 (7.5) Test: a Lua device inside a subproject reads the subproject's bar
- [ ] #13 (7.5) crates/paw-engine/tests/no_alloc.rs passes
- [ ] #14 (7.5) docs/reference/lua-devices.md and engine.md say what a device inside a subproject sees; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a83228f05bcfad60d. Commits: 7221f7ef (7.3 scope), 01577d75 (7.4 playback into the return row), 16865da6 (7.5 transport for devices inside), 12aed6b3 (Teal shadow fix), merges of main. 7.3: nest scope kind (znn, <CR>, zw, zW, ]z, <C-o>, <Space>zz marked nest, breadcrumb with ⧉, local bars and song bars row), api.track_list default = song tracks, {nest=id}, {all=true}; track_add/track_move index among the tracks of the place; clip_add kind nest; undo label 'Name: ...' for steps that change only one subproject. 7.4: sync/nests.rs places nest tracks' clips per block, master routes into the return row (NONE when unplaced). 7.5: paw_engine::LocalTime + Msg::SetLocalTime, run_chain gives devices the subproject's bars; no_alloc covers it. Limits: a subproject on two rows plays into the first and runs its devices once; a clip cut at a block start plays only for non-looped MIDI; follow-meter bars in the window use the song map from beat 0 of the subproject. Full suite with plugins: 4 failed in the run (3 timing flakes that pass alone, 1 Teal shadow, fixed).
<!-- SECTION:NOTES:END -->
