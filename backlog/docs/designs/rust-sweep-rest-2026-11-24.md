# Rust sweep: "rest" (all crates except paw-core and paw-gui)

Agent: rest. Tree: `scratchpad/merge` at 9cecbfdc (read only).
Crates: paw-engine, paw-plugins, paw-luadev, paw-types, paw-tui, paw-mcp,
paw-proto, paw-scene, paw-raster, paw-measure, paw-listen (the remote
listener; no crate is named paw-remote), chain-syntax, chain-lsp, fuzz,
extensions/sampler/native. 241 `.rs` files, about 80 000 lines.

Skills loaded: rust-skills (with paw-crates.md). I read AGENTS.md and
architecture/05, 11, ADR 0015, 0016, 0033.

Evidence files in `scratchpad/sweep/`: `rest-files.txt` (file list),
`rest-clippy.txt` (pedantic + nursery, first run), `rest-clippy2.txt`
(second run, the crates that the first run did not reach),
`rest-longfn.txt` (functions over 80 lines), `g.sh` (the grep helper),
`procalloc.py` (allocations and locks in `process` bodies).

## Clippy coverage and counts

The first run stopped at the reboot. It finished paw-types, paw-engine
and chain-syntax (libraries). The build of `mlua-sys` (LuaJIT) failed in
the same run, so paw-luadev, paw-tui and the test targets have no clippy
data. The second run (`-j 2`, libraries and binaries only) covered the
crates without mlua: paw-plugins 573, paw-mcp (bin) 207, paw-raster 165,
paw-scene 140, paw-measure 100, paw-proto 47, paw-listen 30, chain-lsp 11.
No clippy data: paw-luadev, paw-tui, fuzz, the sampler (own workspace) and
all test targets. The second run adds: `too_many_lines` 12 in all
(`lv2/factory.rs:270`, `vst3/factory.rs:154`, `clap/factory.rs:49`,
`lv2/ui.rs:294`, `paw-mcp/src/audio.rs:111`, `paw-raster/src/lib.rs:188`,
`paw-raster/src/vector.rs:178`), `borrow_as_ptr` 29 more (most in
`vst3/`), `struct_excessive_bools` 3 in `paw-scene/src/props.rs:90,238,313`
(view props: these are flags of a view, low), `redundant_clone` in
`lv2/worker.rs:96`. The unchecked `Duration` subtraction at
`sandbox/device.rs:220` is safe: line 205 returns first when
`waited >= limit`.

Pedantic + nursery warnings, first run: paw-engine 1120, paw-types 185,
chain-syntax 128. Main kinds (all three crates):

| Lint (message) | Count | Note |
| --- | --- | --- |
| `must_use_candidate` (method 181, function 90) | 271 | Low. Do not deny. |
| `cast_lossless` | 170 | Low. `f64::from(x)` for `x as f64`. |
| `cast_possible_truncation` | 192 | 57 in `paw-engine/src/devices`. Low: DSP casts. |
| `suboptimal_flops` (mul_add) | 135 | Do not apply: it changes the sound bytes. |
| `cast_precision_loss` | 109 | Low. |
| `missing_const_for_fn` | 84 | Low. |
| `use_self` | 76 | Low, mechanical. |
| `cast_sign_loss` | 76 | Low. |
| `missing_errors_doc` | 34 | Low. |
| `borrow_as_ptr` | 15 | `midi.rs:228`, `midi_out.rs:360`, `pool.rs:306`, `backend.rs:721`. Use `&raw const`. |
| `struct_excessive_bools` | 4 | `device.rs:388` ParamInfo, `engine/mod.rs:70` Engine, `engine/part.rs:14` PartRt, `engine/work.rs:22` Block. |
| `too_many_lines` (>100) | 4 | `devices/drums.rs:190`, `devices/mod.rs:23`, `devices/reverb.rs:293`, chain-syntax `check.rs:442`. |
| `match_same_arms` | 4 | `ump.rs:368`, `engine/graph.rs:264`, `envelope.rs:87`, `assist.rs:403`. |
| `redundant_clone` | 1 | `backend/cpal.rs:76`. |

## Summary table

