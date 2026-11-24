# Architecture review of paw: the Rust side and the extension system

Review only. No code and no tracked file changed. Audited at `fb9882bf`
(2026-11-22). Internal text, in Simplified Technical English.

The owner's focus, in short: the Rust side. Which abstractions can be
better and stay idiomatic Rust, which files can become smaller files,
how to decouple the parts that know too much of each other, and how to
give the extension system more power.

## 0. Method

The review follows the method of the skill
`improve-codebase-architecture` and its word list, the skill
`codebase-design` (both from `mattpocock/skills`, read on 2026-11-22).
The review uses these words with these meanings:

- **Module**: anything with an interface and an implementation (a
  function, a struct, a file, a crate).
- **Interface**: all that a caller must know: types, rules, order of
  calls, errors, costs.
- **Deep module**: much behavior behind a small interface. **Shallow
  module**: an interface that is almost as large as its implementation.
- **Seam**: the place where the interface of a module is, where you can
  change behavior without an edit in that place. **Adapter**: a thing
  that fills a seam.
- **Gain for callers** (the word of the skill for it is a lever) and **locality** (for
  maintainers: a change is in one place).
- **The deletion test**: if you delete the module, does complexity go
  away (a pass-through) or come back in many callers (it earns its place)?
- **One adapter is a seam on paper, two adapters are a real seam.** Do
  not add a trait for one adapter.

Changes from the process of the skill, for this task:

- The skill writes an HTML report and then asks the owner which finding
  to explore. The owner asked for this Markdown file and for tickets, so
  this file replaces the report, and the last part of this file holds
  the questions for the owner.
- paw has no glossary file and no folder of decision records. The words
  of the domain come from the agent instructions and from the
  explanation pages of the manual. The decisions not to open again come
  from the designs in `backlog/docs/designs` (platforms, the web, media,
  nests) and from the notes of the owner on tickets.
- Rust advice follows the skill `rust-skills` and its page on the
  recommended crates. The rules of the audio thread come first: no lock,
  no allocation, no wait.

Hot spots: `git log --since=2026-11-10` over `crates/` names these files
most often: the API of `paw-core` (42 commits), the session (41), the
window tests of `paw-gui` (31), the scene and app of the window (23,
21), sync (20), the kernel (19), the `paw` binary (18), `clap.rs` (18),
`model.rs` (18), `session/folder.rs` (17), `session/undo.rs` (16),
`vst3.rs` (16). The review gives these files more weight.

## 1. Measurements

### Crates

| Crate | Lines of Rust | Files | Depends on (paw crates) |
| --- | ---: | ---: | --- |
| `paw-core` | 42 569 | 112 | `engine`, `luadev`, `proto`, `raster`, `scene` |
| `paw-engine` | 25 939 | 68 | none |
| `paw-plugins` | 12 773 | 29 | `engine` |
| `paw-gui` | 11 879 | 25 | `listen`, `proto`, `raster`, `scene` |
| `paw-mcp` | 5 771 | 17 | `proto` |
| `paw-tui` (the `paw` binary) | 3 775 | 8 | all but `gui` and `mcp` |
| `paw-raster` | 2 526 | 7 | `scene` |
| `paw-scene` | 1 564 | 4 | none |
| `paw-luadev` | 1 267 | 3 | `engine` |
| `paw-proto` | 885 | 5 | none |
| `paw-listen` | 298 | 1 | `proto` |

The runtime in Lua and Teal has about 110 000 lines more (`runtime/`,
without `tl.lua` and `compat53`).

The graph of crates is good. `paw-core` does not depend on
`paw-plugins`: the binary gives the kernel a `Registry` of device
factories. The scene crate depends on nothing, and both frontends use
it.

### Largest files (code lines before `#[cfg(test)]`, then test lines)

| File | Code | Tests | Note |
| --- | ---: | ---: | --- |
| `paw-plugins/src/vst3.rs` | 1 900 | 0 | loader, host callbacks, run loop, factory, device, controller, editor, streams |
| `paw-core/src/model.rs` | 1 836 | 204 | all model types; `impl Project` at lines 1174 to 1689 |
| `paw-plugins/src/clap.rs` | 1 795 | 0 | the same roles as `vst3.rs` |
| `paw-core/src/session/folder.rs` | 1 638 | 205 | the format of the project folder |
| `paw-core/src/session/render.rs` | 1 264 | 18 | offline render, stems |
| `paw-core/src/session.rs` | 1 091 | 0 | the `Session` struct and its option types |
| `paw-gui/src/runner.rs` | 1 010 | 0 | the `winit` loop and the GL surface together |
| `paw-engine/src/device.rs` | 989 | 75 | `Device`, `Controller`, `DeviceFactory`, `Registry` |
| `paw-core/src/session/undo.rs` | 957 | 186 | |
| `paw-core/src/session/devices.rs` | 930 | 0 | |
| `paw-core/src/session/media.rs` | 888 | 131 | |
| `paw-core/src/session/transport.rs` | 869 | 0 | transport and the record of takes |
| `paw-gui/src/app.rs` | 848 | 44 | |
| `paw-gui/src/scene.rs` | 821 | 82 | |

No file has more than 2 000 lines of code. An earlier refactor split
`api.rs` into `api/` and `session.rs` into `session/`. The large files
that stay are the plugin hosts and the model.

### Longest functions (not tests)

| Lines | Function | Kind of length |
| ---: | --- | --- |
| 353 | `paw-core/src/api/screen.rs:154 install` | a list of `define!` entries |
| 349 | `paw-mcp/src/tools/write.rs:14 tools` | a table of tools with JSON Schemas written by hand |
| 312 | `paw-core/src/api/clips.rs:117 install` | a list of `define!` entries |
| 275 | `paw-plugins/src/lv2/factory.rs:60 create` | one long procedure |
| 226 | `paw-plugins/src/lv2/controller.rs:273 open_editor` | one long procedure |
| 225 | `paw-plugins/src/vst3.rs:1195 process` | audio thread: events, buffers, call, output |
| 224 | `paw-core/src/api/devices.rs:12 install` | a list of `define!` entries |
| 204 | `paw-plugins/src/vst3.rs:940 create` | one long procedure |
| 202 | `paw-plugins/src/clap.rs:726 process` | audio thread, as in `vst3.rs` |
| 193 | `paw-core/src/scene.rs:357 install` | a list of `define!` entries |
| 171 | `paw-engine/src/devices/drums.rs:189 render` | DSP |
| 158 | `paw-core/src/stretch.rs:341 vocoder` | DSP |
| 153 | `paw-core/src/sync/routing.rs:206 build_schedule` | order of the graph and delay compensation |
| 147 | `paw-core/src/measure/mod.rs:120 start` | |
| 123, 122, 122, 106 | `session/transport.rs`: `finish_take`, `add_recorded_audio`, `add_recorded_notes`, `start_take` | the record of takes |

