# Review of m-10 and the generalizations

Superseded where it differs by [architecture-plan.md](architecture-plan.md) (2026-11-23).

Status: review and plan. No tracked file changed. Nothing was built.
Base: main at 7228146b. Date: 2026-11-23. Internal text.

The owner asked three things on 2026-11-23:

1. Can the generic Modifier trait go into the m-10 rework, and what other
   items need a generic form?
2. Extensions must be able to change the whole program: views, windows
   and the rest. Neovim is the bar.
3. Plan across all open milestones, and put this review first.

A reference `file:line` is at main 7228146b.

## Rust refinement (2026-11-23)

[The Rust refinement](rust-architecture.md) changes the Rust shapes of this review. What changed:

- `KindId` is `KindId<F: Family>`: one id type, the family as a type, dot-joined words. `Family` is a sealed trait with `const NAME` and `const ABSENT`. `RESERVED` and `ClipKindId` go.
- `Kinds<S>` is `Kinds<F, S>` with a stack of shadowed entries for each key, and the verbs of `paw.registry` (`put`, `get`, `remove`, `unload`, `owned_by`).
- `Stored` has `Version(NonZeroU32)` and reads into `Loaded<F, T> { Ready, Newer, Absent }`.
- The modifier family's absent rule is `PassThrough` (the owner's decision in the modifier design), not `Keep`.
- No `trait Op<T>` and no Rust `TemplateKind` trait: template kinds are registry entries with a `Verb`, and the store stays in Teal.
- `Linked<D>` is `Linked<D: Linkable>` with an associated type `Overrides`; definitions live once in `Defs<D>`.
- Model ids become `newtypes` (`TrackId`, `ClipId`, `DeviceId`, `NodeId`). No new type depends on a track (part 10 of the refinement).

## Interim: running work

The bundles below run now from 0d19ed40. The verdicts did not change
after the full review. The TASK-281 row has one more item.

| Bundle | Verdict | Change |
| --- | --- | --- |
| TASK-215 + 208 (timers, message sink, command registry below the upper layers; last registries onto `paw.registry`) | Continue, with one change | `paw.registry` (`runtime/lua/paw/registry.tl`) is already the generic Lua kind registry: owner, a stack of shadowed entries (`Slot.below`), unload by owner, `registry.all()`. Use that stack for `options` (the ticket asks for "a way to keep a shadowed entry": it exists, `registry.tl:14-17`). Do not add a second registry type. Do not give `formats`, `lsp`, `health` a `put` of their own that does work: put the spec, and let the owner module read `reg:get`. Then the later bundle for kinds only adds a Rust mirror. |
| TASK-98 (paw-core `pub(crate)`, lints) | Continue as is | Keep `model::custom` (`Word`, `ClipKindId`, `KindValue`, `KindData`) and `model::links` reachable inside the crate: Template, Modifier and the graph use them next. `pub(crate)` is correct. Do not delete a part of them as dead code. |
| TASK-3 + 217 (lazy extensions, optional dependencies, notation marks extension point) | Continue, with two changes | 1. The `kind` trigger is generic: a stub is a key in any `paw.registry` (`{registry = "clip_kinds", key = "video"}`), not a case only for clip kinds. Then template kinds, modifier ops, split kinds and track kinds get lazy load with no new code. 2. Give the notation marks extension point the form of a core `paw.registry` ("note marks": a function that gives the marks of a note), which notation puts. `query.tl:544`, `grep.tl:211` and `pick/project.tl:281` read it in place of `meta.notation.art`. That closes TASK-218 criteria 1 to 3 in the same branch, so TASK-218 does not build it a second time. |
| TASK-279 (devices graph kernel model) | Continue, with two changes | 1. Split kinds are open words in a kind registry (use `model::custom::Word`, as `ClipKindId` does), because the design (its summary, item 2) says an extension adds a kind. Built-in kinds can be a Rust `enum` behind the word. 2. Write "a linked definition with overrides per instance" as its own small generic module (`Linked<D, O>`: a definition id and the overrides of one instance), not inside the rack code. Linked clips (`model/links.rs`, with `Overrides` at `model.rs:626`), linked template instances (TASK-298 criterion 5) and linked racks are the same pattern. TASK-298 lifts that module; it must not have to pull it out of the rack code. |
| TASK-281 (generic `chain-syntax` crate) | Continue as is | The host schema as versioned JSON data fits the versioned contract of this review. Make sure that the kind of a node and of a split is an open string in the schema, so that a split kind from an extension is valid text. New: for the parameters of a kind, use the words of JSON Schema where they exist (`type`, `minimum`, `maximum`, `enum`, `default`, `description`) and keep units as an added key. Then the schemas that `schemars` makes for TASK-96 and the modifier ops convert with no loss. |
| TASK-93 / 109 / 107 (website with live paw) | Continue as is | No overlap with the generalizations. |

Nothing that runs now must stop.

## 0. Verdict

paw already has most of the generic parts. What it lacks is one
contract that joins them. The Lua side has one registry type
(`paw.registry`, 18 registries) and most entry points are public. Three
gaps remain:

1. **Built-ins take private paths.** The built-in clip kinds (`midi`,
   `audio`, `nest`) are outside the registry of kinds. 100 branches
   `kind == "midi" | "audio" | "nest"` in 30 runtime files decide what a
   built-in kind does. 87 call sites reach into the piano roll by name
   (`paw.ui.views:get("pianoroll")`), and 11 modules import its private
   type. An extension can add a view or a kind. An extension cannot
   replace the piano roll or draw an audio clip in its own way.
2. **No contract for data that an extension stores.** Clip kinds have a
   version and a `deserialize(stored, version)` (`clip_kinds.tl:14-36`,
   `model/custom.rs:352-354`). Templates (TASK-298 criterion 8), media
   ops (`media.md`, the `Modifier.version` field), modifier ops, split
   kinds and the chain host schema each plan their own form of the same
   thing. `meta` has no version and no owner (`model.rs:77`, `:141`,
   `:507`, `:608`, `:924`).
