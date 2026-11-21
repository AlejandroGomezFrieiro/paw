# The source tree

<!-- tags: source-tree crates repository -->

This page lists the folders of paw's repository and what each one holds.
[About the architecture](../explanation/about-the-architecture.md) tells
how the parts connect. [The instructions for agents and contributors](../../AGENTS.md)
give the rules for a change.

## Top-level folders

| Folder | What it holds |
| --- | --- |
| `crates/` | The Rust crates. The next section lists them. |
| `runtime/lua/paw/` | The Lua runtime: the views, the keys, the commands and the `paw` module. The build puts it into the binary. `--runtime <dir>` loads it from the disk. |
| `runtime/lua/paw/defaults/` | The built-in keys, commands and views. They use the same `paw` module as a configuration. |
| `runtime/lua/paw/*.tl` | The modules of the runtime written in Teal. The build compiles them to Lua. `types.tl` holds the records of the data that crosses `paw.api`. |
| `runtime/lua/tl.lua` | The compiler of Teal, version 0.24.8 (MIT license, `tl.LICENSE`). |
| `runtime/types/` | `paw.lua`, the type definitions of the `paw` module for LuaLS. `paw.d.tl` and `paw/api.d.tl`, the declarations of `paw` and `paw.api` for Teal. `paw/untyped.d.tl`, the type that a module of the runtime in Teal gives to the parts of `paw` that are still Lua. `any-allowed.txt`, each `any` that they can have, with the reason. `tools/apidoc.lua` makes them. |
| `tlconfig.lua` | The configuration of Teal for `tl check` and editors. |
| `extensions/` | The bundled extensions. Each folder has a `README.md`, a `manifest.lua`, an `init.lua`, its Lua in `lua/` and its tests in `tests*.lua`. Some also have `doc/`, `images/`, `native/` and `nix/`. |
| `config/` | The example configuration: an `init.lua` that loads the bundled extensions, and two small extensions in `config/extensions/`. |
| `examples/` | The demo song (`examples/demo-song.lua`) and the files of the tutorial [Make music with paw](../tutorials/make-music/README.md). |
| `docs/` | The manual. [docs/README.md](../README.md) lists the pages. `docs/images/` holds the pictures, and `docs/images/make/` the scripts that record them again. |
| `tests/` | The Lua suite: the runner `tests/suite.lua`, the tests of the core in `tests/<area>.lua`, the guides' tests in `tests/guides*.lua`, and files for the tests in `tests/fixtures/`. |
| `tests/tools/` | The scripts that run the tests: `suite.sh` (the Lua suite), `gui.sh`, `live.sh`, `loaded.sh`. |
| `tools/` | `apidoc.lua` (the API reference and the types), `tlcheck.sh` (`tl check` on each Teal file), `vale.sh` (Vale on the docs), `vale-hook.sh`, `ste-check.lua`, `sweep.sh` (frees the disk that old builds use). |
| `bench/` | The benchmarks and the stress tests. See [bench/README.md](../../bench/README.md). |
| `.vale/` | The project's Vale styles (STE) and its vocabulary. `.vale.ini` configures Vale. |
| `.claude/skills/` | The instructions for agents: write an extension, write the docs, prune the tests. |
| `flake.nix` | The Nix package, the dev shell and the checks. See [The Nix package](nix-package.md). |

## The crates

Two crates have a README: [paw-gui](../../crates/paw-gui/README.md) and
[paw-mcp](../../crates/paw-mcp/README.md). This table describes the other
crates.

| Crate | What it holds |
| --- | --- |
| `paw-engine` | The audio thread: tracks, routing, chains of devices, clip playback, the transport, the metronome. The built-in devices. The cpal and null backends. It has no Lua and no UI. |
| `paw-core` | The kernel: the project model, undo, the sync that drives the engine from the model, the Lua host and `paw.api`, the grid of cells, the event loop, the control socket. |
| `paw-plugins` | The hosts of CLAP, LV2 and VST3 plugins: the scan, its cache, and for each format a device for the audio thread and a controller for the main thread. |
| `paw-luadev` | Devices written in Lua. Each is a script in its own LuaJIT state, in a helper process. Also the folders where paw finds the scripts. |
| `paw-scene` | What all frontends share of a view: the cells and their styles, and the scene. A scene is the drawing of a view as nodes in cell units. It has no Lua and no UI. |
| `paw-raster` | Changes the drawings of views (the operations of `paw.canvas`) into pixels, with music fonts. Also the kitty graphics protocol that shows them in a terminal. |
| `paw-proto` | The client side of the control protocol, with TLS. A program that only talks to a kernel does not need the kernel to build. |
| `paw-listen` | Plays the sound of an instance on the computer where a terminal or a graphical window is attached. |
| `paw-tui` | The terminal frontend and the `paw` binary. |
| `paw-gui` | The graphical frontend, written with egui. It is a client of the control socket. Its tests drive the window on a private X display. |
| `paw-mcp` | A Model Context Protocol server in front of the control socket. |

## Generated files

Do not edit these files. Make them again from their source.

| File | Source | Command |
| --- | --- | --- |
| `docs/reference/api.md`, `runtime/types/paw.lua`, `runtime/types/paw.d.tl`, `runtime/types/paw/api.d.tl`, `runtime/types/paw/untyped.d.tl` | the doc comments of the `paw` modules, of the files of `crates/paw-core/src/api/` and of the other files that add to `paw.api` | `paw --clean --no-plugins -l tools/apidoc.lua` |
| `docs/tutorials/course/*.md` | the tutor's lessons in `extensions/tutor/lua/tutor/lessons/` | `paw --clean --no-plugins -l extensions/tutor/make-docs.lua` |
| `docs/images/*.gif`, `docs/images/*.png` | a recording of paw | `docs/images/make/make.sh` |

## See also

- [How to build and run paw from the source](../how-to/build-paw-from-source.md)
- [How to run the tests](../how-to/run-the-tests.md)
