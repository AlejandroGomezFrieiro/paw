# Rust sweep: paw-core (agent "core")

Tree: `scratchpad/merge` at 9cecbfdc (main + W1). Crate: `crates/paw-core`
(165 files, 60 359 lines). Read only. No file of the tree changed.

Skills loaded: `rust-skills` (with `paw-crates.md`), `architecture`.
I read `AGENTS.md` and `architecture/` 05, 11 and the decision log. I did
not load `rust-testing`, `paw-code` or `plain-writing` with the Skill
tool: the sweep writes no code and no test, and this file is internal
text (STE).

Evidence files (scratchpad/sweep/): `core-prod.txt` (the non-test lines),
`core-unwrap.txt`, `longfn.py` (functions over 80 lines),
`fields.awk` (structs with 15 or more fields), `core-clippy.txt`.

Clippy: the first run stopped when the machine rebooted. The second run
(`-j 2`, pedantic + nursery) is in the section "Clippy counts" at the end.

## 1. Summary table

Severity: high = correctness, audio thread or contract risk; medium =
maintainability across files; low = local style.

| # | Area | Finding | Sev. | Count | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | repo | Merge leftovers are in git: `sync/mod.rs.orig` and `sync/mod.rs.rej` (added by the merge 65864dd4 of G2). The `.orig` still has `Track`, `tracks()`, `TrackPass`. Also 3 `.orig` files in paw-engine. | high | 5 files | `crates/paw-core/src/sync/mod.rs.orig:272`, `crates/paw-core/src/sync/mod.rs.rej`, `crates/paw-engine/src/lib.rs.orig`, `crates/paw-engine/src/engine/msg.rs.orig`, `crates/paw-engine/src/engine/apply.rs.orig` |
| 2 | api | `MidiEventOpts.kind` is a `String`. Each unknown `type` (a typo such as `"note_onn"`) becomes a note-off with no error. | high | 1 | `src/api/midi.rs:18`, `src/api/midi.rs:64-79` |
| 3 | model, serde | Constant helpers and per-value serde defaults: `fn yes() -> bool { true }`, `one()`, `one_u32()`, `default_velocity()`, `no_signals()`, and copies of `is_zero`, `is_false`, `is_one`, `is_true`, `is_beats`, `is_auto`, `unnamed`. | medium | 18 fns in 5 files | `src/attr_map.rs:61,72-78`, `src/model.rs:515-521,599,684-694,946,1019-1025`, `src/model/chain.rs:74,162-176`, `src/model/custom.rs:353,367,371-385`, `src/model/overrides.rs:26` |
| 4 | model | `CustomContent.version: u32` with its own `one_u32`/`is_one_u32`, while `model/kinds.rs` has `Version` with `is_one`. Two types for one concept. | medium | 1 | `src/model/custom.rs:353`, `src/model/kinds.rs:217` |
| 5 | session | Field words are matched by hand two times: a hand `FromStr` for the setter enum, and a second list of string arms in the getter. The lists can drift (the getter has `id`, `master`, `nest`; the setter has `automation`, `sends`, `attr_map`). | medium | 7 hand `FromStr` impls, 1 getter | `src/session/document/parts.rs:82-106,379-401`, `src/session/document/project.rs:107`, `src/session/document/nests.rs:45`, `src/session/document/clips.rs:46`, `src/session/midi_in.rs:512`, `src/session.rs:214`, `src/model.rs:447` |
| 6 | session | Look up, then `unwrap()` the same lookup again inside the `edit` closure. An invariant, but each site repeats it, and a refactor that drops the first check panics. `part_in(p, id)?` exists for this. | medium | about 30 | `src/session/automation.rs:52,63,72,80`, `src/session/devices.rs:139,307,322,354,501`, `src/session/document/automation.rs:28,45,94,131,163`, `src/session/document/devices.rs:23,55,67,102,113`, `src/session/document/clips.rs:315,319,716,717` |
| 7 | kernel | The kernel thread waits in `sleep` loops (plugin settle, state lanes, plugin state requests, loads). A key that starts one waits for it. paw has a doorbell for waits. | medium | 6 | `src/session.rs:696`, `src/session/statelanes.rs:353`, `src/session/devices.rs:481`, `src/session/loading.rs:313,325`, `src/io.rs:477` |
| 8 | kernel, api | God struct: `api::Shared` has 40 fields that mix the screen (grid, highlights, dirty, frames, kept cells, redraws), the loop (rx, inbox, turning, waiter, missed wakes), the connections (sizes, caps, seat, desk, clients, input_from, detach) and timers. | medium | 40 fields | `src/api/mod.rs:56-140`, `src/kernel.rs:161` (`new`, 85 lines, fills them) |
| 9 | sync | `Mapper` has 31 fields, most `HashMap<Id, _>` by part: one record per part is spread over 15 maps. | medium | 31 fields | `src/sync/mapper.rs:58-120` |
| 10 | session | `Session` has 32 fields, 5 of them `pub`; it is already split into sub-objects. Keep as is; make the `pub` fields `pub(crate)` with methods. | low | 32 fields | `src/session.rs:345` |
| 11 | model | Upward reference: `model` calls `crate::sync::repeats`. It blocks the move of `model` to `paw-model` (TASK-95.1). The same function returns `Box<dyn Iterator>`. | medium | 1 | `src/model/nest/time.rs:217,223`, `src/sync/clips.rs:206` |
| 12 | session | Five "free name" helpers, with three different schemes (`a.2.wav`, `a-2.wav`, `stem-2.wav`, `name 2`). | medium | 5 | `src/fs_api.rs:72`, `src/upload.rs:54`, `src/session.rs:569`, `src/session/folder.rs:121`, `src/session/document/nests.rs:221` |
| 13 | model, sync | Part kind read from `meta` by Rust code: `is_vca` 4 times, `is_group`, `group_of`. (Known debt row, Rust sites not listed there.) | medium | 6 | `src/freeze.rs:250,388`, `src/session/save.rs:91-101`, `src/sync/automation.rs:139` |
| 14 | all | Functions over 80 lines (not counting the 18 `install` tables of `define!`, which are lists of small functions). | medium | 33 | `src/session/save.rs:287` (285 lines), `src/stretch.rs:341` (158), `src/sync/routing.rs:231` (157), `src/measure/mod.rs:150` (151), `src/attr_map.rs:506` (139) |
| 15 | all | Bool parameters that select behavior. | low | 33 | `src/sync/mod.rs:756` (`held: bool, fresh: bool`), `src/sync/mod.rs:507`, `src/session/folder.rs:1081`, `src/safe.rs:21`, `src/session/document/clips.rs:415` |
| 16 | all | MIDI 7-bit to unit scale open-coded (`/ 127.0`, `* 127.0`). | low | 8 | `src/attr_map.rs:368,416`, `src/api/midi.rs:91`, `src/session/recording.rs:126`, `src/sync/clips.rs:90,110` |
| 17 | kernel | MIDI input goes through `Arc<Mutex<VecDeque>>` plus a channel message for each event. One channel that carries the event does both. Not the audio thread. | low | 1 | `src/kernel.rs:183-187`, `src/api/mod.rs:127,153`, `src/kernel/reactor.rs:229` |
| 18 | session | Code reads back its own JSON views by string keys. (Typed API work: T96.) | low | 20 sites, 80 fns return `Value` | `src/session/devices.rs:290-295`, `src/session/automation.rs:73`, `src/session/audition.rs:310-339`, `src/session/cues.rs:160-171` |
| 19 | errors | `Result<_, String>` in library code. Most go to Lua as `nil, err`, which is fine at the `api/` edge only. | low | 14 | `src/api/kind_data.rs`, `src/xml.rs:94`, `src/model.rs`, `src/model/kinds.rs`, `src/fs_api.rs:122` |
| 20 | crates | Hand-written code: a regex escape in a test helper (`regex` is in Cargo.lock). The XML escape and `deletion_date` (libc `localtime_r`) have a written reason; keep them. | low | 1 | `src/golden.rs:60` |
| 21 | lints | `#[allow(dead_code)]` with no reason. | low | 1 | `src/api/midi.rs:22` |
| 22 | files | Large files. `model.rs` is known debt. `session/folder.rs` is larger and not listed. | medium | 2 | `src/session/folder.rs:1` (2333 lines), `src/model.rs:1` (2252 lines) |