### Other counts

- `paw.api`: about 330 functions (`runtime/types/paw/api.d.tl` has 332
  typed entries), in one flat table, made in 20 `install` functions.
- `Session`: 30 fields (`session.rs`, lines 498 to 568), 208 public
  methods in 33 files that each add an `impl Session`. 45 of the 208
  methods touch only the state of the model (project, undo, ids,
  events). The others touch the link to the engine (39), live devices
  (18), the audio cache (17), MIDI (13) and more. Only 18 Rust tests
  cover the session. The Lua suite covers the rest through a whole
  kernel.
- `Shared` (`api/mod.rs`, lines 48 to 112): 26 fields for the screen and
  seats, timers, connections, helper processes, MIDI input, scenes and
  options.
- JSON as the inner format: 154 `json!` in the session, 40 public
  methods of the session take or give `serde_json::Value`, and `api/`
  has 88 calls of `to_lua`. The window reads the state from the kernel
  through 192 string keys (`s["modal"]["panes"]...`); the binary and
  `paw-mcp` through 333.
- Typed shapes kept by hand: `runtime/lua/paw/types.tl`, 1 781 lines,
  146 records, written "from the Rust that builds each table".
- `paw-core` declares 37 public modules and about 700 `pub fn`, and 21
  items are `pub(crate)`. The binary uses about 12 items of it.
- No manifest has `[lints]`, `[workspace.lints]` or `rust-version`.
- `unwrap()` outside test modules: `paw-core` 50, `paw-plugins` 54,
  `paw-gui` 30, `paw-engine` 6. Most are `lock().unwrap()` (49 in all).
- Error types: `anyhow` in 53 files of `paw-core`; `thiserror` types in
  6 places (media table, custom clips, MIDI filter, the scan of Lua
  devices, the sandbox wire, raster pixels). Lua never matches an error
  kind: the only matches on error text outside tests take the first line
  for display (`autosave.lua:159`, `frontend.tl:3192`).
- State for the whole process: `paw_luadev::HELPER`
  (`paw-luadev/src/lib.rs:43`), `sandbox::HOST` and `CACHE`
  (`paw-plugins/src/sandbox/mod.rs:51,53`), `ADDED_DIRS`
  (`paw-plugins/src/lib.rs:127`), `session::panic::LATEST`,
  `encode::ENCODERS`.
- The rules of the audio thread hold where the review looked: the CLAP
  and VST3 `process` functions take the plugin with `try_lock`
  (`clap.rs:733`, `vst3.rs:1203`), and the `cpal` callback uses
  `try_lock` (`backend/cpal.rs:380`).

## 2. Summary: the top findings, by value and risk

Value: how much gain for callers or locality the change gives, and what
it unblocks. Risk: the chance to break behavior. Size: S is less than 1
day, M is 1 to 3 days, L is 3 to 7 days.

| # | Finding | Value | Risk | Size | Order | Ticket |
| --- | --- | --- | --- | --- | --- | --- |
| F1 | A `Document` module out of `Session`: the model, edits and undo without the engine, then a `paw-model` crate | high | medium | L | 3 | TASK-95 (m-1), refines TASK-51 |
| F2 | One typed source for the shapes that cross `paw.api`, MCP and the frontends (views, patches, frontend state) | high | medium | L, in parts | 4 | TASK-96 (m-6) |
| F3 | One `DeviceProvider` seam for the built-in devices, plugins, Lua devices and later WebAssembly, in place of four closures and global state | high | low | M | 2 | TASK-97 (m-5), before TASK-1 |
| F4 | The interface of `paw-core`: `pub(crate)`, workspace lints, `rust-version` | medium | low | S | 1 | TASK-98 (m-6), note on TASK-20 |
| F5 | `Shared` in parts, and the host services (sockets, processes, TLS) behind a `native` feature | high for the web | low | M | 5 | TASK-99 (m-1), refines TASK-44 and TASK-51 |
| F6 | Plugin host files split by role (`clap.rs`, `vst3.rs`, LV2) | medium | low | M | 6 | TASK-100 (m-6), prepares TASK-47 |
| F7 | One measurement module for `paw-core` and `paw-mcp` | medium | low | M | 7 | TASK-101 (m-6) |
| F8 | The record of takes in its own module, and no wait on the kernel thread | medium | medium | M | 8 | TASK-102 (m-3) |
| F9 | Platform seams: modules chosen at compile time where one build has one adapter, traits only where it has two | high for platforms | low | in TASK-43 | with TASK-43 | note on TASK-43 and TASK-51 |
| F10 | Extension registries as one typed `Registry<T>` in Teal | medium | low | M | 9 | TASK-103 (m-5), generalizes TASK-17 |
| F11 | What an extension needs, in its manifest (`needs`) | medium for the web | low | S | 10 | TASK-104 (m-5) |
| F12 | A lock file of the API before the first tagged release | low now | low | S | last | TASK-105 (m-6, low) |

The order in short: F4 first (cheap, and then the compiler shows dead
code), then F3 (it unblocks WebAssembly devices), then F1 and F2 (the
large ones, area by area), then F5 with the web and platform work.

## 3. The findings

### F1. A `Document` module out of `Session`

**Evidence.**

- `Session` (`paw-core/src/session.rs`, lines 498 to 568) has 30 fields:
  the project and its last synced copy, undo, ids, the link to the
  engine, the device registry, the audio cache, live devices, transport
  and playback, the path, the screen, events and warnings, the recorder,
  MIDI ports, the write of files, render jobs, state lanes, loads, the
  watch of files, media sources, the shelf and audition.
- 208 public methods in 33 files (`impl Session` in each file of
  `session/`). The interface is as wide as the implementation: a
  **shallow** module, split by file but not by type.
