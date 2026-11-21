# paw's extension: use the recommended crates

This page is paw's own addition to the rust-skills skill. It applies to all
of paw's Rust code: the crates in `crates/` and the native parts of the
extensions.

The rule: **do not write what a recommended crate already does.** Examples
are a parser, a codec, a hash, a command-line parser, a signal handler, a
memory map and a data structure. Before you write one, look for it in the list at
<https://blessed.rs/crates>. If the list has it, use that crate. Examples:
`mlua` for Lua, `clap` for command lines, `serde` for formats, `thiserror`
for the errors of a library.

## Why

- A recommended crate has tests, fuzzing and users that paw's own copy does
  not have.
- The next reader knows the crate's API. They do not know paw's copy.
- Less code to keep. A copy grows its own bugs, and three copies (paw had
  three hex color parsers) grow three sets.

## How to choose

1. Look in paw's `Cargo.lock` first. A crate that paw already builds through
   another crate costs nothing new. On 2026-11-20 the lock file already had
   `ring` (with `rustls`), `thiserror` 2, `rustix` 1, `memmap2`, `bitflags`
   2, `signal-hook`, `tempfile`, `walkdir`, `percent-encoding`, `smallvec`
   and `arrayvec`. It did not have `clap`, `jiff`, `dirs` or `sha2`.
2. Then the list at <https://blessed.rs/crates>, in its order: its first
   choice for the job, unless a reason below says otherwise.
3. Add the crate to `[workspace.dependencies]` in the top `Cargo.toml` when
   two crates of paw use it. Disable the default features that paw does not
   need (`default-features = false`), as the manifests do now.
4. Say why in one comment line above the dependency, as the manifests do now
   ("Pure Rust FLAC encoder, for renders to .flac.").

## When paw keeps its own code

Write your own code only for one of these reasons, and put the reason in a
comment next to the code:

- **The audio thread.** No crate call that can lock, allocate or wait. A
  crate is fine there only when its docs or its code show it does none of
  these (for example `rtrb`), and `tests/no_alloc.rs` still passes. A
  three-line noise generator in a device stays as it is.
- **The Nix build.** The crate needs a system library or a C toolchain that
  the flake does not give, and a pure Rust crate does not exist.
- **The format is paw's own** (the sandbox wire, the scene protocol). Use
  serde for the encoding where you can, but the shapes are paw's.
- **The crate is much larger than the job**, and the job is a few lines
  that a reader can check at once. Say how large, in the comment.

## The map: jobs in paw and the crate for each

