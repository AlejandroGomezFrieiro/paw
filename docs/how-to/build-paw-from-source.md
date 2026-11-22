# How to build and run paw from the source

<!-- tags: running build-from-source -->

You can build paw and run it from a checkout of its source. The steps use
the dev shell of the flake, which has the Rust toolchain and the PipeWire
libraries.

1. In the checkout, run `nix develop`.
2. To open a demo song in the terminal interface, run the following
   command:

   ```sh
   cargo run -- -e 'dofile("examples/demo-song.lua")'
   ```

3. To open the graphical window on the same song, run the following
   command:

   ```sh
   cargo run -p paw-gui -- -e 'dofile("examples/demo-song.lua")'
   ```

## Variations

- If you use `direnv`, run `direnv allow` once in the checkout. The
  checkout then loads the dev shell by itself, and you can skip
  `nix develop`. With nix-direnv, the shell loads in well under a second.
- To use the example configuration, run `cargo run -- --config config`.
  To start without a search for plugins, add `--no-plugins`.
- To build the demo song and render it to a file without a UI, run
  `cargo run -- -l examples/demo-song.lua song.wav`.
- To open specific audio devices, give a part of their names:
  `cargo run -- --output UR22 --input UR22`.
- To check the audio, the plugins and the environment, run
  `cargo run -- doctor`, and the doctor prints a report.

The first start looks at every installed plugin, and it can take several
seconds, because each bridged Windows plugin starts Wine. The later starts
use the cache in `~/.cache/paw/plugins.json`.

If you are new to paw, type `:tutor` in paw, or read
[the course](../tutorials/course/README.md). Load `extensions/tutor` first
if your configuration does not load it.

## See also

- [The programs and their options](../reference/programs.md): every option of `paw`, `paw-gui` and `paw-mcp`.
- [How to run the tests](run-the-tests.md).
- [How to install paw with Nix](install-paw.md): the package, without the dev shell.