Checked and clean, not findings:

- `unsafe`: each block has a `SAFETY:` comment (`src/kernel.rs:279,329`,
  `src/io.rs:137`, `src/watchdog.rs:40,61,99,180`, `src/api/mod.rs:230`).
- No `Box<dyn Error>`. `thiserror` is in 6 model files.
- The audio thread is not in paw-core. `settle_plugins` calls
  `engine.process` on the main thread only before the engine starts.
- `project.clone()` (20 sites) is cheap: `Project` holds `Arc<Part>`.
- `lock().unwrap()` (33) obeys the workspace rule in `Cargo.toml:46`.
- Layers: `session`, `sync` and `grid` do not reach `api` or `kernel`.
  `scene.rs:28` uses `api::Shared`, which is correct: the scene is a
  Lua host part.

Known debt in `11-risks.md`, confirmed:

- `model.rs` is one large file: still true, 2252 lines.
- Track kind and group in `meta`: true, and Rust reads them too
  (finding 13).
- The 16 ms idle wait (`kernel/reactor.rs:40`): still there. The sleep
  loops of finding 7 are other waits.
- `Clip.overrides`, `RESERVED`, freeze in `meta`, linked clips by copy:
  not checked again in depth; the cited lines still exist.

## 2. Proposed tickets

The bundles are large, as the owner asks. Order: CORE-0 first (small,
now), then CORE-1 and CORE-2 in one batch (different files), then CORE-3
and CORE-4.

