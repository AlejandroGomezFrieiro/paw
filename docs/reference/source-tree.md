# The source tree

<!-- tags: source-tree crates repository -->

The source tree page lists the folders of paw's repository and what each one holds.
[About the architecture](../explanation/about-the-architecture.md) tells
how the parts connect, and [the instructions for agents and contributors](../../AGENTS.md)
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
| `tlconfig.lua` | The configuration of Teal for `tools/tlcheck.sh`, `cyan`, `tl check` and the language server of Teal. |
| `.luacheckrc` | The configuration of `luacheck`, which checks the Lua files: LuaJIT, the global `paw`, the warnings that paw does not use. |
| `stylua.toml`, `.styluaignore` | The settings of StyLua, the formatter of Lua. `tools/fmtcheck.sh` checks that each Lua file is formatted with it. |
| `.luarc.json` | The configuration of the language server of Lua (LuaLS): LuaJIT, the global `paw` and `runtime/types`. |
| `extensions/` | The bundled extensions. Each folder has a `README.md`, a `manifest.lua`, an `init.lua` (or an `init.tl` in Teal), its Lua in `lua/` and its tests in `tests*.lua`. Some also have `doc/`, `images/`, `native/` and `nix/`. |
| `config/` | The example configuration: an `init.lua` that loads the bundled extensions, and three small extensions in `config/extensions/`. |
| `examples/` | The demo song (`examples/demo-song.lua`) and the files of the tutorial [Make music with paw](../tutorials/make-music/README.md). |
| `docs/` | The manual. [docs/README.md](../README.md) lists the pages. `docs/images/` holds the pictures, and `docs/images/make/` the scripts that record them again. |
| `tests/` | The Lua suite: the runner `tests/suite.lua`, the tests of the core in `tests/<area>.lua`, the guides' tests in `tests/guides*.lua`, the known leaks of state in `tests/leaks-allowed.txt`, and files for the tests in `tests/fixtures/`. |
| `tests/e2e/` | The end-to-end scenarios: the test driver, the reference model, the scenarios and their golden files. See [About the end-to-end scenarios](../explanation/about-the-e2e-tests.md). |
| `tests/tools/` | The scripts that run the tests: `suite.sh` (the Lua suite), `gui.sh`, `live.sh`, `loaded.sh`, `e2e.sh` (the end-to-end scenarios). |
| `tests/harness/` | The crate `paw-lua-suite`: the test binary that runs the Lua suite under cargo-nextest, one test for each test file of `tests/` and for each extension with tests. `tests/tools/suite.sh` runs it, with the limits in `.config/nextest.toml`. |
| `tools/` | `apidoc.lua` (the API reference and the types; the generator in Teal is in `apidoc/`), `tlcheck.sh` and `tlcheck.lua` (the strict check of all the Teal files), `fmtcheck.sh` (checks that StyLua and cerulean formatted each file; `fix` formats them), `layers.lua` with `layers.txt` and `layers-allowed.txt` (checks that no module of the runtime reads a module of a higher layer), `vale.sh` (Vale on the docs), `vale-hook.sh`, `ste-check.lua`, `sweep.sh` (frees the disk that old builds use), `website/` (builds the manual as a static site with mdBook). |
| `web/browserpod/` | The pod image: paw in a BrowserPod pod, for a page of the docs. See [paw in a BrowserPod pod](../../web/browserpod/README.md). |
| `bench/` | The benchmarks and the stress tests. See [bench/README.md](../../bench/README.md). |
| `.vale/` | The project's Vale styles (STE) and its vocabulary. `.vale.ini` configures Vale. |
| `.claude/skills/` | The instructions for agents: write an extension, write the docs, prune the tests. |
| `.pi/` | The setup of pi, the agent: `settings.json` gives it the skills of `.claude/skills` and the packages, `agents/` holds the paw agent types, and `extensions/paw.ts` runs the hooks and the `Skill` tool. |
| `.pi-lens.json` | The settings of pi-lens: the Teal language server, and no automatic format or fixes. |
| `flake.nix` | The Nix package, the dev shell and the checks. See [The Nix package](nix-package.md). |
| `nix/lua-tools.nix` | The tools for Teal of the dev shell that nixpkgs does not have, or has in an old version. |

