# Profile of paw in the terminal

The scripts in [profile/](profile) measure paw as a person uses it in a
terminal. They show where the processor time, the latency and the memory
go. They measure the kernel (the Rust program with its Lua runtime) and
the terminal frontend. They do not measure the graphical window.

## What you need

- A build with the `profiling` profile. It is the release build with line tables and
  symbols, for `perf` and `heaptrack`:
  `nix develop -c cargo build --profile profiling -p paw-tui`.
  The scripts use the newer of `target/profiling/paw` and
  `target/release/paw`.
- The profile shell: `nix develop .#profile`. It adds `perf`, `samply`,
  `inferno` (flame graphs), `heaptrack`, `valgrind` and `hyperfine` to
  the default shell.
- `perf` without root needs `kernel.perf_event_paranoid` at 2 or less.
  At 2, `perf` samples only the user space of your own processes. The
  scripts use the events `cycles:u` and `instructions:u` and
  `--user-callchains` for this reason.

## How to run a scenario

```sh
nix develop .#profile -c bench/profile/run.sh <scenario> [options]
```

`run.sh` takes the shared lock (`flock`) and runs on the processors 16 to
23 (`taskset`). `CORES` and `LOCK` change them. The driver is
[profile/drive.py](profile/drive.py). It starts paw in a private
pseudo-terminal with `--clean --no-plugins --audio null`, scratch `XDG_*`
folders and `HOME`, and a control socket of its own. It answers the
terminal probe, writes the keys and reads what paw draws. A frame is
what paw writes between the start and the end of a synchronized update.

The driver gives paw the variables `PAW_RUNTIME` and `LD_PRELOAD` of its
own environment. Use `PAW_RUNTIME` to measure the Lua of a checkout with
a binary of main (`tools/dev-runtime.sh`). Use `LD_PRELOAD` to measure
another allocator.

The first run makes the large project with
[profile/project.lua](profile/project.lua). It has 64 tracks with a synth
each, 2 000 MIDI clips and 50 000 notes. Each fourth track has a volume
lane.
The results go to `$BENCH_TMP/profile` (`BENCH_TMP` is `/tmp/paw-bench`
when it is not set), one JSON line for each measurement in
`results.jsonl`.

| Scenario | What it does | What it measures |
| --- | --- | --- |
| `startup` | Starts paw empty, then with the large project, `--reps` times each. | The time from the start to the first frame, the memory and the Lua heap after the start. |
| `idle` | The large project open, nothing moves, `--secs` seconds (60). | The processor share of each thread, frames and bytes, memory. |
| `idle-armed` | As `idle`, with a track armed on the test input of the null backend. | As `idle`. |
| `keys` | Each key of a list in the large project: moves, scrolls, edits, undo, the piano roll, the mixer, pickers, help. | For each key: the processor time of the kernel thread, the time to the first frame and to the last frame, the bytes. A move is measured `--reps` times (5): the median, smallest and largest value. |
| `play` | The large project plays in a loop for `--secs` seconds. | As `idle`, and the frames that the kernel drew (whole, live, unchanged). |
| `record` | A take on a new armed track from the test input. | As `play`. |
| `long` | Edits, keys and playback in turns for `--secs` seconds (600). | Resident memory and the Lua heap every five rounds; the heap after a full collection; the undo history. |
| `repeat` | The keys of `--keys` (comma-separated, with Python escapes), `--times` times. | The processor time of the kernel for each round, and the time from each key to its first frame (median, smallest and largest value). Use it with the probes to profile one key. |
| `scope` | Adds regions (Intro, Verse with Verse A and Verse B in it, Chorus, End) and a group Strings of the first 16 tracks after the start. The project file does not change. Then the keys of a scope in order: `znar`, moves, `zfar`, `zm`, `zr`, `znn`, `zw`, `]z`, `:%quantize 1/4` and `u`, the piano roll, `zW`, `znag`, moves, `zw`. | As `keys`, with the path of the scope after each key. Also the time of a full frame (`paw.api.ui_snapshot`, 40 frames after `j` or `k`) in the song, in the region and in the group: the median, smallest and largest value. |

The thread named `kernel` is the main thread: Lua, the views, the
drawing and the terminal output. The thread of the null backend
processes the audio. It has the name `paw` and its number.

### The probes

These options add a probe to `idle`, `idle-armed`, `play`, `record` and
`repeat`:

- `--perf SECS`: `perf stat` for each thread: instructions, cycles,
  processor time, context switches, page faults. Instructions do not
  change with the load of the machine.
- `--record SECS`: `perf record` with call graphs from the debug data (`--call-graph dwarf`), then a flame
  graph (`<label>-<scenario>.perf.svg`) and its folded stacks.