### CORE-0. Remove merge leftovers; model stops reading sync (m-10)

Files: `crates/paw-core/src/sync/mod.rs.orig`, `sync/mod.rs.rej`, the
three `paw-engine/src/**/*.orig`, `.gitignore`, `flake.nix` (one check),
`crates/paw-core/src/model/nest/time.rs`, `crates/paw-core/src/sync/clips.rs`.

Acceptance criteria:

1. `git ls-files '*.orig' '*.rej'` is empty. `.gitignore` has `*.orig`
   and `*.rej`.
2. A check in `nix flake check` fails when git tracks a `*.orig` or a
   `*.rej` file.
3. `repeats` moves from `sync/clips.rs:206` to `model` (or to
   `paw-types`, if the engine needs it). `sync` imports it from there.
4. `played_notes` (`model/nest/time.rs:217`) returns `impl Iterator`
   (an `either::Either`, or two `Option` iterators chained), not
   `Box<dyn Iterator>`.
5. A check fails when a file under `crates/paw-core/src/model*` names
   `crate::sync`, `crate::session`, `crate::api` or `crate::kernel`.

Must not change: behavior, file bytes. Conflicts: G2 merged; the engine
`.orig` files touch TASK-331 only by name (delete only). Tell the
`engine` sweep agent.

### CORE-1. Serde defaults, field words and typed MIDI event kinds (m-10)

Files: `src/attr_map.rs`, `src/model.rs`, `src/model/chain.rs`,
`src/model/custom.rs`, `src/model/kinds.rs`, a new
`src/model/serde_util.rs`, `src/session/document/{parts,project,nests,clips}.rs`,
`src/session/midi_in.rs`, `src/session.rs`, `src/api/midi.rs`.
Also `crates/chain-syntax/src/schema.rs:298` and
`crates/paw-scene/src/cells.rs:117`, `crates/paw-engine/src/device.rs:427`
if the `rest`/`engine` sweeps agree (same pattern).

Exact patterns and their fix:

1. `is_zero`, `is_false`, `is_beats`, `is_auto`, `unnamed` become one
   generic `pub(crate) fn is_default<T: Default + PartialEq>(v: &T) -> bool`
   in `model/serde_util.rs`. `Timeline` and `StretchMode` derive
   `Default` with `#[default]` on `Beats` and `Auto` (check that each is
   the default today).
2. `fn yes()` + `is_true` on `AttrMap.attribute`: put
   `#[serde(default)]` on `AttrMap` and write `impl Default for AttrMap`
   with `attribute: true`. All other fields of `AttrMap` already have
   `default`.
3. `one()`/`is_one` (`Clip.stretch`, split `mix`): a newtype with a
   `Default` of 1.0 (`Stretch(f64)`, `Mix(f64)`, `#[serde(transparent)]`),
   or, if the newtype spreads too far, one `const fn` generic helper
   `serde_util::one::<f64>()`. No helper that returns one constant per
   field.
