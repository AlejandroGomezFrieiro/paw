# Results

This DAW (branch `stress` after merging `main` at 3e0867f) against Tracktion
Engine 3.5.0 (commit c629312, JUCE 7ff644f), on the workloads both can run.
How to run everything: [README.md](README.md). Raw numbers:
`results/final.jsonl` (after the merge) and `results/premerge.jsonl` (the same
matrix before it). The processor time of the whole program while it plays,
against REAPER, Ardour and LMMS, is in [DAWS.md](DAWS.md).



## 2026-11-23: the region tree and the tracks of a scope as memos of paw.derived

`paw.markers.tree()` is a memo of `paw.derived` that reads the source
`project` (the event `project.changed`: the name, `meta` or the tempo
changed). A note edit does not make it stale. Before, each call read
the whole project (`project_get()`) and made a text of every region to
compare with the last one. `paw.scope.tracks()` is a memo for each
scope of the song: it reads the track list, and for a scope with a
group, the `meta` of each track.

The project: 64 tracks with a synth, 2 048 MIDI clips of 25 notes (the
shape of `bench/profile/project.lua`), 500 regions (250 of 8 beats, each
with one of 4 beats inside), and a group of 8 tracks. Each of 25 rounds
moves one note of the first clip of track 3 (`clip_set_notes`,
`paw.flush()`, `undo_checkpoint`), then reads `paw.markers.tree()`,
`paw.scope.tracks()` (the song) and `paw.scope.tracks(group)`. The
script is not in the repository.

The times are the processor time of the kernel thread for one call, the
median of the 25 rounds of each run, and the range of the 5 medians.
`main` (the shared binary of e46ecc13 with its own runtime) and the
branch (its dev runtime on the same binary) ran in turns, 5 pairs, under
the measure lock on cores 16 to 23. The load average was 13 to 18,
measured under external load.

| What | main | branch |
| --- | ---: | ---: |
| `paw.markers.tree()` after a note edit | 1.07 to 1.41 ms | 0.0015 to 0.0027 ms |
| `paw.scope.tracks(group)` after a note edit | 0.75 to 0.84 ms | 0.0020 to 0.0031 ms |
| `paw.scope.tracks()` (the song) after a note edit | 0.005 to 0.016 ms | 0.004 to 0.007 ms |

The count that does not depend on the load: over the 25 note edits, the
branch made the tree 0 times (`stats().made` of `markers.tree` stayed
at 1, the make before the first round) and each scope's tracks once,
at their first read. The largest single read of the tree in a branch
run was 0.048 to 0.054 ms, one read out of 25. The tracks of the song
show no measurable difference: the kernel's track list was already
quick, and the memo gives a copy of its list.

## 2026-11-23: the first scope keys after the group tree change

## 2026-11-23: what the built-in effects cost live, for edit quality

`paw.opt.quality = "edit"` lowers the costly settings of the built-in
devices while paw plays live. To choose the devices, `bench/quality.lua`
measured each effect live: 16 audio tracks with one effect each, on the
null backend at 256 frames and 48 kHz, on one thread. Binary of main at
7f02e829. Five interleaved rounds of 3 s for each device, under
`flock` and `taskset -c 16-23`. Measured under external load (load
average 10 to 14). Raw numbers: `results/quality-2026-11-23.jsonl`.

The processor time is that of the audio thread, from its `schedstat`.
"One instance" is (device - none) / 16.

| Device on 16 tracks | Audio thread, % of a core: median (range) | One instance, % of a core | Mean time per block, ms (budget 5.33) |
| --- | ---: | ---: | ---: |
| none | 2.25 (2.12 to 2.30) | | 0.095 |
| `saturation` at 4x, drive 12 dB | 38.30 (37.61 to 38.55) | 2.25 | 2.03 |
| `reverb` | 27.38 (26.73 to 28.93) | 1.57 | 1.45 |
| `chorus` | 15.59 (14.38 to 17.38) | 0.83 | 0.82 |
| `compressor` (threshold -30 dB, look-ahead 2 ms) | 6.76 (6.27 to 7.27) | 0.28 | 0.34 |

The decision:

- The `saturation` at 4x costs the most. Edit quality turns its
  oversampling off.
- The `reverb` costs 70 % of a `saturation` at 4x. Its cost is in its
  eight delay lines and their drift. Edit quality does not change it,
  because a reverb without the drift rings with a metallic sound, and
  the mix decisions of the user then rest on a wrong sound. A project
  usually has few reverbs, on buses.
- The `chorus` and the `compressor` cost little. Edit quality does not
  change them.

16 saturations at 4x with `full` and with `edit`, measured after the
change: binary of main at cd367da1 (dev profile, optimized), `bench/quality.lua
16 3 5`, five interleaved rounds of 3 s, under `flock` and
`taskset -c 16-23`. Measured under external load (load average 12 to
14). The raw numbers are added to the same file.

| Quality | Audio thread, % of a core: median (range) | Mean time per block, ms: median | p99 per block, ms: worst |
| --- | ---: | ---: | ---: |
| `full` | 36.19 (34.72 to 37.48) | 1.93 | 2.53 |
| `edit` | 4.45 (4.04 to 5.05) | 0.23 | 0.43 |

Edit quality cuts the audio thread time of this project by a factor of
about 8. The ranges do not overlap.

## 2026-11-23: the trace compiler in the first press of a key

An earlier profile found about 45 % of the `jit.profile` samples of each
first key of the scenario `scope` in the state J (LuaJIT's trace
compiler). This section explains that share and the change that lowers
it.

Setup: the shared binary of main (8e91e5b0, dev profile) with the Lua of
main ("main") and of the branch ("branch") as dev runtimes, in turns,
under the measure lock on cores 16 to 23. The load average was 1.4 to 17,
measured under external load. A key is the processor time of the kernel
thread from the key until the screen is quiet for 250 ms. Two new probes
of `bench/profile/drive.py` give the numbers that do not depend on the
load: `traces` (the traces that LuaJIT started, compiled and stopped, and
its flushes) and `--vmstates` (`perf` cycles in each part of LuaJIT).

### What the 45 % was

- Part of it came from the probe. The start and the stop of
  `jit.profile` flush all traces: each key had 2 flushes, and each key
  compiled all its code again. Without the probe, `j`, `k`, `w` and `b`
  compile 0 to 15 traces.
- The rest is real. With `--vmstates` (no flush by the probe), the trace
  compiler was 33 to 41 % of the cycles of the 15 first-press keys of
  `scope` on main (3 runs). For one key it was 21 to 78 %.
- The cause is the size of the trace cache. LuaJIT keeps at most 1 000
  traces (`maxtrace`). When it needs one more, it throws all traces away
  and compiles each hot path again. The start of paw with the large
  project makes about 1 000 traces, and the keys of `scope` make 2 700
  more. On main, paw flushed once during the start and 2 or 3 times
  during the 21 keys of `scope`. The highest trace number at each flush
  was 1 000.
- About 30 % of the started traces stop with no result (abort). The
  reasons, in order: a loop left in a root trace, closures (the
  bytecodes `UCLO` and `FNEW`), `...` (`VARG`), a return to a lower
  frame, an inner loop, the loop unroll limit. These are costs of the
  style of the code, not of a parameter.

### What was tried

`jit.opt.start` in `--setup`, 6 rounds of `scope` in turns (the main runtime
in all). "First keys" is the sum of the 15 keys of `scope` that run once
(not the moves, which run 5 times).

| Parameters | First keys | Traces started | Flushes |
| --- | ---: | ---: | ---: |
| defaults | 422 to 517 ms | 2 809 to 3 999 | 2 to 3 |
| `maxtrace=8000`, `maxmcode=16384` | 330 to 356 ms | 1 114 to 1 202 | 0 |
| `hotloop=200` | 396 to 580 ms | 2 602 to 2 796 | 2 to 3 |
| `hotexit=40` | 418 to 491 ms | 2 472 to 3 008 | 1 to 2 |
| `maxtrace=8000`, `maxmcode=16384`, `hotloop=200` | 332 to 431 ms | 1 048 to 1 291 | 0 |

Only the larger cache gives a difference larger than the spread.
`hotloop` and `hotexit` do not. The runtime now sets `maxtrace=8000` and
`maxmcode=16384` before it loads (`runtime/lua/paw/jit.tl`).

### Main against the branch

| Measure | Main | Branch |
| --- | ---: | ---: |
| `scope`, first keys, 5 pairs | 446 to 535 ms | 325 to 416 ms |
| `scope`, traces started in all keys | 2 991 to 4 164 | 1 131 to 1 256 |
| `scope`, flushes | 2 to 3 | 0 |
| `scope --vmstates`, the trace compiler in the first keys, 3 pairs | 33 to 41 % | 15 to 25 % |
| `scope-keys ':%quantize 1/4\r,u' --times 8`, 4 pairs: `:%quantize` (median of each run) | 93 to 116 ms (54 to 143) | 45 to 54 ms (42 to 100) |
| the same, `u` | 46 to 70 ms (35 to 87) | 34 to 39 ms (32 to 76) |
| `scope-keys 'j,k' --times 20`, 3 pairs: `j` | 6.8 to 7.5 ms (4.9 to 17) | 6.6 to 7.0 ms (5.0 to 40) |
| the same, `k` | 6.9 to 7.6 ms (4.8 to 38) | 5.9 to 6.8 ms (4.9 to 38) |
| `startup`, large project, 4 runs of 3 | 170 to 173 ms (167 to 175) | 168 to 172 ms (167 to 175) |
| `startup`, resident memory after the start | 70.0 to 72.2 MB | 71.1 to 73.3 MB |

A repeated `:%quantize` and `u` now cost half: on main, each pair made
hundreds of new traces, so the cache filled again and again, and each
flush made all the code compile again. Moves and the start show no
measurable difference.

The cost is memory. After the keys of `scope` and 3 more rounds of them,
the branch has 3 057 traces with 2.4 MB of machine code (main: 453
traces after its last flush, 0.4 MB). The resident memory was 117 MB
against 106 MB, but the Lua heap differed by 15 MB in the same runs, so
the part of the traces is not clear from these runs. The number of traces
still grows, by about 150 for each round of `scope`. A long session can
fill the 8 000 traces or the 16 MB of machine code, and LuaJIT flushes
then, as before.

## 2026-11-23: the check of a frozen track after an edit

A frozen track keeps the key of what its file was made from
(`paw/bake_state.tl`). Two nodes of `paw.derived` make the key again
when `K` asks: `freeze.members` (the routing) and `freeze.key` (the
clips, devices, automation and mix of the members, and the tempo). An
edit marks the sources only. It does no work for the freeze.

The project: `bench/profile/project.lua` (64 tracks, 2 000 MIDI clips,
50 000 notes). Track 40 is frozen. Each round edits one note of the
first clip of track 3 (outside the freeze), then one note of the first
clip of track 40 (inside the freeze). Each edit is `clip_set_notes`,
`paw.flush()` and `undo_checkpoint`. Then the branch calls
`paw.freeze.describe` on track 40 (the check of `K`).

The script is not in the repository. The times are the processor time of the kernel
thread, the median of 15 rounds, with the smallest and largest value.
`main` (the shared binary of d5127487 with its own runtime) and the
branch (its dev runtime on the same binary) ran in turns, 5 pairs,
under the measure lock on cores 16 to 23. The load average was 4.1 to
9.6, measured under external load.

| What | main | branch |
| --- | ---: | ---: |
| An edit outside the freeze (p50 of each run) | 0.22 to 0.26 ms | 0.26 to 0.33 ms |
| An edit inside the freeze (p50 of each run) | 0.23 to 0.26 ms | 0.23 to 0.25 ms |
| `K`'s check after the edit (p50 of each run) | none | 0.29 to 0.45 ms (one run 4.1 ms) |

An edit inside the freeze shows no measurable difference: the cost of
the check for each edit is below the spread, so it is less than 0.1 ms.
The branch's edit outside the freeze is 0.03 to 0.1 ms more. That edit
does not touch a node of the freeze. The likely cause is the slice of
the `derived` job that the check before it scheduled, and the
difference is in the spread of the runs.

When `K` asks, the key is
made again: `clip_list` of the track (0.04 ms), `device_get` (0.07 ms),
and the hash of the text. The largest values (up to 9 ms) come when
the read waits for the chord reading of the same job to end.


## 2026-11-23: the first scope keys after the group tree change

The group tree change found that `znn`, `]z` and `znag` cost more in the scenario
`scope` with its branch (22 -> 40 ms, 30 -> 68 ms, 26 -> 40 ms), and that
the `repeat` scenario showed no difference. The cause is the garbage
collector of LuaJIT. The group tree change does not add work: it moves the steps of the
incremental collector from some keys to other keys.

Setup: one binary of main (c386d3a4), with three Lua runtimes in turns,
under the measure lock on cores 16 to 23. "before" is f1b087ae with
`groups.tl` and `trackcolumn.tl` of the parent of the group tree change merge.
"after" is f1b087ae (the group tree change merged). "stamp" is this branch
(`paw.events.stamp()`). All values were measured under external load (load
average 4.1 to 22). A key is the processor time of the kernel thread from
the key until the screen is quiet for 250 ms: the median of the runs, then
the smallest and largest run. `bench/profile/drive.py` now gives, for each
key of `scope`, the full cycles of the collector (`gc_cycles`) and the Lua
heap, and with `--luaprof` a `jit.profile` of each key alone.

With `--luaprof`, 5 pairs (the samples of the 5 runs added):

| Key | Before | After | Collector samples (before, after) | Full cycles (before, after) |
| --- | ---: | ---: | ---: | ---: |
| `znn` | 34.5 ms (29.6 to 36.9) | 39.7 ms (38.1 to 113) | 0, 73 | 0, 2 |
| `]z` | 51.9 ms (46.8 to 57.7) | 61.1 ms (52.3 to 98.2) | 3, 52 | 0, 2 |
| `znag` | 39.2 ms (36.8 to 66.2) | 45.7 ms (43.1 to 106) | 0, 83 | 0, 2 |
| `:%quantize 1/4` | 135 ms (125 to 195) | 130 ms (121 to 198) | 97, 38 | 1, 1 |
| `u` | 102 ms (83.8 to 138) | 84.9 ms (78.5 to 86.0) | 92, 5 | 2, 0 |
| open the piano roll | 41.7 ms (37.2 to 94.6) | 38.1 ms (28.7 to 44.8) | 84, 10 | 1, 0 |
| all 21 keys of a run | 868 ms (852 to 944) | 866 ms (841 to 1005) | 337, 423 | 5, 8 |

The keys that change the scope get the collector's work in "after", and
`:%quantize`, `u` and the piano roll get it in "before". The whole
scenario costs the same.

The heap is smaller in "after" when the keys
start (53.6 MB against 61.1 MB after `znar`): the frames of the group tree change make
less garbage, so the cycle that ends before the scope keys in "before" is
still running there in "after". A run of `repeat` sees no difference,
because each round goes through all phases of the collector.

With `--collect` (a full cycle before each key, outside the measurement), 5
rounds of the three runtimes, no collector work fell in a key:

| Key | Before | After | Stamp |
| --- | ---: | ---: | ---: |
| `znn` | 24.6 ms (23.1 to 32.0) | 30.7 ms (21.5 to 37.9) | 28.4 ms (23.5 to 33.6) |
| `]z` | 33.8 ms (29.8 to 38.9) | 39.8 ms (30.2 to 47.5) | 35.1 ms (33.6 to 45.1) |
| `znag` | 31.6 ms (28.6 to 42.4) | 32.2 ms (31.4 to 48.3) | 28.6 ms (28.2 to 61.5) |