- `Session::new` (`session.rs:626`) starts the engine
  (`start_engine(opts)`). A test of an edit therefore needs an engine.
  The session has 18 Rust tests. Only the Lua suite, with a whole kernel,
  tests the behaviors.
- 45 methods touch only the state of the model (`project`, `edit`,
  `undo`, `new_id`, `dirty`, `named`, `clip_kinds`, `emit`).
  `Session::edit` (`session/editing.rs:12`) is already a small, deep
  seam: a closure over `&mut Project`, with undo and the names of new
  notes after it.
- The model files depend only on data modules of `paw-engine`
  (`automation`, `launch`, `midi_form`, `midi_out`, `ump`) and on
  `crate::stretch` and `crate::edits`. `paw-engine` builds for `wasm32`
  (the web design). The model can therefore be portable now.

**Proposed change.**

1. Make a `Document` struct in `session/document.rs`: `project`, `undo`,
   `next_id`, `dirty`, `named`, `clip_kinds`, the waiting `events` and
   `warnings`. Move `edit`, `edit_named`, `new_id`, undo and redo, and
   the 45 methods that touch only the model to `impl Document`. `Session`
   keeps `pub doc: Document` and the link to the engine, and its other
   methods call `self.doc`. `sync` still compares `synced` with
   `doc.project`, so the rule "only `sync` tells the engine" stays.
2. Move the field logic of each area (tracks, clips, devices, lanes) to
   `impl Document`, one branch for each area. A method that needs the
   engine (a live parameter of a device) stays on `Session` and calls the
   document for the part of the model.
3. When the document has no type of the engine in it, move `model.rs`,
   `model/`, `history.rs`, `attr_map.rs`, `clipfile.rs`, `edits.rs`,
   `events.rs`, the document and the pure part of `session/folder.rs`
   (`layout` and `read`: bytes in and out; `commit` stays in `paw-core`
   with the file system) to a new crate `paw-model`. It has no calls to
   the operating system, and CI builds it for `wasm32`.
4. Split `model.rs` in the same move: `model/project.rs` (`impl
   Project`), `model/track.rs`, `model/clip.rs`, `model/lane.rs`,
   `model/check.rs` (the `check_*` functions, lines 1689 to 1837).

**Gain.** Locality: the rules of an edit are in one place. The interface
is the test surface: edits and undo get fast Rust tests without an
engine (the deep module is `Document`, not 208 methods). The portable
core of TASK-51 and TASK-30 starts here, because `paw-model` has no
`tokio`, no `rustix` and no LuaJIT. A change in the model compiles less
code.

**Risk.** Medium. Many files change. Do it area by area, with no change
of behavior, and the Lua suite as the guard. Keep `pub use` paths for
one branch, so that callers move in small steps.

**Size and order.** L, in 4 or 5 branches. After F4.

### F2. One typed source for the shapes that cross the seams

**Evidence.**

- Code builds each view by hand as JSON. `Session::track_view`
  (`session/tracks.rs`, lines 6 to 29) is a `json!` map of about 30
  keys, and `track_field` (lines 34 to 58) lists most of them again in a
  `match`. `clip_view`, `lane_view`, `device_view`, `project_view` and
  `transport_view` do the same. The session has 154 `json!`.
- A setter reads a string key into an `enum` (`TrackField`,
  `tracks.rs`, lines 259 to 283) and the value as a `serde_json::Value`,
  read again for each field. The API reads a Lua table into a
  `serde_json::Value` first (`api/tracks.rs`, lines 58 to 69), so each
  call converts two times.
- `runtime/lua/paw/types.tl` (1 781 lines, 146 records) gives the Teal
  types of these tables, written by hand. No check makes sure that the
  record `Track` (`types.tl:248`) and the `json!` of `track_view` agree.
- `paw-mcp` writes the JSON Schemas of its tools by hand
  (`paw-mcp/src/tools/write.rs`, lines 14 to 362, and `schema.rs`), for
  the same shapes (track, clip, device, send).
- The window reads the frontend state (`frontend.watch`, made in
  `frontend.tl`) as JSON without types: 192 string keys in `paw-gui`,
  for example `s["modal"]["panes"]["panes"]` in `chrome.rs:199`.
- `tools/apidoc.lua` already makes Teal records from serde structs
  (`apidoc.lua`, lines 1277 to 1300), and it does so for
  `paw-scene/src/props.rs` (the props of roles) today.

**Proposed change.** One typed struct for each shape, and the other
descriptions made from it:

- `#[derive(Serialize)] struct TrackView { ... }` and
  `#[derive(Deserialize)] #[serde(deny_unknown_fields)] struct TrackPatch
  { name: Option<String>, output: Option<Option<Id>>, ... }` (with
  `serde_with`'s double option or a small `Patch<T>` `enum`, so that a
  patch can clear a field). The API converts the Lua table straight to
  the struct with the serde support of `mlua` (`lua.from_value`) and back
  (`to_lua`), with no `serde_json::Value` between. `TrackField` goes
  away, or becomes the list of the fields of the patch.
- `tools/apidoc.lua` writes the Teal records from these structs, as it
  does for the props of roles. `types.tl` keeps only what does not come
  from Rust.
- `paw-mcp` makes its schemas with `schemars` (`rmcp` supports it), from
  the same structs. `paw-mcp` does not depend on `paw-core`, so the
  shapes go in a crate that both can use: `paw-model` (F1) or
  `paw-proto`.
- The frontend state (`panes`, `modal`, the transport) becomes typed
  structs in `paw-proto`, with Teal records made from them, so the
  window reads fields and not strings. The web frontend (TASK-32,
  TASK-34) uses the same types.

**Gain.** For callers: one definition gives the Rust type, the Teal
record, the MCP schema and the type of the window. Locality: a new field
is one edit. An unknown key is an error at the seam. A call converts one
time, and the view of a clip with many notes costs less (TASK-14 removed
one such JSON copy for the clip list).