| # | Area | Finding | Severity | Count | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | paw-luadev | The audio thread of a Lua device takes a blocking `Mutex::lock` on the Lua state. `Controller::call` holds the same lock while a script's `dev.call` runs. A slow call stops the block. | high (audio thread) | 2 | `crates/paw-luadev/src/device.rs:438`, `:545`, `:292` |
| 2 | git | Merge leftovers are committed (by merge 65864dd4, G2). One of them is a `.rej`. | high (hygiene, grep noise) | 5 | `crates/paw-engine/src/lib.rs.orig`, `crates/paw-engine/src/engine/apply.rs.orig`, `crates/paw-engine/src/engine/msg.rs.orig`, `crates/paw-core/src/sync/mod.rs.orig`, `crates/paw-core/src/sync/mod.rs.rej` |
| 3 | serde | `#[serde(default = "yes")]` with `fn yes() -> bool { true }`. Also `#[derive(Default)]` gives `automatable: false`, but serde of `{}` gives `true`: two defaults that disagree. paw-luadev sets `automatable: true` by hand to work around it. | medium (contract) | 1 (+1 workaround) | `crates/paw-engine/src/device.rs:386-428`, `crates/paw-luadev/src/device.rs:96` |
| 4 | duplication | Three BS.1770 copies: K filter, `lufs`, gate and true peak in the meter device and in paw-measure; a third true peak in the limiter. The meter device and `:analyze` can give different numbers. | medium (correctness drift) | 3 | `crates/paw-engine/src/devices/meter.rs:25,42,72`, `crates/paw-measure/src/analysis.rs:65,75,98,130`, `crates/paw-engine/src/devices/limiter.rs:332` |
| 5 | duplication | dB conversions with different floors (-120, -200, none). | medium | 7 | `crates/paw-engine/src/lib.rs:58,67`, `crates/paw-engine/src/devices/dsp.rs:16,22`, `crates/paw-mcp/src/audio.rs:63`, `crates/paw-measure/src/analysis.rs:52`, `extensions/sampler/native/src/engine.rs:1056` |
| 6 | duplication | Pitch names `["C", "C#", ...]` in four crates. | low | 4 | `crates/paw-mcp/src/music.rs:267`, `crates/paw-core/src/clipfile.rs:578`, `crates/paw-engine/src/devices/meter.rs:425`, `extensions/sampler/native/src/m2.rs:165` |
| 7 | duplication | paw-mcp `Meter` does bar and beat math again. `paw_types::TempoMap` has `bar_of`, `bar_start`, `bbt`, `from_bbt`. | medium | 1 | `crates/paw-mcp/src/music.rs:17-135`, `crates/paw-types/src/tempo.rs:330-373` |
| 8 | duplication | Thread priority read and set in three places. The sandbox copy does not remove `SCHED_RESET_ON_FORK`, the pool copy does. | medium (behavior differs) | 3 | `crates/paw-engine/src/pool.rs:299,324`, `crates/paw-plugins/src/sandbox/device.rs:105-116`, `crates/paw-plugins/src/sandbox/serve.rs:80-98` |
| 9 | duplication | Little-endian readers: two helpers and about 20 inline `from_le_bytes(x[..4].try_into().unwrap())`. | low | 22 | `crates/paw-plugins/src/sandbox/wire.rs:201`, `crates/paw-plugins/src/lv2_patch.rs:207`, `crates/paw-plugins/src/lv2/device.rs:79,133,260`, `crates/paw-plugins/src/sandbox/serve.rs:173,544`, `crates/paw-plugins/src/presets.rs` (4) |
| 10 | crate rule | Hand-written recursive `read_dir` where paw-crates.md says `walkdir`. | low | 1 | `crates/paw-plugins/src/lib.rs:553` |
| 11 | errors | Library crates return `anyhow::Result` from `pub fn`s. paw-engine 61 uses, paw-plugins 51, paw-proto 14. Only 3 `thiserror` types in these crates. | medium | ~126 | `crates/paw-engine/src/backend.rs:352`, `crates/paw-engine/src/clip.rs:59`, `crates/paw-engine/src/samples.rs:370`, `crates/paw-plugins/src/libs.rs:102`, `crates/paw-plugins/src/attach.rs:107` |
| 12 | stringly | `Controller::call(method: &str, data: &[u8])`. The host methods are loose `&str` constants in two places (`method::*` and `FILE_SAVE`, `FILE_LOAD`, `CLIPS`). Each host matches strings. | medium | 9 consts | `crates/paw-engine/src/device.rs:339`, `:1072-1095`, `crates/paw-plugins/src/clap/controller.rs:252` |
| 13 | bool flags | Bool parameters that select behavior. 62 `fn`s take a `bool`; the clear cases are below. | low | 62 | `crates/paw-engine/src/wav.rs:17` (`bits, float`), `crates/paw-plugins/src/lib.rs:720` and `vst3/device.rs:111` (`add`), `crates/paw-plugins/src/vst3/controller.rs:399` (`offline`), `crates/paw-plugins/src/sandbox/factory.rs:50` (`hang`) |
| 14 | God struct | `Engine` has 46 fields; 14 are `bool`. `PartRt` 33, `Shared` 27, `Block` 7 bools. | medium | 4 | `crates/paw-engine/src/engine/mod.rs:70`, `crates/paw-engine/src/engine/part.rs:14`, `crates/paw-engine/src/engine/shared.rs:15`, `crates/paw-engine/src/engine/work.rs:22` |
| 15 | long functions | 39 functions over 80 lines (`rest-longfn.txt`). Largest: paw-mcp `tools` 349, drums `render` 171, LV2 `create` 167, VST3 `create` 151, sampler `start` 134. | medium | 39 | `crates/paw-mcp/src/tools/write.rs:14`, `crates/paw-engine/src/devices/drums.rs:190`, `crates/paw-plugins/src/lv2/factory.rs:270`, `crates/paw-plugins/src/vst3/factory.rs:154`, `extensions/sampler/native/src/engine.rs:757` |
| 16 | long parameter lists | `#[allow(clippy::too_many_arguments)]` 7 times. `write_text` and `write_fill` take `(cells, width)` as two values; `draw_text` and `text_shapes` repeat one text layout. | low | 7 | `crates/paw-scene/src/cells.rs:175,215`, `crates/paw-raster/src/lib.rs:493,545`, `crates/paw-raster/src/vector.rs:49`, `crates/paw-engine/src/launch.rs:400`, `extensions/sampler/native/src/engine.rs:1158` |
| 17 | allow attributes | 20 `#[allow(dead_code)]` on the fields of the `Garbage` enum (one per variant). | low | 20 | `crates/paw-engine/src/engine/msg.rs:224-243` |
| 18 | constructors | `ParamInfo::new(name, min, max, default, unit)` and `panel::param(key, name, min, max, default, unit)`: 5 and 6 positional values, two of them `f32`. A builder fits. | low | 2 | `crates/paw-engine/src/device.rs:432`, `crates/paw-engine/src/devices/panel.rs:33` |
| 19 | env reads in library code | `Dirs` says library code does not read `XDG_*`, but `window.rs` reads `XDG_RUNTIME_DIR`. `sandbox::enabled()` reads `PAW_PLUGIN_SANDBOX` on each call. | low | 4 | `crates/paw-plugins/src/window.rs:101`, `crates/paw-plugins/src/sandbox/mod.rs:145`, `crates/paw-plugins/src/lv2/ui.rs:139`, `crates/paw-tui/src/keys.rs:24` |
| 20 | main.rs | `paw-tui/src/main.rs` has 719 lines and 25 functions (`ctl`, `attach`, `listen`, `clip_cat`, `doctor_script`, ...). | low | 1 | `crates/paw-tui/src/main.rs:132,198,171,360,315` |
| 21 | workspace deps | Same dependency written in many manifests, not in `[workspace.dependencies]`: tempfile 6, rustix 6, libc 5, rtrb 4, hound 4, realfft 3, base64 3, mlua 2, cpal 2, flate2 2, include_dir 2, unicode-width 3. | low | 12 deps | `crates/*/Cargo.toml` |
| 22 | crate boundary | paw-proto is "the client side of the control protocol" in 05, but it holds `Dirs` (used by paw-core in 10 places), TLS and the one tokio runtime of each process. The text of 05 is wrong, not the code. | low (docs) | 1 | `crates/paw-proto/src/dirs.rs:1`, `crates/paw-proto/src/runtime.rs:24` |
| 23 | sampler plugin | Raw `clap-sys` with 82 `unsafe` and `&self -> &mut` getters under `allow(clippy::mut_from_ref)`. paw-crates.md names Clack for CLAP; `clack-plugin` is its plugin side. | medium (unsafe surface) | 82 | `extensions/sampler/native/src/plugin.rs:119,126,133,297` |
| 24 | rmcp | paw-mcp uses rmcp, but writes each tool's JSON schema by hand (`json!`) in one 349-line function. rmcp derives schemas from typed argument structs (`schemars`). | low | 1 | `crates/paw-mcp/src/tools/write.rs:14` |