No fix is necessary: the differences of the medians are less than the
spread.

The larger cost of the first time of a key is the trace compiler of
LuaJIT (the state J), with about 45 percent of the samples of each key in
both branches. That cost is not in the scope of this ticket.

Without probes and without `--collect`, 4 rounds of the three runtimes.
Of the 5 values over 70 ms, 3 are in a key where a full cycle of the
collector ended. The other 2 (`znn` and `]z` of "after") are in one run,
at load 8.7, with the heap near its largest (69 MB and 73 MB).

| Key | Before | After | Stamp | Full cycles (before, after, stamp) |
| --- | ---: | ---: | ---: | ---: |
| `znn` | 28.1 ms (24.2 to 56.1) | 23.2 ms (22.7 to 80.7) | 27.7 ms (22.2 to 33.7) | 1, 0, 0 |
| `]z` | 30.7 ms (25.9 to 38.8) | 58.6 ms (36.1 to 82.2) | 34.2 ms (32.5 to 85.5) | 0, 1, 1 |
| `znag` | 36.9 ms (30.5 to 74.5) | 35.5 ms (26.7 to 36.8) | 30.5 ms (29.3 to 39.6) | 2, 0, 0 |
| all 21 keys of a run | 676 ms (632 to 736) | 653 ms (605 to 1529) | 699 ms (601 to 730) | 7, 5, 4 |

`paw.events.stamp()` (part 1 of the ticket) puts the two counts in one
number. It does not change the cost of a frame or of a key in a way that
these runs can show.

## 2026-11-23: :%quantize writes its notes with paw.api.notes_set

The key `:%quantize 1/4` (grid 1 beat) in the region Verse B of the
scenario `scope`: 6 300 notes move, on 63 tracks, with `u` after each key.
One binary (2b340c1f, dev profile) ran with the Lua of 3acafc09 ("before",
the first change of :%quantize) and of 2b340c1f ("after", the bulk note call), as dev runtimes, in turns:
5 pairs, each run under the measure lock on cores 16 to 23. All values were
measured under external load (load average 12 to 26).

| Series | Before | After |
| --- | --- | --- |
| `drive.py scope-keys --keys ':%quantize 1/4\r,u' --times 8`: the median of each run, processor time of the kernel thread | 291, 136, 112, 129, 143 ms (88 to 438) | 115, 106, 90, 90, 99 ms (53 to 221) |
| the same, `u` | 171, 80, 69, 84, 98 ms (48 to 214) | 77, 58, 60, 84, 51 ms (39 to 136) |
| the write of the notes, 8 keys a run: `paw.ex.apply` before, `paw.api.notes_set` after (wall time of the call) | 40, 16, 13, 13, 14 ms (12 to 91) | 1.8, 1.8, 1.7, 1.7, 1.8 ms (1.6 to 2.2) |
| allocation of the Lua heap in one key, the collector stopped (8 keys a run) | 6.05 MB (6.03 to 6.18) | 4.08 MB (4.06 to 4.17) |

The whole key: the median of each "after" run is lower than that of the
"before" run next to it, but the spread of the two series overlaps, so
the size of the change is not known from these runs. The values that do
not depend on the load changed:

- The write of the notes takes about 1.7 ms in place of 12 to 16 ms
  (the lowest runs). Before, `paw.ex.apply` made a table of each change,
  `Clip:edit_notes` made a second one, and the kernel read each with serde,
  in one edit for each of the 63 clips. Now the kernel reads three lists
  of numbers and makes one edit. The "after" value has no Lua part: the
  loop of `:quantize` now fills the lists itself, and its cost is in the
  whole key.
- 2 MB less allocation a key: no change table and no item of a change for
  each moved note.

What is left of the key is mostly the read of the notes (`paw.ex.items`,
a table for each note from `paw.api.clip_notes`) and the redraw.

## 2026-11-23: what :%quantize costs after the scope change of :%quantize and the group tree change

The key `:%quantize 1/4` in the region Verse B of the scenario `scope`
(about 6 400 notes on 63 tracks), with `u` after each key. One binary of
main (b48920a4) ran with the Lua of main ("before") and of the branch
("after"), in turns, under the measure lock on cores 16 to 23. All values
were measured under external load (load average 2.2 to 3.1). Each value is
the processor time of the kernel thread from the key until the screen is
quiet.

| Series | Before | After |
| --- | --- | --- |
| a driver of the ticket, 3 pairs of 8 keys | 140 ms (95 to 206) | 109 ms (80 to 186) |
| `drive.py scope-keys --keys ':%quantize 1/4\r,u' --times 8`, 3 pairs (medians of each run) | 121, 128, 123 ms (93 to 233) | 132, 142, 111 ms (76 to 174) |
| instructions of the kernel thread (`perf stat`), 8 keys | 650 to 1 919 million | 857 to 1 334 million |

The two series of time do not agree, and each difference is inside the
spread: there is no measurable difference of the whole key. The values
that do not depend on the load changed:

- Allocation of one key, with the garbage collector stopped: 15.3 MB before
  (15.3 to 15.6), 11.4 MB after (11.0 to 11.7).
- The garbage collector in the LuaJIT profile: 19.4 ms of samples a key
  before, 11.5 ms after.

What changed:

- `:quantize` snaps each start with `paw.notes.snap` (new). Before, it
  copied each note and made two tables for each note (1.1 MB a key).
- `paw.ex.items` sorts with a merge sort in Lua. `table.sort` calls the
  Lua comparator from C, and LuaJIT cannot compile that call: 4.8 ms of
  samples a key before, 3.4 ms after.
- `paw.commands.list` keeps its sorted list until a command comes or goes.
  Completion asked for the list after each typed character (2 ms a key).

The criterion "under 100 ms" is not met. The parts that are left, from the
LuaJIT profile of 10 keys after the change (taking the samples adds about 5 %:
131 ms of samples a key against a median of 127 ms):

| Part | ms a key | What it is |
| --- | --- | --- |
| The chord reading (the job `derived`) | 46 | 63 tracks changed in 32 windows: 2 142 track windows, 256 groups, 32 mixes, the chords and the keys of the whole song again. About 15 ms of it is the work of `paw.derived` itself (`settle`, `ensure`, `get`, `link`, `push_over`), the rest is `paw.harmony.read` and `paw.harmony.song`. |
| The command | 32 | `ex.items` 17 ms (the kernel gives each note as a table, 4 ms; the items and their sort), `ex.apply` 12 ms (the kernel takes the 6 400 changes, 7 ms). |
| One full frame of the arrange view | 27 | `views/arrange.lua` (since ported to Teal). |
| The typing and the events | 27 | The preview of the range after each character (2 ms, mostly `paw.scope`), the completion (1.5 ms), the event handlers of `paw.scope`, `paw.ui` and `paw.freeze` (5 ms), the status line. |
| Of all the above, the garbage collector | 11.5 | 11.4 MB a key: 5 MB the command, 1.9 MB the chord reading, the rest the frame and the typing. |

To go under 100 ms, the next steps are in the kernel or in other tickets:
a change of many notes in one call that does not go through a Lua table
for each note (the command), a chord reading that does not decode the whole
song after each edit, and the frame of the arrange view.

## 2026-11-23: the chord reading after :%quantize in Verse B

## 2026-11-23: paw.derived finds the entries over a change by their spans

The same key and probe as the scope change below: `:%quantize 1/4` in Verse B of
the scenario `scope`, with `u` after each key. One binary of main
(d5127487) ran with the Lua of main ("before") and of this branch
("after"), in turns, under the measure lock. All values were measured
under external load (load average 2.5 to 6.4).

| What | Before | After |
| --- | --- | --- |
| Spans compared with a change of a track, in one reading | 17 984 (64 × 281) | 2 368 (64 × 37) |
| Entries made again | 2 048 track windows, 256 bars of tracks, 256 groups, 32 mixes | the same |
| Allocation of one reading (medians of 5 runs) | 1.49 to 1.62 MB | 1.51 to 1.54 MB |
| Allocation of the first reading after the start (the largest) | 2.4 MB | 2.9 to 3.4 MB: the 64 indexes are made once |

The count "before" comes from a counter in `overlaps` of main's Lua (a
copy of the runtime, only for this probe).

The time of one reading (wall clock, 40 keys, 10 pairs): medians 15.2,
21.9, 15.6, 19.1, 16.2, 24.2, 22.1, 22.2, 23.2, 21.5 ms before (11.1 to
63.8) and 13.9, 12.5, 14.8, 15.4, 13.7, 22.1, 20.2, 18.1, 21.0, 20.1 ms
after (9.8 to 55.6). The median after is lower in each of the 10 pairs, by
0.8 to 9.4 ms (about 10 %), but the spreads overlap. The whole key
(`drive.py scope-keys --keys ':%quantize 1/4\r,u' --times 8`, cores 16 to
23, 3 pairs): medians 106, 106, 102 ms before (70 to 162) and 115, 111,
125 ms after (65 to 159). That difference is inside the spread: no
measurable difference. The reading is a small part of the key.

What changed: an entry whose value tells where it changed (`touched`, the
tracks) keeps the entries that read it in an index by their spans: by
start, with the latest end up to each one, as `over` in
`paw/harmony/song.tl` keeps the places of a track. `push_over` starts at
the last span that starts before the end of the change, and goes back
while a span can end after its start. A change of the 4 bars of Verse B
compares 37 spans of each track (32 windows, 4 bars and the length of the
song, which has no span), not all 281. The index is made at the first
change, and again only after a new or a lost user, a new span, or a pass
that stopped at an error. `tests/derived.lua` counts the spans compared
after `:3quantize` on 2 tracks: 20 for a song of 8 bars and for one of 32
bars, and more for `:3,6quantize`.

## 2026-11-23: a walk of paw.derived without recursion

The same key and probe as the chord reading change below: `:%quantize 1/4` in Verse B of
the scenario `scope`, with `u` after each key. One binary of main
(b48920a4) ran with the Lua of the chord reading change branch ("before") and of this
branch ("after"), in turns, under the measure lock. All values were
measured under external load (load average 3.8 to 14.0).

| What | Before | After |
| --- | --- | --- |
| Entries made again | the same (2 048 track windows, 256 groups, 32 mixes) | the same |
| Traces that LuaJIT stopped in `paw.derived` at the call unroll limit (20 keys, 2 runs) | 22, 37 | 0, 0 |
| Traces that LuaJIT stopped at a closure in `push_over` (20 keys, 2 runs) | 26, 35 | 0, 0 |
| Allocation of one reading | 1.48 MB (1.46 to 2.4) | 1.46 MB (1.45 to 2.5) |
| Lua bytecodes of one reading, with the compiler off | 8.79 million | 8.91 million |

The time of one reading (wall clock, 40 keys, 5 pairs): medians 19.5,
18.4, 22.8, 23.3, 24.6 ms before (13.8 to 66.0) and 25.6, 23.0, 23.8,
22.3, 22.3 ms after (15.1 to 57.4). The whole key
(`drive.py scope-keys --keys ':%quantize 1/4\r,u' --times 8`, cores 16 to
23, 3 pairs): medians 126, 147, 148 ms before (70 to 294) and 156, 133,
119 ms after (81 to 210). Both differences are inside the spread: no
measurable difference.

What the profile shows (`jit.profile` of LuaJIT, 40 keys, samples whose top frame
is in `paw.derived`): 581 to 603 compiled, 117 to 189 in the trace
compiler and 7 to 13 in the interpreter before; 582 to 631 compiled, 134
to 323 in the trace compiler and 20 to 40 in the interpreter after. The
bookkeeping was compiled code before this change too. Its cost is the
number of entries that it touches: about 2 950 entries go stale, and
`push_over` looks at each of the about 280 entries that read each of the
64 tracks (about 18 000 checks of a span). A walk that touches fewer
entries, for example the entries that read a track kept in the order of
their spans, can make it smaller; the form of the walk does not.

## 2026-11-23: the chord reading after :%quantize in Verse B

The key `:%quantize 1/4` in the region Verse B of the scenario `scope`
(64 tracks, 4 one-bar clips of each track in the region), with `u` after
each key. One binary of main (b48920a4) ran with the Lua of main
("before") and of the branch ("after"), in turns, under the measure lock.
All values were measured under external load (load average 6.6 to 14.8).

The values that do not depend on the load, for one reading after the key
(a probe in the kernel: `song.update()` after the key, the garbage
collector stopped):

| What | Before | After |
| --- | --- | --- |
| Track windows made again | 2 176 (64 × 34) | 2 048 (64 × 32) |
| Bars of a track made again (for the key) | 384 (64 × 6) | 256 (64 × 4) |
| Groups, mixes, windows made again | 256, 32, 32 | 256, 32, 32 |
| Allocation | 2.0 MB (2.0 to 3.3) | 1.47 MB (1.46 to 2.4) |
| Lua bytecodes, with the compiler off | 9.60 million | 8.79 million |

The time of the same reading (wall clock, 40 keys, 3 runs each):
medians 28.2, 31.8, 28.8 ms before (17.5 to 59.0) and 19.9, 26.7, 48.6 ms
after (15.9 to 170.3; the load went to 14.8 in the last run). The whole key
(`drive.py scope-keys --keys ':%quantize 1/4\r,u' --times 8`, cores 16 to 23,
3 pairs): medians 132, 138, 130 ms before (94 to 208) and 141, 128, 121 ms
after (80 to 221). The difference of the whole key is inside the spread: no
measurable difference.

What changed:

- A window that only touches a changed clip at an edge is not made again.
  Before, the window before the first moved note and the window after the
  last one were made again on each track (2 of 34).
- `paw.derived` keeps the span of each entry from its last make, so a
  change of a track does not call `span` for each of the 280 entries that
  read it. It uses the lists of entries read again, and it does not compare
  the sources of an entry when the list is the same.
- A track window reads the window length from its track and not from
  `harmony.step`: 2 048 reads less after this key.
- A track reads its mute and its clips as single fields, not the whole track
  with its devices and lanes.

What the ticket said and what the profile shows: the whole-song decode is
not the cost. In the LuaJIT profile of 20 keys, `read.decode` and
`read.key_path` take about 1 ms a reading together (0.4 ms each with a timer
around them). About half of the reading is the bookkeeping of `paw.derived`
for about 2 900 entries (`went_stale`, `link`, `ensure`, `settle`, `near`),
and much of it runs in the interpreter, because the graph is recursive. The
rest is `read.part` for the 2 048 windows and the 64 tracks made again.
A decode that starts at the first changed window would save less than
0.5 ms, so the branch does not do it.

## 2026-11-23: the key d, the collector between keys, and `events_take` after u of dd

Setup: the shared binary of b48920a4 (dev profile), with the Lua of
b404646a ("main") and of this branch in turns (`PAW_RUNTIME`), under the
measure lock on cores 16 to 23. The project of `bench/profile/project.lua`
(64 tracks, 2 000 clips, 50 000 notes). A key is the processor time of the
kernel thread from the key until the screen is quiet for 300 ms. The script
and its probes are not in the repository: they use `drive.py` of the cache key change
(`measure_key`, the `paw.limit.slow` list, `handlers.lua`). All values were
measured under external load.

### The key d

The key `d` (an operator before its motion) draws one whole frame, and that
frame is the cost. `jit.profile` of 15 presses of `d` (main, load 7.1):
74 % of the samples are in the arrange view (`arrange.lua:render`, its
`lane` 39 %), 6.5 % in the status line, 57 % in the state J (the trace
compiler). The keymap itself takes 0.2 ms.