4. `default_velocity()`: a `Velocity(u8)` newtype with `Default` = 100
   and a check of 1 to 127 (`#[serde(try_from = "u8")]`). It also gives
   the scale functions of finding 16 (`Velocity::unit()`,
   `Velocity::from_unit()`); use them at the 8 sites.
5. `CustomContent.version: u32` with `one_u32` becomes `kinds::Version`.
6. `no_signals()`: `Arc<[Signal]>` gets `#[serde(default)]` (the
   `Default` of `Arc<[T]>` is empty) .
7. The 7 hand `FromStr` impls of word enums (`PartField`,
   `ProjectField`, `NestField`, `ClipKind` built-ins, `TransportField`,
   `LaneKind`, `InputChannels`): derive `Deserialize` with
   `rename_all = "snake_case"`, parse with
   `T::deserialize(word.into_deserializer())`, and map the error to the
   same text as now. One `Serialize` gives the word back. No new crate.
   (`strum` is not in Cargo.lock; use it only if the owner accepts a
   new crate.)
8. `part_field` (`parts.rs:82-106`) uses the enum, not a second list of
   strings. Getter keys that are not setter fields (`id`, `master`,
   `nest`) are variants marked read-only.
9. `MidiEventOpts.kind` is an enum (`note_on`, `note_off`, and the
   others the doc names). An unknown `type` gives the error
   "a MIDI event has no type `x`: use note_on, note_off, ...".

Acceptance criteria:

- No function in `crates/paw-core/src` has the shape
  `fn name() -> T { <literal> }` used by `serde(default = ...)`.
- Each `skip_serializing_if` in paw-core names `is_default`,
  `Option::is_none`, `Vec::is_empty`, `Map::is_empty`, `BTreeMap::is_empty`
  or `<[T]>::is_empty`.
- The saved bytes do not change: the insta snapshots and golden folders
  (`src/golden.rs`) pass with no update, and a project saved before
  the change reads back equal (a round-trip test of a project file
  from `tests/`).
- The error texts that Lua sees stay the same (finding 5); one new
  error for finding 2, with a test through `paw.api.midi_send` (or the
  function at `api/midi.rs`) that sends `"note_onn"` and gets the error.
- `cargo clippy -p paw-core` adds no warning.

Must not change: file bytes, the `paw.api` names and the order of keys
in saved JSON and TOML.

Conflicts: M1 modifiers in `model/` (`Clip`, `model/overrides.rs`,
`model.rs:599` area): do CORE-1 after M1 merges, or leave
`overrides.rs` and the `Clip` fields to M1 and do the rest. T96 typed
API in `api/`: only `api/midi.rs` overlaps; ask the T96 agent to take
item 9, or do it after T96.

### CORE-2. Session lookups, free names and the scale of MIDI values (m-10)

Files: `src/session/automation.rs`, `src/session/devices.rs`,
`src/session/clips.rs`, `src/session/document/{automation,devices,clips}.rs`,
`src/session/stretching.rs`, `src/fs_api.rs`, `src/upload.rs`,
`src/session.rs`, `src/session/folder.rs`, `src/session/document/nests.rs`,
a new `src/names.rs`.

Patterns and fix:

1. Each `p.part_mut(x).unwrap()`, `p.device_mut(x).unwrap()`,
   `p.lane_mut(x).unwrap()`, `p.clip_mut(x).expect("the clip was found")`
   inside `self.edit(|p| ...)`, and each `self.doc.project.part(x).unwrap()`
   after a check: use `?` with the helpers `part_in` (exists,
   `parts.rs`), and new `device_in`, `lane_in`, `clip_in` on `Project`
   that return `anyhow::Result<&mut T>` with "no part {id}" texts.
   Remove the first check where the `?` gives the same error.
2. `find_param(...).unwrap()` (`devices.rs:307,322`): return the error
   "the device has no parameter `x`".
3. One `names::free(dir_or_set, stem, ext, Scheme)` for the 5 helpers.
   Keep each scheme that a user sees today (file names on disk are
   user-visible), with one enum `Scheme` (`Dot`, `Dash`, `Space`), and
   write in the ticket which scheme each caller keeps. The owner can
   choose one scheme later.

Acceptance criteria:

- `rg '\.(part|part_mut|device|device_mut|lane|lane_mut|clip_mut)\([^)]*\)\.(unwrap|expect)\(' crates/paw-core/src`
  finds nothing outside `#[cfg(test)]`.
