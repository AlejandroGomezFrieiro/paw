# paw in the browser (TASK-28, Web 0: spike and decisions)

Status: spike done 2026-11-21. Branch `worktree-agent-aaf6d472254f591da`,
commit `bf3331cd` ("Web 0 spike: paw's engine in an AudioWorklet").
Milestone m-0, tickets TASK-29..36.

## Verdict

**Feasible, at a medium-large cost (about 6 to 9 weeks of agent work for
TASK-29..33 and 35..36; the window, TASK-34, is extra).** Nothing found is
a wall:

- paw's audio engine (`paw-engine`) builds for `wasm32-unknown-unknown`
  with three small, native-neutral changes, and plays in an AudioWorklet
  in headless Chromium at **~17 us per 128-frame callback, 0.65 % of the
  2.67 ms budget, the same as native (16.5 us)**. Module: 577 KB, 232 KB
  gzip, 177 KB brotli. Start: 9-14 ms from fetch to a playing engine.
- paw's whole Lua runtime (Teal output included) **boots and runs on PUC
  Lua with no change to a single runtime file**, only a ~60-line prelude
  (`loadstring`, `unpack`, `setfenv`, `package.loaders`, `bit`). The Rust
  side builds on mlua's `lua54` and `lua52` features with **no Rust
  change** (only the feature name). Suite results below.
- PUC Lua is 5-7x slower than LuaJIT on pure-Lua hot paths and ~2x slower
  again in wasm; but program-level work (a full redraw, an edit) is
  dominated by Rust and costs only 1.0-1.7x on PUC Lua natively. Keys stay
  far under 100 ms; the harmony analysis is the one hot spot to watch.
- Cross-origin isolation works on a host that sets no headers (GitHub
  Pages) through a service worker: proven in headless Chromium
  (`crossOriginIsolated: true`, `SharedArrayBuffer` present).

The cost is in the kernel (`paw-core`): it is a desktop program (tokio
sockets and processes, rustix, TLS, threads, the file system, LuaJIT FFI
in Lua devices). Each needs a feature gate or a browser implementation.

## Decisions

### 1. Lua VM: PUC Lua 5.2 in the browser, LuaJIT stays native

- **Native keeps LuaJIT.** It is 5-7x faster on pure Lua (harmony
  analysis: 10 ms vs 56-73 ms), and the Lua devices' FFI depends on it.
- **The browser build uses PUC Lua through mlua's vendored `lua52`**
  (recommended) or `lua54`. Both build and run paw today.
  - Lua 5.4 is ~30 % faster than 5.2 but has integers: `3.0` prints as
    `"3.0"` where LuaJIT prints `"3"`, `math.floor` returns integers,
    `string.format("%d", 1.5)` fails. **111 of the 265 suite failures on
    5.4 are exactly this** (`got "4.0+4.0", want "4+4"`). Every
    `tostring`, `..` and `%s` of a number would need care, in the runtime,
    every extension and every user config: a permanent tax for 30 %.
  - Lua 5.2 has LuaJIT's number model (doubles only, `"3"`), `goto`
    (8 files use it), `bit32`, `table.maxn`, and runs compat-5.3 as
    LuaJIT does. The prelude closes the rest. **Recommended.**
  - Lua 5.1 is out: no `goto`. Luau is out: no `goto`, another library.
    A pure-Rust VM (piccolo...) is out: incomplete library, 444 files.
- One runtime, two VMs: the prelude moves into the runtime as
  `paw/portable.lua` (loaded first when `jit == nil`). CI runs the Lua
  suite natively on the portable VM (cargo feature `portable-lua`), so the
  browser has a test bed that needs no browser.

### 2. Target triples: one `wasm32-unknown-emscripten` module for the app

- **The app (kernel + engine + TUI) is one `wasm32-unknown-emscripten`
  module with shared memory.** Reasons:
  - mlua supports wasm only through emscripten (mlua 0.12 README: "WASM is
    supported through the `wasm32-unknown-emscripten` target for all
    Lua/Luau versions excluding JIT"). `lua-src` refuses
    `wasm32-unknown-unknown` ("don't know how to build Lua for ...") and
    builds emscripten with `-sSUPPORT_LONGJMP=wasm`.
  - Kernel and engine share pointers: `Msg::InsertDevice` carries a
    `Box<dyn Device>` made by the kernel, freed through the garbage queue.
    Two modules with two memories cannot do this; one module with one
    shared memory and one allocator can, unchanged (rtrb works on shared
    memory as on native).
  - Emscripten gives `std::fs` (WASMFS with an OPFS backend), threads
    (pthreads on workers), `std::time`, and **Wasm Audio Worklets**
    (`-sAUDIO_WORKLET -sWASM_WORKERS`): the same module and memory on the
    audio thread. That is paw's native shape.
- **`wasm32-unknown-unknown` stays for the spike and standalone parts**
  (the engine demo; later Wasm devices, TASK-1). No glue, but no Lua, no
  threads on stable Rust, no file system, no clock.
- Toolchain: nixpkgs' `rustc` ships the `wasm32-unknown-unknown` std (the
  spike uses it, with `lld` and `binaryen` in the new `nix develop .#web`
  shell), not `wasm32-unknown-emscripten`'s. The web shell needs a
  toolchain with that target from a flake input (oxalica/rust-overlay or
  fenix, stable, web shell only; native keeps nixpkgs' rustc), plus
  nixpkgs' `emscripten` 5.0.6 (725 MB download; verified: it builds the
  vendored Lua 5.4.9 to 272 KB wasm).