Not findings (checked):

- `unwrap`/`expect` outside tests: 65 and 20. Most are slice-size
  invariants (item 9) or `lock().unwrap()`, which the workspace allows.
- The cpal callback `try_lock` on `parked` (`backend/cpal.rs:380`) and the
  CLAP `run.try_lock` (`clap/device.rs:152`) do not wait. The engine has
  `tests/no_alloc.rs`. `procalloc.py` found no allocation in a `process`
  body of these crates.
- `libc::signal` in `record.rs:447` is test code with a written reason.
- The `Dirs` type is hand-written with a written reason
  (`paw-proto/src/dirs.rs:9-13`).
- Debt in `architecture/11-risks.md`: no row names these crates except
  "the format of Rust code was never checked as a whole"
  (`flake.nix:133`). It is still true for these crates.

## Proposed tickets

Each bundle is one session for one agent. All are m-10 Architecture.

### R1. Value types and flags of the engine and the plugin hosts

Findings 2, 3, 13, 17, 18.

- Delete the five `.orig`/`.rej` files of finding 2.
- `ParamInfo` (`paw-engine/src/device.rs:386-436`): delete `fn yes`. Write
  `impl Default for ParamInfo` with `automatable: true` and keep
  `#[serde(default)]` on the struct. Remove `automatable: true` from
  `paw-luadev/src/device.rs:96`.
