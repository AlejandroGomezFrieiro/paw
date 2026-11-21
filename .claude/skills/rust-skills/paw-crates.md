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
| Content hashes of files (sources, caches) | `blake3` (`media::hash` in paw-core: memory map and rayon for big files, incremental) | `ring` or `sha2` for a hash that names content |
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
| Loudness (BS.1770, EBU R 128: integrated, short-term, range, true peak) | paw's own in `measure/analysis.rs` (see below) | `ebur128` |
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
  `pthread_setschedparam` in `pool.rs` and `sandbox/serve.rs`.
- **The engine's allocation test.** `assert_no_alloc` forbids allocations
  only inside a closure, and counts them on the thread that made them. The
  engine's `tests/no_alloc.rs` marks the worker pool's threads for good and
  counts what they do while the engine plays on them. The crate cannot do
  this, so the test keeps its own `GlobalAlloc`. The sampler, with one
  audio thread, uses the crate.
- **Denormals off.** The `no_denormals` crate gives only a scoped closure
  (an `unsafe fn`, and a compile error off x86 and aarch64). paw's audio
  threads turn denormals off for good, and the render holds the
  `NoDenormals` guard across early returns. paw keeps `no_denormals()` and
  `NoDenormals` in `backend.rs`.
- **The sampler's formats** and other formats that are paw's own.

## Where paw does it by hand today (2026-11-20)

Found with grep at a72467cf. Each refactor part that owns the file fixes it.

- **Command lines:** done: `paw-tui/src/args.rs`, `paw-gui/src/args.rs` and
  `paw-mcp/src/main.rs` use clap with derive and subcommands. Keep every
  flag, its short form and its meaning, and keep `docs/reference` in step.
- **I/O that waits, on threads:** (done: paw-core has one `tokio` runtime,
  `paw-core/src/io_runtime.rs`, on one thread, `paw-io`. The control
  socket and the network server, `paw-core/src/rpc.rs`, run on it with
  `tokio-rustls`, and so do the readers of helper processes in
  `paw-core/src/io.rs`. The sockets of `io.rs` stay polled from a timer,
  because `paw.api` polls them. The runtime is `paw-proto/src/runtime.rs`
  (`paw_proto::runtime::handle()`), which the client's blocking
  `Connection` uses too: one I/O thread per process, kernel or client
  or both.)
  `paw-core/src/session/encode.rs` (ffmpeg jobs),
  `paw-mcp/src/kernel.rs`, `paw-luadev` (its helper process),
  `paw-gui/src/client.rs` and the attach path of `paw-tui`. Use `tokio`.
  Not these: the audio thread, the worker pool, the plugin sandbox's
  shared memory and its process wire on the audio path, the ALSA MIDI
  thread, the terminal's input thread, the watchdog, and the render and
  stretch threads.
- **SHA-256:** done: `paw-proto/src/lib.rs` uses `ring::digest`.
- **Hex:** five `fn hex` (paw-plugins vst3.rs, paw-proto, paw-gui theme.rs,
  paw-raster vector.rs, paw-scene cells.rs). One color type with
  `FromStr`/`Display` for colors, and one function for bytes.
- **Signals:** `paw-engine/src/record.rs` (SIGXFSZ). (Done:
  `paw-tui/src/terminal.rs` uses `signal-hook` for SIGTERM and SIGHUP.)
- **Memory maps:** done: `paw-engine/src/samples.rs` and
  `paw-engine/src/host.rs` use `memmap2`, `paw-plugins/src/sandbox/shm.rs`
  and `paw-raster/src/kitty.rs` use `rustix` for shared memory.
- **Bit flags:** `paw-plugins/src/vst3.rs` (the VST3 process-context flags),
  `paw-engine/src/midi.rs` (ALSA capabilities), the engine's faults.
