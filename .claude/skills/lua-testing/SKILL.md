---
name: lua-testing
description: "How to write and change Lua and Teal tests in paw: the runner and its helpers (T.test, T.fresh, T.keys, T.render, T.until_, T.settle, T.advance, T.advance_until, T.next_block), the manual clock and live tests, real keys, the state that a test makes and puts back, self-contained tests that read nothing of the machine, sound, the screen, skips, flakes, and what a test must not do. Use it for each change of tests/, extensions/*/tests*.lua or the lessons of the tutor, and for each review of Lua tests."
---

# Lua tests in paw

Use this skill for each change of `tests/*.lua`,
`extensions/*/tests*.lua` or the lessons of the tutor. It adds to part 3
of `paw-code`. The skill `prune-tests` tells which tests to delete. For
the Rust tests, use `rust-testing`.

Two designs are the source of this skill. One is a review of the test
suite (the rules for time). The other is research on the practices of
other projects.

## 1. The runner

- `tests/suite.lua` is the runner. paw runs it as a `-l` script, in the
  kernel. All test files run in one process, in order: `tests/*.lua`,
  then `extensions/<name>/tests*.lua` for each extension.
- Each file starts with `local T = ...` and takes the helpers from `T`.
- `T.test(name, fn)` adds a test. `T.last(name, fn)` adds a test that
  runs after all the others.
- The name is a sentence about the behavior, for example "a double
  click on empty space selects the phrase there". `only` filters by the
  words of the name.
- `cargo test -p paw-tui --test suite` runs `tests/tools/suite.sh`. The
  two use one runner, one set of folders and the same passes.
- At the start, the runner compares the binary with the runtime. Each
  function of `paw.api` that `runtime/types/paw.lua` declares must be in
  the binary. An old binary (`PAW_TEST_BIN`) with a new runtime fails
  "the binary has the kernel API of the runtime", and no test runs.
  Build paw again, or use a binary of the same commit.
- Each run writes `target/test-scratch/times.txt`: the wall time of each
  test file, the slowest first. It is information only. A time does not
  fail a test.
- Each run writes `target/test-scratch/suite.tap` for CI: each test with
  its result, and the reason of each skip.
- `tests/runner.lua` tests the runner. It runs a second paw on test
  files in a scratch folder (`PAW_TEST_FIXTURE`, see `tests/suite.lua`).

## 2. The helpers

Use the helpers of `T`. Do not copy them into a file (a local `start`,
`screen` or `wait_for`).