3. **The same three patterns are built several times, with no shared
   type:**
   - a stack of sources layered project > user > extension > bundled >
     generated (six stores today, three more planned);
   - a shared definition with overrides for each instance (linked clips,
     linked racks, linked templates);
   - a non-destructive change over a stored base (clip overrides, media
     modifiers, MIDI modifier stacks, notation marks and perform with
     provenance, modulators, drivers).

The two decided traits fit these gaps. **Kinds** (one contract for every
kind and the data that it stores) is the base under both of them, and it
must come first. **Template** is the layered store plus "copy or linked".
**Modifier** is the non-destructive change. The rule "built-ins use the
public API" turns the three into an extensibility guarantee.

The recommendation: add eight new bundles to m-10 (a design note, kinds,
store, linked, modifier core, two bundles for built-ins through the
public API, and the rest of Template), change the scope of five tickets,
and order m-5, m-16 and m-11 behind them. Do not add a generic Rust
container for every registry. Do not make modes extensible. Do not merge
the audio-rate modulators into Modifier.

## 1. What exists: the evidence

### 1.1 Registries of kinds and entries

The Lua side (all `paw.registry`, so owner and unload work):

| Registry | Where |
| --- | --- |
| views | `ui.tl:347` |
| buffer types | `layout.tl:456` |
| commands, completers | `commands.tl:149`, `:829` |
| picker sources | `pick.tl:327` |
| query fields | `query.tl:527` |
| Ex views, Ex fields | `ex.tl:240`, `:973` |
| grep sources | `grep.tl:107` |
| status line components | `statusline.tl:229` |
| track column components, signs | `trackcolumn.tl:115`, `:127` |
| ruler labels | `ruler.tl:68` |
| clip kinds | `clip_kinds.tl:99` |
| track kinds | `track_kinds.lua:50` |
| subproject kinds | `nest.tl:172` |
| insert kinds | `insert.tl:190` |
| text buffer kinds | `textbuf.tl:279` |
| curve providers | `curves.tl:363` |
| roles | `roles.tl:126` |

Still a plain table with a `put` of its own in `M.registries`
(`ext.lua:212-330`): keys, key groups, key bar, address schemes,
completion sources, controller buttons, layers, languages, health
checks, file formats, language servers, hooks, options, timers, Lua
device folders. TASK-208 moves them.

Still a plain table, in no list at all: language server subjects
(`lsp/subjects.tl:212`), zoom of a view (`vzoom.tl:160`), help pages
(`help.tl:605`), named layouts (`paw.layouts`, `defaults/views.lua:97`).

The Rust side, each in its own form:

| Kinds | Where | Form |
| --- | --- | --- |
| device kinds | `paw-engine/src/device.rs:831-850` | `BTreeMap<String, Rc<dyn DeviceFactory>>`, built-ins through the same `register` |
| clip kinds | `session/document.rs:59-61`, `model/custom.rs:30` | a set of `ClipKindId`; built-in kinds are reserved words, outside the set |
| content of a clip | `ClipContent::Custom`, 25 matches in 10 files | the built-ins are Rust variants |
| split kinds | TASK-279 (running) | planned |
| template kinds | TASK-298 | planned: "a Rust trait and a registry" |
| modifier ops, media ops | TASK-75, `media.md` (the `define_op` contract) | planned |

### 1.2 Sources layered project > user > bundled

| Store | Where | Layers |
| --- | --- | --- |
| templates | `extensions/templates/lua/templates/init.lua:22` | user only (`data_dir/templates`) |
| device presets | `fx.lua:200-215`, `device_presets.lua` | bundled table, the plugin's own, user JSON |
| articulation maps | `articulations/lua/articulations/maps.lua:447-460` | user, each extension, generated |
| utau singer presets | `utau/lua/utau/singer_presets.lua:20` | user |
| workspaces | `workspace.tl:86-126` | layouts, configuration, project, kept in memory |
| perform styles | `perform.md` (design) | bundled, user (`~/.config/paw/perform/`) |
| racks | `devices-graph.md`, "Templates" | bundled, user, project (planned) |
| export presets | TASK-222.5 | built-in, `init.lua`, project (planned) |

Each store has its own walk of folders, its own name clash rule and its
own picker source. Three more are planned with the same layers.

### 1.3 Non-destructive and derived things

| Thing | Where | Pattern |
| --- | --- | --- |
| clip overrides (transpose, velocity) | `model/overrides.rs:15-23`, applied in `sync/clips.rs` | a live change at compile time |
| linked clips | `model/links.rs:1-9` | one definition, many instances, each with its own overrides |
| media recipe and its modifiers | `media.md`, "Modifiers" (`Modifier { op, version, enabled, params }`) | a live or baked stack, Apply, Consolidate |
| MIDI modifier stacks | TASK-75 | a live stack, Apply, a bake when the extension is absent |
| notation marks | `meta.notation.wrote` | write the MIDI, keep provenance, undo only what is unchanged |
| perform | `perform.md`, "Non-destructive by design" | the same as notation: write and keep provenance. The design refused a live layer. |
| modulators | `devices-graph.md`, "Modulation" | audio thread, a base value kept, `:mod.bake` |
| drivers | TASK-86 | an expression on the main thread over a parameter |
| freeze, bounce | `freeze.lua`, `freeze.rs`, TASK-214 | a kept bake |
| derived values | `derived.tl:1-35` | one dependency graph for Lua caches |
| takes | `takes.tl:181-184` | core data in `clip.meta.takes` |

Two patterns stand out. A **live** stack evaluates over a stored base
(overrides, media, TASK-75, modulators). An **applied** change writes the
truth and keeps provenance (notation, perform). Both have toggle, order,
"what did it change" (`K`) and Apply.

### 1.4 Data stored with a version

| Data | Version | Migration |
| --- | --- | --- |
| project folder | `session/folder.rs:52`, `:1284-1289` | refuses a newer version |
| custom clip data | `model/custom.rs:352-354`, `clip_kinds.tl:33-36` | `deserialize(stored, version)` of the kind |
| `meta` of notes, clips, tracks | none | each extension does its own (`perform.md` puts `version = 1` inside its meta) |
| templates | TASK-298 criterion 8 | planned: version and migrate |
| media ops | `media.md`, `Modifier.version` | planned |
| chain host schema | TASK-281 criterion 8 | planned: versioned JSON |
| plugin state | `.state` files | the plugin's own |

