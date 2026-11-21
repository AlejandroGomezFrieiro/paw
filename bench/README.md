# Benchmarks and stress tests

Scripts that measure this DAW, the same workloads on Tracktion Engine, and
tools that try to break the DAW. Results and the comparison are in
[RESULTS.md](RESULTS.md). The processor time of paw while it plays,
against REAPER, Ardour and LMMS, is in [DAWS.md](DAWS.md), with its
harness in [daws/](daws).
The speeds that the media design rests on (stretch, decode, hash,
`stat`) are in [media.md](media.md), with its harness in [media/](media).

## Run the benchmarks

```sh
nix develop -c cargo build --release -p paw-tui
bench/tracktion/build.sh                    # optional: Tracktion Engine and its driver
nix develop -c bench/run.sh <name>          # full matrix, both engines → bench/results/<name>.jsonl
nix develop -c bench/run.sh <name> quick    # smaller sizes
REPS=5 nix develop -c bench/run.sh <name>   # more repetitions (default 3; tables show the median)
```

`bench/tracktion/build.sh` clones Tracktion Engine (with JUCE) into
`third_party/`, which git ignores, and builds `te_bench` in a `nix-shell` of
its own (`bench/tracktion/shell.nix`). `run.sh` skips Tracktion if it is not
built. Everything runs with `XDG_*` and, for Tracktion, `HOME` pointed into
`$BENCH_TMP` (default `/tmp/paw-bench`), so neither program touches your real
configuration, caches or recordings.

Each script prints one JSON line per run. `summarize.lua` turns a results file
into Markdown tables:

```sh
./target/release/paw --clean --no-plugins -l bench/summarize.lua bench/results/<name>.jsonl
```

## What each number means

All times are wall-clock milliseconds on one machine. The DAW renders on one
thread. Unless stated, 48 kHz, blocks of 512 frames, 120 BPM, 4/4.

| Script | Workload | Numbers |
| --- | --- | --- |
| `render.lua <tracks> <audio\|midi> <fx> <automation> [bars] [threads]` | N tracks, 16 bars (32 s). Audio: one 2 s clip per bar from the same WAV. MIDI: per bar a 4-note chord and 8 eighth notes into the built-in `synth`. `fx`: a `delay` after it. `automation`: a volume lane with a point per bar. | `render_ms` time of the whole render loop, file writing included; `processing_ms` the engine alone; `realtime_x` audio seconds per second; `block_p50/p99/max_ms` per 512-frame block, against a budget of 10.7 ms. |
| `blocks.lua <tracks> <kind> <fx> <automation> <buffer> <seconds> [edit\|play] [threads]` | Real-time playback on the null backend, which calls the engine on a real-time clock. With `edit`, a clip move and a volume change every 20 ms. Tracktion (`te_bench blocks`) plays the same project through its hosted audio device, calling it back to back rather than on a clock. | Per callback: `budget_ms` (buffer / rate), `p50/p99/p999/max_ms`, and `max_load` = worst / budget (above 1 would be a dropout on a real device). From the engine's own histogram (four buckets per octave, so quantiles are within 19%; the maximum is exact). |
| `edit.lua clips <n> [nosync]` | Add n clips, move each, delete each, each a turn of its own (call, sync to the engine, undo step); then undo and redo everything. With `nosync`, without the sync to the engine: what Tracktion's `edit` measures, since Tracktion rebuilds its playback graph later on its message loop. | Totals per phase; `*_first_ms` / `*_last_ms` the mean per edit over the first and last tenth: a ratio well above 1 means edits slow down as the project grows. |
| `edit.lua notes <n> [nosync\|sync] [list]` | Add n notes to one clip one at a time, then move each, then delete each, with the calls for one note, as the piano roll does. With `list` (and on builds from before those calls), a move reads the notes, changes one and writes them all back. | As above. |
| `edit.lua scale <tracks>` | One edit (a volume, a clip move), undo and redo, in a project of N synth tracks with a delay each. | Median ms per edit, including the sync to the engine. |
| `saveload.lua <tracks> <clips>` | N tracks, each a synth, a delay and `clips` one-bar MIDI clips of 12 notes. | `save_ms`, `load_ms` (load includes rebuilding the engine), `file_bytes`. |
| `memory.lua project <tracks> <clips> <steps>` | The same project, then `steps` one-note edits as undo steps. | Resident memory (kB) after building and after the undo history. |
| `memory.lua bigclip <notes> <steps> <adds>` | One clip of many notes, `steps` one-note changes as undo steps, all undone and redone, then `adds` notes added one by one. | `history_bytes_per_step` (what the undo history holds for each step), `rss_kb_per_step`, `edit_p50_ms` (the change, the sync to the engine and the step), `undo_ms_per_step`, `redo_ms_per_step`, `adds_per_second`. |
| `memory.lua churn <rounds>` | Build, edit, undo, render, save and load the same project over and over. | Resident memory per round; `growth_kb_per_round` over the second half (near 0 when nothing leaks). |
| `redraw.lua [tracks] [frames]` | Drawing the terminal UI: N tracks (a synth, eight one-bar MIDI clips, a volume lane on every third), then `frames` full redraws through `ui_snapshot` with the arrange view alone (150×45 and 80×24) and with the mixer, device panel and piano roll open (150×45 and 100×30). Run as `paw --clean --no-plugins -l bench/redraw.lua`. | `p50_ms` and `max_ms` per frame, for each layout. |
| `devices.lua [tracks] [seconds] [kind...]` | N tracks of audio rendered on one thread, without effects and then with one instance of each built-in effect on every track (with settings that keep it working). | `processing_ms` per render (best of three); `core_percent`, one instance's share of one core in real time. |
| `startup.sh` | Start, run an empty script, exit. | Median of 10. With plugins: the dev shell's LSP Plugins and Surge XT, with an empty scan cache (cold) and a filled one (cached). |

## Stress tests

| Script | What it does |
| --- | --- |
| `fuzz.lua <seed> <steps>` | Random API calls (edits with good and bad values, undo, redo, save, load, render, transport, recording on the null backend, engine restarts, routing, devices, automation) with a fixed seed. Checks that every error is a clean rejection, that undo then redo give back the same project, that a project folder saved, loaded and saved again gives the same files and project (after the first load puts notes on the tick grid), that renders of the same project are bit-identical and finite, and that every listed id resolves. Stops at the first broken invariant with the seed and step. |
| `abuse.sh` (cases in `abuse.lua`) | Damaged and hand-made project files, missing and broken audio, NaN and infinite values, absurd sizes and rates, thousands of tracks past the engine's limit. Each case in its own process under a time and memory limit, so a hang or a crash is reported rather than ending the run. |
| `session-soak.lua <minutes> <dir>` | A long working session on the null backend: per round a new 10 s sound file, six tracks, a take recorded from the test input, edits, undo, playback, save and reopen. Prints resident memory every ten rounds; it stays flat (about 30 MB over 20 minutes and 450 rounds). |
| `soak.lua <minutes>` | Playback for several minutes with continuous edits, watching dropouts, the worst block, leaks and resident memory. |
| `crates/paw-engine/tests/no_alloc.rs` | A counting global allocator: fails if the audio thread allocates or frees anything, across every engine message, every built-in device, recording, loops and a full garbage queue. |

`nix develop -c bench/stress.sh` runs the fuzzer over several seeds, the
abuse cases and a short soak.
