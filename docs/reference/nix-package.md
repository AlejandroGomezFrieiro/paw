# The Nix package

<!-- tags: nix-package flake -->

The flake builds paw for `x86_64-linux` and `aarch64-linux`. It does not
need the dev shell.

## Outputs

| Output | Holds |
| --- | --- |
| `.#default` | `paw`, `paw-gui`, `paw-mcp` and `chain-lsp`, with the extensions, the examples and the example configuration in `share/paw`. `nix run .` runs `paw`. |
| `.#paw`, `.#paw-gui`, `.#paw-mcp`, `.#chain-lsp` | One program of the default package. One build gives all of them. `chain-lsp` is the language server of the [chain language](chain-language.md), which works in any editor and needs nothing else of paw. |
| `.#paw-utau` | The default package with `extensions/utau` and its engine. |
| `.#utau-engine` | The engine of `extensions/utau` alone. |
| `.#paw-sampler` | The plugin and the command of `extensions/sampler` alone. |
| `.#paw-pod` | The pod image: paw in a BrowserPod pod, with the page files. `x86_64-linux` only. See [paw in a BrowserPod pod](../../web/browserpod/README.md). |
| `.#paw-pod-bin` | paw for a BrowserPod pod alone, a WebAssembly program. `x86_64-linux` only. |
| `.#default.programs` | The programs as cargo builds them, without wrappers. |
| `.#default.deps` | The compiled dependencies of the workspace. |
| `.#default.extensions` | Each extension as a package that holds `share/paw/extensions/<name>`. |
| `.#default.withExtensions` | A function that gives the default package with some extensions: `paw.withExtensions (exts: [ exts.utau ])`. |

The package loads each extension of `withExtensions` at the start, before the configuration, through `PAW_EXTENSIONS`.

## What the package does for the programs

- The programs have the paths of the libraries of the graphical window (Wayland, xkbcommon, X11, fontconfig, OpenGL) and of the libraries that plugins built elsewhere open by name, so the programs run from any shell.
- The graphical window draws with the OpenGL driver of the system. On NixOS,
  `hardware.graphics.enable` gives it.
- LuaJIT has `LUAJIT_ENABLE_CHECKHOOK`, as `.cargo/config.toml` asks, so `paw.limit` can stop a loop that does not end.
- The Lua runtime and the fonts of the graphical window are in the binaries.
- The extensions, `examples` and `config` are in `share/paw`. Each program starts with `PAW_HOME` set to that directory, unless you set it, and `paw doctor` finds its script there. To load a packaged extension, use
  `paw.ext.load(os.getenv("PAW_HOME") .. "/extensions/sections")`.
- `ffmpeg` and `fc-list` are on the `PATH` of the programs, after your own
  `PATH`. paw uses `ffmpeg` only to render MP3, Ogg Vorbis and Opus.
  `paw.opt.ffmpeg` names a different program.
- The package does not install `docs/`, so `:help` has the pages of the extensions but not the manual, unless `PAW_HOME` names a source tree.

## Checks

`nix flake check` builds the program and runs the checks in the table below.

| Check | Effect |
| --- | --- |
| `clippy` | Runs clippy on all targets of the workspace but the graphical window, the fuzz targets in `fuzz/` included, with `--deny warnings`. It fails on a finding of a lint of `[workspace.lints]` in `Cargo.toml`, and on an `#![expect(...)]` that no finding fulfils. |
| `rustlint` | Runs the pattern rules of `tools/ast-grep/rules` with `ast-grep scan` and their examples with `ast-grep test`. It fails on a function that only gives a constant, on a `#[serde(default = "...")]`, on a helper such as `is_zero` that tests one value, and on a module of the model of paw-core that names the session, the sync, the API or the kernel. |
| `machete` | Runs cargo-machete. It fails when a crate lists a dependency that its code does not use. |
| `deny` | Runs `cargo deny check bans licenses sources` with `deny.toml`. It fails on a license that is not on the permissive list of the file, and on a source that is not crates.io. |
| `fmt` | Runs `cargo fmt --check`. It reports how many places would change and does not fail. |
| `tests` | Runs the Rust tests that need no display, audio device or Lua suite, with cargo-nextest. These must pass. A test fails when its output is not the same as the saved file in a `snapshots/` folder, and the check writes no new file. |
| `docs` | Runs Vale on `README.md`, `AGENTS.md`, `docs/`, the READMEs of the crates and extensions, the `doc/` pages of the extensions, `bench/README.md` and `bench/DAWS.md`. It fails on an error. |
| `chaindeps` | Fails if a crate of the chain language (`crates/chain-*`, which are `chain-syntax` and `chain-lsp`) depends on a crate of paw. |
| `paw` | Builds the program. |

The build does not run tests. See [How to run the tests](../how-to/run-the-tests.md).
