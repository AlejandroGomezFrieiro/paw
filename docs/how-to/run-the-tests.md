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

## Write a test that a loaded machine does not break

The tests run on a machine that also builds and runs other programs, and a
loaded machine is slow but not wrong. Follow these rules so that a slow
machine does not fail a test:

- Wait for the event or the state, not for a time. `T.until_` waits for a
  condition, `T.next_block` for the audio blocks, and `T.until_beat` for
  the playhead. In the window tests, `expect` waits for a condition in the
  kernel.
- Set a limit on a wait to the time that the slowest machine needs, not
  the usual time, which is 30 seconds for a wait in the kernel. A wait
  that gets to its limit shows a fault.
- Do not compare two drawings of a value that changes with the time, for
  example a meter. Hold the value still while the test draws.
- Measure the speed only when the speed is the behavior, as described
  below.

When you measure the speed, measure the processor time of the thread with
`T.cpu_ms()`, not the time on the clock. Then check it with
`T.quick(ms, limit, what)`. Other programs share the caches and the memory
of the processor. As a result, the same work takes more processor time on
a loaded machine, up to four times more.

`T.quick` runs a fixed piece of work three times, and it compares the best
time with its time on an idle machine. It multiplies the limit by the
larger of the slowdown and the load average per processor, at most 8
times and at least 1. The message of a failure shows both numbers. Keep
the limit a few times the target.

## Run the Rust tests

1. Run `cargo test`, which also runs the Lua suite once, from
   `crates/paw-tui/tests/suite.rs`.
2. To test one crate, run `cargo test -p <crate>`.

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

The Lua suite and the window tests do not run in the build. They need an X
server, plugins and their own directories, and a build sandbox does not
have them.