### 1.5 Where the core knows an extension by name

| Where | What |
| --- | --- |
| `midifile.tl:1194` | `device.kind == "drums" or device.kind == "sampler"`: both kinds come from extensions |
| `midifile.tl:1260` | reads `note.meta.lyric` (the utau data) to write a lyric event |
| `query.tl:544`, `grep.tl:211`, `pick/project.tl:281` | read `meta.notation.art` (TASK-218) |
| `defaults/views.lua:97` | `paw.layouts.score = "notation"` |
| `takes.tl:181-184`, `track_kinds.lua` (`meta.kind`) | the core stores its own data in `meta`, the space of the extensions |

## 2. The generalizations, ranked

The rank weighs three things: duplicate code that goes, what an
extension can do that it cannot do now, and the class of bugs that goes.
The risk column is the risk of the change itself.

| Rank | Generalization | Removes | Enables | Fixes | Risk |
| --- | --- | --- | --- | --- | --- |
| 1 | K. One contract for kinds and their stored data | 5 planned forms of version and migrate; the reserved list | lazy kinds of every registry; an absent extension handled the same everywhere | "the project does not open or play without the extension" | M |
| 2 | P. Built-ins through the public API | 100 kind branches, 87 reaches into the roll | replace a built-in view or the drawing of a built-in kind | a change of a built-in breaks an extension that used a private path | L |
| 3 | M. Modifier (decided) | `Overrides`; the second stack type of media | an extension adds a MIDI transform that the user can toggle and apply | results that differ between playback, export and the roll | L |
| 4 | T. Template and the Store (decided) | 6 store walks, 3 more planned | project templates, generated templates for every kind | different clash rules in each store | M |
| 5 | L. Linked definitions with overrides | the link code of clips, racks and templates written three times | a linked instance of any kind | an override lost on an update of a definition | M |
| 6 | S. Project sections for extensions | none today | an extension keeps a file in the project folder | data of an extension in one big `meta.json` | S |
| 7 | E. One editor subject for notes | the private `Roll` type in 11 modules | Ex, the language servers, snippets and diagnostics work in notation and in a drum grid | a split of the roll breaks 11 modules | M |
| 8 | Y. One schema of parameters | three schema formats (MCP, chain host, modifier params) | an agent and the language server check any kind's values | a schema that drifts from its struct | S |

The event loop steps (TASK-292 to 297) and the typed API (TASK-96) are
already planned. They do not change rank here. They are in the roadmap.

### 2.1 K. One contract for kinds and their stored data (rank 1)

A kind is a name, an owner, a version of its data, and a codec. The
contract also says what paw does when the owner is absent. The absent rule
is the one that each design wrote again (clip kinds, TASK-298 criterion
10, TASK-75, `media.md` "Without the extension").

```rust
// paw-model (in paw-core until TASK-95.3): no OS, builds for wasm32.
pub struct KindId(Word);                 // `video`, `notation.marks`: the Word of model/custom.rs

pub struct Stored {                      // what the project keeps for any kind
    pub kind: KindId,
    pub version: u32,
    pub data: KindData,                  // the JSON value or the text of model/custom.rs
}

/// What a family of kinds does with a kind whose owner is not loaded.
pub enum Absent {
    Keep,                                // keep the data, use the kept result (clip sound, a bake)
    PassThrough,                         // a split or a modifier: the signal or the notes go through
    Refuse,                              // a template: list it, do not make it
}

pub struct Kinds<S> {                    // one table for each family: clip, track, split, ...
    family: &'static str,
    absent: Absent,
    entries: BTreeMap<KindId, (Owner, S)>,
}
```

```lua
-- Lua face: one function for every family, over paw.registry.
paw.kinds.define("clip", "video", {
  version = 2,
  serialize = function(value) return stored end,        -- to KindData
  deserialize = function(stored, version) return value end, -- migrate older versions here
  describe = function(value) return "3 scenes" end,      -- for K and the picker
  -- the family's own fields: look and editor (clip), create (track), ...
})
```

- **Users today.** Clip kinds (`clip_kinds.tl:99`, `session/document.rs:59`),
  track kinds (`track_kinds.lua:50`), subproject kinds (`nest.tl:172`),
  device kinds (`device.rs:850`). Planned: split kinds (TASK-279), template
  kinds (TASK-298), modifier ops (TASK-75), media ops (`media.md`).
- **What it deletes.** The reserved list as a case of its own
  (`model/custom.rs:30`: the built-ins become entries of the owner
  `paw`). The planned version and migrate code of TASK-298, TASK-75, media
  and TASK-279. The `kind` field in `meta` (`track_kinds.lua`, `meta.kind`).
- **meta.** `paw.meta.define("perform", {version = 1, deserialize = ...})`
  declares the key of an extension in `meta`. The core keeps an undeclared
  key as it does now. `K` names the owner of each key. Core data leaves
  `meta`: `meta.takes` and `meta.kind` become model fields.
- **Out of scope.** A generic Rust trait over the containers of all
  registries. A device factory runs on the engine side with `Rc<dyn
  DeviceFactory>`; a clip kind is a set of ids in the document. They share
  the id type, the owner and the absent rule. Each keeps its container.
- **Risk.** Medium. It touches the save path of clips and tracks. Each
  family moves in its own commit with a round-trip test.

### 2.2 P. Built-ins through the public API (rank 2)

The rule: **a built-in feature registers through the same public `paw.*`
function that an extension uses, and reads other features only through
public functions.** Neovim's runtime works so: `ftplugin`, `syntax` and
the default plugins are Lua files over the same API as a user's plugin.

Today the rule holds for views, commands, keys, components and formats.
It fails in three places:

