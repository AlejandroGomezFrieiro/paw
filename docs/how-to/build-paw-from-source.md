# How to build and run paw from the source

<!-- tags: running build-from-source -->

This guide shows you how to build paw and run it from a checkout of its
source. It uses the dev shell of the flake. The dev shell has the Rust
toolchain and the PipeWire libraries.

1. In the checkout, run `nix develop`.
2. To open a demo song in the terminal interface, run this command:

   ```sh
   cargo run -- -e 'dofile("examples/demo-song.lua")'
   ```

3. To open the graphical window on the same song, run this command:

   ```sh
   cargo run -p paw-gui -- -e 'dofile("examples/demo-song.lua")'
   ```

## Variations

- To use the example configuration, run `cargo run -- --config config`.
- To build the demo song and render it to a file without a UI, run
  `cargo run -- -l examples/demo-song.lua song.wav`.
- To open specified audio devices, give a part of their names:
  `cargo run -- --output UR22 --input UR22`.
- To check the audio, the plugins and the environment, run
  `cargo run -- doctor`. The doctor prints a report.
- To start without a search for plugins, add `--no-plugins`.

The first start looks at every installed plugin. This can take several
seconds, because each bridged Windows plugin starts Wine. The next starts
use the cache in `~/.cache/paw/plugins.json`.

If you are new to paw, type `:tutor` in paw, or read
[the course](../tutorials/course/README.md). Load `extensions/tutor` first
if your configuration does not load it.

## See also

- [The programs and their options](../reference/programs.md): every option of `paw`, `paw-gui` and `paw-mcp`.
- [How to run the tests](run-the-tests.md).
- [How to install paw with Nix](install-paw.md): the package, without the dev shell.
