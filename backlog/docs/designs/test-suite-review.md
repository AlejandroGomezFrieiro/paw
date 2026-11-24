# Test suite review: tests that do not depend on time

Review only. No tracked file changed. Audited at
`84fe69c4` (2026-11-22), with the changes in the working tree of the main
checkout at that time (`tools/dev-runtime.sh`, `PAW_TEST_BIN` in
`tests/tools/suite.sh`, `PAW_TEST_STUB` in three test files). TASK-121 was
read at `85456e1a` in `.claude/worktrees/agent-a4cb58c8859bb90a5`, with
the changes in its working tree. Internal text, in Simplified Technical
English.

The owner's goal (2026-11-22): a test gives the same result on an idle
machine and at load 60, in a dev build (opt-level 1) and in a release
build, in any order, under any `only` filter and in parallel shards.
Speed is a matter for `bench/` and for profiles, not for pass or fail.

The scope: `tests/suite.lua` (the runner and the helpers `T`),
`tests/*.lua`, `extensions/*/tests*.lua`, the lessons of the tutor (their
steps are test input), `tests/tools/*.sh` and `speed.lua`, the Rust
integration tests in `crates/*/tests`, the `#[cfg(test)]` modules, the
window tests of `paw-gui`, the remote tests of `paw-tui`, and `bench/`.
The end-to-end scenarios (`tests/e2e`) were read, not run.

The present review builds on finding L1 of
[architecture-review-lua.md](architecture-review-lua.md) and on TASK-121,
which builds L1 now. It does not repeat them. The part "TASK-121 and the other
tickets" tells what
TASK-121 gives, and what this review adds on top of it.

## 0. Method

The method and the word list are the same as in the two architecture
reviews: the skills `improve-codebase-architecture` and `codebase-design`
from `mattpocock/skills` (read again on 2026-11-22), and the local skill
`prune-tests`. In short:

- **Module**, **interface**, **implementation**, **depth**, **seam**,
  **adapter**, **gain for callers**, **locality**, as in the Lua
  review.
- **The interface is the test surface.** A test crosses the same seam as
  a caller.
- **One adapter is a seam on paper, two adapters are a real seam.**
- **Replace, do not layer.** When a test at a better seam exists, delete
  the old test.
- From `prune-tests`: keep a test only if it fails on a regression of
  intended behavior, and only on such a regression.

Words that this review uses with one meaning only:

- **Wall time**: the time of the clock on the wall (`Instant::now`,
  `api.now()` today).
- **Schedule time**: the time that product code uses to decide *when* to
  do a thing (a settle delay, a throttle, a double click, a timer, a timeout
  of keys, an autosave interval).
- **Budget time**: the time that product code uses to measure *how long*
  a piece of work took (a slice of 4 ms, the Lua time limit, a profile).
- **Virtual time**: schedule time that only a test moves.
- **Quiescence**: the state of the kernel when no work is ready, no timer
  is due, and no work of another thread or process is in flight.
- **stall guard**: the one limit of wall time that stops a test that
  never ends. It reports a test that does not end, not a slow machine.
- **Flake**: a test whose result changes with the speed of the machine,
  the order of the tests or the filter, with no change of code.

Changes from the process of the skill: the owner asked for this Markdown
file, not an HTML report. The review walked the code itself, with
`grep` counts, and it ran small filters of the suite to confirm the
classes of the known flakes ("Runs", under "Measurements").

## 1. Measurements

### Size

| Part | Files | Lines | Tests |
| --- | ---: | ---: | ---: |
| `tests/*.lua` (with `suite.lua`) | 132 | 41 939 | |
| `extensions/*/tests*.lua` | 42 | 22 407 | |
| Lua tests in all (`T.test`, `test(`, `T.last`) | 174 | 64 346 | 1 875 |
| Rust `#[test]` (integration and unit) | | | 577 |
| Rust files with `#[cfg(test)]` | 116 | | |
| `crates/paw-gui/tests/window.rs` | 1 | 2 739 | 45 |
| `crates/paw-tui/tests/remote.rs` | 1 | | 16 |

The largest Lua test files: `tests/guides_howto.lua` (1 494 lines),
`tests/core.lua` (1 385), `tests/frontend.lua` (1 230),
`tests/workflow.lua` (1 084), `tests/tuimouse.lua` (867).

### What the Lua tests do with time

Counts over the 174 Lua test files.

| Construct | Uses | Files | Kind |
| --- | ---: | ---: | --- |
| `paw.wait(ms)` (time passes, timers fire) | 140 | 55 | sleep |
| `api.sleep(ms)` (time passes, nothing runs) | 21 | 13 | sleep |
| `api.wait(ms)` | 8 | 3 | sleep |
| Literal sleeps (`paw.wait(300)` and so on) | 162 | | sleep, 31.1 s in sum |
| `{ wait = N }` in the steps of the tutor's lessons | 23 | 13 lessons | sleep, 7.7 s in sum |
| `api.now()` (deadlines, durations) | 138 | 36 | wall time |
| `os.clock()` | 4 | 2 | processor time |
| `os.time()` | 13 | 6 | date (fixtures) |
| `T.until_` | 169 | 34 | event wait, 30 s deadline |
| `T.next_block` | 37 | 15 | event wait, 10 s deadline |
| `T.until_beat` | 66 | 10 | event wait, 30 s deadline |
| Local `wait_for` helpers (return false at a deadline of 5 s) | 7 copies | 7 | event wait |
| `T.quick` and `T.cpu_ms` | 29 | 7 | speed assertion |
| `:meter()` (a live level of the real-time engine) | 69 | 24 | live audio |
| `transport.play()` | 56 | 25 | live audio |
| `paw.render` and `T.render` (offline, deterministic) | 308 | 46 | rendered audio |
| A function of `paw.api` replaced by the test | 13 | 11 | replaced function |
| `math.random` (seeded with `math.randomseed(77)`) | 2 | 1 | random |

78 of the 174 files hold at least one sleep, wall-time read, speed
assertion or live meter (400 constructs in all). The files with the most:

| File | Sleeps | `api.now` | Speed | Live meter | Event waits |
| --- | ---: | ---: | ---: | ---: | ---: |
| `tests/guides.lua` | 7 | 14 | 0 | 2 | 1 |
| `tests/guides_howto.lua` | 11 | 8 | 0 | 2 | 3 |
| `tests/offline.lua` | 10 | 10 | 0 | 1 | 2 |
| `tests/safety.lua` | 6 | 5 | 0 | 7 | 0 |
| `tests/core.lua` | 5 | 0 | 0 | 11 | 36 |
| `tests/input.lua` | 6 | 0 | 0 | 7 | 6 |
| `extensions/doctor/tests.lua` | 4 | 8 | 0 | 0 | 0 |
| `tests/flow.lua` | 3 | 9 | 0 | 0 | 1 |
| `tests/plugin_state.lua` | 9 | 2 | 0 | 0 | 0 |
| `tests/attr.lua` | 3 | 4 | 0 | 4 | 5 |
| `tests/scope.lua` | 6 | 0 | 0 | 4 | 0 |
| `tests/complete.lua` | 7 | 2 | 0 | 0 | 0 |
| `tests/realtime.lua` | 0 | 3 | 0 | 6 | 15 |
| `tests/stretch.lua` | 4 | 0 | 0 | 3 | 0 |
| `tests/help.lua` | 1 | 0 | 5 | 0 | 0 |

The literal sleeps that cost the most wall time: `tests/safety.lua` 4.8 s,
`tests/workflow.lua` 3.4 s, `tests/offline.lua` 2.6 s, `tests/media.lua`
2.4 s, `tests/input.lua` 2.4 s. With the tutor, the suite sleeps at least
39 s on literals alone, before the loops that sleep 5 ms at a time.

### Speed assertions in pass/fail tests

About 25 assertions fail when the machine, the build or the load is slow:

- `T.quick` (processor time, scaled by the load average, at most 8
  times): `tests/help.lua:311` and `:314`, `tests/pick.lua:223`,
  `extensions/notation/tests_speed.lua:32` and `:41`,
  `extensions/notation/tests.lua:1681` and `:1682`,
  `extensions/musicops/tests.lua:622`, `extensions/pattern/tests.lua:382`.