| Private path | Evidence | Fix |
| --- | --- | --- |
| built-in clip kinds | 100 branches in 30 files; the most in `takes.tl` (20), `scope.tl` (11), `views/arrange_track.tl:557`, `:669-750` (clip drawing) | `midi`, `audio` and `nest` become entries of the clip kinds registry with owner `paw`. Their `look`, `editor`, `takes`, `describe` and `scope` fields hold the code that the branches hold now. TASK-23 B2 ("the arrange view draws custom clips by `look`") is then the same code path for every kind. |
| the piano roll as a hub | 87 `views:get("pianoroll")`; `ex.tl:249` casts to the private type; `type Roll` in `structure.tl:21`, `qf.tl:39`, `lsp/subjects.tl:32`, `locators.tl:10`, `complete.tl:48`, `snippet.tl:51`, `diagnostic.tl:33`, `ex.tl:50`, `frontend/host.tl:32` | Generalization E (2.7): an editor subject. |
| plain tables | `M.registries` in `ext.lua:212`; `lsp/subjects.tl:212`, `vzoom.tl:160`, `help.tl:605`, `paw.layouts` | TASK-208, widened to these four. |

The mechanism has three parts:

1. **Owner `paw`.** Each built-in entry carries the owner `paw.<feature>`
   (`paw.arrange`, `paw.roll`). `:extensions` lists them. An extension
   that puts an entry over a built-in shadows it, and the unload puts the
   built-in back (`registry.tl:14-17` does this now).
2. **A lint.** `tools/privatepath.lua` (in the suite, beside
   `tools/layers.lua`) refuses three things outside the owner module: a
   `views:get("<built-in view>")`, a `kind == "<built-in kind>"`, and the
   name of a bundled extension in `runtime/`. An allow-list that only gets
   shorter, as `tools/layers-allowed.txt`.
3. **Public contracts first.** TASK-132 (`@internal`) marks what stays
   internal. Each contract that a built-in uses to reach another feature
   gets a public form before TASK-105 locks the API.

What stays in the core on purpose, and why:

| Part | Reason |
| --- | --- |
| the audio engine, the plan, the plugin hosts | the audio thread rules: no lock, no allocation, no wait |
| the model, undo, the sync | one truth; one user action is one undo step |
| the key dispatcher and the grammar engine (counts, registers, `.`, operators waiting for a motion) | a key under 100 ms; extensions add operators, motions and text objects to it (`keymap.tl:635-676`) |
| the modes (`keymap.tl:48`) | Neovim does not let a plugin add a mode either. A view gets its own keys through key scopes. |
| the scene, its diff and its encoding | both frontends read it; a view draws cells, and the core makes the scene from them |
| the layout tree of windows | windows, splits and floats are mechanics; views and buffer types are the parts that change |
| the registry itself, the bake scheduler, the project folder codec | the contracts that every extension relies on |

### 2.3 M. Modifier (rank 3, decided)

TASK-75 designs the stack now (`backlog/docs/designs/midi-modifier-stacks.md`
was not on the disk when this review ran). The review gives the fit, not
the design.

```rust
/// One step of a stack. The same struct as the media design's modifier.
pub struct Modifier {
    pub op: KindId,          // `transpose`, `quantize`, `perform.dynamics`
    pub version: u32,        // of the op's meaning; part of every cache key it touches
    pub enabled: bool,       // `~` switches it
    pub params: KindValue,
}

/// An op over one kind of target. Pure: the same input, the same output.
pub trait Op<T> {
    fn apply(&self, params: &KindValue, input: &T, ctx: &OpContext) -> Result<T>;
}
// T = MIDI content (notes, controllers); T = an edit list of a media recipe.
```

```lua
paw.modifiers.define("humanize", {
  target = "midi",
  version = 1,
  apply = function(params, notes, ctx) return notes end,   -- pure; ctx.rng(name) for random ops
  describe = function(params) return "humanize 8 ms" end,
})
```

- **One stack type for MIDI and media.** The media design already has
  `Modifier { op, version, enabled, params }` and Apply. TASK-75 and media
  part M6 must use one struct and one registry (family `modifier` of
  generalization K), with a target (`midi`, `sound`, `picture`).
- **Overrides become built-in modifiers.** `transpose` and `velocity`
  with owner `paw`. `Overrides` (`model/overrides.rs`, `model.rs:626`,
  `sync/clips.rs`, `session/document/clips.rs`) goes.
- **Two modes, one UX.** *Live*: the stack runs at compile time, the
  stored notes do not change (overrides, TASK-75, media). *Applied with
  provenance*: the op writes the notes and keeps what it wrote, so a run
  again changes only what is still as it left it (notation marks,
  perform). The perform design refused a live layer for good reasons, so
  the applied mode stays. Both modes share `~`, order, `K`, Apply and
  the record of the op in the kind registry. The applied mode is a later
  step; the first build is the live mode.
- **Without the extension.** The stack keeps the op and its params. The
  clip plays the last result, kept as a bake (TASK-75 says so). The family
  rule is `Absent::Keep`.
- **The cache.** Live results key on the content stamp of the notes and
  the stack (the compiled events of TASK-7.2 already key on content). A
  Lua op runs under `paw.limit` in the kernel, and its result goes to the
  bake store of `media.md` (M2) when it is slow.
- **Where it meets the devices graph.** Modulators run on the audio
  thread over parameter values; drivers (TASK-86) run on the main thread
  over parameter values. They share with Modifier the UX (a stack in a
  container, `~`, `K`, Apply as `:mod.bake`) and the kind registry (family
  `modulator`). Each keeps its own evaluation. A MIDI device in a chain
  (an arpeggiator in the graph) is a device: it runs live on the track
  and does not show in the piano roll. A clip modifier changes what the
  roll shows.
- **The text form.** A modifier stack is a serial chain of ops with
  params. `chain-syntax` parses exactly that, with a host schema for the
  ops. `:e paw://clip/12/modifiers` can then use the same parser and
  language server as `devices.chain`. A later step.
- **Risk.** Large. The piano roll must show the result and edit the
  source. TASK-75 owns that question.

### 2.4 T. Template and the store (rank 4, decided)

TASK-298 makes one store with the layers project > user > bundled. The
review widens the store to every layered source, and splits the
template kind in two verbs.

```rust
pub trait TemplateKind {
    fn kind(&self) -> &KindId;
    fn version(&self) -> u32;
    fn capture(&self, doc: &Document, at: &Address) -> Result<Stored>;
    /// Make a new object at a place: a track, a rack, a clip. One undo step.
    fn make(&self, doc: &mut Document, data: &Stored, at: &Address) -> Result<Made> { .. }
    /// Put the data onto an object that exists: a device preset, an export preset.
    fn apply(&self, doc: &mut Document, data: &Stored, on: &Address) -> Result<()> { .. }
}
```

