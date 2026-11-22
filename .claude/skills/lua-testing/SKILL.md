---
name: lua-testing
description: "How to write and change Lua and Teal tests in paw: the runner and its helpers (T.test, T.fresh, T.keys, T.render, T.until_, T.next_block), real keys, the state that a test makes and puts back, self-contained tests that read nothing of the machine, sound, the screen, skips, flakes, and what a test must not do. Use it for each change of tests/, extensions/*/tests*.lua or the lessons of the tutor, and for each review of Lua tests."
---

# Lua tests in paw

Use this skill for each change of `tests/*.lua`,
`extensions/*/tests*.lua` or the lessons of the tutor. It adds to part 3
of `paw-code`. The skill `prune-tests` tells which tests to delete. For
the Rust tests, use `rust-testing`.

Two designs in `backlog/docs/designs/` are the source of this skill.
One is the review of the test suite (the rules for time). The other is
the research on the practices of other projects. The milestone m-12
builds the parts that are marked "planned" here. Do not use a planned helper before its ticket is done.

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

## 2. The helpers

Use the helpers of `T`. Do not copy them into a file (a local `start`,
`screen` or `wait_for`).

| Helper | Use |
| --- | --- |
| `T.fresh()` | A new project and the start layout. Call it first in each test that needs a project. |
| `T.after(fn)` | Put back what the test changed. It runs after the test, also after a failure. |
| `T.keys(text)` | Feed keys through the keymap, as the user types them (`"<Esc>dd"`). |
| `T.eq(got, want, what)`, `T.near(got, want, tolerance, what)` | Compare a value. `what` tells what the value is. |
| `T.fails(fn, pattern, what)` | `fn` gives an error that matches `pattern`. |
| `T.render(opts)` | Render offline to a file under `T.scratch`. The result does not depend on the machine. |
| `T.frequency(info, from, to)`, `T.channel_peaks(info, from, to)` | Read a render. |
| `T.tone`, `T.three_clips`, `T.melody`, `T.layout`, `T.roll_notes` | Fixtures. |
| `T.until_(cond, what)` | Wait for a state. |
| `T.next_block(n, device)` | Wait until the engine ran `n` blocks, so that a change is in effect. |
| `T.until_beat(beat, rounds)` | Wait for the playhead. |
| `T.scratch`, `T.read_file`, `T.write_file` | Files of the test. |

Planned helpers:

- `T.start()` and `T.screen(w, h)`, and the leak check after each file
  (TASK-121).
- `T.settle()`, `T.advance(ms)`, `T.advance_until(cond, what, ms)` and a
  `T.until_` that fails at quiescence (TASK-146). Then `paw.wait(ms)`
  advances a virtual clock.
- `T.next_block(n)` on a stepped audio backend (TASK-147).
- `T.expect_screen(name, w, h)` with golden files (TASK-152).
- `T.check_keys(fixture, keys, expected)` (TASK-158).

## 3. Start clean and put back

A test makes all the state that it reads.

- Start from `T.fresh()`. Set each option that the test needs. Do not
  rely on an option, a window or a mode that an earlier test left.
- Take ids from the kernel (the value that a call returns). Never write
  a literal id of a track, a device, a clip or a lane.
- Write files under `T.scratch`. Never write in the checkout or in the
  owner's folders.
- Put back what you change with `T.after`: options, keys, hooks, timers,
  MIDI test ports, the engine backend, extensions that you loaded.
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
  folders, a scratch `WINEPREFIX` and empty plugin folders, and sets
  `PAW_TEST_ENV`. `tests/suite.lua` does not run without it, so start
  the suite only through `tests/tools/suite.sh`.
- A path in a test comes from `T.scratch` or from the checkout, never
  from the home folder.
- A test of the plugin host uses the stub CLAP plugin. `suite.sh plugins`
  gives the known test plugins. Never an installed plugin.