- One free-name function; `rg 'fn (free_name|free_path|unique_path|unique)\b' crates/paw-core/src` finds only it.
- Tests: one unit test per scheme of `names::free`; the existing tests
  of upload and trash pass unchanged.

Must not change: error texts that Lua sees (check them with
`rg` in `tests/` and `runtime/`), file names on disk.

Conflicts: T96 (no: session, not api), M1 (only `session/document/clips.rs`
if M1 edits clip edits; check), G3 devices view (`session/devices.rs` if
G3 adds Rust; check before start).

### CORE-3. Split the kernel's `Shared`, `Mapper`, and the long functions (m-10)

Files: `src/api/mod.rs`, `src/kernel.rs`, `src/kernel/reactor.rs`,
`src/api/*.rs` (field paths only), `src/scene.rs`, `src/sync/mapper.rs`
and its users in `src/sync/`, `src/session/save.rs`,
`src/sync/routing.rs`, `src/measure/mod.rs`, `src/attr_map.rs`,
`src/session/recording.rs`, `src/session/promote.rs`, `src/xml.rs`.

Work:

1. `Shared` (40 fields) becomes `Shared { session, screen: Screen,
   seats: Seats, turn: Loop, timers: Timers, io, clock, started,
   watchdog, measures, clients }`. `Screen` holds grid, highlights,
   dirty, live_dirty, frames, snapshot, kept_cells, redraws,
   line_redraws, cursor, attached. `Seats` holds sizes, caps, seat,
   desk, input_from, detach. `Loop` holds rx, inbox, turning, waiter,
   missed, missed_wakes, quit, reload. Each sub-struct has methods for
   what the callers do now (for example `Screen::mark_dirty`).
2. `Mapper`: the per-part maps (`parts`, `mix`, `inputs`, `midi_inputs`,
   `midi_outputs`, `outs`, `pieces`, `host_latency`, `played`,
   `cue_rows`, `cue_events`, `state_main`, `local`, `trees`, `meters`)
   become one `HashMap<Id, PartSent>` where the data has the same key
   and life. Do this part only after TASK-312, or leave it to TASK-312.
3. Split each function over 100 lines (list in finding 14; first
   `save_own_row` 285, `vocoder` 158, `build_schedule` 157,
   `measure::start` 151, `attr_map::downgrade` 139, `xml::decode` 126,
   `xml::encode_el` 121, `add_recorded_audio` 118, `nest_promote` 115,
   `add_recorded_notes` 114) into named steps, a struct with methods
   where the steps share state.
4. Bool flags: `send_plan(held, fresh)`, `renumber(devices_only)`,
   `write_file(keep_backup)`, `clip_set_notes(append)`,
   `media_relink(anyway)` get two-variant enums.

Acceptance criteria:

- `Shared` has 15 fields or fewer; no sub-struct has more than 12.
- `clippy::too_many_lines` (threshold 100, in `crates/paw-core/clippy.toml`)
  gives no warning outside `install` functions (they get
  `#[expect(clippy::too_many_lines, reason = "a table of paw.api functions")]`).
- `clippy::fn_params_excessive_bools` gives no warning.
- All Rust tests of paw-core and the Lua suite pass with no change of
  a test.

Must not change: behavior, the order of work in a turn, the protocol.

Conflicts: T96 (field paths in `api/*.rs`: do item 1 after T96 merges,
or in one session with a rebase), TASK-312 (Mapper, `sync/`), TASK-294
(`kernel/reactor.rs`), TASK-149 (tests that read `Shared` fields).

### CORE-4. No sleep loops on the kernel thread (m-10)

Files: `src/session.rs` (`settle_plugins`), `src/session/statelanes.rs`,
`src/session/devices.rs`, `src/session/loading.rs`, `src/io.rs`,
`src/kernel.rs` (MIDI queue), `src/doorbell.rs`.

Work:

1. Each wait in finding 7 waits on the doorbell (`Waiter`) or on the
   channel that the other thread already uses, with the same limit of
   time. A wait that must poll a plugin (`controller.idle()`) polls
   on the doorbell's timer, not in `sleep`.
2. MIDI input: send `(port, kind)` in the kernel channel, or one
   `crossbeam`/`std::sync::mpsc` channel, not `Arc<Mutex<VecDeque>>`
   plus a wake message. Keep the rule that a script that waits empties
   it.