Now a key that only waits for the next key (an operator, a count, a
register, a prefix, Escape out of them) draws only the status line and the
command line, as live parts (`ui_redraw_line`). A view that draws the mode
of an operator (the arrange view with lanes open) says so with
`operator_shown`, and gets a whole frame.

`d` then Escape, 15 rounds a run, 4 runs each in turns (load 3.8 to 5.1).
The key comes over the control socket (`keys`): the shared binary does not
have the kernel change of this branch, and a key of the terminal there
always draws a whole frame. The median of each run, and the smallest and
largest press of all runs:

| Key | Main | Branch |
| --- | ---: | ---: |
| `d` | 5.3, 5.6, 6.1, 6.4 ms (3.8 to 47.4) | 1.4, 1.5, 1.6, 1.6 ms (0.8 to 32.8) |
| `Esc` after `d` | 10.3 to 13.2 ms | 6.5 to 7.7 ms |

The largest values are the first press of a run. `Esc` also pays the
whole frame of the list of keys that `d` asks for after
`paw.opt.hint_delay` (500 ms).

The kernel change (`crates/paw-core/src/kernel.rs`): a key of the terminal
sets no whole frame by itself. `K.key` asks for it, unless the keymap drew
only the lines. Before, each key of the terminal drew a whole frame, also
a key typed in the `:` line, which only the tests (keys over the socket)
drew as a line.

### The collector after an edit

In main, LuaJIT's incremental collector ends some cycles inside a key.
The turn of the key then pays the atomic step and the sweep, and
`paw.opt.budget_ms` names "an event handler" or a frame. Now the cycle
runs as the job `collector` of `paw.slices` (paw/collector.tl), in slices
of 2 ms between keys, after a turn in which the heap grew to 2 times its
size after the last cycle. LuaJIT's own pause is 300 %, so it starts a
cycle in a turn only when one turn makes more garbage than that room.
Between two slices, the job stops the collector. Without that, the turns in
between paid steps as they allocated, and the next slice paid what they
left owed (slices of 5 to 13 ms).

`repeat` of `x`, `u`, `dd`, `u`, 10 rounds a run with `handlers.lua`, 4
runs each in turns (load 3.7 to 7.7):

| | Main | Branch |
| --- | ---: | ---: |
| Ends of a turn over 4 ms in which the heap fell (160 presses of `u` after `dd` a side) | 3 (4.7, 6.9 and 15.7 ms; the heap fell 5 to 6 MB) | 0 |
| Runs that name "an event handler" | 2 of 4 (6.9 and 15.7 ms) | 1 of 4 (19.1 ms, the heap did not fall) |
| Cycles that the job ended in a run | none | 6 to 7 |
| Slices of the job over 5 ms in a run | none | 1 to 3 (5.3 to 15.4 ms) |
| `dd`, median of the runs | 58.0 to 70.9 ms | 54.9 to 69.9 ms |
| `u` after `dd`, median of the runs | 54.7 to 79.6 ms | 47.4 to 82.4 ms |

The key costs show no measurable difference: the work moves, and the
cycles come as often as before. A probe of each call of
`collectgarbage("step", 0)` in the job found one step of 9.6 and one of
15.3 ms of processor time in a run, with a heap of 36 MB. That is one
indivisible step of the cycle (the atomic step or one large table), and a
key that comes then waits for it. The slow event handler of the branch was
not the collector: in a probe run, the two calls of `events_take` over 3
ms took 5.1 and 3.6 ms on the clock and 1.2 and 0.7 ms of processor time
(the thread did not run).

### `events_take` after u of dd

`u` after `dd` gives 35 events in one call (32 `clip.added`,
`track.added`, `device.added`, `changed`). `events_take` first sends the
edits to the engine (the 32 clips of the track that comes back), then
makes a table for each event. A script (`-l`, 30 rounds a run, 2 runs
each, load 3.5 to 4.5) timed each call:

| | Main | Branch |
| --- | ---: | ---: |
| `events_take` after `u` of `dd` | 0.224 ms median (0.200 to 0.377) | 0.221 ms median (0.185 to 0.282) |
| An empty call | about 1 µs | about 1 µs |

In the terminal it is called on each turn, about 27 times a press. The
sum for a press was 0.76 to 1.22 ms in main and 0.78 to 0.88 ms in the
branch, and the largest call 0.54 to 3.87 ms in main and 0.55 to 0.99 ms
in the branch. The large calls of main (up to 4.6 ms) are steps
of the collector that its allocations ran: the heap fell in that call. In
the branch they come in the job.

## 2026-11-23: the group tree and the marks of groups in a frame

The scenario `scope` of `bench/profile/drive.py`, with the Lua of the
the scope keys branch (c210bbc2, "before") and of this branch ("after") in turns
on the shared binary of main, 6 pairs, under the measure lock on cores 16
to 23. The binary changed from 07a06cd3 to bc16df6d during the first 3
pairs; the last 3 pairs ran on bc16df6d. All values were measured under
external load (load average 2.9 to 18.8). A frame is the processor time of
`paw.api.ui_snapshot` (40 frames after `j` or `k` in each run): the median
of the 6 run medians, then the smallest and largest frame of all runs. A key
is the processor time of the kernel thread from the key until the screen is
quiet for 250 ms, as in the scope keys.

In `jit.profile` samples of 40 rounds of `j` and `k` in the song,
`trackcolumn.tree_of` took 40 % and `groups.meta` 31 % of the samples
before, and 0.9 % and 1.9 % after. Two causes:

- The fold part of the track column worked out the tree of groups again for
  most lines of each frame. Its key held `paw.folds.list()`, which is a new
  table for each call in a window with no folds. Now the tree is kept while
  the tracks drawn, the window, the change count of the folds and the edits
  of the project are the same (`runtime/lua/paw/trackcolumn.tl`).
- Each question to `paw.groups` (`of`, `is_group`, `hidden`, `rows`) read
  the track's `meta` from the kernel. Now the marks and the group of each
  track are kept until the project or an event changes, with the key of
  `paw.scope`'s regions (`runtime/lua/paw/groups.tl`).

| Measurement | before | after |
| --- | ---: | ---: |
| A frame of the song | 11.1 ms (7.6 to 139) | 5.5 ms (3.4 to 29) |
| A frame in the region | 11.7 ms (7.8 to 111) | 5.9 ms (3.5 to 41) |
| A frame in the group (16 tracks) | 7.8 ms (5.6 to 66) | 7.6 ms (5.4 to 86) |
| `j` in the region | 10.2 ms (8.7 to 21) | 6.2 ms (5.0 to 8.6) |
| `k` in the region | 11.8 ms (9.1 to 27) | 6.2 ms (4.7 to 9.6) |
| `w` in the region | 15.4 ms (11.4 to 72) | 5.8 ms (4.8 to 16) |
| `b` in the region | 11.5 ms (9.3 to 56) | 7.1 ms (4.9 to 12) |
| `zm` | 27.3 ms (21.5 to 56) | 31.4 ms (23.2 to 60) |
| `znn` | 21.8 ms (18.5 to 25) | 40.5 ms (23.9 to 60) |
| `]z` | 30.3 ms (25.8 to 40) | 67.7 ms (31.4 to 90) |
| `znag` | 26.4 ms (24.4 to 29) | 40.4 ms (32.9 to 104) |
| `j` in the group | 11.6 ms (9.0 to 42) | 9.7 ms (8.1 to 60) |

A frame of the song or of a region costs half of what it cost. A frame in
the group costs the same: it draws 16 tracks, not 64.

The keys that change the scope (`znn`, `]z`, `znag`) cost more in the
scenario, where each runs once. The time is before the first frame, not in
the drawing. With the `repeat` scenario and the same keys in the same order
(`znar,zfar,zm,zr,znn,zw,]z,zW`, 8 rounds, under `jit.profile`), the two
branches cost the same: 167 against 172 ms for each round, and the median
first frame of `]z` is 9.2 against 7.7 ms. The cause of the difference in
the scenario is not known.

The first version of this change worked out the tree in each layout. That
made `zm` cost 42 ms (41.9 to 50.5) against 27 ms: in a window with folds,
`paw.folds.row` looks at each fold for each track. The kept tree removed
that cost.

## 2026-11-23: :%quantize in a scope

The key `:%quantize 1/4` and then `u`, in the scope `Song › Verse B` of the
scenario `scope`, with `--budget 10`. One binary of main
(bc16df6d) ran with the Lua of main with the scope keys merged ("before") and of
the branch ("after"), in turns, 3 pairs of 5 keys each, under the measure
lock on cores 16 to 23. All values were measured under external load (load
average 3.3 to 4.8). Each value is the processor time of the kernel thread
from the key until the screen is quiet: the median of the 15 keys, then the
smallest and the largest.

| Key | Before | After |
| --- | --- | --- |
| `:%quantize 1/4` | 217 ms (152 to 257) | 135 ms (85 to 190) |
| `u` | 101 ms (68 to 140) | 74 ms (52 to 125) |

The callbacks over 10 ms, in the 15 keys of each:

| Callback | Before | After |
| --- | --- | --- |
| the job `derived` after `:%quantize` | 15 times, at most 53.5 ms | 2 times, at most 13.8 ms |
| the job `derived` after `u` | 15 times, at most 55.3 ms | 0 times |
| the job `harmony` | 15 and 15 times, at most 69.0 ms | 0 times |
| the command `quantize` | 15 times, at most 123.8 ms | 15 times, at most 37.7 ms |
| drawing the screen | 17 and 15 times, at most 79.2 ms | 16 and 15 times, at most 35.4 ms |

What changed:

- A note edit marked every window of its track stale (256 windows a track
  in this project), and the job looked at all 16 640 windows of the song
  again. Now the track, the track list, the span, the step and the bars
  are `eager` nodes of `paw.derived`: the job makes them first, and marks
  the windows only over the time that changed.
- The job stopped only where a sliced node asked. One window could make
  hundreds of entries in one slice. Now a slice stops before each entry
  that it makes, at any depth.
- The track read `clip_list` (each clip with all its fields) and asked
  `is_drums` after each edit. Now `harmony.place` reads one clip by its id,
  and `harmony.drums` reads the track's name, meta and devices only.
- `:%quantize` read the notes of every clip of the scope's tracks. Now it
  asks only for the clips that meet the range's time, it sends only the
  notes that move, and each with only its changed fields.

Criteria of the ticket: the job `derived` is under 10 ms in all but 2 of
25 keys (a slice of 4 ms and the garbage collector, by the profile). `u`
is under 100 ms. `:%quantize` is not: what is left, by the LuaJIT profile
(about 60 % of its time):

- Two frames of the screen, 20 to 35 ms each. Part of each is the group tree
  of the track column (`trackcolumn.tree_of`, the group tree change).
- The typing of the command: completion sorts `commands.list` after each
  character, and the preview parses the range (about 10 ms).
- `ex.items`: the kernel gives each note as a table (about 9 ms), and the
  sort of the items (about 5 ms).
- The kernel's events and the garbage collector.

## 2026-11-23: keys in a scope

The scenario `scope` of `bench/profile/drive.py` ([profile.md](profile.md)).
The project: `bench/profile/project.lua`, with five regions and a group of 16
tracks that the scenario adds. One binary of main (07a06cd3) ran with the Lua
of main and of the branch (`PAW_RUNTIME`), in turns, 3 pairs, under the
measure lock on cores 16 to 23. All values were measured under external load
(load average 3.3 to 6.7). Each value is the processor time of the kernel
thread from the key until the screen is quiet for 250 ms: the median of the
3 runs, then the smallest and largest value of all runs (a move runs 5 times
in each run). "First frame" is the median time from the key to its first
frame on the branch.

Two causes were over the limit or made a scope slower than the song:

- Each frame asked for the region of the scope again, for each lane and for
  each bar of the ruler. Each time, `paw.markers.list()` read the whole
  project from the kernel. Now `paw.scope` keeps the regions until the
  project or an event changes (`runtime/lua/paw/scope.tl`).
- `:%quantize` in a region read every note of every clip of the scope's
  tracks, and then kept the notes in the region's time. Now the kernel gives
  only the notes that sound in the time (`runtime/lua/paw/ex.tl`).

| Key, in the order of the scenario | main | branch | first frame |
| --- | ---: | ---: | ---: |
| A frame of the song | 11 ms (8 to 48) | 11 ms (8 to 51) | |
| `znar` (into Verse A) | 39 ms (35 to 39) | 38 ms (34 to 38) | 33 ms |
| A frame in the region | 13 ms (11 to 60) | 11 ms (8 to 57) | |
| `j` | 16 ms (12 to 57) | 11 ms (9 to 18) | 11 ms |
| `k` | 14 ms (12 to 45) | 10 ms (9 to 14) | 10 ms |
| `w` | 17 ms (11 to 31) | 19 ms (11 to 45) | 12 ms |
| `b` | 15 ms (13 to 51) | 12 ms (10 to 54) | 12 ms |
| `zfar` | 12 ms (11 to 13) | 7.0 ms (6.9 to 8.4) | 7 ms |
| `zm` | 40 ms (34 to 101) | 25 ms (24 to 26) | 16 ms |
| `zr` | 14 ms (13 to 42) | 7.3 ms (6.8 to 13.2) | 7 ms |
| `znn` (into Strings in Verse A) | 28 ms (27 to 115) | 20 ms (19 to 21) | 12 ms |
| `zw` | 17 ms (16 to 30) | 4.8 ms (4.5 to 14.9) | 5 ms |
| `]z` (Verse B) | 32 ms (29 to 36) | 27 ms (26 to 30) | 11 ms |
| `:%quantize 1/4` (about 6 400 notes) | 270 ms (245 to 301) | 253 ms (225 to 262) | 76 ms |
| `u` | 111 ms (84 to 133) | 92 ms (81 to 114) | 31 ms |
| Open the piano roll (`<CR>`) | 36 ms (33 to 44) | 32 ms (29 to 37) | 25 ms |
| `j` in the piano roll | 40 ms (31 to 74) | 42 ms (35 to 60) | 5 ms |
| `:q` | 21 ms (19 to 23) | 19 ms (16 to 21) | 19 ms |
| `zW` | 17 ms (14 to 20) | 19 ms (13 to 21) | 19 ms |
| `znag` (into Strings) | 24 ms (22 to 26) | 28 ms (24 to 36) | 19 ms |
| A frame in the group | 7.2 ms (5.8 to 48) | 7.2 ms (5.7 to 37) | |
| `j` in the group | 11 ms (10 to 47) | 11 ms (10 to 46) | 11 ms |
| `k` in the group | 9.5 ms (8.8 to 50) | 11 ms (9 to 46) | 11 ms |
| `zw` out of the group | 6.6 ms (6.6 to 6.9) | 7.1 ms (6.5 to 7.4) | 7 ms |

A frame in the region now costs the same as a frame of the song, and a frame
in the group costs less. Before, a frame in the region cost 13 to 14 ms
against 11 ms for the song. In the samples of `jit.profile`, `markers.list`
was 21 % of the region's frames before and 1.5 % after.

Each key is under 100 ms but two. `:%quantize 1/4` and the `u` after it are
over the limit. Their first frame comes after 76 and 31 ms. The rest is work
after the frame: the chord reading runs one slice of 61 to 103 ms (the job
`derived`), and the command itself costs 45 to 58 ms. The same edit on the
whole song costs more, so it is not a cost of the scope. The scope change of :%quantize is
for it.

`j` in the piano roll costs 35 to 60 ms because the note that it plays
moves the meters.

## 2026-11-23: each request of a connection ends its own turn