- `ParamInfo` gets a builder (`ParamInfo::builder(key).name(..).range(min,
  max).default(..).unit(..)`), or a `Range { min, max, default }` value.
  `panel::param`, `panel::choice` and `ParamInfo::new` use it.
- `wav::Writer::create(path, rate, bits, float)` becomes
  `create(path, rate, WavFormat)` with `enum WavFormat { Int16, Int24,
  Float32 }`. Callers in paw-core `session/render.rs` change too.
- `write_output(.., add: bool)` (`paw-plugins/src/lib.rs:720`,
  `vst3/device.rs:111`) takes `enum Mix { Add, Replace }`.
- `calls_to_set_up(offline: bool)` and `spawn(.., hang: bool)` take the
  enums `Processing { Realtime, Offline }` and a test seam.
- `Garbage` (`engine/msg.rs:223`): one `#[expect(dead_code, reason = "held
  only to be dropped off the audio thread")]` on the enum, not 20.
- Acceptance: `rg 'fn yes\(|serde\(default = "' crates extensions` is
  empty; `git ls-files '*.orig' '*.rej'` is empty; a test proves
  `ParamInfo::default() == serde_json::from_str("{}")`; `cargo test -p
  paw-engine -p paw-plugins -p paw-luadev` and the no-alloc tests pass.
- Must not change: the JSON of `ParamInfo` on the sandbox wire and in the
  scan cache (same field names and values); the WAV bytes of a render;
  the audio thread rules.
- Conflicts: TASK-331 (paw-plugins `sandbox/`, `vst3/`). Land after it
  or take only the paw-engine part first.

### R2. One home for audio math, pitch names and small readers

Findings 4, 5, 6, 7, 8, 9, 10.

- dB: a module `paw_types::gain` with `db_to_gain`, `gain_to_db` and a
  named floor (`const SILENCE_DB: f64 = -120.0`). Replace
  `paw-engine/src/lib.rs:58,67`, `devices/dsp.rs:16,22`,
  `paw-mcp/src/audio.rs:63`, `paw-measure/src/analysis.rs:52` (power dB
  is `10 log10`: keep it as `power_to_db`). paw-mcp adds the dependency
  `paw-types` (no system calls, builds for wasm32). Where a floor differs
  on purpose (-200 in `dsp.rs`), the call names it.
