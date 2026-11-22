# How to run the tests

You can run paw's tests in a checkout of the source. Run every command on
the page in the dev shell (`nix develop`).

## Run the Lua suite

The Lua suite is the end-to-end test of paw, and it runs on the release
build.

1. Build paw: `cargo build --release`.
2. Run `tests/tools/suite.sh`.
3. Read the last line, which is `all passed` or the number of failed
   tests.

The suite writes its full output to `target/test-scratch/suite.out`.

The tests never use your own files or plugins. Each test run gets a scratch
home folder and empty plugin folders under `target/test-scratch`, so your
plugins, your settings and your Wine prefix stay untouched. To run paw by
hand in the same setup, use `tests/tools/run.sh` in place of `paw`, for
example `tests/tools/run.sh --clean --no-plugins -l tools/apidoc.lua check`.

`tests/suite.lua` is the runner and the helpers (`T`). The tests of the
core are in `tests/<area>.lua`, and the tests of an extension are beside
it, in `extensions/<name>/tests.lua` and `tests_<part>.lua`. The runner
loads each of the test files, in the order of their names.

- To run only some tests, give words of their names:
  `tests/tools/suite.sh only "loop on"`.
- To run the suite with the test plugins, run `tests/tools/suite.sh plugins`.
  The dev shell gives the plugins (LSP Plugins and Surge XT) through
  `PAW_TEST_PLUGINS`, and outside the dev shell, the plugin tests do not
  run.
- To test the plugins that are not in nixpkgs, give their package:
  `PAW_TEST_TONE3000=<store path> PAW_TEST_SOUNDSHED=<store path> tests/tools/suite.sh plugins plugstate`.
  In that mode, the plugins get a scratch `HOME`.
- To test a change of Lua or Teal without a build, use a binary that
  another checkout built. Run `tools/dev-runtime.sh` to make a runtime
  folder from your checkout. Then give the binary's folder and the
  runtime:
  `PAW_TEST_BIN=<folder> PAW_RUNTIME=$PWD/target/dev-runtime tests/tools/suite.sh only "loop on"`.
  The folder also holds `examples/libstub_clap.so`. A change of Rust
  still needs a build of your checkout.

## Run the suite in more than one process

By default, one paw process runs all the tests, one after the other. To
use more processor cores, give `-j` and a number from 1 to 4 before the
other words: `tests/tools/suite.sh -j 2`, or
`tests/tools/suite.sh -j 2 plugins`. With `-j 2`, each process gets every
second test file of `tests/`, and every second extension with all of its
test files. Each process has its own scratch home, plugin and XDG folders under
`target/test-scratch/shard<N>`. The script puts the outputs together in
`target/test-scratch/suite.out`, and the last line is the same as with one
process.

Run one suite at a time on a machine that other people or programs use.
Two suites, or a large `-j`, slow down the tests that wait for the audio.

## Read the leak check

A test file must put back what its tests change, so that the next file
starts in the same state, whatever ran before it. The runner gives back
the options that paw had when the suite started after each test.
`T.fresh()` gives a new project, the default layout, normal mode and no
open float. `T.start()` also types `<Esc><Esc>` and moves the focus to the
arrange view. `T.screen(w, h)` gives the text of the screen.

The runner checks each file of `tests/`, and the test files of each
extension together, because a test file of an extension can use what an
earlier one set up. After the last test of a file or an extension, the
runner puts back the following things as they were at the start of the
run:

- the event handlers, timers and key mappings that the test code made
- the loaded extensions, so it unloads each extension that the tests
  loaded

If a handler, timer or key mapping of the test code was still there, or
an extension can't be unloaded, the runner fails a test named
`tests/<file>.lua leaves no state behind` or
`extensions/<name>/ leaves no state behind`. The `changed:` line names
what changed. To fix the failure, put back the change in the test that
made it, with `T.after(function() ... end)`.