- **Dates:** `paw-core/src/fs_api.rs` `deletion_date`.
- **Percent-encoding:** `paw-core/src/fs_api.rs` `percent_encode`.
- **poll:** `paw-engine/src/midi.rs`. (Done: `paw-tui/src/terminal.rs` uses `rustix::event::poll`.)
- **Temporary folders in tests:** paw-plugins `attach.rs`, paw-gui and
  paw-tui tests. (Done: paw-mcp's tests use `tempfile`.)
- **WAV writers:** `paw-engine/src/record.rs` (a take, header kept valid
  as it grows: `hound`'s `WavWriter::flush` does this),
  and `paw-listen/src/lib.rs`. (The sampler's `audio.rs` is on `hound` now.)
- **FFT:** done. `paw-mcp/src/audio.rs`, `paw-engine/src/devices/dsp.rs`
  (`rfft`, main thread only: no device calls an FFT in `process`) and
  `paw-core/src/measure/analysis.rs` use `realfft`.
- **Loudness:** `paw-core/src/measure/analysis.rs` keeps its own BS.1770
  K-weighting, gates, loudness range and true peak. Compared with `ebur128`
  0.1.11 (2026-11-21): integrated, momentary and short-term agree to 0.001
  LU and true peak to 0.1 dB, but the crate takes the short-term blocks for
  loudness range once a second, and EBU Tech 3342 (version 3 and later)
  asks for at least 10 Hz. On quiet and loud passages that alternate, its
  range reads several LU lower. The crate also does not give the blocks
  that the gate keeps (paw's mono loss uses them) or the two ends of the
  range (`lra_low`, `lra_high`).
- **Real-time tools:** done: paw-engine's atomic `f32` and `f64` use
  `atomic_float`. The `no_alloc.rs` test and `no_denormals` stay paw's own,
  for the reasons above.
- **CLAP host:** done. `clack-host` 0.2 (crates.io, on the same
  `clap-sys` 0.5) covers all that `paw-plugins/src/clap.rs` uses, with
  `clack-extensions` (same version). paw still opens the file itself
  (`libs.rs`) and gives Clack the entry (`PluginEntry::load_from_raw`),
  and keeps it for good, so Clack never calls `deinit`. The port, in
  steps:
  1. Done: the file's entry and its plugin factory.
  2. Done: the host's callbacks are `PawHost`'s handlers (`HostShared`
     holds the `Arc<HostFlags>`; `HostMain` has the main-thread ones), with
     no static tables. `create` makes a `PluginInstance` and activates it.
     `Shared` keeps the instance in a `RefCell`, used on the main thread
     only, and the audio processor in `run: Mutex<Option<PluginAudioProcessor>>`:
     the audio thread only tries the lock and starts the processor;
     `stopped` and the drops take it out, stop it, deactivate the plugin
     (`Shared::deactivate`), and `stopped` puts a new one back.
  3. Done: `process` goes through `StartedPluginAudioProcessor::process`.
     paw's `ClapEvents` (a list of its `ClapEvent` union) is an
     `InputEventBuffer`, `Out` is an `OutputEventBuffer`, the transport is a
     `TransportEvent`, and the tail is `PluginTail` with the processor's
     handle. The buffers go through `InputAudioBuffers::from_raw_buffers`
     and `OutputAudioBuffers::from_raw_buffers` with the block length: the
     safe builders give a plugin with no audio ports 0 frames.
     `tests/no_alloc.rs` of paw-plugins runs the stub plugin with an
     allocator that counts the audio thread's allocations.
  4. Done: the plugin's extensions through `clack-extensions` (parameters,
     state through Clack's streams, editor, timer, posix-fd, tail, render,
     note ports and names, audio ports, preset load). `Shared::on_main`
     gives the callers a `PluginMainThreadHandle` from the instance;
     `Shared::ext` keeps the extensions that are called often, the others
     are asked for when used. No raw plugin or table pointer is kept: only
     the attachments get `raw_instance()`, once, in `create`.
     `get_extension` asks only for an extension's first id, so the
     preset-load extension's compatible id is paw's own `PresetLoadCompat`,
     and `dev.paw.call/1` is paw's own `PawCall` (both `unsafe impl
     Extension`).
  5. Done: `presets.rs` finds the presets through `clack-extensions`'
     `preset_discovery` (`PresetDiscoveryFactory`, `Provider`, paw's
     `IndexerImpl` and `MetadataReceiverImpl`), from the `PluginEntry`;
     `Library` keeps no factory pointer. A preset id's location is a
     `PresetLocation`, so the load of a preset needs no `Location::from_raw`.
     Clack asks for a factory by its first id only, so a file that has only
     the draft factory (`.../draft-2`) is seen through `DraftFactory` and a
     static entry, `DRAFT_ENTRY`, that gives that factory under the final
     id (a thread-local holds it for the scan).

  What stays raw, and why. paw uses the types and ids of `clap-sys` that
  Clack takes or does not name: the entry symbol, `clap_audio_buffer` for
  `from_raw_buffers`, event structs, `clap_id` and the draft ids. The
  attachments get `raw_instance()`, because `attach.rs` takes a
  `clap_plugin`. paw calls three tables that Clack does not have: the draft
  preset-load table (`PresetLoadCompat`), `dev.paw.call/1` (`PawCall`) and
  the draft entry of preset discovery. Each is one small `unsafe` block
  with a SAFETY comment.
- **`rubato` 0.16** in paw-core: crates.io has 5.1. Update it with the
  sample-rate tests.