- Wall time, compared with a number: `extensions/doctor/tests.lua:340`
  (`< 10000`), `tests/offline.lua:95` (`< 400`), `:137` (`< 4 * one`),
  `:153` (`< 1000`), `tests/robust.lua:140` (a ratio of two times),
  `:463` (`< 12000`), `tests/safety.lua:346` (`< 4500`), `:357`
  (`< 5000`), `tests/search.lua:462`, `tests/flow.lua:614` (`< 3000`),
  `extensions/mixdiag/tests.lua:385` (`elapsed < 10`).
- Processor time: `extensions/utau/tests.lua:359` (`os.clock`, a block in
  less than 1 000 µs).
- Processor share of the window: `crates/paw-gui/tests/window.rs`, three
  tests on `cpu_percent` and `settled_cpu_percent` (lines 1660, 1726,
  1781), and one more that is `#[ignore]` (1737).
- The end-to-end scenarios check that the keys of a day were quick
  (`tests/e2e/lib.lua:158` and `:320`, rule 7, with `speed.lua`).

### The Rust tests

| File | Tests | `sleep` | `Instant::now` | Durations |
| --- | ---: | ---: | ---: | ---: |
| `paw-engine/tests/*` (13 files) | 49 | 24 | 16 | 13 |
| `paw-tui/tests/remote.rs` | 16 | 2 | 17 | 32 |
| `paw-tui/tests/join.rs`, `safety.rs` | 8 | 7 | 9 | 11 |
| `paw-mcp/tests/protocol.rs` | 6 | 3 | 4 | 5 |
| `paw-gui/tests/window.rs` | 45 | 18 | many | 30 |

- The engine tests are the good model. They make an `Engine` and call
  `engine.process()` block by block (`clips.rs`, `sleep.rs`, `punch.rs`,
  `tempo.rs`). No real time passes. The `sleep` in `sleep.rs` is the
  name of the feature (devices that sleep), not a wait.
- `remote.rs` checks absence with `quiet(&c, 400 ms)` (17 uses in the
  test files of all crates): "nothing came in 400 ms".
- `window.rs` finds text on the screen with `tesseract` (30 calls of
  `find_text`, `click_text` or `click_last_text`), waits with `pause()`
  after gestures (42 uses) and with fixed sleeps of 500 and 700 ms when a
  window starts (lines 580, 592). An `#[ignore]` test measures how often
  OCR reads each text (line 2177): the reading is known to be not
  certain.
- `#[cfg(test)]` modules with sleeps or wall time: `paw-core/src/io.rs`
  (9), `paw-engine/src/record.rs` (4), `paw-core/src/session/folder.rs`
  (4), `bake/scheduler.rs` (3, it sleeps the real `SETTLE` of 150 ms),
  `bake/helper.rs` (3), `measure/mod.rs` (3), and 7 more with one or two.

### What the product code does with time

The tests can only be as certain as the code under test. The product code
reads wall time for schedule time in many places:

- Lua: `api.now()` in 46 files of `runtime/lua/paw` and `extensions`
  (147 reads): 40 reads that set a time to come (`api.now() + x`), 29
  that compare with a deadline, 21 that take a duration. Examples of
  schedule time: the double click (`paw/mouse.tl:151`, 400 ms), the
  audition throttle of utau (`utau/audition.lua:49`, 50 ms), the live
  frames (`paw/ui.tl:1761`, `active_until`), the time a message shows
  (`ui.tl:1569`), the MIDI light of the status line (`statusline.tl:899`),
  the pace of remote frames (`remote.tl:293`), the idle pause of
  completion (`complete.tl:992`, `complete_idle_ms`), the slices of help
  (`help.tl:1088`).
- Lua timers (`paw.defer`, `timer_start`): 56 sites in product code. The
  kernel fires them on wall time (`crates/paw-core/src/api/timers.rs:15`,
  `due_timers`).
- Rust: `Instant::now` in 127 places of `crates/*/src`. Schedule time
  examples: the bake settle (`paw-core/src/bake/scheduler.rs:31`, 150
  ms), the settle of the file watch (`session/files_watch.rs:31`, 300
  ms), the state lanes (`session/statelanes.rs:282` and `:285`, 150 ms).
- Audio: with `--audio null` (the default of a `-l` script,
  `paw-tui/src/main.rs:587`), a clock thread renders blocks on wall time
  (`paw-engine/src/backend.rs:478`, `spawn_clock`). The position of the
  transport, the meters and the sleep of devices move with the clock on
  the wall, not with the test.
- No clock seam exists. A search for a `Clock` trait, a fake clock or a
  virtual clock finds nothing in `crates` or `runtime`.

### The kernel loop in a test

A test runs inside the kernel as a `-l` script. Between two calls of the
test, nothing runs: Lua timers fire, plugins are looked after, MIDI and
helper output is read, and the undo step closes only inside `api.wait`
(`api/timers.rs:79` to `:105`). So the suite has one way to make the
kernel do its work: let wall time pass. It has no call that does one turn
of the loop, and no call that says "nothing is left to do".

### Runs

The machine had a load average of 16 to 34 during these runs. The binary
was `target/release/paw` of the main checkout, which is older than
`84fe69c4`, with the Lua and Teal of `84fe69c4` from
`tools/dev-runtime.sh` (`PAW_TEST_BIN`, `PAW_RUNTIME`, scratch folders in
the session's scratch directory).

| Filter | Runs | Result | Wall time |
| --- | ---: | --- | ---: |
| a name that no test has | 1 | all passed | 0.27 s |
| `help is made at idle` | 3 | 3 passed | about 6 s each |
| `a clip plays a rough preview` | 2 | 2 passed | 0.78 s |
| `tracks fit their height` | 1 | passed | 0.26 s |
| `narrowing to a group shows` | 1 | passed | 0.30 s |
| `the vocal editor plays notes as they are placed` | 3 | **3 failed**: "a note placed: got 2, want 3" | |
| `the vocal editor selects a phrase` | 2 | **2 failed**: "a double click on empty space selects the phrase there: got "", want "1,2"" | |
| `tutor: lesson 4 (pianoroll)` | 3 | 3 passed | |
| `tutor: lesson` (17 lessons) | 1 | all passed | 13.2 s |
| `tutor:` (32 tests) | 1 | all passed | 30.1 s |

Each run also printed "attempt to get length of field 'fields' (a nil
value) (derived.lua:1014)" 12 times, and still said "all passed". The
binary and the runtime did not agree, and the suite did not see it
(finding T9).

The runner prints no time per test or per file, so this review cannot
name the slowest files from a run. The full suite was not run (the rules
of the task).

### Flakes that the tickets report

15 tickets report test failures that "pass alone" or that are "timing
failures": TASK-5 ("stretch label timing"), TASK-6.2 ("help made at
idle; notation page speed", load 46 to 60), TASK-7.2 ("one help timing
test failed under load 60 to 85"), TASK-7.3 ("3 timing flakes that pass
alone"), TASK-16 ("only load-timing failures, which pass alone"), and
TASK-121 (the filter failures). Each merge then needs a person or an
agent to decide that a failure is "only timing". The decision is the
cost that the owner wants to remove.

## 2. Summary: the findings, by value and risk

Value: how many flakes the change removes, and what it unblocks. Risk:
the chance to break behavior. Size: S is less than 1 day, M is 1 to 3
days, L is 3 to 7 days.

| # | Finding | Value | Risk | Size | Order | Milestone | Tickets |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T1 | Speed assertions in pass/fail tests: move them to `bench/`, or count work | high | low | S to M | 1 | m-3 | TASK-114, TASK-79 |
| T2 | No written rule and no check against tests that depend on time | high | low | S | 1 (with T1) | m-3 | TASK-121 |
| T3 | Schedule time is wall time everywhere: one clock with a real and a manual adapter | high | medium | L | 2 | m-6 | TASK-114 |
| T4 | The kernel loop cannot be stepped and cannot say "nothing is left to do" | high | low | M | 2 (with T3) | m-6 | none |
| T5 | The audio runs on a real-time thread in the tests: a stepped backend | high | medium | M | 3 | m-6 | TASK-16 |
| T6 | Plugin, helper and mock processes have no handshakes | medium | medium | M | 4 | m-6 | none |
| T7 | Order dependence that the fingerprint of TASK-121 cannot see | medium | low | S | with TASK-121 | m-3 | TASK-121 |
| T8 | Remote and window tests wait for time and read pixels | medium | medium | L | 5 | m-6 | TASK-42 |
| T9 | The structure of the suite: one runner path, a binary check, times per file, shared helpers | medium | low | S | 6 | m-6 | TASK-121, TASK-69 |