- `--luaprof`: the tool of LuaJIT that takes samples (`jit.profile`) in the
  kernel. It gives the Lua functions that cost the most, as a flame graph
  (`<label>-<scenario>.lua.svg`). A stack that ends in `[C]` is time in
  Rust, `[N]` in compiled Lua, `[I]` in the interpreter, `[G]` in the
  garbage collector, `[J]` in the trace compiler. LuaJIT counts time in
  Rust at the next Lua line that runs, so use `--record` for the Rust
  side. In `scope`, the probe runs for the first time of each key
  alone. The key gets the samples of each state (`lua_states`) and the
  file of its folded stacks (`lua_folded`).
- `scope` always gives the full cycles of the garbage collector during
  each key (`gc_cycles`) and the Lua heap after it (`lua_kb`). With
  `--collect`, a full cycle runs before each key, outside the
  measurement. Then no key pays for the garbage of the keys before it.
- `--wrap "heaptrack -o <file>"`: runs paw under `heaptrack`. To get the
  allocations of the steady state, run the scenario twice with different
  `--secs`, and give both files to
  `heaptrack_print -f <long> -d <short>`.
- `--budget MS`: the value of `paw.opt.budget_ms` (5 when you do not
  give it, 0 disables it). paw names each callback that takes longer.
  `keys` writes these callbacks in the field `slow` of the key that ran
  them. `repeat` writes all of them in `slow` at the end.
- `--setup LUA`: Lua that the kernel runs after the start. For example,
  `--setup "paw.harmony.provide('builtin', nil)"` stops the chord
  analysis.

## Without the scenarios

Two tools in paw itself give the same view without `drive.py`:

- `paw --startuptime FILE` writes the time of each step of the start to
  `FILE`, in the format of Neovim's `--startuptime`. Each module that
  `require` loads, each extension and the `init.lua` of the user is a
  line with three times: the clock, the whole time, and the time of the
  item alone (without the modules that it loads). The other lines give
  the clock and the time since the line before. The last steps are the
  project load and the first frame. Sort the lines by the third column to
  find the slow modules:
  `grep -E '^[0-9.]+ +[0-9.]+ +[0-9.]+:' FILE | sort -k3 -rn | head`.
  The option adds less than 2 ms to the start.
- `:profile start [file]` in paw starts `jit.profile` in the
  kernel, and `:profile stop` puts the 30 Lua functions with the most
  samples in the quickfix list, with their file and line. With a file,
  it also writes the folded stacks there, as `--luaprof` does: give them
  to `inferno-flamegraph` or `profile/top.py`.

## The other tools

| Script | What it does |
| --- | --- |
| [profile/top.py](profile/top.py) `<file.folded> [n] [--thread NAME] [--under FRAME]` | The functions with the most samples in a folded stack file: their own share and the share with what they call. |
| [profile/calls.py](profile/calls.py) | Counts the calls of each `paw.api` function, and the line that calls it, per frame while paw plays (or with `--press j,k`, per key). |
| [profile/compare.py](profile/compare.py) `<paw A> <paw B> <pairs> <scenario> [options]` | Two builds in turns, A B A B, and the median, smallest and largest value of each measure. |
| [profile/frame.lua](profile/frame.lua) `<project> [rounds] [keys] [size]` | The time of a full frame of the arrange view after each key (`j,k` by default), with no terminal. With `PAW_FRAME_PROF=<file>`, the folded Lua stacks of the frames, for `top.py`. Under `perf stat`, run it with 0 rounds and with N: the difference divided by N is the instructions of a key and its frame. The frame is drawn as the terminal draws it (`paw.api.ui_snapshot`), and it is not written to a terminal. Run it with [profile/headless.py](profile/headless.py). |
| [profile/harmony.lua](profile/harmony.lua) | The time to read all the chords and keys of a project, as when paw opens it, with a hash of the result to compare two builds. Run it with [profile/headless.py](profile/headless.py), which gives paw scratch folders. |
| [profile/help.lua](profile/help.lua) `[project] [alloc]` | The slices of the help index that paw makes at idle (the job `help`): their number, the longest slice, the mean slice and the time of the build. With `alloc`, the collector is stopped, and it also gives the MB that one build allocates. Each run makes the index once, as at the start: run it a few times for the spread. Run it with [profile/headless.py](profile/headless.py). |

## Numbers on a shared machine

The machine runs other work. The processor time of the same work goes up
with the load. Give the load average with each number. Run before and
after in turns with `compare.py`. A difference smaller than
the spread is no measurable difference. Instructions (`--perf`) are the
measure that the load does not change.