Acceptance criteria:

- `rg 'thread::sleep' crates/paw-core/src` finds only threads that are
  not the kernel thread (watchdog, workers) and tests.
- A test with the stepped clock shows that a load, a state lane and a
  plugin state request finish with no wall-clock sleep (wait for the
  state, AGENTS.md rules).

Must not change: the time limits, the messages, the audio thread rules.

Conflicts: TASK-331 plugin threads (paw-plugins, plugin state calls):
do after TASK-331. TASK-294 (the 16 ms wait in `reactor.rs`): one
agent should do both.

## 3. Proposed lints and checks

In the workspace `Cargo.toml` `[workspace.lints.clippy]` (each `warn`,
as the file does now):

| Lint | Stops |
| --- | --- |
| `allow_attributes_without_reason` | finding 21 |
| `allow_attributes` (use `#[expect]`) | stale allows |
| `too_many_lines` (+ `too-many-lines-threshold = 100` in each `clippy.toml`) | finding 14 |
| `fn_params_excessive_bools`, `struct_excessive_bools` | finding 15 |
| `unwrap_used` (+ `allow-unwrap-in-tests = true` in `clippy.toml`; keep `lock().unwrap()` with `#[expect]` at the 33 sites, or allow it through a `fn locked()` helper) | finding 6 |
| `trivially_copy_pass_by_ref` | `is_zero(&f64)` helpers |
| `float_cmp` | `*value == 1.0` in `is_one` |

Small checks (a script in `tools/`, run by `nix flake check`):

1. `rustlint.sh constants`: fail on `fn \w+\(\) -> [A-Za-z0-9_<>\[\]]+ \{\s*[-0-9.a-z_:\[\]()]+\s*\}`
   when the name is in a `serde(default = "...")`. This stops
   `fn yes() -> bool { true }` in all crates.
2. `rustlint.sh merge-leftovers`: fail when `git ls-files '*.orig' '*.rej'`
   is not empty.
3. `rustlint.sh model-layer`: fail when a file in
   `crates/paw-core/src/model*` names `crate::(sync|session|api|kernel)`.
4. `rustlint.sh serde-skip`: fail on a new `fn is_(zero|false|true|one)\b`
   outside `serde_util.rs`.

## 4. Changes for the orchestrator

`architecture/11-risks.md`, table "Technical debt".

Replace the row:

```text
| Track kind, group and takes live in `meta`, and core code reads them | `runtime/lua/paw/edit.tl:261` | TASK-306, TASK-309 |
```

with:

```text
| Track kind, group and takes live in `meta`, and core code reads them, in Teal and in Rust (`is_vca`, `is_group`, `group_of`) | `runtime/lua/paw/edit.tl:261`, `crates/paw-core/src/sync/automation.rs:139`, `crates/paw-core/src/session/save.rs:91`, `crates/paw-core/src/freeze.rs:250` | TASK-306, TASK-309 |
```

Add these rows:

```text
| `model` calls `sync::repeats`: an upward reference that blocks the move to `paw-model` | `crates/paw-core/src/model/nest/time.rs:223` | bundle CORE-0, before TASK-95.1 |
| Serde defaults are one function for each constant (`fn yes() -> bool { true }`) | `crates/paw-core/src/attr_map.rs:72` | bundle CORE-1 |
| `api::Shared` has 40 fields of screen, loop and connection state | `crates/paw-core/src/api/mod.rs:56` | bundle CORE-3 |
| `session/folder.rs` is one large file (2333 lines) | `crates/paw-core/src/session/folder.rs:1` | bundle CORE-3, after TASK-312 |
| The kernel thread waits for plugins and loads in sleep loops | `crates/paw-core/src/session/loading.rs:313` | bundle CORE-4, after TASK-331 |
```

Fix at once (not a debt row): delete the tracked merge leftovers
`crates/paw-core/src/sync/mod.rs.orig`, `crates/paw-core/src/sync/mod.rs.rej`,
`crates/paw-engine/src/lib.rs.orig`, `crates/paw-engine/src/engine/msg.rs.orig`,
`crates/paw-engine/src/engine/apply.rs.orig` (added by 65864dd4).

## 5. Clippy counts

CLIPPY_PLACEHOLDER
