# Modifier stacks: a generic Modifier, and the MIDI stack as its first user (TASK-75)

Superseded where it differs by [architecture-plan.md](architecture-plan.md) (2026-11-23).

Author: design agent for TASK-75, 2026-11-23. No tracked file changed. Nothing was built.
Status: a proposal. The owner answers the questions for the owner before anyone builds it.
Base: `main` at 7228146b.

Read with: `backlog/docs/designs/media.md` (recipes, modifiers, Apply, kept bakes; owner
decisions at its end), `clip-kinds.md` (a kind's data is a plain value, CK-A6),
`devices-graph.md` 4.6 (modulators) and 9.5 (templates), `perform.md` (provenance),
`derived.md` (stamps and nodes), TASK-85.1, TASK-85.2, TASK-176 (links and overrides),
TASK-86 (drivers), TASK-298 (templates in the core).

---

## Rust refinement (2026-11-23)

[The Rust refinement](rust-architecture.md) changes the Rust shapes of this design. What changed:

- No `ModifierKind<C>` trait and no `Content` trait now. The built-ins are `enum Builtin` with typed params; the registry holds `ModImpl { Builtin, Extern }`.
- No Lua call from the sync. `evaluate` stops at an extension kind and gives an `ExternJob`; the kernel runs it with no session borrow held (`RunExtern`), then evaluation goes on from the job.
- The saved step is `Modifier { kind, version, on, scope, params }`, one struct with the media design.
- `ChainKey` is 128 bits of BLAKE3, not a `u64` of the standard `hasher`.
- `check` gives `ModError` (`thiserror`), not `String`.
- The stack takes a stream of an owner, not a clip of a track (part 10 of the refinement).

## 0. The short version

- **A modifier is a pure function over saved content.** It takes the content of one place
  (the notes and controller moves of a MIDI clip), its own parameters and a small read-only
  context, and gives new content of the same type. It has a stable kind id and a version. The
  same input, parameters and version give the same output, bit for bit. So paw keys each
  output by a hash and keeps it in a cache.
- **A stack is an ordered list of modifiers on one place.** The stored content stays the
  truth. The stack is a recipe that paw evaluates when the content or the stack changes. The
  engine plays the result. `:clip.apply 3` writes the result after modifier 3 into the notes
  and removes modifiers 1 to 3, in one undo step (Blender's Apply).
- **Generic in the core, in Rust.** A `ModifierKind<C>` trait, where `C` is the type of content
  (MIDI content first). The built-in kinds are one Rust `enum`. An extension kind is a Teal
  function that the core calls through the same trait (`paw.modifier.register`). Each kind
  has its own parameter schema and its own encoding of the parameters, with a version and a
  migration. The generic part is small on purpose: the saved entry, the registry, the chain
  of keys, the cache, Apply, templates, and the panel rows. The part "Where the generic trait costs more than it
  gives" tells where it costs more than it gives.
- **Where a stack sits.** On a MIDI clip, and so on each linked copy (a copy is a clip; the
  notes of a link are shared, the stack is not). A modifier can have a scope: a beat range of
  the clip. A track stack is possible later and comes after the clip stack. A project-wide
  range is a command that puts one scoped modifier on each clip, not a stack of its own.
- **`Overrides` becomes two built-in modifiers**, `transpose` and `velocity`. Old projects open:
  the loader turns the `overrides` field into the two entries. The piano roll keeps the
  behavior of TASK-85.2 through a general rule: the roll shows the result of the leading
  modifiers that can be reversed (see "Editing through a reversible prefix").
- **MIDI stays the truth.** The stored notes are the data. A modifier of an extension that is
  not loaded stays in the stack, unchanged to the byte, and waits. The stack runs without it,
  so the project opens and plays the notes, and the panel, `K` and the clip label say
  `waits for musicops`.
- **What is not a modifier:** a modulator of the devices graph (per block, on the audio
  thread, over parameter values), a driver (TASK-86, an expression over time on the main
  thread), a note-FX device on a track (live, it also hears the keyboard), an audio render op
  of the media design (a bake in a helper process), and the tempo map. The part "What is not a
  modifier" tells how they relate.
- **Templates.** A stack is a template kind of the TASK-298 store: save it under a name, put
  it on other clips, bundled, user or project.
- **The user sees** a stack panel (`<Space>cs`, the same rows and keys as the inspector of the
  device graph), the stack as text (`:clip.recipe`, as the media design approved), ghost notes
  of the result in the piano roll (`\m` switches what the roll shows), a short stack in the
  clip label (`riff ≡ +3 q16 hum`), and `K`.
- **Fast.** Built-in kinds run in Rust, extension kinds get columns of numbers (not a table for
  each note). Keys chain as a hash chain, so a change of modifier 3 runs only 3 and the ones
  after it. Copies with the same notes and stack share one compiled list of events, as today.

Words:

- A **kind** is a type of modifier (`quantize`, `musicops.arp`).
- A **modifier** (or an **entry**) is one kind with its parameters in a stack.
- A **stack** is the ordered list on one place.
- The **source** is the stored content. The **result** is what the stack gives. The engine
  plays the result.
- A kind is **reversible** when each output note comes from one input note and paw can map an
  edit of the output back to the input.
- **Apply** writes a result into the source.
- A modifier **waits** when no loaded extension defines its kind.

---

## 1. Research: how other programs do it

| Program | Where it sits | Non-destructive how | Bake | What paw takes |
| --- | --- | --- | --- | --- |
| Blender modifier stack | On the object, not on the mesh data: two objects that share one mesh have their own stacks. | Evaluated on each change, top to bottom; toggles for the 3D view, the render and edit mode. | Apply (Ctrl-A). Apply of a modifier that is not first warns that the result can differ. A mesh with more than one user must be made single-user first. | The stack on the instance (the clip), not on the shared data (the link). Apply of a prefix. Refuse Apply on shared data. |
| Logic region parameters | On a MIDI region: quantize, Q-swing, transpose, velocity offset, dynamics, gate time, delay. | Applied at playback; the editors show the stored notes. | Normalize Region Parameters writes them into the notes. | The first set of built-in kinds. The name of the bake (Apply) and that it is one command. |
| Cubase MIDI Modifiers | On the track (Inspector), and as a MIDI insert: transpose, velocity shift and compression, length compression, random, range. | Real time. | Freeze MIDI Modifiers writes them into the parts and resets them. | Range and random as kinds. A track stack is a real use (later). |
| Cubase and Logic MIDI inserts and MIDI FX | On the track, in front of the instrument (an arpeggiator, chords, scripts). | Live, also on input from the keyboard. | Render or "MIDI insert to part". | These are devices, not modifiers: paw has them as note-FX devices (luafx `chords`). |
| Bitwig Note FX and operators | Note FX: devices on the track. Operators (chance, repeats, occurrence) are fields of each note in the clip. | Note FX live. Operators are read at playback. | Slice at repeats, bounce. | Per-note randomness belongs to a seeded modifier, not to a new field of each note. |
| Ableton Live 12 MIDI Tools | In the clip view: transformations and generators. | The settings act on the notes of the clip while the tool is open; the result is the notes. | No bake step: the result is already the notes. | The audition with `Enter` or `Esc` (paw has it: `paw.audition.try`), for the moment of choice. Not the model: paw keeps the recipe. |
| REAPER take FX and JSFX MIDI | An FX chain on one take of an item. A JSFX can change MIDI. | Live, on that take only. | "Apply track/take FX to items as new take (MIDI output)". | A stack on the take (the clip) is a known need. Bake to a new take is an option for a later Apply ("apply as a new take"). |
| Reaticulate | Articulations are program changes in the MIDI item; a JSFX on the track turns them into keyswitches for the instrument. | Live, on the track. | None needed. | The articulation map stays at the output of the track (paw's articulations extension does this). It depends on the instrument, not on the music, so it is not a clip modifier. |

The sources are at the end.

---

## 2. What paw has today

| Part | Where | What it gives the design |
| --- | --- | --- |
| `Overrides { transpose, velocity }` | `crates/paw-core/src/model/overrides.rs` | A fixed stack of two kinds. The sync applies it when it compiles events, and it is in the cache key. MIDI export applies it (`runtime/lua/paw/midifile.tl` near line 1236). |
| Compiled events shared by copies | `crates/paw-core/src/sync/clips.rs` `Source`, `Compiled`, `Entry` | The key is the run pointers of the notes, the length, the loop and the overrides. Copies at many places share one list. |
| Runs of 256 notes in `Arc`s, `Notes::stamp` | `crates/paw-core/src/model/notes.rs` | A content stamp of the notes, and runs that copies share. A per-run cache for local kinds is possible. |
| Linked clips | `model/links.rs`, `linked/<link>.midi2` | The notes are shared. Each clip of a link keeps its own fields, so the stack goes on the clip. |
| The shifted handle | `Clip:shifted` in `runtime/lua/paw/objects.tl` | The roll shows played pitches and writes through the reverse of the transpose (TASK-85.2, TASK-176). The reversible prefix makes this general. |
| Pure transforms | `runtime/lua/paw/notes.tl` (`paw.notes.quantize`) | One quantize for the key, the gesture, Ex and musicops (TASK-128). The built-in `quantize` kind must not be a second quantize (see "One quantize"). |
| musicops operators | `extensions/musicops` | Humanize (with a seed), strum, arpeggiate, crescendo, transpose in the key. Destructive operators today. They become the first extension kinds. |
| Provenance in the perform design | `perform.md` | A different model: it writes MIDI and keeps what it wrote. The part on `perform` tells how the two live together. |
| pattern | `extensions/pattern` | A generator: text in meta, the notes are its output. Not a modifier (no input). |
| Custom clip sound | `model/custom.rs` `Sound`, `clips/<clip>.sound.midi2` | The model of a saved output that plays without the extension. The part "Why no kept result" tells why the stack does not copy it. |
| Bake keys | `crates/paw-core/src/bake/` (media design, partly built) | The chained keys and the vocabulary (Apply, kept). |
| Derived nodes | `paw.derived`, `derived.md` | Views of the result (ghosts, labels) are derived values with a stamp. |
| Audition | `paw.audition.try` | A modifier that you choose in the picker plays at once; `Enter` keeps it, `Esc` takes it back. |
| A measure of cost | `bench/RESULTS.md`, 2026-11-23 | `:%quantize` over 6 400 notes costs about 110 ms a key. Most of it is the read of the notes into a Lua table for each note, and the redraw. Extension kinds must not get a table for each note. |

---

## 3. The generic modifier

### 3.1 The content

A kind says which content it takes. The content of the input and of the output is the same
type, so a stack is a chain.

```rust
/// What a stack works on. One implementation for each place that has a stack.
pub trait Content: Clone + Send + Sync + 'static {
    /// A hash of the content, the same for the same content: the first key of a chain.
    fn stamp(&self) -> u64;
    /// The name in the saved entry and in the registry: "midi", later "lane".
    const NAME: &'static str;
}

/// The content of a MIDI clip as a stack sees it: the notes and the controller moves.
/// It holds the runs of `Notes`, so that a kind that changes nothing gives the same runs.
pub struct Midi { pub notes: Notes, pub controls: Arc<[Control]> }
```

- **MIDI content (notes and controller moves): yes, the first user.** Notes and controllers are
  one content, because a kind often moves both (a transpose moves the bend of one key, a
  quantize moves a CC with its note).
- **Automation lanes: fits the trait, not in the first plan.** `Lane { points }` is a content.
  Kinds such as `scale`, `offset`, `smooth`, `snap to grid` are pure over points. But a lane
  already has three ways to change a value over time: points, modulators (devices graph) and
  drivers (TASK-86). A fourth way needs a use that the other three do not cover. Recommendation:
  keep the type parameter so a lane stack fits, and build it only on a real request (Q4).
- **The parameters of an audio clip (gain, fades, stretch): no.** They are fields with one value,
  not a list of items. A stack over one number is a driver or automation.
- **The structure ops of an audio clip (media design: cut, slice, shuffle over an edit list):
  they fit.** Their `expand` is pure over an `EditList`. The media design's `Modifier` record and
  this entry are the same record (see "The saved entry"). The render ops (pencil, stretch, video encode) do
  not fit: they bake in a pool or a helper process, they are not fast, and their output is a
  file. They stay bakes.
- **The tempo map: no.** It changes the time of every track. A stack on it changes the place of
  each clip in seconds at each edit, and the view of each track. The tempo map is edited rarely,
  and its points are already the recipe.
- **The parameters of a device graph: no.** See 3.6.

### 3.2 The trait

```rust
/// A kind of modifier: the code. The saved entry (3.3) holds the parameters.
pub trait ModifierKind<C: Content>: Send + Sync {
    /// "quantize", or "musicops.arp" for a kind of an extension. Never changes.
    fn id(&self) -> &KindId;
    /// The version of the meaning of the parameters and of the output. A change of the
    /// output is a new version: it is in every key that the kind touches.
    fn version(&self) -> u32;
    /// What the kind reads beyond its input: the project key, the tempo map, the meter,
    /// the length and loop of the clip. Only what it declares is in its key.
    fn reads(&self) -> Reads;
    /// Local: each output item comes from one input item and needs no other item, so paw
    /// evaluates each run of 256 notes alone and keeps the runs that did not change.
    fn local(&self) -> bool { false }
    /// Checks the parameters: a sentence for the user when they are wrong.
    fn check(&self, params: &Params) -> Result<(), String>;
    /// The function. Pure: the same input, parameters and context give the same output.
    /// Random kinds draw only from `ctx.rng(name)`, a named stream of the entry's seed.
    fn apply(&self, input: &C, params: &Params, ctx: &Ctx) -> Result<C, ModError>;
    /// For a reversible kind, the change of one item and its reverse (section 7.2).
    fn reverse(&self, params: &Params) -> Option<Reverse> { None }
    /// "quantize 1/16 · 60 %" for K and the panel, and "q16" for the clip label.
    fn describe(&self, params: &Params) -> String;
    fn short(&self, params: &Params) -> String;
}
```

- **The built-in kinds are one `enum Builtin`** that implements the trait with a `match`. There
  is no `Box<dyn>` for them. The trait exists so that `LuaKind` (and later a WebAssembly kind) sits
  next to them in one registry.
- **`Params`** is the plain JSON value of CK-A6 (no binary, no NaN, at most 64 KB for a
  modifier). Built-in kinds decode it with serde into their own record.
- **Note identity.** An output note keeps the `id` of its input note when it comes from one note.
  A note that a kind makes (an arpeggio from a chord) gets `from = <id of its input note>` in
  the result. The result is never saved, so `from` lives in the result only. With it, `K` on a
  ghost names the note that made it, and the roll can light the results of the note under the
  cursor.
- **Attributes pass through.** A kind that does not know the MIDI 2.0 attribute of a note keeps
  it. The sampler and the articulations see the attribute in the result.
- **Errors.** `apply` that fails, or a Lua kind over its time limit, gives `ModError`. The stack
  then passes the input through that entry, the entry shows `error: <sentence>` in the panel,
  and paw gives the message one time. It is never a stack trace.

### 3.3 The saved entry

```rust
/// One modifier in a stack, as the project saves it.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    pub kind: KindId,              // "quantize", "musicops.arp"
    pub version: u32,
    #[serde(default = "yes", skip_serializing_if = "is_true")]
    pub on: bool,                  // off: not evaluated, not in any key
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope: Option<Scope>,      // a beat range of the clip; later a query
    pub params: Params,            // the kind's own value, as the kind encoded it
}

pub struct Stack<C: Content> { entries: Vec<Entry>, _c: PhantomData<C> }
```

- In `track.json`, a MIDI clip has `"modifiers": [ { "kind": "quantize", "version": 1,
  "params": { "grid": 0.25, "strength": 0.6 } }, … ]`, with the keys in alphabetical order, as
  every JSON file of the project. A change of one parameter is one line in `git diff`.
- The media design's `Modifier { op, version, enabled, params }` becomes this `Entry`. Its
  `enabled` is `on`, and its `op` is `kind`. The two designs then share the record, the
  registry and Apply. Its builder (TASK for the media plan) uses the same type.

### 3.4 The chain of keys, and the cache

```text
k0 = hash(C::NAME, source.stamp(), stamps of what the kinds read)
ki = hash(k(i-1), kind, version, canonical params, scope)        for each entry that is on
result = the output with the key of the last entry that is on
```

- The cache is in the sync (`Compiled` gets a sibling `Results`), keyed by `ki`, holds `Arc`s,
  and forgets an entry that no clip holds, after a sweep, as `Compiled::sweep` does today.
- A change of the parameters of entry 3 keeps `k1` and `k2`, so paw runs entries 3 to the end.
  A switch of an entry off removes it from the chain, and the keys after it change.
- An undo gives the old keys back. The results are often still in the cache, so an undo costs
  nothing more than today's undo.
- A local kind keeps a result for each run: the key of a run is the pointer of its input run
  and `ki`. An edit of one note in a clip of 4 000 notes then runs the kind over 256 notes.
- The sync keys the compiled events of the engine by `k_last` in place of the overrides. Clips with
  the same notes and the same stack share one list, wherever they are (as TASK-85.1 requires).

### 3.5 The Lua face

```lua
-- runtime/lua/paw/contracts.tl (additions), and the module paw.modifier

--- A kind of modifier that an extension defines. P is the record of its parameters.
record ModifierKind<P>
   name: string                       -- "musicops.arp": the extension, a dot, a word
   version: integer
   content: string                    -- "midi" now
   params: {ParamSpec}                -- name, kind (number, choice, toggle, seed, grid),
                                      -- range, unit, default: the rows of the panel
   main: string                       -- the parameter of + -; second: the one of ] [
   second: string
   reads: {string}                    -- "key", "tempo", "meter", "clip"
   ["local"]: boolean
   -- The kind's own form of its parameters. Without them, P is saved as it is, as plain data.
   encode: function(p: P): util.Data
   decode: function(d: util.Data, version: integer): P, string    -- migrates an old version
   check: function(p: P): string
   apply: function(cols: NoteColumns, p: P, ctx: ModifierCtx): NoteColumns
   reverse: function(p: P): Reverse   -- optional
   describe: function(p: P): string
   short: function(p: P): string
end

--- The notes as columns of numbers: one array for each field, the same length.
record NoteColumns
   start: {number}  length: {number}  pitch: {integer}  velocity: {integer}
   id: {integer}    attr: {integer}   from: {integer}  -- from: 0 when the note is an input note
   controls: ControlColumns
   n: integer
end

record ModifierCtx
   rng: function(name: string): Rng   -- PCG32, a named stream of the entry's seed
   clip: ClipInfo                     -- length, loop, start in the song (read-only)
   key: Key                           -- only when declared in reads
   beats_to_seconds: function(b: number): number   -- only when "tempo" is in reads
end

paw.modifier.register(kind: ModifierKind<P>)   -- goes away when its extension unloads
```

- The core calls `apply` in the kernel, under `paw.limit.guard` with a budget of 50 ms (the
  clip-kind budget). During the call, a write to the project is refused (a write guard, as the
  clip-kinds design C3 gives), and `math.random` is not part of the key, so the guide and the
  teal skill name `ctx.rng` as the one source of chance.
- Columns, not a table for each note: the bench of 2026-11-23 shows that the tables cost most of
  a key over 6 400 notes. The kernel fills the arrays from the runs. Note `meta` is not in the
  columns: a kind does not read or write `meta` (it stays with the source notes). If a kind needs
  it later, `cols.meta(i)` reads one note.
- An extension that unloads takes its kinds away. Their entries then wait (4.5).

### 3.6 What is not a modifier, and how the others relate

| Thing | Runs | Over | Its output | Relation to a modifier |
| --- | --- | --- | --- | --- |
| **Modifier** | In the kernel, on an edit, cached | Saved content (the notes) | New content, compiled to engine events | none |
| **Modulator** (devices graph 4.6) | On the audio thread, each 32 samples | The values of parameters of devices | An offset of a parameter value | Different time and data. A modifier never sees audio or a block. A modulator never changes notes. `:mod.bake` turns a modulator link into automation points, which a lane stack could later change. |
| **Driver** (TASK-86) | On the main thread, over time | A value: time, tempo, another value | Automation-like control of a parameter | A driver can set a parameter of a modifier (a constant at compile time). It cannot set a value that changes in a note. |
| **Note-FX device** (luafx `chords`, a CLAP note effect) | Live, on the audio thread or in a Lua device | MIDI that comes into the track, also from the keyboard | MIDI to the next device | The same pure Teal function can be both: a kind (`chords`) and a device. The kind changes the clip and its export; the device also plays what you play live. |
| **Articulation map** (articulations extension) | At the output of the track | Attributes of notes | Keyswitches, CC, programs | It depends on the instrument, so it is at the track (as Reaticulate). A kind that chooses articulations (perform) writes attributes in the result, and the map then sends them. |
| **Generator** (pattern) | On an edit of its text | Its own text, no input notes | The notes of the clip | Not a modifier: a stack needs an input. It stays a writer of notes or a custom clip kind. |
| **Audio render op** (media design) | A bake, in a pool or a helper process | Samples, frames | A file in the cache | Shares the entry and Apply, not the trait. |

The line: a modifier is pure, runs in the kernel, takes and gives saved content of one type,
and its output is complete before the engine plays it. Everything that runs while sound plays
is a device or a modulator.

### 3.7 Where the generic trait costs more than it gives

- **One content is the real need today.** The MIDI stack is the only consumer that is sure. A
  trait with a content parameter adds a type parameter to the stack, the cache and the
  evaluator. The cost is small in Rust, but a lane stack or an audio stack does not come for
  free with it: each content needs its own views (a ghost curve, a ghost waveform), its own
  reverse for editing, and its own export. The generic part is the bookkeeping, not the user
  experience. Recommendation: build `Content` with one implementation (`Midi`), and add
  `Lane` only on a request (Q4).
- **The built-in kinds do not need the trait.** A `match` over an `enum` is faster, easier to test
  and has no dynamic call. The trait is there only for extension kinds. Rust code must not grow
  a `dyn ModifierKind` for each built-in kind.
- **The media design's render ops do not fit,** and must not be forced into `apply`: an op that
  takes seconds and writes a file breaks "a key under 100 ms". Two families share the entry:
  pure ops (this trait) and bakes (the media scheduler).
- **A Lua kind called from Rust is a re-entry.** The evaluator calls Lua while the kernel holds
  the session. The design takes a snapshot of the input columns and releases the session borrow
  before the call, and the write guard refuses `paw.api` writes. This is more code than a pure
  Rust stack, and it is the main risk of the first bundle.
- **A generic parameter schema is a small language.** The schema covers what the panel needs
  (number, choice, toggle, seed, grid, a range and a unit). A kind with a more complex value (a
  groove template, a list of chords) gets `encode` and `decode` and a `c` key that opens its own
  prompt. The schema must not grow into a form builder.

---

## 4. The MIDI stack

### 4.1 Where a stack sits, and the order

| Place | In the first plan | Why |
| --- | --- | --- |
| A MIDI clip | Yes | The place of Logic's region parameters, REAPER's take FX and Blender's object stack. |
| A linked copy | Yes, because a copy is a clip | The notes are shared, the stack is per copy (Blender: modifiers on the object, not on the mesh). |
| The link (all copies) | No | Copy a stack with `yy` `p` or with a template. A second stack on the link adds an order question for little gain. |
| A scope: a beat range in the clip | Yes, a field of the entry | `:'<,'>clip.stack add humanize` humanizes bars 9 to 12 only. Blender restricts a modifier with a vertex group in the same way. |
| A scope: a query (`pitch>=C5`, `art=stc`) | Later | Uses the query language of `:select`. It is in the key as text. |
| A track | Later (Q3) | Cubase's track MIDI modifiers. It comes after each clip's stack. Today a note-FX device does a live version. |
| A time range of the song over many tracks | No stack of its own | A command puts one scoped entry on each clip in the range, in one undo step. A stack of the song would be a second source of truth for every clip. |
| A custom clip's MIDI sound, a nest | Later | A custom kind already owns its sound. A nest has its own tracks with their own clips. |

The order when several apply, from the stored notes to the speaker:

```text
notes of the clip (shared by a link)
  → the clip's stack, top to bottom (an entry with a scope changes only its range)
  → (later) the track's stack
  → compiled events (loop, trim, clip start) → the engine
  → the track's note-FX devices, live → the instrument → the articulation map at the output
```

### 4.2 The built-in kinds

Each kind is in Rust. Its main value is on `+ -`, its second value on `] [`.

| Kind | Parameters (main, second first) | Reversible | Local | Reads |
| --- | --- | --- | --- | --- |
| `transpose` | semitones, octave | yes | yes | none |
| `velocity` | add, scale (%), fixed (off or 1 to 127), curve | yes when only `add` is set | yes | none |
| `quantize` | strength, grid, swing, lengths, window | no | no (swing reads the grid of the song) | clip |
| `length` | factor (gate time), legato (off, on, overlap) | no | factor: yes; legato: no | clip |
| `humanize` | time (ms), velocity range, length range, seed | no | yes | tempo |
| `range` | low, high, mode (drop, fold into octaves) | no | yes | none |
| `scale` | mode (snap up, down, nearest, drop), the key or the project key | no | yes | key |
| `delay` | beats or ms | no | yes | tempo for ms |
| `chance` | percent, seed | no | yes | none |

Kinds that are not built in (extensions): `musicops.arp`, `musicops.strum`, `musicops.crescendo`,
`musicops.transpose_in_key`, `perform` (9.2), `luafx.chords` (3.6).

### 4.3 `Overrides` becomes `transpose` and `velocity`

- `Clip.overrides: Overrides` is removed. `Clip.modifiers: Stack<Midi>` takes its place.
- **Old projects open.** `track.json` with `"overrides": { "transpose": 3, "velocity": -10 }` loads
  into `[transpose 3, velocity add -10]`. The two commute, so the order changes no note. The
  next save writes `modifiers` only. The shim is one `#[serde(default)]` field that the loader
  folds into the stack and does not write. It goes away with the first tagged release (no
  compatibility is needed before a release).
- `:clip.override transpose=3 velocity=-10` stays as a short command (Q2). It sets the first
  `transpose` and `velocity` entries of the stack and adds them at the top when they are not
  there. `:clip.override clear` removes them.
- `paw.api.clip_get` loses `transpose` and `velocity` and gains `modifiers`. `Clip:shifted` stays
  as the name of the reversible prefix (7.2), so `roll_draw` and `A.move_note` keep their code.
- The label `riff ≡ +3 v-10` stays the same: those are the `short` forms of the two kinds.
- The tests of TASK-85.2 and TASK-176 (`tests/clip_overrides.lua`, the sync test
  `a_copy_with_overrides_plays_its_notes_changed`) pass with no change of their keys. They are
  the proof of the migration.

### 4.4 Evaluation and the engine

- **When.** The sync of the kernel evaluates the stack of each clip that it compiles. It already
  compiles only the clips that changed. A stack with no entry that is on costs nothing: the
  source runs go to the compile as today.
- **Where.** On the kernel thread, in Rust for built-in kinds. For a Lua kind, the evaluator fills
  the columns, releases the session, calls the kind under the guard, and reads the columns back.
- **The engine does not change.** It gets compiled events as today. No allocation, lock or wait
  is added on the audio thread.
- **Budget.** Targets for a key (to measure in bundle 1, in `bench/`, not in a test):

  | Case | Target |
  | --- | --- |
  | A clip of 500 notes, a stack of 4 built-in kinds, a change of the last entry | under 1 ms |
  | 6 400 notes on 63 clips, a quantize entry added to each (`:%clip.stack add quantize`) | under 30 ms for the stacks, the key under 100 ms |
  | A clip of 4 000 notes, a Lua kind (arpeggio) | under 20 ms |
  | An edit of one note in a clip of 4 000 notes, a stack of local kinds | one run of 256 notes again |

- **Over the budget.** The guard stops a Lua kind that runs over 50 ms. The entry shows
  `error: over 50 ms`, the stack passes the notes through it, and the message says which kind.
  A slow kind does not make each key slow.

### 4.5 A kind that is not loaded

- The entry stays in `track.json` with its bytes as they were. paw never rewrites or removes it.
- The stack runs without it: the entries before and after it run, and it passes its input
  through. So the clip plays its notes, as the rule "MIDI is the truth" asks.
- The panel row says `? musicops.arp — waits for musicops`. The clip label gets `?`. `K` and
  `:checkhealth` name the extension. `:ext.load musicops` makes it run at once (its key joins the
  chain, and the clip compiles again).
- Apply over a prefix that holds a waiting entry is refused: "modifier 2 waits for musicops:
  load it, or remove it with dd".
- An entry of a newer version than the loaded kind knows waits too, with `needs musicops 3`.
  An older version goes through the kind's `decode`, which migrates it; the entry is written
  in the new version only when the user changes it.

### 4.6 Why no kept result

The ticket proposed to keep the last result of an extension kind in the project, as a custom
clip keeps its sound. The owner's message of 2026-11-23 asks for the other behavior: without the
extension, the notes play and the modifier waits. The design follows the owner:

- For: one truth on disk, no second `.midi2` file that can be stale, no rule of when a kept result
  is valid, and a smaller project in git.
- Against: a project with an arpeggio modifier sounds different on a machine without musicops.
  The panel and the label say so. Apply makes the result into notes when the user wants it to
  sound the same everywhere.

Q7 asks the owner to confirm.

### 4.7 Undo

- Each action is one undo step: an entry added, removed, moved, switched on or off, a parameter
  changed (each `+` is one step, as in the device panel), a template put on, Apply.
- The stack is a field of the clip, so the existing undo of the model covers it. The results are
  not in the undo: they come back from the cache, or the evaluator makes them again.
- The undo label is the kind's `describe`: `quantize strength 60 % → 70 %`.

### 4.8 Apply

- `:clip.apply` applies the whole stack. `:clip.apply 3` applies entries 1 to 3: the result after
  entry 3 becomes the notes, and entries 1 to 3 leave the stack. Entries that are off in the
  prefix leave too (they changed nothing). One undo step.
- Only a prefix. Apply of one entry in the middle is refused with "move it to the top (Alt-k), or
  apply 1 to 3". Blender allows it and warns. A refusal is clearer, and `Alt-k` is one key.
- **A linked clip.** Apply changes the shared notes, so all copies would change. paw refuses with
  "riff is linked to 3 clips: :clip.apply! takes it out of the link first". `:clip.apply!` takes the clip out of its link and applies,
  in one undo step (Blender: make single user, then apply).
- Notes that come from one input note keep their `id` and their `meta`. Notes that a kind made
  get new ids and copy the `meta` of the note in `from`.
- A note that a modifier dropped (out of range, chance) is gone after Apply. The message says how
  many: "applied 3 modifiers: 212 notes, 4 dropped, 8 made".

### 4.9 Templates

- The template store of TASK-298 gets a core kind `stack`. Capture: the entries of the stack
  under the cursor (or the entries selected in the panel). Make: put the entries on the clip,
  after its stack or in place of it, as one undo step. The format is the JSON of the entries.
- A template that holds a kind of an extension that is not loaded is listed with the name of the
  extension, as TASK-298 #10 says. Put on a clip, its entries wait (4.5).
- Bundled templates: `swing 16ths 58 %`, `loose drummer`, `tight quantize`, `piano gate 90 %`.
- Linked stack templates (a clip follows its template, so a change of `my swing` changes 30
  clips) use TASK-298 #5. Not in the first plan (Q9).

---

## 5. Speed and correctness details

### 5.1 Determinism

- Random kinds keep a seed in their parameters and not their output. The stream is PCG32, named
  by `(seed, kind, name)`, as the media design gives (its part on modifiers). The crate is `rand_pcg`
  (a row goes into `paw-crates.md` if it is not there).
- The parameters are keyed as canonical JSON with floats in shortest round-trip form.
- A built-in kind that changes its output on purpose takes a new version. A test pins each
  built-in kind on a small golden input, so a change of output without a new version fails.

### 5.2 Controllers

- A move of one key (the bend or pressure of a note) follows its note, as `Overrides::control`
  does today. A kind that moves or drops a note moves or drops the moves of its key.
- Other moves pass through unless the kind changes controllers (a later `cc.scale` kind).

### 5.3 One quantize

TASK-128 asks for one implementation of quantize. The built-in kind is in Rust. So
`paw.notes.quantize` (Teal) becomes a thin call to the same Rust function through
`paw.api.notes_quantize` with columns, and the operator, the gesture, Ex and musicops keep
their callers. A test feeds both paths the same notes. Humanize, strum and arpeggio stay in
Teal (musicops), and their operator and their kind call the same Teal function.

---

## 6. The views and the keys

### 6.1 The stack panel

A view of its own, `stack://`, beside the device graph. It follows the clip under the cursor in
the arrange view, and the clip of the piano roll. `\p` pins it, as the device panel does. Its rows
are the rows of the inspector of the devices graph (`device_rows`): a heading for each entry,
then its parameters, then an add line. The keys are the keys of the device panel, so nothing is
new to learn.

80 columns:

```text
 stack · riff ≡ (linked, 3 clips) · Keys · 208 notes → plays 212          pinned
 1 transpose      +3                                              ↑ ↓ ×   on
 2 quantize       1/16 · 60 %                                     ↑ ↓ ×   on
   strength       ▕██████████▌         ▏ 60 %
   grid           1/16
   swing          ▕                    ▏ 0 %
   lengths        off
 3 humanize       seed 7 · 8 ms · vel ±6                          ↑ ↓ ×   off
 4 musicops.arp   ? waits for musicops                            ↑ ↓ ×   ?
   + add a modifier
 a add · gcc on/off · Alt-j/k move · \a apply to here · K describe · ? keys
```

120 columns (more room: the scope and the change that each entry makes):

```text
 stack · riff ≡ (linked, 3 clips) · track Keys · 208 notes → plays 212                                          pinned
 1 transpose      +3                              whole clip         208 notes moved                ↑ ↓ ×   on
 2 quantize       1/16 · 60 %                     whole clip         191 starts moved, ≤ 12 ticks   ↑ ↓ ×   on
   strength       ▕██████████████████████▌               ▏ 60 %
   grid           1/16                                                                       ] [ the second value
   swing          ▕                                      ▏ 0 %
   lengths        off
 3 humanize       seed 7 · 8 ms · vel ±6          bars 9 to 12       off: changes nothing           ↑ ↓ ×   off
 4 musicops.arp   ? waits for musicops            whole clip         passes the notes through       ↑ ↓ ×   ?
   + add a modifier
 a add · c type · x default · dd cut · yy p copy, put · gcc on/off · Alt-j Alt-k move · \a apply to here · K · ? keys
```

| Keys in the panel | Effect (the device panel's grammar) |
| --- | --- |
| `j` `k`, `w` `b`, `e`, `gg` `G` | rows, entries, the last parameter, first and last row |
| `+` `-`, `Ctrl-a` `Ctrl-x` | the main value: of the parameter, or on a heading the kind's `main` |
| `]` `[` | the second value of the entry (the kind's `second`; for a seed: the next and the previous seed) |
| `c` | type the value; on a heading, change the kind with the picker |
| `x` | the parameter to its default |
| `a` | add a modifier after the cursor: the picker of kinds, with audition (`<C-Space>` hears it, `Enter` keeps, `Esc` takes it back) |
| `gcc`, `~` | switch the entry on or off (`gc` bypasses a device; `~` switches a property; both mean the same here) |
| `Alt-j` `Alt-k` | move the entry down or up |
| `dd`, `yy`, `p` `P` | cut, copy, put an entry (also into the panel of another clip) |
| `V` then `p` in the arrange view | put the copied entries on every selected clip (Blender's Copy to Selected) |
| `<` `>` on a heading | the start of the scope, earlier and later (time keys) |
| `K` | describe the entry: what it changed, in numbers |
| `\a` | Apply up to the entry under the cursor (as the media design's `\a` in `:clip.recipe`) |
| `\t` | save the stack, or the selected entries, as a template |
| `.` | repeat the last change |

### 6.2 The stack as text

`:clip.recipe` (approved in the media design) opens the stack of a MIDI clip as a list edited as
text: one line for each entry, `:w` applies the changes in one undo step.

```text
transpose +3
quantize grid=1/16 strength=60%
# humanize seed=7 time=8ms velocity=6 scope=9:1-13:1
musicops.arp rate=1/16 order=up            # waits for musicops
```

A line with `#` first is an entry that is off. Unknown words in a line of a waiting kind are kept
as the bytes were.

### 6.3 Ex commands

| Command | Effect |
| --- | --- |
| `:clip.stack add quantize grid=1/16 strength=60%` | add an entry at the bottom, on the clip under the cursor or on each selected clip |
| `:'<,'>clip.stack add humanize` | the same, with the scope of the range |
| `:clip.stack set 2 strength=70%`, `:clip.stack on 3`, `:clip.stack off 3`, `:clip.stack move 3 1`, `:clip.stack rm 3` | change an entry |
| `:clip.stack` | list the stack (as `K`) |
| `:clip.apply [n]`, `:clip.apply! [n]` | Apply (4.8) |
| `:clip.override transpose=3 velocity=-10`, `:clip.override clear` | the short form of 4.3 |

Not `:mod`: the devices graph uses `:mod` for modulators.

### 6.4 Global keys

| Keys | Effect |
| --- | --- |
| `<Space>cs` | the stack panel of the clip under the cursor (arrange view, piano roll); again: close it |
| `<Space>ca` | add a modifier to the clip under the cursor, or to each selected clip, from the picker |
| `<Space>cA` | Apply the whole stack of the clip (as `:clip.apply`) |

They are in the domain `c` (clip), next to `<Space>cf`, `<Space>cl` and `<Space>cu`. The
`:lua =paw.keyrule.broken()` check and `tests/keys_constitution.lua` cover them.

### 6.5 The arrange view

The label gets the `short` form of each entry that is on, as long as it fits, then `ƒN`:

```text
a clip 24 cells wide: ▕riff ≡ +3 q16 hum   ▏   ▕riff ≡ ƒ4 ?        ▏
                       all fit                 too long, one waits
```

`K` on a clip:

```text
MIDI clip riff · linked: riff, 3 clips · 208 notes, plays 212
stack: 1 transpose +3 · 2 quantize 1/16 60 % · 3 humanize (off) · 4 musicops.arp (waits for musicops)
```

---

## 7. The piano roll

### 7.1 What it shows

- The **ink** is what you edit: the source notes, seen through the reversible prefix (7.2).
- The **ghosts** are the result, where it is not the same as the ink: a note that moved, a note
  that a kind made, a velocity that changed. They use the ghost style of completion
  (`complete.tl`: a faint fill). A note that the stack drops shows as ink with a dim cross.
- `\m` steps through three looks: `notes + played` (the default), `notes`, `played`. In `played`,
  the roll is read-only: an edit key says "the roll shows what plays: \m to edit the notes".
- `K` on a note: `C4 v80 at 9.2.10 · plays C4 v74 at 9.2.00 (quantize −10 ticks, humanize v −6)`.
  `K` on a ghost: `made by musicops.arp from E4 at 9.1.00`.
- The title of the roll names the look: `roll · riff ≡ ƒ3 · notes + played`.

80 columns, `notes + played`, a stack of `quantize` and `musicops.arp`:

```text
 roll · riff ≡ ƒ2 · Keys · notes + played (\m)                        9.1 → 10.1
       │9.1             9.2             9.3             9.4             10.1
 G4    │                                                  ░░░░
 E4    │  ████████                        ░░░░    ░░░░            ░░░░
 C4    │████████████████              ████████████████░░░░    ░░░░    ░░░░
 A3    │                ░░░░  ████████
       │
 █ the notes (you edit them)   ░ what plays   ✕ dropped        \m the look
```

At 120 columns the roll shows more bars and the strip of velocities shows the ink velocity as a
bar and the played velocity as a tick in the same column:

```text
 roll · riff ≡ ƒ2 · Keys · notes + played (\m)                                                       9.1 → 11.1
       │9.1             9.2             9.3             9.4             10.1            10.2            10.3
 G4    │                                                  ░░░░                                    ░░░░
 E4    │  ████████                        ░░░░    ░░░░            ░░░░  ████████          ░░░░
 C4    │████████████████              ████████████████░░░░    ░░░░    ░░░░████████████████    ░░░░    ░░░░
 A3    │                ░░░░  ████████
 vel   │█▔      █▔      ▁▔    █▔      █▔      ▔       ▔       ▔       █▔      ▔
 █ the notes   ░ what plays   ▔ played velocity   ✕ dropped   \m the look   <Space>cs the stack
```

### 7.2 Editing through a reversible prefix

- The reversible prefix is the run of entries at the top of the stack whose kind is reversible
  and has no scope (`transpose`; `velocity` with only `add`; an extension kind with `reverse`).
- The ink shows the source after that prefix, and an edit writes back through the reverse. With
  only `transpose +3` and `velocity -10`, this is the behavior of TASK-85.2 to the letter: the
  roll shows played pitches and stores the pitch less 3.
- With no reversible prefix, the ink is the plain source.
- A note that the prefix takes outside 0 to 127 is not in the ink, and it keeps its place in the
  list (TASK-176 #3).
- The ghosts start after the prefix, so a transposed copy with a quantize shows the quantize
  ghosts at the shown pitch.

### 7.3 The score and other readers

| Reader | Reads | Why |
| --- | --- | --- |
| Engine, render, freeze, stems | result | What you hear. |
| MIDI export (`:export midi`) | result; `notes=source` writes the source | As overrides today. |
| DAWproject and RPP export | result | The other programs do not know paw's kinds. |
| Score (notation) | source (it edits notes); `played` look read-only | A score is an editor of the notes (Q10). |
| Harmony reading, MIDI LSP | result | They describe what you hear. |
| `:select`, `:query`, search, Ex ranges | source | They choose notes to edit. |
| musicops operators | source | They edit notes. |

---

## 8. Export to MIDI files

- `:export midi` writes the result of each clip, as it writes the overrides today
  (`midifile.tl` near line 1236 calls `Clip:shifted`; it then calls `Clip:played()`, which asks
  the kernel for the result columns).
- `:export midi notes=source` writes the stored notes.
- A clip whose stack holds a waiting entry exports what plays (the stack without it), and the
  message says "riff: musicops.arp waits, exported without it".
- The stack is not written into the MIDI file. A MIDI file has no place for a recipe.

---

## 9. Extensions

### 9.1 A kind in an extension

```lua
-- extensions/musicops/lua/musicops/kinds.tl (sketch)
paw.modifier.register({
  name = "musicops.arp", version = 1, content = "midi",
  params = {
    { name = "rate", kind = "grid", default = 0.25 },
    { name = "order", kind = "choice", values = { "up", "down", "updown", "random" }, default = "up" },
    { name = "seed", kind = "seed" },
  },
  main = "rate", second = "order",
  apply = function(cols, p, ctx) return arp.columns(cols, p, ctx.rng("order")) end,
  describe = function(p) return ("arp %s %s"):format(paw.grid.name(p.rate), p.order) end,
  short = function(p) return "arp" end,
})
```

- The operator `gzp` and the kind call the same `arp` function.
- The README of the extension names each kind, as it names each command and key, and the test of
  the README covers kinds.

### 9.2 The extension `perform`

The perform design keeps a different model: it writes the performance into the notes and keeps
provenance, so that a value that the user changed wins over a new run. A modifier cannot do
"the user wins" for one note, because the user edits the source, not the result. Both models have
a use:

- perform as approved (writes MIDI, `\ee`, the audition, provenance) stays the main way.
- A kind `perform` (later) runs the same rules as a modifier, for a user who wants the
  performance to follow the notes on each edit, and accepts that Apply must come first before a change of a single
  value.

Q8 asks the owner.

### 9.3 Drivers, templates, clip kinds

- A driver (TASK-86) can target a parameter of an entry: `quantize.strength` follows a macro. The
  value is read when the stack is evaluated, so it is in the key.
- Templates: 4.9.
- A custom clip kind with a MIDI sound can get a stack later (the stack over `Sound`).

---

## 10. Tests

Rust (crates/paw-core, sealed, by the rust-testing skill):

- Each built-in kind on a small input: the output, and the golden pin of 5.1.
- The chain: a change of entry 3 runs entries 3 to the end only (a count, as `COMPILES` does).
- Linked copies with the same stack compile one time; with two stacks, two times.
- An edit of one note in a clip of 4 000 notes with local kinds runs one run again.
- The migration: a `track.json` with `overrides` opens as two entries and plays the same events
  as before (the existing sync test).
- A waiting entry: the stack passes through it; the save keeps its bytes.
- Apply of a prefix: the notes equal the result after entry n; ids are kept; one undo step.
- `tests/no_alloc.rs` passes unchanged (no engine change).

Lua and Teal (real keys, by the lua-testing skill):

- `<Space>ca`, choose `quantize` in the picker, `Enter`: one undo step; `u` removes it; a render
  plays the quantized notes; the stored notes are the same.
- In the panel: `+` on `strength`, `gcc`, `Alt-k`, `dd` and `p` on another clip, `\a`.
- The piano roll: golden screens at 80 and 120 columns of the ghosts; `\m`; `K` on a ghost; an
  edit in a transposed copy with a quantize below the transpose.
- The tests of `tests/clip_overrides.lua` pass with no change of keys.
- An extension registers a kind; a project saved with it opens without the extension: the clip
  plays its notes, the panel says it waits, `:ext.load` makes it run.
- A Lua kind over the time limit: the entry shows the error, the key returns.
- `:export midi` writes the result; `notes=source` writes the source.
- A stack template: save, put on another clip, one undo step.

Not tests: the time of a key. The time goes to `bench/` (a scenario `stacks` in `bench/edit.lua`).

---

## 11. The plan, in bundles

Each bundle is one ticket for one agent, with its docs in the same commit.

| Bundle | Content | Size | Depends on |
| --- | --- | --- | --- |
| **S1 Core stack** | `model/modifiers.rs`: `Content`, `Midi`, `Entry`, `Stack`, `Builtin` (`transpose`, `velocity`), chain keys, `Results` cache in the sync, compile from the result. `Overrides` removed; the loader shim. `paw.api.clip_stack_*`, `clip_get.modifiers`. `:clip.override` on the stack. `:clip.stack`, `:clip.apply[!]` (prefix, links). Folder save. Undo labels. The bench scenario. Docs: the reference pages of the project files, the arrange view and the piano roll (the parts on overrides). | L | none |
| **S2 Built-in kinds** | `quantize` (and `paw.notes.quantize` on it), `length`, `humanize` (PCG32), `range`, `scale`, `delay`, `chance`; the golden pins; scopes as beat ranges; `:'<,'>clip.stack add`. | M | S1 |
| **S3 Extension kinds** | `paw.modifier.register`, `ModifierKind` in contracts.tl, `LuaKind` with columns, guard, write guard, `encode` and `decode` with versions, waiting entries, unload, `:checkhealth`. musicops registers `arp`, `strum`, `crescendo`, `transpose_in_key`. The reference page of extensions, the extension skill. | L | S1 |
| **S4 The views** | `stack://` panel on `device_rows`, keys of 6.1, `<Space>cs` `<Space>ca` `<Space>cA`, the picker with audition, `:clip.recipe` for MIDI clips (shares the list buffer of the media design), the label, `K`, golden screens. | L | S1; S3 for waiting rows |
| **S5 The piano roll and readers** | ghosts, `\m`, the reversible prefix rule (generalizes `Clip:shifted`), `K` on notes and ghosts, export (`notes=source`), the readers of 7.3, the explanation page `about-midi-as-the-truth.md` (a section on stacks), a how-to guide with its test in `tests/guides_howto.lua`, GIF. | L | S2, S4 |
| **S6 Templates** | the `stack` kind of the TASK-298 store, bundled stack templates, `\t` in the panel. | S | S4, TASK-298 |
| Later | lane stacks (Q4), track stacks (Q3), query scopes, linked stack templates (Q9), the `perform` kind (Q8), drivers on parameters (TASK-86), stacks on custom clip sound. | none | none |

S1 is the risk: the re-entry of Lua from the evaluator is in S3, so S1 stays pure Rust and can
merge alone. S2 and S3 can run in parallel after S1. S4 can start after S1 with the built-in
kinds.

---

## 12. Risks

- **Re-entry.** A Lua kind is called while the kernel evaluates the sync. The snapshot and the
  write guard must be right, or a kind that calls `paw.api` corrupts a borrow. S3 has a test
  that a kind that tries to write gets an error, and the stack passes the notes through.
- **Two quantizes.** If S2 adds a Rust quantize and `paw.notes.quantize` stays in Teal, TASK-128
  is broken again. S2 owns both.
- **A link with an Apply.** Apply on a linked clip changes 3 clips. The refusal and `!` protect it.
- **The roll with many ghosts.** An arpeggio on a dense clip doubles the cells to draw. The ghost
  cells are a derived value keyed by `k_last`, so a scroll draws from the cache.
- **The devices graph rewrites the device panel.** The stack panel uses `device_rows`, which the
  graph's inspector keeps. If the graph changes the rows, S4 follows the inspector.

---

## 13. Questions for the owner

Each question has my recommendation.

1. **A generic trait with MIDI as the one content now?** Recommendation: yes. Build
   `ModifierKind<C>` and the shared entry, registry, keys, cache, Apply and templates. Build only
   `Midi` as a content. The audio structure ops of the media design use the same entry.
2. **`:clip.override` after the migration.** Recommendation: keep it as a short command that sets
   the `transpose` and `velocity` entries. It is the fast way for the common case.
3. **A track stack (after the clips' stacks, as Cubase's track MIDI modifiers).**
   Recommendation: not in the first plan. A note-FX device covers the live case. Add it on a
   request; the order (clip, then track) is already defined.
4. **Automation lane stacks.** Recommendation: not now. Lanes already have points, modulators and
   drivers. The trait keeps a place for them.
5. **The stack panel: a view of its own, or a part of the device graph.** Recommendation: its own
   view (`stack://`) with the inspector's rows and keys. The graph is about a track's sound; a
   stack is about a clip's notes.
6. **What the roll shows by default.** Recommendation: the notes as ink and the result as ghosts,
   `\m` for the other looks, and the reversible prefix rule so that transposed copies stay as
   they are now.
7. **A kind that is not loaded.** Recommendation (your message): the notes play without it, and
   it waits. No kept result in the project. Apply makes the result into notes when it must sound
   the same everywhere.
8. **perform as a modifier kind.** Recommendation: keep the approved model of perform (it writes MIDI
   with provenance) as the main way, and add a `perform` kind later.
9. **Linked stack templates (a clip follows a template).** Recommendation: later, on TASK-298 #5.
   Copies first.
10. **The score reads the source or the result.** Recommendation: the source, because the score
    edits notes; a read-only `played` look like the roll's `\m`.
11. **Apply of an entry in the middle.** Recommendation: refuse, and say "move it to the top or
    apply up to here". Blender allows it with a warning that users find confusing.
12. **Keys.** Recommendation: `<Space>cs` panel, `<Space>ca` add, `<Space>cA` apply all; in the
    panel `\a` apply up to here and `\t` save as a template; `\m` the look of the roll.
13. **The label mark.** Recommendation: the `short` forms (`+3 q16 hum`), then `ƒN` when they do
    not fit, and `?` when an entry waits.

---

## 14. Sources

- Logic Pro region parameters and Normalize Region Parameters:
  https://help.apple.com/logicpro/mac/10.4/en.lproj/lgcpf7c0d270.html,
  https://support.apple.com/guide/logicpro-ipad/lpipc2e6aa6b/ipados
- Cubase MIDI Modifiers and Freeze MIDI Modifiers:
  https://www.steinberg.help/r/cubase-elements/13.0/en/cubase_nuendo/topics/midi_realtime_parameters_and_effects/midi_realtime_parameters_midi_modifiers_section_r.html,
  https://steinberg.help/cubase_pro_artist/v9/en/cubase_nuendo/topics/midi_processing/midi_processing_midi_modifiers_freeze_c.html,
  https://www.soundonsound.com/techniques/cubase-midi-mod-cons
- Bitwig operators and Note FX: https://www.bitwig.com/userguide/latest/operators/,
  https://www.bitwig.com/userguide/bws44-504/note_fx
- Ableton Live 12 MIDI Tools: https://www.ableton.com/live-manual/12/midi-tools,
  https://www.soundonsound.com/techniques/ableton-live-12-midi-generators
- REAPER take FX with MIDI output, JSFX: https://reaper.fm/sdk/js,
  https://publish.obsidian.md/arendleejessurun/Atlas/Music+production/Reaper/MIDI+Sequencer+Megababy
  (a secondary source; the REAPER user guide has the action)
- Blender modifier stack and Apply: the Blender manual, "Modifiers" and "Apply" (from knowledge;
  not fetched in this session).
- Reaticulate: program changes in items, a JSFX on the track that sends keyswitches (from
  knowledge; not fetched in this session).