- BS.1770: paw-measure exports its `Biquad`, `k_weighting`, `lufs` and an
  oversampling `TruePeak` that does not allocate in its step. The meter
  device (`devices/meter.rs:25-80`) and the limiter
  (`devices/limiter.rs:332`) use them. paw-engine depends on
  paw-measure. A test feeds one signal to the meter device and to
  `paw_measure::analyze` and compares integrated loudness and true peak.
- Pitch names: `paw_types::pitch::{name, parse}`. Replace
  `paw-mcp/src/music.rs:267-311`, `paw-core/src/clipfile.rs:578`,
  `paw-engine/src/devices/meter.rs:425`.
- paw-mcp `Meter` (`music.rs:17-135`) becomes a thin wrapper of
  `paw_types::TempoMap` (`bar_start`, `bbt`, `from_bbt`).
- Thread priority: one module `paw_engine::priority` with
  `current() -> Priority` and `apply(Priority) -> bool`. `pool.rs:299,324`,
  `sandbox/device.rs:105-116` and `sandbox/serve.rs:80-98` call it. The
  `SCHED_RESET_ON_FORK` mask is in one place.
- Byte readers: one `fn le_u32(bytes, at) -> Option<u32>` (and `u64`) in
  paw-plugins, for finding 9.
- `find_bundles` (`paw-plugins/src/lib.rs:553`) uses `walkdir` with
  `max_depth(5)` and the same order (sorted per folder).
- Acceptance: `rg '"C#", *"D"'` finds one place; `rg 'fn (db_to_gain|
  gain_to_db|db_to_lin|lin_to_db)'` finds one module; `rg
  pthread_setschedparam crates` finds one file; the null render tests
  and the meter golden values do not change; `cargo check -p paw-types
  --target wasm32-unknown-unknown` passes.
- Must not change: output sound bytes, the numbers that the meter device
  and `:analyze` show (to the rounding they show), the audio thread
  rules (no allocation in `TruePeak::step`).
- Conflicts: TASK-331 (`paw-plugins/src/sandbox/`); T96 (paw-core
  `api/`) only if `clipfile.rs` is in its files. The sampler extension
  stays out: it is its own Cargo workspace (finding 5 there stays).

### R3. Lua devices: no lock on the audio thread

Finding 1.