| Helper | Use |
| --- | --- |
| `T.fresh()` | A new project, the start layout with no popped-out view and no window history, normal mode, no float and no quickfix list. Call it first in each test that needs a project. |
| `T.start()` | `T.fresh()`, then `<Esc><Esc>`: the start of a test that types keys. |
| `T.screen(w, h)` | The text of the screen, 120 by 40 if no size is given. |
| `T.hover_text()` | The text of the float of `K` (`paw.ui.hover`): the title, then the lines. |
| `T.after(fn)` | Put back what the test changed. It runs after the test, also after a failure. |
| `T.keys(text)` | Feed keys through the keymap, as the user types them (`"<Esc>dd"`). |
| `T.eq(got, want, what)`, `T.near(got, want, tolerance, what)` | Compare a value. `what` tells what the value is. `T.eq` compares two tables by their values (deep). |
| `T.fails(fn, pattern, what)` | `fn` gives an error that matches `pattern`. |
| `T.expect_error(pattern)` | The test gives an error on the message line that matches `pattern`. Without it, such an error fails the test. |
| `T.render(opts)` | Render offline to a file under `T.scratch`. The result does not depend on the machine. |
| `T.frequency(info, from, to)`, `T.channel_peaks(info, from, to)` | Read a render. |
| `T.tone`, `T.three_clips`, `T.melody`, `T.layout`, `T.roll_notes` | Fixtures. |
| `T.until_(cond, what)` | Settle, then check a state. While the state waits for the engine (a meter, a device that sleeps, the playhead), the engine plays block by block, and the clock moves with it. Fails with "nothing is left to do, and <what> is false" when no work is left, after about 2 s of blocks. While the song plays, it fails after 30 s of the song. |
| `T.settle()` | Turn the loop until the due timers fired and the bakes, plugin loads, renders and measurements ended, and the files of stretched clips have a hash (`api.settle()`). The loop sleeps until each worker rings when its work ends. The clock does not move. Idle work (a job of `paw.slices` with `idle`, as the collector) and a job that polls at no delay are not work. Gives `api.pending()`: `quiet` is true when nothing is in flight, no helper works and the engine plays nothing. |
| `T.advance(ms)` | Move the clock `ms`: each timer and settle delay fires in its order, the engine plays the blocks of that time, then the kernel settles. |
| `T.advance_until(cond, what, ms)` | Move the clock from one due time to the next until `cond` holds. With no timer, or while a helper or the engine plays, a step is one audio block. While a helper owes an answer (`helpers_busy` of `api.pending()`), the clock does not move: the wait is for the helper, up to the stall guard. Fails after `ms` of schedule time. |
| `T.next_block(n, device)` | Play exactly `n` blocks (1 if not given), so that a change sent before is in effect. The clock moves by their time. With `device`, play until that device ran `n` blocks: a device that sleeps does not count them. |
| `T.meter(part)` | The left and right peaks of a meter after the blocks that played last. It fails on the manual clock when the engine is not on the stepped backend. Use it, not `:meter()`. |
| `T.level(part, side)` | The peak level of the part after one more block: the left side, or the right with `side` 2. Read a level only with it, for example in `T.until_`. |
| `T.stepped()` | True when the engine plays on the stepped backend. |
| `T.until_beat(beat, rounds, ms)` | Play until the playhead is at `beat`, after `rounds` times round the loop. Fails after `ms` of the song (30 s if not given). |
| `T.wakes(fn, device, ...)` | Run `fn`, and give `true` or `false` for each device: did it make sound then? Each device sleeps through silence first, and a device that wakes runs blocks. It reads no meter. |
| `T.until_meters_at_rest()` | Wait until no meter of the engine shows a level. A meter falls while the engine plays blocks: the sound of a test before can still show. A loud meter falls for longer than one `T.until_`, so the clock moves block by block for at most 5 s. Then it puts out the held peaks and clip lights of the screen. Use it before a test draws or compares a meter, or waits for the engine to rest. |
| `T.scratch`, `T.read_file`, `T.write_file` | Files of the test. |
| `T.home(dir)` | Make `HOME` a folder of the test until it ends (part 4). |
| `T.expect_screen(name, w, h, opts)` | Compare the screen with a golden file (part 7). |
| `T.check_keys(fixture, keys, expected, what)` | Make the project of a text fixture, type `keys`, and compare the project with the expected fixture (part 5). |
| `T.fixture(text)`, `T.fixture_text()` | Make the project of a text fixture, and give the project as a fixture. |

## 3. Start clean and put back

A test makes all the state that it reads.

- Start from `T.fresh()`. Set each option that the test needs. Do not
  rely on an option, a window or a mode that an earlier test left. The
  runner gives back the options of the start of the run after each test.
  `T.fresh()` does not change the options: an option that the test set
  before it stays until the test ends.
- After each file of `tests/`, and after the files of each extension, the
  runner unloads the extensions that the tests loaded and removes the
  hooks, timers and key mappings that test code made. It also puts back
  the audio engine, the MIDI test ports, the step input controls that
  Lua bound, the parts that the engine plays from a file, and the plugin
  folders and plugin kinds. The leak check names the first test that
  changed them (not for the plugins: it reads them once for each file). A test file that
  leaves one fails "`<part>` leaves no state behind". Do not add a line to
  `tests/leaks-allowed.txt`.