The order in short: T1 and T2 first. They are cheap, they remove the
flakes that agents report most (help at idle, notation speed), and the
check stops new ones.

Then T3 and T4 together: they are the seam that the
rest uses. Then T5, which makes the live audio tests stepped. Then T6 and
T8 for the other processes. T7 goes with TASK-121 now. T9 is small and
can go at any time.

## 3. The design

### 3.1 The rules for a test

The rules below are written so that they can go into `AGENTS.md` (section
"How to work") and into the skill `prune-tests` (a section "Time"). They
apply to the Lua tests, the Rust tests and the window tests.

1. **A test checks behavior, not speed.** No assertion on wall time,
   processor time, frames per second, a share of a processor, or a count
   that changes with speed (frames drawn in a time, slices of a job,
   blocks in a time). To guard a cost, count the work (compiles, renders
   of a view, notes read, cells drawn, requests sent), or measure it in
   `bench/`.
2. **Time passes only when the test says so.** A test does not sleep:
   no `paw.wait(ms)` with a real clock, no `api.sleep`, no
   `std::thread::sleep`, no busy loop. It uses `T.settle()`,
   `T.advance(ms)` and `T.next_block(n)` ("The seams").
3. **A wait fails when nothing is left to do, not when a time ends.**
   `T.until_(cond, what)` fails when the kernel is at quiescence and
   `cond` is still false. The only limit of wall time is the stall guard
   of the runner, one value for all tests. Its message says "stalled", and a
   test does not set it.
4. **Check absence after a barrier.** To check that a thing does *not*
   happen, first settle, and advance past each timer that could make it
   happen. Do not check "nothing in 300 ms". A protocol test calls a
   sync request that returns after everything before it was sent.
5. **Check sound in a render or in stepped blocks.** Use `paw.render`
   (offline), or play with the stepped backend and `T.next_block(n)`.
   Do not read a live meter after a sleep.
6. **Hold other processes with a handshake.** A plugin, a helper or a
   mock server that the test controls waits for the test to release it
   (a gate), and tells when it is done (an acknowledgment). An injected
   stall lasts until the test ends it. Do not compare a finite delay with a
   deadline.
7. **A test makes all the state that it reads.** It starts from
   `T.fresh()` or `T.start()`, sets each option that it needs, paints a
   window before it clicks in it, takes ids from what the kernel gives
   (never a literal kernel id), and writes files under `T.scratch`. It
   puts back what it changes with `T.after` (the leak check of TASK-121
   fails if it does not).
8. **A test that needs real time is a live test.** The few tests that
   must use the real clock thread, a real socket or a real device are
   marked live ("Two tiers of tests"). They still follow rules 1, 3, 4 and 6.
9. **The result is the same everywhere.** Idle or at load 60, dev or
   release build, any order, any `only` filter, any shard. A test that
   cannot meet this is not finished.
10. **Product code takes schedule time from the clock.** A settle delay, a
    throttle, a double click, a timeout or an interval reads
    `api.now()` (the schedule clock, "The seams"), and a timer fires it.
    timer. Budget time (the length of a slice, the Lua time limit, a
    profile) reads `api.real_ms()`.

Text for `AGENTS.md`, in its style:

> - A test checks behavior, not speed. Speed goes in `bench/`.
> - A test does not sleep and does not read the clock. Time passes only
>   with `T.advance(ms)`; the kernel does its work with `T.settle()`. A
>   wait fails when nothing is left to do, not when a time ends.
> - A test gives the same result idle or loaded, in a dev or a release
>   build, in any order, under any filter and in any shard.
> - `tools/testlint.lua` refuses a new sleep, clock read or speed
>   assertion in a test. Its allow-list only gets shorter.

Text for the skill `prune-tests`, a new kind of dependence after "The
implementation":

> **The machine:** it fails when the machine is slow or loaded, or when
> another test ran before it. It sleeps, reads the clock, compares a
> time, or reads state that it did not make. Rewrite it against the
> behavior with `T.settle`, `T.advance` and a render, or delete it if a
> bench already measures the same thing.

### 3.2 The seams

The seams are listed from the bottom up. Each has two adapters or more,
so each is a real seam.