**Risk.** Medium. Behavior at the edges can change: today a patch with an
unknown key fails in the parse of `TrackField`, and a view key that is
`null` reads as nil in Lua (`to_lua` keeps that behavior). Keep the same
texts of errors (the page on recommended crates: "the same error texts
that Lua or a user sees").

**Size and order.** L in all. One branch for each area: tracks first (the
smallest area with a record written by hand, a setter and an MCP tool),
then clips, devices, lanes, the transport, the project, and last the
frontend state.

### F3. One `DeviceProvider` seam for all sources of devices

**Evidence.**

- `Registry` (`paw-engine/src/device.rs`, lines 792 to 803) holds the
  factories and four optional closures: `rescan`, `add_dir`,
  `remove_dir`, `attach` (type aliases at lines 776 to 790). The binary
  fills them (`paw-tui/src/main.rs`, lines 421 to 460).
- The same binary sets state for the whole process: the helper of Lua
  devices (`paw_luadev::set_helper`, a `OnceLock` at
  `paw-luadev/src/lib.rs:43`), the command and cache of the plugin host
  (`sandbox::set_host_command`, statics at `sandbox/mod.rs:51,53`), and
  the added folders (`ADDED_DIRS`, `paw-plugins/src/lib.rs:127`).
- The helper process chooses its kind of device by a text prefix: a
  kind that starts with `lua:` is a Lua device (`main.rs:367`), and
  `plugin-scan lua` scans Lua devices (`main.rs:382`).
- The seam is real: the built-in devices (`devices::register`), CLAP,
  VST3, LV2, the sandbox wrapper (`sandbox::wrap`, `sandbox/mod.rs:107`)
  and Lua devices are five adapters today, and WebAssembly devices
  (TASK-1) are the sixth.
- The `Controller` trait (`device.rs:208`) has 22 methods. Four are for
  the editor window (`has_editor`, `editor_open`, `open_editor`,
  `close_editor`) and three for diagnostics (`health`, `late_blocks`,
  `busy_time`). A Lua or WebAssembly device has none of these.

**Proposed change.**

```rust
/// A source of device kinds: the built-in devices, the plugin formats,
/// the Lua devices, the WebAssembly devices. Lives on the main thread.
pub trait DeviceProvider {
    fn name(&self) -> &'static str;
    /// Register what this provider finds now; give notes for the user.
    fn scan(&mut self, kinds: &mut Kinds) -> Vec<String>;
    fn rescan(&mut self, kinds: &mut Kinds, only: Option<&str>) -> Vec<String> { ... }
    fn add_dir(&mut self, kinds: &mut Kinds, dir: &Path) -> Added { Added::default() }
    fn remove_dir(&mut self, kinds: &mut Kinds, dir: &Path) {}
    fn attach(&mut self, _lib: &Path) -> Result<String> { bail!("...") }
}
```

- `Registry` keeps the factories (`Kinds`), the posts and aliases, and a
  `Vec<Box<dyn DeviceProvider>>`. `rescan`, `add_dir` and the others
  call each provider in turn. The four `Option<Rc<dyn Fn>>` go away.
- `PluginProvider` (in `paw-plugins`) owns the cache path, the host
  command and the added folders as fields: no statics. `LuaProvider` (in
  `paw-luadev`) owns the path of the helper. Each provider makes its
  sandbox factories itself, so `sandbox::wrap` becomes a step in
  `PluginProvider::scan`.
- The helper process gets a typed choice (`enum HostKind { Plugin, Lua,
  Wasm }` in a `clap` subcommand), not a `lua:` prefix.
- Make `Controller` narrower: `fn editor(&mut self) -> Option<&mut dyn
  Editor>` for the four window methods, and one `fn stats(&mut self) ->
  Stats` for the diagnostics. Default methods keep the small devices
  short (rust-skills `trait-default-methods`).

**Gain.** For callers: a new kind of device (WebAssembly, TASK-1) is one
adapter and no change to the binary. The web build leaves the plugin
provider out with a cargo feature. Tests can register a fake provider.
No global state, so two kernels in one test process do not share a host
command.

**Risk.** Low. The behavior stays; the plugin tests and the tests of Lua
devices guard it.

**Size and order.** M. Second, before TASK-1.

### F4. The interface of `paw-core`: visibility, lints, `rust-version`

**Evidence.** `paw-core/src/lib.rs` has 37 `pub mod`. The crate has about
700 `pub fn` and 21 `pub(crate)` items. The binary uses about 12 items:
`Kernel` and its options, `grid::{Grid, Cell}`, `remote::{apply,
input_json}`, `rpc::Connection`, `tls::{identity, default_dir}`,
`session::panic`, `clipfile::{text, decode}`. No crate has `[lints]`,
and no manifest has `rust-version`.

**Proposed change.** Add `[workspace.lints]` with `rust.unreachable_pub
= "warn"` and the clippy rules that TASK-20 settles, and `rust-version`
in `[workspace.package]` (rust-skills `proj-msrv-declare`). Make each
module of `paw-core` `pub(crate)` except the items above (rust-skills
`proj-pub-crate-internal`, `proj-pub-use-reexport`). The compiler then
warns about dead code that `pub` hides today. Delete the dead code that
it finds.

**Gain.** The interface of `paw-core` becomes what its callers use. Dead
code shows. F1 and F5 get a clear list of what crosses the edge of the
crate.

**Risk.** Low. Size S. First, because it is cheap and makes the next
steps safer.

### F5. `Shared` in parts, and the host services behind a feature

**Evidence.**

- `Shared` (`api/mod.rs`, lines 48 to 112) has 26 fields with `RefCell`
  and `Cell`. `api/screen.rs` touches only the fields of the screen (19
  uses of `sh.grid` and none of `sh.session`). The other areas touch
  only the session. Each closure of `paw.api` gets all of `Shared`.
- `Shared` holds `io: RefCell<Io>` (helper processes and sockets, Unix
  only, `io.rs`) and `clients: rpc::Clients` (`tokio` sockets, TLS).
  These are the blockers of `paw-core` for the web that the web design
  lists: `tokio` `net` and `process`, `rustix`, and `ring` through
  `rustls`.
- Few files of `paw-core` use the operating system for I/O: `rpc.rs`,
  `tls.rs`, `io.rs`, `io_runtime.rs`, `session/files_watch.rs`,
  `bake/helper.rs`, `session/encode.rs`, `safe.rs`, `api/processes.rs`.

**Proposed change.**

- Put the fields of `Shared` in structs: `Screen` (grid, sizes, caps,
  seat, highlights, dirty flags, frames, snapshot, redraws, attached,
  cursor), `Timers` (timers, next id), `Seats` (clients, the connection
  of the input, the connections that leave), `Inbox` (MIDI that came
  in). Each closure reads one part.
- Put the host services behind a default feature `native` in
  `paw-core`: `rpc`, `tls`, `io` (the Lua `proc_*` and `sock_*`
  functions), `bake::helper`, `encode`, `files_watch`. Without the
  feature, the functions exist and fail with a clear message ("helper
  programs are not in this build"), so the Lua runtime and the
  extensions see the same `paw.api`. These are modules chosen at compile
  time (F9), not traits.

**Gain.** Locality for the screen code. The web build of TASK-30 needs
only `--no-default-features`, and the list of what it does not have is
the list of the gated modules.

**Risk.** Low. Size M. Do it with TASK-44 (cargo features) or at the
start of TASK-30.

### F6. Plugin host files split by role

**Evidence.** `clap.rs` (1 795 lines) and `vst3.rs` (1 900 lines) each
hold, in one file: the load of the library, the plugin list, the
factory, the host callbacks, the run loop of timers and file
descriptors, the audio device with `process`, the controller, the editor
window, the state streams and the conversion of events. `process` has
202 lines (`clap.rs:726`) and 225 lines (`vst3.rs:1195`). In LV2,
`create` has 275 lines (`lv2/factory.rs:60`) and `open_editor` 226 lines
(`lv2/controller.rs:273`). The LV2 code is already a folder.

**Proposed change.** `clap/` and `vst3/` folders, as `lv2/` is:
`mod.rs` (the `PluginFormat` implementation), `library.rs` (load, list,
the bundle path), `host.rs` (callbacks, flags, run loop), `factory.rs`,
`device.rs` (the audio thread only), `controller.rs`, `editor.rs`,
`state.rs`, `events.rs` (the events of paw to the events of the format,
and back). Split each `process` into three named steps: events in, the
call, events and audio out. Split the long LV2 functions by step in the
same way.

**Gain.** Locality: the code of a format on the audio thread is one file
that a reviewer reads with the rules of the audio thread in mind. The
platform work of TASK-47 (bundles, editor windows on macOS and Windows)
touches only `library.rs` and `editor.rs`.

**Risk.** Low (moves, no change of behavior), but unsafe code moves too:
keep each `// SAFETY:` comment with its block. The plugin tests and
`paw-plugins/tests/no_alloc.rs` guard it. Size M.

### F7. One measurement module for `paw-core` and `paw-mcp`

**Evidence.** `paw-core/src/measure/` (`analysis.rs`, 971 lines)
measures loudness, true peak, spectrum and stereo. `paw-mcp/src/audio.rs`
has its own WAV reader, RMS levels and an FFT spectrum in octave bands
(`analyze`, 139 lines). `paw-mcp` does not depend on `paw-core`, which
is correct (it is a separate process), so it cannot use the module of
the core.

**Proposed change.** A crate `paw-measure` with the analyzer of
`measure/analysis.rs` (and `peaks.rs` if it fits). `paw-core` and
`paw-mcp` use it. `paw-mcp` keeps its texts for the model and takes the
numbers from the shared analyzer, so a render that the MCP tools
describe and one that `:mix` measures give the same numbers.

**Gain.** One analyzer, one set of tests (the 398 lines of
`measure/tests.rs`). `paw-core` gets smaller.

**Risk.** Low. The MCP texts must keep their form. Size M.

### F8. The record of takes in its own module, with no wait

**Evidence.** The logic of a take is in `impl Session` in
`session/transport.rs`: `start_take` (106 lines), `finish_take` (123),
`add_recorded_audio` (122), `add_recorded_notes` (122). The `Recorder`
struct (`session.rs:136`) holds only data. `finish_take`
(`transport.rs`, lines 397 to 410) waits on the kernel thread for up to
2 s, with `std::thread::sleep` of 1 ms in a loop, until the engine
closes the take.

**Proposed change.** A `record` module with a `Take` type that owns the
steps: start, collect, close, and make clips. The session calls it. The
close becomes a state: the kernel sends `SetTake(None)`, returns, and
finishes the take when the engine says that it closed it (a kernel
message, as for stretch results). The undo step and the feedback stay
one user action.

**Gain.** Locality for the record of takes. Rule 7 (fast keys): a stop
never blocks the kernel. Rust tests of the logic of a take, with the
null backend.

**Risk.** Medium: a take is the work of the user. Test with real keys
(`Space` to stop a take) and the null backend. Size M.

### F9. Platform seams: where a trait, where a module

The finding refines TASK-43 and TASK-51 and needs no ticket of its own.

**Evidence.** The platforms design lists about 40 ties to Linux in 8
crates. The web design lists the blockers for `wasm32` by crate. "The
child dies with its parent" (`PR_SET_PDEATHSIG`) is in 5 places:
`io.rs`, `bake/helper.rs`, `session/encode.rs`, `paw-mcp/src/kernel.rs`,
`paw-gui/src/client.rs` (the last one has no `cfg`). The audio backend
is an `enum` and modules with `cfg` (`backend.rs:22` `BackendChoice`,
`backend/cpal.rs`, `backend/no_cpal.rs`), with the null backend in the
same file (`backend.rs:467 spawn_null`).

**The rule for the seams** (rust-skills `trait-dyn-vs-generic` and
`anti-over-abstraction`, and "one adapter is a seam on paper"):

- **One adapter in a build: a module chosen at compile time, not a
  trait.** Write one module with the same function signatures for each
  target, chosen with `#[cfg_attr(target_os = "...", path = "...")] mod
  imp;`, as `std` does in `std::sys`. That form fits the doorbell
  (`futex`, `os_sync`, Event), shared memory, "the child dies with its
  parent", the local socket, the thread priority and the counts of CPU
  and disk. Each one has one adapter for each target, and a `dyn` call
  there costs a table of function pointers on the audio path for no
  gain.
- **Two adapters in one build: a trait or an `enum`.** The audio backend
  has `cpal`, null and offline in one build, and the web adds a backend
  that the browser drives from an AudioWorklet (pull, not a thread). MIDI
  has ALSA and "none" (tests) in one build, and later CoreMIDI, `midir`
  and Web MIDI (TASK-46). The terminal of TASK-32 has `crossterm` and the
  `xterm.js` ring. Device providers (F3).
- **A crate, not a seam,** where a recommended crate does the job:
  folders with `etcetera`, the watch of files with `notify`, random
  numbers with `ring` or `getrandom`, free disk space with `fs4`, CPU
  time with `sysinfo`.
- **No seam where the target gives the same API.** The web design chose
  `emscripten`, which gives `std::fs` over OPFS, threads and time. So the
  code of the project folder needs no file-system trait.
- Put the modules chosen at compile time in one crate (`paw-sys`), which
  `paw-core`, `paw-plugins`, `paw-tui`, `paw-gui` and `paw-mcp` use.
  Then "the child dies with its parent" is one function, not five
  copies.

### F10. Extension registries as one typed `Registry<T>`

See E2 in the part on the extension system.

### F11. What an extension needs, in its manifest

See E3 in the part on the extension system.

### F12. A lock file of the API before the first tagged release

See E5 in the part on the extension system.

### Findings with a note only (no ticket)

- **The long `install` functions** of `paw.api` (353, 312, 224 lines and
  more) are lists of `define!` entries, one short closure for each API
  function. The deletion test says that a split moves the length and
  does not remove it. Do not split them alone. F2 makes each closure
  shorter.
- **The runner of the window** (`paw-gui/src/runner.rs`, 1 010 lines,
  no tests) mixes the `winit` loop and the GL surface of `glutin` with
  damage swaps. When TASK-34 starts, move the GL surface into `gl.rs`,
  so that the web window replaces only that file. A note goes on
  TASK-34.
- **Typed ids** (`pub type Id = u64`, `model.rs:26`). Rust-skills says
  `type-newtype-ids`. But tracks, clips, devices, lanes and notes take
  ids from one counter (`next_id`), so ids never collide, and a mix-up
  gives "no track N", not a silent error. Wrapper types would touch
  about 330 API functions for a small gain. Not now.
- **`thiserror` everywhere.** The errors of the session are messages for
  the user (rule 6), and no caller branches on their kind. Keep `anyhow`
  in the session and the API. Keep `thiserror` where a caller branches
  (the sandbox wire, the scan, the media table), as now.
- **`lock().unwrap()`** (49 uses). A poisoned lock means a panic on
  another thread, and the engine guards devices itself. TASK-20's clippy
  settings decide.
- **Five `fn hex`** (`paw-gui/src/theme.rs:66`, `vst3.rs:175`,
  `paw-proto/src/lib.rs:60`, `paw-raster/src/vector.rs:132`,
  `paw-scene/src/cells.rs:272`). The page on recommended crates already
  lists them. `paw-scene::color::Rgba` has `FromStr`: use it for colors,
  and the `hex` crate for bytes. A note goes on TASK-20.
- **`build_schedule`** (`sync/routing.rs:206`, 153 lines) orders the
  tracks and calculates delay compensation. It is long, but it is one
  algorithm with tests in `sync/tests.rs`. Split it only when it changes
  next (order first, then the delays).

## 4. The extension system

### What an extension can do today

| From | It can | It cannot |
| --- | --- | --- |
| Lua or Teal in the kernel | Register commands, keys, views, buffer types, kinds of track and clip, pickers, query fields, parts of the status line, hooks, health checks, file formats, insert keys (about 36 registries in `ext.lua`, lines 249 to 410). Call all of `paw.api` (about 330 functions). Use the whole standard library, `ffi` and `debug` too (`kernel.rs`, lines 362 to 366, `Lua::unsafe_new`). Start helper programs and talk to them over pipes and sockets. | Run on the audio thread. Add a role that the window paints as a widget (the roles are a closed set in `paw-gui/src/roles.rs`; a view adds pixels with `paint` and pictures). Run when the target has no FFI or no processes (the web, Windows), and paw cannot tell before it fails. |
| Lua devices (`devices/*.lua`) | DSP in LuaJIT with FFI arrays, in a helper process with shared memory and a `futex` (no added latency). Get data through `device_call` and `device_post`, map files with `dsp.map`. | Run in the browser (no LuaJIT, no processes). Run in the process of the engine: each block costs a transfer to another process. |
| Native code that Nix builds | A CLAP or VST3 plugin in the folder of the extension (`paw.plugins.add_dir`), in a helper process. An attachment: a C library that paw loads into each plugin host (`include/paw_attach.h`, ABI 1), which reaches the own extensions of a CLAP plugin (ARA). A helper program (the .NET engine of utau). | Add a device that runs in the process of the engine, or an API function in Rust. Run on another platform without a build for it. |
| Rust (only in the core) | `DeviceFactory` and `Device`: the built-in devices. | Nothing outside the workspace. |

The model is the one of Neovim: no separate plugin interface, all is the
one API. The model keeps the core small. The gaps are three: native speed
without a process, a typed and general way to own registrations, and a
way to say what an extension needs from the target.

### E1. WebAssembly devices through the `DeviceProvider` seam (refines TASK-1)

With F3, a WebAssembly device is one adapter, `WasmProvider`, and one
`DeviceFactory` with a `Device` that calls an export of the module.

- A WebAssembly module cannot touch memory outside its own and cannot
  crash the host, so it can run in the process of the engine, unlike a
  plugin. It then does not pay the transfer of each block that Lua
  devices pay.
- The rules of the audio thread: make the store, the instance and the
  linear memory on the main thread, with the block buffers inside the
  linear memory. `process` copies the inputs in, calls one export, and
  copies the outputs out. A module that runs away stops through epoch
  interruption (a counter that another thread increments), which needs no
  lock. The spike of TASK-1 must prove with `tests/no_alloc.rs` that the
  call path of the chosen runtime (`wasmtime` first) does not allocate
  after the instance exists.
- The device ABI: `init(rate, max_block)`, `process(frames)`,
  `set_param(index, value)`, `message(frame, ptr, len)`, `resting()`,
  and a descriptor (name, kind, parameters) as a custom section or an
  export that gives JSON. These are the four methods of `Device` and the
  descriptor of `DeviceInfo`, so the seam does not grow.
- On the web, the same module runs in the AudioWorklet next to the
  module of paw. The web plan already says "Lua devices: not in v1; with
  WebAssembly devices" (owner question 4 of the web design).
- Keep the sandbox for plugins. A WebAssembly device can still go
  through the sandbox wrapper when the owner wants a process for it (a
  device that uses much memory), because the wrapper wraps any factory.

### E2. One registry type for all extension entries

**Evidence.** `ext.lua` (846 lines) keeps about 36 registries, each made
with `keyed(kind, title, get, put)` (`ext.lua`, lines 148 to 176). Each
`get` reads the table of another module by name (`paw.pick.sources`,
`paw.ex.fields`, `paw.grep.sources`, and more). To find what an
extension owns, `ext.lua` copies each table before and after the load
and compares them. So `ext.lua` knows the inside of about 36 modules,
and each load copies all of them. TASK-17 found one gap of this kind:
`paw.roll_draw.keys` is not a registry, so its entries stay after an
unload.

**Proposed change.** A small Teal module `paw.registry`:

```lua
local record Registry<T>
   kind: string
   title: string
   put: function(self, key: string, value: T, owner: string)
   remove: function(self, key: string)
   get: function(self, key: string): T
   entries: function(self): function(): string, T
   owned_by: function(self, owner: string): {string}
end
```

Each module makes its own registry (`local sources =
paw.registry.new<PickSource>("pickers", "picker sources")`), and the
registry records the owner when an entry goes in (`paw.ext.caller()`).
`ext.lua` lists the registries that exist and unloads by owner. No
copies before and after a load, and a new module needs no edit in
`ext.lua`. The `ExtEntry` of TASK-17 becomes the type of the entries
that need `desc` and `order`. TASK-3 (lazy extensions) can then put
stub entries in the same registries, with an owner that is "not loaded
yet".

**Risk.** Low, module by module. `tests/extensions_api.lua` guards the
unload. Size M.

### E3. What an extension needs, in its manifest

**Evidence.** Extensions get `ffi`, `io.popen`, `os.execute` and the
helper programs. On the web (PUC Lua, no FFI, no processes) and on
Windows, some bundled extensions cannot work (the web design, "LuaJIT-only
features": 11 files use `ffi`; its owner question 5 lists the
extensions that do not ship). Today paw finds this out when the code
fails.

**Proposed change.** A field `needs` in `manifest.lua`:
`needs = { "ffi", "processes", "network", "native" }` (native: a part
that Nix builds). At load, paw compares `needs` with what the build has
(`paw.api.build()` gives the list: the Lua VM, the features of F5). An
extension that needs what the build does not have does not load, and
`:extensions` and `:checkhealth extensions` say why ("needs processes,
which this build does not have"). The web build reads the manifests to
choose which bundled extensions to ship.

The field is not a security sandbox, and the docs must say so. An
extension in the kernel can still call what it likes. A real limit on
what an extension can do is a WebAssembly extension (TASK-2), where the
host gives each import.

**Size.** S.

### E4. WebAssembly for the compute of an extension: bakers and ops (refines TASK-2 and TASK-10)

`bake::Bake` (`paw-core/src/bake/scheduler.rs:75`) has two adapters
today: `Native` (work on threads) and `Helper` (a process). The media
design (part 2.9) keeps the trait because of these two. A render op of
an extension as an export of a WebAssembly module is a third adapter,
`Wasm`: it runs on the worker threads, it cannot crash the kernel, and
it works on the web, where helper processes do not exist. The third
adapter is a smaller first step for TASK-2 than the whole `paw` API in
WebAssembly: an extension in Teal defines the op
(`paw.recipe.define_op`), and its `bake` gives a module and its
arguments in place of a command line. The generator of bindings that
TASK-2 plans (from the source of `paw.d.tl`) can type the arguments.

### E5. A versioned API, at the first release (new ticket, low)

`API_VERSION` is `"1.0.0"` (`api/mod.rs:208`) and did not change since
commit `b129ebce` added it, while `api/` had 15 commits in November. The
owner said that paw needs no compatibility before a tagged release, so
the constant is correct now. Before the first release:
`tools/apidoc.lua` writes an `api.lock` (each function of `paw.api` and
`paw.*` with its Teal type), and the check fails when the lock changes
and the version does not (a removal or a change needs the major number,
an addition the minor number). `:help` can then show the version that
added each function.

### E6. What stays as it is

- **No Rust libraries loaded into the kernel.** Rust has no stable ABI;
  `abi_stable` is large, and a crash in such a library stops the kernel.
  The C ABI stays where it is (CLAP, attachments), and portable native
  speed comes from WebAssembly (E1, E4, TASK-2).
- **Roles in the window stay a closed set.** A new widget is a core
  change in `paw-gui` and in the terminal cells, which keeps rule 2. An
  extension that wants more paints pixels (`paint`, pictures), which
  both frontends show.
- **`device_call(method, data)` stays text and bytes.** It is a call to
  a device in another process or language. A typed layer belongs in the
  extension (Teal records over the bytes), or in the WebAssembly
  bindings.

## 5. Platform seams that TASK-43 and the web plan need

In the order of the work, with the rule of F9:

| Seam | Adapters | Form | Where |
| --- | --- | --- | --- |
| Doorbell between processes | Linux `futex`; macOS `os_sync`; Windows Event | module chosen at compile time | `paw-sys`, used by the sandbox |
| Shared memory | `memfd_create`; `shm_open`; file mapping | module chosen at compile time | `paw-sys` |
| The child dies with its parent, kill a tree, priority | `PR_SET_PDEATHSIG` and process group; `kqueue`; Job object | module chosen at compile time | `paw-sys`; replaces 5 copies |
| Local socket | Unix socket; named pipe (`interprocess`) | crate | `paw-sys` gives it again |
| Thread class of the audio thread | `pthread_setschedparam`; the audio work groups of macOS; MMCSS | module chosen at compile time | `paw-sys`; from `pool.rs` and `sandbox/serve.rs` |
| Folders, the watch of files, random numbers, disk, CPU | `etcetera`, `notify`, `ring`, `fs4`, `sysinfo` | crates | where used |
| Audio backend | `cpal`, null, offline, AudioWorklet | trait or `enum` | `paw-engine` |
| MIDI | ALSA, none, CoreMIDI, `midir`, Web MIDI | trait | `paw-engine` (TASK-46) |
| Terminal I/O | `crossterm`, the `xterm.js` ring | trait | `paw-tui` (TASK-32) |
| Device sources | built-in devices, plugins, Lua, WebAssembly | trait | `paw-engine` (F3) |
| Host services of the kernel | sockets and processes, or none | cargo feature `native` | `paw-core` (F5) |
| Lua VM | LuaJIT, PUC Lua 5.2 | cargo feature | `paw-core`, `paw-luadev` (TASK-29) |
| Editor window of a plugin | X11, Cocoa, Win32 | module chosen at compile time | `editor.rs` of `paw-plugins` after F6 (TASK-47) |

## 6. The findings and the existing tickets

| Ticket | What this review adds |
| --- | --- |
| TASK-43 (platform seams) | F9: modules chosen at compile time for one adapter, traits for two; one `paw-sys` crate; "the child dies with its parent" in 5 places; the table of platform seams. |
| TASK-44 (cargo features, install layout) | F5: the `native` feature of `paw-core`, which the web needs too; the lints and `rust-version` of F4 in the same manifests. |
| TASK-51 (design of the portable core) | F1 (`Document`, `paw-model`), F5, F9 and the table of platform seams are inputs for its design. |
| TASK-77 (graph of derived data) | The sync layer keys on `Arc::ptr_eq` of the persistent snapshots (27 uses, `sync/mod.rs` lines 183 to 471, `sync/clips.rs:595`): a content stamp at no cost for the graph. `bake::Scheduler<K>` already has priorities and lanes, a natural runner for slices. The `Document` of F1 is the place where edits make the stamps. |
| TASK-1 (WebAssembly devices) | E1: one adapter of F3; the ABI is the four methods of `Device`; epoch interruption; the proof of no allocation in the spike. Depends on the ticket of F3. |
| TASK-2 (WebAssembly extensions) | E4: start with WebAssembly bakers (a third `Bake` adapter) before the whole API; E3 for what an extension needs; E6 (no Rust libraries in the kernel). |
| TASK-3 (lazy extensions) | E2: stubs as entries of typed registries, with an owner that is not loaded. |
| TASK-17 (pencil and insert) | E2 makes `ExtEntry` general for all registries. Do TASK-17 as planned; E2 takes it in later. |
| TASK-20 (clippy to zero) | The `[workspace.lints]` of F4 is the place for the clippy settings; the five `fn hex`; the decision on `lock().unwrap()`. |
| TASK-34 (the window on the web) | Move the GL surface of `paw-gui/src/runner.rs` into `gl.rs` first; the typed frontend state of F2. |
| TASK-47 (plugin bundles, editor windows) | F6 first, so that the work touches only `library.rs` and `editor.rs`. |
| TASK-10 (media M4 to M12) | E4: a WebAssembly baker as the third `Bake` adapter. |

New tickets: TASK-95 to TASK-105 (the list of tickets below).

## 7. What a reader of each crate meets first

- **`paw-engine`** is in good shape: clear traits (`Device`,
  `Controller`, `DeviceFactory`, `Starting`), messages as an `enum`
  (`engine/msg.rs`), the rules of the audio thread written on the trait,
  and tests that count allocations.
- **`paw-scene`** and **`paw-proto`** are small and deep.
- **`paw-core`** is the large one. Its sync layer is a deep module (one
  function, one rule: only `sync` tells the engine). Its session is the
  shallow part (F1), and JSON is its inner format (F2).
- **`paw-plugins`** has a good `PluginFormat` trait (`lib.rs:232`) and a
  sandbox that wraps any factory. Its two big files are the problem (F6).
- **`paw-gui`** reads JSON without types (F2) and mixes the loop with GL
  (see the notes).
- **`paw-mcp`** repeats shapes (F2) and an analyzer (F7).

## 8. Tickets made from this review

| Ticket | Finding | Milestone | Size |
| --- | --- | --- | --- |
| TASK-95 | F1: `Document` out of `Session`, then `paw-model` | m-1 | L |
| TASK-96 | F2: one typed source for views, patches, Teal records and MCP schemas | m-6 | L |
| TASK-97 | F3: `DeviceProvider` for all sources of devices | m-5 | M |
| TASK-98 | F4: the interface of `paw-core`, workspace lints, `rust-version` | m-6 | S |
| TASK-99 | F5: `Shared` in parts, host services behind `native` | m-1 | M |
| TASK-100 | F6: plugin host files split by role | m-6 | M |
| TASK-101 | F7: the crate `paw-measure` | m-6 | M |
| TASK-102 | F8: a `Take` module, no wait at the stop of a take | m-3 | M |
| TASK-103 | E2: one typed `Registry<T>` for extension entries | m-5 | M |
| TASK-104 | E3: `needs` in the manifest | m-5 | S |
| TASK-105 | E5: a lock file of the API before the first release | m-6 | S |

Notes went on TASK-1, TASK-2, TASK-3, TASK-10, TASK-17, TASK-20,
TASK-34, TASK-43, TASK-44, TASK-47, TASK-51 and TASK-77.

## 9. Questions for the owner

1. **A `paw-model` crate (F1)?** Recommended: yes, after the `Document`
   step shows that the model has no type of the engine in it. It is the
   first piece of the portable core of TASK-51.
2. **Where the shared shapes go (F2):** in `paw-model` (if F1 is done)
   or in `paw-proto` (now)? Recommended: `paw-proto` for the frontend
   state, `paw-model` for the shapes of the project; `paw-mcp` then
   depends on `paw-model`, which has no code for the operating system.
3. **`schemars` for `paw-mcp` (F2)?** It is a new dependency (well known,
   and `rmcp` uses it). Recommended: yes.
4. **WebAssembly devices in the process of the engine (E1)?**
   Recommended: yes, if the spike of TASK-1 proves no allocation on the
   call path; else in the sandbox, as plugins are.
5. **`needs` in manifests (E3): a refusal at load, or only a warning?**
   Recommended: a refusal with a clear message, because an extension
   that works only in part is worse.
6. **No Rust libraries loaded into the kernel (E6)?** Recommended:
   confirm, so that a later review does not propose them again.

## Owner decisions (2026-11-22)
All recommendations accepted: (1) paw-model crate after the Document step; (2) window state shapes in paw-proto, project shapes in paw-model; (3) paw-mcp may add schemars; (4) WebAssembly devices run in the engine process if the TASK-1 spike shows no allocation on the call path; (5) an extension whose needs the build lacks is refused with a clear message; (6) paw never loads Rust libraries into the kernel (do not propose it again). Naming: no Factory in paw's own traits (a device kind or provider with create()); Builder for values with many optional settings (Session, kernel, engine setup); plugin-format code may keep CLAP/VST3 factory names.