- Take ids from the kernel (the value that a call returns). Never write
  a literal id of a part, a device, a clip or a lane.
- Write files under `T.scratch`. Never write in the checkout or in the
  owner's folders.
- Put back what you change with `T.after`: options, keys, hooks, timers,
  MIDI test ports, the engine backend, extensions that you loaded, plugin
  folders that you added (`paw.plugins.remove_dir`).
- Paint a view before a click in it. A handler can use the geometry of
  the last paint, which an earlier test made.
- A test passes alone, under each `only` filter, and in any order.

## 4. Self-contained

The owner's rule: a test is fully self-contained. It does not depend on
the owner's computer or folders. Mock what it needs.

- A test reads nothing of the machine: not the home folder
  (`os.getenv("HOME")`, `~`), not the installed plugins (`CLAP_PATH`,
  `VST3_PATH`; a yabridge bridge in `~/.vst3` starts wine), not the user
  name, not the system fonts, not the desktop bus, not the network.
- `tests/tools/env.sh` gives each run a scratch home, scratch `XDG_*`
  folders, a scratch runtime folder (`XDG_RUNTIME_DIR`, where the owner's
  paw opens its control socket), a scratch `WINEPREFIX`, empty plugin
  folders, the user name `paw-test`, no system configuration of git and
  no desktop bus. It sets `PAW_TEST_ENV`. `tests/suite.lua` does not run
  without it, so start the suite only through `tests/tools/suite.sh`.
  bench/ sources it too.
- A path in a test comes from `T.scratch` or from the checkout, never
  from the home folder.
- A test of `~` or of the home folder calls `T.home()`. It makes `HOME`
  a new folder under `T.scratch` (or the folder that you give) until the
  test ends, and gives the folder. Write the expected path as a literal
  under that folder. Do not read `os.getenv("HOME")` or `USER`, and do
  not read `/etc/passwd` to find the owner's home: the run always has a
  scratch home.
- Code that asks the machine (a font, a program on the `PATH`) gets a
  field that a test can replace. Example: `paw.health.cjk_font`, which
  `tests/health.lua` replaces with a fake that gives a font name or nil.
- A test of the plugin host uses the stub CLAP plugin. `suite.sh plugins`
  gives the known test plugins. Never an installed plugin.
- Mock what is needed. Give a fake to the code as an argument, or put a
  fake in the field of a module and put the old value back with
  `T.after`. Other fakes: the stub plugin, the plugin sandbox that the
  test controls (`sandbox.hold`, `sandbox.hang`), a scratch folder.
- Run paw by hand only through `tests/tools/run.sh`. It uses the same
  environment as the suite.

## 5. Real keys for what the user does

- A test of a behavior of the user uses `T.keys`, not the function
  behind the key. A fix of the user experience has a test with the real
  keys.
- A test of an action also checks that one `u` undoes it (rule 6: one
  action is one undo step).
- A command or a key that can fail has a test of its message, not only
  of the success.
- The runner fails a test when an error of `paw.try` (an event handler, a
  timer, a key) comes and the test does not expect it. Before a test
  checks an error message, it calls `T.expect_error(pattern)`.
- Write the expected value as a literal (`T.eq(name, "Bass 2")`). Do not
  compute it with the code under test.
- Where the result depends on a combination (mode, selection, view),
  write a small table of the cases that change the result, and test
  each row in one loop.
- A position in time is a whole number of ticks (`paw.timegrid`, 61440
  to a beat). Compare `paw.cursor.tick` with `T.eq`, not with `T.near`,
  and write the value as ticks (`10 * TPQ`). The runner sets
  `paw.timegrid.strict`: `paw.cursor.set_tick` with a fraction is an
  error in the tests. To test a rule of the grid on many positions, use
  `paw.timegrid.new(spec)` with positions from a fixed seed, as
  `tests/timegrid.lua` does. Do not use `math.random` without a seed.