The runner checks a file only when all of its tests ran, so a filter with
`only` does not fail the check. The file `tests/leaks-allowed.txt` lists
the leaks that are known, one on each line, for example
`tests/model.lua hooks` or `extensions/utau/ timers`. Don't add
lines to the list. When a file no longer leaks, the runner fails until you
remove its line.

## Write a test that does not depend on time

The tests run on a machine that also builds and runs other programs, so a
test must give the same result on an idle machine and on a loaded one, in
a dev build and in a release build, and in any order or filter of the
tests. Follow these rules when you write a test:

- Check the behavior and never the speed. A test does not compare a time
  on the clock, a processor time or a count of frames with a number. When
  the cost is the behavior, count the work, for example the builds of an
  index or the compiles of a clip. To measure a speed, write a script in
  `bench/`, for example `bench/heavy.lua`, which reports the processor
  time with the load of the machine and does not fail.
- Wait for an event or a state, not for a time. `T.until_` waits for a
  condition, `T.next_block` for the audio blocks, and `T.until_beat` for
  the playhead. Don't call `api.sleep` or `paw.wait` to let time pass, and
  don't put a `wait` step in a lesson of the tutor.
- Don't set a limit of your own on a wait, and don't write a local wait
  with a deadline. The waits of `T` share one limit, and a wait that gets
  to it shows a fault.
- Check that a thing does not happen only after the kernel did its work,
  for example after `T.next_block`. A check that nothing happened in some
  milliseconds passes on a slow machine for the wrong reason.
- Check sound in an offline render with `T.render`, not in a live meter
  after a wait.
- Make a plugin or a helper process that the test controls wait for the
  test, for example with a file that the test removes, and don't compare a
  delay with a deadline.
- Make all of the state that the test reads. Start from `T.fresh()`, and
  put back what the test changes with `T.after`.

`tools/testlint.lua` checks the test files for a sleep, a read of the clock
or a speed check, and the suite and `nix flake check` run it. The file
`tests/timing-allowed.txt` lists the uses that the tests have today, one
line `<file> <pattern> <count>` for each. A count that goes up fails, so a
new test can't add one. A count that goes down also fails until you make
its line smaller, so the list only gets shorter. Run
`luajit tools/testlint.lua` to check the tree, and
`luajit tools/testlint.lua counts` to print the counts of today.

## Run the Rust tests

1. Run `cargo test`, which also runs the Lua suite once, from
   `crates/paw-tui/tests/suite.rs`.
2. To test one crate, run `cargo test -p <crate>`.

## Run the fuzz targets

The fuzz targets in `fuzz/` feed random input to the code that reads files
and messages from outside paw, and they report each input that makes paw
panic, stop responding or run out of memory. They need cargo-fuzz and a nightly Rust,
which the dev shell doesn't have, so they are meant for CI.

1. To check that the targets compile on stable Rust, run
   `cargo check -p paw-fuzz`. A plain `cargo build` or `cargo test` skips them.
2. With cargo-fuzz and a nightly Rust, run `tools/fuzz.sh` to run each target
   for 200000 inputs, or `tools/fuzz.sh build` to only build them.
3. If a target fails, its input is in `fuzz/artifacts/<target>/`. Write a
   plain test in the crate that crashed, from that input, and fix the code.

## Run the end-to-end scenarios

The end-to-end scenarios act as a person who works on a song for many
days. Run them only in CI or for the release check before a tag, and run
the Lua suite to test a change. The suite and the default
`nix flake check` do not run the scenarios. Their design is in
[About the end-to-end scenarios](../explanation/about-the-e2e-tests.md).

1. Build paw: `cargo build --release`.
2. Run the mode that fits the check:
   - For a pull request, run the short mode: `tests/tools/e2e.sh --short`.
   - For the check of each night, run all the days with some seeds:
     `tests/tools/e2e.sh --seeds 1-3`.
   - For a release, run all the days: `tests/tools/e2e.sh`.
