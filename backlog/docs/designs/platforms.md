# Platforms: what ties paw to Nix and to Linux, and how to cut the ties

TASK-37 (Platforms 0), milestone m-1. An audit and a design, no code
changed. It refines TASK-38 (standalone Linux), TASK-39 (macOS),
TASK-40 (Windows), TASK-41 (Android and others) and TASK-42 (CI and
release). Audited at `ccb3d6d8` (2026-11-21).

## Summary

- **Nix is a convenience, not a requirement, for the core.** The Rust
  workspace builds with plain cargo once the system has five things:
  a C compiler with make (LuaJIT is vendored by mlua), `pkg-config`,
  the ALSA headers, the PipeWire headers (cpal's `pipewire` feature)
  with **libclang** for bindgen, and the lilv library (LV2). Nothing in
  the Rust source reads a Nix path at build time except two optional
  environment variables (`PAW_GUI_LIBS`, `PAW_PLUGIN_LIB_DIRS`) that
  write RPATHs. See "The build outside the dev shell" for the exact
  failures, in order.
- **What only Nix does today:** the install layout (`share/paw` beside
  the binaries, `PAW_HOME` set by a wrapper, `PAW_EXTENSIONS` for
  chosen extensions, ffmpeg/fc-list/curl put on `PATH`), the native
  parts of extensions (sampler's CLAP, utau's .NET engine, ara's bridge
  and test plug-in), every test plugin of the suite (LSP, Surge XT,
  NAM, sfizz, ARA test plug-in and the `PAW_TEST_*` packages), the
  test tools (Xvfb, openbox, xdotool, tesseract, ImageMagick, Vale with
  its style packages, `tl`), and every install page of the manual.
  There is no CI outside `nix flake check`; there is no `.github/`.
- **Linux ties are many but shallow and well located.** About 40 places
  in 8 crates. The deep ones are four: (1) the **plugin sandbox**
  (`memfd_create` + `futex` + socketpair fd passing + `PR_SET_PDEATHSIG`
  + process groups), which also carries Lua devices; (2) the **ALSA
  sequencer MIDI** (raw `alsa-sys`, MIDI 2.0 UMP); (3) **plugin editor
  windows** (X11 through x11rb; CLAP `x11` and VST3 `X11EmbedWindowID`
  only); (4) **Unix domain sockets** as the one local IPC (control
  socket, `paw ctl`, `attach`, `paw-gui`, `paw-mcp`, the Lua `sock_*`
  API that utau uses). The rest (termios, signals, inotify, statvfs,
  `/proc`, `/sys`, `/dev/urandom`, XDG folders, `localtime_r`, inode
  numbers, `OsStrExt`) has a well-known cross-platform crate.
- **macOS is the natural second platform:** it is Unix, so rustix,
  Unix sockets, signals, termios and POSIX shm stay; the work is
  CoreMIDI, the sandbox's wake primitive, Cocoa plugin windows,
  bundle paths and signing. **Windows is the larger port:** no fork,
  no Unix sockets in std, no termios, no mmap in the C library that
  `dsp.lua` calls through FFI, `sh` in several Lua files.
- **Recommended order:** standalone Linux (TASK-38) with a "portability
  seam" refactor first, then macOS, then Windows, with CI per target
  growing from the first part. Android and iOS stay feasibility notes;
  ARM Linux is almost free (the flake already builds `aarch64-linux`);
  FreeBSD is a cheap side effect of the seams if the owner wants it.

## The build outside the dev shell

The machine is NixOS, so a "stock distro" was simulated: `env -i` with
only `cargo`, `rustc`, `gcc` and `make` on `PATH` (from `nix shell`,
not the dev shell), a fresh `CARGO_TARGET_DIR` in the scratchpad, then
`cargo build --release -j 8 --keep-going`. Each run added only what
the previous one asked for. Nothing was installed system-wide.

| Run | Given | Result |
| --- | --- | --- |
| 1 | cargo, rustc, gcc, make | 407 of 409 crates compile, **LuaJIT and mlua included** (vendored, built with gcc and make), paw-core, paw-gui and paw-mcp included. Fails: `libspa-sys` (needs `pkg-config` for `libpipewire-0.3`) and `alsa-sys` (needs `pkg-config` for `alsa`). |
| 2 | + pkg-config, the ALSA and PipeWire `.pc` files | `alsa-sys` passes. Fails: `libspa-sys`: "Unable to find libclang" (bindgen). |
| 3 | + libclang, glibc headers for bindgen, lilv/ALSA/PipeWire libraries on `LIBRARY_PATH` | **Success** in 2 min 29 s: `paw` (38 MB), `paw-gui` (25 MB), `paw-mcp` (11 MB). `paw` links `libasound.so.2`, `libpipewire-0.3.so.0`, `liblilv-0.so.0` (and glibc). `paw --clean --no-plugins --audio null -l smoke.lua` runs and exits 0. Run from another folder, `paw.ext.bundled_dir()` is nil: without `PAW_HOME` the bundled extensions are found only when the current folder is the source tree. |

So the package list of a stock distro is (Debian/Ubuntu names):
`build-essential pkg-config libasound2-dev libpipewire-0.3-dev
libclang-dev liblilv-dev` (and `clang` for bindgen's headers). Fedora:
`gcc make pkgconf alsa-lib-devel pipewire-devel clang-devel
lilv-devel`. At run time: `libasound2 libpipewire-0.3-0 liblilv-0-0`,
and for the window the system's libGL/EGL, Wayland or X11 libraries,
xkbcommon and fontconfig (`fc-list`), which every desktop has.

Two cheap changes remove most of the list (part L1, below): make cpal's
`pipewire` feature optional and Linux-only (cpal's ALSA host, which
reaches PipeWire through pipewire-alsa, needs only `libasound`); and
make LV2 (`lilv-sys`) a default-on cargo feature that a packager can
turn off. Without them, the bindgen step is the single worst part of a
plain `cargo build` (libclang plus the right C headers).

## Inventory 1: ties to Nix

### flake.nix

| Output | What it does that cargo does not | Replacement outside Nix |
| --- | --- | --- |
| `packages.default` (`paw`) | Builds the workspace with crane; installs `extensions examples config runtime tlconfig.lua` in `share/paw`; wraps each binary with `PAW_HOME=$out/share/paw` and puts `ffmpeg-headless`, `fontconfig.bin` (fc-list) and `curl` last on `PATH`. | Find `share/paw` from the binary (`<exe>/../share/paw`, then `<exe>/..` in a source tree) instead of a wrapper. ffmpeg, fc-list, curl become documented optional run-time tools that `:checkhealth` reports. |
| `programs` | Sets `PAW_GUI_LIBS` and `PAW_PLUGIN_LIB_DIRS` so `paw-gui/build.rs` writes RPATHs and `paw-plugins/src/libs.rs` bakes library folders in; `patchelf --add-rpath` after fixup. | On a normal distro the loader finds these libraries; both variables are optional already (unset = nothing written). Keep them for Nix only. |
| `withExtensions`, `homeManagerModules.default` | Loads chosen extensions through `PAW_EXTENSIONS` (colon list). | The bundled `share/paw/extensions` and the user's config. Use the platform's path list separator (`;` on Windows). |
| `extensionsFor` (`extensions/*/nix/default.nix`) | Builds native parts: **sampler** (Rust CLAP + command, crane), **utau** (`buildDotnetModule`, .NET 10, OpenUtau pinned, `autoPatchelfHook`, `libworldline.so` from OpenUtau's `runtimes/linux-*`), **ara** (C++ bridge `paw-ara.so` against the ARA SDK + CLAP 1.1.9 fetched by hash; the SDK's test plug-in). | Sampler: a cargo workspace member or `cargo build` in CI (pure Rust, no Nix need; `native/build.sh` calls `nix develop` today). utau: `dotnet publish` (its README already says how) per RID (`linux-x64`, `osx-arm64`, `win-x64`). ara: CMake or cc-rs build of `bridge.cpp` with the SDK as a git submodule or a fetched archive. |
| `checks` | clippy, fmt (report only), nextest without display/plugins, the program, Vale, `tl check`. | The same commands in CI per platform (TASK-42). |
| `devShells.default` | Toolchain, sccache, `bindgenHook`, ffmpeg, xmllint; Xvfb, openbox, xdotool, ImageMagick, tesseract, Vale + styles (incl. AiTells fetched by hash), curl, `tl`; `LD_LIBRARY_PATH` for the window; `PAW_TEST_PLUGINS` (lsp-plugins, surge-xt, neural-amp-modeler-lv2, sfizz-ui), `PAW_TEST_NAM_MODELS`, `PAW_TEST_ARA`, `PAW_ARA_BRIDGE`. | A documented "test tools" list per OS; CI installs them from the distro or Homebrew/winget; tests skip a plugin test when its `PAW_TEST_*` is unset (most do already). |
| `systems` | `x86_64-linux`, `aarch64-linux` only. | Add `aarch64-darwin` later only if the owner wants Nix on macOS (optional). |

### Scripts and tests that call Nix

| File | Tie |
| --- | --- |
| `tests/tools/suite.sh` (`plugins` mode) | Calls `nix develop -c sh -c ...` itself to read `PAW_TEST_*` store paths. The default mode (`--no-plugins`) needs only the binary. |
| `extensions/sampler/native/build.sh` | `nix develop "$root" -c cargo build`. |
| `tools/vale.sh`, `tools/tlcheck.sh` | Need `PAW_VALE_STYLES` and `tl` from the dev shell. |
| `tests/tools/gui.sh`, `crates/paw-gui/tests/window.rs` | Xvfb, openbox, xdotool, tesseract, ImageMagick. Linux/X11 only by nature. |
| `tests/tools/e2e.sh` | Not audited in depth (owner rule: not run by agents). |
| `docs/images/make/make.sh` | `nix` twice. |

### Docs that give only Nix instructions

`README.md` (2), `docs/how-to/install-paw.md` (title "How to install paw
with Nix", 5), `docs/how-to/build-paw-from-source.md` (starts with `nix
develop`), `docs/how-to/run-the-tests.md` (4), `docs/how-to/load-an-extension.md`,
`docs/how-to/sign-in-to-tone3000.md`, `docs/reference/nix-package.md`,
`docs/reference/extensions.md`, `docs/reference/limits.md`,
`docs/explanation/about-the-nix-build.md`, `docs/explanation/about-the-e2e-tests.md`,
`crates/paw-gui/README.md`, `crates/paw-mcp/README.md` (2),
`extensions/sampler/README.md`, `extensions/utau/README.md` (2; it also
gives a `dotnet publish` path), `extensions/interop/README.md`. There is
no page for "install without Nix", for system packages, or for any OS
but Linux. `build-paw-from-source.md` mentions "bridged Windows plugins
start Wine": the Wine bridges (yabridge) are a Linux-only concept.

### Plugin search paths that assume NixOS

- `crates/paw-plugins/src/lib.rs:543-565` (`usual_dirs`): `~/.{clap,vst3,lv2}`,
  `~/.nix-profile/lib/<fmt>`, `/etc/profiles/per-user/$USER/lib/<fmt>`,
  `/run/current-system/sw/lib/<fmt>`, `/usr/local/lib/<fmt>`, `/usr/lib/<fmt>`.
  Correct for Linux (the Nix entries are harmless elsewhere), wrong for
  macOS and Windows.
- `crates/paw-plugins/src/libs.rs:22-70`: preloads `libX11.so.6` and others
  and searches `PAW_PLUGIN_LIBS`, `NIX_LD_LIBRARY_PATH`, the baked
  `PAW_PLUGIN_LIB_DIRS`, nix-ld, `/run/current-system/sw/lib`,
  `~/.nix-profile/lib`, `/usr/lib/x86_64-linux-gnu`, `/usr/lib64`, `/usr/lib`,
  `/lib64`. A NixOS workaround; it does nothing on other distros except that
  `x86_64-linux-gnu` is hard-coded (should be the target triple). Linux only.
- `crates/paw-plugins/src/presets.rs:380-384`: `~/.vst3/presets`,
  `/usr/share/vst3/presets`, `/usr/local/share/vst3/presets`.

## Inventory 2: ties to Linux and Unix

Legend for "Mac" and "Win": **ok** builds and works as is; **port**
needs a per-OS implementation; **gate** compile it out or skip it.

### paw-engine

| Place | Tie | Mac | Win | What instead, and the crate |
| --- | --- | --- | --- | --- |
| `Cargo.toml` `cpal = { features = ["pipewire"] }` | PipeWire host (bindgen, libclang) | gate | gate | `[target.'cfg(target_os = "linux")'.dependencies]` for the feature. cpal covers CoreAudio and WASAPI (and ASIO behind its `asio` feature, which needs the Steinberg SDK and its license). |
| `backend/cpal.rs:67-150` | Ranks hosts `pipewire`, `jack`; PipeWire device naming | ok | ok | Generic already; add `coreaudio`, `wasapi`, `asio` names to the ranking and the docs. |
| `midi.rs:144-440`, `midi_out.rs:127-230`, `alsa.rs`; feature `midi = ["dep:alsa-sys"]` | ALSA sequencer, in and out, MIDI 2.0 UMP (`snd_seq_set_client_midi_version`, `snd_seq_ump_event_input`), `poll` on its descriptors | port | port | A `MidiBackend` trait behind the existing feature seam (there is a `not(feature = "midi")` stub already). macOS: `coremidi` crate (MIDIEventList is UMP, macOS 11+). Windows: `midir` (WinMM, MIDI 1.0, up-converted by `ump.rs`) now; Windows MIDI Services (UMP) later through `windows` crate bindings. `midir` can be the portable MIDI 1.0 fallback everywhere. |
| `pool.rs:297-345` | `pthread_getschedparam` / `setschedparam`, `SCHED_FIFO`, `SCHED_RESET_ON_FORK` (`cfg(unix)` / `linux`, with a `not(unix)` stub) | port | port | Workers must join the audio thread's class: macOS audio workgroups (`os_workgroup_join`, the device's workgroup through CoreAudio) or Mach time-constraint policy; Windows MMCSS (`AvSetMmThreadCharacteristicsW("Pro Audio")`). `audio_thread_priority` (Mozilla) does both; its D-Bus cost (the reason it is not used, `pool.rs:320`) is Linux only. |
| `record.rs:404-414` | `SIGXFSZ`, `setrlimit` | test only | gate | `cfg(unix)` on the test. |
| `samples.rs:203` | `OsStrExt` (bytes of a path) | ok | port | `OsStr::as_encoded_bytes` (std, all OS). |
| `Cargo.toml` `rustix` (`event`, `process`) | poll for MIDI | ok | gate | Goes with the MIDI trait. |

### paw-plugins (and paw-luadev, whose devices run in the same sandbox)

| Place | Tie | Mac | Win | What instead, and the crate |
| --- | --- | --- | --- | --- |
| `sandbox/shm.rs:214-240` | `memfd_create` + `ftruncate` + `mmap` | port | port | macOS: `shm_open` with a random name, unlinked at once, fd passed (rustix `shm`); Windows: `CreateFileMappingW` (pagefile-backed) and a duplicated handle. `memmap2` maps both; `shared_memory` crate wraps both. |
| `sandbox/shm.rs:369-382`, `serve.rs:52-65`, `device.rs:169-216` | `futex` wait/wake across processes, on the audio thread, with a time limit | port | port | macOS 14.4+: `os_sync_wait_on_address_with_timeout` / `os_sync_wake_by_address_any` with `OS_SYNC_*_SHARED` (public, same shape as futex); older macOS: a Mach semaphore per direction. Windows: `WaitOnAddress` is in-process only, so a pair of auto-reset Event handles (`WaitForSingleObject` with a timeout, `SetEvent`). A `Doorbell` trait with three impls; no crate does this real-time safely. |
| `sandbox/factory.rs:55-110` | `UnixStream::pair`, fds passed by number, `pre_exec`: `fcntl_setfd` (clear CLOEXEC), `PR_SET_PDEATHSIG`, `setpgid` | port | port | Mac: keep socketpair + fd numbers; replace PDEATHSIG with "the helper exits when its socket closes" (it already reads the socket) plus a kqueue `EVFILT_PROC` watch on the parent; `setpgid` stays. Windows: a named pipe (or AF_UNIX socket, Windows 10 1803+) and the mapping handle inherited through `STARTUPINFOEX` handle lists; a **Job object** with `KILL_ON_JOB_CLOSE` replaces both PDEATHSIG and the process group (`win32job` crate). |
| `sandbox/controller.rs:59-61,127-138` | `kill_process_group(SIGKILL)`; `/proc/<pid>/stat` CPU time; `clock_ticks_per_second`; `ExitStatusExt` signal | port | port | `sysinfo` (or `proc_pid_rusage` on mac, `GetProcessTimes` on Windows) for CPU; kill by Job on Windows; signal of an exit is Unix only (show the exit code on Windows). |
| `sandbox/serve.rs:91-96`, `sandbox/device.rs:102-105` | Helper's audio thread copies the DAW's `SCHED_FIFO` policy | port | port | The same thread-class helper as `pool.rs`. |
| `sandbox/wire.rs:5`, `lib.rs:451` | `std::os::unix::net::UnixStream`, `ExitStatusExt` | ok | port | `interprocess::local_socket` (Unix sockets and Windows named pipes behind one type, with tokio support). |
| `window.rs` (whole file, 23 KB) | Plugin editor windows with `x11rb`; X authority search (`~/.Xauthority`, `$XDG_RUNTIME_DIR`); `RTLD_NOLOAD` probe | port | port | A `HostWindow` trait. macOS: an `NSWindow`/`NSView` (objc2-app-kit) on the helper's main thread; Windows: a Win32 `HWND`. `baseview` (RustAudio) is a parent-window crate for exactly this, on all three; or winit with raw-window-handle. |
| `clap.rs:1063-1335` | `GuiApiType::X11` only; `posix-fd` extension (`clap.rs:38,279,1685,1774`) | port | port | Ask `cocoa` on macOS, `win32` on Windows (clack has both). `posix-fd` is Linux/macOS only: gate it on Windows (plugins use timers there). |
| `vst3.rs:83,105-114,133,1710-1740` | Bundle path `Contents/<arch>-linux/<name>.so`; `X11EmbedWindowID`; `IRunLoop` with fds (a Linux-only VST3 interface); `libloading::os::unix` | port | port | Mac: `Contents/MacOS/<name>` and `bundleEntry`/`bundleExit` with a CFBundleRef (not `ModuleEntry`); `NSView` platform type. Windows: `Contents/x86_64-win/<name>.vst3` (a DLL), `InitDll`/`ExitDll`, `HWND`. `IRunLoop` only on Linux. `libloading::Library` (portable type). |
| `lv2/*`, `lilv-sys` | LV2 through system lilv | gate | gate | LV2 is a Linux format in practice: a default-on `lv2` feature, off on macOS and Windows. |
| `libs.rs` (whole) | NixOS library search, `.so` names, `libloading::os::unix` with `RTLD_LOCAL` | gate | gate | `cfg(target_os = "linux")`; elsewhere `open_library` is `Library::new`. |
| `lib.rs:543-565`, `presets.rs:380-384` | Linux plugin folders | port | port | Per-OS lists: macOS `~/Library/Audio/Plug-Ins/{CLAP,VST3}`, `/Library/Audio/Plug-Ins/{CLAP,VST3}`; Windows `%COMMONPROGRAMFILES%\{CLAP,VST3}`, `%LOCALAPPDATA%\Programs\Common\{CLAP,VST3}`; the `CLAP_PATH`/`VST3_PATH` variables use `;` on Windows (`env::split_paths` already does). |
| `attach.rs` + `include/paw_attach.h` | Attachments loaded as `.so` | port | port | `.dylib` / `.dll` by `std::env::consts::DLL_EXTENSION`. |
| `Cargo.toml` `x11rb`, `rustix` (`fs mm param process thread`) | (dependency) | gate | gate | Target-specific dependencies. |
| Wine bridges (yabridge) in docs and scans | Linux only | gate | n/a | On Windows the plugins are native; on macOS there is no Wine story. |

### paw-core

| Place | Tie | Mac | Win | What instead, and the crate |
| --- | --- | --- | --- | --- |
| `rpc.rs:24-36,140-165` | Control socket: tokio `UnixListener` at `$XDG_RUNTIME_DIR/paw.sock`, stale-socket probe | ok | port | `interprocess` local socket (named pipe `\\.\pipe\paw-<user>`), or the TCP+TLS listener that already exists (`--listen-tcp`) bound to loopback with the token. Named pipe recommended: no port, per-user ACL. |
| `rpc.rs:282` | Token file mode `0o600` (`OpenOptionsExt`) | ok | port | On Windows the file in `%LOCALAPPDATA%` is per-user already; skip the mode. |
| `rpc.rs:302` | `/dev/urandom` for the nonce | ok | port | `ring::rand::SystemRandom` (ring is already a dependency) or `getrandom`. |
| `tls.rs:35`, `ext_api.rs:92` | File modes (`0o600`, executable bit) | ok | gate | `cfg(unix)`. |
| `io.rs` (whole, the Lua `proc_*` and `sock_*` API) | `poll(2)` on pipes, `fcntl O_NONBLOCK`, `UnixListener`/`UnixStream`, `PR_SET_PDEATHSIG` (`cfg(linux)`), `kill(SIGTERM)` | ok (minus PDEATHSIG) | port | The kernel already has a tokio runtime (`io_runtime`): use `tokio::process` pipes and `interprocess` sockets; a Job object on Windows. `sock_listen(path)` takes a name that becomes a named pipe on Windows. utau's .NET engine speaks Unix sockets, which .NET supports on Windows 10+ too; keep its socket on a path in `%TEMP%` or move it to the same named-pipe scheme. |
| `bake/helper.rs:93-170`, `session/encode.rs:314-340`, `bake/native.rs:61` | ffmpeg and bake helpers: PDEATHSIG (`cfg(linux)`), `kill(SIGTERM)`, `setpriority(10)` | ok (minus PDEATHSIG) | port | `tokio::process::Command::kill_on_drop` is already set; Job object on Windows; `BELOW_NORMAL_PRIORITY_CLASS` creation flag for the nice level. |
| `session/files_watch.rs` | `inotify` (rustix), `OsStrExt` | port | port | `notify` crate (FSEvents/kqueue, ReadDirectoryChangesW, inotify), keeping the "watch folders, not files" rule. |
| `safe.rs:67-80`, `api/system.rs:61` | `statvfs` (free space), directory fsync | ok | port | `fs4::available_space` / `sysinfo`; directory fsync is not possible on Windows (skip; `MoveFileExW` with `WRITE_THROUGH` for the rename). |
| `session.rs:769` | `/sys/devices/system/cpu/*/topology` (physical cores) | port | port | `sysinfo` physical core count, or `num_cpus::get_physical`. Falls back to `available_parallelism` already. |
| `fs_api.rs:31,50,104-106,148` | `EXDEV`, `symlink`, `time` + `localtime_r` | ok | port | `io::ErrorKind::CrossesDevices` (std 1.85); `std::os::windows::fs::symlink_file` needs Developer Mode: fall back to a copy; `jiff` for local time. |
| `media/index.rs:16,39-40` | `MetadataExt` mtime ns and inode | ok | port | `Metadata::modified()` for time; no inode on stable Windows: use 0 (size+mtime+hash still catch changes). |
| `kernel.rs:396-399` | `malloc_trim` | gated (`gnu`) | gated | Nothing to do. |
| `Cargo.toml` `mlua` luajit vendored; `.cargo/config.toml` `TARGET_CFLAGS=-DLUAJIT_ENABLE_CHECKHOOK`; `build.rs` | LuaJIT built by `luajit-src` | ok (arm64 and x86_64) | check | `luajit-src` builds with MSVC through `msvcbuild.bat`, which may ignore `TARGET_CFLAGS`: then `paw.limit` falls back to interpreting hot loops (the documented fallback). Make sure of it and, if needed, patch through `luajit-src`'s MSVC flags. `build.rs` already skips bytecode when cross-compiling. |
| `Cargo.toml` `rustix` (`event fs process`) | (dependency) | ok | gate | Target-specific. |

### paw-tui (the `paw` binary)

| Place | Tie | Mac | Win | What instead, and the crate |
| --- | --- | --- | --- | --- |
| `terminal.rs:22-24,68-90` | `termios` save/restore, `signal_hook` for SIGTERM/SIGHUP, raw `write` to stdout | ok | port | crossterm already does raw mode on all three; restore through crossterm; Windows console events through `ctrlc`/`SetConsoleCtrlHandler`. |
| `terminal.rs:207-240` | Terminal probe reads `/dev/tty` with `poll` | ok | port | `crossterm::event::poll/read` (or `CONIN$`). Windows Terminal answers DA1 and supports Sixel, not the kitty graphics protocol. |
| `main.rs:27-51` | `dup2` stderr into a log file | ok | port | `SetStdHandle(STD_ERROR_HANDLE)` or route `tracing`/`log` to the file instead of fd 2. |
| `main.rs:20-60`, `args.rs:85,109` | `~/.config/paw`, `$XDG_RUNTIME_DIR/paw.sock` in help texts | ok | port | See paw-proto `dirs`. |
| `Cargo.toml` `signal-hook`, `rustix termios` | (dependency) | ok | gate | Target-specific. |

### paw-proto, paw-mcp, paw-gui, paw-raster, paw-listen

| Place | Tie | Mac | Win | What instead, and the crate |
| --- | --- | --- | --- | --- |
| `paw-proto/src/dirs.rs` (whole) | XDG folders by hand (`$XDG_*_HOME` else `~/.config` and so on); runtime dir `$XDG_RUNTIME_DIR` else temp | decide | port | `directories`/`etcetera`. Recommendation: keep XDG on Linux and BSD; macOS `~/Library/Application Support/paw` (config and data), `~/Library/Caches/paw`; Windows `%APPDATA%\paw` (config), `%LOCALAPPDATA%\paw` (data, state, cache). `etcetera` can also give XDG on macOS, which terminal users often prefer: see open question 3. |
| `paw-proto/src/lib.rs:25,87` | tokio `UnixStream` client | ok | port | `interprocess` (tokio). |
| `paw-mcp/src/kernel.rs:13-20,155-165,176,226-248` | Unix socket, PDEATHSIG, `recv(MSG_PEEK)` liveness | ok (minus PDEATHSIG) | port | Same seam as above. |
| `paw-gui/src/client.rs:5,236-265` | Starts `paw --headless --listen <socket>` with `libc::prctl(PR_SET_PDEATHSIG)` **without a cfg**: does not compile on macOS | port | port | The shared "child dies with parent" helper. |
| `paw-gui/src/main.rs:69-125,287` | `/dev/dri` probe, X authority repair, `WAYLAND_DISPLAY` repair, `libc::kill` | gate | gate | Linux only (`cfg`). |
| `paw-gui/Cargo.toml` | `egui-winit` features `x11 wayland`; `glutin` features `egl glx x11 wayland` | port | port | Add target-specific features: macOS `cgl`, Windows `wgl` (and `egl` for ANGLE). winit itself is portable. |
| `paw-gui/src/portal.rs`, `ashpd` | File dialogs through the XDG desktop portal over D-Bus | gate | gate | `rfd` (NSOpenPanel, IFileDialog, and the XDG portal on Linux). The fallback to the kernel's list picker stays. |
| `paw-gui/src/theme.rs:134-160` | `fc-list` subprocess for a CJK font | port | port | `fontdb` (system font scan on all three) or `font-kit`. |
| `paw-gui/build.rs` | RPATH from `PAW_GUI_LIBS` | ok | ok | Only acts when the variable is set. |
| `paw-gui/tests/window.rs`, `tests/tools/gui.sh` | Xvfb, openbox, xdotool, tesseract | gate | gate | Linux CI only; macOS/Windows get `egui_kittest` tests only. |
| `paw-raster/src/kitty.rs:18,86,313-345` | POSIX `shm_open` for the kitty protocol's shared-memory transfer | ok | gate | Windows: direct (base64) transfer only; it already is the fallback. |
| `paw-listen` `cpal = { features = ["pipewire"] }` | As paw-engine | gate | gate | Same Linux-only feature. |

### The Lua runtime and the extensions

| Place | Tie | Mac | Win | What instead |
| --- | --- | --- | --- | --- |
| `runtime/lua/paw/dsp.lua:27-34,108-130` | LuaJIT FFI to libc `open`, `lseek`, `mmap(..., 0x8002 = MAP_PRIVATE\|MAP_POPULATE)`, `munmap` | port (flag) | port | A kernel function exported to the FFI (`paw_map_file`, `paw_unmap`) or a `paw.api` call that returns a pointer and length, so the Lua side has no libc. This also helps TASK-29 (Web 1), which must gate the FFI. |
| `runtime/lua/paw/lang.tl:198,210` | `io.popen(cmd .. " 2>&1")`, `os.execute("mkdir -p ...")`, shell quoting | ok | port | `paw.api.proc_spawn` with an argv; `paw.fs` mkdir. |
| `runtime/lua/paw/health.lua:157,201` | `io.popen("git ... 2>/dev/null")`, `fc-list` | ok | port | `proc_spawn`; the font check moves to the kernel (`fontdb`). |
| `runtime/lua/paw/lang.tl:129`, `extensions/utau/lua/utau/engine.lua:55,167`, `extensions/tutor/make-docs.lua:7` | `HOME`, `TMPDIR`, `/tmp` | ok | port | `paw.api.env()` with the platform's cache and temp folders. |
| `runtime/lua/paw/ext.lua:649-695`, `init.lua:322`, `help.tl:292-306` | `PAW_EXTENSIONS` split on `:`; bundled extensions and `docs/` found through `PAW_HOME` or the current folder | port | port | The kernel gives the install's `share/paw` (exe-relative) and the list separator. **Needed for TASK-38 already** (an archive with no wrapper). |
| `extensions/notation/lua/notation/operators.lua:582` | `io.popen("(" .. cmd .. ") < 'file' 2>&1")` | ok | port | `proc_spawn` with stdin from a file. |
| `extensions/projdiff/lua/projdiff/init.lua:74-77` | `git -C` through `io.popen` with `2>/dev/null` | ok | port | `proc_spawn`. |
| `extensions/plugstate/lua/plugstate/tone3000_api.lua:141-142,293`, `tone3000_auth.lua` | A `sh` script with `command -v`, `timeout`; `secret-tool` (libsecret) for the key | ok (no secret-tool) | port | `curl` ships with macOS and Windows 10+; drop the `sh` wrapper for an argv; the keyring through a kernel API over the `keyring` crate (Keychain, Credential Manager, Secret Service). |
| `extensions/doctor/lua/doctor/checks.lua:714` | `/tmp/.X11-unix/X<n>` | gate | gate | Linux-only check. |
| `extensions/ara/lua/ara/init.lua:18`, `runtime/lua/paw/plugins.lua:61` | `lib/paw-ara.so` | port | port | By the platform's library suffix. |
| `extensions/utau` (engine) | .NET engine, `libworldline.so` from OpenUtau `runtimes/linux-*`, Unix socket | ok | ok | OpenUtau ships `osx-*` and `win-*` worldline builds; `dotnet publish -r <rid>`. |
| `extensions/sampler/native` | Rust CLAP, `.so` renamed to `.clap` | ok | ok | Rename `.dylib` into a `.clap` bundle (`Contents/MacOS`, `Info.plist`) on macOS; `.dll` to `.clap` on Windows. |
| `extensions/vinput` | Not read in depth; spawns a helper | check | check | Check in part M-0. |

## Per-platform plan

### 1. Standalone Linux (TASK-38)

Goal: `cargo build --release` on Ubuntu 24.04 and Fedora with a
documented package list, a release archive that runs without a wrapper,
and a CI job on a plain image.

1. Cut the build list (L1): cpal `pipewire` behind a Linux feature that
   is on by default in Nix and optional in a plain build; LV2 behind a
   default-on feature. Recommendation: keep PipeWire on in the release
   archive (it is the best Linux host) and build the archive on a CI
   image that has libclang; a source build may turn it off.
2. Install layout (L2): the binary finds `share/paw` from its own path
   (`<prefix>/bin/paw` -> `<prefix>/share/paw`; `<dir>/paw` ->
   `<dir>/share/paw` for an unpacked archive; the source tree as today).
   `PAW_HOME` and `PAW_EXTENSIONS` keep working as overrides. Doctor,
   help, bundled extensions and `docs/` all use the one function.
3. Archive (L3): `paw-<version>-<arch>-linux.tar.gz` with `bin/paw`,
   `bin/paw-gui`, `bin/paw-mcp`, `share/paw/{extensions,examples,config,runtime,docs}`,
   the sampler's CLAP built by cargo, the licenses. glibc baseline: build
   on the oldest supported Ubuntu LTS. utau's engine is a separate
   archive (it is 100+ MB with .NET and models), or downloaded by
   `:UtauInstall`; see open question 5.
4. Docs (L4): `docs/how-to/install-paw.md` becomes "How to install
   paw" with sections per method (archive, from source with cargo, Nix);
   `build-paw-from-source.md` gives the package list; the Nix pages stay.
5. CI (L5, TASK-42): GitHub Actions on `ubuntu-24.04`: build, `cargo
   test` (the set `nix flake check` runs), the Lua suite with
   `--no-plugins --audio null`, Vale and `tl` from their releases.
6. Later (L6): AppImage (simplest: one file, no portal needed) and
   Flatpak (needs the PipeWire/ALSA permissions and a plugin-folder
   extension point; Flathub has the `org.freedesktop.LinuxAudio` plugin
   base). AUR is a cheap PKGBUILD around the archive; a deb only if asked.

### 2. macOS (TASK-39)

Goal: Apple Silicon first (Intel by a universal build later), terminal
first in Terminal.app, iTerm2, WezTerm, Ghostty and kitty; then the
window.

Blockers, in order: (a) paw-gui's unguarded `prctl` and Linux-only
dependencies (compile errors); (b) the plugin sandbox's `memfd` and
`futex` (the Lua devices also depend on it, so even `--no-plugins` needs
it for `paw.dsp` devices); (c) MIDI (CoreMIDI); (d) plugin editor windows
(Cocoa); (e) VST3 bundle layout; (f) bundle, signing, notarization.

1. Make it compile (M1): target-specific dependencies; `cfg` the
   Linux-only parts with stubs that say "not on this system yet".
2. Sandbox on macOS (M2): POSIX shm + `os_sync_wait_on_address`
   (macOS 14.4+) behind the `Doorbell` trait; PDEATHSIG replaced by
   socket EOF + kqueue. Minimum macOS: 14.4 (recommended), or 11 with a
   Mach-semaphore doorbell.
3. CoreAudio through cpal works as is (M3: host ranking, device names,
   buffer size; audio workgroups for the worker pool).
4. CoreMIDI (M4) with the `coremidi` crate, UMP in and out.
5. Plugins (M5): CLAP and VST3 bundle paths and entry points, Cocoa
   editor windows in the helper (main thread). AU: not now (open
   question 6).
6. Window (M6): glutin `cgl`, `rfd` dialogs, `fontdb` fonts, Retina
   scale.
7. Package (M7): `paw.app` for the window, with the `paw` CLI inside
   `Contents/MacOS` and a "link the CLI" note; ad-hoc signature for
   unsigned use (open question 7), Developer ID + notarization when the
   owner has an account. Plugins need `com.apple.security.cs.disable-library-validation`
   in the helper's entitlements to load third-party plugins under the
   hardened runtime; the LuaJIT JIT needs `allow-jit` (MAP_JIT).
   Microphone access needs `NSMicrophoneUsageDescription`.

### 3. Windows (TASK-40)

Goal: Windows 10 22H2 and 11, x86_64 (ARM64 later), terminal first in
Windows Terminal; then the window.

Blockers, in order: (a) the IPC model: every Unix socket (control,
helper, Lua `sock_*`, MCP, gui) needs the local-socket seam; (b) process
model: `pre_exec` (fd passing, PDEATHSIG, process groups) becomes handle
inheritance + Job objects; (c) the sandbox's shared memory and doorbell;
(d) the terminal layer (termios, `/dev/tty`, signals, `dup2`); (e)
`dsp.lua`'s libc FFI and the `sh`-based Lua; (f) MIDI; (g) plugin paths
and HWND editors; (h) installer.

1. Seams first (W1), shared with macOS: `local_ipc` (interprocess),
   `child` (spawn with "dies with parent", priority, kill tree),
   `shm` + `Doorbell`, `dirs`, `watch` (notify), `sysinfo`-based stats.
2. Terminal (W2): crossterm only; probe through crossterm; console
   control handler; stderr log through the logger, not fd 2.
3. Lua portability (W3): `dsp.lua` through a kernel mapping call; the
   `io.popen`/`os.execute` users through `proc_spawn`; path list
   separator; temp folders.
4. Audio (W4): WASAPI through cpal, exclusive mode as an option; ASIO
   behind a cargo feature built only by users who accept the Steinberg
   SDK license (open question 8). MIDI: midir (WinMM) now.
5. Plugins (W5): `%COMMONPROGRAMFILES%` paths, VST3 `x86_64-win`, CLAP
   `.clap` DLLs, `win32` editors. No Wine bridge.
6. Window (W6): glutin `wgl`, `rfd`, `fontdb`.
7. Package (W7): a zip first; then an MSI with `cargo-wix` or an Inno
   Setup installer, and a winget manifest and a scoop bucket (both read
   a zip/MSI URL). Code signing optional at first (SmartScreen warns).

### 4. Android, ARM boards, BSD, iOS (TASK-41 notes)

- **ARM Linux (Raspberry Pi 4/5, aarch64):** already a flake system;
  everything above for Linux applies. Risks: GL ES 3.0 only (glow
  handles it), small CPUs (the performance goal), JACK/PipeWire on
  Raspberry Pi OS. **Go**, almost free once L5 has an arm64 runner.
- **FreeBSD:** cpal has no OSS host of note (ALSA via `alsa-lib` port
  works; sndio through a fork); rustix supports FreeBSD; no `memfd` but
  `shm_open(SHM_ANON)`; `_umtx_op` instead of futex; `procctl(PROC_PDEATHSIG_CTL)`;
  no inotify (notify uses kqueue). **Cheap after the seams; low
  priority; no-go for CI** unless the owner asks.
- **Android:** cpal has AAudio (Oboe through `oboe-rs`); LuaJIT's JIT
  works on Android arm64; the terminal-first rule does not hold (Termux
  only), so it needs a touch frontend over the scene protocol, files
  through SAF, no plugin formats (CLAP on Android does not exist in
  practice), no helper processes in the usual sense (a separate process
  needs a service). **Feasibility spike only, after Windows;** shares
  the portable-Lua work of TASK-29.
- **iOS:** no JIT (LuaJIT interpreter only, or the portable VM of
  TASK-29), no subprocesses (the sandbox and helpers are impossible:
  devices in-process only), AUv3 as the only plugin format. **No-go**
  for now.

## Ordered parts (sizes S, M, L)

Each part is one branch with its tests and docs. "Refines" names the
ticket it belongs to. New tickets are proposed, not created.

| # | Part | Size | Refines | What and the test |
| --- | --- | --- | --- | --- |
| P1 | `PLATFORM-SEAMS`: a `paw-sys` crate (or modules in paw-proto/paw-plugins) with `dirs`, `child` (spawn, dies-with-parent, priority, kill tree), `local_ipc`, `shm`, `Doorbell`, `random`, `cpu`/`disk` stats, `watch`; Linux impls only, moved from today's call sites, no behavior change. | L | 38 (prepares 39, 40) | The existing suite passes; one unit test per seam. |
| P2 | Target-specific dependencies and features: `pipewire` and `lv2` features, `x11rb`/`ashpd`/`signal-hook`/`alsa-sys` under `cfg(target_os = "linux")`, guard paw-gui's `prctl`. | S | 38 | `cargo build --no-default-features` on Linux; `cargo check --target aarch64-apple-darwin` and `x86_64-pc-windows-msvc` in CI show only the remaining ports (a list that shrinks). |
| P3 | Exe-relative install layout (`share/paw`), the one root function for doctor, help, bundled extensions and docs; path list separator. | S | 38 | A test that runs the binary from a copied tree with no `PAW_HOME`. |
| P4 | Plain-Linux build doc and the package list; `install-paw.md` split by method; sampler built by cargo, not `nix develop`. | S | 38 | Vale; a how-to test where it applies. |
| P5 | CI on `ubuntu-24.04` (x86_64 and arm64): build, Rust tests, Lua suite `--no-plugins`, Vale, `tl`; plus `cargo check` for macOS and Windows targets (allowed to fail at first). | M | 42 | The workflow is green. |
| P6 | Release archive for Linux from a tag, with checksums. | M | 38, 42 | The archive runs on a clean container: `paw --headless --audio null -l` smoke script. |
| P7 | `dsp.lua` without libc FFI; `io.popen`/`os.execute` users moved to `proc_spawn` and `paw.fs`; temp folder from the kernel. | M | 39, 40 (and TASK-29) | Lua suite; dsp tests. |
| P8 | macOS compile and terminal: target deps, dirs, stubs for MIDI and plugin windows, CoreAudio. | M | 39 | CI `macos-14` build and Lua suite `--no-plugins --audio null`. |
| P9 | macOS sandbox (shm + os_sync doorbell, parent death through socket EOF/kqueue): Lua devices and plugins in helpers. | M | 39 | The helper-process tests on macOS CI. |
| P10 | MIDI trait: ALSA impl moved behind it; CoreMIDI impl; midir fallback. | M | 39, 40 | Unit tests with a virtual port on macOS; ALSA tests unchanged. |
| P11 | Plugin paths, bundle loaders (CLAP, VST3) and Cocoa editor windows (`HostWindow` trait; X11 impl moved). | L | 39 | Load the sampler's CLAP and a free VST3 on macOS CI headless; window by hand. |
| P12 | macOS window: glutin cgl, rfd, fontdb, `paw.app`, ad-hoc signing, entitlements. | M | 39 | egui_kittest on macOS CI; a manual check list. |
| P13 | Windows IPC and processes: named pipes for control/helper/Lua sockets, Job objects, handle inheritance. | L | 40 | `paw ctl` and `paw-gui` attach on Windows CI. |
| P14 | Windows sandbox (file mapping + Event doorbell) and the terminal layer (crossterm only, console handler, logger). | M | 40 | Lua suite `--no-plugins --audio null` on `windows-2022`. |
| P15 | Windows audio and MIDI (WASAPI, midir; ASIO feature), plugin paths and Win32 editors. | M | 40 | Load the sampler's CLAP on Windows CI. |
| P16 | Windows package: zip, then MSI/Inno, winget and scoop manifests. | M | 40, 42 | Install and smoke test on CI. |
| P17 | AppImage, then Flatpak; AUR. | M | 38 | Smoke test inside the image. |
| P18 | One release workflow from a tag: all archives, checksums, the install page per OS, the e2e suite at the release check (owner rule). | M | 42 | A dry-run tag on a fork. |
| P19 | utau engine for macOS and Windows (`dotnet publish -r`), worldline per RID, as a separate download. | M | 39, 40 | utau tests on each CI. |
| P20 | Android feasibility spike (cpal AAudio + headless kernel + scene client on a phone); notes for ARM boards, FreeBSD, iOS. | M | 41 | A go/no-go note. |

Proposed new tickets: P1 (seams), P7 (Lua portability), P10 (MIDI
trait), P11 (plugin windows and bundles), P13 (Windows IPC) are each big
enough for a ticket of their own under m-1; the others fit inside
TASK-38..42 as written.

## Risks

- **Real-time wake across processes on macOS and Windows.** The futex
  doorbell is the heart of the sandbox. `os_sync_wait_on_address` needs
  macOS 14.4; Windows Events cost a kernel transition per block (about
  the same as futex, but measure). A slow doorbell adds a block of
  latency to every plugin. Mitigation: measure on CI hardware early (P9,
  P14) with the existing bench.
- **Plugin windows are the hardest UI work.** Three window systems,
  Retina/DPI scale, focus and key forwarding, the main-thread rule on
  macOS. Mitigation: `baseview` or winit; X11 impl first moved behind
  the trait with no change.
- **MIDI 2.0 parity.** ALSA gives UMP; midir is MIDI 1.0 only. A
  MIDI 1.0 backend loses per-note controllers from hardware (not from
  clips, which are already UMP internally). Acceptable at first.
- **LuaJIT on Windows with MSVC** may lose `LUAJIT_ENABLE_CHECKHOOK`;
  then `paw.limit` stops runaway compiled loops only by falling back to
  the interpreter. Also mingw vs MSVC choice for the whole workspace.
- **Signing and notarization** need paid accounts (Apple Developer, a
  Windows code-signing certificate). Unsigned builds warn the user.
- **ASIO license**: the Steinberg SDK cannot be redistributed freely
  in source; a binary with ASIO is allowed under their license, which
  the owner must accept.
- **Test tooling** (Xvfb, tesseract, the plugin set) has no macOS and
  Windows twin: window and plugin tests are thinner there.
- **Branch churn**: P1 touches many files at once, like the Rust
  refactor did. Do it in one short branch with no behavior change.
- **Cost of CI minutes** for macOS runners (10x Linux on GitHub for
  private repositories; free for public).

## Open questions for the owner (with recommended answers)

1. **Which platforms are supported, and in what order?** Recommended:
   Linux (x86_64, arm64) first-class; macOS Apple Silicon second;
   Windows x86_64 third; Android a spike; iOS and FreeBSD not now.
2. **Is Nix still the main way to build for development?** Recommended:
   yes. The dev shell stays the reference; plain cargo is supported
   and tested in CI; the docs lead with the archive for users.
3. **Config folders on macOS: Apple's (`~/Library/Application Support/paw`)
   or XDG (`~/.config/paw`)?** Recommended: XDG when `XDG_CONFIG_HOME` is
   set or `~/.config/paw` exists, else Apple's. Terminal users expect
   `~/.config`, Finder users expect Library; `:checkhealth` says which.
4. **IPC on Windows: named pipes or loopback TCP with the token?**
   Recommended: named pipes (`interprocess`), per-user, no port.
5. **utau's engine in the release archives?** Recommended: no, a
   separate download per platform (size, .NET license notices), fetched
   by the extension's install command or the user.
6. **Audio Units on macOS?** Recommended: not in m-1. CLAP and VST3
   cover most plugins; AU hosting needs AudioToolbox and an out-of-process
   AUv3 story of its own.
7. **Signing:** recommended unsigned (ad-hoc on macOS, documented
   `xattr -d com.apple.quarantine`) until a tagged 1.0; then pay for
   Developer ID and a Windows certificate if users ask.
8. **ASIO:** recommended off by default, a cargo feature for users who
   build it; WASAPI exclusive mode is the default low-latency path.
9. **Minimum versions:** recommended macOS 14.4 (the doorbell),
   Windows 10 22H2, glibc of Ubuntu 22.04.
10. **CI provider:** recommended GitHub Actions (the repository is
    there), with `nix flake check` kept as the Linux reference job.