- For a key test of parts, clips and notes, use one check helper:
  `T.check_keys(fixture, keys, expected, what)`. The fixture is a small
  project in a Lua string. Its format has a reference comment in
  `tests/suite.lua` ("Text fixtures"). A failure prints the project as a
  fixture, ready to paste. Read it, and paste it only when it is right.
  The piano roll test in `tests/modal.lua` is an example:

```lua
T.check_keys(
  "part T\n clip a 0+4\n 60 0+0.5\n 64 0.5+0.5\n cursor 60@0",
  "dw",
  "part T\n clip a 0+4\n 64 0.5+0.5\n cursor 60@0",
  "dw deletes up to the next note"
)
```

## 6. Sound

- Check sound with `T.render` (offline). Check the peaks or the
  frequency of the render.
- Prefer a null test (two renders that must be the same) to a level with
  a tolerance.
- The suite runs the engine on the stepped audio backend
  (`paw --clock manual --audio step`, from `tests/tools/suite.sh`). The
  engine plays a block only when the clock gets to its end, so a meter
  is the same in each run, to the bit. Play with `T.next_block(n)`,
  `T.advance(ms)` or `T.until_beat`, then read the meter with
  `T.meter(part)`, or wait for a level with `T.level(part)` in
  `T.until_`. The lint counts each `:meter(` in a test: a live test only
  reads one. To check that a device sounds, or does not sound, use
  `T.wakes`: it reads no meter.
- A test that starts the engine again names no backend:
  `api.engine_restart({ test_input = ... })` keeps the backend that runs
  (`step` in the suite, `null` in the live pass). A test that names a
  backend puts back the one that ran before (`api.engine_get().backend`).
  The `test` backend (the device that a test unplugs) plays on the wall
  clock: read no meter there. `api.wait_blocks` on a backend that is not
  stepped is an error.
- A live test that must read the clock goes in a file of live tests
  (`tests/live_<area>.lua`, for example `tests/live_limits.lua`).
- An extension's project must open and play without the extension.
  Test that too.

## 7. The screen

- `find()` on the screen text checks that one text exists. It does not
  check a layout: a wrong layout that still holds the text passes.
- For a layout, use a golden file: `T.expect_screen(name, w, h, opts)`
  compares the screen with `tests/screens/<file>/<name>.txt`. For an
  extension, the folder is `extensions/<ext>/screens/<file>/`.
  `tests/tools/golden.lua` holds the helper.
- Keep each grid small: the smallest size and region that show the
  behavior. `opts.rows = { first, last }` and `opts.cols = { first, last }`
  keep a region. `opts.styles = false` keeps the text only.
- A golden file holds no value that changes from run to run or from
  machine to machine: a time, a path, the user name, the processor load,
  a list of plugins. Choose a size and a region without them. For example,
  the status line shows `cpu` only from 90 columns.
- To write or accept a golden file, run the test with `PAW_BLESS=1`:
  `PAW_BLESS=1 tests/tools/suite.sh only "<words>"`. Read each file and
  its diff, and name the blessed files in the commit.
- If the file is not there or is different, the test fails. The message gives the
  rows that differ and the command to bless. A golden file that no test
  uses fails the run (`every golden screen has a test`). A run with
  `PAW_BLESS=1` removes it.
- Call `T.settle()` (or `T.advance(ms)` for a view that draws after a
  delay) before you compare a view with its golden file.
- `tests/scene_parity.lua` checks that the window and the terminal draw
  one view the same. Keep a new view in it.
- The text formats have golden files in Rust (`insta`, see the skill
  `rust-testing`, part 5): the scene on the wire, the control protocol,
  the project folder, the `.midi2` clip and the undo folder. A Lua test
  does not check these formats field by field. When a change of Lua
  changes one of them, run `cargo insta test -p <crate>` and
  `cargo insta review`, and commit the accepted files.