- `LuaDevice::process` (`paw-luadev/src/device.rs:438`) must not wait.
  Choose one:
  1. A script's `call` goes to the audio side as a request through an
     `rtrb` queue, and the audio side runs it between two blocks (the doc
     comment at `:535` already says "run in its state between two
     blocks") and sends the answer back. The controller waits for the
     answer, not the audio thread for the controller.
  2. `process` uses `try_lock`; on contention it outputs the input (an
     effect) or silence (an instrument), as the CLAP host does
     (`paw-plugins/src/clap/device.rs:152`), and counts the miss.
- The `failed` lock (`:445`) becomes an atomic flag plus a message that
  the controller reads.
- Acceptance: a Rust test holds the controller in a script `call` that
  waits on a channel, and `process` returns for the next block (no time
  in the test: the test releases the call after `process` returns).
- Must not change: the answers of `paw.api.device_call` for Lua devices;
  the instruction limit hook.
- Conflicts: none known (paw-luadev is not in TASK-331).

### R4. Typed errors and methods of the device contract

Findings 11, 12. A contract change: the agent proposes an ADR first
(`Controller::call` is a trait of the engine).

- paw-engine and paw-plugins: `thiserror` enums per area, for the `pub fn`s
  first: `BackendError` (`backend.rs:352,417,465`), `ClipError`
  (`clip.rs:59,66,233`, `probe.rs:23`, `envelope.rs:54`), `SampleError`
  (`samples.rs:370,436,538`), `PluginLoadError` (`libs.rs:102`,
  `attach.rs:107`, `presets.rs:337`). `anyhow` stays in binaries
  (paw-tui, paw-mcp, chain-lsp) and inside `paw-core`.
- `Controller::call`: an `enum Method<'a> { Presets, PresetLoad,
  PresetExport, NoteNames, Properties, PropertySet, FileSave, FileLoad,
  Clips, Script(&'a str) }` with `FromStr`/`as_str`. Scripts still send
  strings; the parse is at the `paw.api` edge.
- Acceptance: no `anyhow` in `paw-engine/src` and `paw-plugins/src`
  outside tests, or a written reason on each one left; the error texts
  that Lua and the user see are the same (a test compares a few);
  `rg 'method == "' crates/paw-plugins crates/paw-luadev` is empty.
- Must not change: messages that a user sees; the sandbox wire.
- Conflicts: TASK-331 (heavy, same crates). Schedule after it. T96
  (`paw-core/src/api/`) for the `paw.api.device_call` edge.

### R5. Engine state in named parts

Findings 14 and the engine rows of 15.

- `Engine` (`engine/mod.rs:70`): group into `Transport { playing, head,
  loop_enabled, loop_start, loop_end, seeks }`, `Metronome { metronome,
  click_gain, click_accent, click_output, click_buf, click_at, click }`,
  `Previews { preview, preview_leaving }`, and a `bitflags` `EngineFlags`
  for `flush_notes, chase, reapply, restate, has_states, states_held,
  launching, listening, sleep, offline`. `Block` (`work.rs:22`) takes the
  same flags type.
- Long functions: `devices/drums.rs:190` (171 lines, one voice function
  per drum), `devices/mod.rs:23` (`register`, 119 lines: a `const` table
  of built-in specs), `devices/reverb.rs:293`, `engine/apply.rs:32`,
  `engine/graph.rs:154`; `launch.rs:400` `play` takes a `SlotBlock`
  struct, not 8 values.
- Acceptance: `Engine` has at most 20 fields; no function in
  `paw-engine/src` over 100 lines; `#[allow(clippy::too_many_arguments)]`
  is gone from paw-engine; `tests/no_alloc.rs` and the null render tests
  pass with the same bytes.
- Must not change: sound bytes, the audio thread rules, the size class of
  `Msg` (no new heap object on the audio thread).
- Conflicts: TASK-331 (paw-engine). G3 (devices view) only if it adds a
  built-in device to `devices/mod.rs`.

### R6. Plugin hosts, frontends and tools: long functions and lists

Findings 15 (non-engine rows), 16, 20, 24.

- Plugin `create` functions: `lv2/factory.rs:270` (167), `vst3/factory.rs:154`
  (151), `clap/factory.rs:49` (118), `lv2/ui.rs:294` (125),
  `clap/events.rs:82`, `vst3/events.rs:94`: split into named steps
  (ports, state, activation).
- paw-scene: a `CellsMut<'a> { cells: &'a mut [Cell], width: u16 }` for
  `write_text` and `write_fill` (`cells.rs:175,215`). This changes
  paw-scene: report that it can stop the build of paw-gui.
- paw-raster: one `TextRun { font, text, x, baseline, size, colour,
  right }` for `draw_text` (`lib.rs:545`) and `text_shapes`
  (`vector.rs:49`), and one layout function that both use.
- paw-tui `main.rs`: move `ctl`, `ctl_call`, `connect` to `ctl.rs`;
  `attach`, `fetch_pixels`, `send_wanted`, `listen` to `attach.rs`;
  `clip_cat` to `clip_cat.rs`. `main.rs` keeps `main`, `dispatch`, `run`.
- paw-mcp `tools/write.rs:14`: typed argument structs with
  `schemars::JsonSchema` (rmcp's way), or one function per tool.
- Acceptance: no function over 100 lines in these crates; `allow(clippy::
  too_many_arguments)` gone from paw-scene and paw-raster; the golden
  screens, the MCP protocol tests (`paw-mcp/tests/protocol.rs`, the
  schema snapshots) and the plugin tests pass unchanged.
- Must not change: MCP tool schemas (same JSON), terminal output bytes,
  command-line flags.
- Conflicts: TASK-331 (plugin factories: do the plugin part after it);
  T96 if it changes the MCP tools; TASK-149 if it changes the same tests.

### R7. Workspace hygiene and lints

Findings 19, 21, and the lints below.

- Move the 12 shared dependencies of finding 21 to
  `[workspace.dependencies]` with a one-line reason each (paw-crates.md,
  "How to choose", step 3). chain-syntax and chain-lsp may keep their own
  lines (they are generic crates), with a comment that says so.
- `window.rs:101` takes the runtime folder from `Dirs` (given at start).
  `sandbox::enabled()` reads the variable once (`OnceLock`) at
  `set_host_command`.
- Add the lints of the next section and fix or `#[expect(.., reason)]`
  each hit.
- Acceptance: `cargo clippy --workspace --exclude paw-gui -- -D warnings`
  passes with the new lints; no manifest repeats a workspace dependency.
- Must not change: behavior.
- Conflicts: every Rust branch in flight touches `Cargo.toml` or gets new
  lint hits. Run it in a quiet batch, as the `cargo fmt` debt row says.

### R8 (optional, sampler milestone). The sampler plugin on clack-plugin

Finding 23. Port `extensions/sampler/native/src/plugin.rs` from raw
`clap-sys` to `clack-plugin` (same version family as `clack-host`).
Acceptance: `unsafe` count in the sampler drops from 82 to the
`assert_no_alloc` and format code only; the sampler's tests and the
paw-plugins stub tests pass. Must not change: the plugin id, the
parameter ids, the saved state bytes. Conflicts: none known.

## Proposed lints and checks

In the top `Cargo.toml`, `[workspace.lints.clippy]` (warn, as today; the
flake check or CI runs clippy with `-D warnings` on them):

| Lint | Stops | Hits now (rest crates, partial) |
| --- | --- | --- |
| `too_many_lines` (with `clippy.toml` `too-many-lines-threshold = 100`) | long functions | 16 over 100 (clippy), 39 over 80 (script) |
| `struct_excessive_bools`, `fn_params_excessive_bools` | bool flags | 7 structs |
| `allow_attributes`, `allow_attributes_without_reason` | `#[allow]` with no reason | 34 `#[allow]` |
| `borrow_as_ptr` | `&x as *const _` | 44 |
| `match_same_arms`, `redundant_clone`, `manual_let_else` | local style | 5+ |
| `unwrap_used` (with `allow-unwrap-in-tests = true`) | `unwrap` in production | 65 (most become `expect` with the invariant) |

Small checks (a `tools/rustlint.sh`, run by the suite and the flake):

1. No serde default function that returns a constant:
   `rg -U 'fn \w+\(\) -> \w+ \{\s*(true|false|-?[0-9.]+)\s*\}' crates extensions --type rust`
   is empty.
2. No merge leftovers: `git ls-files '*.orig' '*.rej'` is empty.
3. One definition of the shared helpers: each of `fn db_to_gain`,
   `"C#", "D"`, `pthread_setschedparam`, `fn k_weighting` appears once
   (a list of patterns with a count of 1).
4. No `anyhow` in the `src/` of the library crates paw-engine,
   paw-plugins, paw-measure, paw-types, paw-scene, paw-raster (after R4).

## Changes for the orchestrator

1. `architecture/11-risks.md`, table "Technical debt", add these rows:

```markdown
| A Lua device's audio thread waits on the lock that a script call holds | `crates/paw-luadev/src/device.rs:438` | R3 of the Rust sweep |
| The meter device, the limiter and paw-measure each keep their own BS.1770 code (K filter, gate, true peak) | `crates/paw-engine/src/devices/meter.rs:42` | R2 of the Rust sweep |
| The library crates paw-engine and paw-plugins return `anyhow` errors, and device methods are strings | `crates/paw-engine/src/device.rs:339` | R4 of the Rust sweep |
| `Engine` has 46 fields, 14 of them flags | `crates/paw-engine/src/engine/mod.rs:70` | R5 of the Rust sweep |
| Merge leftovers (`.orig`, `.rej`) are in git | `crates/paw-engine/src/lib.rs.orig:1` | R1 of the Rust sweep |
```

2. `architecture/05-building-blocks.md`, crate table, row `paw-proto`:
   replace "The client side of the control protocol." with "The client
   side of the control protocol, and what each process of paw shares:
   the base directories (`Dirs`), TLS, and the one I/O runtime."
3. `architecture/05-building-blocks.md`, crate table: add a row
   `paw-listen` | "Plays the sound of an instance where a frontend is
   attached (the remote listener)." The level-1 table calls it
   `paw-remote`; the crate is `crates/paw-listen`.
4. The existing debt row "The format of Rust code was never checked as a
   whole" stays true for the rest crates.
5. Remove the five merge leftovers now, before R1, in a one-line commit
   on main: they show in every grep of paw-engine and paw-core.