## The crates

Four crates have a README: [chain-syntax](../../crates/chain-syntax/README.md),
[chain-lsp](../../crates/chain-lsp/README.md), [paw-gui](../../crates/paw-gui/README.md) and
[paw-mcp](../../crates/paw-mcp/README.md), and the table below describes the other
crates.

| Crate | What it holds |
| --- | --- |
| `paw-engine` | The audio thread: parts, routing, chains of devices, clip playback, the transport, the metronome. The built-in devices. The cpal and null backends, and the `page` backend of a BrowserPod pod. It has no Lua and no UI. |
| `paw-core` | The kernel: the project model, undo, the sync that drives the engine from the model, the Lua host and `paw.api`, the grid of cells, the event loop, the control socket. |
| `paw-plugins` | The hosts of CLAP, LV2 and VST3 plugins: the scan, its cache, and for each format a device for the audio thread and a controller for the main thread. |
| `paw-luadev` | Devices written in Lua. Each is a script in its own LuaJIT state, in a helper process. Also the folders where paw finds the scripts. |
| `paw-scene` | What all frontends share of a view: the cells and their styles, and the scene. A scene is the drawing of a view as nodes in cell units. It has no Lua and no UI. |
| `paw-raster` | Changes the drawings of views (the operations of `paw.canvas`) into pixels, with music fonts. Also the kitty graphics protocol that shows them in a terminal. |
| `paw-proto` | The client side of the control protocol, with TLS. A program that only talks to a kernel does not need the kernel to build. |
| `paw-measure` | Measures a sound: loudness, true peak, levels, stereo and the spectrum in octave bands. The kernel (`paw.api.measure`, and so `:mix`) and `paw-mcp` both use it, so they give the same numbers. |
| `paw-listen` | Plays the sound of an instance on the computer where a terminal or a graphical window is attached. |
| `paw-tui` | The terminal frontend and the `paw` binary. |
| `paw-gui` | The graphical frontend, written with egui. It is a client of the control socket. Its tests drive the window on a private X display. |
| `paw-mcp` | A Model Context Protocol server in front of the control socket. |
| `chain-syntax` | The [chain language](chain-language.md): it parses, prints, formats and checks a chain of devices as text, and it finds the completions, the hover text and the definitions at a place in the text. It depends on no other crate of paw, so a program that is not paw can use it. |
| `chain-lsp` | The language server of the chain language, the program `chain-lsp`. It depends on `chain-syntax` and on no crate of paw, so any editor and any host can use it. |
| `paw-types` | The values that the project model and the audio engine share: notes and controllers as MIDI 2.0 events and the packets that carry them, the tempo map, where a launch lands, and the values of automation lanes. It has no sound, no threads and no calls to the operating system, so it builds for WebAssembly. |

## Generated files

Do not edit the files below by hand. Generate them again from their source.

| File | Source | Command |
| --- | --- | --- |
| `docs/reference/api.md`, `runtime/types/paw.lua`, `runtime/types/paw.d.tl`, `runtime/types/paw/*.d.tl`, `runtime/lua/paw/events/kernel.tl` | the doc comments of the `paw` modules, of the files of `crates/paw-core/src/api/` and of the other files that add to `paw.api` | `paw --clean --no-plugins -l tools/apidoc.lua` |
| `docs/tutorials/course/*.md` | the tutor's lessons in `extensions/tutor/lua/tutor/lessons/` | `paw --clean --no-plugins -l extensions/tutor/make-docs.lua` |
| `docs/images/*.gif`, `docs/images/*.png` | a recording of paw | `nix run .#gifs` (`docs/images/make/make.sh`) |

## See also

- [How to build and run paw from the source](../how-to/build-paw-from-source.md)
- [How to run the tests](../how-to/run-the-tests.md)