## 8. No time and no speed

- A test checks behavior, not speed. No `T.quick`, no `T.cpu_ms`, no
  `os.clock()`, and no comparison of a time with a number. To guard a
  cost, count the work (compiles, renders, builds). A time goes to
  `bench/`, for example `bench/heavy.lua`.
- The lint `tools/testlint.lua` refuses a new sleep, clock read or speed
  check. The suite (`tests/testlint.lua`) and `nix flake check` run it.
  It also fails on each `os.getenv("HOME")`, `os.getenv("USER")`,
  `/etc/passwd` or `'/home/` path in a test file. These have no
  allow-list: use `T.home()` or `T.scratch`.
  Its allow-list `tests/timing-allowed.txt` holds the uses of today. A
  count that goes down fails until you make its line smaller.
- A test does not sleep: no `api.sleep`, no `api.wait(ms)`, no
  `paw.wait(ms)` to let time pass, no `{ wait = N }` in a lesson of the
  tutor (write `{ advance = N }`). Wait for a state with `T.until_`, for blocks with
  `T.next_block`, or for the playhead with `T.until_beat`. Move the
  clock with `T.advance(ms)`, or with `T.advance_until` to a state that a
  timer makes.
- The suite runs paw with `--clock manual` and the engine on the
  stepped backend. `api.now()`, the timers and the audio move only when
  a test moves them, and `paw.wait(ms)` in a test is `T.advance(ms)`.
  Work on other threads and helper processes still takes wall time. The
  one limit of wall time is the stall guard of the runner (30 s for each
  wait), which fails with "stalled". A test has a limit on the clock
  too: after ten minutes of schedule time its next wait fails with "the
  test ran more than 600000 ms of the clock".
- A test that needs real time is live: `T.test(name, fn, { live = "why" })`.
  The suite runs the live tests after the others, in a second paw on the
  wall clock (`PAW_TEST_LIVE=1`). Keep them few (about 3 % of the tests),
  and check outcomes only.
- Do not use `api.now()` for a deadline in a test. The waits of `T`
  have one limit, the same for all tests.
- Do not write a local `wait_for` with its own deadline. A wait that
  returns in silence at a deadline makes the next assertion fail with a
  wrong message.
- Check that a thing does not happen only after a sync point. First
  wait until the kernel did its work (`T.next_block`, a state, or
  `T.settle()`), and advance past each timer that could
  make it happen. Then check. "Nothing happened in 300 ms" is not a
  check.
- A plugin or a helper process that the test controls waits for the
  test. Do not compare an injected delay with a deadline. The plugin
  sandbox has test commands (`api.device_call(id, "sandbox.<command>")`):
  `hold` and `release` keep a device that loads a stand-in until the
  test releases it (`T.settle` does not wait for it); `hang` stops a
  device while it is made (call it before the next turn), or stops the
  answers of a device that runs, and of the plugins of its kind made
  after it, until `hang 0`; `deadline <ms>` makes the session stop it
  soon.
  Reset a command of a plugin that runs with `T.after`: it holds for its
  kind. Wait for `device.state_applied` (with its `seq`) when a plugin
  must take a state on, not for a time. A helper process that still
  runs is work in flight (`api.pending().helpers`): `T.until_` waits
  for it.
- A test fails when a worker did not ring the loop when its work ended
  ("missed wakes", `api.pending().missed_wakes`): the loop found the
  result only on its safety tick. Fix the worker: it rings its bell
  after it sends its result.

## 9. Skips

- A test that needs a plugin, a tool or a file that the machine does not
  have returns a string: the reason. The runner prints
  `skip  <name> (<reason>)`.
- Never skip in silence with an `if` that returns nothing.
- Plugin tests run with `tests/tools/suite.sh plugins`.

## 10. Flakes

- A test that fails once and passes again is a bug. Do not change a
  time, a tolerance or an order to make it pass.