### 3. Threads and workers

| Native thread | Browser |
|---|---|
| main (kernel, Lua, event loop) | a Web Worker (emscripten `PROXY_TO_PTHREAD`): may block (`Atomics.wait`), so the kernel loop stays |
| audio callback (cpal) | the Wasm Audio Worklet, same module and memory |
| engine worker pool | none at first (`set_pool(None)`); a worklet cannot give real-time priority to workers |
| io runtime (tokio sockets, helper processes) | gone; timers from the kernel loop |
| watchdog (Lua hook) | a pthread as native |
| page main thread | xterm.js, keys, mouse, Web MIDI, file pickers; a SharedArrayBuffer ring to the kernel worker (bytes out, keys in) |

### 4. Audio path

- AudioWorklet, 128-frame quanta, the engine called once per quantum,
  written straight into the output (spike: `web/demo/worklet.js`).
- Kernel to engine: the existing rtrb `Msg` queue in shared memory, no
  `postMessage` on the audio path. Meters and positions: existing atomics.
- Audio-thread timing goes through `paw_engine::clock` (spike): std's
  `Instant` under emscripten; a still clock on unknown-unknown.
- Latency: `latencyHint: "interactive"`; base latency 128 frames + device
  output latency (typically 10-40 ms on PipeWire). Measure on a real
  device in TASK-31 (headless has none).
- MIDI: Web MIDI on the page thread, into the engine's MIDI ring through a
  SharedArrayBuffer. Chromium and Firefox; Safari has none.
- Microphone: `getUserMedia` into the worklet's input, after a gesture.

### 5. Terminal in the page: xterm.js fed by paw-tui's own output

- **xterm.js (MIT) with its WebGL renderer, fed by the exact bytes
  paw-tui writes to a terminal.** Terminal first means the browser shows
  the terminal frontend, not a new one. paw-tui's only crossterm user is
  `crates/paw-tui/src/terminal.rs` (762 lines): put the tty behind a
  trait (native: crossterm + /dev/tty; web: a byte ring to xterm.js and
  key/mouse/resize events back).
- Pictures: paw-raster speaks the kitty graphics protocol, xterm.js does
  not; its image addon speaks sixel and iTerm IIP. paw-raster gains an
  IIP (PNG) output. Its rustix shared-memory path stays native.
- Not chosen: a canvas renderer of paw-scene cells (a third frontend to
  keep in step). The window in the browser is TASK-34 (egui on WebGPU).

### 6. Files: OPFS through std::fs

- Project folders in the Origin Private File System, mounted by WASMFS's
  OPFS backend (sync access handles, kernel worker): paw's file code runs
  unchanged (folders, media by hash, `unused/`).
- Open/save a folder from disk: File System Access API
  (`showDirectoryPicker`, Chromium only), copied in/out of OPFS.
  Everywhere: zip import/export (flate2 is already in paw-core).
- `navigator.storage.persist()` on first save; quota messages.
- No network code in the web build: nothing leaves the machine.

## The spike (what was built)

Commit `bf3331cd` on `worktree-agent-aaf6d472254f591da`:

- `crates/paw-engine` builds for `wasm32-unknown-unknown` with
  `--no-default-features`; native unchanged (all its tests pass):
  - `rustix` under `[target.'cfg(unix)'.dependencies]`;
  - `samples.rs`: `madvise` only on unix; `as_encoded_bytes` instead of
    `OsStrExt::as_bytes` (same bytes on unix);
  - `clock.rs`: `paw_engine::clock::Instant`, used by the three
    audio-thread timings.
- `web/engine` (crate `paw-web-engine`, own workspace): the native engine
  with built-in synth + reverb looping an eight-note phrase; plain C ABI
  (`paw_web_new/render/left/right/free`), no wasm-bindgen, no imports;
  one test, one example (`cost`, native callback cost).
- `web/demo`: `index.html` (Play/Stop, real audio), `worklet.js`,
  `bench.html` (numbers), `coi.js` + `coi-sw.js` (isolation by service
  worker, written for paw).
- `web/build.sh`, `web/serve.py` (localhost, optional COOP/COEP,
  `--result FILE`), `web/bench.sh` (headless Chromium, own profile and
  HOME, nothing left running), `web/README.md`.
- `flake.nix`: `devShells.web` = default + `lld` + `binaryen`.

Reproduce: `nix develop .#web -c web/build.sh`; `web/bench.sh OUT.json`
(server headers) or `web/bench.sh OUT.json --no-headers` (service
worker). Listen: `python3 web/serve.py`, open http://127.0.0.1:8765/.

The Lua VM experiments were scratch copies (not committed): mlua features
`lua54`/`lua52` and a prelude loaded before `api::install` in
`Kernel::boot`.

## Numbers

Shared, loaded machine: single runs +-30 %; ratios within one run firmer.

### Engine in the browser (headless Chromium 156, `web/bench.sh`)

