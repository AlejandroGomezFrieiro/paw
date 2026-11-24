---
id: TASK-16
title: Devices sleep when silent
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-22T13:25:00Z'
labels:
  - performance
  - engine
milestone: m-3
dependencies: []
priority: medium
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: when the song is stopped and nothing sounds, the audio thread does almost no work. Today the null backend's audio thread takes 1.8% of a core with 64 synths at rest (bench/RESULTS.md, 2026-11-21, "Idle for 30 s").

Devices at rest already sleep (since 2026-11-19: docs/reference/engine.md, "Devices at rest"). What is left is the walk over every track for each block: buffers cleared, sums, meters. So the engine rests as a whole:
- After 8 blocks in which the transport is stopped, no clip plays, no input is monitored, no preview or audition plays, no tail rings and every device sleeps, `process()` writes silence and returns after one check.
- A command from the kernel's queue, a MIDI input event, an armed input, an audition or the start of the transport wakes it in the same block. The first sound comes in the same block as without the rest.
- `engine_get().engine_rests` counts the blocks that the engine rested. `paw.opt.device_sleep = false` turns the rest off too (one switch).

Take care with: tails (a reverb that still rings keeps it awake), side-chains (a compressor never sleeps, so it keeps the engine awake), plugins that make sound without notes (a CLAP plugin that never says it can sleep keeps it awake), the metronome, MIDI clock out while stopped (crates/paw-engine/src/midi_out.rs), the clip launcher's queued clips.

Read first:
- docs/reference/engine.md ("Devices at rest", the `engine_get` table).
- bench/RESULTS.md ("2026-11-19: devices that sleep, and threads only when needed").
- crates/paw-engine/src/engine/process.rs (`process`, `process_input`), engine/work.rs, engine/shared.rs, engine/stats.rs, the null backend in crates/paw-engine/src/backend.rs.
- crates/paw-engine/tests/sleep.rs and tests/no_alloc.rs.
- .claude/skills/rust-skills: the audio thread rules (no lock, no allocation, no wait).

Depends on: nothing.
Do not touch: crates/paw-core/src/sync (TASK-7.2, nest S2a), Lua code. TASK-80 also changes the engine: do not change the quality flags.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test in crates/paw-engine/tests/sleep.rs: 64 synth tracks, stopped; after the settle, engine_rests grows each block and device_runs does not
- [ ] #2 Rust test: a note-on that comes while the engine rests sounds in the same block (the first non-zero sample is where it is without the rest)
- [ ] #3 Rust tests: a ringing reverb tail, a device that never sleeps, a monitored input and the metronome each keep the engine awake
- [ ] #4 crates/paw-engine/tests/no_alloc.rs passes: no allocation and no lock on the audio thread
- [ ] #5 A render is bit-identical with device_sleep on and off (renders do not rest)
- [ ] #6 bench/profile/run.sh idle --perf 30 on project.lua: the audio thread's instructions per second fall by at least 80% against main; bench/RESULTS.md gets the numbers with their spread
- [ ] #7 docs/reference/engine.md documents the rest and engine_rests; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-ad07349e5a837ae8f: cef5155d (engine rest: engine/rest.rs, engine_rests, docs, tests), 3da88d0c (a launch queued while stopped no longer keeps the engine awake; found by the app probe), ae831c7d (bench), 9982a4c3 (merge main). The engine rests after 8 quiet blocks (no device run, silent output, nothing busy, meters below -100 dB, quiet frames at least the schedule latency). A message or MIDI input event wakes it in the same callback. Renders (offline) never rest. paw.opt.device_sleep is the one switch. idle --perf 30 on project.lua: audio thread 38.17 M to 0.1096 M instructions/s (-99.7 %), 1.86 % to 0.38 % of a core, 5 interleaved pairs, measured under external load. Checks: paw-engine tests incl. sleep.rs and no_alloc.rs, full suite plugins (only load-timing failures, which pass alone), apidoc check, tlcheck, fmtcheck, luacheck, Vale 0.
<!-- SECTION:NOTES:END -->