A request over the control socket (`eval`, `cmd`) now ends its turn
before its reply: the kernel's `settle` and the undo step. Before, a
client that sent its next request at once shared one turn with it. The
cost of the end of a turn alone is `edit.lua turn <tracks>`: 200 turns
with nothing changed (a read) and 200 after one volume edit. One binary
of main (6c3286a3), 3 runs for each size, wall time of the Lua calls,
not under the measure lock, under external load (load average 11 to 13).

| Tracks | Nothing changed, median | After an edit, median | After an edit, largest |
| ---: | ---: | ---: | ---: |
| 10 | 0.005 ms | 0.049 to 0.052 ms | 0.21 ms |
| 100 | 0.004 to 0.006 ms | 0.10 to 0.14 ms | 0.71 ms |
| 500 | 0.004 ms | 0.46 to 0.64 ms | 1.9 ms |

A read pays about 5 microseconds more. An edit pays the end of its
own turn, which it paid before only when the client paused. Keys of a
terminal still share one turn when they come fast.

## 2026-11-22: windows kept by their stamp

A window without the keyboard keeps its cells while the `stamp` of its
view and the stamp of the frame do not change (`runtime/lua/paw/ui.tl`).
The arrange view, the piano roll and the mixer give a stamp.

The project: `bench/profile/project.lua`. The piano roll is open on the first
MIDI clip, under the arrange view, with the keys. The scenario is
`repeat --keys 'j,k' --times 30`. One binary of main (7ae25570) ran with
the Lua of main (5d520705) and of the branch (`PAW_RUNTIME`), in turns,
8 pairs, under the measure lock on cores 16 to 23. All values were
measured under external load (load average 4 to 13).

| `j` then `k` in the piano roll | main | branch |
| --- | ---: | ---: |
| Processor time of the kernel thread, for each round | 32.8 ms (25.9 to 40.6) | 29.8 ms (22.7 to 33.8) |
| Frames that drew the screen for 5 ms or more, in 60 keys | 23 to 29 | 5 to 9 (24 in one run at load 12.6) |

The arrange view above the roll is no longer drawn after each key. The
processor time falls less than the slow frames. Most of the time of a
round goes to the meters of the note that `j` and `k` play, in frames of
the live parts.

## 2026-11-22: the event handlers after an edit

`bench/profile/handlers.lua` times each event handler where
`paw.events` calls it, and the parts of the end of a turn around them
(`events_take`, the whole `K.settle`). The scenario: `run.sh repeat
--keys x,u,dd,u --times 40` on the project of `project.lua` (64 tracks,
2 000 MIDI clips, 50 000 notes), the terminal, budget 5 ms. Main is the
runtime in the binary of 7ae25570; the branch is its runtime from
`tools/dev-runtime.sh` with the same binary. Wall times, measured under
external load (load average 8 to 10). "A press" is the mean over the 40
presses; "longest" is one call. The handlers under 0.05 ms a press are
not in the table.

