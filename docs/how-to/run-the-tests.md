# How to run the tests

This guide shows you how to run paw's tests. Run every command in the dev
shell (`nix develop`), in a checkout of the source.

## Run the Lua suite

The Lua suite is the end-to-end test of paw. It runs on the release build.

1. Build paw: `cargo build --release`.
2. Run `tests/tools/suite.sh`.
3. Read the last line. It is `all passed`, or the number of failed tests.

The suite writes its full output to `target/test-scratch/suite.out`.

`tests/suite.lua` is the runner and the helpers (`T`). The tests of the
core are in `tests/<area>.lua`. The tests of an extension are beside it,
in `extensions/<name>/tests.lua` and `tests_<part>.lua`. The runner loads
each of these files, in the order of their names.

- To run only some tests, give words of their names:
  `tests/tools/suite.sh only "loop on"`.
- To run the suite with the test plugins, run `tests/tools/suite.sh plugins`.
  The dev shell gives the plugins (LSP Plugins and Surge XT) through
  `PAW_TEST_PLUGINS`. Outside the dev shell, the plugin tests do not run.
- To test the plugins that are not in nixpkgs, give their package:
  `PAW_TEST_TONE3000=<store path> PAW_TEST_SOUNDSHED=<store path> tests/tools/suite.sh plugins plugstate`.
  In this mode, the plugins get a scratch `HOME`.

## Run the Rust tests

1. Run `cargo test`. This also runs the Lua suite once, from
   `crates/paw-tui/tests/suite.rs`.
2. To test one crate, run `cargo test -p <crate>`.

## Run the tests of the graphical window

1. Run `cargo test -p paw-gui`.
2. If a scenario fails, look at `target/tmp/window/<scenario>`. It holds
   `failure.png` and the output of the window.
3. To run the tests marked `#[ignore]`, run `cargo test -p paw-gui -- --ignored`.
   These are a measurement of how reliably the tests read the screen
   (several minutes), and known bugs, if there are any.

The window tests need `Xvfb`, `openbox`, `xdotool`, ImageMagick and
`tesseract`. The MP3 test also needs `ffmpeg`. The dev shell has all of
them. If one is not there, the tests say which one and pass.

Each scenario starts Xvfb on a free display from `:120` up, with openbox
and no session bus. A scenario claims its display number with a file in
`/tmp`. Two test runs at the same time do not share a display. Nothing
goes to your desktop.

The tests use xdotool for
the pointer and the keys. They find menu entries and buttons with
tesseract, which reads a picture of the window. Then they ask the kernel
what it holds.

## Run the checks of the flake

Run `nix flake check`. This builds paw and runs these checks:

- the Rust tests that need no display, audio device or Lua suite, with cargo-nextest (they must pass).
- clippy and rustfmt, which report what they find and do not fail.

The Lua suite and the window tests do not run in the build. They need an X
server, plugins and their own directories, which a build sandbox does not have.