- Mock what is needed. Give a fake to the code as an argument, or put a
  fake in the field of a module and put the old value back with
  `T.after`. Other fakes: the stub plugin, the plugin sandbox that the
  test controls (`sandbox.hang`), a scratch folder.
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
- Write the expected value as a literal (`T.eq(name, "Bass 2")`). Do not
  compute it with the code under test.
- Where the result depends on a combination (mode, selection, view),
  write a small table of the cases that change the result, and test
  each row in one loop.

## 6. Sound

- Check sound with `T.render` (offline). Check the peaks or the
  frequency of the render.
- Prefer a null test (two renders that must be the same) to a level with
  a tolerance.
- Do not read a live meter (`:meter()`) after a wait. The level depends
  on how many blocks ran in real time. After TASK-147, play on the
  stepped backend and read the meter after `T.next_block(n)`.
- An extension's project must open and play without the extension.
  Test that too.

## 7. The screen

- `find()` on the screen text checks that one text exists. It does not
  check a layout: a wrong layout that still holds the text passes.
- For a layout, use a golden file (planned, TASK-152):
  `T.expect_screen(name, w, h)` against `tests/screens/<file>/<name>.txt`.
  Bless with `PAW_BLESS=1`, read the diff, and name the blessed files in
  the commit. Keep each grid small: the smallest size and region that
  show the behavior.
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
  `bench/`. TASK-143 removes the speed checks that exist and adds a lint
  (`tools/testlint.lua`) that refuses new ones.
- A test does not sleep: no `api.sleep`, no `api.wait(ms)`, no
  `paw.wait(ms)` to let time pass, no `{ wait = N }` in a lesson of the
  tutor. Wait for a state with `T.until_`, for blocks with
  `T.next_block`, or for the playhead with `T.until_beat`. After
  TASK-146, advance the clock with `T.advance(ms)`.
- Do not use `api.now()` for a deadline in a test. The waits of `T`
  have one limit, the same for all tests.
- Do not write a local `wait_for` with its own deadline. A wait that
  returns in silence at a deadline makes the next assertion fail with a
  wrong message.
- Check that a thing does not happen only after a sync point. First
  wait until the kernel did its work (`T.next_block`, a state, or
  `T.settle()` after TASK-146), and advance past each timer that could
  make it happen. Then check. "Nothing happened in 300 ms" is not a
  check.
- A plugin or a helper process that the test controls waits for the
  test (`sandbox.hang`, and the handshakes of TASK-148). Do not compare
  an injected delay with a deadline.

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
  other files. `suite.sh repeat N only "<words>"` and `--shuffle <seed>`
  are planned (TASK-151).
- If you cannot fix it now, put it in `tests/quarantine.txt` with a
  ticket (TASK-145 adds the runner support). The list only gets shorter.

## 11. Teal

A test of a `.tl` module can be Lua. The module itself passes
`cyan check`, and the suite runs `tools/tlcheck.sh`. Use the skill
`teal` for the module.

## 12. Commands

Run them in the dev shell. A change of Lua or Teal needs no build: make a
runtime from the checkout and use a binary of main.

```sh
tools/dev-runtime.sh                                   # target/dev-runtime
PAW_TEST_BIN=<dir of paw> PAW_RUNTIME=$PWD/target/dev-runtime \
  tests/tools/suite.sh only "<words>"                  # some tests
tests/tools/suite.sh                                   # all tests (the orchestrator, before a push)
tests/tools/suite.sh plugins "<words>"                 # with the test plugins
tools/tlcheck.sh                                       # Teal types
luacheck .                                             # unused and undefined names
tools/fmtcheck.sh                                      # the format (`fix` formats)
```

Do not run `tests/tools/loaded.sh` or `tests/tools/e2e.sh`.

## 13. Before you commit

- Apply `prune-tests` to each test that you added or changed.
- Each new test fails when its behavior breaks, and passes alone and
  under `only`.
- No test sleeps, reads the clock or checks a time.
- No test reads the home folder, the installed plugins or another thing
  of the machine.
- The guide tests (`tests/guides*.lua`) still match the pages that you
  changed.
