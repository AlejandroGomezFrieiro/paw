# Event loop review: is paw a game loop, and what to do about it

Superseded where it differs by [architecture-plan.md](architecture-plan.md) (2026-11-23).

Review and design only. No tracked file changed. Nothing was built.
Internal text, in Simplified Technical English.

The states of the code that this review reads:

| Name | Ref | What it adds |
| --- | --- | --- |
| main | `7228146b` | The product as the owner builds it. |
| B17 | `2f70b19f` | Batch 17: `--clock manual`, `api.now` and `api.real_ms`, `T.advance`, timers and watchdogs on the wall clock, `paw.limit`. |
| STEP | `worktree-agent-a23815c420af4a2d3` (`422ae4b8`) | `--audio step`, `Stream::run_to`, `api.wait_blocks`, stepped blocks in `Session::idle`, the device watch and the file check on the schedule clock, `Watch::next_due`; merged with TASK-148 (`device.state_applied`, `Controller::state_pending`, `sandbox.hold/release/hang/deadline`). |
| HASH | `worktree-agent-a0784eed8c6c33c77` (`63545f9c`) | `api.pending().hashing`, the hash worker at once, `T.settle` in more files. |
| RUNNER | `worktree-agent-a8062e24546374fe4` (`29d60d1d`) | `tests/suite.lua` with quarantine, shuffle, repeat. |

A reference `file:line` is at main unless it names a ref (`STEP:`,
`B17:`, `HASH:`). The earlier designs
[test-suite-review.md](test-suite-review.md) (the clock seam, quiescence)
and [testing-practices.md](testing-practices.md) are the start of this
work. The present review does not repeat them.

## Rust refinement (2026-11-23)

[The Rust refinement](rust-architecture.md) changes the Rust shapes of this review. What changed:

- `Upkeep` has `fn kind()`, not `const KIND`, so it is dyn-compatible. `poll` gives `Outcome` values that the session applies; no `UpkeepCx` of borrows.
- `ScheduleTime` is a type; the clock is `enum Clock { Wall, Manual }`, not `Arc<dyn Clock>` with `manual()`.
- `Agenda` has a union (`|`) and `quiet()`.
- `KernelMsg::Wake` becomes a `Doorbell`: an atomic bit set of `Woken` kinds and one `mio::Waker`. The audio thread only sets a bit (CLAP `request_callback` runs on any thread).
- The main loop waits in `mio::Poll`; the `inotify` descriptor is a token, so the `inotify` thread goes. The browser build keeps `recv_timeout`.
- Clippy's `disallowed_methods` replaces `tools/clocklint`.

## 0. Verdict

paw is not a game loop with a physics engine. It is a reactor (one
thread that sleeps until a message or a deadline, like Neovim's `libuv`
loop) beside a fixed-step real-time engine (like JUCE or REAPER), and the
tests drive it as a discrete-event simulation (virtual time that jumps
to the next deadline). The audio boundary, the pub/sub of events and the
"one turn is one undo step" rule are sound and need no change. What is
not sound is at the edges: two copies of the turn, a 16 ms poll in place
of wake-ups, six clocks with no rule for which one a subsystem reads,
and the definition of "nothing is left to do" lives in the test runner
and not in the kernel.

The recommendation: no rewrite. Do a consolidation in six bundles:
one turn function, one clock rule, one agenda (next due, in flight) that
the product loop and the tests both read, wake-ups in place of the
16 ms poll, an honest stepped backend, and fault injection at a seam.
Each bundle leaves paw working, and each deletes code.

Of the architectures compared in part 3, the best fit is a hybrid that
paw nearly has: actors at the process and thread borders, one event loop
with turns on the main thread, a fixed-step engine on the real-time
thread, and virtual time for the tests.

## 1. Terms

| Term | Meaning |
| --- | --- |
| Turn | One pass of the main thread: take messages, fire timers, do upkeep, deliver events, close the undo step. One user action is one turn. |
| Upkeep | The polls in `Session::idle` (devices.rs:582): takes, renders, transport state, preview, plugin loads, bakes, device watch, file watch, plugin scan. |
| Schedule time | The time that decides *when* a thing happens (a timer, a delay, a timeout). `Clock::now` (clock.rs). |
| Budget time | The time that measures *how long* work took (a slice, the Lua limit). `Instant`, `api.real_ms`. |
| Block time | The audio engine's time: blocks processed, samples played. |
| Agenda | (Proposed.) What a subsystem tells the loop: work is ready now, work is in flight elsewhere, or the next due time. |
| Quiet | (Proposed.) No work ready, no work in flight. Only deadlines are left. The earlier design calls it "quiescence". |
| Wake | (Proposed.) A message that a worker thread or process sends to the main thread when its work ends. |

## 2. What the system is today

### 2.1 Threads and queues

```text
 terminal thread ──Input──┐
 rpc threads ─────Rpc/Gone┤                          ┌─────────────── main thread (Kernel) ──────────────┐
 MIDI-in thread ──Midi────┤  mpsc<KernelMsg>         │ Lua state (mlua, !Send)                           │
   (+ Mutex<VecDeque>)    ├────────────────────────▶ │ Session (RefCell)                                 │
 helper output ───Output──┘  kernel.rs:173           │ timers: Vec<Timer>, linear scan (api/timers.rs)   │
                                                     │ doc.events: Vec<ModelEvent> (turn-local queue)    │
                                                     │ Lua handlers: paw.on / paw.emit (events.tl)       │
                                                     └──┬────────────▲──────────────┬───────────▲────────┘
                         rtrb Msg (SPSC, no lock) ──────┘            │ polled       │ polled    │ polled
                         rtrb Garbage (back) ◀───────────────────────┤ in idle      │ in idle   │ in idle
                         Shared atomics (meters, position, blocks) ──┘              │           │
   ┌───────────── audio thread (cpal callback, or null clock thread) ─┐             │           │
   │ Engine::process: fixed blocks, no lock, no alloc, no wait        │             │           │
   │ STEP: on the main thread inside Session::idle (run_to)           │             │           │
   └──────────────────────────────────────────────────────────────────┘             │           │
   bake workers + bake helper processes ── mpsc "ended" (scheduler.rs:277) ─────────┘           │
   hash worker (media/sources.rs) ── channel, polled in events_take ─────────────────────────── ┤
   plugin loads (Starting::poll), render thread (render_job), inotify fd (nonblocking) ──────────┤
   CLAP plugin: request_callback flag, timers and file descriptors of its editor (clap/host.rs:128,187) ──────┘
   watchdog thread (paw.limit): sets a Lua hook from outside on overrun
```