3. Read the last line, which is `all passed` or the number of scenarios
   that failed.

You can choose what runs:

- To run one scenario, give its name: `tests/tools/e2e.sh song`. To run
  another seed, give it: `tests/tools/e2e.sh song --seed 7`.
- To run some seeds, give a range or a list: `--seeds 1-5`, `--seeds 3,7,12`.
  Each seed has its own approved renders.
- To run only the first days, give their number:
  `tests/tools/e2e.sh song --days 2`.

If a failure shows, run the command that its `repeat:` line gives, and
look at the folder that its `kept:` line gives. If the sound of a scenario
changes on purpose, approve the new renders with
`tests/tools/e2e.sh song --seeds 1-3 --approve`, and commit
`tests/e2e/golden/song.json` with the reason for the change.

The scenarios use `--audio null`, no plugins, and their own home and XDG
folders under `target/test-scratch`. They need no display and no network.
The CI runs them in the dev shell, as
`nix develop -c tests/tools/e2e.sh --short`.

## Run the tests of the graphical window

1. Run `cargo test -p paw-gui`.
2. If a scenario fails, look at `target/tmp/window/<scenario>`, which
   holds `failure.png` and the output of the window.
3. To run the tests marked `#[ignore]`, run `cargo test -p paw-gui -- --ignored`.
   They are a measurement of how reliably the tests read the screen
   (several minutes), and known bugs, if there are any.

The window tests need `Xvfb`, `openbox`, `xdotool`, ImageMagick and
`tesseract`, and the MP3 test also needs `ffmpeg`. The dev shell has all of
them. If one is missing, the tests say which one and pass.

Each scenario starts Xvfb on a free display from `:120` up, with openbox
and no session bus. A scenario claims its display number with a file in
`/tmp`, so two test runs at the same time do not share a display. Nothing
goes to your desktop. A scenario opens its window when openbox
runs, and it gives the window the input focus before the first key.

The tests use xdotool for the pointer and the keys. They find menu entries
and buttons with tesseract, which reads a picture of the window, and then
they ask the kernel what it holds.

## Check the documentation

1. To check the docs with Vale, run `tools/vale.sh`. Vale must report 0
   errors. To check only the pages that you changed, give them:
   `tools/vale.sh docs/how-to/run-the-tests.md`.
2. To check the Lua API reference, run
   `target/release/paw --clean --no-plugins -l tools/apidoc.lua check`.
   It names each function that has no doc comment, and it says if
   `docs/reference/api.md` is out of date.
3. If you changed a doc comment, make the API reference again:
   `target/release/paw --clean --no-plugins -l tools/apidoc.lua`.
4. If you changed a lesson of the tutor, make the course again:
   `target/release/paw --clean --no-plugins -l extensions/tutor/make-docs.lua`.

Vale checks `README.md`, `AGENTS.md`, `docs/`, the READMEs of the crates
and the extensions, the `doc/` pages of the extensions, `bench/README.md`
and `bench/DAWS.md`. It does not check `bench/RESULTS.md`, because
`RESULTS.md` is a log of measurements with their dates. The Lua suite
checks that the API reference and the course agree with their sources.

## Run the checks of the flake

Run `nix flake check`, which builds paw and runs the following checks:

- The Rust tests that need no display, audio device or Lua suite, with
  cargo-nextest. They must pass.
- Clippy and rustfmt, which report what they find and do not fail.
- Vale on the documentation, which fails on an error.
- The checks of the Lua and Teal code, which fail on a problem: the types
  of the Teal files with cyan, `luacheck` on the Lua files, and the format
  of both with StyLua and cerulean.
- The check against tests that depend on time, `tools/testlint.lua`, which
  fails on a count over `tests/timing-allowed.txt`.

The Lua suite and the window tests do not run in the build. They need an X
server, plugins and their own directories, and a build sandbox does not
have them.