| Keys | Event | Handler | Calls a press | main ms a press (longest) | branch ms a press |
| --- | --- | --- | ---: | ---: | ---: |
| `x` | `track.changed` | `paw/derived.tl` (mark a track's clips) | 1 | 0.61 (1.24) | < 0.05 |
| `x` | `track.changed` | `paw/scope.tl` | 1 | 0.06 | 0.06 |
| `x` | all the handlers | | 32 | 0.77 | 0.24 |
| `dd` | `track.removed` | `paw/derived.tl` (mark the track list) | 1 | 0.93 (2.87) | < 0.05 |
| `dd` | `device.removed` | `paw/freeze.lua` (is the track frozen) | 1 | 0.51 (1.27) | < 0.05 |
| `dd` | `track.removed` | `paw/groups.tl` (the group of the track) | 1 | 0.25 (1.10) | 0 |
| `dd` | `device.removed` | `paw/address.tl` (the device's address) | 1 | 0.20 | < 0.05 |
| `dd` | all the handlers | | 37 | 2.05 | 0.17 |
| `u` after `dd` | `track.added` | `paw/derived.tl` | 1 | 0.94 (2.65) | < 0.05 |
| `u` after `dd` | `device.added` | `paw/address.tl` | 1 | 0.22 | < 0.05 |
| `u` after `dd` | `clip.added` | `paw/defaults/transport.lua` (a take over a clip) | 32 | 0.14 | < 0.05 |
| `u` after `dd` | `clip.added` | `paw/address.tl` | 32 | 0.05 | < 0.05 |
| `u` after `dd` | all the handlers | | 339 | 1.58 | 0.33 |
| `u` after `x` | `track.changed` | `paw/derived.tl` | 1 | 0.65 (2.69) | < 0.05 |
| `u` after `x` | `cursor.changed` | `paw/defaults/transport.lua` (the track that the keyboard plays) | 1 | 0.20 | 0.19 |
| `u` after `x` | all the handlers | | 51 | 1.07 | 0.42 |

Each handler of `clip.removed` takes less than 0.05 ms a press. A
`changed` event comes after each edit; its handlers (`paw/address.tl`,
`paw/remote.tl`) take less than 0.15 ms a press.

The whole end of the turn (`an event handler`: the reading of the events
from the kernel, the hooks, the handlers), the sum for each press:

| Keys | main | branch |
| --- | ---: | ---: |
| `x` | 1.29 ms | 0.88 ms |
| `dd` | 2.41 ms | 0.54 ms |
| `u` after `dd` | 2.92 ms | 1.62 ms |
| `u` after `x` | 1.53 ms | 0.86 ms |

What took the time, and what changed:

- **The graph of derived data** marked its entries stale in the
  handler. The track list is read by every window of the chord reading:
  one mark made 4 710 entries stale (0.8 ms). Now the handler only notes
  the source. The entries become stale at the next read of a value or in
  the next slice of the job `derived` (`paw/derived.tl`, `before_read`).
- **A read that fails** costs about 65 µs for a missing track and 107 µs
  for a missing clip (mlua makes a traceback), against 0.3 µs for a good
  read of one field. Four handlers read a removed track or device after
  `dd`: `freeze.lua` twice, `groups.tl` and `address.tl`, 0.27 ms each in
  the turn. Now `address.tl` takes the track from the event, `groups.tl`
  stops at `track.removed` (a removed track has no group to read), and
  `freeze.lua` looks for the track in the track list first.
- **A take over a clip** (`transport.lua`) read the whole clip, with its
  notes, for each added clip: 32 clips after `u`. Now it reads the one
  field `armed` of the track first. This is little time, but it was
  garbage for the collector.

Without the timing of `handlers.lua`: `repeat --keys x,u,dd,u --times
20`, budget 5 ms, main and the branch in turns, 10 runs each (80 presses
a run), load average 4.5 to 14.4. Main named a slow event handler (`an
event handler` or `a handler of ...`) in 6 runs of 10, 9 times in all
(5.1 to 9.1 ms). The branch named one in 1 run of 10, once (`an event
handler` 7.2 ms, load average 13.9). The kernel time for each round
shows no measurable difference: 148 to 202 ms (main) and 146 to 200 ms
(branch).

The ends of a turn over 4 ms that are left come from the collector:
the Lua heap goes down in that turn, and the time is in no handler (once
in 160 presses, `events_take` 4.6 ms while the heap went from 38 to
37 MB).

## 2026-11-22: the key of an LSP document on the graph of derived data

The key of a clip's LSP document (`paw.lsp.document.key_of`) is now a
node of `paw.derived` (backlog design `derived.md`, D5). It reads the
clips of the other tracks through one node for each track
(`lsp.track`), not through `clip_list` of every track. A change of a
track's clips makes again only the keys of the documents that it
overlaps. The graph makes the keys of the documents that a server has
again in slices after an edit, before the LSP sync sends them (250 ms
after the last edit).

The project: `bench/profile/project.lua` (64 tracks, 2 000 MIDI clips,
50 000 notes). The script (not in the repository) edits one note of the
last clip of track 40, then times `key_of` of the first clip of track 1.
"After a pause": `paw.flush()`, then the chord reading and the jobs of
`paw.derived` run, as after a pause of the keys. "At once": only
`paw.flush()`. The times are the processor time of the kernel thread, 15
rounds in each run. `main` (the shared binary of 7ae25570) and the branch
ran in turns, 5 pairs, under the measure lock on cores 16 to 23, load
average 5 to 7, measured under external load.

| `key_of` after an edit elsewhere | main | branch |
| --- | ---: | ---: |
| After a pause | 3.5 to 19.0 ms (p50 3.7 to 3.9), 63 `clip_list` calls | 0.09 to 0.43 ms (p50 0.15 to 0.21), 0 `clip_list` calls |
| At once | 5.0 to 19.0 ms (p50 5.7 to 7.5), 64 `clip_list` calls | 2.0 to 5.6 ms (p50 2.6 to 3.0), 2 `clip_list` calls |

"At once", most of the time on the branch is the chord reading, which
`key_of` waits for to find the key at the clip's start. The first
`key_of` of a session makes the 64 track nodes: 7.5 to 8.4 ms on the
branch, 5.0 to 5.7 ms on main (one run of main took 16.3 ms).
`build` reads the clips that overlap the document from the same node:
it does not read `clip_list` of every track again.

## 2026-11-22: the help index in slices that stop

The help index that paw makes at idle is now the job `help` of
`paw.slices`. The build pauses inside the parse of a page (each line and
each row of a table), inside the render (each block and each row of a
table), in the tags of the headings, in the contents page, in the tags of
the code, and in the sort of the tags (a merge sort that pauses). The
text of a rendered line is joined once, not again for each word.

The measure: each slice (one `coroutine.resume` of the build) is timed,
with the collector on, 5 runs each, `--clean --no-plugins`, no project.
"Old" is the runtime of main in the binary, "new" is this branch with
`PAW_RUNTIME`. Load average 5 to 8, not on reserved processors.

| Binary | Allocator | Old: slices over 5 ms | Old: longest | New: slices over 5 ms | New: longest |
| --- | --- | --- | --- | --- | --- |
| dev (7ae25570) | glibc | 34 to 45 of 225 to 272 | 26.5 to 36.9 ms | 9 to 14 of 211 to 279 | 8.6 to 19.4 ms |
| release (main of 19:31) | glibc | 31 to 51 of 232 to 273 | 17.2 to 35.0 ms | 7 to 19 of 234 to 272 | 9.3 to 15.6 ms |
| release (main of 19:31) | mimalloc 3.3.2 (`LD_PRELOAD`) | 14 to 18 of 169 to 188 | 16.2 to 20.6 ms | 2 to 3 of 194 to 213 | 5.7 to 6.9 ms |

The slices that are still long are not in the Lua code. `perf record`
of the samples inside the slices over 6 ms (release, glibc) gives 54 %
in the allocator: `malloc_consolidate` 21 %, `_int_free_chunk` 17 %,
`unlink_chunk` 9 %. glibc merges all its small free blocks when a large
block is asked for, and the collector frees many small blocks. With
mimalloc, the allocator is gone from these samples. One build allocates
214 MB (224 MB before the line text is joined once). With
`GLIBC_TUNABLES=glibc.malloc.mxfast=0`, the new runtime gives 5.8 to
7.0 ms.

The profile scenario `repeat` of `j` on the large project (dev binary,
`--budget 5`, 4 runs, load 6 to 9) names `the job help` once in each
run, at 7.3 to 8.4 ms (old: `a timer (paw/help.tl:1123)` once, 7.1 to
7.6 ms at load 9 to 11). With mimalloc: 5.5 to 8.4 ms.

## 2026-11-22: the search index on the graph of derived data

The records of `paw.grep` and the nodes of clips and notes that
`paw.query` gives are now nodes of `paw.derived` (backlog design
`derived.md`, D3, `runtime/lua/paw/query/tree.tl`). After an edit, a
search makes again the records and the note nodes of the edited clip
only. The project: `bench/profile/project.lua` (64 tracks, 2 000 MIDI
clips, 50 000 notes). The script (not in the repository) edits one note,
calls `paw.flush()`, then times `paw.grep.search("pizz")` (the search of
`:vimgrep /pizz/`). It edits one more note, then times
`paw.query.run("note[pitch>=c6]")`.

The times are the processor time of
the kernel thread, 15 rounds in each run. `main` at 8e996909 and the
branch ran in turns, 5 pairs, under the measure lock on cores 16 to 23.
All values were measured under external load (load average 49 to 59).

| After one note edit | main | branch |
| --- | ---: | ---: |
| `:vimgrep /pizz/` (the search) | 38.1 to 101.3 ms (p50 39.5 to 88.5) | 2.6 to 11.1 ms (p50 3.0 to 5.4) |
| `note[pitch>=c6]` | 94.3 to 231.5 ms (p50 98.4 to 210.1) | 10.2 to 20.1 ms (p50 11.0 to 18.9) |

The first search in a session makes the index: 142 ms on the branch, 59
ms on main (one run). The first query after it takes 8.9 ms, because
the query reads the same nodes. The index keeps 31.7 MB of Lua heap on
the bench project (main keeps 2.3 MB after a search and a query).

The query is also quicker without the index. A test of a field finds how
it reads the field once for each kind of node, the `paw.ex` item of a
node stays in the node, and the loops over the notes use numbers, not
`ipairs`.

## 2026-11-22: a move key in the piano roll

`j` in the piano roll plays the pitch, and the meters then fall for
1.5 s. paw ticks at `paw.opt.fps` (60) for that time: about 89 live
frames for each key, of which 32 change a cell. Before the change, each
tick drew all live parts again: the status line (all components), the
two playheads (3 000 and 4 600 cells) and the meters. `l` in the roll
plays nothing and costs 4 to 10 ms.

The change: a live part has a stamp, a text of what it is drawn from
(the bound value, or what a meter role shows, or the components of the
status line that move by themselves). A live frame keeps the parts whose
stamp did not change, and the whole frame when no stamp changed. The
reads of each frame use `transport_playhead` and `engine_load` (no
table), and `only_live` binds a window only when that changes. After
the change, 54 of the 89 ticks keep the frame, and only the meter that
moved is drawn on the others.

Kernel processor time of one `j` in the roll, the 2 s after the key
(5 presses a run, median of each run), main (964f160c, with the frame budget)
and the branch in turns, 5 pairs, load average 29 to 53, measured
under external load:

| Build | Median of the runs | Smallest | Largest |
| --- | ---: | ---: | ---: |
| main | 80.4 ms | 56.2 ms | 104.3 ms |
| branch | 48.3 ms | 36.1 ms | 54.9 ms |

The branch is lower in each pair (0.46 to 0.69 of main). The `keys`
scenario against the base before the frame budget (cf15cd12), 5 pairs, load 10
to 34: `j in roll` 85.0 ms (68.1 to 117.1) before, 44.2 ms (34.8 to
51.6) after. Against main with the frame budget, at load 6 to 60, the `keys`
scenario shows no measurable difference: 54.5 ms (45.2 to 89.8) and
55.2 ms (30.2 to 61.1).

What was left then, per `j` in the roll (about 45 ms at load 30): about
89 ticks of about 0.25 ms each (the timer, the kernel loop and its system
calls, `only_live`, the stamps), and the whole frame after the key.

### Frames until the meters rest, at the full rate

A played note now keeps the live frames going until the meters that it
lit are at rest (below -60 dB). Before, the frames ended with the poke,
1.5 s after the note, while the meter still showed a level: the meter
falls with a time constant of 0.3 s and needs about 2.1 s. The last
frame then showed a lit cell until the next whole frame.

A rule of 20 frames a second while only meters fall was built and
measured (`j` in the roll 19.0 ms against 51.6 ms on main), then taken
out: the owner keeps `paw.opt.fps` as an upper limit only, and a frame
comes only when something that it shows changed. The cost that is left
is the falling meters at the full rate, and the owner accepts it.

Kernel processor time of one `j` in the roll, the 2 s after the key
(5 presses a run, median of each run), main (da45a4a0) and the branch
in turns, 5 pairs, load average 14 to 23, measured under external load:

| Build | Median of the runs | Smallest | Largest |
| --- | ---: | ---: | ---: |
| main | 53.1 ms | 52.5 ms | 86.4 ms |
| branch | 38.1 ms | 35.9 ms | 48.5 ms |

The branch is lower in each pair. `j` in the arrange view costs 5 to
12 ms, so `j` in the roll stays at 3 to 7 times its cost, and 'drawing
the screen' (budget 5 ms, wall time) still names the whole frame after
`j in roll`: 55 % of that frame is the arrange view above the roll,
which is drawn whole although only the roll changed.

## 2026-11-22: the chord reading on the graph of derived data

The chord reading is now nodes of `paw.derived` (backlog design
`derived.md`, D1): a part for each track and window, groups of 8
tracks, a mix for each window. A mute takes the parts of one track out
of the sums. The project: `bench/profile/project.lua` (64 tracks, 2 000
MIDI clips, 50 000 notes). The scripts (not in the repository) time
`paw.harmony.builtin(0, math.huge)` after one edit and `paw.flush()`,
with the processor time of the kernel thread and the instructions in
user space (`perf_event_open`). `main` at e18bcfc4 and the branch ran in
turns, 15 rounds each, 3 times, under the measure lock on cores 16 to
23. All values were measured under external load (load average 28 to
57).

| Reading after | main | branch |
| --- | ---: | ---: |
| a note edit, processor time | 5.9 to 17.9 ms (p50 6.2 to 15.4) | 2.4 to 5.5 ms (p50 2.8 to 5.5) |
| a note edit and its undo, instructions | 69 to 74 M | 15 to 16 M |
| a mute, processor time | 29.5 to 73.6 ms (p50 31.5 to 62.8) | 15.9 to 19.1 ms (p50 16.7 to 19.1) |
| a mute and an unmute, instructions | 476 to 589 M | 71 to 85 M |
| the whole song from nothing | 343 to 445 ms | 278 to 363 ms |
| Lua heap of the reading | 15.2 MB | 19.1 MB |

The readings are the same: the hash of the chords of the bench script
`bench/profile/harmony.lua` is 309891027 for both. Without the
measure lock and the cores, at load average 44, the branch read a mute
in 7.1 to 8.6 ms and a note edit in 2.3 to 2.5 ms: the cores 16 to 23
had other work.

What the instructions of a mute go to now (35 M of a reading): the
scores of the 256 windows (14 M), the decode of the chords (8 M), the
groups and the mixes (10 M), the keys (4 M). Two causes of slow LuaJIT
code were found and avoided in the reading: a short inner loop (each
exit from its trace costs), and `ipairs` (compat-5.3 replaces it with a
Lua function, `runtime/lua/compat53/module.lua`, for all of paw).

## 2026-11-22: a budget for each callback

`paw.opt.budget_ms` names each callback of the kernel thread that takes
longer than the budget (docs/reference/lua-other.md, "The budget of a
callback"). `bench/profile/run.sh` sets it to 5 ms, and the `keys`
scenario writes the slow callbacks of each key in the field `slow`. The
project: 64 tracks, 2 000 MIDI clips, 50 000 notes. All numbers were
measured under external load. The budget check uses the wall clock, so
under a load average of 50 to 100 each callback looks 2 to 3 times
slower than at a load average of 14.

### The offenders, before the fixes of this branch

`keys`, 4 runs (one at load average 14 to 19, three at 70 to 94). The
times are wall times of one callback.

| Callback | Where | Time | Result |
| --- | --- | --- | --- |
| `the command pick.grep` | `<Space>fg` | 99 ms (load 14), 148 to 315 ms (load 70 to 94) | fixed in this branch: the records come in slices (`paw.grep.reader`, the job `pick`) |
| `the job harmony` | after the start and each edit | 5 to 44 ms a slice, process time p90 8.6 ms | fixed in this branch: `read.decode`, `read.key_path` and the merges of the notes pause |
| `drawing the screen` | each key in the arrange view | 26 to 183 ms (load 70 to 94) | the arrange drawing (row cache, merged since) |
| `drawing the screen` | Enter on a clip, `j` in the piano roll | 370 to 540 ms, 22 to 33 ms | open: kernel time of `j` in the piano roll (77 ms at load 14) |
| `drawing what moves` | `j` in the roll, `dd`, `u` | 5 to 48 ms | open for the roll; the arrange row cache for the arrange view |
| `a timer (paw/help.tl:1123)` | the help index at idle, after the start | 6 to 69 ms | open: the help index at idle |
| `the key h`, `e`, `l`, `p` | typing `:help` | 5 to 11 ms | open: typing on the command line |
| `an event handler`, `a handler of clip.added`, `the key d` | `x`, `dd`, `u` | 5 to 12 ms | the handlers: the handler work (above); `the key d` open |
| `the job pick` | the files walk | 5 to 9 ms | a read of one folder does not pause; under the noise of the load |
| `the request eval` | the driver itself | 5 ms | not paw's |

### After the fixes

The slices of the chord reading, headless, 5 edits and their undo
(remove a clip, undo), process time of each slice (`os.clock`, all
threads), 3 runs, load average 45 to 100:

| | Slices | Median | p90 | Largest |
| --- | ---: | ---: | ---: | ---: |
| Before | 41 to 67 | 2.4 to 3.3 ms | 7.3 to 8.6 ms | 8.6 to 10.3 ms |
| After | 91 to 106 | 2.0 to 2.6 ms | 3.5 to 3.7 ms | 4.7 to 12.0 ms |

The first reading after the project opens still has slices of 15 to
19 ms. This branch did not find which part of it does not pause.

The two pickers that read in slices, main against this branch, 5 pairs
in turns, `repeat` of the picker key and `Esc`, 5 rounds each, load
average 58 to 88:

| Keys | Measure | main | branch |
| --- | --- | ---: | ---: |
| `<Space>fg`, `Esc` | key to first frame (median of each run) | 335 ms (162 to 968) | 35 ms (19 to 77) |
| `<Space>fg`, `Esc` | kernel time for each round | 263 ms (229 to 272) | 244 ms (90 to 297) |
| `<Space>ff`, `Esc` | kernel time for each round | 156 ms (139 to 222) | 178 ms (111 to 214) |

The kernel time shows no measurable difference. A first version filtered
and drew the picker after each slice of 4 ms: the text picker then took
470 to 1 350 ms of kernel time. The picker now filters and draws at most
every 100 ms while it reads.

In 3 runs of `keys` after the fixes (load average 50 to 65),
`the command pick.grep` is gone. `the job harmony` gives 5 to 6 ms a
slice (wall time). The other offenders of the table above stay, with
their tickets.

### The cost of the check

- `paw.limit.timed` around an empty function, 5 rounds of 10^6 calls:
  263 ns (258 to 266) with the budget on, 1 ns with it off. One
  `paw.api.now()` costs 98 ns (97 to 99).
- One key `j` or `k` in the arrange view (the key, the end of the turn and
  a frame) reads the clock 25 times with the budget off and 55 times with
  it on: 15 callbacks, about 4 µs. The key costs about 7 ms of kernel
  time: the check is about 0.06 % of a key.
- `repeat --keys j,k --times 20`, budget 0 and 5 in turns, 5 pairs, load
  average 40 to 57: 61.5 ms (39.1 to 63.9) and 39.9 ms (22.2 to 72.7)
  for each round. No measurable difference: the spread is much larger.

## 2026-11-22: copies of a clip share their compiled events

The sync now compiles the events of a MIDI clip from the clip's start and
keeps them by what they are made from: the runs of notes, the controllers,
the length and the loop. Copies of a clip that share its notes share one
list, and each part in the engine plays it from its own start. An edit of
notes that 100 copies share compiles them one time. `bench/nest.sh`, 8-bar
clips on 10 tracks, the median of the runs' medians over 2 or 3 rounds that
take turns before and after, in ms of processor time, measured under
external load (load average 24 to 44). Raw numbers:
`results/nest-2026-11-22.jsonl`.

| Case | Before | After |
| --- | --- | --- |
| 100 copies of 384 notes, synced the first time | 1.925 (1.919 to 1.932) | 0.095 (0.094 to 0.096) |
| 100 copies of 384 notes, a note of the shared clip edited | 1.886 (1.881 to 1.893) | 0.057 (0.057 to 0.057) |
| The same, the sync alone (the copies made before) | | 0.044 (0.044 to 0.045) |
| The same, each window cut 4 beats into the clip | 1.648 (1.638 to 1.657) | 0.060 (0.059 to 0.061) |
| A note of one plain clip edited, beside the 100 copies | 0.036 (0.035 to 0.036) | 0.025 (0.025 to 0.026) |
| 100 copies of 96 notes, a note of the shared clip edited | 0.191 (0.191 to 0.199) | 0.037 (0.036 to 0.037) |
| The same, the sync alone | | 0.025 (0.025 to 0.025) |
| A note of one plain clip edited, 96 notes | 0.012 (0.012 to 0.013) | 0.011 (0.010 to 0.011) |
| 1 000 copies of 384 notes, a note of the shared clip edited | 19.060 (18.975 to 19.145) | 0.312 (0.299 to 0.326) |

An edit of the shared notes costs 2.3 times a plain edit at 384 notes and
3.4 times at 96, from 52 and 16 times. The sync alone costs 1.8 and 2.3
times a plain edit. What is left is about 0.3 µs for each copy: the copy
made again, its new part in the engine and its event to the frontends. A
cut at the start of a window costs the cut one time, as the copies of one
window share it. The engine keeps one list of events for 1 000 copies (the
test `an_edit_of_notes_that_copies_share_compiles_them_once`). A render of
copies, loops and cut clips is the same to the bit before and after.

## 2026-11-22: the engine rests when stopped and silent

When the song is stopped and nothing sounds, the whole engine rests: after
8 quiet blocks, a callback writes silence and returns (see
`docs/reference/engine.md`, "The engine at rest"). Before, each block still
cleared, added and measured the buffers of every track, while every device
slept.

`bench/profile/run.sh idle --secs 30 --perf 30` on the profile project (64
synth tracks, 2 000 clips), main at fb9882b against the engine at rest, 5 interleaved
pairs. Measured under external load (load average 44 to 83, with the Lua
suite running on the same machine). The raw numbers are in
`results/rest-2026-11-22.jsonl`. The thread is the audio thread of the null
backend.

| Idle for 30 s, audio thread | main: median (range) | at rest: median (range) |
| --- | ---: | ---: |
| Instructions per second | 38.17 M (38.14 to 38.18 M) | 0.1096 M (0.1096 to 0.1096 M) |
| Cycles per second | 42.5 M (40.6 to 42.6 M) | 2.76 M (2.62 to 2.86 M) |
| Percent of a core | 1.86 (1.81 to 1.90) | 0.38 (0.36 to 0.39) |

The instructions of the audio thread fall by 99.7 %. They do not change
with the load. The thread of the null backend still wakes for each
callback, so the processor time falls less than the instructions.

## 2026-11-21: paw in the terminal, profiled

A profile of the kernel and the terminal frontend, with the tools that
[profile.md](profile.md) names. The project: 64 tracks with a synth each, 2 000
MIDI clips and 50 000 notes, in a 187×56 terminal, `--audio null`. All
numbers were measured under external load (load average 2 to 28): a range
is the spread of the runs. The time of a key is the processor time of the
kernel's main thread.

| Scenario | Result |
| --- | --- |
| Start without a project | first frame 1 035 ms (1 032 to 1 037) before, 35 ms (33 to 47) after: the first frame is drawn before the kernel waits |
| Start with the large project | first frame 113 ms; resident memory 88 MB; Lua heap 47 MB |
| Idle for 30 s | kernel 0 %, no frames; the audio thread of the null backend 1.8 % of a core |
| Idle with an armed track on a steady input | kernel 6.7 %, for 0.07 frames per second sent to the terminal |
| Playing | kernel 6.7 to 9 %, audio 16 to 18 %; 58.5 frames per second, 117 bytes per frame (largest 2.1 kB), 15 kB/s |
| Recording | kernel 7.9 % |
| Moves (`j k w b h l`, `<C-d>`, `<C-u>`) | 7 to 12 ms of kernel time, 7 to 11 ms to the frame |
| `G`, `gg` | 11 to 55 ms, 31 to 33 kB per frame |
| An edit and its undo (`x`, `u`) | 1 450 ms (1 317 to 2 585) before, 693 ms (663 to 696) after: the chord reading is 2.1 times faster, with the same readings |
| Open the piano roll | 28 to 47 ms |
| `<leader>fg` | 74 to 86 ms |
| `:help` | 6 to 9 ms |
| 10 minutes of editing and playing | resident memory 121 to 128 MB, flat after the first minute: no leak |
| Allocations while playing | about 1 400 per frame |

What is left, in order of what the user feels:

1. Each edit reads the chords of the whole song again. Even after the fix
   it costs about 0.6 s on this project, and the next key waits for it.
   Without it, an edit costs 35 to 90 ms.

   After: the reading keeps the notes of each clip by its stamp, and reads
   again only the windows and bars where the notes changed. A change that
   leaves the notes as they are (a volume, a device) reads nothing. The
   work goes in slices of 4 ms, and the views show the reading from before
   until the new one is complete. Measured under external load (load
   average 6 to 22), old and new build in turns, 5 pairs, kernel time per
   round:

   | Keys | Before | After |
   | --- | ---: | ---: |
   | `x`, `u` | 989 ms (760 to 1 399) | 87 ms (81 to 223) |
   | `<leader>mm`, `+`, `-`, `<leader>mm` | 821 ms (804 to 836) | 97 ms (96 to 103) |
   | `dd`, `u` | 756 ms (742 to 764) | 235 ms (232 to 239) |

   With the reading off, `x` and `u` cost 81 to 86 ms a round, and `dd` and
   `u` 234 to 250 ms. That is no measurable difference: the rest of `dd`
   is not the reading. The reading itself after one edit, 10 rounds:

   - a clip removed: 7.2 ms (6.5 to 8.6), its undo 8.1 ms
   - a note added: 8.3 ms
   - a volume: 0.4 ms (nothing read)
   - a track muted: 38 ms (its clips cover the whole song).

   Before, each of these took 430 to 510 ms. To read the whole
   project, when paw opens it, takes 145 ms (128 to 165). The readings are
   the same. The hash of the chords and keys is the same as the old build's
   on this project and its edits. It is also the same on 300 random note
   sets with 6 random edits each, 2 100 readings in all. The notes of 100
   sets start on sixteenths, and of 200 sets on ticks of 1/960 beat. A
   reading after an edit is the same as a reading of all the notes.

   `dd` and `u` after that (2026-11-22). `dd` on a track deletes the track
   and its devices. The event `device.removed` named no track. The reading
   took that as "look at every track", and it listed and hashed all 2 000
   clips. The event now names the track. After each edit, the arrange view
   made the small piano roll of each clip again. The problems list asked
   each device again when one device came or went. Both now keep what did
   not change. The reading of the bars now pauses as the other parts of a
   pass do. Measured under external load (load average 10 to 13): the old
   and the new build in turns, 5 pairs of 10 rounds of `dd` and `u`. The
   driver waits 300 ms after each key. Kernel time per round, median
   (range):

   | Part | Before | After |
   | --- | ---: | ---: |
   | All | 274 ms (272 to 296) | 192 ms (190 to 198) |
   | The chord reading | 151 ms (150 to 166) | 93 ms (91 to 94) |
   | Its longest slice | 18 ms (11 to 29) | 7 ms (7 to 13) |
   | Full frames | 76 ms (72 to 79) | 58 ms (54 to 63) |

   The time from each key to its first frame, in 5 pairs of `drive.py
   repeat` (load average 15 to 20): `dd` took 31 ms (24 to 35) before. It
   took 15 ms (12 to 23) after. `u` took 32 ms (28 to 33) before and 13 ms (11 to 15) after.
   Each key is now well under 100 ms. What is left is the reading itself.
   The clips of a track cover the whole song, so a change to the track
   changes every window. To weigh the notes of each window again costs
   about 45 ms for each key on this project. It runs in slices after the
   frame, and a key does not wait for it.
2. A full frame costs 7 to 12 ms: the clip list is made again as JSON on each
   frame.

   After (2026-11-22): the notes of a clip keep their stamp, a hash of the
   notes. The kernel makes it again only after a change to the notes, not
   on each call. The clip list goes into Lua from a typed record, with no
   JSON between, and leaves out the fields that a clip does not have. The
   clip lists of the 64 tracks cost 7.7 ms before and 3.1 ms after. Each
   number is from one run of 200 calls. The draw of the arrange view now
   makes the most of the cost of a frame. A full frame after `j` or `k`,
   headless, 200 frames, in turns, 5 pairs:

   | Measure | Before | After |
   | --- | ---: | ---: |
   | Instructions (millions) | 73 (72 to 75) | 59 (58 to 59) |
   | Kernel time, measured under external load (load average 39 to 55) | 14.5 ms (14.0 to 27.8) | 13.5 ms (10.3 to 15.5) |

   The kernel still looks for the file of each audio clip on each call, to
   say if the clip is offline. The profile project has no audio clips, so
   this cost is not in these numbers. A watch of file events does not see
   when a folder above the file gets a new name. So it can say that a
   missing file is there, and the kernel does not use one.

   After that (2026-11-22): most of a frame was the drawing of
   the clips' roles in Lua, every clip of every row on each frame. Now a
   row of the timeline that the cursor is not on keeps its cells. On the
   next frame it puts them back when its clips (every field) and what the
   row is drawn from are the same. The layers of other modules are painted
   over them again. A change of a highlight forgets the kept cells.

   In a terminal a mark makes no data for a window and no closure. The view
   asks the kernel only for the clips that it shows. The status line
   finds the key for `:messages` without a sort of every mapping. The
   kernel looks at the file of a clip at most once a second, and again at
   once after each edit, undo, load, save or file event, so a file whose
   folder gets a new name shows as offline within a second.

   A full frame after a key, headless (`profile/frame.lua`, 100 keys and
   frames), the old and the new build in turns, 2 pairs, load average 30
   to 37:

   | Instructions of a key and its frame (millions) | Before | After |
   | --- | ---: | ---: |
   | `j`, `k` | 53.0 and 53.5 | 25.2 and 26.5 |
   | `<C-d>`, `<C-u>` | 52.6 and 53.9 | 26.5 and 27.5 |

   The kernel's processor time of each key in a terminal (`drive.py keys`,
   5 times each key, with the chord reading done before), the old and the
   new build in turns, 3 pairs, measured under external load (load average
   19 to 47). Median of the pairs (range):

   | Key | Before | After |
   | --- | ---: | ---: |
   | `j` | 20.3 ms (19.6 to 34.1) | 17.4 ms (16.1 to 17.4) |
   | `k` | 6.7 ms (6.6 to 24.6) | 5.0 ms (4.4 to 5.4) |
   | `<C-d>` | 6.6 ms (6.6 to 8.7) | 4.8 ms (3.8 to 11.3) |
   | `<C-u>` | 6.9 ms (6.6 to 7.9) | 4.6 ms (4.5 to 10.7) |
   | `w`, `b`, `l`, `h` | 7.4 to 10.6 ms | 4.8 to 5.3 ms |

   `j` is the first key that the scenario measures. Its first frame comes
   after 5 ms. The rest of its time comes after the frame, in the old
   build too, and it is not the drawing. It stays when the keys are
   pressed 20 times first.

   The chord reading after a mute of a track whose clips cover the whole
   song reads every window again: each window holds notes of that track.
   Its weighing now keeps its work tables between windows: a mute and an
   unmute cost 325 million instructions before and 258 million after
   (2 pairs), with the same readings. To read fewer windows needs a part
   of each window for each track, which the planned dependency graph of derived data
   takes up.
3. The live ticker drew 60 frames per second when an armed input changed
   nothing on the screen. Fixed: after 20 frames in a row that change no
   cell, it slows to 8 per second, and a poke ends. Idle-armed kernel
   thread: 7.2% before, 5.0% after (one reading each, on a loaded machine).
4. The files picker walked the whole folder tree (up to 10 s). Fixed: it
   reads in slices of 8 ms, with limits and skipped folders. A round of
   `<leader>ff` and `<Esc>` on 9 000 files: 20.5 ms of kernel time
   before, 3.7 ms after (one reading, on a loaded machine).
5. About 1 400 allocations per frame while playing, half of them for
   strings passed from Lua.

   After (2026-11-22): the screen API takes the number of a highlight
   group (`paw.api.hl_id`), and `buf:text` asks for it once for each name.
   The kernel copies text from the Lua stack into a buffer on its own
   stack, with no shared counter for each string. `transport_get` and
   `engine_get` make their tables from typed structs, with no JSON
   between. A frame reads the transport once (`paw.ui.transport()`). The
   grid keeps the buffers of the live parts, and the live meters keep
   their tables. `layout.find` and `find_id` make no list of the windows.
   The status line keeps a segment and its width while its text stays.
   The playhead keeps its spans while it stays in a column.

   `heaptrack` on `bench/profile/run.sh play` with the large project,
   runs of 10 s and 30 s, `heaptrack_print -f <30 s> -d <10 s>`: the
   allocations of the steady state, divided by the frames between the two
   runs. Old and new build in turns, 3 pairs. The kernel's instructions
   per frame, from `compare.py ... 5 play --secs 15 --perf 10`, 5 pairs.
   Measured under external load (load average 40 to 59):

   | Measure | Before | After |
   | --- | ---: | ---: |
   | Allocations per frame | 1 467 (1 449 to 1 487) | 111 (93 to 129) |
   | Kernel instructions per frame | 3.22 M (3.19 to 3.36 M) | 2.33 M (2.30 to 2.36 M) |
   | Kernel processor time | 8.4 % (8.3 to 9.0) | 6.2 % (5.9 to 6.3) |

   Of the allocations that are left, about 8 a frame are in Rust. The
   rest are the Lua tables and strings of the status line's components
   (the time, the transport) and of the transport table. The count after
   changes more from run to run than the count before: LuaJIT allocates
   too when it compiles a trace again.

## Since then: several threads, and one note at a time

The two largest weaknesses below were taken up after these results were
written. The engine now processes tracks that do not feed each other on a
pool of worker threads (one thread per core by default; renders are
bit-identical whatever the number), and `paw.api` has calls for one note
(`clip_note_set`, `clip_note_add`, `clip_note_remove`, `clip_notes_edit`),
which the piano roll and the graphical frontend use. Measured on the same
machine, under load from other jobs (load average 5 to 15), each figure the
median of three interleaved runs; "before" is the build these results were
taken from. As everywhere here, the synth rows compare synths more than
engines.

| Render (32 s of audio) | 1 thread | 12 threads | Tracktion, 24 threads |
| --- | ---: | ---: | ---: |
| 100 audio tracks | 1.59 s | 0.44 s | 2.04 s |
| 500 audio tracks + delay + automation | 8.6 s | 2.5 s | 9.5 s |
| 100 synth tracks + delay | 6.7 s | 1.15 s | 7.9 s |
| 500 synth tracks + delay + automation | 34.0 s | 5.5 s | 36.2 s |

On one thread the times are what they were before the change, within the
noise of this machine (interleaved with the old build: 1.77 against 1.79 s
for 100 audio tracks, 7.1 against 7.4 s for 500).

| Playing live (null backend), worst block | 1 thread | 4 threads | 12 threads | Budget |
| --- | ---: | ---: | ---: | ---: |
| 100 synth tracks, 128 frames | 2.08 ms | 0.79 ms | 0.49 ms | 2.67 ms |
| 500 audio tracks + delay, 256 frames | 5.29 ms | 1.95 ms | 1.53 ms | 5.33 ms |
| 500 synth tracks + delay, 512 frames | 26.3 ms | 7.9 ms | 3.8 ms | 10.7 ms |

| Editing notes, each edit an undo step and a sync | Before | Now | Tracktion |
| --- | ---: | ---: | ---: |
| 1000 note moves in a 1000-note clip | 700 ms | 33 ms | 1.8 ms |
| the same without the sync to the engine | 870 ms | 12.6 ms | |
| 1000 note deletes | 360 ms | 18 ms | |
| 5000 note moves in a 5000-note clip | 17.3 s | 0.54 s | |

What that leaves: a note edit still costs in proportion to the clip (33 µs at
1000 notes, 108 µs at 5000), because the clip is copied for undo and compiled
again for the engine; Tracktion's 2 µs per note leaves out its graph rebuild.
With several threads the adding-up of what tracks send on is still done on
one, which is what limits 100 plain audio tracks to 3.6 times faster on 12
threads. The audio callback of the PipeWire backend was found to run without
real-time priority on this machine (the workers match it, so they do not
either); the path where a real-time callback's workers become real-time is
covered by a test, not by a real device.

## 2026-11-19: devices that sleep, and threads only when needed

These are three changes to the engine. I measured them on the same machine,
with load from other jobs (load average 6 to 50). The raw numbers are in
`results/sleep-2026-11-19.jsonl`. The run before the changes, on the same
day, is `results/remeasure-2026-11-19.jsonl`.

- **Devices at rest sleep.** The engine does not run a device when its
  input is silent and its tail is below -120 dB (see
  `docs/reference/engine.md`, "Devices at rest"). A render is the same to
  the bit with sleep on and off. Unit tests for each effect, an engine test
  with long silences and `fuzz.lua` examine this.
- **The pool.** Live, the engine uses the worker threads only when one
  thread needs a quarter of the time of a block. Between blocks, the
  worker threads sleep. A render shares a group of tracks when the group
  has 60 µs of work.
- **The reverb and the LFOs.** The reverb calculates its drift each 32
  frames. Before, it calculated one sine for each line and each sample. The
  LFOs use a sine series.

The older benchmark did not measure the cost while stopped. This table
shows `paw --headless` with the demo song (`examples/demo-song.lua`),
`--audio null`, on 8 cores. Each value is the percent of one core, from 5
interleaved rounds of 10 s.

| Demo song | Before: median (range) | After: median (range) |
| --- | ---: | ---: |
| Stopped | 5.7 (4.9 to 6.0) | 1.1 (0.9 to 1.6) |
| Playing | 6.1 (5.8 to 6.3) | 3.4 (3.1 to 6.5) ¹ |

After a merge with main at e0ae197, which has the memory changes of the
same day, the same measurement against that build gave these values:
stopped 4.6 (3.8 to 5.2) before and 1.0 (0.8 to 1.9) after; playing 5.5
(5.2 to 6.3) before and 3.3 (2.6 to 3.6) after.

¹ The 6.5 % run was at load 50. There, the measured work was more than a
quarter of the block, and the worker threads helped (2.3 % of the 6.5 %).

These counters do not change with the load. In 10 s while stopped, devices
ran 70 blocks and slept through 5553 blocks. In 10 s while playing, devices
ran 4736 blocks and slept through 892 blocks. The engine shared no group of
tracks between threads. Before the change, the 3 worker threads used 1.5 to
2.6 % of a core while stopped and while playing. Most of that time they
waited in a loop between blocks.

For one instance (`devices.lua`, 16 audio tracks, one thread, one run), the
reverb went from 1.12 to 0.61 % of a core. The other effects did not change
more than the noise.

Renders on 12 threads, median of 3, in ms for 32 s of audio:

| Render | Before | After |
| --- | ---: | ---: |
| 1 audio track, delay, automation | 88 | 48 |
| 1 synth track | 124 | 99 |
| 10 synth tracks, delay, automation | 191 | 150 |
| 100 audio tracks | 504 | 297 |
| 100 synth tracks, delay, automation | 1340 | 1056 |
| 500 audio tracks, delay, automation | 3503 | 2760 |
| 500 synth tracks, delay, automation | 7006 | 5273 |

Before, the renders of one track were slower on 12 threads than in the
older results (57 ms and 87 ms). A profile showed no work on the worker
threads, so the pool was not the cause. Now they are as fast as before or
faster. The renders of 1 and 10 audio tracks without effects did not change
more than the noise. They went from 40 ms to 43 ms, and from 96 ms to 113 ms.

Live, with the null backend, the p99 time of a block changed as follows.
For 500 audio tracks at 256 frames, it went from 1.72 ms to 1.02 ms. For 100
synth tracks at 128 frames, it went from 0.43 ms to 0.26 ms. For 10 synth
tracks at 128 frames, it went from 0.18 ms to 0.26 ms, with a budget of
2.67 ms. These tracks now play on one thread. This uses less processor
time, but each block takes longer.

## 2026-11-19: edits, memory and startup again

A new run of the matrix (`results/remeasure-2026-11-19.jsonl`) showed a faster engine but slower work around it. 1000 clip moves
took 435 ms (before: 50 ms). 100 tracks took 86 MB (before: 37 MB). A start
took 62 ms (before: 15 ms). And `edit.lua clips 5000` stopped with "out of
Lua stack". The causes, and the changes:

- **The crash.** Each edit started a timer for `address.changed` and then
  sent the event at once, so the timer stayed. A script that `-l` runs does
  not let timers run. Each timer kept its function in a slot of a stack with
  room for about 8000 values. Now the event stops its timer. Timers keep
  their functions in the Lua registry, which has no such limit.
- **Edits.** The handlers of each edit (learn, freeze, groups) asked for the
  whole track, which lists every clip. The `address` module asked for the
  whole project, and the length of the project looks at every clip. Now
  `paw.api.track_get(id, key)` and `paw.api.project_get(key)` give one entry,
  and `track.volume` and `paw.project.edits` use them. The undo history, the
  names of notes, the change events and the clip cache of the engine
  compared two states through a hash map of every clip. Now they compare by
  place first. A project without audio does not look through its history
  for audio files.
- **Memory.** Each device had a line of 128 kB that holds back its dry
  signal. Each block wrote it, but most devices have no latency. Each delay
  wrote silence into its lines of 2 MB while the engine ran. So the memory
  of a project grew with the time that the engine ran. Now a device without
  latency does not write its line, and the line takes no memory until a
  write. A delay that hears only silence does not write its lines.
- **Startup.** The parse of 2.4 MB of Lua took most of the time. Now the
  build compiles the runtime to LuaJIT bytecode, which loads about 15 times
  faster.

The table compares the commit before (`main` at 0694042) and after. The runs
are interleaved, on the same eight cores, under load from other jobs (load
average 6 to 9). Each figure is the median of five runs (three for memory),
with the smallest and largest in brackets.

| | Before | After | Tracktion |
| --- | ---: | ---: | ---: |
| 1000 clip adds, each an undo step and a sync | 365 ms (355 to 392) | 100 ms (85 to 119) | 16 ms |
| 1000 clip moves | 563 ms (511 to 578) | 163 ms (130 to 177) | 2.3 ms |
| 1000 clip deletes | 434 ms (412 to 535) | 166 ms (108 to 184) | 2.1 ms |
| 998 undo steps | 324 ms (292 to 393) | 124 ms (96 to 153) | 25 ms |
| 998 redo steps | 317 ms (273 to 379) | 120 ms (83 to 133) | 25 ms |
| 5000 clips: adds, moves | stops | 1.45 s, 2.67 s | 0.10 s, 0.02 s |
| 1000 note moves in a clip of 1000 notes | 228 ms (164 to 233) | 181 ms (156 to 192) | 1.8 ms |
| Memory, 100 tracks of 8 clips, after 1000 undo steps | 99 MB | 44 MB | 113 MB |
| Memory, 500 tracks of 8 clips, after 1000 undo steps | 629 MB | 94 MB | 499 MB |
| Start and quit, no plugins | 74.8 ms (74.0 to 85.5) | 43.0 ms (41.6 to 43.3) | 115 ms |

The note moves show no measurable difference. The first build in the history
of the repository is 43aad5d. In interleaved runs under the same load, it
did 1000 clip moves in 154 ms (128 to 192). That is level with this build. The
50 ms in the first table came from a machine without load.

What is left: an edit still costs in proportion to the clips of its track.
The undo step copies the list of clips of the track, and the engine gets all
the clips of the track again. A list that shares its parts (a persistent
vector) can make that cost independent of the size.

## 2026-11-19: an edit costs what it changes

These changes make the cost of a clip edit or a note edit independent of
the size of the track and of the clip:

- **Clips in runs.** A track keeps its clips (and its cue clips) in runs of
  about 32. The states of the undo history share the runs. An edit
  copies one run, not the list of all the clips. Two states of a track
  compare run by run, so the undo step, the change events and the sync
  look only at the runs that changed.
- **A clip found by its last place.** Before, the search for a clip by its
  id looked at every clip of the project.
- **Parts in the engine.** The engine keeps one part for each clip. For a
  long MIDI clip, it keeps one part for the controllers and one part for
  each group of at least 256 notes. An edit sends only the parts that
  changed, and the main thread compiles only those parts. The audio thread
  puts the parts in and takes them out without an allocation. It plays the
  parts in the same order as the one sorted list of before, so a render is
  the same to the bit as a render of `main` (the demo song, the demo song
  after edits, and the bench projects).
- **The undo history.** When the history drops a state, the next state
  gets the sum of the two weights. The history weighs a heavy state again
  only after 32 such steps. Before, it weighed the next state against the
  first state at each step past the limit of 1000 steps, and this cost as
  much as the whole project.

The table compares `main` at 13186c0 with the branch. The runs are
interleaved, on cores 16 to 23, under load from other jobs (load average 3
to 21, median 6). Each value is the median of five runs, with the smallest and the
largest in brackets. The values of Tracktion are from the section before.
Its edit calls do not sync an engine. Compare them with the values without
the sync (`nosync`).

| | `main` | Branch | Tracktion |
| --- | ---: | ---: | ---: |
| 1000 clip adds, each an undo step and a sync | 116 ms (89 to 119) | 92 ms (49 to 93) | 16 ms |
| 1000 clip moves | 151 ms (135 to 158) | 87 ms (49 to 89) | 2.3 ms |
| 1000 clip moves without the sync | 28.4 ms (28.3 to 28.9) | 4.5 ms (4.4 to 4.8) | 2.3 ms |
| 1000 clip deletes without the sync | 22.5 ms (22.4 to 22.7) | 6.9 ms (6.8 to 7.2) | 2.1 ms |
| 998 undo steps without the sync | 26.5 ms (26.4 to 26.6) | 8.3 ms (8.1 to 8.4) | 25 ms |
| 5000 clip adds | 1.68 s (1.47 to 1.70) | 0.70 s (0.32 to 0.75) | 0.10 s |
| 5000 clip moves | 2.64 s (2.48 to 2.71) | 0.60 s (0.48 to 0.88) | 0.02 s |
| 5000 clip moves without the sync | 824 ms (815 to 831) | 44 ms (42 to 46) | 20 ms |
| 5000 note moves in a clip of 5000 notes | 3.43 s (3.03 to 11.3) | 0.71 s (0.52 to 0.72) | |
| 5000 note moves without the sync | 1.86 s (1.85 to 1.87) | 0.10 s (0.10 to 0.10) | |
| 1000 note moves in a clip of 1000 notes | 147 ms (123 to 189) | 102 ms (51 to 179) | 1.8 ms |

Without the sync, a clip move costs 4.5 µs on a track of 1000 clips. On a
track of 5000 clips, it costs 8.7 µs. Before, it cost 28 µs and 165 µs.
With the sync, most of the time of a move is in the Lua handlers of the
change events and in the collection of Lua garbage. The sync and the engine
message take about 12 µs for each move, on tracks of 1000 and of 5000
clips (runs without the lock, so only a rough value).

Memory, in one run each:

- A one-note edit in a clip of 200,000 notes (`memory.lua bigclip`) added
  217 kB of resident memory for each undo step before, and 0.4 kB now. The
  undo history counts about 28 kB for each step in both builds.
- 5000 clip edits and their undo steps: 113 MB before, 59 MB now.
- 100 and 500 tracks of 8 clips after 1000 undo steps: 45 and 96 MB before,
  45 and 97 MB now. That is no measurable difference.

What is worse: on a track of 100 clips, 300 undo steps without the sync
take 3.2 ms in place of 2.0 ms. And 100 clip deletes take 5.9 ms in place
of 2.3 ms. The runs and the parts cost a little more than the plain list
when a track has few clips. With 1000 notes in one clip, the resident
memory after the run is 74 MB in place of 57 MB.

What is left:

- The Lua handlers of the change events take 15 to 50 µs for each edit.
- Each edit of a clip looks at all its notes for notes without an id.
- `clip_add_notes` sends the whole list of notes again.

## Machine and method

- AMD Ryzen AI 9 HX 370 (12 cores, 24 threads), 32 GB, NixOS, Linux 7.3.1
  PREEMPT_RT. rustc 1.95.0 (release, thin LTO, baseline x86-64); Tracktion with
  GCC 15.3, `-O3` (JUCE's recommended release flags), no `-march`, no LTO.
- **The machine was shared.** Other builds ran during most measurements (load
  average 4–40 on 24 threads). Each configuration ran 3 times and the tables
  show the median; before/after comparisons of my own changes use the minimum
  of 3–5 interleaved runs. Expect ±15% noise in single numbers; differences
  smaller than that are not findings.
- Both engines: 48 kHz, 512-frame blocks for offline renders, 120 BPM, 4/4,
  24-bit WAV output, the same 2 s 48 kHz WAV for audio clips, the same notes
  (per bar a 4-note chord and 8 eighth notes) for MIDI.
- **Threads.** This DAW rendered and played on one thread when these were
  measured (see the section above for what it does now). Tracktion is run
  twice: limited to the calling thread (`×1`, `getNumberOfCPUsToUseForAudio`
  = 1) and with all 24 (`×N`). For renders Tracktion's default is N.
- **What each engine does differs:**
  - *Synths.* MIDI goes through each engine's own synth: this DAW's `synth`
    (one band-limited oscillator, a state-variable low-pass, an ADSR, 16
    voices) and Tracktion's 4OSC set as close as it goes (one saw oscillator,
    a low-pass, 16 voices, effects off). 4OSC still does far more per voice
    (four oscillator slots, two filters' worth of envelopes, LFOs, the
    modulation matrix), so **the MIDI rows compare synths more than engines**.
  - *Effects.* `delay` against Tracktion's `DelayPlugin`, both stereo
    feedback delays. Each Tracktion track also carries its default
    volume/pan and level meter plugins; this DAW's fader is built in.
  - *Render overhead.* Tracktion reads audio files through a background
    reader and writes through a threaded writer; its render waits for the
    reader, which gives it a floor of about 0.5 s on any render and blocks
    of ~10 ms in its per-block numbers (`block_p99` ≈ 10 ms at every size).
    This DAW decodes files into memory when a clip is added and writes the
    file on the render thread (its `render_ms` includes the writing).
  - *Editing.* Every DAW edit here is a "turn" as the UI makes it: the
    change, the sync to the engine, the change events, an undo step.
    Tracktion's edit calls change its model and undo history only; it
    rebuilds its playback graph later on its message loop, which the driver
    never runs. The "without the sync" tables measure the DAW the same way.
  - *Real time.* The DAW's per-callback times come from its engine's own
    histogram while the null backend calls it on a real-time clock (a plain,
    not real-time-priority, thread). Tracktion's come from timing
    `HostedAudioDeviceInterface::processBlock` called back to back. Neither is
    a real audio device.
- **Tracktion limits.** By default an edit holds at most 400 tracks and a
  track 1500 clips, and `Edit::ensureNumberOfAudioTracks` loops forever when
  it reaches the track limit (it hung the first 400-track runs). The driver
  raises both limits through `EngineBehaviour::getEditLimits`.
- Not run: 500 tracks of 4OSC on one Tracktion thread (over 4 minutes per
  run); plugin hosting on either side (the DAW's CLAP/LV2/VST3 paths are
  covered by its test suite, not benchmarked).

## Headline

| Workload | This DAW (1 thread) | Tracktion ×1 | Tracktion ×N |
| --- | ---: | ---: | ---: |
| Render 100 audio tracks, 32 s | 1.72 s | 3.61 s | 2.35 s |
| Render 500 audio tracks + delay + automation | 9.8 s | 34.3 s | 9.6 s |
| Render 100 synth tracks (different synths) | 6.2 s | 45.4 s | 7.1 s |
| Worst block, 100 synth tracks at 128 frames (budget 2.67 ms) | 1.68 ms | 14.1 ms | 5.7 ms |
| Save / load 500 tracks × 8 clips | 16 / 64 ms | 296 / 520 ms | |
| Resident memory, 500 tracks × 8 clips | 170 MB | 499 MB | |
| Start (no plugins) | 15 ms | 117 ms | |
| 1000 clip moves, each an undo step (DAW without / with the engine sync) | 12 / 50 ms | 3.5 ms | |
| 1000 note moves in a 1000-note clip (DAW, with or without the sync) | 0.6–0.9 s | 1.8 ms | |

Where it wins: rendering audio clips (single-threaded, it beats Tracktion
on 24 threads up to 100 tracks and ties at 500 with effects), small renders
(no 0.5 s floor), saving, loading, memory,
start-up. Where it loses: editing, by 3–15× for clips and by two to three
orders of magnitude for single notes (see "What remains").


## Before and after my changes

Original build (aff0862) against the final one, same machine, minimum of 3–5
interleaved runs unless noted. Renders are bit-identical before and after for
every performance change (checked by hashing renders of all four synth waves,
the drums and delays).

| Change | Workload | Before | After |
| --- | --- | ---: | ---: |
| Delay wraps without `%` | 500 audio tracks + delay + automation, render | 8.53 s | 7.03 s |
| Synth/drums phase without libm; wave chosen per voice (+ delay) | 100 synth tracks + delay + automation, render | 6.58 s | 5.63 s |
| Synth/drums alone | all four waves + drums, engine time | 226 ms | 185 ms |
| Delay alone | the same with a delay per synth | 199 ms | 132 ms |
| Notes read and written directly | 1000 note moves in a 1000-note clip | 1.25 s | 0.60 s |
| Per-clip event cache, pointer diff | sync per clip move, 1000 clips × 12 notes on a track | 167 µs | 139 µs |
| LV2 scan cached | start with LSP Plugins + Surge XT, warm cache | 1180 ms | 15 ms |
| `routing_of`/solo in one pass | one volume change, 1000-track project | 0.44 ms | 0.55 ms ¹ |
| Denormals off for null backend and renders | 20 synths into delays, 120 s tail | 1.51 s | 1.50 s ² |

¹ No gain: the quadratic parts were not what dominated at 1000 tracks (the
per-sync hash maps over every track and device are), and the final tree,
which includes the merged work (undo tree, autosave, latency compensation,
MIDI 2.0), is about 20% slower than the original here. I did not find out
which part.
² With the built-in devices a signal spends very little time in the denormal
range; the change makes the null backend and renders behave like the cpal
callback, which already set the flag, and matters for plugins' tails.

**The merge.** Comparing `premerge.jsonl` and `final.jsonl`: audio renders
without effects 1518 → 1723 ms (100 tracks) and 5977 → 6119 ms (500 tracks),
per-block p99 0.72 ms at 100 tracks in both, real-time 500-track p50 2.05 ms in
both. Those are within the noise, so the per-route delay lines and fade checks
added on the audio path made no measurable difference. Rows with the delay
are faster after (13.1 → 9.8 s at 500 tracks) because of the delay change
above.

## Defects found and fixed

Each has a test in the Lua suite (then `tests/suite.lua`) or a Rust test that fails on the code before the fix (checked by building the original commit in a scratch copy), unless marked as a performance change, which has before/after numbers instead.

| # | Defect | Found by | Fix |
|---|---|---|---|
| 1 | Saving and loading changed numbers in the last bit (serde_json's default float parser is not exact) | fuzzer, save/load invariant | `float_roundtrip` feature; suite: "saving and loading keeps every number exactly" |
| 2 | NaN and infinity accepted by `track_add` (volume, pan), `device_set_param`, note start/length, clip gain/offset, live and injected note velocities. Saved as `null`, so the project file no longer loaded; NaN velocities and parameters made the audio NaN (meters read 0, because `max` skips NaN) | fuzzer, abuse cases | refused with a message; suite: "numbers that are not finite are refused" |
| 3 | A note with a negative or zero length played its note-off before its note-on: a stuck note. Pitches up to 255 were accepted | abuse cases, review | refused |
| 4 | Project files were not checked: a tempo of 0 made every render run forever (hang, disk filling); negative tempo, a time signature of 0, negative clip lengths, duplicate ids, a track routed into itself, routing loops, out-of-range volumes all loaded | abuse cases | `Project::validate` on load, the file is refused whole with the reason; suite: "a damaged project file is refused whole" |
| 5 | `render` with a huge tail or end ran forever; past 4 GiB a WAV header overflows. A sample rate of 0 panicked inside device set-up (mlua turned it into an error); 4 GHz aborted the process (out of memory); an engine buffer of 1e9 frames hung | abuse cases | sample rates 8000–384000, buffers 16–16384, renders that fit a WAV file; suite: "renders and engines refuse sizes and rates they cannot do" |
| 6 | Loops through sends were accepted (`would_cycle` only followed outputs); the engine then silently dropped one side | review, then test | `would_cycle` follows outputs and sends; suite: "sends cannot make a loop either" |
| 7 | A refused edit still made an (empty) undo step and marked the project modified: the next undo did nothing | review, then test | only successful edits count; suite: "a refused edit leaves no undo step behind" |
| 8 | A track added past the engine's 1024-track limit never got a slot, even after tracks were removed; adding a device to it failed with "could not load `synth`" | abuse cases | a slot-less track is built when there is room, and the schedule rebuilt; suite: "a track the engine had no room for sounds once there is room" |
| 9 | Replacing one track's clips while playing (any clip edit) sent all-notes-off and re-triggered every held note on every track: every edit made every sustained note in the project swell | review, then test | the flush and chase are per track; `crates/paw-engine/tests/it/clips.rs` |
| 10 | An audio clip gain of 1e9 dB (finite, so accepted) rendered as infinity; a send level of 1e9 was saved into a file that the new validation refused; parameter values and parameter-lane points from a file reached devices unclamped | fuzzer (seeds 4 and 11) | gains and sends clamped like volumes, files checked, parameter values clamped to their declared range in sync; suite: "levels are kept within range" |
| 11 | `device_get` right after an undo that brought a device back reported it as missing, with no parameters, until the end of the turn | fuzzer (seeds 11 and 14) | `device_get` syncs first; suite: "a device brought back by undo reads as loaded at once" |
| 12 | The null backend and offline renders did not treat denormals as zero, unlike the cpal callback | review | same flag on both (scoped for renders, restored afterwards); no measurable speed change with the built-in devices; suite checks the main thread's float mode is restored |
| P1 | `sync` did O(tracks²) work on every edit (routing existence checks, solo paths) | `edit.lua scale` | hash sets, one pass |
| P2 | Every clip edit recompiled and re-sorted every note of the track, and hashed every clip twice | `edit.lua clips`, profiling | per-clip compiled events cached; pointer diff |
| P3 | Note lists crossed into and out of Lua through serde (views ask for them every frame) | `edit.lua notes` | built and read directly, serde as fallback with identical errors |
| P4 | `f32::fract` is a libm call per sample in the synth and drums | profiling by hand | inline truncation, bit-identical output |
| P5 | The LV2 scan was not cached: 1.2 s at every start with plugins | `startup.sh` | cached with bundle modification times; plugins looked up lazily |

Also found, in Tracktion: `Edit::ensureNumberOfAudioTracks` never returns once
an edit reaches its 400-track limit.

Observed, not changed: with the merged undo tree, once more than 1000 states
exist the oldest are pruned but the opened project is kept, so the undo that
reaches the end of the kept window jumps straight back to the project as it
was opened (in `edit.lua`, from 502 clips to none in one undo). That is the
documented pruning rule; it is a large silent jump for a user.

## Reliability runs

- **Fuzzer**: after the last fix, seeds 1–12 × 1500 steps on the merged code
  and seeds 13–20 × 1500 steps before the merge ran clean: about 30% of calls are refused cleanly, about
  200 undo/redo round trips, 30 save/load round trips and 30 double renders per
  seed, all identical; no panic, no non-finite sample.
- **Abuse cases** (`abuse.sh`, 42 cases): none crash, hang or leave a broken
  project; every bad input is refused with a message. Before the fixes: 4
  hangs, 1 abort (out of memory), 2 panics, 5 projects that saved but would not
  load.
- **Allocation guard** (`crates/paw-engine/tests/no_alloc.rs`): no allocation
  or free on the audio thread across every engine message, every built-in
  device, recording, loops, seeks, live and injected MIDI, and a full garbage
  queue (which leaks rather than frees, as designed). Passes after the merge
  too, with its latency delay lines, fades and MIDI 2.0 events. Not covered:
  the CLAP, LV2 and VST3 hosting paths (a counting allocator cannot tell the
  host's allocations from the plugin's); by reading, their event lists are
  bounded by capacity.
- **Soak**: 12 minutes, 40 synth+delay tracks with automation, an edit every
  10 ms (70 518 edits: clip moves, notes, parameters, whole tracks replaced,
  undo, redo): no dropouts counted, nothing leaked from the audio thread,
  p99 2.0 ms of a 5.33 ms budget, and resident memory levels off at 48 MB once
  the undo history is full. One block took 10.2 ms; with the machine at
  load ~15 and the null backend on an ordinary thread I cannot tell whether
  that was the engine or the scheduler. After the merge, 3 minutes: worst
  block 2.07 ms.
- **Memory churn** (30 rounds of build, edit, undo, render, save, load): levels
  off after the first rounds (59.3 → 59.6 MB over the second half).

## What remains slower or weaker

- **Editing notes.** (Since this run, paw.api has calls for one note,
  `clip_note_set` and its kin, and the views use them.) At the time of the
  run, the piano roll read all of a clip's notes into Lua, changed one, and
  wrote them all back: a note move in a 1000-note clip cost about 0.6 ms
  against Tracktion's 2 µs per note object; at 5000 notes, 3 ms.
- **Editing clips on a long track.** Copy-on-write copies the track's list of
  clips on every edit and the sync recompiles the track's event list, so a
  clip edit costs O(clips on the track): 0.05 ms at 1000 clips, 0.25–0.75 ms at
  5000, against Tracktion's 5–30 µs (without its deferred graph rebuild).
  Without the sync the DAW is 3–10× slower than Tracktion for moves and
  deletes, even for adds; its undo is much cheaper (0.5 ms for 998 steps
  against 214 ms for 15 000).
- **Edits in very large projects.** Each sync builds hash maps over every
  track and device: 0.55 ms per edit at 1000 tracks, and building a 1000-track
  project one call at a time takes over a second.
- **One thread.** (Since this run, playback and renders use a thread for
  each core, and stay bit-identical: see docs/reference/engine.md.) At the
  time of the run, renders and playback used one core: at 500 tracks with
  effects paw and Tracktion on 24 threads tied (9.8 s against 9.6 s), and
  500 synth tracks were close to paw's real-time limit at 512 frames.
- **The delay device** allocates 2 s of both channels per instance (768 kB at
  48 kHz), which is most of the resident memory of large projects.
- **MIDI comparison.** The synths differ too much for the MIDI rows to say
  which engine is faster at playing MIDI; they say this DAW's synth is much
  cheaper than 4OSC.

## Full tables (after the merge)


### Offline render (ms of wall time for 32 s of audio)

| kind | fx | automation | tracks | paw×1 render_ms | tracktion×1 render_ms | tracktion×N render_ms |
| --- | --- | --- | --- | ---: | ---: | ---: |
| audio | 0 | 0 | 1 | 48.4 | 555 | 543 |
| audio | 0 | 0 | 10 | 180 | 794 | 719 |
| audio | 0 | 0 | 100 | 1723 | 3606 | 2350 |
| audio | 0 | 0 | 500 | 6119 | 19711 | 7911 |
| audio | 1 | 1 | 1 | 56.8 | 561 | 557 |
| audio | 1 | 1 | 10 | 242 | 916 | 754 |
| audio | 1 | 1 | 100 | 1860 | 4900 | 2724 |
| audio | 1 | 1 | 500 | 9825 | 34257 | 9634 |
| midi | 0 | 0 | 1 | 87.0 | 994 | 985 |
| midi | 0 | 0 | 10 | 805 | 5437 | 1563 |
| midi | 0 | 0 | 100 | 6195 | 45354 | 7146 |
| midi | 0 | 0 | 500 | 30796 | – | 34127 |
| midi | 1 | 0 | 1 | 120 | 914 | 1025 |
| midi | 1 | 0 | 10 | 862 | 4675 | 1580 |
| midi | 1 | 0 | 100 | 5665 | 49915 | 7950 |
| midi | 1 | 0 | 500 | 34501 | – | 37330 |
| midi | 1 | 1 | 1 | 117 | 971 | 934 |
| midi | 1 | 1 | 10 | 685 | 4771 | 1588 |
| midi | 1 | 1 | 100 | 6639 | 53787 | 7604 |
| midi | 1 | 1 | 500 | 33619 | – | 36599 |

### Offline render, per-block processing time (ms; budget 10.7 ms)

| kind | fx | automation | tracks | paw block_p99_ms | paw block_max_ms | tracktion×1 block_p99_ms | tracktion×1 block_max_ms | tracktion×N block_p99_ms | tracktion×N block_max_ms |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| audio | 0 | 0 | 1 | 0.013 | 0.028 | 10.1 | 11.4 | 10.1 | 11.2 |
| audio | 0 | 0 | 10 | 0.076 | 0.11 | 10.1 | 11.6 | 10.2 | 11.4 |
| audio | 0 | 0 | 100 | 0.72 | 1.23 | 10.6 | 15.2 | 10.4 | 15.0 |
| audio | 0 | 0 | 500 | 2.90 | 3.34 | 12.5 | 47.3 | 12.3 | 51.6 |
| audio | 1 | 1 | 1 | 0.013 | 0.033 | 10.1 | 11.4 | 10.1 | 11.2 |
| audio | 1 | 1 | 10 | 0.11 | 0.13 | 10.2 | 11.7 | 10.2 | 11.6 |
| audio | 1 | 1 | 100 | 1.02 | 1.50 | 11.1 | 16.4 | 10.6 | 15.4 |
| audio | 1 | 1 | 500 | 5.79 | 6.08 | 16.8 | 74.0 | 12.6 | 56.4 |
| midi | 0 | 0 | 1 | 0.038 | 0.072 | 10.1 | 11.7 | 10.1 | 11.2 |
| midi | 0 | 0 | 10 | 0.39 | 0.53 | 10.2 | 11.7 | 10.3 | 11.8 |
| midi | 0 | 0 | 100 | 3.44 | 3.66 | 32.9 | 40.2 | 10.6 | 14.1 |
| midi | 0 | 0 | 500 | 16.4 | 17.5 | – | – | 20.5 | 32.4 |
| midi | 1 | 0 | 1 | 0.054 | 0.093 | 10.1 | 11.9 | 10.2 | 11.2 |
| midi | 1 | 0 | 10 | 0.43 | 0.65 | 10.4 | 12.3 | 10.2 | 11.6 |
| midi | 1 | 0 | 100 | 2.90 | 3.21 | 32.2 | 42.3 | 10.7 | 14.2 |
| midi | 1 | 0 | 500 | 19.5 | 21.7 | – | – | 21.8 | 32.7 |
| midi | 1 | 1 | 1 | 0.054 | 0.099 | 10.1 | 11.5 | 10.1 | 11.3 |
| midi | 1 | 1 | 10 | 0.30 | 0.43 | 10.3 | 12.0 | 10.2 | 11.9 |
| midi | 1 | 1 | 100 | 4.10 | 4.30 | 33.2 | 43.0 | 10.9 | 14.9 |
| midi | 1 | 1 | 500 | 19.5 | 19.8 | – | – | 20.9 | 39.4 |

### Real-time playback, ms per callback (DAW: null backend on a real-time clock; Tracktion: hosted device, back to back)

| kind | tracks | buffer | edits | paw p50_ms | paw p99_ms | paw max_ms | tracktion×1 p50_ms | tracktion×1 p99_ms | tracktion×1 max_ms | tracktion×N p50_ms | tracktion×N p99_ms | tracktion×N max_ms |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| audio | 500 | 256 | 0 | 2.05 | 2.90 | 3.46 | 3.90 | 7.85 | 8.23 | 1.19 | 3.00 | 5.10 |
| audio | 500 | 256 | 239 | 2.05 | 3.44 | 3.69 | – | – | – | – | – | – |
| midi | 10 | 128 | 0 | 0.091 | 0.26 | 0.42 | 0.48 | 0.89 | 1.46 | 0.13 | 0.65 | 0.95 |
| midi | 100 | 128 | 0 | 0.86 | 1.68 | 1.68 | 6.69 | 12.5 | 14.1 | 0.83 | 2.91 | 5.71 |
| midi | 100 | 128 | 247 | 0.86 | 1.62 | 1.62 | – | – | – | – | – | – |

### Clip edits, one undo step each (ms for all of them)

| clips | paw add_ms | paw move_ms | paw delete_ms | paw undo_ms | paw redo_ms | tracktion add_ms | tracktion move_ms | tracktion delete_ms | tracktion undo_ms | tracktion redo_ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 1.37 | 0.85 | 1.02 | 2.84 | 3.79 | 1.54 | 0.12 | 0.13 | 1.19 | 1.14 |
| 1000 | 70.2 | 50.1 | 73.0 | 66.6 | 66.1 | 19.1 | 3.53 | 3.53 | 31.0 | 30.4 |
| 5000 | 1803 | 1199 | 1836 | 57.3 | 56.7 | 155 | 28.8 | 22.5 | 214 | 202 |

### Clip edits without the sync to the engine (DAW) — what Tracktion's numbers above measure

| clips | paw add_ms | paw move_ms | paw delete_ms | paw undo_ms | paw redo_ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100 | 0.27 | 0.14 | 0.085 | 0.066 | 0.058 |
| 1000 | 6.38 | 11.8 | 10.6 | 0.46 | 0.43 |
| 5000 | 143 | 289 | 173 | 0.52 | 0.36 |

### Note edits without the sync to the engine (DAW)

| notes | paw add_ms | paw move_ms | paw delete_ms |
| --- | ---: | ---: | ---: |
| 100 | 0.29 | 6.01 | 3.25 |
| 1000 | 13.3 | 859 | 408 |
| 5000 | 211 | 14918 | 7811 |

### Clip edits: ms per edit, first and last tenth

| clips | paw add_first_ms | paw add_last_ms | paw move_first_ms | paw move_last_ms |
| --- | ---: | ---: | ---: | ---: |
| 100 | 0.012 | 0.015 | 0.009 | 0.008 |
| 1000 | 0.019 | 0.14 | 0.049 | 0.051 |
| 5000 | 0.036 | 0.74 | 0.24 | 0.24 |

### Note edits in one clip, one undo step each (ms for all of them)

| notes | paw add_ms | paw move_ms | paw delete_ms | tracktion add_ms | tracktion move_ms | tracktion delete_ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 0.88 | 9.76 | 5.29 | 0.19 | 0.16 | 0.15 |
| 1000 | 24.9 | 625 | 319 | 2.44 | 1.84 | 4.38 |
| 5000 | 566 | 16837 | 8140 | 36.4 | 26.8 | 127 |

### One edit in a project of N tracks (ms, median of 50)

| tracks | paw build_ms | paw volume_ms | paw clip_move_ms | paw undo_ms | paw redo_ms | paw track_add_ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 3.19 | 0.007 | 0.026 | 0.021 | 0.020 | 0.026 |
| 100 | 43.7 | 0.046 | 0.066 | 0.065 | 0.063 | 0.11 |
| 500 | 405 | 0.28 | 0.32 | 0.33 | 0.32 | 0.52 |
| 1000 | 1256 | 0.75 | 0.82 | 0.84 | 0.84 | 1.18 |

### Save and load (ms)

| tracks | clips_per_track | paw build_ms | paw save_ms | paw load_ms | paw file_bytes | tracktion build_ms | tracktion save_ms | tracktion load_ms | tracktion file_bytes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 8 | 1.37 | 0.42 | 0.66 | 190332 | 8.72 | 16.4 | 10.4 | 82179 |
| 100 | 8 | 20.8 | 3.14 | 12.4 | 1899263 | 109 | 44.4 | 81.3 | 812888 |
| 500 | 8 | 181 | 16.4 | 63.8 | 9498863 | 687 | 296 | 520 | 4060489 |

### Resident memory (kB)

| tracks | clips_per_track | undo_steps | paw rss_built_kb | paw rss_undo_kb | tracktion rss_built_kb | tracktion rss_undo_kb |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 100 | 8 | 1000 | 37308 | 41120 | 112632 | 112844 |
| 500 | 8 | 1000 | 170448 | 257628 | 498588 | 498792 |

### Memory over repeated build/edit/render/load rounds (kB)

| rounds | paw rss_first_kb | paw rss_mid_kb | paw rss_last_kb | paw growth_kb_per_round |
| --- | ---: | ---: | ---: | ---: |
| 30 | 15980 | 59308 | 59604 | 19.7 |

### Startup (ms)

| plugins | paw ms | tracktion ms |
| --- | ---: | ---: |
| cached scan | 15.4 | – |
| cold scan | 1269 | – |
| none | 14.5 | 117 |
