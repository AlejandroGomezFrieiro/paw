# The Nix package

<!-- tags: nix-package flake -->

The flake builds paw for `x86_64-linux` and `aarch64-linux`. It does not
need the dev shell.

## Outputs

| Output | Holds |
| --- | --- |
| `.#default` | `paw`, `paw-gui` and `paw-mcp`, with the extensions, the examples and the example configuration in `share/paw`. `nix run .` runs `paw`. |
| `.#paw`, `.#paw-gui`, `.#paw-mcp` | One program of the default package. One build gives all three. |
| `.#paw-utau` | The default package with `extensions/utau` and its engine. |
| `.#utau-engine` | The engine of `extensions/utau` alone. |
| `.#paw-sampler` | The plugin and the command of `extensions/sampler` alone. |
| `.#default.programs` | The programs as cargo builds them, without wrappers. |
| `.#default.deps` | The compiled dependencies of the workspace. |
| `.#default.extensions` | Each extension as a package that holds `share/paw/extensions/<name>`. |
| `.#default.withExtensions` | A function that gives the default package with some extensions: `paw.withExtensions (exts: [ exts.utau ])`. |

The package loads each extension of `withExtensions` at the start, before
the configuration, through `PAW_EXTENSIONS`.

## What the package does for the programs

- The programs have the paths of the libraries of the graphical window
  (Wayland, xkbcommon, X11, fontconfig, OpenGL). They also have the paths of
  the libraries that plugins built elsewhere open by name. So the programs
  run from any shell.
- The graphical window draws with the OpenGL driver of the system. On NixOS,
  `hardware.graphics.enable` gives it.
- LuaJIT has `LUAJIT_ENABLE_CHECKHOOK`, as `.cargo/config.toml` asks. So
  `paw.limit` can stop a loop that does not end.
- The Lua runtime and the fonts of the graphical window are in the binaries.
- The extensions, `examples` and `config` are in `share/paw`. Each program
  starts with `PAW_HOME` set to that directory, unless you set it. `paw
  doctor` finds its script there. To load a packaged extension, use
  `paw.ext.load(os.getenv("PAW_HOME") .. "/extensions/sections")`.
- `ffmpeg` and `fc-list` are on the `PATH` of the programs, after your own
  `PATH`. paw uses `ffmpeg` only to render MP3, Ogg Vorbis and Opus.
  `paw.opt.ffmpeg` names a different program.
- The package does not install `docs/`. So `:help` has the pages of the
  extensions but not the manual, unless `PAW_HOME` names a source tree.

## Checks

`nix flake check` builds the program and runs these checks:

| Check | Effect |
| --- | --- |
| `clippy` | Runs clippy on all targets. It reports the warnings and does not fail. |
| `fmt` | Runs `cargo fmt --check`. It reports how many places would change and does not fail. |
| `tests` | Runs the Rust tests that need no display, audio device or Lua suite, with cargo-nextest. These must pass. |
| `docs` | Runs Vale on `README.md`, `AGENTS.md`, `docs/`, the READMEs of the crates and extensions, the `doc/` pages of the extensions, `bench/README.md` and `bench/DAWS.md`. It fails on an error. |
| `paw` | Builds the program. |

The build does not run tests. See [How to run the tests](../how-to/run-the-tests.md).