```lua
paw.store.layers()        -- project, user, extension, bundled, generated
paw.templates.define("rack", { version = 1, capture = ..., make = ..., generate = function(ctx) end })
paw.templates.list("rack")  -- { name, source, kind, linked? }; the project wins a name clash
```

- **One store, these kinds:** track, group, rack and chain (TASK-298,
  TASK-284), device preset (`fx.lua`, `device_presets.lua`: the plugin's
  own presets are generated templates), export preset (TASK-222.5),
  articulation map (`maps.lua:447`), singer preset (utau), perform style,
  workspace (`workspace.tl:86`).
- **Out of scope.** Themes, keymaps and options. The user's `init.lua` is
  their store, as in Neovim. A layer adds no value there.
- **Presets.** A device preset is a template of kind `device` with the
  verb `apply`. A rack template uses `make`. One picker shows both, as
  the graph design asks ("devices, presets and templates in one
  picker").
- **Risk.** Medium. Each store moves in its own commit. The articulation
  maps and singer presets move last, when their extensions change for
  other reasons.

### 2.5 L. Linked definitions with overrides (rank 5)

```rust
pub struct Linked<D> { pub def: DefId, pub overrides: Vec<Modifier> }
// The definition lives once in the project; each instance keeps its own stack.
```

Users: linked clips (`model/links.rs`, overrides at `model.rs:626`), linked
racks (TASK-279), linked template instances (TASK-298 criterion 5).
Subprojects placed by more than one nest clip are the same idea, and can
move later. The overrides of an instance are a modifier stack, so a
linked clip that plays one semitone up is the shared notes plus a
`transpose` modifier. `:rack.reset`, `:template.update` and `unlink` are
one function each for every kind.

Risk: medium. Linked clips work now; the move keeps their file form
until a release (no compatibility is needed before one).

### 2.6 S. Project sections for extensions (rank 6)

The project folder has a closed list of files (`session/project_files.rs:5-7`:
`project.toml`, `meta.json`, `screen.json`, `media.json`, `master/`,
`tracks/`). The store needs a project layer (`racks/`, `templates/`), and
perform and the articulation maps want files of their own.

```lua
paw.project.section("perform", { version = 1, files = "styles/*.perf.toml" })
-- saved under ext/perform/; kept as files when the extension is absent; collected and diffed
```

Small, and the Store (T) depends on it. Projdiff (TASK-277, TASK-290)
must know the sections.

### 2.7 E. One editor subject for notes (rank 7)

The piano roll is the hub that Ex ranges, the language servers,
snippets, diagnostics, the quickfix list, locators and completion read
(the 11 modules of 2.2). Notation, a drum grid and step input edit the
same notes and cannot take part.

```lua
-- The note editor that has the focus, whatever view it is.
local ed = paw.editor.notes()   -- nil when no note editor has the focus
ed.clip_id, ed:cursor(), ed:selection(), ed:edit(clip_id), ed:key_scope(name)
paw.editor.define("notes", view_name, impl)   -- the piano roll, notation, a drum grid
```

The language server subjects (`lsp/subjects.tl`) use the same idea on
the side of the server. TASK-177 (window instances for every view)
changes the same files, so the two go in one bundle. Risk: medium; many
call sites, each a small change.

### 2.8 Y. One schema of parameters (rank 8)

TASK-96 makes `schemars` schemas for the typed API and paw-mcp. TASK-281
writes a host schema of device kinds. Modifier ops and template kinds
need a schema of their params. Use one `ParamSchema` in Rust that
`schemars` output and the chain host schema both convert to (see the
TASK-281 row of the interim table). Small; it goes in TASK-96.2.

### 2.9 What not to generalize

| Idea | Why not |
| --- | --- |
| One Rust `Registry<T>` trait over device factories, clip kinds, split kinds and the rest | the containers have different threads and lifetimes. Share `KindId`, the owner and the `Absent` rule (K). |
| Extensible modes | Neovim has none either. Key scopes give a view its own keys. The grammar engine stays fast and small. |
| Modulators and drivers evaluated by Modifier | the audio thread rules. Share the UX and the registry only. |
| Themes, keymaps and options in the Store | `init.lua` is the user's store. |
| `DeviceProvider` (TASK-97) widened to "a provider of every kind" | scan, scan again and attach are for devices only. TASK-97 stays as it is. |
| One cache for Rust and Lua derived data | `derived.md` keeps the Rust caches apart for good reasons (other threads, content keys). |
| A generic `Address` trait in Rust | the Lua address schemes registry is enough; the Rust side uses ids. |
| A loader and manifest for each built-in feature ("turn the mixer off") | start-up time, and no user asked. The owner `paw.<feature>` and the lint give the guarantee; a switch can come later. |

## 3. Extensibility audit, with Neovim as the bar

Columns: can an extension **add** one, **replace** the built-in, **wrap**
or change it, **remove** it? "Yes" means through a public API today.

| Part | Add | Replace | Wrap | Remove | API and gap |
| --- | --- | --- | --- | --- | --- |
| views (arrange, mixer, devices, help, pickers) | yes | yes, by shadow | yes (get, then put) | yes, by `remove` | `paw.ui.view` → `ui.tl:347`; the built-ins register the same way (`arrange.tl:2184`, `mixer.lua:398`, `devices.lua:597`, `help.lua:91`, `pick.tl:1427`) |
| the piano roll | yes | **no**: 11 modules use its private type, 87 reach it by name | partly | **no** | gap: E (2.7) |
| track column, status line, ruler | yes | yes | yes | yes | `trackcolumn.tl:115`, `statusline.tl:229`, `ruler.tl:68` |
| marks on clips, headers, strips, devices | yes | no | no | yes | layers, `ui.tl:1903-1908`. A layer draws over a part; it does not replace the part. |
| drawing of a clip body | custom kinds only (TASK-23 B2, not built) | **no** for `midi`, `audio`, `nest` | **no** | **no** | gap: P (2.2), `arrange_track.tl:557-750` |
| lanes, roles, curves | yes | yes | yes | yes | `roles.tl:126`, `curves.tl:363` |
| windows, splits, floats | yes (buffer types) | no | no | no | layout mechanics stay core; buffer types `layout.tl:456` |
| layouts and workspaces | yes | yes | no | no | `paw.layouts` is a plain table (`defaults/views.lua:97`); `workspace.tl:201` is a picker source; gap: TASK-208 widened, T (store) |
| window instances | piano roll only | | | | TASK-177 |
| operators, motions, text objects | yes | yes | yes | yes | `keymap.tl:635-676` |
| modes | no | no | no | no | on purpose (2.2) |
| leader domains | yes | yes | yes | yes | `keymap.group`, `keymap.tl:645` |
| Ex commands, completion | yes | yes | yes | yes | `commands.tl:149`, `:829`; `ex.tl:240`, `:973` |
| themes | colors yes | yes | yes | n/a | `paw.ui.hl`, `paw.ui.theme` (`theme.tl:1-2`); no named color schemes to choose; low value |
| glyphs | options only | no | no | no | `options.tl:129-130`; low value |
| the scene | through views | no | no | no | on purpose: both frontends read it |
| clip kinds | yes | **no** for built-ins | no | no | `clip_kinds.tl:99`; built-ins are reserved (`model/custom.rs:30`); gap: K and P |
| editors of a clip kind | yes (`editor` field) | no for built-ins | no | no | gap: P |
| device kinds | yes (Lua devices, plugin folders) | no | no | yes (`unregister`) | `device.rs:850`; TASK-97 |
| split kinds | planned | | | | TASK-279, TASK-288; gap: K |
| track kinds | yes | yes | yes | yes | `track_kinds.lua:50`; the kind is in `meta.kind` (gap: K) |
| subproject kinds | yes | yes | yes | yes | `nest.tl:172` |
| transport and playhead | commands and keys only | no | no | no | on purpose: the engine owns time |
| the project file and its sections | `meta` only | no | no | no | closed list, `project_files.rs:5-7`; gap: S |
| render and export formats | yes | yes | no | yes | `formats.tl:116`; presets in TASK-222.5 (gap: T) |
| undo | one step for each turn | no | no | no | on purpose; `Document` undo tree |
| hooks and events | yes | n/a | yes | yes | `events.tl:108`, `:199`, `:285` |
| help | yes | yes | no | no | `help.tl:605` is a plain function (gap: TASK-208 widened) |
| the tutor | it is an extension | yes | yes | yes | `extensions/tutor` |
| language server subjects | yes | no | no | no | `lsp/subjects.tl:212` is a plain table (gap: TASK-208 widened) |

Result: paw is near the bar for everything that is not a kind. The
gaps are the built-in kinds, the piano roll, the project folder and four
plain tables.

## 4. How the parts fit together

```text
                       Kinds (K): KindId, Stored {kind, version, data}, Absent rule
                       paw.kinds over paw.registry; the owner `paw` for built-ins
        ┌──────────────┬──────────────┼───────────────┬───────────────┬─────────────┐
   clip kinds     track kinds    split kinds      modifier ops     template kinds   device kinds
   (TASK-23)      (meta.kind→     (TASK-279,      (TASK-75,        (TASK-298)       (TASK-97:
                   model field)    TASK-288)       media M6/M7)                       providers)
                                        │               │                │
                                        │        Modifier (M)       Template (T)
                                        │        stack: live or      capture / make / apply
                                        │        applied; Apply      Store: project > user >
                                        │               │            extension > bundled > generated
                                        │               │                │        │
                                        └──── Linked<D> (L): one definition, instances with
                                              a modifier stack as their overrides
                                              (linked clips, linked racks, linked templates)
                                                                          │
                                              Project sections (S): ext/<name>/, racks/, templates/
```

- **One kind registry?** Yes on the Lua side, and it exists:
  `paw.registry`. Each family is one registry. `paw.kinds` is a thin face
  that adds the version, the codec and the absent rule, and mirrors the
  key into the Rust `Kinds<S>` of the family. TASK-208 finishes the Lua
  side. TASK-97's `DeviceProvider` stays: it is how device kinds appear,
  and each kind it registers is an entry of the family `device`.
- **One versioned serialization contract?** Yes: `Stored { kind,
  version, data }` with `deserialize(stored, version)`. Clip kinds use it
  now. Templates, modifier ops, split kinds, meta keys and project
  sections use the same. The chain host schema has its own version (it is
  a published format outside paw) and lists the kinds by name.
- **Modifier and the devices graph.** The same kind registry and the
  same UX. Each keeps its evaluation: modulators on the audio thread,
  modifiers in the kernel. A rack's instance overrides are a modifier
  stack of parameter sets, through `Linked<D>`.
- **Template and presets.** A preset is a template with the verb
  `apply`. A rack is a template with `make`. One store, one picker.
- **Typed API (TASK-96).** The built-in template kinds capture model data
  (`Track`, `Clip`), not the views of the API, so TASK-96 is not a
  dependency of Template. The schema part (Y) joins them.
- **Event loop (TASK-292 to 297).** Independent. Modifier caches and the
  bake scheduler report to the agenda of S3 and to the quiet state of
  S4, so the tests wait for a modifier result with no time in them.

## 5. The milestones and the generalizations

For each open milestone: the tickets that depend on a generalization,
gain from it, or would be built twice without the right order.

| Milestone | Tickets | Relation | Order |
| --- | --- | --- | --- |
| m-0 browser | TASK-30, 33 | K and the store go into paw-model with no OS calls; the user layer of the store reads through a seam that TASK-33 fills | after TASK-95.3 |
| m-1 platforms | TASK-43, 44 | the store is the one place for data folders | gains; no wait |
| m-2 sections and views | **TASK-222.5** export presets | **built twice** if it writes its own layering | build on the first store slice (bundle B3), or build a list and move it in B3 |
| m-2 | TASK-222.2, .3, .10 | none | as planned |
| m-5 | TASK-3 + 217 | running; the generic `kind` trigger | now |
| m-5 | **TASK-23** clip kinds B2, B3 | **built twice** if B2 draws custom clips on a path beside the built-ins | merge B2 and B3 into bundle B6 (P) |
| m-5 | TASK-23 C1 to C3 (signals), E1 to E5 | gain from K | after B2 |
| m-5 | **TASK-75** Modifier | the design; must share the media struct | design now; build in B5 |
| m-5 | **TASK-10** media M6, M7 | **built twice** without one Modifier struct | after B5 |
| m-5 | TASK-9 perform | the applied mode of Modifier | after owner approval and B5 |
| m-5 | TASK-86 drivers | the modulator UX and registry | after TASK-285 |
| m-5 | TASK-1, 2 WebAssembly | pure modifier ops are the first WebAssembly compute after devices | after TASK-97 |
| m-5 | TASK-214 freeze | a kept bake, store of media M2 | as planned |
| m-5 | TASK-277, 290 projdiff | must diff project sections and kind data | after B3 |
| m-6 | **TASK-105** API lock | **churn** if it locks before K, M, T, E | last, after B7 |
| m-7 | TASK-220, 221 (`groma` curation) | after the moves | last |
| m-8 | TASK-133 (`tools/apidoc.lua` in Teal) | generates the records of `paw.kinds`, `paw.templates`, `paw.modifiers` | before B2's docs or with them |
| m-9 | docs | new pages: about kinds, about non-destructive edits | with each bundle |
| m-10 | see "The re-scoped m-10" | | |
| m-11 | **TASK-135** to 142 notation and utau in Rust | a native extension needs the Rust side of K; notation needs E and the applied mode of M | **design after B2, B5, B7** |
| m-12 | TASK-145 to 149, 158, 291 | none; the event loop steps follow | as planned |
| m-13 | window | paused; the scene does not change | none |
| m-14 | TASK-237 audio clip view | an editor of the built-in kind `audio`: one more user of P | after B6 |
| m-14 | TASK-234 warp, slices | media modifiers | after B5 and TASK-10 |
| m-14 | TASK-235 ripple edits | addresses and selections; no new generic part | as planned |
| m-14 | TASK-228.3 SysEx in clips | the model, not meta | as planned |
| m-14 | TASK-231.1 OSC port | shares the OSC code of TASK-23 C2 | after C2 |
| m-14 | TASK-232.1 MIDI learn | the triggers registry (TASK-208) | after TASK-208 |
| m-15 | **TASK-273** arrange content | changes clip drawing, as B6 does | before B6, or merge into it |
| m-16 | TASK-279, 281 | running; interim changes | now |
| m-16 | TASK-280, 282, 283, 286, 287 | none | as planned |
| m-16 | **TASK-284** racks and templates | **built twice** without T and L | after B3, B4 and TASK-298 |
| m-16 | **TASK-285** modulators | the registry and UX of M | after B5 is designed; build the engine part freely |
| m-16 | TASK-288 extension split kinds | K | after B2 |
| m-16 | **TASK-298** Template | the store and the trait | split: B3 (store) then B8 (kinds, linked, extension) |

## 6. The re-scoped m-10

### 6.1 Existing tickets

| Ticket | Decision |
| --- | --- |
| TASK-95.1, 95.3 paw-model | Keep. B2 puts `KindId`, `Stored` and `Kinds<S>` in `model/`. Run B2 after TASK-95.1 merges (the same files). |
| TASK-96, 96.2 typed API | Keep. Add the shared `ParamSchema` (Y) to TASK-96.2. |
| TASK-97 DeviceProvider | Keep. Add: each kind that a provider registers is an entry of the family `device` with owner, so an unload and `K` work as for other kinds. |
| TASK-98 lints | Keep (running). |
| TASK-99 Shared in parts | Keep. |
| TASK-132 `@internal` | Change: also give a public form to each contract that one built-in uses to reach another (the editor subject, the clip kind spec), before TASK-105. |
| TASK-177 window instances | Merge into B7 (the same view files as the editor subject). |
| TASK-206 untangle | Keep last. |
| TASK-208 last registries | Keep (running). Widen: language server subjects, zoom, help pages and `paw.layouts` become registries. Use the shadow stack for options. |
| TASK-215 | Keep (running). |
| TASK-218 | Change: criteria 1 to 3 go to the TASK-3 + 217 branch (running). Keep criteria 5 to 7 (`package.loaded`). Add the rest of "the core knows no extension": `midifile.tl:1194` (a device kind field `drum_channel` in place of two names), `midifile.tl:1260` (see question 9), `defaults/views.lua:97`. |
| TASK-260 traces | Keep, low. |
| TASK-292 to 297 event loop | Keep. They run in their own lane. |

### 6.2 New bundles

Each bundle is one agent, leaves paw working, and has tests and docs in
the same commits.

| Bundle | Work | Size | Depends on | Graph order |
| --- | --- | --- | --- | --- |
| B1 | **Design note "kinds"** (2.1 of this review, made exact): the families, the absent rule of each, the `meta` keys, the Lua face. Read beside the TASK-75 design. | S | owner answers Q1 to Q4 | now, in parallel with TASK-279 |
| B2 | **Kinds (K)**: `KindId`, `Stored`, `Absent`, `Kinds<S>`; `paw.kinds`; clip, track and subproject kinds on it; `meta.kind` and `meta.takes` become model fields; `paw.meta.define`; the reserved list becomes entries of owner `paw` (data only, no drawing yet). | L | B1, TASK-95.1, TASK-208 | after TASK-279 merges (both touch `model/`) |
| B3 | **Project sections and the Store (S, first part of T)**: `ext/<name>/` and `racks/`, `templates/` in the folder layout; `paw.store` with five layers and one clash rule; device presets and export presets move on it (TASK-222.5 lands here or moves here). | M | B2 | after TASK-279 |
| B4 | **Linked definitions (L)**: `Linked<D>` from TASK-279's module; linked clips on it; `:link.update`, `:link.reset`, `:unlink` generic. Overrides stay as data until B5. | M | TASK-279, B2 | after TASK-279 |
| B5 | **Modifier core (M)**: one `Modifier` struct for MIDI and media; family `modifier`; `transpose` and `velocity` built-in; `Overrides` goes; the sync evaluates live stacks with content keys; `paw.modifiers.define`; `~`, `K`, Apply; a kept result for an absent op. The applied mode is a later ticket of m-5. | L | TASK-75 approved, B2, B4 | independent of TASK-280 to 283 |
| B6 | **Built-in clip kinds through the public API (P part 1)**: `midi`, `audio`, `nest` as full entries (`look`, `editor`, `takes`, `scope`, `describe`); the 100 branches move into them; TASK-23 B2 and B3 (custom clips drawn by `look`, track kind fields) on the same path; `tools/privatepath.lua` with its allow-list. Coordinate with TASK-273. | L | B2 | independent |
| B7 | **The editor subject and window instances (E, P part 2)**: `paw.editor.notes()`; the 87 reaches and the 11 type imports go; TASK-177 (every view on window instances, the copy code of `layout.tl` goes). | L | TASK-132 (the public forms) | independent |
| B8 | **TASK-298 Template, rest**: `TemplateKind` with `capture`, `make`, `apply`; template kinds of extensions with their codec; generated templates; the templates extension moves into paw; linked instances through B4. Then TASK-284 racks. | L | B3, B4, TASK-279 | after TASK-279 (as the owner set) |

### 6.3 The roadmap across milestones

```text
Phase 0 (now)    TASK-215+208 │ TASK-98 │ TASK-3+217(+218 marks) │ TASK-279 │ TASK-281 │ web 93/107/109
                      │
Phase 1 (design) B1 kinds note ─┐   TASK-75 design (approve) ─┐   TASK-95.1 │ TASK-292, 293 (event loop)
                                │                              │
Phase 2          B2 Kinds ──────┼──────────────┐               │   TASK-280 engine │ TASK-282 view
                 (after 279,    │              │               │   TASK-96 typed API │ TASK-294 alone
                  95.1, 208)    │              │               │
Phase 3          B3 Store ── TASK-222.5 │ B4 Linked ── B5 Modifier core │ B6 built-in kinds │ B7 editor subject
                      │                      │           │                  (with TASK-23 B2/B3)  (with TASK-177)
Phase 4          B8 Template (TASK-298) ── TASK-284 racks │ TASK-285 modulators │ media M6/M7 │ TASK-283 keys
                 TASK-288 split kinds │ TASK-237 audio clip view │ TASK-95.3 paw-model │ TASK-295..297
Phase 5          perform (TASK-9), applied mode of Modifier │ drivers (TASK-86) │ m-11 design (TASK-135)
Phase 6          TASK-132 done → TASK-105 API lock → TASK-206 untangle → TASK-221 Groma
```

- **Critical path:** TASK-279 → B2 → B3 → B8 → TASK-284. A second path:
  TASK-75 approval → B5 → media M6/M7 and perform. A third: B6 and B7 →
  TASK-132 → TASK-105.
- **In parallel:** the event loop lane (TASK-292 to 297, S3 alone in its
  batch), the typed API lane (TASK-96, 96.2), the devices graph lane
  (TASK-280, 282, 283, 286, 287), the web lane. B6 and B7 touch different
  files and can run together. B3 and B4 can run together.
- **Before the graph work** (before TASK-279 merges): only design (B1,
  TASK-75) and the running bundles. **After TASK-279:** B2, B3, B4, B8.
  B5, B6 and B7 do not depend on the graph.
- **Owner decisions needed:** before B1 (questions 1 to 4), before B5
  (TASK-75's own questions and question 5), before B6 (question 2),
  before phase 5 (perform approval, question 6).

## 7. Questions for the owner

| # | Question | Recommendation |
| --- | --- | --- |
| 1 | Is "Kinds" (one contract: name, owner, version, codec, absent rule) the base under Template and Modifier, and does it go first? | Yes. Both decided traits need it, and five designs wrote their own form of it. |
| 2 | Do the built-in clip kinds (`midi`, `audio`, `nest`) become entries of the registry with owner `paw`, so that an extension can replace how one draws or opens? | Yes. It is the main gap to the Neovim bar, and TASK-23 B2 needs the same path for custom kinds. |
| 3 | Can an extension keep files in the project folder (`ext/<name>/`), kept as they are when it is absent? | Yes. The store needs `racks/` and `templates/`; perform and articulations want files. |
| 4 | Do `meta.kind` (track kinds) and `meta.takes` move from `meta` to model fields? | Yes. `meta` is the space of the extensions; the core reads both. |
| 5 | One `Modifier` struct and registry for MIDI stacks and media recipes, with `Overrides` as built-in modifiers? | Yes. The media design has the struct already; two stacks would be built twice. |
| 6 | Is "applied with provenance" (notation marks, perform) a mode of Modifier with the same UX, or a separate mechanism? | A mode of Modifier, built after the live mode. The perform design keeps written MIDI; the user gets one `~`, `K` and Apply. |
| 7 | Are device presets, export presets, articulation maps, singer presets, perform styles and workspaces template kinds in one store? | Yes, in that order. Themes, keymaps and options stay in `init.lua`. |
| 8 | Do modulators (TASK-285) and drivers (TASK-86) share the registry and UX of Modifier, and keep their own evaluation? | Yes. The audio thread rules forbid a shared evaluation. |
| 9 | `meta.lyric`: the core reads it to write MIDI files (`midifile.tl:1260`). A model field of a note, or a declared shared key? | A model field (`Note.lyric`, as `attr`), because MIDI files carry lyrics and the core writes them. |
| 10 | Built-in features as extensions with a loader and a switch ("turn the mixer off")? | Not now. The owner `paw.<feature>`, shadowing and the lint give the guarantee. A switch can come when a user asks. |
| 11 | Modes stay closed (normal, visual, operator, insert, command)? | Yes, as in Neovim. |
| 12 | TASK-222.5 (export presets) waits for the store (B3), or builds a list now that moves into B3? | Build the built-in list now with no layers; add the user and project layers in B3. No second layering code. |
| 13 | The m-11 design (notation and utau in Rust) waits for B2, B5 and B7? | Yes. A native extension needs the Rust side of kinds, and notation needs the editor subject and the applied mode. |
| 14 | A modifier stack as text through `chain-syntax` (`:e paw://clip/12/modifiers`)? | Yes, later, after B5. It reuses the parser, the formatter and the language server. |