Only five sources wake the main thread: terminal input, RPC, a closed
connection, MIDI in, and helper output (`KernelMsg`, kernel.rs:93-101).
Every other completion (a bake, a hash, a plugin load, a render, a file
change, a take that closes, a plugin's `request_callback`) sets a flag
or fills a channel that nothing selects on. The loop sees it only at the
next upkeep.

### 2.2 The two loops

The product and the tests run two different turn functions.

```text
 PRODUCT  Kernel::run (kernel.rs:666-735)          SCRIPT/TEST  Shared::turn (api/timers.rs:74-91)
 ───────────────────────────────────────           ─────────────────────────────────────────────
 wait = min(next Lua timer,                         (no wait: api.step = one turn;
            16 ms if needs_idle())                   api.wait = turns + clock jumps, or
   (work().next_due is NOT read)                     turns + 1 ms sleeps on the wall)
 recv_timeout(wait)                                  
 handle(msg); drain try_recv()                       timers due → fire
   Input → K.key …; Midi → hear_midi                 idle? → Session::idle (STEP: blocks first)
   Output → hear_output; Rpc → request()             hear_midi
     (request() closes its own turn)                 hear_output
 timers due → fire                                   Lua settle → session.checkpoint
 every 16 ms → Session::idle                         (no render, no messages, no reload, no quit)
 Lua settle → session.checkpoint
 monitor.keep_fed
 reload? quit? → exit event
 dirty? → render (each seat)

 Lua settle (init.lua:505-545), the same in both:
   up to 64 rounds: api.events_take()  ← also writes automation, flushes edits
                                         to the engine, reads ahead, polls media
                    → derived.taken → hooks.note → paw.emit
   hooks.turn: up to 8 rounds of edit.before / edit.after (may discard the step)
   scene.turn, remote.turn, collector.turn
```

The order differs: the product hears MIDI before the timers, the test
loop after them. The product reads upkeep each 16 ms, the test loop at
each turn. The test loop does not render, take a message or run
`request()`.

### 2.3 The clocks

| Clock | Source | Owner | Who reads it |
| --- | --- | --- | --- |
| Wall | `Instant::now` | nobody | Kernel::run idle period (kernel.rs:667-711), undo sweep merge (session/document.rs:184-208), automation touch release (session/write.rs:93-218), hash scan "twice a second" (media/sources.rs:54), bake progress throttle (session/stretching.rs:523-528), render progress (session/render.rs:810), read-ahead while playing (session/media.rs:523), audition end (session/audition.rs:302), state settle (session/statelanes.rs), plugin load waits (session/loading.rs:223-242) |
| Schedule | `Arc<dyn Clock>`: `WallClock` or `ManualClock` (clock.rs) | kernel, given once | Lua timers, `api.now`, bake settle (scheduler.rs:304), file watch settle; STEP adds device watch, file check, stepped blocks. Each holds its own `Arc` copy, set by `Session::set_clock` (STEP: schedule.rs) with a `WallClock` default in each `Default` implementation. |
| Budget | `api.real_ms` (= `Shared::started.elapsed()`) | kernel | `paw.limit`, `paw.slices`, `derived.tl`, help index, collector (fixed in B17), grep reader (fixed in B17) |
| Block | engine `Shared` counters | audio thread | `api.blocks`, meters, transport position; the runner's `next_block` |
| Stepped block | `Steps.since` + `Stream::end_of` | session | STEP: `run_stepped_audio`, `api.wait_blocks` |
| Startup | `startuptime` | kernel | `--startuptime` only |

The design rule exists in a comment (clock.rs:1-10): "a time that
measures work is wall time; a time that decides when is schedule time".
Nothing checks it. The Lua side was audited in B17. The Rust side was
not: ten behavior sites in `paw-core` still read `Instant` for a
"when". In the product this changes nothing (schedule = wall). Under
`--clock manual` with `--audio step`, these sites run on a different
time than the sound and the timers.

### 2.4 Push and pull, by subsystem

| Subsystem | Wakes the loop? | Next due known? | Counted in `pending`? | Polled where |
| --- | --- | --- | --- | --- |
| Keys, RPC, MIDI in, helper output | yes (`KernelMsg`) | n/a | `midi`, `helpers` | message |
| Lua timers (`paw.defer`, `paw.every`) | yes (`recv_timeout`) | yes | `timers`, `timers_due`, `next_ms` | each turn |
| Bakes (stretch) | no | settle only (scheduler) | `bakes_running`, `bakes_waiting` | idle |
| Hash worker | no | no (wall 500 ms scan) | HASH: `hashing` | `events_take` |
| Plugin loads | no | no | `plugin_loads` (STEP: minus held) | idle |
| Render | no | no | `renders` | idle |
| File watch (`inotify`) | no | yes (settle) | `files` | idle |
| Device and port watch | no | STEP: yes | no | idle |
| Takes closing | no | no | no (runner reads `transport_get().closing`) | idle |
| Plugin `request_callback`, editor timers and file descriptors | no | no | no | idle (`controller.idle`) |
| Audio engine | no | n/a (it runs by itself) | no (runner reads transport and preview) | atomics |
| GC and idle jobs (`paw.slices`) | timer | yes | as timers (runner names `collector`) | timer |

The product loop hides the "no" column with a fixed 16 ms poll:
`needs_idle()` (session/devices.rs:804-810) is true while any device has
a controller (any plugin), any load runs, any render runs, any take
closes, or `watching()` (session/watch.rs:96-101) is true, which is the
case for every real audio device and every MIDI input. So in daily use
the main thread wakes about 60 times a second for the life of the
session. The bench measured idle only with `--audio null` and no
plugins ("kernel 0 %", `bench/RESULTS.md:1307`). The common case is not
measured.

When `needs_idle()` is false (null backend, no plugin, no MIDI input:
a headless server, a laptop with no device), a bake that ends, a hash
that arrives or a file that changes on disk waits for the next key or
timer. The product loop does not read `work().next_due`
(kernel.rs:680-690), so a bake settle of 150 ms or a file settle of
300 ms does not wake it either. The gap is a latent bug. It hides because
the 16 ms poll nearly always runs.

### 2.5 Where it is incoherent

**P1. Two turn functions.** `Kernel::run` (kernel.rs:666-735) and
`Shared::turn` (api/timers.rs:74-91) do the same job with a different
order and a different set of steps. Two `IDLE_PERIOD` constants
(kernel.rs:34 at 16 ms, api/timers.rs:17 at 15 ms). The Lua suite runs
paw with `-l tests/suite.lua` (tests/tools/suite.sh:109-111), so no Lua
test runs `Kernel::run`: the product loop is tested only by the e2e
scenarios and the remote tests.

**P2. A poll in place of wake-ups.** See 2.4. The 16 ms poll costs CPU
in the common case (a plugin loaded, a real device), and it is the only
reason the product sees background completions. The poll works against the
owner's goal "devices sleep, beat REAPER at idle".

**P3. Quiet is defined in the test runner.** The kernel gives eleven
counters (`Pending`, api/timers.rs:44-66; HASH adds `hashing`). The
runner decides what they mean: `working()` sums five of them and
subtracts the `collector` job by name (HASH:tests/suite.lua:175-178);
`active()`/`busy()` reads the transport and the preview; `settle()`
gives up after `POLL_TURNS = 1000` turns with only timers due
(STEP:tests/suite.lua:214); the kernel has the same guard again as
`TURNS_AT_ONE_INSTANT = 1000` (B17:api/timers.rs:22). `quiet()` plays
up to `ENGINE_BLOCKS = 200` blocks (STEP:tests/suite.lua:348).
`catch_up` has wall-time guards of 250 ms and 50 ms that change the
result, not only stop a stall (HASH:tests/suite.lua:281-282).

The runner knows it is on the manual clock because `api.now() == 0` at its
start (STEP:tests/suite.lua:169). Each new kind of background work needs
a new counter and a runner edit: `hashing` was added in HASH to fix one
flake (commit `249e9de9`), after the earlier design chose "each
subsystem reports its own count" (`test-suite-review.md:451-454`).

**P4. Clocks read with no rule.** See 2.3. The undo merge of a sweep
(`SWEEP_GAP`, session/document.rs:184) decides the undo step on the
wall clock: rule 6 ("one action is one undo step") depends on a time
that a test cannot step. Automation touch (`TOUCH_RELEASE`,
session/write.rs:218) decides what is written on the wall clock while
the stepped engine plays on the schedule clock. Read-ahead while playing
(session/media.rs:523) is throttled on the wall clock: in a stepped test
one second of song can pass in a few wall milliseconds with one
read-ahead.

**P5. One word for several things.** "Settle" names the end of a turn
(`Kernel::settle`, kernel.rs:492), the delivery of events
(`settle` in init.lua:505, also `paw.flush`), quiet in the tests
(`T.settle`), a delay before work starts (`SETTLE` in scheduler.rs:32, 150 ms, and
in files_watch.rs, 300 ms), a wait for plugins after a state
(`Settle` in statelanes.rs), and `layout.settle`, `lsp.settle`. "Idle"
names the upkeep (`Session::idle`), the GC job's idle work, and
"no CPU". The overload breaks the STE rule "one word for one thing", and it
hides which job runs when.

**P6. A query that does work.** `api.events_take`
(api/processes.rs:101-110) writes automation, pushes edits to the
engine, reads ahead and polls media before it gives the events. So
`paw.flush()` from any handler pushes to the engine in the middle of a
turn. The hash worker is polled there and not in upkeep (HASH:
session/media.rs:585-590).

**P7. Hidden order in the end of a turn.** Events are delivered first
(init.lua:532-535), then `edit.before` may refuse the edit
(hooks.tl:136-150), which discards the undo step after other handlers
have already acted on its change events. Three fixed-point loops with
magic bounds sit inside one turn: 64 rounds of events, 8 rounds of
edits, and (tests) 1000 turns at one instant.

**P8. Test-only paths in the product.**
- STEP: `null_steps` (session/engine.rs:28, 392 to 395): once a test asked
  for the stepped backend, each later restart on `null` is stepped. A
  sticky flag that changes what a word means.
- STEP: the stepped backend opens as `Null` (`StreamInfo::backend` says
  `null`, backend.rs), so `engine_get()` needs a second field `stepped`.
- STEP: `StartTest` is a parameter of the engine trait
  `DeviceFactory::start` (paw-engine/src/device.rs:766-781): a test knob
  in the signature that every device kind implements.
- STEP: `KIND_TESTS`, a global `Mutex<BTreeMap>` (sandbox/mod.rs:111),
  environment variables `PAW_PLUGIN_TEST_HANG` and `PAW_PLUGIN_HOST_HANG`,
  `LoadTest` in the session (session/loading.rs:143), and `in_flight()`
  that leaves held loads out of the work count.
- main: `midi.test_ports` and `api.midi_test_ports`
  (api/engine.rs:234), which also make `watching()` true.
- STEP: `api.wait_blocks` returns 0 and does nothing when the engine is
  not stepped: a silent no-op.

Fault injection is legitimate. The problem is where it sits: in trait
signatures, global values and environment variables, and not at one seam.

**P9. Blocking waits on the main thread.** `:engine threads=` sleeps up
to 500 ms for the audio thread (runtime/lua/paw/defaults/project.lua:
358 to 363). On the stepped backend the audio thread is the main thread,
so that wait can never end early: it sleeps 500 ms and reports the old
count. The same pattern is in `Session::await_loads` and
`await_load` (session/loading.rs:223-242), utau (engine.lua:190-198, up
to 120 s; init.lua:697-706), vinput (run.lua:254-257, 349 to 352) and the
LSP (lsp/init.tl:1368-1372). A key that runs one of these freezes the
screen and breaks rule 7.

**P10. The stepped backend makes the main thread the audio thread.**
STEP: `run_to` sets `audio_thread::Mark` on the main thread
(backend.rs). An in-process CLAP plugin that checks its thread is then
on both. The double role is fine for the tests that use it now. It is a risk for
any test of a real in-process plugin under `--audio step`.

**P11. Things that work only because of the runner.** The stretch
preview showed "not stretched" in the turn where a hash came in (fixed
in HASH, commit `63545f9c`). Shuffle found that `:messages` compared two
times that are equal on the manual clock (HASH: views/cmdline.lua).

Both were real product bugs that the virtual clock exposed. The good
news: the manual clock finds bugs. The bad news: each one was found by
a flake, one at a time.

## 3. Which architecture fits paw?

The owner asked for a real comparison. Each candidate below is judged
against paw's constraints:

- **RT**: the audio thread takes no lock, no allocation and no wait.
- **Key**: a key stays well under 100 ms.
- **Idle**: redraw on change; devices sleep; low CPU when nothing changes.
- **Undo**: one user action is one undo step.
- **Plugins**: in-process plugins, and plugins in sandbox processes that
  can crash or stop answering.
- **Lua**: Lua extensions hook in everywhere, with synchronous handlers.
- **Tests**: tests give the same result each time.
- **Desktop**: a single-user desktop program, not a server. Few
  concurrent jobs; a short delay for the user comes before throughput.

### 3.1 The actor model (Erlang and `Akka`; in Rust `actix`, `ractor`, or threads with mailboxes)

An actor owns its state, takes messages from one mailbox, and talks to
others only by messages. A supervisor restarts an actor that crashed.

**What is an actor in paw already.**

| Part | Actor? | Evidence |
| --- | --- | --- |
| Sandbox plugin host | Yes: a process, its own state, messages on a socket and shared memory. | `crates/paw-plugins/src/sandbox/mod.rs:1-30` |
| Bake helper processes, other helper processes | Yes: processes with pipes; output wakes the main thread (`KernelMsg::Output`). | `crates/paw-core/src/io.rs`, `kernel.rs:226-230` |
| Bake native workers | Yes: a job in, one `ended` message out. | `bake/scheduler.rs:13-16, 277` |
| Hash worker | Yes: paths in, records out. | `media/sources.rs` |
| Render thread | Yes: its own engine copy; progress by a shared value, the result by a join. | `session/render.rs` |
| Audio engine | Almost: it owns its state and takes `Msg` from one SPSC mailbox (`rtrb`). But the main thread reads its state through shared atomics (meters, position, blocks), not by messages. | `paw-engine/src/engine/handle.rs:15-20`, `engine/mod.rs:75-76` |
| Terminal, RPC connections | Yes: threads that send `KernelMsg`. | `kernel.rs:93-101`, `rpc.rs:387, 460` |
| Session and Lua | No: one owner on the main thread, `RefCell`, synchronous calls. | `kernel.rs:131-145` |

**Supervision.** Today a crashed sandbox host is found by its exit
signal (`sandbox/controller.rs:152-155`), the device is marked stopped,
the track plays on without it, and the user restarts it with
`:device.restart` (`defaults/devices.lua:74-83`). The session is a supervisor
with a "restart by hand" policy. An automatic policy (restart once, then
give up, as Erlang's `one_for_one` with a restart intensity) is a small
add to `Session::scan_devices` (`session/devices.rs:600-640`). It needs
no actor framework.

**What actors cost here.**
- **Undo.** An undo step is a snapshot of one `Project` (`session/document.rs:157-210`).
  If tracks or clips were actors, one action would touch several of them,
  and one undo step would need a transaction across actors. That is a
  two-phase commit inside a desktop program.
- **Lua.** `mlua` state is not `Send`. Every `paw.api` call is
  synchronous and returns a value now (`api/*.rs`). With actors each call
  becomes a request and a reply that comes later, and each Lua handler a callback
  or a coroutine. Every extension changes.
- **Determinism.** Mailboxes on many threads deliver in an order that the
  scheduler picks. Tests would need a deterministic actor scheduler.
- **Key latency.** A key that reads three actors waits for three round
  trips. Small, but it adds to each key, for no gain on one user.

**Verdict.** Use the actor model at the process and thread borders,
where paw already uses it. Add one thing it lacks: each actor sends a
`Wake` to the main thread when it has a result (see "Wakes, and the safety poll").
The session, the model and Lua stay out of the actor model. A
framework (`actix`, `ractor`) adds nothing over threads with channels
for eight workers: no new dependency.

### 3.2 CSP: channels and a select loop, as in `crossbeam` and Go

Processes share nothing and talk over channels; one loop `select`s on
many channels and a timer.

**Fits.** The main loop is already this, with one channel: all producers
send `KernelMsg` into one `mpsc` (`kernel.rs:173`), and the loop waits
with `recv_timeout` (`kernel.rs:690`). One channel with an `enum` is a
`select` over many channels, merged at the sender. The engine's `rtrb`
queues are CSP on the real-time side.

**Does not fit.** Several channels in a `select` give no order between
channels; with one channel, the order is the order of arrival, which is
what paw wants. `crossbeam::select!` would let the bake `ended` channel
(`bake/scheduler.rs:277`) and the hash channel wake the loop without a
`Wake` message, but each new worker then edits the select in
`Kernel::run`. The `Wake(kind)` message keeps one channel and one place.

**Verdict.** paw is CSP at its borders already. The label adds nothing
except the lesson that every channel must be in the select: the polled
channels of 2.4 break that rule. The fix is the same as in 3.1.

### 3.3 A single-threaded event loop with deferred work (Neovim's `libuv` and `vim.schedule`, Node, REAPER's defer, the message thread of JUCE)

One thread owns the state. It sleeps in one wait on all sources (file
descriptors, timers, wakes from other threads). Callbacks run to the end.
Work for later goes to a queue (`vim.schedule`, `setImmediate`,
`MessageManager::callAsync`).

**Fits.** paw is this model. `Kernel::run` is the loop
(`kernel.rs:666-735`), `paw.defer(fn, 0)` is `vim.schedule`
(`init.lua:80-88`), `paw.wait` is `vim.wait` (`api/timers.rs` `wait`),
`paw.slices` is work cut in slices between keys (`slices.tl:1-12`), the
watchdog is Neovim's `vim.wait` interrupt in another form. Lua handlers
run to the end, synchronously, which the Lua constraint needs. One owner
gives the undo step for free: the turn is the transaction
(`Kernel::settle`, `kernel.rs:492-498`).

**Does not fit, today.** Three gaps against the model:
1. Not every source is in the wait. Bakes, hashes, loads, renders,
   `inotify` and the CLAP callback request are polled each 16 ms
   (`session/devices.rs:582-598`, `needs_idle` at 804 to 810). In `libuv`
   each would be a handle (`uv_async_t` for a thread, `uv_poll_t` for
   the `inotify` descriptor), and the loop would sleep.
2. Two loop bodies (P1). Neovim has one; `vim.wait` runs the same loop.
3. Blocking waits on the loop thread (P9). In Node or Neovim these are
   bugs by definition.

**Cost to finish.** Bundles S1 and S3. No new dependency: the wakes go
through the existing channel; `inotify` gets a small thread or a
`rustix` poll.

**Verdict.** The best fit for the main thread. paw is already this
model with three gaps. The label is the useful one: it names the rules
(one wait on all sources, callbacks run to the end, no block on the loop
thread) that the gaps break.

### 3.4 The Elm architecture and Redux: one model, messages, an update, a view

One immutable model. Each message goes through a pure `update` that
gives a new model and a list of effects. `view` is a pure function of
the model.

**Where paw leans this way already.**
- The undo step is a snapshot of the whole `Project`
  (`session/document.rs:197-208`), as the time travel of `Redux` keeps states.
  `Arc` sharing makes it cheap, as persistent data does in Elm.
- Change events go out after the edit, at the end of the turn
  (`init.lua:505-545`), which is "effects after update".
- Scenes: a view is drawn once in Lua and the kernel sends it to each
  frontend as data (`scene.tl:437`, and the page "About scenes").
  That is `view` producing a value, with the frontend as the runtime.

**Does not fit.**
- `update` in paw is not pure and not one function: Lua handlers and
  commands call `paw.api` setters anywhere in a turn
  (`api/tracks.rs`, `api/clips.rs`). To make it pure, every edit becomes
  a message type and every extension command an `update` case. That is
  a rewrite of the runtime and of every extension.
- Views read state outside the model (engine meters, the playhead, the
  derived graph). Elm handles that with subscriptions; paw's live parts
  of the screen (`render_live`, `kernel.rs:609-620`) do it already.
- The message log of `Redux` gives replay only when all inputs are messages.
  Worker results and clocks are not, today.

**Verdict.** Keep what paw took from it: snapshot undo, effects at the
end of the turn, views as data. A full Elm or Redux move costs a rewrite
and buys replay that paw does not need now. The label adds nothing to
the turn as paw has it, but it supports one rule: an edit's events must
go out after the edit is final. P7 (`edit.before` after delivery) breaks
that rule.

### 3.5 Discrete-event simulation (one priority queue of timed events, a virtual clock)

Events wait in a queue by time. The simulator takes the first, moves the
clock to its time, runs it, and repeats. Nothing happens between events.

**Fits.** The tests. `api.wait` on the manual clock moves from one due
time to the next and runs a turn at each (`api/timers.rs:126-142`). STEP
puts the audio blocks on the same clock (`STEP:session/schedule.rs:65`).
`T.advance_until` jumps to `next_ms`. The test loop is a DES already, and the
paused clock of `tokio` works the same way ("when idle, jump to the next
timer").

**Does not fit.**
- Work on other threads and processes finishes at wall time, outside
  the queue. A full DES (FoundationDB, TigerBeetle) runs every worker
  inside the simulation, with a seeded scheduler. For paw that means
  bakes, hashes, plugin hosts and helper processes simulated or run
  inline. Too much: a plugin host is a real process.
- Timers are a `Vec` with a linear scan (`api/timers.rs:21-40`), and the
  Rust deadlines are not in it at all; `work().next_due` collects them
  only for the tests (`session/schedule.rs:39-51`). One agenda fixes it.
- The product must not run as a DES: a key must run at once, not at a
  simulated time.

**Verdict.** Use DES for the tests, on the same loop as the product:
virtual time is a clock choice, not a second loop. The "physics engine"
feeling the owner noticed comes from here. Stop at "workers wake when
done; the simulator waits for the wake". Do not try to simulate workers.

### 3.6 A fixed-timestep game loop with a physics step, and ECS (Bevy)

The loop runs at a fixed rate: read input, step the simulation by `dt`
(with smaller steps if behind), render, sleep the rest of the frame. ECS
keeps the state as components in tables that systems iterate.

**Fits.** The audio engine is a fixed-step simulation: blocks of N
frames, at the device's rate, no allocation (`engine/process.rs`). The
UI ticker draws at a frame rate while something moves and stops when
nothing moves (`ui.tl:2060-2080`). STEP's `AUDIO_TURN` of 100 ms is a
"physics step" in the test loop (`STEP:api/timers.rs:26`).

**Does not fit.**
- **Idle.** A game loop ticks when nothing changes. paw must sleep. The
  16 ms `needs_idle` poll (`session/devices.rs:804-810`) is the one
  part of paw that behaves like a game loop, and it is the part that
  costs CPU at idle.
- **Key.** A key would wait for the next tick. paw runs it at once.
- **ECS.** A project is a tree (tracks, clips, devices, nests) with
  undo by snapshot (`model.rs`). ECS gives fast iteration over many
  small entities each frame, which paw does not do on the main thread.
  Undo and serialization of ECS worlds are hard. The scheduler of `Bevy` runs
  on many threads and owns `main`, which fights `mlua`.

**Verdict.** Wrong model for the main thread. Right model for the audio
engine, which already is one. The label "game loop" adds nothing and
points the wrong way: it would add ticks where paw wants sleep.

### 3.7 Data flow and FRP: signals and incremental computation

Values derive from other values; a change propagates to what depends on
it; unchanged results stop the propagation (early cutoff).

**Fits.** paw has an incremental computation graph: `paw/derived.tl`
records what each entry read, marks dependents stale on edit events, and
remakes them in slices with early cutoff on inputs and on values
(`derived.tl:1-30`, design `derived.md`). The graph is `Salsa` or `Adapton`,
in Lua. The `stamp` of events (`events.tl` `M.stamp`) is a cheap
version check for memos. Scenes and redraw on change are a push of
"dirty" to the frontends.

**Does not fit.**
- As the whole architecture: edits, undo and plugins are imperative and
  ordered. FRP glitches (a value seen half updated) are avoided in paw
  by the turn: events go out at its end. A global signal graph would
  need its own transaction rule, which is the turn again.
- The derived graph's job runs in slices on timers. Its work in flight
  is a timer to the runner today; in the target design it is an idle job
  with an agenda.

**Verdict.** Keep data flow where it is: derived data (chords, region
tree, query indexes) under the turn. Do not make it the frame of the
program. The derived graph is one `Upkeep` in the agenda (see "One way to report work").

### 3.8 Rust `async`: `tokio` and structured concurrency

Tasks are futures on an executor; I/O and timers are awaited; structured
concurrency ties child tasks to a scope.

**Fits.** paw uses `tokio` already for I/O that waits: the control
socket, TLS, helper process pipes (`io_runtime.rs`,
`crates/paw-core/Cargo.toml:48`). The I/O border is the right place for it. `tokio`'s
paused test clock is the model for `--clock manual` plus auto advance.

**Does not fit.**
- **RT.** The design puts no executor on the audio thread.
- **Lua.** An `mlua` state on a `LocalSet` can run `async` callbacks, but
  each `paw.api` call that awaits makes Lua handlers `async` and the turn
  no longer runs to the end. The undo step would span awaits.
- **Idle and determinism.** A runtime on many threads adds wake-ups and an
  order of tasks that tests do not control. A current-thread runtime is
  just the event loop of 3.3 with `async` syntax.

**Verdict.** Keep `tokio` at the I/O border. Do not move the main loop
to it. If the main loop ever needs to wait on many file descriptors, a
current-thread `tokio` runtime could be its wait; that is an
implementation of 3.3, not a new architecture.

### 3.9 The candidates against the constraints

`+` fits, `0` neutral or partial, `-` conflicts. "Cost" is the cost to
move all of paw to that model.

| Candidate | RT | Key | Idle | Undo | Plugins | Lua | Tests | Desktop | Cost |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Actors, everywhere | 0 | 0 | + | - | + | - | - | 0 | Very high |
| Actors at borders only | + | + | + | + | + | + | 0 | + | Low (exists; add wakes) |
| CSP, select loop | + | + | + | + | + | + | 0 | + | None (exists) |
| Event loop with deferred work | + | + | + | + | + | + | + | + | Low (S1, S3) |
| Elm, Redux, full | + | 0 | + | + | 0 | - | + | + | Very high |
| Discrete-event simulation, tests | + | n/a | n/a | + | 0 | + | + | + | Low (the quiet bundle) |
| Discrete-event simulation, product | + | - | + | + | - | 0 | + | - | High |
| Fixed-step game loop, ECS | + (engine) | - | - | - | 0 | - | + | - | Very high |
| Data flow, FRP, whole program | + | 0 | + | - | 0 | - | 0 | + | High |
| Data flow for derived data | + | + | + | + | + | + | 0 | + | None (exists) |
| Rust `async`, main loop | - | 0 | 0 | - | 0 | - | - | + | High |
| Rust `async` at the I/O border | + | + | + | + | + | + | 0 | + | None (exists) |

### 3.10 The best fit: a hybrid, with its borders

```text
 ┌── process border ── actors with supervision ─────────────────────────────────────┐
 │  sandbox plugin hosts, bake helpers, other helper processes                      │
 │  (crash → device stopped → restart by hand today; restart policy optional)       │
 └────────────────┬──────────────────────────────────────────────────────────────────┘
                  │ messages + Wake(kind)
 ┌── thread border ── actors / CSP ─────────────────────────────────────────────────┐
 │  terminal, RPC (tokio I/O), MIDI in, bake workers, hash worker, render, inotify  │
 └────────────────┬──────────────────────────────────────────────────────────────────┘
                  │ one channel: KernelMsg (FIFO)
 ┌── main thread ── one event loop, one agenda, turns ──────────────────────────────┐
 │  turn = messages → upkeep → timers → close (push to engine, deliver events,      │
 │         edit hooks, scenes, undo step)                                            │
 │  inside: Elm-like rules (effects after the edit, views as data, snapshot undo)   │
 │          data flow for derived data (derived.tl), in slices                       │
 │  clock: wall in the product, manual in tests (DES: jump to the next due time)    │
 └────────────────┬──────────────────────────────────────────────────────────────────┘
                  │ rtrb Msg (SPSC), garbage back; atomics to read
 ┌── real-time border ── fixed-step engine ─────────────────────────────────────────┐
 │  Engine::process(block): state + messages taken at block start → sound           │
 │  no lock, no allocation, no wait; on --audio step, run by the loop at due times  │
 └───────────────────────────────────────────────────────────────────────────────────┘
```

The rules at each border:
- **Process and thread border.** Share nothing mutable with the main
  thread except through a message or a value the worker owns until it
  sends it. Each result sends a `Wake`. A crash is a message, not a
  panic on the main thread.
- **Main thread.** One loop body. One clock rule. A callback runs to its
  end. No wait on another thread (P9). One turn is one undo step.
- **Real-time border.** The engine is a function of its state and the
  messages it takes at the start of a block. The main thread reads its
  results through atomics and never waits for a block, except in tests,
  where the loop runs the blocks itself.

The hybrid is paw today, minus the gaps that "What the system is today"
lists. No candidate asks for more than the bundles of the migration plan.

## 4. Is a proper architecture good value now?

### 4.1 The options

| Option | Cost | Gain | Risk |
| --- | --- | --- | --- |
| A. Leave it, write it down | One page. | People stop guessing the order of a turn. | Each new background job adds a counter, a runner edit and a flake. The 16 ms poll stays. The latent bug in 2.4 stays. |
| B. Small targeted fixes only | Days. Clock audit in Rust, rename "settle", remove `null_steps`, fix P9's 500 ms wait. | Fewer clock bugs; clearer words. | P1, P2 and P3 stay: the cause of the churn stays. |
| C. Consolidation: one turn, one agenda, wakes | About six bundles (the migration plan), each one agent. | One definition of quiet in the kernel; the runner shrinks; the product sleeps with a plugin loaded; the latent bug goes; new work needs one trait implementation, not a counter and a runner edit. | A missed wake stalls the screen until a key. A safety poll that counts misses makes it visible. |
| D. Rewrite (TEA, actors, a deterministic simulator) | Weeks, all of the runtime. | Replay, full determinism. | Breaks every extension. No user gain now. |

### 4.2 What each option buys, honestly

- **Determinism and fewer flakes.** B gives some. C gives the most that
  is possible without D: the kernel, not the runner, says when it is
  quiet, so `T.settle` cannot be wrong about a kind of work it does not
  know. Work on threads still ends at wall time; C waits for its wake
  in place of counting turns.
- **Fewer counters.** Only C. Eleven fields become three (ready,
  in flight by kind for messages, next due). The runner loses
  `working`, `busy`, `POLL_TURNS`, the `collector` name and most of
  `catch_up`.
- **Simpler reasoning.** C: one turn function with one written order.
- **CPU at idle.** Only C. Today a session with one plugin wakes 60
  times a second. After C it wakes for a plugin's own timers and for
  an open editor only. This needs a measurement before and after
  (bench, not a test).
- **Replay and record of sessions.** Not bought by any option short of
  D. C makes a log of `KernelMsg` plus clock reads possible, which is
  enough for a bug report ("these keys at these times"), not for an
  exact replay: worker completions still race.
- **Offline render as the same path.** Small. The stepped backend and
  the render loop (session/render.rs `play`) both drive
  `Engine::process` block by block. They can share the block driver
  (`NullBlocks`). Render must stay on its own thread with its own
  engine: it must not hold the main thread.

### 4.3 Recommendation

**Option C, without its tail.** The core design is sound; the cost is
in the edges, and the edges are where every recent ticket of the test
work went. Do bundles S1 to S4 in order. S5 and S6 are small and can go
in any batch after S1. Do not start D. Do not rename the public Lua API.

What breaks under C, and how it shows:
- A subsystem that does not send its wake: its result shows at the next
  key or safety poll, not at once. A Rust test for each worker checks
  the wake (invariant I4), and the safety poll counts misses.
- A plugin that needs regular idle with no editor open and no timer: it
  stops getting it. Keep the 16 ms idle for a plugin that asks (an open
  editor, an LV2 worker, a VST3 that needs it). Measure first.
- Tests that assumed the old turn order (MIDI after timers in scripts):
  some may change. S1 lists them.

## 5. The target design

### 5.1 The one loop

```text
                     ┌───────────────────────── Kernel::run ─────────────────────────┐
                     │ loop {                                                         │
 KernelMsg ──────────┼─▶ wait until: a message, or agenda.next_due, or 16 ms while    │
 (Input, Rpc, Gone,  │     a plugin asks for idle; forever when nothing is due        │
  Midi, Output,      │   turn(now)                                                    │
  Wake(kind))        │   if dirty: render each seat                                   │
                     │ }                                                              │
                     └────────────────────────────────────────────────────────────────┘

 turn(now)  — the one function; run, api.step, api.wait, api.settle and request() call it
 ────────────────────────────────────────────────────────────────────────────────────────
  1. take messages (input, RPC, MIDI, helper output, wakes)    ← push
  2. upkeep: each Upkeep::poll(now) that is ready or woken      ← pull, but only when due
       (STEP: the stepped engine runs its blocks up to `now` first)
  3. fire Lua timers due at `now`, in due order
  4. close the turn:
       a. push edits to the engine (flush, automation, read-ahead)
       b. deliver events (rounds, bound 64)
       c. edit hooks (edit.before may discard; rounds, bound 8)
       d. scenes and remote state
       e. close the undo step
  5. agenda = union of the timers and each Upkeep::agenda()
```

`request()` keeps its barrier: an RPC request closes the turn of the
keys before it, and its own turn closes before its answer. It calls
`turn` steps 4 and 5 and does not repeat 1 to 3.

`api.events_take` stops doing work: step 4a is the kernel's, and
`paw.flush` calls a new `api.flush` (4a) and then delivers. The name
`paw.flush` stays.

### 5.2 The clocks, and who owns each

| Clock | Owner | Rule | Check |
| --- | --- | --- | --- |
| Schedule (`Clock`) | Kernel. One `Arc<dyn Clock>`. The session gets `now` as an argument of `Upkeep::poll(now)`; subsystems keep no clock of their own. | Every "when": timers, delays, throttles, sweeps, touch release, watch periods, progress rates. | `tools/clocklint`: no `Instant::now` or `.elapsed()` in `paw-core/src/session`, `model`, `media`, `bake`, `sync` except an allow-list of budget sites. |
| Budget (`Instant`, `api.real_ms`) | Nobody; read where work is measured. | Every "how long": `paw.limit`, slices, profiles, deadlines for another process. | The allow-list above names each one with a reason. |
| Block | Audio engine. | The engine's own time. The main thread reads it and does not wait on it. | P9 sites move to an event or to `T.next_block`. |
| Stepped block | Session, from the schedule clock. | On `--audio step`, blocks end at schedule times; `run_to(now)` in step 2. | Existing STEP test `a_stepped_stream_runs_each_block_once_at_its_end`. |

### 5.3 Queues, and their order

The main thread has three queues, in this order in a turn:

1. **Messages** (`mpsc<KernelMsg>`). FIFO. `Wake(kind)` is new; wakes
   of one kind coalesce (a flag per kind and one message, as `AsyncUpdater`
   does in JUCE).
2. **Timers** (Lua timers and nothing else; a `BinaryHeap` keyed by
   `(due, id)` in place of the linear `Vec` scan). Same due time: the
   order of `timer_start`.
3. **Events of the turn** (`doc.events`). Delivered in step 4b, in the
   order they were emitted.

Rust deadlines (delays, watch periods) are not timers. They are the
`next_due` of an `Upkeep`. The loop takes the minimum.

The audio queues (`rtrb` `Msg`, garbage, MIDI) do not change.

### 5.4 One way to report work: the agenda

```rust
/// What a part of the session tells the loop about its work.
pub(crate) struct Agenda {
    /// Work that the next turn can do now (a result came in, a debounce ended).
    pub ready: bool,
    /// Work in flight on another thread or process: it sends `Wake(kind)` when it ends.
    pub in_flight: usize,
    /// The next schedule time at which `poll` has work, if any.
    pub next_due: Option<Duration>,
}

/// A part of the session with work outside the turn.
pub(crate) trait Upkeep {
    const KIND: WakeKind;
    fn poll(&mut self, cx: &mut UpkeepCx<'_>);   // cx: now, events out, engine link
    fn agenda(&self) -> Agenda;
}
```

Eight implementations now: bakes, hash worker, plugin loads, render,
file watch, device and port watch, takes closing, plugin controllers.
Eight implementations pass the "two adapters now" rule for a trait. `Session::idle`
becomes a loop over them. `needs_idle` goes. Lua timers give their own
`Agenda`. Idle jobs (`paw.slices`, the GC job, the help index) mark
their timer `idle = true`: their timers do not count as ready for
quiet, by flag, not by name.

`api.pending()` keeps its name and gives `{ ready, quiet, next_ms,
in_flight = { bakes = n, loads = n, … } }`. The kinds are for messages
and `:checkhealth`, not for the runner's logic.

### 5.5 Wakes, and the safety poll

Each worker gets a `MainWaker` (a clone of the `Sender<KernelMsg>` and a
coalescing flag). It calls `wake()` when its work ends:

| Worker | Where it wakes |
| --- | --- |
| Bake native thread, bake helper | after it sends on `ended` (bake/scheduler.rs) |
| Hash worker | after it posts a record (media/sources.rs) |
| Plugin start | when `Starting::poll` would give a result (the start thread) |
| Render | at each progress step it wants told, and at its end |
| `inotify` | a small thread blocks on its file descriptor and wakes |
| Take closing | the record thread, when the take is let go |
| CLAP `request_callback` | `clap/host.rs:128` sets the flag and wakes |
| CLAP editor timers and file descriptors | their `next_due` is in the controller's agenda |

The product keeps a **safety poll** while any `in_flight > 0`: one turn
each 250 ms. If that turn finds a result with no wake before it, the
kernel counts a missed wake and writes the kind in the log once. The
suite fails a run with a missed wake (a check, not a timing). The count makes
the risk of option C visible.

### 5.6 How tests drive it, with no test-only branch

The tests run the same `turn` as the product. The only differences are
the clock (`--clock manual`) and the backend (`--audio step`), both
chosen at start on the command line (`tests/tools/suite.sh`). The
tests do not switch them at run time.

- `api.settle()` (new, Rust): turn until not `ready`; while
  `in_flight > 0`, block on the message channel for a `Wake` (wall stall
  guard 30 s), then turn again. Returns the agenda. No virtual time
  passes. This replaces `T.settle`'s loop, `working`, `POLL_TURNS` and
  the `collector` name.
- `api.wait(ms)` on the manual clock: settle; then while the next due
  time is within `ms`, move the clock to it, turn, settle. The stepped
  engine runs its blocks in step 2. `AUDIO_TURN` stays as the bound
  while the engine plays (a smaller step).
- `T.until_(cond)`: settle; if `cond` is false and quiet with no due
  time and the engine does not play, fail ("nothing is left to do").
  `api.pending().quiet` answers it. `ENGINE_BLOCKS` stays only while
  the engine plays.
- `api.clock()` gives `"manual"` or `"wall"`, in place of
  `api.now() == 0`.

### 5.7 How the real-time engine fits

It does not change. The audio thread takes no lock, no allocation and
no wait. The main thread never waits on it; P9's waits become either an
event (`engine.started` already exists; the thread count can come with
it) or a step in tests. The stepped backend is a real backend
(`StreamInfo::backend = Step`), and it shares the block driver with the
offline render (`NullBlocks`).

### 5.8 What Lua sees

No API is removed. The changes:

- `paw.on`, `paw.emit`, `paw.defer`, `paw.every`, `paw.cancel`,
  `paw.wait`, `paw.flush`: the same.
- `paw.slices` and other idle work: their timers pass `idle = true`
  (internal; the public signature does not change).
- `api.pending()`: new fields `ready`, `quiet`; the old count fields stay
  under `in_flight` (a Teal type change; `tools/apidoc.lua` regenerates
  api.md).
- `api.settle()`, `api.clock()`: new.
- A reference page "the order of a turn" (external,
  docs/reference/), from the picture of the one loop, for extension authors.

### 5.9 Invariants, each with a check

| # | Invariant | Check |
| --- | --- | --- |
| I1 | One turn function. `run`, `step`, `wait`, `settle` and `request` close a turn only through it. | A Rust test drives `Kernel` with a recording `Frontend` and a fake clock through `run` for N messages and through `api.step`; the order of the hooks it records is the same. |
| I2 | Every "when" reads the schedule clock. | `tools/clocklint` (Rust grep with an allow-list), in the suite and the flake check. |
| I3 | A quiet kernel sleeps: no turn without a message or a due time. | A Rust test: a session with a null controller and a fake device, after `settle`, has `agenda.next_due == None` and `in_flight == 0`; the loop's wait is "forever". |
| I4 | Work in flight always wakes. | A Rust test for each `Upkeep` with a fake worker: after it ends, a `Wake` of its kind is on the channel. The suite fails on a missed wake (5.5). |
| I5 | The manual clock moves only in `wait`, and only forward. | Existing test in clock.rs; plus a lint: no `advance_to` outside api/timers.rs. |
| I6 | One user action is one undo step. | Existing tests (undo); the sweep merge gets a test on the manual clock (possible after S2). |
| I7 | The turn order is written once. | The reference page and the Rust test of I1 name the same steps. |
| I8 | No test knob in an engine trait or a global. | `StartTest` and `KIND_TESTS` gone after the fault injection bundle; a grep check in `testlint` for `PAW_PLUGIN_TEST`. |
| I9 | Idle CPU with a plugin and a device is measured. | bench/: wakes per second and CPU over 30 s, before and after S3. A measurement, not a test. |

## 6. Migration plan

Each bundle leaves paw working, has its own tests, and is one agent.
Merge STEP, then HASH, then RUNNER first (they conflict in
`api/timers.rs`, `session/schedule.rs` and `tests/suite.lua`).

### S1. One turn (Rust: kernel.rs, api/timers.rs, init.lua)

- Make `Kernel::turn(now)` with the order of 5.1. `Kernel::run`,
  `api.step`, `api.wait` (both clocks) and `request` call it. Scripts
  drain the message channel too (only `Midi` and `Output` come there
  when `scripted`, because the socket is off: main.rs `serve_listeners`).
- Move step 4a out of `api.events_take` into the turn and a new
  `api.flush`.
- Rename: `Kernel::settle` → `close_turn`; the Lua `settle` → `deliver`;
  the delay constants → `DEBOUNCE`. `T.settle` keeps its name (it is
  the test word for quiet).
- Deletes: `Shared::turn`, `wait_on_the_wall`'s own idle bookkeeping,
  the second `IDLE_PERIOD` (api/timers.rs:17), `TURNS_AT_ONE_INSTANT`
  (moves to one place).
- Tests: the I1 test. Run the full suite; list the tests whose result
  changed with the order.

### S2. One clock rule (Rust: session/*, media, bake; a lint)

- `Upkeep::poll(now)` style for the existing polls: pass `now` from the
  kernel in place of the `clock` field in `FileCheck`, `Watch`, `Steps`,
  `FileWatch` and the bake scheduler.
- Move to the schedule clock: `SWEEP_GAP` (document.rs:184-208),
  `TOUCH_RELEASE` (write.rs:93-218), the hash scan (sources.rs:54), the
  bake and render progress rates (stretching.rs:523-528,
  render.rs:810-811), read-ahead (media.rs:523), the audition end
  (audition.rs:302).
- Add `tools/clocklint` with the allow-list (loading.rs waits,
  render.rs measures, `statelanes.rs` `Settle` which waits for another
  process).
- Deletes: five `clock: Arc<dyn Clock>` fields and their `WallClock`
  defaults; `Session::set_clock`'s fan-out.
- Tests: the sweep merge on the manual clock (I6), touch release with
  `T.advance`.

### S3. The agenda and wakes (Rust: session, bake, media, plugins)

- The `Agenda` and `Upkeep` of 5.4; eight implementations.
- `MainWaker` and `KernelMsg::Wake(kind)`; the wakes of 5.5; the safety
  poll and the missed-wake count.
- `Kernel::run` waits on `min(timer due, agenda next_due)`, and on 16 ms
  only while a controller asks (open editor, LV2 worker, a VST3 that
  needs it).
- Deletes: `needs_idle`, the fixed 16 ms poll for devices and the
  watch, `Work`'s per-kind fields as logic (they stay as `in_flight`
  counts).
- Tests: I3, I4. Bench: I9 before and after, in the bench results.
- The riskiest bundle. Do it after S1 and S2, alone in its batch.

### S4. Quiet in the kernel (Rust: api/timers.rs; Lua: tests/suite.lua)

- `api.settle()`, `api.clock()`, `api.pending().ready/quiet` (5.6).
- `T.settle` calls `api.settle`. `T.until_` uses `quiet`.
- Deletes in the runner: `working`, `busy`, `POLL_TURNS`, the
  `collector` name, `MANUAL = api.now() == 0`, most of
  `catch_up_on_the_wall` (it stays only for live tests).
- Idle jobs mark their timers `idle = true` (`paw.slices`, collector,
  help).
- Docs: the lua-testing skill, the how-to on tests, the new reference
  page on the order of a turn.

### S5. An honest stepped backend (Rust: paw-engine backend, session/engine.rs; Lua: one command)

- `StreamInfo::backend = Step`; `engine_get().stepped` goes.
- `engine_restart` with no backend keeps the current one; delete
  `null_steps`. The tests that restart with `null` name no backend.
- suite.sh starts paw with `--audio step`; the runner does not restart
  the engine at its start.
- `:engine threads=` stops its 500 ms wait (defaults/project.lua:358 to 363):
  it says the count asked and the next `engine.started` or the status
  line says the count that runs.
- Share `NullBlocks` with the offline render's block loop if the
  signatures fit; if not, leave it.
- `api.wait_blocks` fails with a message when the engine is not stepped,
  in place of returning 0.

### S6. Fault injection at one seam (Rust: paw-plugins sandbox, paw-engine device)

- Remove `StartTest` from `DeviceFactory::start`. The create deadline
  becomes a product option (the limit for a plugin to start, today the
  constant `CREATE_LIMIT`), which a test sets lower.
- The stop-answering fault and hold go to one `FaultPlan` that the sandbox registry gets at
  its construction when paw starts with `--test-faults` (a hidden flag),
  or to the stub CLAP plugin as its own behavior. `device_call`
  commands `sandbox.*` stay as the way a test asks.
- Deletes: `KIND_TESTS`, `PAW_PLUGIN_TEST_HANG`, `PAW_PLUGIN_HOST_HANG`,
  `LoadTest` in the session.
- Optional. Do it when a sandbox ticket touches these files anyway.

### What stays as it is

- The audio engine, its queues and its rest.
- `paw.on`/`paw.emit` and the kernel event list.
- `paw.limit` and the watchdog thread.
- The redraw on change (`dirty`, `live_dirty`, the ticker in ui.tl).
- Helper processes and the I/O runtime.

## 7. Risks and open questions for the owner

1. **The name and the model.** Do you accept "a reactor with an agenda,
   a real-time engine beside it, virtual time in tests" in place of "a
   game loop"? Recommendation: yes. It matches the CPU goal; a game loop
   does not.
2. **Plugin idle at 60 Hz.** S3 stops calling `controller.idle` at
   16 ms for a plugin with no open editor and no timer. Some plugins may
   expect it. Recommendation: measure the wakes with five common plugins
   first; keep the 16 ms idle per controller that asks, not for all.
3. **The safety poll.** 250 ms while work is in flight, with a
   missed-wake count that fails the suite. Recommendation: keep it
   forever; it costs nothing when nothing is in flight.
4. **Fault injection in the product.** A hidden `--test-faults` flag, or
   the stub plugin only? Recommendation: the stub plugin for a helper that stops answering, a
   product option for the deadline, and `sandbox.hold` behind the flag.
5. **Record and replay of sessions.** Not part of this plan.
   Recommendation: after S1, add an optional log of `KernelMsg` and
   clock reads for bug reports. Exact replay needs D; the cost is too high.
6. **The order change in S1.** Scripts will hear MIDI before timers, as
   the product does. Recommendation: accept; the product order is the
   truth.
7. **`edit.before` after delivery (P7).** Today a refused edit has
   already been delivered to other handlers. Moving `edit.before`
   before delivery changes what extensions see. Recommendation: do not
   change it now; write it in the reference page, and open a ticket.
8. **Timing of this work.** The owner's focus order puts m-2, m-3, m-4
   and m-9 first. Recommendation: merge STEP, HASH and RUNNER now (they
   are done); do S1 and S2 in the next batch (small, low risk); S3 and
   S4 after the focus milestones, as their own milestone; S5 with S1;
   S6 when a sandbox ticket comes.