- Find the cause: time, an order of tests, state that an earlier test
  left. Run the test alone, and under `only` filters that run it after
  other files.
- `suite.sh repeat 20 only "<words>"` runs the tests 20 times in one
  paw. It stops after the first run that fails, and prints
  "repeat: run N of 20 failed". Each run loads the test files again. A
  test that depends on the order or on state that it leaves in the kernel
  fails in its second run.
- `suite.sh --shuffle <seed>` runs the test files, and the tests in each
  file, in the order of the seed. It prints the seed on its first line.
  The same seed gives the same order. With no number, it takes a new
  seed. The tests of `T.last` stay last.
- If you cannot fix it now, put it in `tests/quarantine.txt`: the full
  name of the test, a tab, and the fix that it waits for, in words (no
  ticket id). The runner runs the test and prints `quarantined` for its
  failure, and the run does not fail. A quarantined test that passes is
  reported, so that its line can go when the fix is merged. A line with
  no fix fails the run at the start. The list only gets shorter.
- The tiers of checks and the flake policy are in the skill `paw-code`,
  part 7.

## 11. Teal

A test of a `.tl` module can be Lua. The module itself passes
`tools/tlcheck.sh`, and the suite runs the same check. Use the skill
`teal` for the module.

## 12. Commands

Run them in the dev shell. A change of Lua or Teal needs no build: make a
runtime from the checkout and use a binary of main. The skill `paw-code`,
part 7, gives the tier of each command.

```sh
tools/dev-runtime.sh                                   # target/dev-runtime
PAW_TEST_BIN=<dir of paw> PAW_RUNTIME=$PWD/target/dev-runtime \
  tests/tools/suite.sh only "<words>" "<more>"         # the tests that hold any of the words
tests/tools/suite.sh                                   # all tests in 4 processes (the orchestrator, before a push)
tests/tools/suite.sh -j 1                              # the same in 1 process (1 to 4); only, plugins and repeat use 1 if no -j
tests/tools/suite.sh repeat 20 only "<words>"          # find a flaky test
tests/tools/suite.sh --shuffle 7                       # the order of the seed 7
tests/tools/suite.sh plugins "<words>"                 # with the test plugins
PAW_BLESS=1 tests/tools/suite.sh only "<words>"        # write the golden screens
tools/tlcheck.sh                                       # Teal types
luacheck .                                             # unused and undefined names
tools/fmtcheck.sh                                      # the format (`fix` formats)
```

Do not run `tests/tools/loaded.sh` or `tests/tools/e2e.sh`.

The Lua runner has no property tests. Some rules are true for each input
of a file format or of the model, for example a round trip or an undo.
Each of these rules is a Rust property test in `paw-core` or
`paw-engine`. It uses `proptest` and the helper
`crate::props::config()`. The skill `rust-testing` (part 6) gives the
modules and the rules. Run them with:

```sh
cargo nextest run -p paw-core -p paw-engine -E 'test(/::props::/)'
```

A Lua test checks the same format through the API only where the API
adds behavior of its own, for example `paw.xml` with `opts.source`.

The fuzz targets of `fuzz/` (`tools/fuzz.sh`, the nightly tier, which waits for CI)
are Rust only. The readers in Teal (`midifile.tl`, the DAWproject and
RPP readers) have no fuzz target. A test of such a reader gives it bytes
that are cut short or wrong, and checks the message. `tests/midifile.lua`
and `tests/robust.lua` are examples. The skill `rust-testing`, part 13,
lists the targets.

## 13. Before you commit

- Apply `prune-tests` to each test that you added or changed.
- Each new test fails when its behavior breaks, and passes alone and
  under `only`.
- No test sleeps, reads the clock or checks a time.
- No test reads the home folder, the installed plugins or another thing
  of the machine.
- The guide tests (`tests/guides*.lua`) still match the pages that you
  changed.