**A. The clock (Rust, `paw-core`).** A trait `Clock` with one method
that gives the schedule time since the start, and two adapters:
`WallClock` (today's behavior) and `ManualClock` (moves only when told).
`Shared` holds one `Arc<dyn Clock>`, chosen once at the start for the
whole process.

The parts that read it: `api.now()`,
`due_timers` and `timer_start` (`api/timers.rs`), the bake scheduler
(`bake/scheduler.rs`, which already takes `settle` as an argument of
`poll`), the file watch, the state lanes, the autosave interval. The
Lua time limit (`watchdog.rs`) and every measure of a duration stay on
wall time, through a new `api.real_ms()`. The command line takes
`--clock manual`; the runner passes it.

The crate `metrique-timesource` (0.1.10, Apache-2.0) was evaluated for
this seam, at the owner's request. Production code calls
`time_source().instant()` and `.system_time()`. A test sets an override
for its thread (`set_time_source`, with a guard), or uses a
`ManuallyAdvancedTimeSource` that the test moves by hand. An override for
a `tokio` runtime also exists. The crate does not control
`thread::sleep`, `Condvar` timeouts, timers on other threads, or
`Instant::now()` in dependencies.

paw needs more than the crate gives:

- The Lua suite drives the paw binary in its own process. The test is
  not Rust code that sets an override. The choice of clock must come
  from the command line (`--clock manual`), and Lua must move the clock
  through `paw.api`.
- The override of the crate is local to a thread. The kernel has
  several threads: the bake workers, the I/O runtime of the helpers, the
  audio clock thread. A value that the kernel thread reads must be the
  same value that a worker reads. paw needs one clock for the process.
- The hard part is not the number. `T.advance(ms)` must fire each Lua
  timer in its order, run the audio blocks of that time, take in the
  work of other threads, and stop at quiescence. The ticker of frames,
  the idle jobs (`paw.slices`, the help index) and the settle delays are
  timers. No crate does this. It is paw's own loop (seam B).
- `api.wait` sleeps with `thread::sleep`, which the crate does not
  control. The manual clock replaces the sleep with `advance`, so paw
  must change that code anyway.

The recommendation: a small own seam, not the crate. A trait `Clock`
with `now()` (a `Duration` since the start), and two adapters:
`WallClock` and `ManualClock` (an `AtomicU64` of nanoseconds, so that
each thread can read it). The kernel and `paw.api` take the same
`Arc<dyn Clock>`. Each reader gets the clock as an argument or a field,
not from a global.

A caller can see which modules read time, and the
lint can find each `Instant::now()` that stays. The trait is about 40
lines. The rule "use a crate before you write it yourself" does not
apply: the crate gives the number, and the number is the small part.

Two designs were compared for the Lua side:

- Option A (recommended): `api.now()` becomes the schedule clock.
  Product code that schedules does not change (most of the 147 reads).
  The reads that measure a budget move to `api.real_ms()`: `limit.tl`,
  `slices.tl`, `profile.tl`, the slice end of `help.tl`, the timings of
  `derived.tl`, `doctor/report.lua` and `notation/bench.lua`, about 25
  sites in 8 files. The 138 reads of `api.now()` in the tests also
  become virtual, so their deadline loops become certain with no edit.
- Option B: a new `paw.clock.now()` for schedule time, and `api.now()`
  stays wall time. More than 100 product reads must change, and a
  forgotten one stays a flake. Option B is rejected.

With Option A, `paw.wait(ms)` under the manual clock means "advance
`ms` of virtual time, then settle". The change makes most of the 162 literal
sleeps into certain steps with no edit of the test. The lint (section
3.4) then asks for the clearer name `T.advance` in new code.

**B. One turn of the kernel loop, and quiescence (Rust and Lua).** Move
the body of the loop in `api.wait` into `Shared::turn()`: fire the due
timers, look after the plugins, read MIDI and helper output, `settle`,
close the undo step. `api.wait` calls `turn()` and sleeps. Add:

- `api.step()`: one turn, no sleep.
- `api.pending()`: what is in flight, by kind: `{ timers_due, bakes,
  helpers, plugin_loads, renders, messages, slices }`. Each subsystem
  reports its own count. This is a deep module: one small function, and
  each subsystem keeps its own work behind it.

**C. The helpers of the runner (`tests/suite.lua`).** A small interface
that replaces `until_`, the 7 local `wait_for` helpers, `T.quick` and
`T.cpu_ms`:

| Helper | Does | Fails |
| --- | --- | --- |
| `T.settle()` | Turns the loop until nothing is ready. Waits for work in flight in other threads and processes. No virtual time passes. | At the stall guard only. |
| `T.advance(ms)` | Moves virtual time by `ms`: fires each timer in its order, runs the audio blocks of that time on the stepped backend, then settles. | At the stall guard only. |
| `T.until_(cond, what)` | Settles, then checks `cond`. | When the kernel is at quiescence and `cond` is false: "nothing is left to do, and <what> is false". |
| `T.advance_until(cond, what, ms)` | Advances to the next timer or block until `cond` holds. | When `ms` of virtual time passed. This is certain, because the time is virtual. |
| `T.next_block(n, device)` | Runs `n` blocks on the stepped backend. The name stays. | Never by time. |
| `T.until_beat(beat, rounds)` | `T.advance_until` on the playhead. The name stays. | After the virtual time of the song to that beat, and one block more. |

`T.quick`, `T.cpu_ms` and `tests/tools/speed.lua` move to `bench/lib.lua`.

**D. The stepped audio backend (`paw-engine`).** A backend `step` next
to `null`, `test` and the `cpal` ones, with no thread of its own: the
kernel calls `engine.process()` on its own thread when `T.advance` or
`T.next_block` asks.

The engine tests already do this (`Engine::process`
is the internal seam), so the change exposes a seam that exists. The
rule "no lock, no allocation, no wait on the audio thread" stays true:
the stepped backend has no audio thread.

With `--clock manual`, the runner chooses `--audio step`. One block moves
the clock by the length of the block, so the clock and the audio stay one time.

**E. Handshakes with other processes.** Test commands for the plugin
sandbox (`api.device_call(id, "sandbox.<cmd>")`, which already has
`sandbox.hang` and `sandbox.pid`): `hold` and `release` (the next create,
load or block waits for the test), `hang` (until the test ends it), and
`deadline` (a short deadline for this device only, so that an ordinary
plugin never meets a short deadline). An event `device.state_applied`
with a sequence number, sent when a plugin took a state. The same pattern
for helper processes (`bake/helper.rs`, the utau engine) and for the mock
servers of the tests (`tests_tone3000.lua`): a ready line, and an
acknowledgment for each request.

**F. Sync barriers for frontends.**

- Remote: a request `frontend.sync` that returns the sequence number of
  the last state sent, after it flushed all that was due. Each pushed
  state carries its sequence number. "Nothing is sent when nothing
  changed" becomes: sync, then sync again, and no state between the two.
- Window (`paw-gui`): a control request `window.sync` that returns after
  the window handled each input event that the X server had before the
  request (an `XSync` and a marker event that the window echoes). A
  request `window.texts()` that gives each text that the window drew,
  with its rectangle, from the scene that it drew. Tests find a button
  or a menu entry by this list, not by OCR. A counter request
  `window.counts()` gives frames drawn and wake counts, so that "an idle
  window does no work" is a count between two barriers, not a share of
  a processor.

### 3.3 Two tiers of tests

- **Stepped (the default).** `--clock manual --audio step`. Nearly all
  tests. Only quiescence and the stall guard end a wait.
- **Live.** `T.live(name, fn)`, or a file `tests/live_<area>.lua`. The
  wall clock and the `null` backend, as today. For the tests that check
  real time itself: `tests/realtime.lua` (the transport moves in real
  time; its check is one-sided, "not faster than real time", so load
  cannot fail it), the sandbox and its deadlines in `tests/safety.lua`,
  real sockets (`midi2.lua`, `midi_out.lua`, `remote.rs`), and the
  window tests. The runner starts a second paw process for them. They
  follow rules 1, 3, 4 and 6: outcomes only, stall guards only.

The goal is fewer than 60 live tests (about 3 % of the suite).

### 3.4 The check that refuses new tests that depend on time

`tools/testlint.lua` (Lua, run by paw `-l`, or by plain LuaJIT, because
it reads text only):

- Reads `tests/*.lua`, `extensions/*/tests*.lua`, the lessons of the
  tutor, `crates/*/tests/*.rs` and the `#[cfg(test)]` modules.
- Lua patterns: `api.sleep(`, `api.wait(`, `os.clock(`, `T.quick(`,
  `T.cpu_ms(`, `cpu_ms(`, `api.real_ms(`, `paw.wait(` and `api.now()`
  outside a live test, `:meter(` outside a stepped play, and a
  `{ wait = N }` step in a lesson.
- Rust patterns: `thread::sleep`, `Instant::now`, `cpu_percent`, and
  `quiet(` with a `Duration`.
- An allow-list `tests/timing-allowed.txt`, one line `<file> <pattern>
  <count>`, as `tests/leaks-allowed.txt` (TASK-121) and
  `any-allowed.txt` do. A count that goes up fails. A count that goes
  down fails until the line is made smaller, so the list only gets
  shorter.
- A second part for product code: `api.now()` in a module that is on the
  list of budget readers fails, and `api.real_ms()` outside that list
  fails. This keeps rule 10.
- Runs in the suite (a test "no test depends on time") and in
  `nix flake check` (it needs no display and no audio, so the sandbox of
  the build can run it).

### 3.5 What moves to `bench/`

| Now | Behavior to keep in the suite | Speed to move |
| --- | --- | --- |
| `tests/help.lua:298` | `prepare()` returns before the index is made; after the last slice, `:help` makes no new build (a count of builds). | The longest slice and the first `:help`: `bench/profile` with TASK-114. |
| `extensions/notation/tests_speed.lua` (whole file) | Nothing new: other notation tests cover the drawing. | Open and draw, twenty moves: a `bench/` script. |
| `extensions/notation/tests.lua:1681` | The paint is correct (already checked). | Paint times. |
| `extensions/musicops/tests.lua:622`, `pattern/tests.lua:382`, `tests/pick.lua:223` | The results (already checked). | The times. |
| `tests/search.lua:446` | "found some" (already checked). The comment says that the report already has the 1 000-track measure. | Delete the speed line. |
| `tests/robust.lua:125` | Every note is there, ids are unique. | The ratio of two times: `bench/edit.lua notes` already reports `*_first_ms` against `*_last_ms`. Delete it, or count the notes read if a counter comes. |
| `tests/offline.lua:93`, `:153` | Adding a device that loads, or opening a project, returns while the plugin is held (gate), and the state is `loading`. | Delete the times. |
| `tests/offline.lua:137` | Six plugins are made at the same time: while all are held, the sandbox reports at least 4 in creation at once. | Delete the ratio. |
| `tests/safety.lua:346`, `:357`, `tests/robust.lua:463`, `tests/flow.lua:614`, `extensions/doctor/tests.lua:340`, `extensions/mixdiag/tests.lua:385` | The outcome (stopped, reported, rendered without it). | Delete the time comparisons. |
| `extensions/utau/tests.lua:344` | Four phrases at once sound (a level in the block). | The µs per block: a bench. |
| `window.rs` CPU tests (1660, 1702, 1726, 1781) | An idle window draws no frame and asks for nothing between two barriers (counts). | Share of a processor: `bench/profile` (it already measures it). |
| `tests/e2e/lib.lua:158`, `:320` | The scenario's outcome. | The slowest key of a day: a report line, not a failure. |

## 4. The findings

### T1. Speed assertions in pass/fail tests

**Evidence.** "Measurements" lists about 25 speed assertions. The two that
agents report most are `tests/help.lua:298` and the notation page speed.
`T.quick` scales a limit by the load average and by the slowdown of a
fixed piece of work, at most 8 times (`tests/tools/speed.lua`). The scale
makes it fail less often, but it still fails: under load 60 to 85, or
when the slow part is the kernel in a dev build (opt-level 1 for paw's
own crates, `Cargo.toml:52`), which a piece of Lua work does not show.

The help test also measures a known bug (TASK-114: one `md.parse` of a
large page runs with no pause), so the test fails for a reason that is
already a ticket. Several speed checks repeat what `bench/` already
measures (`bench/edit.lua notes`, the search report).

**Proposed change.** Apply the table of "What moves to bench". Delete
`tests/tools/speed.lua` from the suite; `bench/lib.lua` takes it. Where
cost is the behavior, count the work, as the TASK-7.2 test does ("100
copies, 1 compile").

**Gain.** It removes the flakes that the tickets report most, at once.
A failure in the suite means a regression of behavior. Speed has one
home, `bench/`, with its spread and its load written down (the memory
note on noisy CPU numbers).

**Risk.** Low. A speed regression is no longer caught by the suite. The
bench and the profiles catch it, as rule 7 and m-3 already say.

**Size and order.** S to M. First.

### T2. No rule and no check against tests that depend on time

**Evidence.** The how-to page `docs/how-to/run-the-tests.md` ("Write a
test that a loaded machine does not break") tells the reader to wait for
events, but also to give a wait "the time that the slowest machine
needs", and to measure speed with `T.quick`. So the current rule accepts
time as a pass or fail condition. Nothing checks it: 162 literal sleeps
and 138 clock reads exist.

**Proposed change.** The rules of "The rules for a test" in `AGENTS.md`, in the
skill `prune-tests` and in the how-to page (which is external, so in plain
writing). `tools/testlint.lua` with `tests/timing-allowed.txt` ("The check that
refuses new tests"). The first allow-list holds today's counts.

**Gain.** No new test that depends on time. The allow-list shows the
work left, as a number that only goes down.

**Risk.** Low.

**Size and order.** S. With T1.

### T3. Schedule time is wall time: one clock, two adapters

**Evidence.** "What the product code does with time", under "Measurements". Each
settle delay and throttle is a race with the test: the stretch bake (150 ms,
`bake/scheduler.rs:31`), the double click (400 ms, `mouse.tl:151`), the
audition throttle (50 ms, `utau/audition.lua:49`), the idle pause of
completion, the time that live frames go on (`ui.tl:1823`, 1.5 s), the
timeout of keys. `tests/frames.lua:205` waits two real seconds to get
past `active_until`. The leader hints tests sleep 400 ms to see the list
(`tests/leader_hints.lua:91`).

**Proposed change.** Seam A ("The seams"), Option A. Then the
product-code part of the lint.

**Gain.** Locality: one clock, not 46 files that each read the wall. A
test of a settle delay says what it means: "before 150 ms, the preview;
after, the stretch". The suite gets faster: virtual time costs nothing,
so about 39 s of sleeps and the 5 ms poll loops go away.

**Risk.** Medium. A product read of budget time that stays on
`api.now()` sees no time pass under the manual clock, and its loop does
not end. The lint (a list of budget readers) and the stall guard show it
at once, in the tests, not later.

**Size and order.** L. Second, with T4.

### T4. No step of the kernel loop, and no quiescence

**Evidence.** "The kernel loop in a test", under "Measurements". `T.until_` polls
every 5 ms until a deadline of 30 s, and its message is "waited 30000 ms
in vain". `tests/plugin_state.lua:66` (`holds`) polls for 2 s and then
returns with no error, so the next assertion fails with a wrong message.
Seven files have their own `wait_for` with a deadline of 5 s. A test
cannot tell "not yet" from "never".

**Proposed change.** Seam B and the helpers of seam C.

**Gain.** For callers: one `T.until_` with a clear failure ("nothing is
left to do, and the stretch is still being made") for 272 waits. A real
bug fails at once, not after 30 s.

**Risk.** Low. `api.pending()` needs each subsystem to report its work
in flight. A subsystem that forgets makes `T.until_` fail early with a
clear message, which shows the subsystem.

**Size and order.** M. With T3.

### T5. The audio runs on a real-time thread

**Evidence.** `spawn_clock` (`paw-engine/src/backend.rs:478`) renders on
wall time. 69 live meter reads and 56 `transport.play()` calls depend on
how many blocks ran in a sleep. Examples: `tests/devices.lua:136` reads
the gain reduction after `paw.wait(600)`; `tests/stretch.lua:107` reads
the level after `paw.wait(60)`; `tests/offline.lua:486` after
`paw.wait(200)`; `extensions/utau/tests_singing.lua:792` polls the level
for 3 s. The engine's own Rust tests show the certain way: they call
`engine.process()` block by block.

**Proposed change.** Seam D. Change the live meter tests to stepped
blocks, or to `paw.render` where the test checks the sound, not the
live path.

**Gain.** A meter, a tuner, a gain reduction, the sleep of devices and
the playhead are functions of the input and the blocks, so the tests can
compare exact values.

**Risk.** Medium. The live path (the clock thread, the ring buffers
between threads) gets less test coverage. The live tier keeps a few
tests of it (`tests/realtime.lua`), with outcomes only.

**Size and order.** M. Third.

### T6. Other processes have no handshakes

**Evidence.** `tests/offline.lua:92` makes a plugin "slow to make" with
a finite delay (`hang(kind, 0.8, 20)`), then checks that the call
returned in less than 400 ms. `tests/safety.lua:340` waits up to 8 s for
"stopped answering" and checks that it came in less than 4.5 s.
`tests/plugin_state.lua` `holds()` and `rested()` (lines 66 and 78) poll
for the plugin's state with a time limit and then go on in silence;
`rested()` takes one of two code paths (at rest, or awake after 3 s) by
the time. `api.wait(300)` for "the echo of the state" (lines 129 and
145) checks absence by time.

**Proposed change.** Seam E.

**Gain.** The plugin tests check the order of events, which is the
behavior: "the call returned while the plugin was held", "the state was
applied, then the echo came, and it made no undo step".

**Risk.** Medium. The sandbox gets test commands. They exist already
(`sandbox.hang`, `sandbox.pid`), so the pattern is known.

**Size and order.** M. Fourth.

### T7. Order dependence that the TASK-121 fingerprint cannot see

**Evidence.**

- The utau vocal editor: `vocal_window()`
  (`extensions/utau/tests_singing.lua:365`) clicks before the window was
  painted. The pointer handler uses the geometry of the last paint
  (`utau/gui.lua:175`, module state). In the full suite, an earlier test
  painted, so the click lands. Under `only`, it does not. Reproduced:
  5 of 5 runs failed ("Runs", under "Measurements"). The fingerprint of TASK-121
  (options, hooks, timers, keys, extensions) does not see the state of a
  module of an extension.
- Kernel state that `T.fresh()` does not reset: the MIDI test ports
  (`api.midi_test_ports`, set in 5 files), the engine's backend
  (`tests/devices.lua:152` calls `api.engine_restart({ backend = "null"
  })`), the history of windows that `<C-w>p` reads, the step input
  bindings, the id counter of the kernel. The ids of tracks, devices,
  clips and lanes go on across tests and across `project.new()` (commit
  `546731b6`: a fixture's device got id 100, which the test also used).
  `extensions/projdiff/tests.lua` still writes literal ids (lines 110,
  120, 135, 312 to 319).
- The tutor's lesson 4, step 14 (`<C-w>p`, then play for 300 ms): it
  passed alone (3 of 3), with all lessons and with all tutor tests here.
  The probable cause is state that an earlier file leaves: the window
  history, MIDI ports, or step bindings, which decide whether step 13
  opens the list of inputs.

**Proposed change.** Add to the fingerprint of TASK-121: the MIDI test
ports, the engine backend, the timers due on the clock, the count of
windows in the history. Fix `vocal_window()` to paint first. Change the
literal ids in `projdiff` to ids taken from the kernel. Add rule 7.

**Gain.** The filter failures of TASK-121 that the options reset does
not fix are fixed.

**Risk.** Low.

**Size and order.** S. With TASK-121, or right after it.

### T8. Remote and window tests wait for time and read pixels

**Evidence.** "The Rust tests", under "Measurements". `remote.rs:256` checks "an idle
kernel sends nothing" with `quiet(400 ms)`. Lines 260 to 266 had to skip
"a state with only the levels", because a timer of the engine's rest can
push one first: two sources of messages on one stream, with no order
between them. `window.rs` reads text by OCR with four kinds of image
preparation (`screens`, line 922), and an ignored test measures how often
it reads each text. It waits 0.15 to 0.4 s after each gesture (`pause`,
42 uses).

**Proposed change.** Seam F. Keep a small number of OCR tests that check
that pixels show the text at all ("the window draws text"). Locate
everything else by `window.texts()`.

**Gain.** The window tests check what the user sees (the scene of the
window) without the uncertainty of OCR, and without time between
gestures.

**Risk.** Medium. `window.texts()` reads the scene, not the pixels, so a
bug that draws the scene wrong on the screen is caught only by the OCR
smoke tests and by screenshots.

**Size and order.** L. Fifth. The remote part (S) can go first.

### T9. The structure of the suite

**Evidence.**

- Two runner paths: `tests/tools/suite.sh` (scratch XDG folders,
  `XDG_CONFIG_HOME`, a scratch home for plugins, the stub plugin) and
  `crates/paw-tui/tests/suite.rs` (run by `cargo test`; it sets cache,
  data and state, not config, and builds in the dev profile). The two
  can give different results.
- With `PAW_TEST_BIN`, a binary older than the runtime gives Lua errors
  in each run, and the suite still says "all passed" ("Measurements",
  "Runs").
- The runner prints no time per file, so nobody can see which files are
  slow without a profile.
- Local copies of helpers: `start` in 56 files, `screen` in 37, `load`
  in 34, `wait_for` in 7. TASK-121 adds `T.start` and `T.screen`.
- 13 tests replace functions of `paw.api` (for example
  `tests/frames.lua:166` replaces `api.ui_attached` and
  `api.ui_redraw_live`). Each is a seam that exists only in a test.
  The frame tests need a ticker that a test can step: with the clock of
  T3, the ticker is a timer, and `T.advance` steps it.

**Proposed change.** `suite.rs` runs `tests/tools/suite.sh` (one
runner). The runner compares a version stamp of the kernel API with the
runtime, and fails at the start when they differ. The runner writes
`target/test-scratch/times.txt`: the wall time of each file, for
information only. The local `wait_for` copies go with T4.

**Gain.** One way to run the suite, and a clear signal when the binary
and the runtime do not agree.

**Risk.** Low.

**Size and order.** S. Any time.

## 5. The known flakes and their fixes

| Flake | Class | Root cause | Here | Fix under the design |
| --- | --- | --- | --- | --- |
| `tests/help.lua:298` "help is made at idle" | speed assertion | `T.quick` on the longest slice (40 ms) and on the first `:help` (100 ms). The slices end on wall time, and one parse of a large page has no pause (TASK-114). | 3 of 3 passed at load 16 | T1: check "no new build after it is made" (a count); the slice length goes to the bench of TASK-114. |
| Notation page speed (`tests_speed.lua`, `tests.lua:1681`) | speed assertion | `T.quick` on draw times | not run | T1: to `bench/`. |
| `tests/stretch.lua:100` to `:118` (`:111` is `clip.preview == true`) | race with a wall-time settle delay, and a live meter | The bake starts 150 ms after the request, on wall time. The test reads the state after a 60 ms sleep: under load the sleep lasts longer, and the preview is gone. The level after 60 ms depends on how many real-time blocks ran. | 2 of 2 passed | T3: the settle is on the manual clock, so the preview stays until `T.advance(150)`. T5: `T.next_block(4)`, then the level. |
| `tests/plugin_state.lua` Surge XT octave | silent poll with a time limit, two paths chosen by time, absence by time | `holds()` polls 2 s then returns; `rested()` goes on "awake" after 3 s; `api.wait(300)` for the echo | not run (needs plugins) | T6: `T.until_` on `device.state_applied`; `rested()` advances the stepped engine until the device sleeps (Surge XT CLAP never sleeps: that case gets its own test of the awake path); the echo is a message to wait for. |
| `remote.rs` levels-only state (line 260) | two sources on one stream, absence by time | A timer of the engine's rest can push a state with levels only before the state of the change. | fixed by a skip loop; `quiet()` remains 17 times | T8: `frontend.sync`; levels at a pace on the clock. |
| The tutor's lesson 4, step 14 | probable: state left by other files, and a 300 ms wait | `<C-w>p` reads the window history; step 13 depends on MIDI inputs and step bindings | 3 of 3 alone, 17 of 17 lessons, 32 of 32 tutor tests passed | T7 (fingerprint of kernel state), TASK-121, and `{ wait = N }` becomes `T.advance`. |
| utau vocal editor, two tests | order dependence through module state | The helper clicks before the first paint; the click uses the geometry of an earlier test's paint. | **reproduced**: 5 of 5 failed alone | T7: `vocal_window()` paints first; rule 7. |
| `tests/ui.lua:223` "tracks fit their height" | order dependence through options | An earlier file left options (TASK-121 names `tuimouse`). | passed alone | TASK-121 (options restored after each test). |
| `tests/scope.lua:119` "narrowing to a group" | order dependence through scope state | A window left narrowed by an earlier test. | passed alone | TASK-121 (`fresh()` widens each window). |

Two more product rules on wall time can make a test flake, with no report
yet: the double click (`mouse.tl:151`: two presses of a test that come
more than 400 ms apart under load are two single clicks), and the utau
audition throttle (`audition.lua:49`: two notes placed less than 50 ms
apart are heard once on a fast machine). Both become certain under T3.

## 6. Tests that guard no behavior (prune-tests)

Applied to the time-dependent tests only. Each line is a proposal.

- Delete the speed lines of "What moves to bench" that repeat a bench:
  `tests/search.lua:460` to `:465` (the report has the measure),
  `tests/robust.lua:125` (the whole test: `bench/edit.lua notes`
  measures the same growth; the unique ids part moves to another test).
- Delete each time comparison that is next to an outcome check, and keep
  the outcome: `tests/flow.lua:614`, `extensions/doctor/tests.lua:340`,
  `extensions/mixdiag/tests.lua:385`, `tests/robust.lua:463`,
  `tests/safety.lua:346` and `:357`.
- `extensions/notation/tests_speed.lua`: delete the file; it guards speed
  only, and the notation tests cover the drawing.
- `tests/frames.lua:199` waits two real seconds "with no key". Under T3
  it is `T.advance(2000)`. The behavior (an armed or monitored input
  keeps the screen live) stays.
- The `#[ignore]` OCR measurement (`window.rs:2177`) is a measurement,
  not a test. Move it to `bench/` when T8 is done, or delete it with the
  OCR searches.
- `extensions/utau/tests.lua:344`: keep the sound check, move the µs per
  block to a bench.

## 7. TASK-121 and the other tickets

What TASK-121 gives (commit `85456e1a` and its working tree):
`paw.option.snapshot()` and `restore()`; the options of the start given
back after *each* test (not only in `fresh()`); `fresh()` ends key
modes, closes floats and widens scopes; `T.start()` and `T.screen()`; a
leak check after each file over hooks, timers, keys and extensions, made
by test code (by the source file of a function), with
`tests/leaks-allowed.txt`; the runner gives back these registries after
each file; `suite.sh -j N` (at most 4) with a scratch folder for each
shard; the how-to page tells about `-j` and the leak check.

What this review adds on top, without a repeat:

- The fingerprint of TASK-121 sees registries. It cannot see the state
  of a module (utau's geometry) or of the kernel (MIDI test ports, the
  backend, the id counter, window history). T7 adds the kernel parts; rule
  7 covers module state.
- With the clock of T3, the leak check can list each timer of test code
  that is still due on the manual clock.
- Shards share the machine, so with today's tests `-j 4` makes timing
  flakes more frequent. The how-to page of TASK-121 says so ("a large
  `-j` slows down the tests that wait for the audio"). After T3 to T5,
  shards are safe, because no stepped test waits for wall time. So
  `-j 4` as a default can come after T5.
- A shuffled order (`suite.sh --shuffle <seed>`) is the cheapest check
  of order dependence once the leak check exists. It is in ticket P8.

| Ticket | What this review adds |
| --- | --- |
| TASK-121 (order-dependent tests, m-3) | T7: kernel state in the fingerprint; the utau helper; literal ids. Shards as default only after T5. |
| TASK-114 (help slices, m-3) | T1: the help test stops checking the slice length; TASK-114 measures it in `bench/profile`. T3: the slices read budget time from `api.real_ms()`. |
| TASK-79 (nothing over 5 ms on a key, done) | `paw.opt.budget_ms` measures budget time: it reads `api.real_ms()` under T3. |
| TASK-16 (devices sleep, done) | T5: the sleep of devices and the rest of the engine are tested on stepped blocks. |
| TASK-69 (tested as the runner, done: not adopted) | No change: the seams here are in paw's own runner. |
| TASK-42 (CI and release, m-1) | P8: the matrix that CI runs (release and dev build, one process and shards, shuffled order). |
| TASK-24 (e2e approved renders, m-6) | The e2e speed check of the keys becomes a report line (T1). |

## 8. Proposed tickets

The present review makes no tickets. The proposals below are ready to
copy. The overlaps were checked with `backlog search --plain` and
`backlog task view --plain`. The order puts the largest sources of
flakes first.

### P1 (T1, T2). Tests: no speed in pass/fail; the rules and a lint against time

- **Milestone:** m-3.
- **Description:** About 25 assertions in the suite compare wall time,
  processor time or a share of a processor with a limit (list in
  `backlog/docs/designs/test-suite-review.md`, "What moves to bench"). They fail
  under load or in a dev build. Remove each one: keep the behavior that
  it guards, count work where cost is the behavior, and move the
  measure to `bench/` where no bench has it yet. Move
  `tests/tools/speed.lua` (`T.quick`, `T.cpu_ms`) to `bench/lib.lua`.
  Write the rules of "The rules for a test" in `AGENTS.md`, in the skill
  `prune-tests` and in `docs/how-to/run-the-tests.md`. Add
  `tools/testlint.lua` with `tests/timing-allowed.txt` (today's counts),
  run it in the suite and in `nix flake check`.
- **Acceptance criteria:** (1) no `T.quick`, `T.cpu_ms`, `os.clock` or
  comparison of a time with a number in a pass/fail test; (2) each
  removed measure is in `bench/` or is already there (named in the
  commit); (3) the lint fails on a new `api.sleep(` in a test file, and
  the flake check runs it; (4) the allow-list exists, with a count per
  file and pattern; (5) `AGENTS.md`, `prune-tests` and the how-to page
  have the rules, and Vale reports 0.
- **Dependencies:** none.
- **Overlaps:** TASK-114 (the help slice test), TASK-121 (the how-to
  page, the allow-list format), TASK-24 (the e2e speed check).

### P2 (T3 and T4). Kernel: a manual clock, one turn of the loop, and quiescence

- **Milestone:** m-6 (or m-3 if the owner puts test reliability before
  the m-3 speed work; question 1).
- **Description:** Add a trait `Clock` in `paw-core` with `WallClock` and
  `ManualClock`, held by `Shared`. `api.now()`, the timers, the settle of the
  bake scheduler, the file watch, the state lanes and the autosave
  read it. Add `api.real_ms()` for budget time, and move the budget
  readers to it (`limit.tl`, `slices.tl`, `profile.tl`, the slice end of
  `help.tl`, `derived.tl` timings, `paw.opt.budget_ms`). Move the body of
  `api.wait` into one turn of the loop; add `api.step()` and
  `api.pending()`. `paw --clock manual` selects the manual clock. In
  `tests/suite.lua`, add `T.settle`, `T.advance`, `T.advance_until`, and
  make `T.until_` fail on quiescence. Under the manual clock,
  `paw.wait(ms)` advances virtual time and settles. The runner starts
  paw with `--clock manual`. Add the product part of the lint
  (`api.now()` in a budget reader fails).
- **Acceptance criteria:** (1) the bake scheduler test of
  `bake/scheduler.rs` runs with no sleep; (2) the suite passes with
  `--clock manual`, with tests that need real time marked live; (3)
  `T.until_` fails at once, with "nothing is left to do", on a condition
  that never holds; (4) a test of the double click, the audition
  throttle and the stretch preview, each with `T.advance`; (5) the suite
  runs faster than before (number in the commit, for information); (6)
  `docs/reference/api.md` documents `api.real_ms`, `api.step`,
  `api.pending`, and the how-to page documents the helpers.
- **Dependencies:** none. Better after P1 (fewer tests to touch).
- **Overlaps:** TASK-114, TASK-79, TASK-121 (the leak check lists timers
  due).

### P3 (T5). Engine: a stepped audio backend for the tests

- **Milestone:** m-6.
- **Description:** Add the backend `step`: no thread; the kernel calls
  `engine.process()` on its own thread when `T.advance` or
  `T.next_block` asks. One block moves the manual clock by its length.
  The runner uses `--audio step` with `--clock manual`. Change the tests
  that read a live meter after a sleep (69 meter reads in 24 files) to
  stepped blocks, or to `paw.render`.
- **Acceptance criteria:** (1) `T.next_block(n)` runs exactly `n`
  blocks, with no wall time; (2) two runs of a test that plays and reads
  a meter give the same value, to the bit; (3) the `no_alloc` tests pass;
  (4) `tests/realtime.lua` stays live, with its one-sided check.
- **Dependencies:** P2.
- **Overlaps:** TASK-16.

### P4 (T4). The waits of the tests become steps, file by file

- **Milestone:** m-6.
- **Description:** With P2 and P3 in place, change the tests that the
  lint allow-list names, in the order of the table "What the Lua tests do
  with time": `guides`, `guides_howto`, `offline`, `safety`, `core`,
  `input`, `doctor`, `flow`, `plugin_state`, `attr`, `scope`,
  `complete`, `stretch`, then the rest. The steps `{ wait = N }` of the
  tutor's lessons become `{ advance = N }`. Delete the 7 local
  `wait_for` helpers. Mark the live tests (target: fewer than 60). In
  parts of a few files each; agents can do parts side by side.
- **Acceptance criteria:** (1) the allow-list of the lint has no line
  for a stepped test; (2) `suite.sh -j 4 --shuffle <seed>` passes three
  times with three seeds; (3) the full suite passes in a dev build and in
  a release build; (4) each part names the tests that it pruned and why.
- **Dependencies:** P2, P3, P5 for the plugin files.
- **Overlaps:** TASK-121.

### P5 (T6). Plugins and helpers: handshakes for the tests

- **Milestone:** m-6.
- **Description:** Sandbox test commands `hold`, `release`, `hang`
  (until ended) and `deadline` (for one device). An event
  `device.state_applied` with a sequence number. A ready line and
  acknowledgments for the helper processes and for the mock servers of
  the tests. Change `tests/offline.lua`, `tests/safety.lua`,
  `tests/plugin_state.lua` and `extensions/plugstate/tests_tone3000*.lua`
  to them.
- **Acceptance criteria:** (1) no finite injected delay compared with a
  deadline in a test; (2) the plugin state tests wait for
  `device.state_applied`, and fail with a message that names the device
  when it does not come; (3) "six plugins are made at the same time" is
  checked with `hold`, with no time.
- **Dependencies:** P2.
- **Overlaps:** none.

### P6 (T7). Tests: kernel state in the leak check, the utau helper, literal ids

- **Milestone:** m-3 (with TASK-121).
- **Description:** Add to the fingerprint of TASK-121 the MIDI test
  ports, the engine backend, the timers due, and the window history.
  `vocal_window()` in `extensions/utau/tests_singing.lua` paints before
  it clicks. The `projdiff` tests take ids from the kernel. Write rule 7
  in the how-to page.
- **Acceptance criteria:** (1) `suite.sh only "the vocal editor"` passes;
  (2) the leak check names a test that leaves a MIDI test port; (3) no
  literal kernel id in a test (the lint can check `id = <number>` in
  files that build projects).
- **Dependencies:** TASK-121.
- **Overlaps:** TASK-121 (can be its last part).

### P7 (T8). Remote and window tests: barriers, the window's texts, counts for idle

- **Milestone:** m-6.
- **Description:** A request `frontend.sync` and sequence numbers on
  pushed states; change the 17 `quiet()` checks to it. Window control
  requests `window.sync`, `window.texts()` and `window.counts()`. Locate
  text by `window.texts()`; keep a few OCR smoke tests. Change the CPU
  tests to counts between two barriers; the shares of a processor go to
  `bench/profile`.
- **Acceptance criteria:** (1) no `quiet(Duration)` in `remote.rs` and
  `protocol.rs`; (2) no `pause()` after a gesture in `window.rs`; (3) at
  most 5 tests use OCR; (4) `cargo test -p paw-gui` passes three times
  in a row at load 30 or more (one run of the owner's choice).
- **Dependencies:** none for the remote part; P2 for the kernel side of
  the window part.
- **Overlaps:** TASK-42.

### P8 (T9). The suite: one runner, a binary check, times per file, shuffle

- **Milestone:** m-6.
- **Description:** `crates/paw-tui/tests/suite.rs` runs
  `tests/tools/suite.sh`. The runner fails at the start when the kernel
  API stamp and the runtime differ (`PAW_TEST_BIN`). The runner writes
  the wall time of each file to `target/test-scratch/times.txt`
  (information only, not a failure). Add `suite.sh --shuffle <seed>`. Write
  the matrix that CI runs (TASK-42): release and dev build, `-j 1` and
  `-j 4 --shuffle`.
- **Acceptance criteria:** (1) an old binary with a new runtime fails at
  the start with a clear message; (2) `times.txt` exists after a run;
  (3) `--shuffle` prints its seed, and the same seed gives the same
  order.
- **Dependencies:** TASK-121 (shards). The matrix is useful after P4.
- **Overlaps:** TASK-121, TASK-42, TASK-69.

## 9. Questions for the owner

1. **May the test seams (P2, P3) go before the open m-3 speed work?**
   They touch `paw-core` and `paw-engine`, and the focus order says m-2,
   m-3, m-4 and m-9 come first. Recommended: P1 and P6 now in m-3
   (cheap; they remove the reported flakes); P2 and P3 next, before more
   tests are written on wall time; P4, P5, P7, P8 in m-6.
2. **Option A: may `api.now()` become the schedule clock, with a new
   `api.real_ms()` for budgets?** It changes the meaning of a public
   call. Recommended: yes. No release is tagged, so no compatibility is
   needed, and most callers mean schedule time.
3. **May tests stop checking speed, with no exception?** Rule 7 (a key
   well under 100 ms) is then guarded only by `bench/` and the profiles.
   Recommended: yes. Add a bench report to the release check (TASK-42)
   that shows the key times against rule 7, as a report, not a failure.
4. **May the window tests find text through the window's own list
   (`window.texts()`) and keep OCR only for a few smoke tests?**
   Recommended: yes. OCR stays where the pixels themselves are the
   behavior.
5. **A live tier: may about 3 % of the tests keep the wall clock, if
   they check outcomes only?** Recommended: yes. Real time is the
   behavior of the transport and of the plugin sandbox, and a one-sided
   check ("not faster than real time") cannot fail from load.
6. **Shards by default?** Recommended: keep one process as the default
   until P4 is done, then make `-j 4` the default.
7. **The clock seam: the crate `metrique-timesource`, or a small own
   `Clock` trait?** The crate sets a clock for one thread, from Rust
   code. paw needs one clock for the process, chosen on the command line,
   moved from Lua, and read by several threads. Recommended: an own trait
   with two adapters (`WallClock`, `ManualClock`), passed to each reader.
   Look at the crate again if paw gets a Rust library that reads time on
   its own threads and accepts the crate's override.

## Owner decisions (2026-11-22)

The owner approved every recommendation of this document and of the
other testing document ([test-suite-review.md](test-suite-review.md),
[testing-practices.md](testing-practices.md)), as each document
recommends:

- An own small `Clock` trait (`WallClock`, `ManualClock`), not the
  crate `metrique-timesource`.
- `api.now()` becomes the schedule clock, which a test can control. A
  new `api.real_ms()` gives wall time for budgets.
- No speed checks in tests at all. Speed goes to `bench/`.
- A live tier of about 3 % of the tests.
- Shards (`suite.sh -j 4`) as the default only after P4 (TASK-149).
- Golden files for the terminal screen.
- insta and proptest as dev-dependencies.
- A fuzz crate outside the default members of the workspace.
- A quarantine list of flaky tests. Each entry has a ticket, and the
  list can only get shorter.
- The nightly checks run in CI only.
- **The window is paused.** The owner: "We are deprioritizing work on
  paw-gui, we focus on terminal-first right now. Tests for paw-gui
  should not be run until we decide to work on it again. It should also
  not be built until then." paw-gui is not a default member of the
  workspace. Each window ticket has the priority low, and its title
  starts with "Window (paused):".

The tickets (the milestone "Better testing" is m-12). P1 to P8 are the
tickets of the review; BT1 to BT12 are the tickets of the practices
document.

| Ticket | Source | Milestone | Priority | Depends on |
| --- | --- | --- | --- | --- |
| TASK-143 No speed checks; the rules and a lint against time | P1 (T1, T2) | m-3 | High | none |
| TASK-144 Kernel state in the leak check, the utau helper, no literal ids | P6 (T7) | m-3 | High | TASK-121 |
| TASK-145 The tiers, written, and a quarantine list | BT1 | m-12 | High | none |
| TASK-146 A manual clock, one turn of the loop, quiescence | P2 (T3, T4) | m-12 | High | TASK-143 |
| TASK-147 A stepped audio backend | P3 (T5) | m-12 | High | TASK-146 |
| TASK-148 Handshakes with plugins and helpers | P5 (T6) | m-12 | Medium | TASK-146 |
| TASK-149 The waits become steps; a live tier of about 3 % | P4 (T4) | m-12 | Medium | TASK-146, 147, 148, 151 |
| TASK-150 Remote: a sync barrier in place of quiet periods | P7, remote part (T8) | m-12 | Medium | none |
| TASK-151 Lua runner: one path, binary check, times, repeat, shuffle, CI output | P8 (T9) and BT9 | m-12 | Medium | TASK-121 |
| TASK-152 Golden files for the terminal screen | BT4 | m-12 | High | none |
| TASK-153 Null tests of the engine | BT2 | m-12 | Medium | none |
| TASK-154 One integration-test binary for paw-engine | BT3 | m-12 | Low | none |
| TASK-155 insta snapshots for the text formats | BT5 | m-12 | Medium | none |
| TASK-156 Property tests for the model and the file formats | BT6 | m-12 | Medium | TASK-145 |
| TASK-157 Contract test of the API boundary | BT7 | m-12 | Medium | none |
| TASK-158 One check helper and text fixtures for key tests | BT10 | m-12 | Low | none |
| TASK-159 Fuzz targets for input from outside | BT11 | m-12 | Medium | TASK-145 |
| TASK-160 Window (paused): kittest, smoke tests with a sync barrier and counts | P7, window part (T8) and BT8 | m-12 | Low | TASK-146 |

Merged: P8 and BT9 are one ticket (TASK-151). The window part of P7 and
BT8 are one ticket (TASK-160), with kittest in place of `window.texts()`.
BT12 (the two skills) is done in the setup commit: the skills
`rust-testing` and `lua-testing` exist, and each ticket that adds a
helper changes them in the same commit. The items under "Later" of the
practices document have no ticket yet.

Notes in the existing tickets, in place of duplicates: TASK-121,
TASK-114, TASK-42, TASK-24 and TASK-133.