| Job | Use | Not |
|---|---|---|
| Lua, LuaJIT | `mlua` | raw `lua_*` FFI |
| MCP servers | `rmcp`, the official SDK (<https://github.com/modelcontextprotocol/rust-sdk>) | own JSON-RPC and tool tables |
| Command line of a binary | `clap` (derive) | a loop over `std::env::args` |
| Errors of a library crate | `thiserror` | `Result<_, String>` |
| Errors of a binary | `anyhow` | `Box<dyn Error>` |
| JSON, TOML, XML | `serde_json`, `toml`/`toml_edit`, `quick-xml` | hand-written escaping |
| base64, deflate, crc32 | `base64`, `flate2` (`flate2::Crc`) | own tables |
| SHA-256 and other hashes | `ring::digest` (already linked), else `sha2` | an own SHA |
| Bit sets in a `u8`/`u32` | `bitflags` | `const X: u32 = 1 << n` and `&` by hand |
| Signal handlers | `signal-hook` (`low_level::register` for a handler that writes) | `libc::signal` |
| Memory maps of files | `memmap2` | `libc::mmap` |
| Unix calls (`poll`, `shm_open`, `termios`) | `rustix` | `unsafe libc::` |
| Temporary files and folders in tests | `tempfile` | `temp_dir().join(pid)` |
| Walking folders | `walkdir` | a recursive `read_dir` |
| Lazy statics | `std::sync::LazyLock`, `OnceLock` | `lazy_static` |
| Ring buffers between threads | `rtrb` | own atomics |
| Channels | `std::sync::mpsc` or `crossbeam-channel` | own queues |
| Network, sockets, child processes, timers that wait on I/O | `tokio` (with `tokio-rustls` for TLS) | a thread for each connection, sockets polled from a timer, read timeouts as a loop |
| Dates and times | `jiff` | `libc::localtime_r` |
| User folders (XDG) | `dirs` or `etcetera` | reading `XDG_*` by hand (keep the XDG order paw documents) |
| Percent-encoding | `percent-encoding` | a loop over bytes |
| A terminal | `crossterm` (paw uses it) | escape codes by hand where `crossterm` has them |
| Windows, OpenGL | `winit`, `glutin`, `egui` (paw uses them) | |
| Small vectors on the stack | `arrayvec`, `smallvec` | own fixed arrays with a length |
| Benchmarks of Rust code | `criterion` or `divan` | `Instant::now()` loops |
| Snapshot tests | `insta` | hand-written golden files |

The table is a guide, not a list of required crates. A row with no use in
paw adds nothing. A change from paw's code to a crate keeps the behavior.
It keeps the same output bytes and command-line flags, and the same error
texts that Lua or a user sees.

## I/O that waits: `tokio`

The owner chose `tokio` for each job in paw that waits on I/O, now and in
the future. The rules:

- **One runtime for each process**, on threads of its own, made where the
  process starts. A library crate takes a handle or gives `async fn`s.
  It makes no runtime of its own.
- **I/O only.** Sockets, TLS, child processes and their pipes, waits with a
  time limit. Work for the processor (render, stretch, analysis) stays on
  threads or the worker pool. The audio thread never sees `tokio`.
- **The kernel stays as it is.** The Lua state is on one thread and is not
  `Send`. Tasks send their results to the kernel's channel and wake it, as
  the reader threads do now. The kernel never blocks on a future.
- **Quiet when idle.** An idle runtime must not wake the processor. Measure
  how often the idle program wakes, before and after (paw's goal: redraw on change, devices
  sleep).
- **Features.** Enable only what the crate uses (`rt-multi-thread` or
  `rt`, `net`, `io-util`, `process`, `time`, `sync`, `macros`), as one
  workspace dependency.
- **Behavior stays.** Same messages on the wire, same time limits (for
  example the hello time of a network connection), same error texts.

## Audio

paw is an audio program, so the audio crates matter most. The sources are
the audio page of <https://arewegameyet.rs/ecosystem/audio/>, the Rust
parts of Awesome Audio DSP (linked from <https://rust.audio/>) and
crates.io's download counts (checked 2026-11-20). Before you add one of the
real-time crates, read its code for the audio thread rules.

| Job | Use | Not |
|---|---|---|
| Sound devices | `cpal` (paw uses it) | |
| WAV, read and write | `hound` (paw-engine uses it) | a RIFF header by hand |
| FLAC, Ogg Vorbis, MP3 and other files, read | `symphonia` (paw uses it) | `claxon`, `lewton`, `minimp3` next to it |
| FLAC, write | `flacenc` (paw uses it) | |
| Sample-rate conversion | `rubato` (paw uses it) | |
| FFT | `realfft` (paw uses it) | a radix-2 FFT by hand |
| Loudness (BS.1770, EBU R 128: integrated, short-term, range, true peak) | `ebur128` | own K-weighting and gates |
| Lock-free queues to the audio thread | `rtrb` (paw uses it) | |
| A test that the audio thread does not allocate | `assert_no_alloc` | an own `GlobalAlloc` in each test |
| Denormals off on a thread | `no_denormals` | own MXCSR code |
| Atomic `f32`/`f64` (meters, parameters) | `atomic_float` | `f32::from_bits(x.load())` by hand |
| Hosting CLAP plugins | `clack-host` (Clack), if it covers what paw uses | raw `clap-sys` calls in `unsafe` |

What paw keeps as its own, and why:

- **The engine.** `kira`, `rodio`, `firewheel`, `oddio` and `fyrox-sound`
  are engines for games. paw's engine hosts plugins in a sandbox, plays
  MIDI 2.0, puts quiet devices to sleep, and has a test that proves the
  audio thread does not allocate. It is measured against REAPER. An engine
  for games does none of this.
- **The devices' DSP** (EQ, dynamics, reverb, synth, drums). These run on
  the audio thread, and their cost is measured. A crate such as `fundsp` or
  `biquad` replaces a device only when it gives the same sound and costs no
  more, measured with the benches.
- **MIDI 2.0.** paw speaks Universal MIDI Packets to ALSA through
  `alsa-sys`. `midir`, `portmidi` and `wmidi` are MIDI 1.0 only.
- **Real-time thread priority.** `audio_thread_priority` goes through RtKit
  over D-Bus on Linux (a C library for the Nix build), and it does not copy
  the sound thread's own policy and priority as paw does. paw keeps
  `pthread_setschedparam` in `pool.rs` and `sandbox.rs`.
- **The sampler's formats** and other formats that are paw's own.

## Where paw does it by hand today (2026-11-20)

Found with grep at a72467cf. Each refactor part that owns the file fixes it.

- **Command lines:** `paw-tui/src/main.rs` (`parse_args`, `doctor_args`,
  the subcommands `doctor`, `clip`, `ctl`, `attach`, `plugin-host`,
  `plugin-scan`), `paw-gui/src/main.rs`, `paw-mcp/src/main.rs`. Use clap with derive
  and subcommands. Keep every flag, its short form and its meaning, and keep
  `docs/reference` in step.
- **I/O that waits, on threads:** (done: paw-core has one `tokio` runtime,
  `paw-core/src/io_runtime.rs`, on one thread, `paw-io`. The control
  socket and the network server, `paw-core/src/rpc.rs`, run on it with
  `tokio-rustls`, and so do the readers of helper processes in
  `paw-core/src/io.rs`. The sockets of `io.rs` stay polled from a timer,
  because `paw.api` polls them.)
  `paw-core/src/session/encode.rs` (ffmpeg jobs),
  `paw-proto` (the client: connect, TLS, a reader thread),
  `paw-mcp/src/kernel.rs`, `paw-luadev` (its helper process),
  `paw-gui/src/client.rs` and the attach path of `paw-tui`. Use `tokio`.
  Not these: the audio thread, the worker pool, the plugin sandbox's
  shared memory and its process wire on the audio path, the ALSA MIDI
  thread, the terminal's input thread, the watchdog, and the render and
  stretch threads.
- **SHA-256:** `paw-proto/src/lib.rs:261`. Use `ring::digest`.
- **Hex:** five `fn hex` (paw-plugins vst3.rs, paw-proto, paw-gui theme.rs,
  paw-raster vector.rs, paw-scene cells.rs). One color type with
  `FromStr`/`Display` for colors, and one function for bytes.
- **Signals:** `paw-tui/src/terminal.rs` (SIGTERM, SIGHUP), and
  `paw-engine/src/record.rs` (SIGXFSZ).
- **Memory maps:** `paw-engine/src/samples.rs`, `paw-engine/src/host.rs`,
  `paw-plugins/src/sandbox.rs`, `paw-raster/src/kitty.rs` (shared memory). Use
  `memmap2` for files and `rustix` for shared memory. Keep the layouts.
- **Bit flags:** `paw-plugins/src/vst3.rs` (the VST3 process-context flags),
  `paw-engine/src/midi.rs` (ALSA capabilities), the engine's faults.
- **Dates:** `paw-core/src/fs_api.rs` `deletion_date`.
- **Percent-encoding:** `paw-core/src/fs_api.rs` `percent_encode`.
- **poll:** `paw-tui/src/terminal.rs`, `paw-engine/src/midi.rs`.
- **Temporary folders in tests:** paw-mcp, paw-plugins `attach.rs`,
  paw-gui, paw-tui tests.
- **WAV writers:** `paw-engine/src/record.rs` (a take, header kept valid
  as it grows: `hound`'s `WavWriter::flush` does this),
  and `paw-listen/src/lib.rs`. (The sampler's `audio.rs` is on `hound` now.)
- **FFT:** three radix-2 transforms by hand: `paw-core/src/measure/analysis.rs`,
  `paw-mcp/src/audio.rs`, `paw-engine/src/devices/dsp.rs`. Use `realfft`.
  The one in `dsp.rs` stays only if a device calls it on the audio thread.
- **Loudness:** `paw-core/src/measure/analysis.rs` has its own BS.1770
  K-weighting, gates, loudness range and true peak. Compare it with
  `ebur128` on the tests in `measure/tests.rs`, and change to the crate if
  the numbers agree.
- **Real-time tools:** the `no_alloc.rs` test of paw-engine (own allocator;
  the sampler's uses `assert_no_alloc`), `backend.rs` `no_denormals`, the atomic `f32`
  in `devices/dsp.rs` and `engine/shared.rs`.
- **CLAP host:** `paw-plugins/src/clap.rs` calls `clap-sys` directly.
  Clack's host crate gives safe wrappers. If it is not on crates.io,
  the Nix build must pin its Git commit. Try it on the stub plugin and
  the plugin tests first.
- **`rubato` 0.16** in paw-core: crates.io has 5.1. Update it with the
  sample-rate tests.
