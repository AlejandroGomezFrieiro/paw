# Rust architecture: a refinement of four designs

Superseded where it differs by [architecture-plan.md](architecture-plan.md) (2026-11-23).

Status: review and design. No tracked file changed. Nothing in the
repository was built. Internal text, in Simplified Technical English.
Date: 2026-11-23. Base: main at deb79a0f.

The owner asked: "Let's make sure our architecture design is idiomatic in
Rust, let's refine it with Rust best practices in mind."

The Rust refinement covers four designs:

- `m10-generalization-review.md` (Kinds, Template, Modifier, Linked,
  project sections, one parameter schema).
- `midi-modifier-stacks.md` (TASK-75).
- `event-loop-review.md` (TASK-292 to 297).
- `devices-graph.md` (the model, the plan, the chain language).

Each of the four designs has a note at its top that points here.

The rules used: the skill `rust-skills` (`api-newtype-safety`,
`type-newtype-ids`, `type-no-stringly`, `api-sealed-trait`,
`api-parse-dont-validate`, `trait-dyn-vs-generic`, `trait-object-safety`,
`anti-over-abstraction`, `err-thiserror-lib`, `serde-*`), its page
`paw-crates.md`, and the skill `paw-code` ("add a trait only when two
adapters use it now").

The proof: a scratch crate compiles the core types of the Rust refinement and runs
three tests. It is at
a scratch folder of the session that wrote this design (not kept).
(`src/kinds.rs`, `modifier.rs`, `linked.rs`, `sched.rs`, `graph.rs`).
`cargo test` passes; `cargo clippy` gives two warnings for scratch code
only (a missing `Default`, an unused method).

## 0. Summary

The four designs are sound in their shape. Their Rust has six problems
that repeat:

1. **Ids are strings or aliases.** `pub type Id = u64` (`model.rs:35`) is
   one alias for tracks, clips, devices and nodes. A link is
   `Option<String>` (`model.rs:621`). The designs add more ids
   (`KindId`, `DefId`, a split kind, a modifier kind, a param target
   `(Id, String)`) with no type for each family.
2. **A trait with one implementation.** `ModifierKind<C: Content>`
   (only `Midi`, and only `LuaKind` uses `dyn`), `Op<T>`,
   `TemplateKind` (no Rust implementation besides built-ins), and
   `Clock` (two implementations and a downcast method `manual()`,
   `clock.rs:16-24`).
3. **Lua called while Rust holds a borrow.** The modifier design calls a
   Lua kind from the evaluator in the sync. `Shared.session` is a
   `RefCell<Session>` (`api/mod.rs:52`). A `paw.api` call from that Lua
   code panics on `borrow_mut` or needs a hand-made write guard.
4. **A trait that is not dyn-compatible.** `Upkeep` has `const KIND`, so
   `Session::idle` cannot loop over `dyn Upkeep`.
5. **Errors as strings.** `check() -> Result<(), String>`, and paw-core
   uses `anyhow` in 66 files and `thiserror` in 2. The new modules give
   errors that callers must tell apart (a kind that waits, a kind that is
   newer, a bad parameter).
6. **A wake path that is not real-time safe.** The event-loop design
   wakes the main thread from CLAP `request_callback`
   (`clap/host.rs:128`). Clack calls that handler on any thread, also the
   audio thread. A `send` on `std::sync::mpsc` can allocate.

The refinement:

- **One id type with the family as a type:** `KindId<F: Family>`, where
  `Family` is a sealed trait with `const NAME` and `const ABSENT`. The
  absent rule is part of the type, not a field.
- **One envelope:** `Stored<F> { kind, version, data }`, read into
  `Loaded<F, T> { Ready, Newer, Absent }`.
- **One registry shape:** `Kinds<F, S>`, a stack of shadowed entries
  for each key, with the verbs of `paw.registry`: `put`, `get`,
  `remove`, `unload`, `owned_by`.
- **Closed `enum` plus an open variant, resolved late.** The model stores
  the name (`KindId<F>`). The compile step (the sync, the graph
  compiler) resolves the name in the registry to an implementation `enum`
  (`ModImpl::Builtin | Extern`, `SplitImpl::Builtin | Device`). So
  shadowing works and an unknown kind is kept.
- **Plan, then run.** The sync gives an `ExternJob` for each extension
  kind and returns. The kernel runs the job with no borrow held, and the
  sync goes on from the job. No Lua runs inside `Session`.
- **Schedule time is a type:** `ScheduleTime`. The clock is an `enum`. The
  agenda is a value with a union (`|`). `Upkeep` is dyn-compatible and
  returns outcomes as data. A `Doorbell` (an atomic bit set and a
  `mio::Waker`) wakes the main thread; the audio thread only sets a bit.
- **Errors:** `thiserror` `enums` at each new boundary (`KindError`,
  `ModError`, `GraphError`, the chain crate's `Diagnostic`). The kernel
  and `paw.api` keep `anyhow` and turn errors into messages.

## 1. References used

| Source | What the Rust refinement takes from it |
| --- | --- |
| Rust API Guidelines, C-NEWTYPE, C-SEALED, C-STRUCT-PRIVATE (<https://rust-lang.github.io/api-guidelines/>) | `newtype` ids, the sealed `Family` trait |
| Zed, "Ownership and data flow in GPUI" (<https://zed.dev/blog/gpui-ownership>) | "lease" state out during an update; `emit` and `notify` are queued as effects and flushed after the outermost update, "run-to-completion behavior without `reentrancy`". paw's turn already does this for events; the modifier jobs do it for Lua kinds. |
| `mlua` `Lua` docs (<https://docs.rs/mlua/latest/mlua/struct.Lua.html>) | `Lua::scope` gives non-`'static` callbacks that stop working after the scope; `app_data_ref` and `app_data_mut` panic on a conflicting borrow, the `try_` forms give an error. paw must not move `Shared` into app data to fix re-entry: it moves the same panic. |
| `mio` `Waker` docs (<https://docs.rs/mio/latest/mio/struct.Waker.html>) | `eventfd` on Linux, `EVFILT_USER` on `kqueue`; one `Waker` for each `Poll`, shared in an `Arc`; `Send + Sync`; not on WASI. |
| `libuv` `uv_async_send` (the event-loop design, 3.3) | one wake handle for each loop, wakes coalesce |
| "Real-time audio programming 101: time waits for nothing" (`rossbencina.com`, 2011) | no system call, lock or allocation on the audio thread: the reason the audio thread only sets a bit |
| `typetag` README (<https://github.com/dtolnay/typetag>) | registration through `inventory` and `ctor`; the README gives no fallback for an unknown tag. paw must keep unknown kinds, so `typetag` does not fit. |
| `bevy_reflect` `TypeRegistry` (<https://docs.rs/bevy_reflect/latest/bevy_reflect/struct.TypeRegistry.html>) and Bevy `Plugin::build(&self, &mut App)` | a registry that the application owns and plugins fill; built-in features are plugins over the same `App` API. This is the m-10 rule "built-ins use the public API". |
| rust-analyzer and `rowan` ("Resilient LL Parsing Tutorial", 2023) | a lossless syntax tree with comments for a formatter and a language server; a hand-written parser that recovers |
| Salsa (<https://salsa-rs.github.io/salsa/>) | early cutoff by a content key: the chain key of the modifier stack, and `derived.tl` already |

## 2. The shared core

All four designs use these types. They go in `paw-core/src/model/`
(and later `paw-model`, TASK-95.3). They need no OS call and no `mlua`.

```rust
// ---- families: the core defines them, extensions add kinds, never families
mod sealed { pub trait Sealed {} }
pub enum Absent { Keep, PassThrough, Refuse }
pub trait Family: sealed::Sealed + 'static {
    const NAME: &'static str;   // "clip", "split", "modifier", ...
    const ABSENT: Absent;
}
pub enum ClipFamily {}     // Keep        (the compiled sound plays)
pub enum TrackFamily {}    // Keep
pub enum SplitFamily {}    // PassThrough (the signal goes through)
pub enum ModifierFamily {} // PassThrough (the owner's decision: no kept result)
pub enum TemplateFamily {} // Refuse      (list it, do not make it)
pub enum MetaFamily {}     // Keep        (a declared key of `meta`)

// ---- one id type; the family is a type, so a clip kind is not a modifier kind
pub struct KindId<F: Family> { name: Arc<str>, _f: PhantomData<fn() -> F> }
// dot-joined lowercase words, at most 64 bytes: `video`, `quantize`, `musicops.arp`
impl<F: Family> FromStr for KindId<F> { type Err = KindError; /* ... */ }
// Serialize/Deserialize as a string; Clone, Eq, Ord, Hash by hand (no F bounds)

// ---- one versioned envelope
pub struct Version(NonZeroU32);                 // absent in a file means 1
pub struct Stored<F: Family> { pub kind: KindId<F>, pub version: Version, pub data: Arc<Value> }
pub enum Loaded<F: Family, T> { Ready(T), Newer(Stored<F>), Absent(Stored<F>) }
pub trait Versioned: Sized {                    // a Rust-implemented kind's record
    const VERSION: Version;
    fn migrate(data: &Value, from: Version) -> Result<Self, String>;
    fn store(&self) -> Value;
}

// ---- one registry shape, the same verbs as paw.registry (registry.tl)
pub enum Owner { Paw(&'static str), User, Extension(Arc<str>) }
pub struct Kinds<F: Family, S> { entries: BTreeMap<KindId<F>, Vec<(Owner, S)>> }
impl<F: Family, S> Kinds<F, S> {
    pub fn put(&mut self, kind: KindId<F>, value: S, owner: Owner);
    pub fn get(&self, kind: &KindId<F>) -> Option<&S>;
    pub fn remove(&mut self, kind: &KindId<F>) -> Option<S>;
    pub fn unload(&mut self, owner: &Owner) -> usize;
    pub fn owned_by<'a>(&'a self, owner: &'a Owner) -> impl Iterator<Item = &'a KindId<F>>;
}

// ---- ids of the model: newtypes over the u64 that the files hold now
pub struct TrackId(u64); pub struct ClipId(u64); pub struct DeviceId(u64); pub struct NodeId(u64);
pub struct DefId<D> { raw: u64, _d: PhantomData<fn() -> D> }   // a linked definition

// ---- the schedule clock
pub struct ScheduleTime(Duration);              // "when"; budget time stays Instant
pub enum Clock { Wall { started: Instant }, Manual { nanos: AtomicU64 } }
pub struct Agenda { pub ready: bool, pub in_flight: u32, pub next_due: Option<ScheduleTime> }
impl BitOr for Agenda { /* union: or, sum, min */ }
```

### 2.1 Why these shapes

- **`KindId<F>` and not one `KindId` for all.** The four designs name
  six families. A modifier stack that holds a clip kind is a real class
  of bug (copy and paste in `:clip.recipe`, an agent that edits JSON).
  The type parameter costs nothing at run time (`PhantomData<fn() -> F>`
  is zero size and keeps the id `Send + Sync`). The scratch crate shows
  that the derives need hand-written `impls` (a derive asks `F: Clone`);
  this is a few lines, once.
- **The names change.** The modifier design uses dotted names
  (`musicops.arp`); `Word` (`custom.rs:59`) does not accept a dot. One
  rule for all: dot-joined words. A bare word is free for any owner; the
  registry, not the parser, decides a clash. So `RESERVED`
  (`custom.rs:30`) and `ClipKindId` (`custom.rs:116`) go: the built-ins
  become entries of owner `Owner::Paw("paw.clips")`. `Word` stays for
  roles and port names.
- **The absent rule is a `const` of the family**, not a field of
  `Kinds` (the m-10 sketch had `family: &'static str, absent: Absent`).
  A family has one rule; a value cannot disagree with it.
- **`Loaded` is parse, do not validate.** The m-10 contract and the
  modifier design both describe three states (ready, newer, absent) in
  prose. As an `enum`, no code path can use data of a newer version as
  ready.
- **Ids are not generational keys.** paw's ids are written in files and
  never reused, so no ABA problem exists. `slotmap` keys do not fit
  saved ids. The engine already uses index `newtypes` (`TrackSlot`,
  `DeviceSlot`, `paw-engine/src/slot.rs:10-15`).
- **The model keeps names; the compile step keeps meaning.** A model
  field never holds `enum SplitKind { Band, Layer, ... , Ext(..) }`. It
  holds `KindId<SplitFamily>`. The graph compiler and the sync resolve
  the name through `Kinds<F, S>` each time they compile. So an extension
  can shadow a built-in, an unload brings it back, and a project with an
  unknown kind saves the same bytes.

### 2.2 Who owns what, and threads

| Value | Owner | Thread | Send/Sync |
| --- | --- | --- | --- |
| `Project` and its snapshots (undo) | `Document` in `Session` | main | `Send + Sync` (`Arc` everywhere); must stay so, for the render thread and bake workers |
| `Kinds<F, S>` for each family | `Session` (a `Registries` struct of fields) | main | `S` may hold `Rc` (device factories do: `device.rs:832`); the registry never crosses a thread |
| Lua functions of extension kinds | the Lua registry (`RegistryKey`), in the kernel | main | never in the model; the Rust mirror holds metadata only |
| `GraphPlan`, compiled events | made on main, owned by the engine after `Msg` | audio | `Send`; the old value comes back as garbage and the main thread drops it |
| `Doorbell` | cloned to each worker | any | `Send + Sync` |

The rule for re-entry: **no Lua runs while Rust holds a borrow of
`Session`.** The kernel calls Lua only between borrows: keys, timers,
event delivery, and now modifier jobs. A `paw.api` setter uses
`try_borrow_mut` and gives `ApiError::Busy` (a message, not a panic) if
a future path breaks the rule. Do not use `Lua::scope` for this: it
solves non-`'static` callbacks, not a second borrow.

### 2.3 Errors

- New library modules use `thiserror`: `KindError`, `ModError`,
  `GraphError`, `chain_syntax::Diagnostic`. Each variant is one case
  that a caller treats in its own way (a kind waits: show `?`; a kind is
  newer: read-only; a parameter is bad: the panel row says why).
- The kernel and `paw.api` keep `anyhow` and `LuaResult::lua`
  (`api/mod.rs:151`), which gives the chain of causes as one message.
  Do not change the 66 files of paw-core in one sweep. A module moves to
  `thiserror` when a caller must match on its error.
- Messages are lowercase, with no full stop, as `CustomError` does now.

### 2.4 Serialization

- One canonical writer: paw turns a value into `serde_json::Value` and
  writes it with sorted keys (the default `Map`, no `preserve_order`).
  The scratch test proves that a `Stored` of an unknown kind reads and
  writes the same text this way.
- Keep unknown data as `Arc<Value>` (`KindValue`), not as
  `Box<RawValue>`. The files are canonical, so a `Value` gives the same
  bytes, and a `Value` can be compared and hashed for the chain key.
- `#[serde(default, skip_serializing_if = ...)]` for every new optional
  field, as the model does now. Do not use `deny_unknown_fields` on a
  project file: a newer paw writes fields that an older paw must keep.
  Use it only on input that a person types (a command's options).
- Use `#[serde(try_from = "String")]` (or a hand `Deserialize`, as
  `KindId` needs) to check a name while reading.
- No `typetag` and no `erased-serde`. paw keeps the data of an unknown
  kind, and an open set of tags with a fallback is exactly what
  `Stored<F>` does with plain serde.

## 3. The review of m-10 and the generalizations

### 3.1 What is not idiomatic

| Item | Problem | Rule |
| --- | --- | --- |
| `pub struct KindId(Word)` for all families | one type for six families; `Word` refuses dots, but modifier kinds have them | `type-newtype-ids`, `api-newtype-safety` |
| `Kinds<S> { family: &'static str, absent: Absent, ... }` | a string and a value for what is a property of the type | `type-no-stringly` |
| `entries: BTreeMap<KindId, (Owner, S)>` | no shadow stack, but `paw.registry` has one (`registry.tl:14-17`) and the review wants a mirror | one shape on both sides |
| `trait Op<T> { fn apply(&self, params: &KindValue, ...) }` | a second trait for the same thing as `ModifierKind<C>`; one content type now | `anti-over-abstraction` |
| `trait TemplateKind` with `make` and `apply` defaults | each kind uses one verb; no Rust implementation outside the built-ins; the layered store walks folders, which is Lua's work now | `paw-code`: a trait needs two adapters now |
| `Linked<D> { def: DefId, overrides: Vec<Modifier> }` | `D` is not used (needs `PhantomData`); racks override parameter values, not a MIDI stack | associated type |
| `pub type Id = u64` (`model.rs:35`), `link: Option<String>` (`model.rs:621`) | ids mix; a link name is a string | `type-newtype-ids` |

### 3.2 The refined Rust

- **Kinds:** the shared core of part 2. `paw.kinds.define(family, name,
  spec)` puts the Lua spec in the family's `paw.registry` and mirrors
  the key into `Kinds<F, S>` through one `paw.api.kinds_put(family,
  name, owner, meta)`. `S` for a family defined in Lua is a small
  record of metadata (`version`, flags such as `local`). The Lua
  functions stay in Lua.
- **Template:** no Rust trait. Template kinds are entries of
  `Kinds<TemplateFamily, TemplateMeta>` for listing and the absent rule.
  The layered store (`paw.store`) stays in Teal: it is folder walks and
  a clash rule. The kernel gives the operations that a template kind
  needs (`graph_capture`, `graph_insert`, `track_capture`) through
  `paw.api`. One verb for each kind, as data:

  ```rust
  pub `enum` Verb { Make, Apply }            // in TemplateMeta; the picker reads it
  pub struct TemplateMeta { pub version: Version, pub verb: Verb }
  ```

  If two Rust template kinds appear later (rack and track), add a trait
  then.
- **Linked:** a trait with an associated type, because each definition
  has its own kind of override (compiled in `linked.rs`):

  ```rust
  pub trait Linkable: Clone {
      type Overrides: Clone + Default + PartialEq;
      fn resolve<'a>(def: &'a Self, overrides: &Self::Overrides) -> Cow<'a, Self>;
  }
  pub struct Linked<D: Linkable> { pub def: DefId<D>, pub overrides: D::Overrides }
  pub struct Defs<D> { defs: BTreeMap<DefId<D>, Arc<D>>, next: u64 }  // in Project
  impl<D: Linkable> Defs<D> {
      pub fn resolve<'a>(&'a self, i: &Linked<D>) -> Option<Cow<'a, D>>;
      pub fn update(&mut self, id: DefId<D>, edit: impl FnOnce(&mut D)) -> bool; // Arc::make_mut
  }
  ```

  Two users now: linked clips (`type Overrides = Vec<Modifier>`) and
  linked racks (`type Overrides = BTreeMap<(DeviceId, ParamKey), f64>`).
  The definition is stored one time. Today `links.rs` copies the shared
  runs into each clip and spreads them after each edit (`Links::spread`).
  The move to `Defs` removes the spread. `Cow` keeps the `Arc`-shared
  runs when an instance has no overrides, so the sync still compiles
  equal clips one time.
- **Project sections:** `ext/<name>/` is a map from an extension name to
  files that the core keeps byte for byte:

  ```rust
  pub struct Sections(BTreeMap<ExtName, Section>);
  pub struct Section { pub version: Version, pub files: BTreeMap<RelPath, Arc<[u8]>> }
  pub struct RelPath(Arc<str>);   // checked: relative, no `..`, no absolute part
  ```

  `RelPath` is parse, do not validate: a path from a project file that
  leaves the folder is refused when it is read, not where it is used.
- **`meta`:** `Map<String, Value>` stays (`model.rs:77`, `:141`, `:507`,
  `:608`, `:924`). A declared key becomes an entry of
  `Kinds<MetaFamily, MetaMeta>`. `meta.kind` and `meta.takes` become
  typed model fields, as the review says.
- **One parameter schema:** one Rust type, `ParamSchema`, that serializes
  to the JSON Schema words (`type`, `minimum`, `maximum`, `enum`,
  `default`, `description`) plus `unit`. Built-in kinds derive it with
  `schemars` (already in `Cargo.lock`). The chain crate reads the same
  JSON. Do not write a schema builder of paw's own.

### 3.3 Testability

The seam is the registry, not a trait: a test makes a `Kinds<F, S>`,
puts entries with owners, and checks `unload` and shadowing. No mock.

## 4. The modifier stacks

### 4.1 What is not idiomatic

| Item | Problem |
| --- | --- |
| `trait ModifierKind<C: Content>: Send + Sync` | one content (`Midi`), and the trait exists only for `LuaKind`. A `dyn` call into a Lua wrapper also needs the `Lua` state, which is `!Send`; the `Send + Sync` bound cannot hold for it. |
| `trait Content { const NAME; fn stamp() -> u64 }`, `Stack<C> { _c: PhantomData<C> }` | a type parameter in the stack, cache and evaluator for one type |
| `check(&self, params) -> Result<(), String>` | an error as a string |
| the evaluator calls Lua, "releases the session borrow before the call" | a borrow released in the middle of a `Session` method is a frequent cause of bugs; a panic on the next `borrow_mut` |
| `k_i = hash(...)` as `u64` with the std `hasher` (as `Notes::stamp`, `notes.rs:76-80`) | `DefaultHasher` has no stable algorithm between Rust releases, and a 64-bit key that collides plays the wrong notes. The bake store keeps keys on disk. |
| `Params` decoded by each built-in | correct; keep it, but decode once at the evaluator, not in the model |

### 4.2 The refined Rust (compiled in `modifier.rs`)

```rust
pub type ModKind = KindId<ModifierFamily>;

/// One step of a stack. One struct for MIDI stacks and media recipes.
pub struct Modifier {
    pub kind: ModKind,
    pub version: Version,                 // default 1
    pub on: bool,                         // default true, not written when true
    pub scope: Option<Scope>,
    pub params: Arc<Value>,               // plain JSON; the model keeps what the file said
}

/// The built-ins: a closed enum, typed params, run by `match`.
#[derive(Deserialize)]
#[serde(tag = "kind", content = "params", rename_all = "lowercase")]
pub enum Builtin { Transpose { semitones: i8 }, Velocity { add: i8 }, Quantize { grid: f64, strength: f64 } }

/// What the registry holds for each kind.
pub enum ModImpl { Builtin, Extern { version: Version, local: bool } }

/// 128 bits of BLAKE3 with a derived key: stable, so a bake on disk can use it.
pub struct ChainKey([u8; 16]);
impl ChainKey { fn source(stamp: &[u8]) -> Self; fn then(self, m: &Modifier) -> Self; }

/// The sync runs built-ins and stops at the first extension kind.
pub enum Progress { Done { key: ChainKey, result: Midi }, Needs(ExternJob) }
pub struct ExternJob { pub key: ChainKey, pub entry: Modifier, pub input: Midi, pub rest: Range<usize> }
pub enum Skipped { Waits(ModKind), Newer(ModKind), Error(ModError) }

pub fn evaluate(kinds: &Kinds<ModifierFamily, ModImpl>, stack: &[Modifier], range: Range<usize>,
                key: ChainKey, input: Midi, skipped: &mut Vec<(usize, Skipped)>) -> Progress;

/// The seam where the kernel runs an extension kind: Lua in paw, a closure in a test.
pub trait RunExtern { fn run(&mut self, job: &ExternJob) -> Result<Midi, ModError>; }

#[derive(thiserror::Error)]
pub enum ModError {
    #[error("{kind}: {reason}")] Params { kind: String, reason: String },
    #[error("{kind}: over its time limit of {limit_ms} ms")] OverLimit { kind: String, limit_ms: u32 },
    #[error("{kind}: {message}")] Failed { kind: String, message: String },
}
```

The flow of one turn:

1. The sync (in `Session`, borrowed) compiles each changed clip. For a
   stack it calls `evaluate`. Built-ins run in Rust. A waiting kind is
   skipped (`Absent::PassThrough`). At an extension kind it stores the
   `ExternJob` in a list and goes on with the other clips. The clip
   keeps its last compiled events until its job ends.
2. The sync returns. The kernel holds no borrow.
3. The kernel runs each job through `RunExtern`: it fills the note
   columns from `job.input` (a value it owns, not a borrow), calls the
   Lua `apply` under `paw.limit`, and reads the columns back. During the
   call, a `paw.api` read works (no borrow is held); a write is refused
   by the existing write guard of clip kinds, as a message.
4. The kernel calls `evaluate` again from `job.rest` with the result,
   then hands the clip's result to the sync in the same turn.

The test `a_waiting_extern_passes_through_and_lua_runs_outside_the_sync`
in the scratch crate runs this flow with a closure as the runner.

Why not the trait of the design: the `ExternJob` design has the same
reach (Lua now, WebAssembly later: both are `Extern`, both run in the
kernel), keeps `mlua` out of the model crate (needed for `paw-model` and
the browser), and removes the re-entry risk by construction. GPUI uses
the same idea: state is leased out, and effects run after the update.

Why not `Content` now: a lane stack (Q4 of the design) is not planned.
When it comes, `Midi` becomes the first of two contents, and a trait
`Content` then has two implementations. The saved `Modifier` struct does
not change, because it holds no content type.

### 4.3 Cache and keys

- The results cache keys by `ChainKey` and holds `Arc<Midi>`. It forgets
  on a sweep, as `Compiled::sweep` does.
- `ChainKey::then` hashes the kind, the version, the canonical text of
  the params and the scope. The params are a `Value` with sorted keys,
  so one value has one text.
- `Notes::stamp` stays a `u64` for the in-memory cache. The source key
  of a chain is `ChainKey::source(&stamp_bytes)` plus the bytes of what
  the kinds read. Move `Notes::stamp` to BLAKE3 only when a key goes to
  disk.
- A local kind keys each run of 256 notes by `(run pointer, ChainKey)`.
  Keep the pointer key in memory only.

### 4.4 Serde of a stack

- `track.json`: `"modifiers": [ {kind, version, on, scope, params} ]`.
  The old `overrides` field reads with `#[serde(default)]` and the
  loader folds it into two entries. No compatibility after that, as the
  design says.
- The model never decodes `params` into `Builtin`. A bad parameter of a
  built-in is a `Skipped::Error` at evaluation, and the file keeps the
  value. So a project with a bad value opens.

## 5. The review of the event loop

### 5.1 What is not idiomatic

| Item | Problem |
| --- | --- |
| `trait Upkeep { const KIND: WakeKind; fn poll(&mut self, cx: &mut UpkeepCx<'_>); ... }` | an associated `const` makes the trait not dyn-compatible; `UpkeepCx` that lends "events out, engine link" from `Session` while the parts are fields of `Session` fails the borrow checker (two `&mut` of one struct) |
| `Agenda { in_flight: usize, next_due: Option<Duration> }` | schedule time as a plain `Duration`; nothing stops a budget time going in |
| `Arc<dyn Clock>` with `fn manual(&self) -> Option<&ManualClock>` (`clock.rs:16-24`) | a downcast hook in a trait of two implementations; a closed set is an `enum` |
| `KernelMsg::Wake(kind)` sent from each worker | `request_callback` (`clap/host.rs:128`) runs on any thread, also the audio thread; `mpsc::Sender::send` can allocate |
| "`inotify`: a small thread blocks on its file descriptor" | a thread to turn a file descriptor into a message; a poller can wait on the descriptor itself |
| `tools/clocklint` (a grep) | Clippy's `disallowed_methods` does this, with a reason on each allowed site |
| the timer list `Vec<Timer>` with a linear scan (`api/timers.rs:21-40`) | the design proposes a `BinaryHeap`; correct, keep it |
| `StartTest` in `DeviceFactory::start`, `KIND_TESTS` global `Mutex` (STEP branch, not on main) | test knobs in a trait signature and a global; the design's S6 fixes them |

### 5.2 The refined Rust (compiled in `sched.rs`)

```rust
pub struct ScheduleTime(Duration);                       // "when"
pub enum Clock { Wall { started: Instant }, Manual { nanos: AtomicU64 } }
impl Clock {
    pub fn now(&self) -> ScheduleTime;
    pub(crate) fn advance_to(&self, at: ScheduleTime) -> Result<(), NotManual>;
}

#[must_use]
pub struct Agenda { pub ready: bool, pub in_flight: u32, pub next_due: Option<ScheduleTime> }
impl Agenda { pub fn quiet(&self) -> bool { !self.ready && self.in_flight == 0 } }
impl BitOr for Agenda { /* the union of two parts */ }

bitflags! { pub struct Woken: u32 { const BAKES; const HASHES; const LOADS; const RENDER;
                                    const FILES; const DEVICES; const TAKES; const PLUGINS; } }

/// One for each process. The payload of a message still goes on the mpsc channel.
pub struct Doorbell { woken: Arc<AtomicU32>, bell: Arc<mio::Waker> }
impl Doorbell {
    pub fn ring(&self, kind: Woken);   // worker threads: fetch_or; the first bit rings the eventfd
    pub fn mark(&self, kind: Woken);   // the audio thread: fetch_or only, no system call
    pub fn take(&self) -> Woken;       // the start of each turn: swap(0)
}

/// Dyn-compatible. Returns outcomes as data; the session applies them after the polls.
pub trait Upkeep {
    fn kind(&self) -> Woken;
    fn poll(&mut self, now: ScheduleTime, out: &mut Vec<Outcome>);
    fn agenda(&self, now: ScheduleTime) -> Agenda;
}
pub struct Upkeeps { pub bakes: Bakes, pub hashes: Hashes, pub loads: Loads, pub render: Render,
                     pub files: FileWatch, pub devices: DeviceWatch, pub takes: Takes, pub plugins: Plugins }
impl Upkeeps {
    fn each(&mut self) -> [&mut dyn Upkeep; 8];   // concrete fields, borrowed as trait objects
    pub fn turn(&mut self, now: ScheduleTime, woken: Woken, out: &mut Vec<Outcome>) -> Agenda;
}
```

Decisions and reasons:

- **Outcomes, not a context of borrows.** Each part polls its own state
  and pushes `Outcome` values (`BakeDone`, `FileChanged`,
  `PluginStopped`). `Session` then applies them with full access. This
  is the shape `scan_devices` already has: it fills a `DeviceScan` and
  `apply_device_scan` applies it (`session/devices.rs:595-597`). It
  splits the borrow without `unsafe` or `RefCell`, and a test checks a
  part by its outcomes.
- **The trait stays.** Eight implementations pass the rule of
  `paw-code`. Static dispatch through an array of `&mut dyn Upkeep` is
  enough; the call costs nothing next to the work.
- **The doorbell.** The main loop waits in `mio::Poll::poll` with the
  timeout `min(timer due, agenda.next_due)`. The doorbell's `Waker` is
  one token. The `inotify` descriptor and the ALSA sequencer descriptor
  are tokens of the same poll, so the "small thread" for `inotify` goes.
  A sender of a `KernelMsg` (the terminal, RPC, a helper) sends on the
  channel and then calls `ring`. `mio` is already in `Cargo.lock`
  through `tokio`. `mio::Waker` is not on WASI: the browser build
  (`target_vendor = "browserpod"`) keeps today's `recv_timeout` behind a
  `#[cfg]` in one module.
- **The audio thread never rings.** CLAP's `request_callback` calls
  `mark(Woken::PLUGINS)`, which is one atomic `fetch_or`. The main loop
  sees it at the next turn. While a plugin controller is live, the
  safety tick of the design (250 ms, or 16 ms for a controller that asks
  for idle) makes sure that the bit is seen. This keeps the rule "no
  system call on the audio thread". The other flags in `HostFlags`
  (`restart`, `callback`) can become bits of the same `Woken`.
- **`ScheduleTime` and Clippy.** `Upkeep::poll` gets `now:
  ScheduleTime`; a part holds no clock. In
  `crates/paw-core/clippy.toml`: `disallowed-methods = [{ path =
  "std::time::Instant::now", reason = "a 'when' reads ScheduleTime;
  only a budget reads Instant" }]`. Each budget site gets
  `#[expect(clippy::disallowed_methods, reason = "...")]`. This replaces
  `tools/clocklint`, and `cargo clippy` already runs in the flake check.
- **The clock `enum`.** `Arc<Clock>` replaces `Arc<dyn Clock>`. The
  kernel is the one owner. `Session` gets `now` from the turn, so the
  five `clock: Arc<dyn Clock>` fields and their `WallClock` defaults go
  (the design's S2).
- **One turn function.** `Kernel::turn(&mut self, now: ScheduleTime) ->
  Agenda`. `run`, `api.step`, `api.wait`, `api.settle` call it. The
  `request()` barrier calls `close_turn()` and `agenda()`, the last two
  steps, as named methods, not a flag.
- **Fault injection.** A `FaultPlan` value that the sandbox registry
  takes at construction (a builder option), set from `--test-faults`.
  No parameter in `DeviceFactory::start`, no global `Mutex`, no
  environment variable.
- **An honest stepped backend.** `enum Backend { Cpal, Null, Step }` in
  `StreamInfo`. `api.wait_blocks` on a backend that is not `Step` gives
  an error, not 0.

### 5.3 Testability

- I1 (one turn): a `Kernel` with a recording frontend and
  `Clock::manual()`. No trait is needed for the clock.
- I3 and I4: a part with a fake worker (a thread that ends and calls
  `ring`); the test calls `Doorbell::take` and `Upkeeps::turn`. No
  sleep: the test waits on the `Poll` with no timeout.
- I2: Clippy, not a test.

## 6. The devices graph

### 6.1 What is not idiomatic

| Item | Problem |
| --- | --- |
| `Split { id: Id, kind: SplitKind, ..., meta: Map<String, Value> }`, `Node::Device(Id)` | ids as the shared alias; `meta` on a split again |
| `Link { target: (Id, String), ... }` | a tuple of an alias and a string for a parameter |
| `SplitKind` as an `enum` in the model (implied) | the m-10 review asks for open names; an `enum` in the model freezes the meaning at load |
| `GraphPlan { bufs: Box<[[Vec<f32>; 2]]>, ... }` | a `Vec` for each channel: many allocations, and a `Vec` that the audio thread could grow by mistake |
| `Range<u8>`, `buf: u8`, `events: u8` | raw indices of three kinds that mix |
| the plan's checks (no tap later than its listener) in prose | the audio thread must trust a plan; only the compiler may make one |
| the chain parser on `chumsky` | the formatter must keep comments, and the language server needs a lossless tree with spans after errors |

### 6.2 The refined Rust (compiled in `graph.rs`)

```rust
pub struct DeviceId(u64); pub struct NodeId(u64); pub struct TrackId(u64);
pub struct ParamKey(Arc<str>);             // a stable parameter name of the device's schema
pub type SplitKind = KindId<SplitFamily>;  // open: built-ins are entries of owner `paw`

pub struct Split { pub id: NodeId, pub kind: SplitKind,
                   pub values: serde_json::Map<String, Value>,   // the kind's schema checks them
                   pub branches: Vec<Branch> }
pub struct Branch { pub id: NodeId, pub name: String, pub gain_db: f64, pub nodes: Vec<Node> }
pub enum Node { Device(DeviceId), Split(Split) }
pub struct Link { pub source: NodeId, pub device: DeviceId, pub param: ParamKey, pub depth: f64 }

#[derive(thiserror::Error)]
pub enum GraphError { Twice(DeviceId), Unknown(DeviceId), AbsentKind { node: NodeId, kind: String } }

/// Only `compile` makes one, so the audio thread trusts each index.
pub struct GraphPlan { samples: Box<[f32]>, max_block: usize, ops: Box<[Op]> }
pub struct Buf(u8);
pub enum Op { Run { device: DeviceSlot, buf: Buf }, Copy { from: Buf, to: Buf },
              Split { splitter: DeviceSlot, from: Buf, to: Range<u8> },
              Merge { from: Range<u8>, to: Buf }, Delay { buf: Buf, frames: u16 } }
pub enum SplitImpl { Builtin, Device { factory: Arc<str> } }   // the resolved registry entry
pub fn compile(root: &Split, slots: &BTreeMap<DeviceId, DeviceSlot>,
               kinds: &Kinds<SplitFamily, SplitImpl>, max_block: usize)
    -> Result<Box<GraphPlan>, GraphError>;
```

- **One allocation for the buffers.** `samples` holds `count * 2 *
  max_block` floats; `channels(buf)` gives two `&mut [f32]` by
  `split_at_mut`. It is one allocation on the main thread, freed on the
  main thread when the plan comes back as garbage.
- **`GraphPlan` fields are private** and its only constructor is
  `compile`. This is the `typestate` rule without a type parameter: a
  checked plan is the only plan. A compile-time check in the scratch
  crate asserts `Box<GraphPlan>: Send`.
- **Absent split kinds.** The family's rule is `PassThrough`: the
  compiler compiles an absent split as its first branch in series, and
  the kernel shows the diagnostic. The file keeps the split as written.
- **`Graph::validate` returns `Result<(), GraphError>`**, and a device
  that the graph does not name goes at the end of the root, as the
  design says. Keep the flat `Track.devices` list; the graph holds
  `DeviceId`s.
- **Linked racks** use `Linked<Rack>` with `type Overrides =
  BTreeMap<(DeviceId, ParamKey), f64>` (part 3.2).
- **`meta` on a split:** no. A split kind's own values are `values`,
  checked by its schema. An extension's data on a node is a declared
  `MetaFamily` key, if a use comes.

### 6.3 The chain language crate

- **Name and place:** `crates/chain-syntax` (no `paw-` prefix, as the
  owner wants a crate with no dependency on paw). Its dependencies:
  `rowan`, `serde`, `serde_json`, `thiserror`, and a lexer crate if one
  helps (`logos`). No `mlua`, no `paw-*`.
- **A lossless tree.** `rowan` gives a green and red tree with every
  byte, comments and whitespace included. The formatter, the language
  server (hover, code actions, ranges) and "keep a hand-edited comment"
  need that. rust-analyzer, and the TOML language server `taplo`, work
  so. The parser is hand-written recursive descent with recovery at
  each line: the language is line-based with indents, so recovery is
  "skip to the next line at this indent". `chumsky` builds an AST and
  is a good choice for a language with no need for trivia; it is not
  the best choice here.
- **The API, in three layers:**

  ```rust
  pub fn parse(text: &str) -> Parse;                          // never fails; errors are in it
  pub struct Parse { green: rowan::GreenNode, errors: Vec<Diagnostic> }
  pub fn lower(parse: &Parse, schemas: &HostSchema) -> (ChainGraph, Vec<Diagnostic>);
  pub fn format(parse: &Parse, schemas: &HostSchema) -> String;
  pub struct Diagnostic { pub range: TextRange, pub code: Code, pub severity: Severity,
                          pub message: String, pub fix: Option<Fix> }
  pub struct HostSchema { pub version: Version, pub kinds: BTreeMap<String, KindSchema> } // JSON
  ```

  `ChainGraph` is the crate's own graph with string kind names; paw
  maps it to its model (`KindId<SplitFamily>`, `DeviceId`) in
  `paw-core`. The crate never names a paw type.
- **Lints as data.** `paw.chain.lint.add(code, fn)` gets the lowered
  graph through `paw.api`, as the design says. In Rust, a lint is a
  `fn(&ChainGraph, &HostSchema, &mut Vec<Diagnostic>)` in a table, not
  a trait object.
- **The language server:** `chain-lsp` with `lsp-server` and
  `lsp-types` (synchronous, the crates of rust-analyzer). No `tokio` is
  needed for stdio. `tower-lsp` is `async` and larger.
- **Tests:** `proptest` for print then parse, `insta` for golden
  diagnostics, a fuzz target in `paw-fuzz`.

## 7. Where the designs disagree, and the one answer

| Topic | m-10 review | Modifier stacks | Event loop | Devices graph | One answer |
| --- | --- | --- | --- | --- | --- |
| Kind id | `KindId(Word)` for all | `KindId`, dotted names | `WakeKind` (not a kind) | open split names (via m-10) | `KindId<F: Family>`, dot-joined words; `Woken` stays bit flags |
| Absent rule of modifiers | `Absent::Keep` (a kept bake) | pass through; no kept result (owner, Q7) | | | `ModifierFamily::ABSENT = PassThrough` |
| The saved step | `Modifier { op, version, enabled, params }` | `Entry { kind, version, on, scope, params }` | | | `Modifier { kind, version, on, scope, params }` |
| The op trait | `trait Op<T>` | `trait ModifierKind<C>` + `enum Builtin` | | | `enum Builtin` + `ModImpl::Extern` run by the kernel (`RunExtern`); no content trait until a second content |
| Linked overrides | `Vec<Modifier>` | the stack on each clip | | overrides of parameters | `Linked<D: Linkable>` with `D::Overrides` |
| Versions | `version: u32` | `version: u32` | | host schema version | `Version(NonZeroU32)`, default 1, not written when 1 |
| Registry shape | `Kinds<S>` map | "one registry" | | split kinds registry | `Kinds<F, S>` with a shadow stack and the verbs of `paw.registry` |
| Time | | `ctx.beats_to_seconds` | `Duration`, `Arc<dyn Clock>` | | `ScheduleTime`, `enum Clock` |
| Errors | `Result<T>` (anyhow) | `String`, `ModError` | | diagnostics | `thiserror` `enums` at the new boundaries; `anyhow` stays in the kernel |
| Hash of content | | `u64` chain | | `rev` of the chain text | BLAKE3 for keys that can reach disk (`ChainKey`, `rev`); `u64` only in memory |
| Parameter schema | one `ParamSchema` | `ParamSpec` in Lua | | JSON host schema | one `ParamSchema` with JSON Schema words plus `unit`; `schemars` for built-ins; the host schema embeds it |

## 8. Crates

Rows to add to `paw-crates.md`:

| Job | Use | Not | Reason |
| --- | --- | --- | --- |
| The main loop's wait on a channel, file descriptors and a cross-thread wake | `mio` (`Poll`, `Waker`; already in `Cargo.lock` through `tokio`) | a thread for each descriptor; `recv_timeout` plus a 16 ms poll | one wait on all sources, as `libuv`; not on WASI, so the browser build keeps `recv_timeout` |
| A lossless syntax tree for a language with a formatter and a language server | `rowan` | an AST with no trivia; `chumsky` for this job | comments and exact ranges after errors |
| A language server over stdio | `lsp-server` and `lsp-types` | `tower-lsp` | synchronous, small |
| JSON Schema of Rust types | `schemars` (in `Cargo.lock`) | a schema writer of paw's own | one schema for the API, MCP, the host schema |
| Seeded random streams in modifiers | `rand_pcg` (PCG32) with `rand_core` | `rand::thread_rng`, own PCG | the modifier design asks for named streams of one seed |
| Lexer (optional) | `logos` | a hand loop over chars, when tokens are many | fast and checked; skip it if the line lexer stays small |

Rows to change or keep:

- **Content keys:** `blake3` already. Extend the row: "and every key
  that names a result on disk or across runs (`ChainKey`, `rev`); not
  `DefaultHasher`".
- **Errors of a library:** `thiserror`. Add: "paw-core's kernel and
  `paw.api` may use `anyhow`, because they turn every error into a
  message for Lua; a module whose callers match on the error uses
  `thiserror`".
- **Bit flags:** add `Woken` and the CLAP `HostFlags` as users.

Crates to avoid here, with the reason:

| Crate | Why not |
| --- | --- |
| `typetag`, `erased-serde` | no fallback for an unknown tag; paw keeps unknown kinds byte for byte |
| `inventory`, `linkme` | registration at link time is static; paw's kinds come and go with extensions at run time, and the registry has owners |
| `slotmap` | its keys are not stable ids in files |
| `salsa` | paw's derived data is in Lua (`derived.tl`), and the Rust caches are few and keyed by content; a framework adds a query database for two caches |
| `actix`, `ractor` | the event-loop review: threads and channels for eight workers are enough |
| `basedrop`, `arc-swap` for the plan | the plan already crosses by `rtrb` and comes back as garbage; a second way to free on the audio thread adds risk |
| `bevy_reflect` | a reflection system for the model is much larger than the job; serde and `schemars` cover it |

## 9. What not to do in Rust here

- Do not make a `Registry<T>` trait over device factories, clip kinds
  and split kinds. Share `Kinds<F, S>` (a struct) where the thread and
  the lifetime are the same. Device factories (`Rc<dyn DeviceFactory>`,
  `device.rs:832`) keep their own `Registry` and add an owner.
- Do not put `mlua::Function` or `RegistryKey` in a model type or in
  `Kinds`. The model must build for wasm32 with no Lua.
- Do not call Lua from a `Session` method. Give the kernel a job.
- Do not use `Rc<RefCell<..>>` webs for the graph or the stacks. The
  model is a tree of values in `Arc`s with ids; an undo snapshot is a
  clone of the root.
- Do not freeze kind names into a model `enum` (`enum SplitKind { Band,
  .., Ext(String) }`). Store the name; resolve at compile.
- Do not use `#[serde(untagged)]` to tell a built-in from an extension
  entry. The error messages of `untagged` are poor ("did not match any
  variant"). Decode the name first, then the params.
- Do not use `#[serde(flatten)]` on a hot path or with
  `deny_unknown_fields`: flatten buffers the map and the two do not
  work together.
- Do not use `DefaultHasher` for a key that is saved, and do not trust a
  64-bit hash to decide which notes play.
- Do not add a generic `Content` or `Op<T>` parameter for a second
  content that is not planned.
- Do not send on a channel, lock, allocate or make a system call from
  the audio thread to wake the kernel. Set a bit.
- Do not use `Box<dyn Any>` for kind data. It is `Arc<Value>`.
- Do not move `Shared` into `Lua::set_app_data` to "fix" borrows:
  `app_data_mut` panics on a conflicting borrow as `RefCell` does.
- Do not add `async` to the main loop (the event-loop review, 3.8).

## 10. No new type depends on a track

The owner (2026-11-23, through the coordinator): `Track` as a type of
the first rank is a fault from older DAWs. paw goes to a generic
container: a named container in a tree that holds typed streams (MIDI,
audio made from MIDI, notes for performers, video, `keyframes`,
automation, kinds of extensions) and producers that make streams from
streams. The design is in `containers.md` (in progress). Its interim
verdict for TASK-279 agrees with this part: the graph is a value that
does not know its owner.

### 10.1 Where the refined types assume a track

| Type | Assumption of a track | Change |
| --- | --- | --- |
| `Graph`, `Split`, `Branch`, `Node` (part 6) | none in the scratch code; the devices design puts `graph` on `Track` (its 4.3) and `Msg::SetGraph { track, plan }` | the graph module holds no `TrackId` and reads no `Track`. Edits are `fn(&Graph, ..) -> Result<Graph, GraphError>`. The session finds the owner and makes the undo step. |
| `compile(root, slots, kinds, max_block)` | none; the engine message names a `TrackSlot` | the engine message names the processor that runs the plan (a `ProcessorSlot`, which a track has today) |
| `Link { source, device, param, depth }` | none | stays |
| `Linked<D: Linkable>` (part 3.2) | none; `Defs<D>` sits in `Project` | `Defs<D>` sits with the container tree, keyed by `DefId<D>` |
| `Modifier`, `evaluate` (part 4) | the input is `Midi`, the content of one MIDI clip | the input is a stream value; `Midi` is the first stream kind (see 10.2) |
| `ExternJob` | none | stays |
| `TemplateMeta`, `Verb` (part 3.2) | `track_capture` named as an API | `capture(owner)` and `make(at: Owner)`, where the owner is a container handle |
| `Upkeep`, `Agenda`, `Doorbell` (part 5) | none | stay |
| `TrackId`, `TrackFamily` (part 2) | they name a track | keep them only while `Track` exists; the container design gives `ContainerId` and may make `TrackFamily` a family of container kinds |
| `chain-syntax` | the header `track "Gtr bus" rev=...` in the grammar (devices design, 10.2) | the header names the subject by a free word (`chain 1` then `for "Gtr bus"`), and the host maps it; the crate keeps no word "track" |

### 10.2 How the types read with a generic container

The types of the Rust refinement take an owner handle or a stream kind, so a
container tree changes their callers and not the types:

```rust
/// A place that owns data: a track today, a container of the tree later.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum OwnerRef { Track(TrackId) }        // later: Container(ContainerId); a clip; a nest

/// A family of stream kinds: MIDI, audio, video, keyframes, automation, extension kinds.
pub enum StreamFamily {}                    // a Family of part 2, Absent::Keep

/// Where a modifier stack sits: a stream of one owner.
pub struct StreamRef { pub owner: OwnerRef, pub stream: KindId<StreamFamily> }

/// The graph does not know its owner; the session keeps the map.
pub struct Graphs(BTreeMap<OwnerRef, Arc<Graph>>);
```

- **Modifier** is "a pure function from a stream value to a stream
  value of the same kind". A producer of the container design ("MIDI
  `keyframes` into a video") is a function from one stream kind to
  another. Keep the two apart in Rust: `Modifier` keeps the type of its
  input (so a stack chains), and a producer is a node with typed ports.
  The `Content` trait of the modifier design comes back here, as the
  trait of a stream value, when the second stream kind (`keyframes` or
  lanes) has a stack. Until then, `Midi` is the only value.
- **The devices graph** is a producer graph for the audio stream. With
  typed ports it would also carry video or control streams; the
  container review decides that. The plan (`GraphPlan`) stays the audio
  part.
- **Linked** links any definition that a container holds; `DefId<D>`
  does not name its owner.
- **Template** captures a `subtree` of containers; the store does not
  change.

No bundle of the Rust refinement must wait for the container design: each type
above already takes the owner from its caller.

## 11. Order of the work

The refinement changes no bundle order. It adds three small items:

1. **Before B2 (Kinds):** the shared core of part 2, with
   `ClipKindId` and `RESERVED` replaced. The id `newtypes` (`TrackId`,
   `ClipId`, `DeviceId`) go in TASK-98's lane, one type for each commit,
   because they touch many files.
2. **In S1 of the modifier plan:** `Modifier`, `Builtin`, `ModImpl`,
   `ChainKey`, `evaluate`. `RunExtern` and the jobs go in S3.
3. **In S2 and S3 of the event loop:** `ScheduleTime`, `enum Clock`, the
   Clippy rule, `Upkeep` with outcomes, `Doorbell` with `mio`.

## 11. Questions for the owner

| # | Question | Recommendation |
| --- | --- | --- |
| R1 | Kind names become dot-joined words for every family, and the reserved list goes: a bare word is free to any owner, and the registry decides a clash by shadowing. | Yes. One rule, and the built-ins become plain entries. |
| R2 | Ids of the model become `newtypes` (`TrackId`, `ClipId`, `DeviceId`, `NodeId`). The files do not change (a `u64`). | Yes, in steps, with TASK-98. |
| R3 | The main loop waits in `mio::Poll` (`eventfd`), and the `inotify` thread goes. The browser build keeps `recv_timeout`. | Yes, in S3 of the event loop. |
| R4 | The chain crate uses `rowan` and a hand-written parser, not `chumsky`. | Yes: the formatter keeps comments, and the language server needs a lossless tree. |