| | value |
|---|---|
| wasm (`wasm32-unknown-unknown`, LTO) | 697 KB raw |
| after `wasm-opt -O3` | **577 KB raw, 232 KB gzip, 177 KB brotli** |
| imports | none |
| start: fetch + compile + instantiate + engine | 8.5-13.7 ms (fetch 4-9, compile 1.5-2.3, instantiate 0.25, engine 2.3-2.5) |
| callback, 128 frames, 48 kHz, synth + reverb | **mean 17.4-18.5 us**, p50 15 us, p99 30-45 us, max 1.9-3.2 ms (main-thread outliers) |
| native, same code (`--example cost`) | mean 16.5 us, p50 16.1 us, p99 19-23 us |
| real-time factor | 144-153x wasm, 161x native |
| AudioWorklet path, 4 s offline render | 29-30 ms, peak 0.25 (it plays) |
| isolated, server headers | true |
| isolated, no headers, service worker | **true** |

`performance.now` is coarsened to 5 us when isolated; the mean over
22 500 calls is reliable, p50/p99 are quantized.

### Lua VMs, pure Lua (standalone bench)

paw's harmony reader (Teal output of `paw/harmony/read.tl`) on 1 280 notes
(64 bars), and the churn of building 45 rows of 150 cells:

| VM | `read.chords` | `read.keys` | 45x150 rows |
|---|---|---|---|
| LuaJIT 2.1 (JIT) | **10.2 ms** | 0.32 ms | 0.10 ms |
| LuaJIT 2.1 `-joff` | 31.0 ms | 1.31 ms | 0.17 ms |
| Lua 5.4.7 (nixpkgs) | 56 ms | 1.9 ms | 0.35 ms |
| Lua 5.4.9 (mlua's vendored, -O3) | 55-57 ms | 1.9-2.0 ms | 0.39-0.40 ms |
| Lua 5.2.4 (nixpkgs) | 72-74 ms | 2.9 ms | 0.44 ms |
| **Lua 5.4.9 in wasm** (emscripten 5.0.6, node 24) | **111-127 ms** | 4.1-4.3 ms | 0.62-0.65 ms |

PUC Lua costs 5.5x (5.4) to 7x (5.2); wasm adds 2.0-2.2x: ~11x LuaJIT for
5.4, an estimated ~15x for 5.2 in the browser. Emscripten Lua 5.4.9: 272
KB wasm (116 KB gzip) + 76 KB JS.

### Lua VMs, the whole program (paw built on each, natively)

| | LuaJIT | Lua 5.4 | Lua 5.2 |
|---|---|---|---|
| redraw p50, 16 tracks, arrange 150x45 | 2.14 ms | 2.43 ms | |
| redraw p50, 16 tracks, all panels 150x45 | 2.11 ms | 2.39 ms | |
| redraw p50, 100 tracks, arrange 150x45 | 2.00 ms | 2.63 ms | 0.73 ms (*) |
| redraw p50, 100 tracks, all panels 150x45 | 3.16 ms | 3.49 ms | 2.90 ms (*) |
| edit: 1000 note adds, total | 45.6-48.7 ms | 42.7-61.8 ms | |
| 100 tracks: one clip move / undo | 0.074 / 0.073 ms | 0.123 / 0.119 ms | |
| 100 tracks: build | 64 ms | 105 ms | |
| startup, median of 10 | 39.1 ms | 40.9 ms | |

(*) run while two suites loaded the machine; the 5.2 arrange number is
below LuaJIT's, so it may have drawn less: TASK-29 checks.

Rust dominates these: program-level cost of PUC Lua is 1.0-1.7x.
Expected in the browser: a full 100-track redraw ~4-7 ms, an edit well
under 1 ms; inside one 60 Hz frame, far under the 100 ms key rule.

### The Lua test suite on PUC Lua (natively)

Reference (LuaJIT, a recent main run): 1 782 ok, 0 failed.

- **Lua 5.4 + prelude: 1 450 ok, 265 failed.** 111 failures are
  integer/float formatting (`"3.0"` vs `"3"`); 41 come from utau's
  msgpack (LuaJIT `LL` literals, FFI); 8+ are Lua devices (`no device
  kind lua:...`: FFI in luadev); a few are `table.maxn`/`table.copy`
  gone in 5.4, `string.format`/`os.date` refusing non-integers, and 9
  are the test scratch path being too long for a socket (environment,
  not the VM).
- **Lua 5.2 + prelude: 1 503 ok, 213 failed, and no number-formatting
  failures at all.** 41 are utau's msgpack (`LL`, FFI) and 8+ Lua
  devices (FFI), as on 5.4; 9 the long socket path (environment); most of
  the rest are small library gaps the prelude did not fill yet:
  `table.maxn` and `math.log10` (5.2 has them only with `LUA_COMPAT_ALL`,
  which lua-src does not set), a `table.copy`, a `.string` field in
  plugstate (ffi.string), and knock-on view errors (`geometry` nil) to
  trace in TASK-29. None needs a runtime rewrite.
- Both runs: 1 715-1 716 tests reached of the reference 1 782 (a few
  groups abort early on the same errors).

## LuaJIT-only features in runtime/ and extensions/

444 `.lua`/`.tl` files (`tl.lua` and `.d.tl` left out):

| feature | files | where | browser answer |
|---|---|---|---|
| `ffi` | 11 (8 code) | `paw/dsp.lua`; doctor/checks; utau (msgpack, audition, device, tests); plugstate (juce, tone3000, frameworks, tests); `runtime/types/paw.lua` | dsp.lua: portable path (TASK-29); utau, plugstate native-only; doctor guarded |
| `bit` | 9 | `paw/compat.tl`, `paw/canvas.tl`; pattern; articulations (3); plugstate (2); utau tests | prelude `bit` over `bit32` |
| `jit.*` | 1 | `paw/limit.tl` | guarded already |
| `goto` | 8 | `paw/frontend.tl`, `views/arrange_mouse.lua`, `hooks.tl`, `markers.tl`; utau; sections (2); undotree | 5.2+ has it: rules out 5.1 |
| `setfenv`/`getfenv` | 3 | compat53, tutor store, utau import | prelude (`debug.upvaluejoin`) |
| `loadstring` | 5 | `paw/lang.tl`, `defaults/project.lua`, `init.lua`, compat53, tutor | prelude; kernel.rs reads the global `loadstring` (lines 701, 783) |
| global `unpack(` | 14 | many | prelude |
| `LL` literals | 2 | utau msgpack, plugstate tone3000 | native-only extensions |
| `table.new`/`clear`, `string.buffer` | 0 | | |
| `math.pow`/`mod` | 1 | `paw/dsp.lua` | portable path |
| `package.loaders` (Rust) | 1 | `crates/paw-core/src/kernel.rs:742` | `package.searchers` on 5.2+ |
| Lua devices (luadev, FFI arrays) | 5 | luafx (chords, drive, gain_pan, sine), utau | not in the browser at first; Wasm devices later (TASK-1) |

Also `debug.*` in 22 files and `collectgarbage` in 3: fine on PUC Lua.
The test harness needs `ffi` too (`tests/tools/speed.lua`, thread CPU
time): an `os.clock` fallback.

## Blockers by crate (`cargo check --target wasm32-unknown-unknown`)

| crate | status | what fails and why | fix |
|---|---|---|---|
| paw-scene | **builds** | | |
| paw-engine | **builds** (spike), no default features | was: `errno` via rustix; `memmap2::Advice`, `std::os::unix` in samples.rs; `Instant::now` panics at run time | done; `cpal`, `midi` (alsa-sys) off |
| paw-raster | fails | rustix `shm` (kitty over shared memory) -> errno | shm path unix-only; IIP output |
| paw-luadev | fails | mlua `luajit` (no wasm backend; luajit-src panics) | VM feature; Lua devices off in the browser |
| paw-core | fails | mlua `luajit`; tokio `net`/`process` -> mio (36 errors); rustix (fs, event, process) -> errno; ring (rustls, rcgen, paw-proto) -> getrandom 0.2; libc; code: 7 files `std::os::unix`/`fd`, 13 processes, 19 threads, 33 `std::fs` | features `net`, `processes`, `luajit`/`portable-lua`; emscripten supplies fs, threads, time, getrandom |
| paw-proto | fails | tokio net, rustls/ring | not in the web build (remote client) |
| paw-plugins | fails | lv2_raw, alsa-sys, plugin hosts (dlopen, helper processes) | not in the web build; Wasm devices later |
| paw-tui | fails | crossterm (mio), signal-hook, rustix termios/stdio | tty trait (`terminal.rs` only); xterm.js |
| paw-gui | not tried | winit/glutin/egui_glow | TASK-34 |
| paw-mcp, paw-listen | not in the web build | sockets, processes | |

The emscripten target itself was not built: nixpkgs' rustc has no std for
it (only `wasm32-unknown-unknown` and `wasm32v1-none`).

## Cross-origin isolation (SharedArrayBuffer)

- `SharedArrayBuffer` (shared wasm memory, threads, Wasm Audio Worklets)
  exists only when `crossOriginIsolated` is true: the document must be
  served with `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: require-corp` (or `credentialless`).
- GitHub Pages sets no custom headers. A service worker can add them to
  every same-origin response; the first visit registers it and reloads
  once. `web/demo/coi.js` + `coi-sw.js` do this (written for paw after
  the known coi-serviceworker pattern); headless Chromium reports
  `crossOriginIsolated: true` from a server that sends no headers.
- Consequences: every sub-resource same-origin or CORS/CORP (bundle
  xterm.js and fonts, no CDN); one reload on the first visit; private
  windows without service workers get no isolation (show a message). The
  same worker caches the app for offline use (TASK-35).
- Later option: a host with headers (Cloudflare Pages / Netlify
  `_headers`): no reload.

## Prior art: openDAW

openDAW (https://opendaw.org, source
https://github.com/andremichelle/openDAW), a browser DAW by André
Michelle. From its repository, read 2026-11-21:

- **Build**: TypeScript monorepo (Vite, Sass, Turbo/lerna, Node 23+) with
  a Rust engine in wasm.
  [README](https://raw.githubusercontent.com/andremichelle/openDAW/main/README.md),
  [package.json](https://raw.githubusercontent.com/andremichelle/openDAW/main/package.json),
  [vite.config.ts](https://raw.githubusercontent.com/andremichelle/openDAW/main/packages/app/studio/vite.config.ts)
- **Hosting**: an Apache/PHP host reached by SFTP (`deploy/run.ts`;
  opendaw.studio, dev.opendaw.studio), not a static CDN. Isolation from
  **host headers** (`.htaccess`: COOP `same-origin`, COEP `require-corp`,
  CORP `cross-origin`); Vite sets them in dev. No coi service worker.
  Hashed names, one-year immutable caching, Brotli precompressed.
  [deploy/run.ts](https://raw.githubusercontent.com/andremichelle/openDAW/main/deploy/run.ts),
  [.htaccess](https://raw.githubusercontent.com/andremichelle/openDAW/main/packages/app/studio/public/.htaccess)
- **Offline**: none; "PWA with offline support" is on its help-wanted
  list. Its only service worker (`wclap-sw.js`) serves WebCLAP plugin
  files with COOP/COEP.
  [wclap-sw.js](https://raw.githubusercontent.com/andremichelle/openDAW/main/packages/app/studio/public/wclap-sw.js)
- **Audio**: AudioWorklet running **only the wasm engine** (no TS DSP).
  Commands over the worklet `port` (an RPC layer); state over
  **SharedArrayBuffers**: a flag word with `Atomics` sleep/wake, a
  "SyncStream" the UI polls per animation frame, a ring of performance
  samples, MIDI input via a port plus a SAB.
  [EngineWorklet.ts](https://raw.githubusercontent.com/andremichelle/openDAW/main/packages/studio/core/src/EngineWorklet.ts),
  [EngineVariant.ts](https://raw.githubusercontent.com/andremichelle/openDAW/main/packages/studio/core/src/EngineVariant.ts)
- **Devices**: ~34 built-in devices in Rust crates; `engine.wasm` is a
  dynamic-linking host (imports shared memory and a function table), each
  device a ~2 KB position-independent side module (nightly
  `-Zbuild-std=core`). Third-party: **WebCLAP** (`.wclap`, CLAP compiled
  to wasm: Surge XT, Odin2, OB-Xf) with their own UIs. A JS-scripted MIDI
  effect.
  [build-wasm.sh](https://raw.githubusercontent.com/andremichelle/openDAW/main/packages/studio/core-wasm/build-wasm.sh),
  [crates/](https://github.com/andremichelle/openDAW/tree/main/crates)
- **Storage**: **OPFS**, a folder per item (`<folder>/<uuid>/meta.json`),
  `trash.json` instead of immediate deletes, quota tracking; zip bundles
  (jszip, plugins inside), WAV and MIDI export; a `lib/dawproject`
  package (UI wiring not verified).
  [Storage.ts](https://raw.githubusercontent.com/andremichelle/openDAW/main/packages/studio/core/src/Storage.ts),
  [project/](https://github.com/andremichelle/openDAW/tree/main/packages/studio/core/src/project)
- **MIDI**: Web MIDI (`requestMIDIAccess({sysex: false})`), MIDI learn,
  software input, MIDI output device.
  [MidiDevices.ts](https://raw.githubusercontent.com/andremichelle/openDAW/main/packages/studio/core/src/midi/MidiDevices.ts)
- **Size/load time**: not measured; it bundles Monaco and an ONNX runtime:
  far bigger than paw needs.
- **Licence**: **AGPL-3.0-or-later**, commercial licence on request.
  [LICENSE](https://raw.githubusercontent.com/andremichelle/openDAW/main/LICENSE).
  paw is MIT OR Apache-2.0: copying openDAW code would make the combined
  work AGPL. **Learn its patterns; copy no code**, file or build script.
  The spike's coi files are not from openDAW (it has none).

| openDAW choice | paw | why |
|---|---|---|
| Rust DSP in wasm in an AudioWorklet, no JS DSP | **adopt** (proven here) | one engine, native and web |
| SAB + `Atomics` flags and rings, UI polls per frame | **adopt** | paw's native model (rtrb, atomics), same code on shared memory |
| commands by `port.postMessage` RPC | **not** | kernel and engine share memory; `Msg` needs no serialization |
| COOP/COEP from host headers | **not at first** | GitHub Pages cannot; the service worker (proven) can |
| no offline mode | **not** | local-first: cache the app in the same service worker |
| OPFS, folder per project, trash list | **adopt** | matches project folders and "never delete" (`unused/`) |
| zip bundles | **adopt** | flate2 already in paw-core |
| tiny dynamic-linked device modules | **study for TASK-1** | elegant; needs nightly build-std |
| WebCLAP plugins | **study for TASK-1** | the browser's answer to "no native plugins" |
| a big TypeScript UI | **not** | paw's UI is the TUI (xterm.js), later egui |

## Risks

1. **Rust on `wasm32-unknown-emscripten` with mlua + pthreads + Wasm Audio
   Worklets** is the least trodden path, not built here (no toolchain).
   TASK-30 starts with exactly that hello-world. Fallback: kernel module
   (emscripten) + engine module (unknown-unknown) with a serialized
   command ring instead of `Box<dyn Device>` (a bigger engine boundary).
2. **Lua speed**: pure-Lua analyses ~15x slower than native LuaJIT in the
   browser (harmony, 64 dense bars: ~10 ms -> ~150 ms est. on 5.2). Bench
   keys on the portable VM in CI; heavy analyses at idle time or in Rust.
3. **Two VMs drift**: an extension uses `ffi` or 5.1-only calls. The suite
   on `portable-lua` in `nix flake check`; a lint against `ffi` outside an
   allow-list.
4. **Audio glitches**: shared-memory growth can stall the worklet: fixed
   maximum or growth at safe points; measure dropouts (TASK-31).
5. **Storage**: OPFS eviction and quotas: `storage.persist()`, zip export.
6. **Browsers**: Safari has no Web MIDI and stricter workers/OPFS;
   Firefox lacks `showDirectoryPicker`.
7. **Download**: emscripten app est. 4-8 MB raw (~1.5-3 MB brotli) plus
   xterm.js ~0.3 MB. Fine for a cached app; measure in TASK-30.

## Plan (refines TASK-29..36; S < 1 day, M 1-3 days, L 3-7 days, XL > 1 week)

1. **TASK-29, Web 1: Lua runtime without LuaJIT (M-L).** Cargo features
   `luajit` (default) / `portable-lua` (= mlua `lua52`) in paw-core and
   paw-luadev through paw-tui (workspace deps `default-features = false`);
   `build.rs` dumps bytecode with the matching VM (the build-dependency
   mlua follows the feature) or ships source; `paw/portable.lua` prelude;
   kernel.rs uses `package.searchers` when `loaders` is absent; non-FFI
   `paw/dsp.lua`; `os.clock` fallback in `tests/tools/speed.lua`; Lua
   devices refuse clearly on the portable VM; suite on `portable-lua` in
   CI, fix the rest.
2. **TASK-30, Web 2: kernel builds for wasm32 (XL).** First the
   emscripten smoke test (risk 1): flake input for the web shell; mlua
   `lua52` + pthread + Wasm Audio Worklet hello-world (go/no-go for one
   module). Then features in paw-core: `net` (rpc, TLS, rcgen,
   paw-proto), `processes` (helpers, io runtime), `plugins`; rustix
   behind `cfg(unix)` (the spike's pattern); paw-raster shm unix-only;
   kernel on a worker (`PROXY_TO_PTHREAD`), `set_pool(None)`. Output: the
   kernel boots `--clean --no-plugins` in a headless page.
3. **TASK-31, Web 3: audio and MIDI (M).** Engine on the Wasm Audio
   Worklet; Web MIDI rings; microphone; latency and dropouts on a real
   device; bench page grows a dropout counter.
4. **TASK-32, Web 4: terminal in the page (L).** tty trait; bundled
   xterm.js + WebGL addon fed by a byte ring; keys, mouse, resize, focus;
   IIP pictures; same scenes (rule 2).
5. **TASK-33, Web 5: projects and files (M).** WASMFS OPFS as projects
   root; zip import/export; `showDirectoryPicker`; `storage.persist()`.
6. **TASK-35, Web 7: GitHub Pages with the docs (S-M).** Workflow for
   docs + app; coi worker plus a versioned offline cache; links. Owner
   decides when to publish.
7. **TASK-36, Web 8: limits documented, smoke test (S-M).** Reference
   page (no native plugins until TASK-1, no Lua devices, no ffmpeg, no
   network, storage, latency); `web/bench.sh` grows into the CI test.
8. **TASK-34, Web 6: window on WebGPU/WebGL (L, last).** After TASK-27.

Order: 29 and the start of 30 in parallel; 31 and 32 once 30 boots; 33
with 32; 35 and 36 last.

## Owner questions (recommended answers)

1. **Lua 5.2 (LuaJIT's numbers, ~30 % slower) or 5.4 (`3.0` prints
   `"3.0"`)?** 5.2.
2. **May the web dev shell add a flake input for a Rust toolchain with the
   emscripten target (oxalica/rust-overlay, stable)?** Yes; native keeps
   nixpkgs' rustc.
3. **Which browsers?** Chromium and Firefox supported, Safari best effort.
4. **Lua devices (luafx, utau) in the browser?** Not in v1; with Wasm
   devices (TASK-1).
5. **Which bundled extensions ship?** Every pure-Lua one; off: utau,
   plugstate, doctor's shell checks, projdiff's git, interop's tools.
6. **GitHub Pages + service worker, or a host with headers?** GitHub
   Pages as planned; revisit if the first-visit reload matters.
7. **Keep the spike on main (`web/`, engine cfg changes, `.#web`)?** Yes:
   native-neutral, and `web/bench.sh` seeds TASK-36's smoke test.

## BrowserPod (TASK-54): a second path

Status: spike done 2026-11-22. Branch `worktree-agent-a0f1e73fe5e27369b`,
commit `8922521e` (`web/browserpod/`: `build.sh`, `run.sh`, the probes,
`paw-browserpod.patch`, the page, the driver). BrowserPod 4.1.0, headless
Chromium 156, a shared machine (load average 3-5 on 24 cores): single
runs +-30 %.

BrowserPod (Leaning Technologies) is a Linux-like kernel in Wasm. Each
process and thread runs in a Web Worker. Its Rust pack is a pinned
nightly (`nightly-2026-05-19`) with the target
`wasm32-browserpod-linux-musl` (a JSON target: `arch = "wasm64"` with
32-bit pointers, shared memory, `panic = "abort"`), patched `libc`,
`rustix` and `linux-raw-sys`, a clang wrapper and a musl sysroot.

### Verdict

**paw-tui runs in a pod today, after about one day of work and with a
183-line patch.** The arrange view of the demo song draws in the page
terminal; `j k h l`, `Space Space` and `:q!` work; a pod process can
send sound to an AudioWorklet in the page. Two defects of the pod's
terminal remain (escape sequences split, no resize). The licence does
not let us host the runtime: the app depends on BrowserPod's CDN and
cannot work offline.

### What worked

1. **crossterm** (`probe`): raw mode, key events, `poll`, the alternate
   screen and a draw work. `signal-hook` registers SIGWINCH. Process
   start to first frame: 1.4 ms.
2. **paw-tui with `--audio null --clean --no-plugins`** and
   `-e 'dofile("examples/demo-song.lua")'`: boot, the runtime, the Teal
   output and the demo song work on PUC Lua 5.2 with a prelude. The patch
   (`web/browserpod/paw-browserpod.patch`):
   - mlua `lua52` for the target; the build dependency stays on LuaJIT:
     build.rs runs on the host, checks and compiles the Teal, and ships
     source (no bytecode) when it cross-compiles;
   - `prelude52.lua` before `api::install` (`loadstring`, `unpack`,
     `setfenv`/`getfenv`, `package.loaders`, `bit`, `table.maxn`,
     `math.log10`, `math.pow`, `math.mod`);
   - workspace deps `paw-engine` and `paw-listen` with
     `default-features = false` (no cpal, no ALSA); `Hear::Device`
     refuses;
   - four casts: Lua 5.2's integer is `ptrdiff_t`, 32 bits here
     (`formats.rs`, `toml_api.rs`); `1 << 40` overflows `usize`
     (`undo.rs`); `tv_nsec` is `i32` (`paw-plugins` `shm.rs`);
   - `strip = true`.
3. **setjmp/longjmp**: BrowserPod's libc has no `setjmp` (its objects
   are empty). `_setjmp` stays an undefined import, and the first Lua
   call hangs forever with no error. Fix: build Lua with
   `-mexception-handling -mllvm -wasm-enable-eh -mllvm
   -wasm-use-legacy-eh=false -mllvm -wasm-enable-sjlj
   -D_setjmp=setjmp -D_longjmp=longjmp`, and link `sjlj/rt.c` (the three
   runtime functions of LLVM's lowering, 35 lines). Lua errors, `pcall`
   and errors out of Rust callbacks then work.
4. **The paw-plugins link** needs `-llilv-0 -ldl`: empty archives
   satisfy it. The lilv functions become 77 `env` imports that nothing
   calls with `--no-plugins`.
5. **Cross-origin isolation without headers**: the coi service worker of
   TASK-28 works with BrowserPod. The pod boots from a server that sends
   no COOP/COEP (one reload). `rt.browserpod.io` sends
   `Cross-Origin-Resource-Policy: cross-origin`; the disks come over
   `wss://`.
6. **Audio, pod to page** (`bridge`): `createFetchNetwork({ fetch })`
   gives the page every HTTP request of the pod. The probe POSTs blocks
   of 512 stereo f32 frames to `http://audio.paw/` over keep-alive. The
   page's `fetch` puts the body (a `ReadableStream`) into a
   SharedArrayBuffer ring that an AudioWorklet plays. Paced at real time,
   50 ms ahead: **4.94 s of a 440 Hz sine played, 0 underruns, 0 blocks
   dropped**, request p50 0.40 ms, max 23 ms. Unpaced: 9.9 MB/s with
   keep-alive (26 times the 384 KB/s of 48 kHz stereo f32), 2.3 MB/s
   with a new connection for each block. Only documented API.

### What did not work

1. **Escape sequences arrive split.** The pod's tty gives ESC alone to
   the first `read`, then the rest: an arrow key reads as `1b`, then
   `5b 41`; F5 as `1b`, `5b 31`, `35 7e` (`probe-raw`). crossterm then
   reports `Esc`, `'['`, `'A'` for one arrow. Every key with an escape
   sequence (arrows, F-keys, Alt, mouse, bracketed paste, focus) is
   broken in paw-tui. Fixes: a reader in `terminal.rs` that waits a few
   ms for more bytes after a lone ESC (as Vim's `ttimeoutlen`), or a fix
   upstream (to report).
2. **No resize.** The default terminal is sized to its element once.
   A resize of the page does not refit xterm.js and sends no SIGWINCH;
   `Terminal` has only `write`.
3. **No input to a custom terminal.** `createCustomTerminal` takes
   `cols` and `rows` at creation and has no input path, so we cannot use
   our own xterm.js. Its output capture works (`onOutput`), but the
   buffer is a view on a resizable buffer: `TextDecoder` refuses it
   without a copy.
4. **Version pins**: the pack patches `libc 0.2.189` and
   `rustix 1.1.4`. paw's lock has 0.2.191 and 1.1.6, so the patch is
   unused and `libc` fails to compile (83 errors). `build.sh` pins
   `mio 1.2.4`, `libc 0.2.189` and `rustix 1.1.4` in the copy. A newer
   pack moves these.
5. **No `chmod` API**: a file from `createFile` is not executable, and
   `pod.run("chmod")` costs 0.6-1.3 s (a process start) before paw runs.

### Numbers (headless Chromium 156, cold cache, localhost server)

| | value |
|---|---|
| paw for BrowserPod, stripped | **23.0 MB raw, 7.2 MB gzip -9, 4.7 MB brotli -11** (TASK-28 estimate for emscripten: 4-8 MB raw) |
| BrowserPod runtime (`rt.browserpod.io`, 8 files) | 0.84 MB on the wire |
| disk blocks read (`disks.browserpod.io`, `wss`) | 4.2 MB (base image) + 0.79 MB (user image) |
| download, first visit | **about 10.5 MB with brotli** (paw 4.7 + BrowserPod 5.8) |
| page start to the arrange view drawn | **3.06, 3.13, 3.22, 5.56 s** (4 runs) |
| of which: import runtime / boot pod / copy paw in / chmod / paw to first frame | 0.3 / 1.6-3.2 / 0.2-0.4 / 0.6-1.3 / 0.25-0.35 s |
| paw boot in the pod (`Kernel::new` to booted) | about 0.15 s (native LuaJIT: 0.04 s) |
| key to the terminal's rows changed (`j`/`k`, 90 keys) | **p50 7.9 ms**, min 5.2, max 43 |
| key to the terminal's rows changed (`h`/`l`, 60 keys) | **p50 6.5 ms**, min 4.7, max 23 |
| CPU, browser process tree, paw idle | 3.0-5.4 % of one core |
| CPU, playing on the null backend | 4.5-7.0 % of one core |
| RSS, browser process tree | about 1.45 GB (26 workers) |

Measured under external load. The key time is keydown (capture) to the
first DOM change of `.xterm-rows`: it includes the pod, paw and
xterm.js's DOM renderer.

### Audio design for BrowserPod

The bridge above is the smallest path. For paw: a backend in paw-engine,
`http` (BrowserPod only), driven by a sender thread. The thread renders
a block, puts it on an rtrb ring, and a second thread POSTs the blocks
to `audio.paw` on a keep-alive connection, about 50 ms ahead of the
worklet. MIDI and the transport position come back in the reply bodies.
The engine never waits on the network. Latency: about 50-100 ms from key
to sound (the buffer ahead, the worklet's 128 frames, the device). That
is more than the emscripten plan (128 frames + the device). Each block
crosses the pod's kernel, a worker and the page's main thread, so a busy
main thread stalls the sound. Not built in this spike.

### BrowserPod or emscripten

| | BrowserPod | emscripten (TASK-28 plan) |
|---|---|---|
| effort to the TUI in a page | **done in the spike** (about 1 day); left: the ESC reader, resize (needs BrowserPod), an audio backend over the bridge (M), files (pod disk with `storageKey`) | 6-9 weeks (TASK-29..33, 35, 36) |
| changes to paw | 183-line patch, mostly features and casts | features in paw-core (net, processes, plugins), a tty trait, OPFS, the kernel on a worker |
| download | about 10.5 MB brotli, half from their CDN | est. 1.5-3 MB brotli + xterm.js 0.3 MB |
| start | 3-5.5 s to the first frame (pod boot 1.6-3.2 s) | est. well under 1 s (engine demo: 9-14 ms) |
| keys | p50 6-8 ms; arrows and Alt broken until fixed | not measured; same xterm.js |
| audio | a bridge over HTTP through the page's `fetch`: works, 50-100 ms, main thread in the path | Wasm Audio Worklet on shared memory, 128 frames, the native engine model |
| memory | about 1.45 GB browser RSS | not measured; one module |
| licence | Community Licence: free; a visible "Powered by BrowserPod" credit that links to browserpod.io; the runtime loads from their CDN only; self-hosting, vendoring or redistribution needs the Enterprise Licence; no reverse engineering | emscripten (MIT/UIUC), our code only |
| hosting on github.io | works with the coi service worker (verified), but the page depends on `rt.browserpod.io` and `disks.browserpod.io` (they say published versions stay available) | static, our files only |
| offline | **no**: the runtime and disks come from their CDN, and the licence forbids a mirror | yes: the service worker caches the app (TASK-35) |
| privacy | each visitor's browser loads from Leaning Technologies' CDN: the docs must say so | nothing leaves the origin |
| browsers | Chromium best; Firefox and Safari "with some limitations" (`Atomics.waitAsync`) | Chromium and Firefox; Safari best effort |
| tested | the real paw-tui, std unchanged (files, threads, processes, sockets) | the engine only |

### Recommendation

**Both, with different jobs.**

- **BrowserPod for an interactive demo in the docs.** It runs the real
  paw-tui with a small patch: a "try paw" page next to the tutorials,
  with the demo song and the course, behind a button (visitors who do
  not press it load nothing from the CDN), with the credit on the page
  and a line in the privacy note. Silent at first; the bridge backend
  later. Before it ships: the ESC reader in `terminal.rs` (useful
  natively too, on slow ssh links), and a report to BrowserPod about the
  split escape sequences and the resize. Features replace the patch's
  edits (`portable-lua` from TASK-29 replaces most of it).
- **emscripten stays the path for the full app** (TASK-29..36): small,
  fast to start, offline, real-time audio on shared memory, no third
  party at run time, no licence condition on our page. BrowserPod gives
  no offline use and no self-hosting without an Enterprise licence, and
  its audio path puts the page's main thread between the engine and the
  speakers.
- TASK-29 (Lua without LuaJIT) serves both. The setjmp finding matters
  for emscripten too: `-sSUPPORT_LONGJMP=wasm` is the same lowering.

Owner questions:

1. A BrowserPod demo page in the docs, with the credit and the CDN load
   behind a button? Recommended: yes, after the ESC reader.
2. Apply for BrowserPod's open-source Edge grant? Not needed: the demo
   uses no Edge feature (no Portals, no outbound TCP).
3. Report the split escape sequences and the missing resize to
   leaningtech/browserpod-meta? Recommended: yes, from the owner's
   account.

Skill: Leaning Technologies publishes an official BrowserPod skill
(leaningtech/skills, MIT, commit `f782b75e`, the same file as
browserpod.io/skills/browserpod/SKILL.md). It is installed unchanged in
`~/.claude/skills/browserpod/` with its LICENSE and a SOURCE note that
adds the findings of this spike.
