# Architecture plan: one model for the six designs, and the corrected milestones

Status: plan, version 2 (2026-11-23, after the owner's answers). No
tracked file changed. Nothing was built. No Backlog command that writes
was run. Part "Version 2" below is the authority. The numbered
sections after it are version 1 and stay in force only where version 2
says nothing.

Internal text (ASD-STE100). Date: 2026-11-23. Base: main at deb79a0f.
Writer: the lead architect.

The owner asked for "a joint architectural refinement to figure out how
we need to correct our milestones". The plan joins six designs of
2026-11-23:

| Short name | File | Subject |
| --- | --- | --- |
| M10 | `m10-generalization-review.md` | Kinds, built-ins through the public API, Modifier, Template, store, `Linked<D>`, project sections, editor subject, one parameter schema |
| MOD | `midi-modifier-stacks.md` | The modifier stack (TASK-75) |
| EVL | `event-loop-review.md` | One turn, one clock rule, `Upkeep`, quiet in the kernel (TASK-292 to 297) |
| DG | `devices-graph.md` | The devices graph and the chain language (m-16) |
| RUST | `rust-architecture.md` | The idiomatic Rust shapes of the four designs above |
| CONT | `containers.md` | `Track` generalized in place: lanes, optional mix, producers |

Each of the six designs gets one line at its top: "Superseded where it
differs by `architecture-plan.md` (2026-11-23)". Where this plan says
nothing, the design stays in force.

Facts read for this plan, beside the six designs:

- The Backlog: all milestones and all open tasks (`backlog/tasks`).
- TASK-279 as built: branch `worktree-agent-a5603cc7cf5901939`, commit
  `3ac0c8b3` (`model/graph.rs`, `model/linked.rs`, `model/racks.rs`,
  `session/document/graph.rs`, `runtime/lua/paw/graph.tl`). It lands in
  batch 19 as it is.
- TASK-281 as built: branch `worktree-agent-ad8bc9b308ad8837e`, commit
  `303d0c54` (`crates/chain-syntax`, on `winnow`). Its lexer keeps each
  comment and blank line as trivia of the next item, with a span for
  each line, and it recovers line by line.

## Version 2: the owner's answers

Version 2. Date: 2026-11-23. Writer: the lead architect. Source: the
owner's answers of seven rounds,
[owner-answers-2026-11-23.md](owner-answers-2026-11-23.md). The answers
are the authority. Where this part and the rest of the plan disagree,
this part is correct. The sections after it are version 1. Each section
of version 1 that this part replaces has a line at its top that says
so. The rows of the conflict table (section 1) that version 2 does not
name stay in force.

Nothing was built. No tracked file changed. No Backlog command that
writes was run.

### V2.0 What changed, in short

| # | Version 1 | Version 2 (owner) | Round |
| --- | --- | --- | --- |
| 1 | `Track` stays the one container, generalized in place | The **lane** is the first-class unit and the truth. The container is a named folder of lanes that nests. Its user word is **part** | 1.5, 7.1 |
| 2 | Lane 0 takes every clip kind | A lane holds **one** kind of clip. A lane is typed: a base kind plus properties (channels, lyrics present, rig, frame rate) | 1.6, 3.E |
| 3 | A lane's kind is a stream kind (K3) | A lane names its clip kind. Its type is the stream that the clip kind gives, plus properties. Ports declare the type that they need. paw inserts a converter, or refuses with a message that names the missing property | 3.E |
| 4 | `Mix` is an optional field of a track (C4) | A mix is the live audio part of the graph: strips, buses, sends and master are **nodes**. A strip is a free node. A new audio lane gets its own strip by default. Two lanes can share one strip | 3.A, 3.B |
| 5 | One graph for each track (`Track.graph`, then `Mix.graph`) | **One project graph**, composed from the graph of each part. The user can view, edit and export the graph of one part | 2.2 |
| 6 | Producer branches in the chain document (`produce`) | The graph has two kinds of arrows: **stored-lane** arrows and **live-signal** arrows. **Render** turns any signal into a lane (freeze, print, a stack, a derived lane) | 3.A |
| 7 | "Apply" | "**Render**", with **provenance** (a recipe and a hash of the source). paw offers "re-derive as a new take". `:lane.detach` cuts the link. Only a prefix of a stack renders | 2.5, 3.D, 5.2, 5.3 |
| 8 | Takes become lanes with `role: Take` (P1) | **Takes for every lane kind.** Source or derived is a property of each **take**. A **comp** is source data of the lane. Re-bake the takes that the comp uses first | 1.4, 4.1 to 4.5 |
| 9 | Automation stays a list on the track (`automation`) | Automation is a lane of kind `curve` that feeds a node parameter | 3.B |
| 10 | Mute, solo, arm, fader on the strip | **Arm** on source lanes of a kind that records. **Mute** on any lane and any node. **Solo** on a strip or a bus | 2.1, 3.B |
| 11 | Producers in tiers 1 to 3 | Tiers **live**, **kernel**, **bake**. The producer reports the span that it covers. Per-note producer controls live on the source notes, owned by the producer | 3.C |
| 12 | Outside processes "in bake jobs" (proposed) | Outside programs run **only in bake jobs**, never when a project opens. paw asks one time for each program in a project. Jobs run in a sandbox, in one queue (`:bakes`) | 4.6 to 4.8 |
| 13 | One `Modifier` stack on a clip, lanes later | **One stack type** on a clip or on a lane. A lane stack runs after the stack of each clip | 5.1 |
| 14 | Template kinds `track`, `group`, `rack`, `device`, `export`, `stack`, `workspace` | Kinds **project, part, lane, rack (graph), stack, export**. The **shape** by default, a flag keeps the **content**. Insert copies, or links with overrides. A linked definition is copied into the project | 6.1 to 6.3 |
| 15 | Store: three layers plus generated | **Four layers**: project, user, extension, bundled. `templates/<kind>/` in each | 6.4 |
| 16 | Project folder: `tracks/<name>/` | A folder for each **part** (nested), a subfolder for each **lane**, `devices.chain` for each part, `ext/<name>/` | 6.5 |
| 17 | Rule 4: "MIDI is the truth" | "**Lanes are the truth.** Source lanes hold the data. A derived lane is a recipe plus its kept result. A project opens and plays without the extension or program that made a derived lane." | 7.2 |
| 18 | Questions Q1 to Q7 open | All answered. m-3 and m-4 close. The architecture work runs beside m-2 and m-9 | 7.3 |
| 19 | Video: proposed | A monitor view with half blocks or kitty graphics. Thumbnails in the arrange view where images work. Phase 5 or later | 7.4 |
| 20 | The roll is the editor of MIDI | The piano roll is the **default** MIDI editor, **not the only** one. Its UX gets its own design | 5.4 |

### V2.1 The model in one picture

```text
 Project = the root part                 The project graph = the union
 ├─ part "Strings"  (a folder; nests)    of the part graphs (composed,
 │   ├─ part "Violin I"                  not saved). Arrows:
 │   │   ├─ lane "Notes"  midi           ──▶ live signal (engine)
 │   │   │    takes A B (source), comp   ══▶ stored lane (bake, render)
 │   │   ├─ lane "Words"  midi+lyrics    ··▶ curve feeds a parameter
 │   │   ├─ lane "Sung"   audio ch=1
 │   │   │    takes s1 s2 (derived)
 │   │   ├─ lane "Vol"    curve          graph of part "Violin I":
 │   │   └─ graph ─────────────────────▶   Words ──▶ [singer] ══▶ Sung
 │   └─ graph: [bus "Strings"]             Notes ──▶ (strip "Vln")
 └─ graph: [master]                        Sung  ──▶ (strip "Vln")
                                           Vol   ··▶ (strip "Vln").gain
 Lane: the truth. One clip kind.           (strip "Vln") ──▶ [bus]
 Take: source or derived. Comp: source.    [bus "Strings"] ──▶ [master]
 Render: any arrow ──▶ a new lane or take, with provenance.
```

Words, one for each thing (user words first):

| Word | Meaning |
| --- | --- |
| part | A named folder of lanes. Parts nest. A part owns the nodes of its graph. The project is the root part. |
| lane | A typed row of time. It holds clips of one kind, in takes. It is the unit of truth. |
| take | One version of a lane's content. Its role is source or derived. |
| comp | Ranges that each name a take, with crossfades for audio. Source data of the lane. |
| clip | A piece of content on a take, of the lane's clip kind. It has a stack. |
| stack | A list of modifiers on a clip or on a lane. It keeps the type. |
| graph | The nodes and arrows of a part (the part graph), or of all parts (the project graph). |
| node | A strip, a bus, a send, the master, a VCA, a producer, a converter, or an input or output. |
| strip | A node with a fader, a pan and inserts. It sums its inputs. |
| inserts | The devices and splits inside a strip: the chain of TASK-279. |
| producer | A node that makes a stream of one type from streams. Tier live, kernel or bake. |
| converter | A producer with one input and one output that paw inserts for a gap of type. |
| render | Turn a signal, a stack prefix or a derived take into a lane or a source take, with provenance. |
| provenance | The recipe and the hash of the source that made a take. |
| bake | The kept result of a derived take. paw makes it again when its source changes. |

### V2.2 The core types in Rust

All types are in `paw-core/src/model/` and later in `paw-model` (no OS
call, no `mlua`). Ids are `NonZeroU64` newtypes. Files keep the numbers.
Data that the user edits is behind `Arc`, so an edit copies only the
part that changes (as today).

```rust
// ── ids (serde: a number) ───────────────────────────────────────────
pub struct PartId(NonZeroU64);  pub struct LaneId(NonZeroU64);
pub struct TakeId(NonZeroU64);  pub struct ClipId(NonZeroU64);
pub struct NodeId(NonZeroU64);  pub struct DeviceId(NonZeroU64);

// ── the tree ────────────────────────────────────────────────────────
pub struct Project {
    pub root: PartId,                 // the root part holds the master
    pub parts: Parts,                 // all parts, in screen order
    pub nests: BTreeMap<NestId, Arc<Nest>>,
    pub defs: Defs,                   // linked definitions, copied in
    pub sections: Sections,           // ext/<name>/, kept as bytes
    pub tempo: Arc<TempoMap>,
    pub meta: Meta,
}
pub struct Parts(Vec<Arc<Part>>);     // fn children, ancestors, check
pub struct Part {
    pub id: PartId,
    pub name: String,
    pub parent: Option<PartId>,       // None only for a root part
    pub kind: Option<KindId<PartFamily>>,
    pub lanes: Vec<Arc<Lane>>,        // in screen order
    pub graph: Arc<PartGraph>,        // the nodes that this part owns
    pub cues: Clips,                  // the launcher (unchanged)
    pub nest: Option<NestId>,
    pub link: Option<Linked<PartDef>>,
    pub meta: Meta,
}

// ── types of streams ────────────────────────────────────────────────
pub struct StreamType {               // a base kind plus properties
    pub base: KindId<StreamFamily>,   // midi, audio, curve, video, ...
    pub props: Props,
}
pub struct Props(BTreeMap<Word, Prop>); // checked by the base kind
pub enum Prop { Flag(bool), Count(u32), Ratio(u32, u32), Word(Word) }

// ── lanes, takes, comps, clips ──────────────────────────────────────
pub struct Lane {
    pub id: LaneId,
    pub name: String,
    pub clips: KindId<ClipFamily>,    // the one kind of clip it holds
    pub props: Props,                 // channels, lyrics, rig, rate
    pub takes: Vec<Arc<Take>>,
    pub active: TakeId,
    pub comp: Option<Arc<Comp>>,      // None: the active take plays
    pub stack: Stack,                 // after the stack of each clip
    pub mute: bool,
    pub arm: Option<Arm>,             // only if the kind records
    pub meta: Meta,
}
pub struct Take {
    pub id: TakeId,
    pub name: String,
    pub role: Role,
    pub clips: Clips,
}
pub enum Role {
    Source { from: Option<Provenance> }, // the truth; Some after render
    Derived { made: Provenance, kept: Kept }, // a bake; never edited
}
pub struct Provenance {
    pub recipe: Arc<Recipe>,
    pub source: SourceHash,           // BLAKE3 of the inputs, 128 bits
    pub seed: Option<u64>,
}
pub struct Recipe {                   // its text form is chain text
    pub producer: KindId<ProducerFamily>,
    pub version: Version,
    pub params: Stored<ProducerFamily>,
    pub inputs: Vec<PortRef>,
    pub stack: Option<Stack>,         // a rendered stack prefix
}
pub struct Kept { pub files: Vec<RelPath>, pub span: Span }
pub struct Comp { pub ranges: Vec<CompRange> }
pub struct CompRange {
    pub span: Span,
    pub take: TakeId,
    pub fade: Option<Fade>,           // audio only
}
pub struct Arm { pub input: Input, pub monitor: bool }
pub struct Clip {
    pub id: ClipId,
    pub at: Pos,
    pub len: Len,
    pub content: ClipContent,         // of the lane's clip kind
    pub link: Option<Linked<NotesDef>>,
    pub stack: Stack,
}
pub struct Stack(Vec<Modifier>);      // one type on a clip or a lane

// ── the graph ───────────────────────────────────────────────────────
pub struct PartGraph {
    pub nodes: BTreeMap<NodeId, Node>,
    pub wires: Vec<Wire>,             // each wire ends in this part
}
pub struct Node {
    pub id: NodeId,
    pub name: String,
    pub mute: bool,
    pub body: Body,
}
pub enum Body {
    Strip(Strip),                     // sums its inputs; fader, pan
    Bus(Strip),                       // a strip that lanes do not feed
    Master(Strip),                    // one in each root part
    Send(Send),                       // level, pre or post
    Vca(Vca),                         // a control output to gains
    Producer(Producer),               // kind, tier, params
    Converter(Producer),              // inserted by paw for a type gap
    Io(Io),                           // audio or MIDI in or out
}
pub struct Strip {
    pub gain_db: f64,
    pub pan: f64,
    pub solo: bool,
    pub inserts: Arc<Chain>,          // devices and splits (TASK-279)
}
pub struct Producer {
    pub kind: KindId<ProducerFamily>, // tier and ports from the kind
    pub params: Stored<ProducerFamily>,
    pub seed: Option<u64>,
}
pub struct Wire { pub from: PortRef, pub to: PortRef, pub arrow: Arrow }
pub enum Arrow { Live, Store }        // Store always ends at a lane
pub struct PortRef { pub end: End, pub port: Word }
pub enum End { Lane(LaneId), Node(NodeId), Param(NodeId, ParamKey) }
pub struct PortSpec {                 // declared by a kind
    pub port: Word,
    pub out: bool,
    pub ty: StreamType,               // the properties it needs
    pub main: bool,
}
pub enum Tier { Live, Kernel, Bake }

/// The built TASK-279 `Graph` (a tree of splits), renamed: the inside
/// of a strip, and the body of a rack.
pub struct Chain { pub root: Split, pub taps: Vec<Tap> }

/// Not saved. Made again for the parts that changed (`Arc::ptr_eq`).
pub struct ProjectGraph { /* nodes, wires, order, port types */ }
pub fn compose(p: &Project, was: Option<&ProjectGraph>)
    -> Result<Arc<ProjectGraph>, Vec<GraphError>>;

/// A handle of the API. `paw.graph.of(owner)`, `paw.chain.of(owner)`.
pub enum OwnerRef {
    Part(PartId), Lane(LaneId), Node(NodeId), Clip(ClipId),
}
```

Notes on the shapes:

- **No trait objects in the model.** `Body` is a closed `enum` of the
  node roles that the kernel must know. Open behavior comes from kinds:
  `KindId<ProducerFamily>` and `KindId<StreamFamily>` resolve in
  `Kinds<F, S>` (plan K6). A converter is a producer kind with one
  input and one output and the flag `converts`.
- **`Role` on the take, not on the lane** (round 4.1). A derived lane is
  a lane that a `Store` wire feeds. Its takes are `Derived` until the
  user renders one. A comp can pick from either.
- **`Kept` holds no state of freshness.** Stale and absent are computed:
  stale when `made.source` differs from the hash of the inputs now;
  absent when the producer kind has no entry. So a git merge or a
  missing extension never leaves a wrong flag in a file.
- **A wire is stored in the part that owns its end** (`to`). A wire from
  another part names a project-wide id. In the text of one part (an
  export), such a wire is an outside reference `@"Strings/Violin I/Notes"`
  (CL2). So one part graph is a whole document, and the project graph
  is the union.
- **The project is the root part.** Today's `Project.master` (a track
  with id 0) becomes the `Master` node of the root part. A nest keeps
  its own root part and master.
- **Per-note producer controls** (round 3.C) are a field of `Note`:
  `ctl: BTreeMap<KindId<ProducerFamily>, Stored<ProducerFamily>>`.
  paw keeps the bytes when the producer is absent. The producer's editor
  edits them.

### V2.3 The families (replaces table 2.3)

| Family | `ABSENT` | Built-in entries (owner `paw`) | Bundle |
| --- | --- | --- | --- |
| `StreamFamily` | `Keep`: the lane keeps its clips, plays nothing new | `midi`, `audio`, `curve`, `state`; later `video`, `text`, `keyframes`. Each declares its properties (a `ParamSchema`), its time base and whether it records | A2 |
| `ClipFamily` | `Keep`: the kept sound plays | `midi`, `audio`, `nest`, `curve`. Each names the stream it gives (`gives`) | A2 |
| `PartFamily` | `Keep`: a label and defaults | none (today's track kinds become part kinds of extensions) | A2 |
| `MetaFamily` | `Keep` | none | A2 |
| `SplitFamily` | `PassThrough`: the first branch in series | `chain`, `layer`, `band`, `ms`, `lr`, `key`, `vel`, `select`, `outs` | A1 |
| `ModifierFamily` | `PassThrough`: the entry waits | `transpose`, `velocity`, then the kinds of M2 | M1 |
| `ModulatorFamily` | `PassThrough`: the base value | `macro`, `lfo`, `follower`, `midi`, `random` | TASK-285 |
| `ProducerFamily` | `Keep`: the last kept result, with an "absent" mark | `render` (tier bake), the built-in converters (tier live: `mono`, `stereo`) | RD, TY |
| `TemplateFamily` | `Refuse`: list it, do not make it | `project`, `part`, `lane`, `rack`, `stack`, `export` | B3, B8 |
| `DeviceFamily` | `PassThrough`: bypass, values kept | the built-in devices | TASK-97 |

Each producer kind also declares its `Tier` and its ports (`PortSpec`).
A device is a live producer: an instrument has a `midi` input and an
`audio` output, as today.

### V2.4 What the engine sees

The engine sees no part, lane, take or comp. The sync composes the
project graph and compiles its live part:

```text
 Project ─compose─▶ ProjectGraph ─plan─▶ processors in a fixed order
   (main thread; per part,              ProcessorSlot = one Strip, Bus
    Arc::ptr_eq skips the parts         or Master node: its inputs (the
    that did not change)                played events and audio of the
                                        lanes that feed it, other slots,
                                        sends), its inserts (GraphPlan,
                                        TASK-280), its fader and pan,
                                        and the ramps of curve lanes.
```

- A lane that feeds a strip gives the strip its played content: the comp
  or the active take, after the clip stacks and the lane stack, as
  compiled events (MIDI) or clip players (audio). This is what
  `build_clips` does today for one list.
- A strip with two lanes gets two inputs. A lane that feeds no strip is
  silent, and `K` says so.
- A `Store` wire is not live. The bake scheduler reads it. The engine
  never waits for a producer.
- Tier kernel producers run in the turn (plan M4), tier bake producers
  on the bake scheduler (plan M5).
- `Msg::SetGraph { slot, plan }` names a `ProcessorSlot` (plan L8). Today
  each track is one slot.
- The audio thread rules do not change. `compose` and `plan` run on the
  main thread. The engine gets finished plans through `rtrb`.
- The order of processors is a fixed order of the DAG, so a render gives
  the same bytes on 1 or 16 threads (scenario S6).

### V2.5 Today's track, with nothing lost

| Today (`crates/paw-core/src/model.rs:121-193`) | Version 2 |
| --- | --- |
| `Track` | `Part` with one lane for each clip kind that it holds, and a `Strip` node in its graph |
| `Track.clips` | One lane for each clip kind; each with one source take. A track with MIDI and audio clips gets two lanes, both wired to its strip (the strip has a `midi` and an `audio` input, as the engine mixes today) |
| `clip.meta.takes` | Takes of the lane (`Role::Source`). The piece of each take that `takes.tl` comps becomes a `Comp` |
| `Track.lanes` (automation, `model.rs:1160`) | Lanes of base `curve` (`Target` `Volume`, `Pan`, `Param`), each with a `Live` wire to `Param(strip, key)`. `Target::State` becomes a lane of base `state` |
| `volume`, `pan`, `solo`, `devices`, `attr_map` | The `Strip` node: `gain_db`, `pan`, `solo`, `inserts` (the chain; `devices` was a series) |
| `mute` | `Node.mute` of the strip |
| `armed`, `input`, `monitor`, `midi_input` | `Lane.arm` of the lanes that record |
| `output` | A `Live` wire from the strip to the parent bus or the master |
| `sends` | `Send` nodes with a wire from the strip and to the target |
| `midi_output` | An `Io` node and a wire from the strip's `midi` output |
| `automation` (`AutoMode`) | A field of the strip (the mode of its curve lanes) |
| `cues` | `Part.cues`, unchanged |
| `meta.group`, a group | `Part.parent`; the group part has a `Bus` node, and the strips of its children feed it by default |
| A folder that does not sum | A part with no bus (new) |
| `meta.vca`, a VCA | A `Vca` node with `Live` control wires to the gains of its members |
| `meta.kind` | `Part.kind` |
| `meta.frozen` (freeze) | A render with "replace": a lane of base `audio` with a source take whose provenance names the instrument; the instrument is bypassed. Undo or `:render.undo` brings back the wire |
| `Project.master` (id 0) | The `Master` node of the root part |
| `Track.nest`, a nest | `Part.nest`; a nest has a root part with its own master |
| `source`, `origin`, `chain_source`, `chain_origin` | `Part.link: Linked<PartDef>`, and `Strip.inserts` as a linked rack |
| `meta` | `Part.meta`, `Lane.meta`, `Clip.meta`, for extensions |

The null test of the move: each project of the test corpus renders the
same bits before and after (as plan C4 asked).

### V2.6 The files

```text
song/
├── project.toml          name, tempo, meter, key, the order of the parts
├── devices.chain         the graph of the root part (the master, buses)
├── parts/
│   └── Strings/          one folder for each part; parts nest
│       ├── part.json     name, kind, color, meta, the order of lanes
│       ├── devices.chain the graph of this part (chain language 2)
│       ├── lanes/
│       │   └── Notes/    one folder for each lane
│       │       ├── lane.json   clip kind, props, takes, active,
│       │       │               comp, stack, mute, arm
│       │       └── takes/A/    clip files of take A, take.json
│       │                       (role, provenance, kept files)
│       └── parts/Violin I/     a child part, the same shape
├── linked/<kind>/        linked definitions (notes, racks, parts)
├── templates/<kind>/     the project layer of the store
├── ext/<name>/           files of an extension, kept as bytes
├── media/                sound files; media/baked/ kept results
├── nests/<name>/         as today, with parts/ in place of tracks/
└── unused/               as today
```

- `devices.chain` holds the nodes of the part, their parameters (fader,
  pan, inserts) and the wires that end in the part. The lanes, takes and
  clips are not in it. The text names a lane only as an end of a wire.
- Clip files stay as today (`.midi2`, custom clip files). A take folder
  replaces `clips/`.
- `racks.json` (TASK-279) moves to `linked/rack/` with bundle B8.
- No compatibility before a release (ADR 0008). Each step below reads
  the files of the step before it and writes its own.

### V2.7 The migration, in steps that each keep the suite green

The order puts the cheap and mechanical steps first and the step with
the most risk (the mix as nodes) after the parts that it needs. Each
step is one bundle, with its tests and docs in the same commits.

| Step | Bundle | What moves | Risk | How the risk gets lower |
| --- | --- | --- | --- | --- |
| 0 | R19, then A1 | TASK-279 lands as built. A1 renames its `Graph` to `Chain` and `paw.graph` to `paw.chain`, makes it owner-free, adds the kinds core and typed ids | Low | Pure Rust model; the TASK-279 tests keep their keys |
| 1 | W1 | The word: `Track` to `Part` in Rust, `paw.api`, Teal types, Ex commands (`:track.*` to `:part.*`, 28 commands, 11 API functions), files (`tracks/` to `parts/`, `track.json` to `part.json`), messages and the user docs | Medium: wide, not deep. 4881 hits in 158 Rust files, 329 Lua and Teal files, 205 Markdown files, 163 test files, 15 GIFs | Alone in its batch. Commits by layer, each green: Rust (the compiler finds each use), files, `paw.api` and Teal (`tlcheck`), runtime and extensions (the suite), commands and keys, docs and tutor. GIFs in W1g |
| 2 | A2 | `Part.kind`, `Part.parent` from `meta`; `Note.lyric`; the families with `StreamType` and properties; built-in kinds through `paw.kinds.define` | Medium | One family for each commit, each with a round trip of the folder |
| 3 | LA | `Part.clips` to lanes (one for each clip kind) with takes; `meta.takes` to takes; the folder gets `lanes/<lane>/takes/<take>/`; the arrange view draws lanes under the part header | Medium: files and the arrange view | The engine does not change: the sync gives the same clip list. `paw.api.part_get` gives `lanes`; the arrange view already has row kinds (`views/arrange.tl:305-313`) |
| 4 | MX | The strip fields to a `Strip` node in `Part.graph`; output, sends, VCA, groups and the master as nodes and wires; `compose` and the processor plan; arm to lanes; `devices.json` to `devices.chain` | **High**: the sync, routing, the mixer view, freeze, every reader of the strip fields | After G2 (TASK-280) and CL2. Alone with respect to `sync/`. The null test of renders on the corpus; a `compose` property test (union of part graphs = the graph of today's routing) |
| 5 | CV | Automation to `curve` lanes with `Param` wires | Medium | The null test of renders again |
| 6 | TK | Takes and comps for every kind: keys `za`, `[` `]`, `<localleader>c`, `K` | Low | Model is from LA; UX with golden screens |
| 7 | RD | Render with provenance, derived takes, producers of tier kernel and bake, freeze as render with replace, re-derive as a new take, `:lane.detach` | Medium | After MX, M3, FZ. A stub producer in tests |
| 8 | TY | Properties checked at ports; converters; refusal messages | Low | After MX |
| 9 | OP | Outside programs in bake jobs, the sandbox, the question for each program, `:bakes` | Medium: security | A stub program in tests; no network unless declared |
| 10 | GV | The graph view of a part and of the project; the mixer view as the graph filtered to strips, buses, sends and master; export of a part graph | Medium: UX | Design with golden screens first (owner: UX first) |
| 11 | VD | Video lanes, the monitor view (half blocks, kitty), thumbnails | Medium: `paw-scene` change can stop the window build | Report it; window paused |

Why W1 comes first: every later bundle then writes the final words one
time in code and docs. The rename is wide but has no logic. It costs
most when many branches are in flight, so it goes in a quiet batch
before the structural work starts. Why MX comes after LA: LA keeps the
engine the same and makes lanes; MX then wires lanes to strips. Two
large changes of the sync never land in one bundle.

### V2.8 What the change costs

| Area | Cost |
| --- | --- |
| Rust | `model.rs` and `model/clips.rs` change their main types; `sync/` gets `compose` and a planner (MX); `session/document/*` find owners by `OwnerRef`. The engine changes only the slot name (`ProcessorSlot`). About 158 files see the rename |
| Lua and Teal | 329 files have the word "track". About 40 read `track.clips`, `track.lanes`, `meta.group`, `meta.kind` or `meta.takes` and change in LA, A2, CV. `groups.tl`, `takes.tl`, `vca.tl`, `lanes.tl`, `track_kinds.lua`, `freeze` code become thin views over the model or go |
| Views | Arrange (lanes under parts, takes, comps), mixer (a filter of the graph), devices (the inserts of a strip, then the graph view), piano roll (editor of the clip kind `midi`, its own UX design), the launcher (unchanged) |
| Files | The folder layout of V2.6. The e2e golden outputs change after W1, LA and MX: the owner or CI approves them again (TASK-24) |
| Docs | 205 Markdown files say "track". New explanation pages: about parts and lanes, about the graph, about render. Rewritten: about MIDI as the truth (becomes lanes as the truth), groups and VCAs, takes, freeze, project files, the mixer, the course and the tutor |
| Tests | 163 test files name tracks. Groups, takes, freeze, automation and routing tests change their setup in LA, MX and CV. New: the null render test (MX), the compose property test, take and comp tests with real keys |
| Extensions | Part kinds replace track kinds (same API shape). utau and notation read `Note.lyric` and producer controls. Each extension README that says "track" changes in W1 |

The largest risk is MX (step 4). The second is W1, because of its width
and its conflicts with work in flight. The order of V2.7 puts each of
them where the fewest branches touch the same files.

### V2.9 The core contracts (replaces table 2.4 where they differ)

Rust (new or changed in version 2):

| Contract | Shape | Bundle |
| --- | --- | --- |
| `Part`, `Parts`, `PartId`, `PartFamily` | V2.2 | W1, A2 |
| `StreamType`, `Props`, `Prop`, `PortSpec` | a base kind plus properties; checked by the kind's `ParamSchema` | A2, TY |
| `Lane`, `Take`, `Role`, `Comp`, `CompRange`, `Arm` | V2.2 | LA, TK |
| `Stack` | one type on a clip or a lane | M1 (clip), LA (lane field), M4 (lane stack runs) |
| `Recipe`, `Provenance`, `Kept`, `SourceHash` | V2.2; `SourceHash` uses the `ChainKey` hash | RD |
| `PartGraph`, `Node`, `Body`, `Strip`, `Send`, `Vca`, `Io`, `Wire`, `Arrow`, `PortRef`, `End` | V2.2 | MX |
| `Chain` (was the built `Graph`), `Split`, `Branch`, `Tap` | owner-free; pure edits in `model/chain/edit.rs` | A1 |
| `ProjectGraph`, `compose`, `ProcessorSlot`, `GraphPlan` | V2.4 | MX, TASK-280 |
| `Producer`, `Tier`, `ProducerImpl { Builtin, Extern, Bake }` | plan M1 with tiers | RD |
| `BakeJob`, `Permit`, `Sandbox` | V2.12 | MD4, OP |
| `OwnerRef` | `Part`, `Lane`, `Node`, `Clip` | A1 (with `Track` until W1), MX |

Lua and Teal (new or changed):

| Contract | Shape | Bundle |
| --- | --- | --- |
| `paw.chain.of(owner)` | the inserts of a strip (TASK-279's `paw.graph`, renamed) | A1 |
| `paw.graph.of(owner)`, `paw.graph.project()` | the part graph and the project graph: nodes, wires, `connect`, `disconnect`, `export`, `import` | MX, GV |
| `paw.parts`, `paw.lanes`, `paw.takes` | the tree, the lanes, takes and comps | W1, LA, TK |
| `paw.render(what, opts)` | a wire, a node output, a stack prefix or a derived take; `opts.replace` for freeze | RD |
| `paw.producers.define(kind, spec)` | `tier`, `ports`, `span(input) -> span`, `run` (kernel) or `job` (bake), `controls` (per-note schema) | RD |
| `paw.kinds.define("stream", name, spec)` | `props` schema, `time`, `records` | A2 |
| `paw.editor.define(clip_kind, view, impl)` | several editors for each kind; the piano roll is the default of `midi` | B7, PR |
| `paw.templates.define(kind, spec)` | `capture(owner, {content})`, `make(at)`, `link`, `encode`, `decode`, `version` | B8 |
| `paw.bakes` | the queue: list, move, cancel, `run` | OP |

### V2.10 The milestones (replaces section 3 where it differs)

| Milestone | Change |
| --- | --- |
| m-3, m-4 | **Close** (owner, round 7.3). |
| m-2 | TASK-222.5 goes on as reduced (X5). |
| m-9 | Goes on beside the architecture work. Each bundle brings its pages. |
| m-10 | A1 (new scope), A2 (with `StreamType`), W1, EL1, EL2, P95, T96, B3 (four layers), B4, B6, B7 (editor per clip kind), B8 (new template kinds), PM3, LOCK. |
| m-16 devices graph | Re-scoped: "the chain inside a strip, and the graph view". TASK-279 to 289 stay. TASK-282 edits the inserts of a strip. TASK-286 splits: taps now (G8a), the `outs` split as strip ports after MX (G8b). TASK-284 waits for B8 and MX. GV (the graph view) joins. |
| **m-17 (new) "Parts and lanes"** | W1g, LA, MX, CV, TK, RD, TY, OP, VD. Replaces the proposed "Tracks as containers". |
| m-5 | M1 to M6 use the word "render". MD4, FZ (freeze job only). TASK-9 (perform) becomes a producer of tier kernel with provenance, after RD and the owner. TASK-10, TASK-23 as in version 1. |
| m-15 | New ticket PR: the piano roll UX design (golden screens), before M5. TASK-299 goes on. |
| m-14 | TASK-238 (send automation) after CV; TASK-240 (wide buses) after TY (channels property); TASK-237 (audio clip view) is an editor of clip kind `audio` after B6 and B7. |
| m-6 | TASK-24 approves the e2e golden outputs again after W1, LA and MX. |
| m-11, m-13 | As in version 1: do not start; the window stays paused. |

### V2.11 The roadmap

Size: S about a day, M a few days, L a week of agent work. Each bundle
is one Opus agent.

| Id | Bundle | Tickets | Size | Depends on | Milestone |
| --- | --- | --- | --- | --- | --- |
| **Phase 0: land what runs** | | | | | |
| R18 | Batch 18 | TASK-147, 148 and 145 parts | | | m-12 |
| R19 | Batch 19: TASK-279 and TASK-281 as built | TASK-279, 281 | | | m-16 |
| run | Running: 215+208, 3+217, 287, 107, 98, 299 | | | | |
| **Phase 1: the shared core (beside m-2, m-9)** | | | | | |
| A1 | Chain alignment and the kinds core | new | M | R19 | m-16 |
| EL1 | One turn, one clock rule | TASK-292 (+293, 296) | L | R18 | m-10 |
| P95 | `paw-model` 1 and 2 | TASK-95.1 | M | merges after A1 | m-10 |
| T96 | Typed API 2, `ParamSchema` | TASK-96.2 | M | none | m-10 |
| X5 | Export presets, built-ins | TASK-222.5 | M | none | m-2 |
| G2 | The engine runs a chain plan in each slot | TASK-280 | L | A1 | m-16 |
| G3 | The devices view (inserts of a strip) | TASK-282 | L | A1 | m-16 |
| D4 | Rule 4 and the word "part" in the instructions | new | S | none | m-9 |
| **Phase 2: the word and the kinds** | | | | | |
| W1 | The word "part" | new | L | A1, EL1, P95 merged; nothing else in its batch | m-10 |
| W1g | GIFs and the course after W1 | new | S | W1 | m-9 |
| A2 | Kind families, `StreamType`, `Part.kind`, `Part.parent`, `Note.lyric` | new | L | W1, TASK-208, TASK-133 | m-10 |
| M1 | Modifier core, render of a prefix | TASK-75.1 | L | A1 | m-5 |
| EL2 | Agenda, doorbell, quiet | TASK-294 (+295) | L | EL1 | m-10 |
| G4 | Devices modes and keys | TASK-283 | L | G3 | m-16 |
| CL2 | Chain language 2: a document is one part's graph | new | M | TASK-287 | m-16 |
| B7 | Editor subject by clip kind | new + TASK-177 | L | W1 | m-10 |
| G8a | Taps | TASK-286 (part) | S | G2 | m-16 |
| PR | Piano roll UX design | new | M | none | m-15 |
| **Phase 3: lanes and the store** | | | | | |
| LA | Lanes and takes in the model, files and the arrange view | new | L | A2 | m-17 |
| B3 | Store in four layers; sections | new + TASK-222.5 AC 1, 3 | M | A2 | m-10 |
| M2 | Built-in modifier kinds | TASK-75.2 | M | M1 | m-5 |
| M3 | Extension modifier kinds | TASK-75.3 | L | M1, EL1 | m-5 |
| B4 | Linked clips on `Defs` | new | M | M1 | m-10 |
| G6 | Macros, modulators, links | TASK-285 | L | G2, G3 | m-16 |
| MD4 | Bake scheduler with provenance | TASK-10 (part) | L | M1, EL2 | m-5 |
| **Phase 4: the mix as nodes** | | | | | |
| MX | Part graph, strips, buses, sends, master; `compose`; arm on lanes; `devices.chain` | new | L | LA, G2, CL2 | m-17 |
| B6 | Built-in clip kinds through the API | new + TASK-23 B2, B3, E1 | L | A2, LA | m-10 |
| B8 | Templates: kinds, shape and content, linked | TASK-298 | L | B3, B4 | m-10 |
| M4 | Stack views, `:clip.recipe`, lane stacks | TASK-75.4 | L | M2, M3, G4, LA | m-5 |
| FZ | Freeze as a bake job | TASK-214 | M | MD4 | m-5 |
| TK | Takes and comps for every kind (UX) | new | M | LA | m-17 |
| **Phase 5: render, curves, the graph view** | | | | | |
| CV | Curve lanes | new | M | MX | m-17 |
| RD | Render and provenance; producers; derived takes | new | L | MX, M3, FZ, CL2 | m-17 |
| TY | Properties at ports; converters | new | M | MX | m-17 |
| GV | Graph view; mixer as a filter; export | new | L | MX, G4 | m-16 |
| G5 | Racks and rack templates | TASK-284 | L | B8, MX | m-16 |
| G8b | `outs` as strip ports | TASK-286 (part) | S | MX | m-16 |
| M5 | The roll and readers of the stack | TASK-75.5 | L | M4, PR | m-5 |
| M6 | Stack templates | TASK-75.6 | S | M4, B8 | m-5 |
| G11, DRV, CK | as version 1 | TASK-288, 86, 23 | | as version 1 | |
| **Phase 6: outside programs, video, lock** | | | | | |
| OP | Outside programs in bake jobs | new | M | RD, MD4 | m-17 |
| VD | Video lanes and the monitor | new | L | RD, CK | m-17 |
| PF | perform as a producer | TASK-9 | L | RD, the owner | m-5 |
| G13, WA, PM3, LOCK | as version 1 | TASK-289; 97, 1, 2; 95.3; 132, 105, 206, 220, 221 | | PM3 after MX | |

The dependency picture:

```text
Ph0  R18 ──────────┐      R19 (279, 281) ──┐    running work
Ph1  EL1 ◀─────────┘      A1 ◀─────────────┘
      │  T96 X5 D4         ├──▶ P95   ├──▶ G2 ──▶ G8a
      │                    │          └──▶ G3 ──▶ G4
Ph2  EL2   W1 ◀── A1, EL1, P95 (quiet batch) ──▶ W1g
      │     ├──▶ A2 ◀── 208, 133     CL2 ◀── 287
      │     └──▶ B7      M1 ◀── A1   PR (design)
Ph3  MD4 ◀─ M1, EL2   LA ◀── A2    B3 ◀── A2
                      M2, M3, B4 ◀── M1     G6 ◀── G2, G3
Ph4  FZ ◀── MD4   MX ◀── LA, G2, CL2   TK ◀── LA   B6 ◀── A2, LA
                  B8 ◀── B3, B4        M4 ◀── M2, M3, G4, LA
Ph5  RD ◀── MX, M3, FZ, CL2   CV, TY, G8b ◀── MX   GV ◀── MX, G4
     G5 ◀── B8, MX   M5 ◀── M4, PR   M6 ◀── M4, B8
Ph6  OP ◀── RD, MD4   VD ◀── RD, CK   PF ◀── RD   LOCK last
```

The critical path:

```text
R19 → A1 → W1 → A2 → LA → MX → RD → OP
                              └──→ VD (with CK)
R19 → A1 → G2 → MX           TASK-287 → CL2 → MX
A1 → M1 → M3 → RD            M1 → MD4 → FZ → RD
```

The longest chain is R19, A1, W1, A2, LA, MX, RD, OP: eight steps. A1
gates the most bundles. W1 must run in a quiet batch, so the
coordinator plans the batch before it to finish the work in flight.

Parallel work, up to 8 agents:

| Phase | Slots |
| --- | --- |
| 1 | A1 · EL1 · T96 · X5 · D4 · TASK-287 (running) · TASK-215+208 (running) · web (TASK-107) |
| 1, after A1 | G2 · G3 · P95 · EL1 · T96 · X5 · TASK-3+217 · web |
| 2a (quiet) | W1 alone; beside it only work that touches no Lua, docs or model: G2 (engine), EL2 (kernel loop) |
| 2b | A2 · M1 · EL2 · G4 · CL2 · B7 · G8a · PR |
| 3 | LA · B3 · M2 · M3 · B4 · G6 · MD4 · TASK-133 or m-12 |
| 4 | MX (alone in `sync/`) · B6 · B8 · M4 · FZ · TK · m-9 · m-12 |
| 5 | RD · CV · TY · GV · G5 · G8b · M5 · M6 |
| 6 | OP · VD · PF · G13 · WA · PM3 · then LOCK |

Pairs to keep apart in one batch: W1 and anything with Lua, docs or the
model; A1 and P95 (`model/`); LA and B6 (`views/arrange*.tl`); MX and
any bundle in `sync/` or the mixer view; CV and MX; EL2 and any bundle
that edits `Session::idle`.

### V2.12 Outside programs, bakes and the hard rules

- A bake job runs a producer of tier bake. An outside program runs only
  in such a job, in a helper with a scratch `HOME`, a working folder in
  the project cache, and no network unless the extension declares it.
  The job reports progress and can be cancelled. One queue, `:bakes`,
  that the user can order.
- Opening a project never starts an outside program and never starts a
  bake. A take whose source changed outside paw (a git merge) shows a
  stale mark. Bakes start after the first edit in the session, or by
  `:bakes run`.
- The question "allow this program?" comes one time for each program in
  each project. The answer (a `Permit`: project id, program path, hash
  of the program) is kept in the user's state folder
  (`$XDG_STATE_HOME/paw/permits.json`), **not** in the project. Reason:
  a project from another person must not give itself a permit.
- A missing program: the lane keeps its last bake with an "absent" mark;
  `K` names what to install.
- Tests use a stub program built in the repository (as the stub CLAP
  plugin), a scratch `HOME` and a permit from the test's scratch state
  folder. No test runs a real outside program.

### V2.13 The fate of the running work

| Work | Fate |
| --- | --- |
| TASK-279 (built: `Track.graph`, `Linked<D, O>`, `racks.json`, `paw.graph`) | Lands as built in batch 19 (owner, round 7.5). Then **A1** gives it its version 2 shape: the type `Graph` becomes `Chain` (the inserts of a strip and the body of a rack; the word "graph" goes to the part graph); `paw.graph` becomes `paw.chain` with `paw.chain.of(owner)`; the model is owner-free with pure edits; typed ids; `Linked<D: Linkable>`, `Defs<RackDef>`; the kinds core. `Track.graph` stays on the track until MX moves it to `Strip.inserts`. No `meta` on a split. The file stays `devices.json` until MX |
| TASK-280 (engine runs graphs) | Keeps its scope: the engine runs a compiled `GraphPlan` of a `Chain` in each processor slot. `Msg::SetGraph { slot }` names a `ProcessorSlot`. The order of slots stays the routing of today; MX gives it from `compose`. Depends on A1 |
| TASK-281 (chain-syntax, built) | Lands as built in batch 19. `winnow` stays (plan C1) |
| TASK-287 (chain tools) | Goes on, with the host context (empty by default) and the codes E213 to E218 and W302 kept free. No lint assumes that each port is audio |
| CL2 (chain language 2, was 7.6 of `containers.md`) | Re-scoped: **a document is the graph of one part**. Header `chain 2 "Violin I"`. Top-level node lines (`strip`, `bus`, `send`, `master`, `vca`, `producer`, `io`) with parameters; a `strip` holds its inserts as an indented chain of version 1; wires `a -> b` (live) and `a => lane` (store); outside ends `@"Strings/Violin I/Notes"`. Ports and stream types with their properties come from the schema (`chain_schema: 2`: `streams` with `props`, `ports`, `tier`, `converts`). The `produce` block of version 1 goes: a producer is a node and its sink is a store wire. The project graph exports as one document for each part |
| TASK-282, 283 (devices view, modes) | Go on after A1, on `paw.chain.of`. They edit the inserts of one strip. GV later adds the graph view |
| TASK-284 (racks) | Waits for B8 and MX. A rack is a template of kind `rack` in `templates/rack/` |
| TASK-286 (taps, `outs`) | Splits: G8a (taps) after G2; G8b (`outs` branches become strip output ports in the part graph) after MX |
| TASK-298 (templates) | B8, with the kinds of round 6 and the contract of ADR 0020 |
| TASK-214 (freeze) | FZ: the bake job and its key only. RD makes freeze a render with replace |
| TASK-75 | M1 to M6 with the word "render" |
| TASK-9 (perform) | A producer of tier kernel with provenance, after RD and the owner |
| TASK-299, TASK-222.5, the web lane | Go on (owner, round 7.5) |

### V2.14 Work that must not start yet (replaces 4.5 where it differs)

| Work | Why | Starts after |
| --- | --- | --- |
| Any new code or doc that adds the user word "track" | W1 renames it | W1 (then never) |
| A model field on `Track` (`kind`, `parent`, `Mix`) | A2 and MX put them on `Part` and nodes | A2, MX |
| TASK-284 racks and templates | store, link type, the strip | B8, MX |
| The `outs` split of TASK-286 | its branches become strip ports | MX |
| `devices.chain` as the file of TASK-279's tree | MX writes the part graph | MX |
| Any change of `meta.takes`, `takes.tl` data or `groups.tl` data | LA and A2 move them | LA, A2 |
| Automation features (TASK-238) | curve lanes | CV |
| A producer that runs an outside program | the sandbox and permits | OP |
| The `produce` block of `containers.md` 7.3 | replaced by producer nodes and store wires | never |
| `Mix` as an optional field (C4 of version 1) | strips are nodes | never |
| Lanes that mix clip kinds | owner, round 1.6 | never |
| Piano roll UX changes beyond fixes | PR designs it | PR |
| TASK-298 as a Rust trait; TASK-222.5 AC 1 and 3; TASK-23 B2, B3, E1; TASK-10 M6, M7; TASK-95.3; TASK-105; m-11 | as version 1 | as version 1 |

### V2.15 The ticket plan for phases 1 and 2 (replaces section 6 where it differs)

Nothing is written to the Backlog. The coordinator or the product owner
agent makes these edits. "NEW-x" is a placeholder for a new id. The
edits of 6.1 stay, with these changes: TASK-279's note names "A1
(architecture-plan.md V2.13)"; TASK-284 depends on NEW-MX (not C4);
TASK-298's kinds are those of V2.3; TASK-214's note names NEW-RD.

**Close m-3 and m-4.** Create m-17 "Parts and lanes" with the tickets
NEW-W1g, NEW-LA, NEW-MX, NEW-CV, NEW-TK, NEW-RD, NEW-TY, NEW-OP,
NEW-VD, each with a title and one line, filled when its phase starts.

#### Phase 1

**NEW-A1 (m-16, HIGH). "Chain alignment and the kinds core"**

The AC of version 1 (section 6.2) stay, with these changes:

1. The built type `Graph` is `Chain` (module `model/chain.rs`,
   `model/chain/edit.rs`); `GraphError` is `ChainError`. The word
   "graph" is free for the part graph.
2. `paw.graph` is `paw.chain`; `paw.chain.of(owner)` gives a handle;
   `owner` is `{track = id}` until W1 and `{part = id}` after it, then
   `{node = id}` after MX. The Teal types and the API reference come
   from the doc comments.
3. `OwnerRef` is an `enum` with one variant `Track(TrackId)` now; W1 and
   MX add the others.
4. The families of V2.3 exist as types; `StreamFamily` has no entries
   yet (A2 adds them).
5. `devices.json` and `racks.json` keep their bytes.

**TASK-292 = EL1, TASK-95.1 = P95, TASK-96.2 = T96, TASK-222.5 = X5:** as
version 1 (6.2).

**TASK-280 (G2).** The edit of version 1, and: "The plan is of a `Chain`
(the inserts of a strip). The order of slots does not change in this
ticket."

**TASK-282 (G3).** Add a dependency on NEW-A1. Add a note: "The view
edits the inserts of one strip through `paw.chain.of`. The graph view of
a part is NEW-GV."

**NEW-D4 (m-9, HIGH, S). "Rule 4 and the word part in the instructions"**

1. `AGENTS.md` rule 4 has the text of round 7.2, with a link to the
   public page.
2. The skills `paw-extension` (rule 1 of its list), `diataxis-docs`
   (the list of explanation pages, the glossary words "part" and
   "lane") and `teal` (if it names the rule) agree with rule 4.
3. `docs/explanation/about-midi-as-the-truth.md` gets one paragraph at
   its top: the rule is now "lanes are the truth"; today a track has
   one lane of each kind; the page is rewritten with LA. (Each fact
   stays true.)
4. `tools/website/landing.md` "MIDI is the truth" agrees.
5. Vale reports 0 alerts.

#### Phase 2

**NEW-W1 (m-10, HIGH, L). "The word part: Track becomes Part in the
model, the API, the commands, the files and the docs"**

1. Rust: `Track` is `Part`, `TrackId` is `PartId`, `Project.tracks` is
   `Project.parts`; `MASTER_ID` stays until MX. `cargo clippy` passes.
2. Files: `tracks/<name>/track.json` is `parts/<name>/part.json`;
   `master/` stays until MX. A round trip test of the folder.
3. `paw.api.track_*` is `paw.api.part_*`; `paw.tracks` is `paw.parts`;
   the Teal types and the API reference are made again. `tlcheck`
   passes.
4. Ex commands `:track.*` are `:part.*`; keys keep their letters unless
   a key names the word (the key rule page lists each change). Messages
   say "part".
5. Runtime and extensions: no public name, message or doc comment says
   "track" for the container (`git grep` with an allow-list for
   `track` in other senses: a sound track of a video, a MIDI file track,
   to track a value).
6. Docs, READMEs, the tutor's lessons and the course say "part"; the
   guide tests pass; Vale reports 0 alerts.
7. Each layer is one commit, and the suite is green at each commit.

Dependencies: A1, EL1, P95 merged. No other bundle with Lua, docs or
`model/` in its batch.

**NEW-A2 (m-10, HIGH, L).** The AC of version 1 (6.3), with these
changes: `Part.kind: Option<KindId<PartFamily>>` and `Part.parent:
Option<PartId>` (no `Track` fields); `StreamFamily` has `midi`, `audio`,
`curve`, `state` with a `ParamSchema` of properties, a time base and
`records`; `StreamType` and `Props` exist and round trip; `ClipFamily`
has `curve`; a test defines a stream kind with a property from Lua.
Dependencies: NEW-W1, TASK-208, TASK-133.

**TASK-75.1 = M1.** The AC of version 1 (6.3), with "render" in place of
"Apply": `:clip.render [n]` and `:clip.render! [n]`; render of a prefix
only; render makes a new source take with provenance once LA lands
(before LA: it writes the notes into the clip and keeps the recipe in
the undo step only, with a note in the ticket that LA adds the take).

**TASK-294 = EL2, TASK-283 = G4:** as version 1.

**NEW-CL2 (m-16, MEDIUM, M). "Chain language 2: a document is the graph
of one part"**

1. Grammar version 2: node lines `strip`, `bus`, `send`, `master`,
   `vca`, `producer`, `io` with fields; a `strip` holds its inserts as an
   indented chain of version 1; wires `a -> b` and `a => <lane>`;
   outside ends `@"path/to/lane"`; a reader of 2 reads 1 (a document of
   version 1 is the inserts of one strip).
2. `chain_schema: 2`: `streams` with `props` (a `ParamSchema`), `time`
   and `records`; kinds with `ports` (`port`, `stream`, `props`,
   `main`, `out`), `tier` and `converts`.
3. The diagnostics E213 to E218 and W302 of `containers.md` 7.3, with
   E213 for a gap of type that names the missing property, each with a
   golden diagnostic and a test that does not fire.
4. Property tests: print then parse; the fuzz target covers the new
   tokens.
5. paw: `chain_schema.rs` writes `midi`, `audio`, `curve` and the ports
   of the built-in devices; `paw chain context <part>` writes the outside
   lanes and nodes.
6. `chain-lsp` completes outside ends from the context.
7. `chain-language.md` and `chain-schema.md` are true; each example
   parses; Vale reports 0 alerts.

Dependencies: TASK-287 merged.

**NEW-B7 (m-10).** The AC of version 1, with
`paw.editor.define(clip_kind, view, impl)` (several editors for each
kind; one default) in place of a stream kind. Dependencies: NEW-W1.

**TASK-286 split.** NEW-G8a (taps) keeps AC about taps; NEW-G8b (the
`outs` split as ports) depends on NEW-MX.

**NEW-PR (m-15, MEDIUM, M). "Piano roll UX: the default MIDI editor"**
(design only). Study real screens (`scratchpad/screens/shots.lua`),
golden screens for: ink and ghosts of a stack (`\m`), takes and comps of
a MIDI lane, lyrics and producer controls of a note, a second editor of
the same kind. Output: a design with keys under the key rule, for the
owner. No code.

### V2.16 Points where the answers meet a hard rule or each other

| # | Point | Recommendation |
| --- | --- | --- |
| P1 | Rule 4 changes "in the same work as ADR 0019" (round 7.2), but each public fact must be true, and lanes do not exist until LA | D4 changes `AGENTS.md` and the skills now (rules for future work), and puts one paragraph on the public page; LA rewrites the public page when lanes exist |
| P2 | "Solo on a strip or bus" and "solo of a lane = only what it feeds" (round 3.B) | Solo is state of strips and buses only. `solo` on a lane is a command that solos the strips that it feeds and mutes the other lanes into those strips, as one undo step |
| P3 | "Asked once per program" (round 4.6) and safety: a permit in the project lets a shared project approve itself | Keep permits in the user's state folder (V2.12), not in the project |
| P4 | The key budget (100 ms) and many kernel-tier producers in one turn | The 50 ms limit is for **all** kernel jobs of one turn, not for each. A job that does not fit goes to the next turn with a stale mark. A producer that is always over the limit moves to tier bake, with a message (version 1, item 7.5) |
| P5 | The key budget and `compose` on a large project | `compose` is incremental: a part whose `Arc` did not change keeps its piece. A test counts the parts composed (a count, not a time) |
| P6 | Audio thread rules and live converters | A live converter is a built-in device with no allocation (mono to stereo, stereo to mono). A converter that needs more (a resample of a file, a video frame) is tier bake |
| P7 | "Opening a project never starts an outside program" and "re-bake the takes the comp uses first" | On open, only stale marks. Bakes start after the first edit or `:bakes run` |
| P8 | Sealed tests and outside programs | A stub program in the repository; a scratch `HOME`; permits from the scratch state folder |
| P9 | Template kind names: round 6.1 says "graph (rack)", round 6.4 says `templates/rack/` | One kind `rack` (a chain: the inserts of a strip). The graph of a part goes in a template of kind `part` (with shape only, it is the lanes and the graph without clips). No kind `graph` |
| P10 | "Undo of each action" and bakes that end later | The render is the undo step (the new lane or take, with a pending result). The kept files of a bake are a cache outside the undo tree, as derived data is today |
| P11 | ADR 0014 says "Apply writes the result into the source"; ADR 0009 names `tracks/` and `track.json` | 0014 stays accepted; ADR 0025 replaces its Apply bullet. ADR 0032 supersedes 0009 and restates its rules |
| P12 | The word "lane" for automation today (user guide) | Automation lanes become lanes of kind `curve`, so the word stays true for the user |

No answer breaks a hard rule. P3 and P4 need the owner to see the
recommendation; the rest are internal.

---

## Contents (version 1)

1. The conflict table: one answer for each conflict
2. The unified architecture: the picture and the core contracts
3. The corrected milestones
4. The roadmap of bundles
5. The merged questions for the owner
6. The ticket plan for phases 1 and 2
7. What this plan could not resolve

---

## 1. The conflict table

Version 2 changes these rows: K2 and K3 (V2.3: `StreamType`, a lane names its clip kind), L4 and L9 (V2.2: a part graph on each part, the strip as a node), M3 (V2.2: a producer is a node, no `produce` block), M7 (V2.5: freeze is a render with replace), T2 (V2.6: four layers), P1 to P4 (V2.2, V2.15). The other rows stay.


"Overrules" names the design whose text this plan replaces on that
topic. RUST is the default for Rust shapes. Where RUST and the built
code disagree, the table gives the reason for the choice.

### 1.1 Kinds and stored data

| # | Topic | Documents | Conflict | Resolution | Overrules |
| --- | --- | --- | --- | --- | --- |
| K1 | The id of a kind | M10, MOD, RUST, built TASK-279 | M10: `KindId(Word)` for all. MOD: dotted names. Built: split kinds as `Word` (no dot). RUST: `KindId<F: Family>`. | `KindId<F: Family>`, dot-joined lowercase words, at most 64 bytes. `Word` stays for roles and port names. `RESERVED` and `ClipKindId` go. A bare word is free to any owner; the registry decides a clash by shadow. | M10 2.1, built `Word` for split kinds |
| K2 | The list of families | M10, RUST, CONT | M10: clip, track, split, modifier, template, device. RUST: six plus `StreamFamily`. CONT: adds `producer`; lane kinds are the clip family. | Ten families, each with one absent rule (table 2.3). `Stream` and `Producer` are families. `Device` is a family for the id type and the absent rule only; its container stays in paw-engine. | CONT 3.4 (lane kinds) |
| K3 | What a lane's kind filters | CONT Q4, RUST 10.2 | CONT: a lane's kind names a clip kind. RUST: a stream family. | A lane's kind is a `KindId<StreamFamily>` (`midi`, `audio`, `keyframes`, `video`, `text`). Each clip kind says which stream it gives (`gives`). Reason: a producer checks its inputs by stream, and two clip kinds can give one stream (a `pattern` clip and a MIDI clip both give `midi`). The chain language 2 schema uses the same stream words. | CONT 3.1, 3.4, Q4 |
| K4 | The absent rule of modifiers | M10 2.3, MOD 4.5 and Q7, RUST | M10: `Keep` (a kept bake). MOD and the owner: the entry waits, the notes play. | `ModifierFamily::ABSENT = PassThrough`. No kept result. | M10 2.3 |
| K5 | The absent rule of producers | CONT 3.3, MOD 4.6 | CONT: the kept bake plays. MOD: no kept result. | `ProducerFamily::ABSENT = Keep`. A producer changes the type of its input, so no input of the same type exists to pass through. The derived lane plays its last kept result and shows a stale mark. A modifier keeps its own type, so it passes through. The two rules do not conflict. | none |
| K6 | The Rust registry shape | M10, RUST, built `SplitKinds` | M10: a map with `family` and `absent` fields. Built: a registry of `Word` over a `Builtin` `enum`. | `Kinds<F, S>` with a stack of shadowed entries and the verbs of `paw.registry` (`put`, `get`, `remove`, `unload`, `owned_by`). The built `SplitKinds` becomes `Kinds<SplitFamily, SplitImpl>`. | M10 2.1 |
| K7 | Versions | M10, MOD, DG | `u32` in each. | `Version(NonZeroU32)`; absent in a file means 1 and is not written. `Loaded<F, T> { Ready, Newer, Absent }` after a read. | M10, MOD |
| K8 | Device kinds | M10 6.1 (TASK-97), RUST 9 | M10: device kinds are entries of a family. RUST: device factories keep their own `Registry` (`Rc`, engine side). | Both. `KindId<DeviceFamily>` and `Owner` on each factory entry. The container stays `paw-engine`'s `Registry`. TASK-97 adds the owner. | none |
| K9 | Modulator kinds | M10 Q8, MOD 3.6, DG 4.6 | M10: modulators share the registry of Modifier. | A family of their own, `ModulatorFamily` (`PassThrough`: the base value stays). They share the UX of a stack (`~`, `K`, `:mod.bake`), not the registry and not the id type. A modifier id in a modulator lane is a type error. | M10 Q8 |
| K10 | `meta` keys | M10 2.1, RUST | Same idea. | `paw.meta.define(key, spec)` puts an entry of `Kinds<MetaFamily, MetaMeta>`. Undeclared keys stay as today. | none |
| K11 | `meta` on a split | DG 4.3, built TASK-279, RUST 6.2 | Built and DG: a `meta` map on each split. RUST: no. | No `meta` on a split. A split kind's values are `values`, checked by the kind's schema. A use for extension data on a node gets a declared `MetaFamily` key then. | DG 4.3, built |

### 1.2 Modifier, producers and bakes

| # | Topic | Documents | Conflict | Resolution | Overrules |
| --- | --- | --- | --- | --- | --- |
| M1 | The op trait | M10 `Op<T>`, MOD `ModifierKind<C>`, CONT `ModifierKind<C>` and `ProducerKind<I, O>`, RUST | Three traits for one job. | No trait. `enum Builtin` with typed params, run by `match`. Extension kinds are `ModImpl::Extern`, run by the kernel as an `ExternJob` through `RunExtern`. Producers use the same split: `ProducerImpl { Builtin, Extern, Bake }`. A `Content` trait comes only with a second stream kind that has a stack. | M10 2.3, MOD 3.2, CONT 3.4 |
| M2 | The saved step | M10, MOD, `media.md` | `op`/`kind`, `enabled`/`on`. | `Modifier { kind, version, on, scope, params }`, one struct for MIDI stacks and media recipes. | M10, `media.md` |
| M3 | Modifier and producer | MOD 3.6, CONT 3.4, RUST 10.2 | CONT: a tier 2 producer with one input of the same type is a modifier stack on a lane. | A **modifier** keeps the type of its stream and sits in a stack on a clip (later on a lane). A **producer** has typed ports, sits in a `produce` branch of the container's chain document, and writes a derived lane. A modifier kind has the implied ports `stream in, same stream out`, so it can also stand in a producer branch. One evaluator (`evaluate` with `ChainKey`) serves both. | CONT 3.4 (the trait part) |
| M4 | Where tier 2 runs | CONT 4.2 (`derived.tl` slices), MOD 3.5 (Lua in the sync), RUST 4.2 (`ExternJob`) | Three places. | Tier 2 runs in the turn. Built-in kinds run in Rust inside the sync. An extension kind is an `ExternJob` that the kernel runs after the sync returns and before events go out, under `paw.limit` (50 ms). Work that cannot meet that budget is tier 3, not tier 2. `derived.tl` slices stay for Lua derived data only. | MOD 3.5, CONT 4.2 |
| M5 | Tier 3 and the event loop | CONT 4.2, EVL 5.4, `media.md` | Producers' bake jobs are not in the EVL list of `Upkeep`. | Tier 3 producers, freeze and media bakes all run on the bake scheduler. The scheduler is the `Bakes` implementation of `Upkeep` (`Woken::BAKES`). No new `Upkeep` for producers. | none |
| M6 | Pending `ExternJob`s and quiet | RUST 4.2, EVL 5.4 | Not said. | A pending `ExternJob` makes `Agenda.ready` true. The jobs of one turn run in that turn, so quiet comes after them with no time in a test. | none |
| M7 | Freeze | CONT 3.2 and Q10, TASK-214, `media.md` | CONT: freeze becomes the producer `render` on a derived lane. TASK-214: freeze bakes through the scheduler. | Both, in order. TASK-214 builds the runner: the bake job and the kernel key. It adds no model field (it keeps `meta.frozen`). C5 moves the place in the model: a derived audio lane, producer `render`, `mode: Baked`, "replaces the source". | none; TASK-214 gets a limit |
| M8 | The stack as text | MOD 6.2, M10 Q14, DG 10 | MOD: its own line format with `#` for an entry that is off. Chain: `#` is the id marker. M10: chain text "later". | One grammar. `:clip.recipe` is a `chain-syntax` document with a modifier host schema. An entry that is off has the flag `off`. `--` is a comment. It is built with the stack views (bundle M4 of the roadmap), not later. No second parser. | MOD 6.2, M10 Q14 |
| M9 | Linked clips and the stack | MOD 4.1, M10 2.5 | Same answer. | The stack is on the instance (the clip), not on the shared notes. In `Linked<NotesDef>`, the stack is the instance's overrides. | none |

### 1.3 Linked definitions, the graph and its owner

| # | Topic | Documents | Conflict | Resolution | Overrules |
| --- | --- | --- | --- | --- | --- |
| L1 | The shape of a link | M10 `Linked<D> { def, overrides: Vec<Modifier> }`, RUST `Linked<D: Linkable>` and `Defs<D>`, built `Linked<D, O>` with `of: Id` | Three shapes. | `Linked<D: Linkable> { of: DefId<D>, overrides: D::Overrides }` and `Defs<D>` in the project. `trait Linkable { type Overrides; }`. The built field name `of` stays. | M10 2.5, built `Linked<D, O>` |
| L2 | Rack overrides | RUST 3.2 `BTreeMap<(DeviceId, ParamKey), f64>`, built `RackOwn { ids, values: Keyed }` | RUST: a map of values. Built: the instance holds its own copy (own device ids, own plugin state) and a set of keys that it keeps; `Keyed::follow` decides which value an instance keeps when the definition changes. | The built model wins. A rack instance is a copy with its own devices, because a device has state that a definition cannot share. `RackOwn { ids: IdMap, values: Keyed<ValueKey> }`. `ValueKey` is typed: `Param { device, param }`, `Split { node, field }`, `Branch { node, field }`, `Macro { node }`. Its text form is the chain reference `#5.ratio`. A value can be a number, a flag, a zone or a choice, so a key set is correct and a map to `f64` is not. | RUST 3.2 (rack override type) |
| L3 | Two ways to follow a definition | RUST 3.2 (`Cow` resolve), built (copy and follow) | One trait, two strategies. | Both stay, by kind. Linked notes resolve: the instance reads the definition, and `Links::spread` goes (bundle B4). Linked racks copy and follow (`Keyed::follow`). `Linkable` holds only the type link. Each `D` gives its own `update`. | none |
| L4 | Who holds the graph | DG 4.3 (`Track.graph`), CONT C4 (`Mix.graph`), RUST 10.2 (`Graphs(BTreeMap<OwnerRef, Arc<Graph>>)` in the session) | Three places. | A field on the owner: `Track.graph` now (built), `Mix.graph` in C4. No side map: the graph must be in the undo snapshot, and the model already is. `OwnerRef` is the handle of the API (`paw.graph.of(owner)`), not a key of a map. | RUST 10.2 (`Graphs`) |
| L5 | Graph edits | built (in the session, about 500 lines), CONT C0, RUST 10.1 | Built: edits live in `session/document/graph.rs`. | Pure functions in `model/graph/edit.rs`: `fn wrap(&Graph, ..) -> Result<Graph, GraphError>`. The session finds the owner, calls the function, records one undo step and gives the message. | built |
| L6 | Ids | RUST 2, built | Built uses `Id` (`u64`) for devices, nodes and rack definitions. | `DeviceId`, `NodeId`, `ParamKey`, `DefId<D>` in the graph and its API now (bundle A1). `TrackId`, `ClipId` across the model come later in TASK-98's lane. Files do not change. | built |
| L7 | Split kinds | DG 4.2 (an `enum`), built (`Word` and a `Builtin` `enum`), RUST 6.2 | The model holds a closed `enum` in DG. | The model holds `KindId<SplitFamily>`. The compiler (TASK-280) resolves it in `Kinds<SplitFamily, SplitImpl>`. An absent split kind compiles as its first branch in series. | DG 4.2 |
| L8 | The engine message | DG 4.4 (`Msg::SetGraph { track }`), RUST 10.1 | Names a track. | The message names a `ProcessorSlot` (a track has one today). `GraphPlan` keeps all buffers in one `Box<[f32]>`, uses `Buf`, and only `compile` makes one. | DG 4.4 |
| L9 | When `Track.graph` moves | CONT C4 | Before or after TASK-284? | C4 moves it after TASK-280 merges and before TASK-284. A1 makes the move mechanical: one field and one lookup of the owner. | none |

### 1.4 Templates, store and project files

| # | Topic | Documents | Conflict | Resolution | Overrules |
| --- | --- | --- | --- | --- | --- |
| T1 | The Template contract | TASK-298 AC 1 ("a Rust trait"), M10 2.4 (`TemplateKind` trait), RUST 3.2 (no Rust trait) | The owner's word is "trait". | The contract is a Teal record in `contracts.tl` (`TemplateKind`: `capture`, `make` or `apply`, `encode`, `decode`, `generate`, `version`). The Rust side is `Kinds<TemplateFamily, TemplateMeta { version, verb }>` for the list and the absent rule. The kernel gives the operations a kind needs (`graph_capture`, `graph_insert`, `capture(owner)`) through `paw.api`. A Rust trait comes when two Rust template kinds exist. The owner's intent (one generic contract in core, extensions own their format) holds. Question Q6 asks the owner to accept the new words of AC 1. | M10 2.4, TASK-298 AC 1 |
| T2 | Where the store keeps files | DG 9.5 (`racks/`, `~/.local/share/paw/racks/`), M10 2.6 (`racks/`, `templates/`, `ext/<name>/`), TASK-222.5 (`project.toml [export.presets]`) | Three layouts. | One layout for every template kind: `templates/<kind>/<name>.<ext>` in the project folder, `$XDG_DATA_HOME/paw/templates/<kind>/` for the user, `runtime/templates/<kind>/` bundled, and generated entries in memory. A rack template is `templates/rack/<name>.chain`. Export presets are kind `export`. `ext/<name>/` is for an extension's own data only. Reason: one walk, one clash rule, one picker. | DG 9.5 and Q13 (paths), TASK-222.5 AC 1 and 3 (place) |
| T3 | Linked rack definitions | built `Project.racks` in `racks.json`, T2 | Is a definition a template? | No. A linked definition is project data (`Defs<RackDef>`, kept in `racks.json`). A template is a file in the store. To load a template as linked makes a definition in the project from the template file. | none |
| T4 | Project sections | M10 2.6, RUST 3.2 | Same idea. | `Sections(BTreeMap<ExtName, Section>)`, `RelPath` checked on read. The core keeps the bytes. Projdiff (TASK-277, 290) lists sections. | none |

### 1.5 Event loop

| # | Topic | Documents | Conflict | Resolution | Overrules |
| --- | --- | --- | --- | --- | --- |
| E1 | The clock | EVL 5.2 (`Arc<dyn Clock>`), RUST 5.2 | Trait with a downcast. | `enum Clock { Wall, Manual }`, `ScheduleTime` for every "when", `Instant` for budgets. | EVL |
| E2 | The clock lint | EVL (`tools/clocklint`), RUST | A grep tool. | Clippy `disallowed_methods` in `crates/paw-core/clippy.toml`, with `#[expect(.., reason)]` at each budget site. | EVL |
| E3 | `Upkeep` | EVL 5.4 (`const KIND`, `UpkeepCx`), RUST 5.2 | Not dyn-compatible; two `&mut` of one struct. | `fn kind() -> Woken`, `poll(now, &mut Vec<Outcome>)`, `agenda(now)`. The session applies the outcomes. | EVL |
| E4 | The wake | EVL 5.5 (`KernelMsg::Wake` from each worker), RUST 5.2 | `mpsc::send` from a CLAP callback on the audio thread can allocate. | `Doorbell`: an atomic bit set and one `mio::Waker`. The audio thread only sets a bit (`mark`). The browser build keeps `recv_timeout` behind one `#[cfg]`. | EVL |
| E5 | The order of a turn | EVL 5.1, RUST 4.2 | `ExternJob`s are not in the order. | Step 4a gets three parts: (1) the sync compiles and collects jobs; (2) the kernel runs the jobs with no borrow; (3) the sync goes on and pushes to the engine. Then events, hooks, scenes, the undo step. | EVL 5.1 (adds a step) |

### 1.6 Chain language

| # | Topic | Documents | Conflict | Resolution | Overrules |
| --- | --- | --- | --- | --- | --- |
| C1 | The parser crate | DG 10.1 (`chumsky`), RUST 6.3 and R4 (`rowan`), built TASK-281 (`winnow`) | Three choices. | Keep `winnow` as built. The built lexer keeps comments and blank lines as trivia with line spans, and it recovers line by line. That gives the formatter and the language server what RUST asked `rowan` for. Move to `rowan` only if TASK-287 shows that the server needs a lossless tree inside a line (for example a code action on a part of a value). Do not rewrite now. | RUST 6.3, R4 |
| C2 | The header | DG 10.2 (`track "Gtr bus" rev=..`), RUST 10.1, CONT 7.5 | Names a track. | `chain 2 "Gtr bus" rev=..`. The crate has no word "track". | DG 10.2 |
| C3 | Version 2 | CONT 7.3 to 7.6 | When. | One ticket after TASK-287 merges (both change `check.rs`). It adds stream kinds, ports, `produce`, sinks and `@"..."`. paw writes only `audio` and `midi` ports until C5. | none |
| C4 | One parameter schema | M10 2.8, MOD 3.5 (`ParamSpec`), DG 10.1, CONT 7.4 | Four forms. | One Rust `ParamSchema` with the JSON Schema words (`type`, `minimum`, `maximum`, `enum`, `default`, `description`), plus `unit`, plus `stream` and `main` for a parameter of type `source`. `schemars` gives it for built-ins. The chain host schema embeds it. The Teal `ParamSpec` is generated from it. | MOD 3.5 (hand-written Lua spec) |

### 1.7 Built-ins, editors and lanes

| # | Topic | Documents | Conflict | Resolution | Overrules |
| --- | --- | --- | --- | --- | --- |
| P1 | `meta.takes` | M10 B2 (a model field), CONT C3 (take lanes) | Two moves of the same data. | One move, in C3, straight to lanes with `role: Take`. B2 does not touch takes. | M10 6.2 B2 |
| P2 | `meta.kind` and `meta.group` | M10 B2, CONT C2 | Same files. | One bundle (A2 below): `Track.kind` and `Track.parent`. | none |
| P3 | A `takes` field of a clip kind | M10 B6 | With take lanes, a clip kind has no take logic. | No `takes` field. C3 comes before B6. | M10 2.2 |
| P4 | The editor subject | M10 2.7, CONT 5.1 (lenses) | M10: a subject of a clip of the roll. CONT: lenses on lanes. | `paw.editor.define(stream, view, impl)` registers a lens for a stream kind. `paw.editor.current(stream)` gives the subject `{ owner, lane, clip, cursor, selection }`. `lane` is nil until C3. The performer lens is a workspace (a template kind), not a view. | M10 2.7 (narrowed to notes) |
| P5 | `meta.lyric` | M10 Q9 | None. | `Note.lyric` as a model field, in A2. | none |

---

## 2. The unified architecture

Replaced by V2.1 to V2.4 and V2.9 where they differ. The rules of 2.4 (built-ins through the public API; no Lua under a borrow of `Session`) stay.


### 2.1 The picture

```text
 ┌───────────────────────────── Lua and Teal: everything the user touches ───────────────────────────────┐
 │ views (arrange, roll, devices, stack, mixer) · lenses by stream kind (paw.editor) · keys and modes     │
 │ paw.kinds.define(family, name, spec)  paw.meta.define  paw.templates.define  paw.store (5 layers)      │
 │ paw.modifier.register (Extern kinds)  paw.graph.of(owner)  paw.project.section(name)                  │
 │ paw.registry: one shadow stack per registry, owner, unload (built-ins have owner paw.<feature>)       │
 └──────────────▲───────────────────────────────────────────────┬────────────────────────────────────────┘
                │ events, scenes                                 │ paw.api (typed, ParamSchema, thiserror → message)
 ┌──────────────┴───────────── kernel: main thread, one turn ─────▼───────────────────────────────────────┐
 │ turn(now): messages → Upkeeps (8, by Doorbell bits) → Lua timers → close:                              │
 │            sync compiles (built-ins) → ExternJobs run (no borrow) → sync pushes → events → hooks →    │
 │            scenes → one undo step → Agenda = timers | upkeeps | pending jobs                           │
 │ Clock { Wall, Manual } · ScheduleTime · Doorbell (mio::Waker; the audio thread only marks a bit)      │
 │ Registries: Kinds<F, S> for each family · Owner { Paw, User, Extension }                              │
 │ bake scheduler = Upkeep "Bakes": tier 3 producers, freeze, media bakes                                │
 └──────────────▲───────────────────────────────────────────────┬────────────────────────────────────────┘
                │ reads, edits as pure functions                  │ rtrb Msg (GraphPlan, compiled events)
 ┌──────────────┴──────────── model (paw-core/model → paw-model) ─┼────────────────────────────────────────┐
 │ Project                                                        │                                         │
 │  ├─ tracks: Track (one container type; a tree by `parent`)     │                                         │
 │  │    ├─ kind: Option<KindId<TrackFamily>>, meta               │                                         │
 │  │    ├─ lanes: [Lane { kind: Option<KindId<StreamFamily>>,    │  (C3; today one row = lane 0)          │
 │  │    │          role: Source | Take{of} | Derived(Recipe),    │                                         │
 │  │    │          clips }]                                      │                                         │
 │  │    │     Clip { content (kind: KindId<ClipFamily>), link: Option<Linked<NotesDef>>,                   │
 │  │    │            modifiers: Vec<Modifier> }                  │                                         │
 │  │    ├─ automation (today's Track.lanes)                      │                                         │
 │  │    └─ mix: Option<Mix { role, fader, sends, devices,        │  (C4; today these are Track fields)    │
 │  │                  graph: Option<Arc<Graph>> }>               │                                         │
 │  ├─ defs: Defs<RackDef> (racks.json), Defs<NotesDef> (linked/)  │                                         │
 │  └─ sections: ext/<name>/ (bytes), templates/<kind>/ (store)    │                                         │
 │ Graph (owner-free): Split { NodeId, KindId<SplitFamily>, values, branches, macros, mods,                │
 │                             linked: Option<Linked<RackDef>> } · Node { Device(DeviceId) | Split }       │
 │ Stored<F> { kind, version, data: Arc<Value> } → Loaded<F, T> { Ready | Newer | Absent }                │
 └────────────────────────────────────────────────────────────────┼────────────────────────────────────────┘
                                                                  │
 ┌──────────── engine: audio thread, fixed blocks, no lock, no allocation, no wait ─▼──────────────────────┐
 │ processors (a track with a mix has one) · GraphPlan (one Box<[f32]>, ops, Buf) · tier 1 producers only │
 └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

 Outside the kernel, with no paw dependency: crates/chain-syntax (winnow, trivia, recovery),
 chain-lsp (lsp-server), the chain command. paw gives a host schema (chain_schema 2) and a context.
```

### 2.2 How data flows from source to sound

```text
 source lane (truth) ──clip──▶ modifier stack (tier 2, same stream type, PassThrough when absent)
        │                              │  ChainKey = BLAKE3(source stamp, then each entry that is on)
        │                              ▼
        │                       compiled events ──▶ engine (tier 1: the Mix graph, audio and MIDI)
        │
        └──▶ producer branch of the container's chain document (`produce`)
               tier 2: ExternJob or built-in, in the turn, under 50 ms
               tier 3: bake job on the scheduler (render, extract, video), kept result
                   └──▶ derived lane (Keep when the producer is absent; stale mark while it bakes)
                          Apply: the result becomes a source lane, one undo step
```

### 2.3 The families

| Family | `NAME` | `ABSENT` | Rust `S` (mirror) | Built-in entries (owner `paw`) | Bundle |
| --- | --- | --- | --- | --- | --- |
| `ClipFamily` | `clip` | `Keep`: the kept sound plays | `ClipKindMeta { version, gives: KindId<StreamFamily> }` | `midi`, `audio`, `nest` | A2 |
| `StreamFamily` | `stream` | `Keep`: the lane keeps its clips and plays nothing new | `StreamMeta { time: Samples, Beats, Seconds, None }` | `midi`, `audio` (later `text`, `keyframes`) | A2 |
| `TrackFamily` | `track` | `Keep`: a label and defaults only | `TrackKindMeta` | none (today's kinds are extensions) | A2 |
| `MetaFamily` | `meta` | `Keep` | `MetaMeta { version }` | none | A2 |
| `SplitFamily` | `split` | `PassThrough`: the first branch in series | `SplitImpl { Builtin(BuiltinSplit), Device { factory } }` | `chain`, `layer`, `band`, `ms`, `lr`, `key`, `vel`, `select`, `outs` | A1 |
| `ModifierFamily` | `modifier` | `PassThrough`: the entry waits | `ModImpl { Builtin, Extern { version, local } }` | `transpose`, `velocity`, then S2 kinds | M1 |
| `ModulatorFamily` | `modulator` | `PassThrough`: the base value | `ModulatorImpl` | `macro`, `lfo`, `follower`, `midi`, `random` | TASK-285 |
| `ProducerFamily` | `producer` | `Keep`: the last kept result | `ProducerImpl { Builtin, Extern, Bake }` | `render` (freeze) | C5 |
| `TemplateFamily` | `template` | `Refuse`: list it, do not make it | `TemplateMeta { version, verb: Make, Apply }` | `track`, `group`, `rack`, `device`, `export`, `stack`, `workspace` | B3, B8 |
| `DeviceFamily` | `device` | `PassThrough`: bypass, values kept | (own `Registry` in paw-engine) | built-in devices | TASK-97 |

Every family keeps the bytes of an unknown kind. The absent rule says
what paw does. It does not change what paw saves.

Lua registries with no Rust mirror stay Lua only: subproject kinds,
insert kinds, text buffer kinds, picker sources and the rest. A family
gets a Rust mirror only when the kernel saves or compiles its data.

### 2.4 The core contracts

Rust (in `paw-core/src/model/`, later `paw-model`; no OS call, no `mlua`):

| Contract | Shape | From |
| --- | --- | --- |
| `Family` (sealed) | `const NAME: &str; const ABSENT: Absent;` | RUST 2 |
| `KindId<F>` | `Arc<str>` with `PhantomData<fn() -> F>`, `FromStr`, serde as text | RUST 2, K1 |
| `Version`, `Stored<F>`, `Loaded<F, T>`, `Versioned` | as RUST 2 | RUST 2 |
| `Owner`, `Kinds<F, S>` | shadow stack; `put`, `get`, `remove`, `unload`, `owned_by` | RUST 2, K6 |
| Id new types | `DeviceId`, `NodeId`, `ParamKey`, `DefId<D>`; later `TrackId`, `ClipId` | RUST 2, L6 |
| `Linkable`, `Linked<D>`, `Defs<D>`, `Keyed<K>` | L1 to L3 | RUST 3.2, built TASK-279 |
| `Graph`, `Split`, `Branch`, `Node`, `GraphError`; `model/graph/edit.rs` | owner-free, pure edits | DG 4.3, RUST 6.2, CONT C0, L5 |
| `GraphPlan`, `Op`, `Buf`, `compile` | private fields, one allocation | RUST 6.2 |
| `Modifier`, `Builtin`, `ModImpl`, `ChainKey`, `evaluate`, `Progress`, `ExternJob`, `RunExtern`, `ModError` | RUST 4.2 | MOD, RUST |
| `Sections`, `Section`, `RelPath` | bytes of `ext/<name>/` and `templates/` | M10 2.6, RUST 3.2 |
| `ParamSchema` | JSON Schema words plus `unit`, `stream`, `main` | M10 2.8, C4 |
| `ScheduleTime`, `Clock`, `Agenda` (union, `quiet()`), `Upkeep`, `Upkeeps`, `Outcome`, `Woken`, `Doorbell` | RUST 5.2 | EVL, RUST |
| `Lane`, `Role`, `Recipe`, `Mix`, `OwnerRef` | CONT 3.1 with K3 | CONT |
| `chain_syntax::{parse, lower, format, Diagnostic, HostSchema, Context}` | no paw type | DG 10, CONT 7, RUST 6.3, C1 |

Lua and Teal (in `runtime/lua/paw/`, records in `contracts.tl`):

| Contract | Shape | From |
| --- | --- | --- |
| `paw.registry` | the one Lua registry type; built-ins are entries of owner `paw.<feature>` | M10 1.1, 2.2 |
| `paw.kinds.define(family, name, spec)` | `version`, `encode`, `decode(stored, version)`, `describe`, family fields; mirrors into `Kinds<F, S>` through `paw.api.kinds_put` | M10 2.1, RUST 3.2 |
| `paw.meta.define(key, spec)` | declares a `meta` key | M10 2.1 |
| `paw.modifier.register(kind)` | `ModifierKind<P>` record; `apply(cols, p, ctx)` over `NoteColumns`; `ctx.rng(name)` | MOD 3.5 |
| `paw.templates.define(kind, spec)`, `paw.store` | `TemplateKind` record (T1); five layers (T2) | M10 2.4, TASK-298 |
| `paw.project.section(name, spec)` | `ext/<name>/` | M10 2.6 |
| `paw.graph.of(owner)` | a graph handle; every graph function takes it | CONT C0 |
| `paw.editor.define(stream, view, impl)`, `paw.editor.current(stream)` | P4 | M10 2.7, CONT 5.1 |
| `paw.chain.lint.add(code, fn)` | gets the lowered graph | DG 10.4 |
| `api.settle()`, `api.clock()`, `api.pending()` with `ready`, `quiet` | EVL 5.6 | EVL |

The rule for every contract: **a built-in registers through the same
public `paw.*` function that an extension uses** (M10 2.2), and **no Lua
runs while Rust holds a borrow of `Session`** (RUST 2.2).

---

## 3. The corrected milestones

Replaced by V2.10 where they differ.


Rules from the owner that this plan obeys:

- m-11 (notation and utau to Rust): do not start.
- m-13 (the window): only when the owner says. paw-gui is paused.
- m-14 (DAW parity): do not implement until the owner says.
- The focus order puts m-2, m-3, m-4 and m-9 before m-10. m-3 and m-4
  have no open ticket. m-2 has one (TASK-222.5). m-9 has the website
  lane. Question Q1 asks the owner to let phase 1 run beside them.

A new milestone is proposed: **m-17 "Tracks as containers: lanes, mix and
producers"** (the steps C3 to C6 of CONT). The model work is large and
user-visible, and it is not "architecture" only.

| Milestone | Stays | Changes | Moves | New | Merges | Dropped |
| --- | --- | --- | --- | --- | --- | --- |
| m-0 browser | TASK-29 to 36, 50, 111, 112, 300 | TASK-30 waits for TASK-95.3; the `Doorbell` has a `#[cfg]` for the browser (no `mio` on WASI) | none | none | none | none |
| m-1 platforms | TASK-38 to 53 | TASK-43 notes: `Clock` and `Doorbell` are the time and wake seams | none | none | none | none |
| m-2 sections | TASK-222.5 (built-in presets, list, stem gain: AC 2, 4, 5 without layers, 6 to 8) | TASK-222.5 loses AC 1 and 3 (layers, save to project) | AC 1 and 3 move to bundle B3 (m-10) as its first user | none | none | none |
| m-3 fast and lean | none open | propose to close | none | none | none | none |
| m-4 editing | none open | propose to close | none | none | none | none |
| m-5 extensions | TASK-1, 2, 3, 9, 10, 23, 86, 214, 217, 290 | TASK-75 becomes the parent of M1 to M6; TASK-214 adds no model field (M7); TASK-10 M6 and M7 wait for M1; TASK-23 B2, B3 and E1 leave it; TASK-9 waits for M3 and Q5 | TASK-23 B2, B3, E1 go to B6 (m-10) | TASK-75.1 to 75.6 (M1 to M6) | none | none |
| m-6 release | TASK-22, 24, 105 | TASK-105 is the last ticket of m-10's work; TASK-24 re-approves e2e golden files after C3 changes the files | none | none | none | none |
| m-7 local tools | TASK-220, 221 | after phase 6 | none | none | none | none |
| m-8 Teal tools | TASK-72, 133 | TASK-133 before A2's docs (it generates the records of `paw.kinds`) | none | none | none | none |
| m-9 docs | TASK-89, 93, 94, 107, 109 | each bundle brings its reference and explanation pages | none | none | none | none |
| m-10 architecture | TASK-95, 95.1, 95.3, 96, 96.2, 97, 98, 99, 132, 206, 208, 215, 218 (AC 4 to 7), 260 | TASK-96.2 gets `ParamSchema`; TASK-97 gets owners on factories; TASK-208 widened (lsp subjects, zoom, help pages, `paw.layouts`); TASK-298 joins and is split | TASK-298 from m-16 | A2 Kinds families, B3 store and sections, B4 linked clips on `Defs`, B6 built-in clip kinds, B7 editor subject, B8 Template | TASK-292 + 293 + 296 → EL1; TASK-294 + 295 → EL2; TASK-177 → B7; TASK-218 AC 1 to 3 → TASK-3 + 217 (running) | M10's B1 (kinds design note): this plan replaces it; TASK-297 stays deferred until a sandbox ticket |
| m-11 Rust extensions | TASK-135 to 142, 222.9 | TASK-135 (design) reads A2, M3 (the `ExternJob` shape), B7 | none | none | none | none |
| m-12 testing | TASK-145, 147, 148, 149, 149.1, 149.3, 149.4, 158, 291 | TASK-147 lands in batch 18; EL1 finishes its honesty part (TASK-296). `T.settle` keeps its name; EL2 changes its inside | none | none | none | none |
| m-13 window | TASK-64, 77.4, 96.5, 160, 193 | paused; C6 adds a picture element to `paw-scene`, which can stop the window build (report it then) | none | none | none | none |
| m-14 parity | all | not started. Notes for later: TASK-237 after B6; TASK-234 after TASK-10; TASK-238 (send automation) and TASK-240 (wide buses) after C4, because sends move into `Mix`; TASK-231.1 shares OSC with TASK-23 C2; TASK-232.1 after TASK-208; TASK-228.3 is a model field | none | none | none | none |
| m-15 UX polish | TASK-299 | none | none | none | none | none |
| m-16 devices graph | TASK-280 to 289 | TASK-279 lands as built, then A1 aligns it; TASK-280, 282 depend on A1; TASK-284 depends on B8 and C4 and uses `templates/rack/`; TASK-287 takes an optional host context; TASK-285 uses `ModulatorFamily` | TASK-298 to m-10 | A1 graph alignment; CL2 chain language 2 | none | none |
| m-17 containers (new) | none | none | none | C3 lanes, C4 optional mix, C5 producers, C6 video and lenses | CONT C2 goes into A2 | none |

---

## 4. The roadmap of bundles

Replaced by V2.11 and V2.14 where they differ. The bundle C3 to C6 of this section are LA, MX, RD and VD in version 2.


### 4.1 The bundles

Each bundle is one Opus agent. Each leaves paw working and brings its
tests and docs in the same commits. Size: S about a day, M a few days, L
a week of agent work.

| Id | Bundle | Tickets | Size | Depends on | Milestone |
| --- | --- | --- | --- | --- | --- |
| **Phase 0: land what runs** | | | | | |
| R18 | Batch 18: the stepped backend, the hash count, the runner | TASK-147, TASK-148 parts, TASK-145 parts (branches STEP, HASH, RUNNER) | | | m-12 |
| R19 | Batch 19: TASK-279 as built; TASK-281 (`winnow`) | TASK-279, 281 | | | m-16 |
| run | Running agents | TASK-215 + 208; TASK-3 + 217 (+ 218 AC 1 to 3); TASK-287; TASK-107; TASK-98 | | | m-10, m-5, m-16, m-9 |
| **Phase 1: the shared core and the loop** | | | | | |
| A1 | Graph alignment and the shared core types | new; finishes TASK-279's alignment | M (5 to 7 h for the graph, plus the core types) | R19 | m-16 |
| EL1 | Event loop: one turn, one clock rule, an honest stepped backend | TASK-292 + 293 + 296 | L | R18 | m-10 |
| P95 | paw-model 1+2 | TASK-95.1 | M | merges after A1 (same `model/` files) | m-10 |
| X5 | Export presets, built-ins only | TASK-222.5 (reduced) | M | none | m-2 |
| T96 | Typed API 2 with `ParamSchema` | TASK-96.2 | M | none | m-10 |
| G2 | The engine runs a graph plan | TASK-280 | L | A1 | m-16 |
| G3 | The devices view | TASK-282 | L | A1 (the owner handle) | m-16 |
| **Phase 2: kinds and the first users** | | | | | |
| A2 | Kinds families (B2 + C2) | new | L | A1, P95, TASK-208 | m-10 |
| M1 | Modifier core (MOD S1) | TASK-75.1 (new) | L | A1, Q2 answered | m-5 |
| EL2 | Event loop: agenda, doorbell, quiet | TASK-294 + 295 | L | EL1; alone in its batch with no other `session/` bundle | m-10 |
| G4 | Devices modes and keys | TASK-283 | L | G3 | m-16 |
| CL2 | Chain language 2 | new | M | TASK-287 merged | m-16 |
| B7 | Editor subject and window instances | new + TASK-177 | L | none (phase 2 for file peace with G3) | m-10 |
| G8 | Taps, the `outs` split, `:keys` | TASK-286 | M | G2 | m-16 |
| **Phase 3: lanes, store, stacks** | | | | | |
| C3 | Lanes: source and take | new (m-17) | L | A2, Q3 | m-17 |
| B3 | Store and project sections; export preset layers | new + TASK-222.5 AC 1, 3 | M | A2, Q4, Q6 | m-10 |
| M2 | Built-in modifier kinds | TASK-75.2 (MOD S2) | M | M1 | m-5 |
| M3 | Extension modifier kinds (`ExternJob`, `RunExtern`) | TASK-75.3 (MOD S3) | L | M1, EL1 | m-5 |
| B4 | Linked clips on `Defs` | new | M | M1 | m-10 |
| G6 | Macros, modulators and links | TASK-285 | L | G2, G3 | m-16 |
| MD4 | Media M4 onward, part 1: the scheduler with provenance; media modifiers on `Modifier` | TASK-10 (part) | L | M1 | m-5 |
| **Phase 4: mix, templates, built-ins** | | | | | |
| C4 | Optional mix; `Track.graph` → `Mix.graph` | new (m-17) | L | C3, G2 | m-17 |
| B6 | Built-in clip kinds through the public API | new + TASK-23 B2, B3, E1 | L | A2, C3 | m-10 |
| B8 | Template (the rest of TASK-298) | TASK-298 | L | B3, B4, A1 | m-10 |
| M4 | Stack views and `:clip.recipe` on `chain-syntax` | TASK-75.4 (MOD S4) | L | M2, M3, G4 (`device_rows`) | m-5 |
| FZ | Freeze through the scheduler | TASK-214 (limited) | M | MD4 | m-5 |
| **Phase 5: racks, producers, the roll** | | | | | |
| G5 | Racks and templates | TASK-284 | L | B8, C4 | m-16 |
| C5 | Derived lanes and producers; freeze becomes `render` | new (m-17) | L | C4, M3, FZ, CL2, Q5 | m-17 |
| M5 | The roll and readers of the stack | TASK-75.5 (MOD S5) | L | M4 | m-5 |
| G11 | Extension split kinds | TASK-288 | M | G6 | m-16 |
| M6 | Stack templates | TASK-75.6 (MOD S6) | S | M4, B8 | m-5 |
| DRV | Drivers | TASK-86 | M | G6 | m-5 |
| CK | Clip kinds: signals and the other extensions | TASK-23 C1 to C3, E2 to E5 | L | B6 | m-5 |
| **Phase 6: video, docs, extensions, lock** | | | | | |
| C6 | Video and lenses | new (m-17) | L | C5, CK (C1, E4), Q7 | m-17 |
| G13 | Devices graph docs final pass | TASK-289 | M | G4, G5 | m-16 |
| PF | perform | TASK-9 | L | M3, Q5, the owner's approval | m-5 |
| WA | WebAssembly devices and extensions | TASK-97, TASK-1, TASK-2 | L | A2 | m-10, m-5 |
| PM3 | paw-model 3 | TASK-95.3 | M | A2, C4 | m-10 |
| LOCK | `@internal`, API lock, untangle, `groma` | TASK-132 → 105 → 206 → 220, 221 | M each | all of the above | m-10, m-6, m-7 |

Other tickets keep their place and run where a slot is free: TASK-99,
TASK-133 (before A2's docs), TASK-145, 148, 149.x, 158, 291 (m-12),
TASK-109, 93, 94, 89 (m-9), TASK-260, TASK-290, TASK-299.

### 4.2 The dependency picture

```text
Phase 0   R18 ─────────────┐        R19 (279, 281) ──┐      running: 215+208 · 3+217 · 287 · 107 · 98
                           │                         │
Phase 1   EL1 (292+293+296)│        A1 graph+core ◀──┘──┬──▶ G2 (280) ──┬──▶ G8 (286)
           │               │         │   │              └──▶ G3 (282) ──┼──▶ G4 (283)
           │               │         │   └──▶ P95 (95.1, merge after A1) │
           │   X5 (222.5) · T96 (96.2) · web lane                        │
           ▼                         ▼                                    │
Phase 2   EL2 (294+295)      A2 kinds (B2+C2) ◀── P95, 208               │
                             M1 modifier core ◀── A1, Q2                  │
                             B7 editor subject + 177   CL2 ◀── 287       │
                                     │                                    │
Phase 3   C3 lanes ◀── A2, Q3        B3 store ◀── A2, Q4, Q6              │
          M2 ◀── M1   M3 ◀── M1, EL1   B4 linked clips ◀── M1   MD4 ◀── M1│
          G6 (285) ◀── G2, G3 ◀───────────────────────────────────────────┘
                                     │
Phase 4   C4 mix ◀── C3, G2    B6 built-in kinds ◀── A2, C3    B8 Template ◀── B3, B4
          M4 stack views ◀── M2, M3, G4      FZ (214) ◀── MD4
                                     │
Phase 5   G5 racks (284) ◀── B8, C4   C5 producers ◀── C4, M3, FZ, CL2, Q5
          M5 roll ◀── M4   G11 (288) ◀── G6   M6 ◀── M4, B8   DRV (86) ◀── G6   CK ◀── B6
                                     │
Phase 6   C6 video ◀── C5, CK, Q7   G13 (289)   PF (9) ◀── M3, Q5   WA   PM3   LOCK (132→105→206→221)
```

### 4.3 The critical path

```text
R19 → A1 → A2 → C3 → C4 → C5 → C6
                 └──────────────→ B6 (built-ins through the API)
R19 → A1 → G2 → C4 → G5 (racks)          A2 → B3 → B8 → G5
A1 → M1 → M3 → C5
```

The longest chain is R19 → A1 → A2 → C3 → C4 → C5. A1 is short and
gates eleven bundles, so it starts first in phase 1, with the strongest
agent. A2 is the second gate.

### 4.4 Parallel work (up to 8 agents)

| Phase | Slots |
| --- | --- |
| 1, first half | A1 · EL1 · X5 · T96 · P95 (merges after A1) · TASK-287 (running) · TASK-215+208 (running) · web (TASK-107 or 109) |
| 1, second half | G2 · G3 · EL1 (if still open) · X5 · T96 · TASK-287 · TASK-3+217 · web |
| 2 | A2 · M1 · EL2 (no other bundle that edits `session/` idle code in its batch) · G4 · CL2 · B7 · G8 · TASK-133 |
| 3 | C3 · B3 · M2 · M3 · B4 · G6 · MD4 · one m-12 ticket |
| 4 | C4 · B6 · B8 · M4 · FZ · two of m-9, m-12 |
| 5 | G5 · C5 · M5 · G11 · M6 · DRV · CK |

File conflicts to keep apart in one batch: A1 and P95 (`model/`); A2 and
C3 (the track fields); C3 and B6 (`views/arrange_track.tl`); C4 and G2
(the sync); EL2 and any bundle that edits `Session::idle`.

### 4.5 Work that must not start yet, because it would be built twice

| Work | Why | Starts after |
| --- | --- | --- |
| TASK-284 racks and templates | its store and its paths change (T2), and its link type changes (L1, L2) | B8, C4 |
| TASK-298 as written (a Rust trait) | T1 | B3 |
| TASK-222.5 AC 1 and 3 (layers, save to `project.toml`) | the store gives the layers once | B3 |
| TASK-23 B2, B3, E1 | they draw custom clips on a second path beside the built-ins | B6 |
| TASK-10 M6, M7 (media modifiers) | they need the one `Modifier` struct | M1 |
| A model field for freeze in TASK-214 | C5 moves freeze into a derived lane | C5 (TASK-214 builds only the job and the key) |
| Any change of `meta.takes` or `takes.tl`'s data | C3 moves takes to lanes once | C3 |
| A `takes` field on clip kinds | P3 | never |
| TASK-9 perform | the applied mode and the kind need M3 and the owner | M3, Q5 |
| TASK-285's own modulator registry | the family comes from A1 | A1 |
| A second registry type in TASK-208 | `paw.registry` has the shadow stack | never |
| TASK-95.3 (split `model.rs`) | A2 and C4 move many model fields | A2, C4 |
| TASK-105 API lock | `paw.kinds`, `paw.templates`, `paw.modifier`, `paw.editor`, `paw.graph.of` are new | LOCK |
| TASK-237 audio clip view (m-14) | an editor of the built-in kind `audio` | B6, and the owner |
| A `rowan` rewrite of `chain-syntax` | C1 | only on a need found in TASK-287 |
| A Lua or own-format parser for `:clip.recipe` | M8 | never |
| m-11 (TASK-135 to 142) | the owner said not to start | the owner |

---

## 5. The merged questions for the owner

All questions are answered (owner, 2026-11-23, seven rounds). See V2.0.


### 5.1 How the 44 questions merge

The four designs ask 44 questions (M10 14, MOD 13, RUST 4, CONT 13).
The owner said that agents own design and ask only about what the user
sees or what is risky. So this plan answers internal design itself and
asks only the rest.

| Source questions | Result |
| --- | --- |
| M10 1, 2, 4, 5, 8, 9, 10, 11, 13 | Answered by this plan (K1 to K10, M2, P1, P5; m-11 waits as the owner said). Not asked. |
| M10 3 | Part of Q4. |
| M10 6, MOD 8 | Merged into Q5. |
| M10 7, DG 13 (answered before; this plan changes the paths) | Part of Q4. |
| M10 12 | Q3. |
| M10 14 | Answered (M8). Part of Q2 as a fact. |
| MOD 1, 3, 4, 7, 9, 10 | Answered: no trait (M1); track and lane stacks later; the owner already chose "the notes play, the entry waits"; linked stack templates later; the score reads the source. Not asked. |
| MOD 2, 5, 6, 11, 12, 13 | Merged into Q2 (the stack as the user sees it). |
| RUST R1, R2, R3 | Internal. Answered yes. Not asked. |
| RUST R4 | Answered: keep `winnow` (C1). Not asked. |
| CONT 1, 2, 3, 4 | Merged into Q3. |
| CONT 5, 6, 7, 10 | Merged into Q5. |
| CONT 8 | Answered (a stale mark; a key never waits for a producer). |
| CONT 9 | Q7. |
| CONT 11, 12, 13 | Answered by the roadmap and C2, C3. |
| EVL 1 to 8 | Answered by their recommendations, as TASK-292 to 297 already say. EVL 8 (timing) is part of Q1. |
| new | Q1 (focus order), Q6 (Template words). |

### 5.2 The questions

Blocking first. "Blocks" names the bundles that cannot start without the
answer.

| # | Question | Recommendation | Blocks | When |
| --- | --- | --- | --- | --- |
| Q1 | The focus order says m-2, m-3, m-4 and m-9 come before m-10. m-3 and m-4 have no open ticket, m-2 has one, m-9 has the website lane. May phase 1 (A1, EL1, P95, T96) and then phase 2 run beside them, and may m-3 and m-4 close? | Yes. A1 is part of m-16, which runs now. The m-10 bundles touch no file of TASK-222.5 or of the website. | EL1, P95, T96, A2, B7, EL2 | Now: blocks phase 1 |
| Q2 | TASK-75, the modifier stack as the user sees it: a panel of its own (`<Space>cs`, `stack://`, the keys of the device inspector); `<Space>ca` adds, `<Space>cA` applies all; in the panel `\a` applies up to the entry and `\t` saves a template; the roll shows the notes as ink and the result as ghosts, `\m` changes the look; Apply only of a prefix (refuse one entry in the middle); `:clip.override` stays as a short command; the clip label shows `+3 q16 hum`, then `ƒN`, and `?` for an entry that waits; `:clip.recipe` is chain text with `off` as a flag (M8). | Yes to all, as MOD recommends, with the one change M8. | M1 (Apply, `:clip.override`), M4, M5 | Now: blocks phase 2 (M1) |
| Q3 | Containers: keep the word "track"; generalize `Track` in place (a tree by `parent`, typed lanes with roles source, take and derived, an optional mix); a track can have no mix (a folder that does not sum, a track of video or notes only); a lane's kind is a stream kind (`midi`, `audio`, `video`, `text`), and lane 0 takes every kind as today. | Yes. The lane kind is a stream kind, not a clip kind (K3). | A2 (the C2 part), C3, C4 | Before phase 2 ends |
| Q4 | Project files: an extension keeps files in `ext/<name>/` of the project, kept byte for byte when it is absent. Every template kind lives in `templates/<kind>/` in the project and in `$XDG_DATA_HOME/paw/templates/<kind>/` for the user, so rack templates move from `racks/` (the approved devices design) to `templates/rack/`, and export presets become template kind `export` in place of `project.toml [export.presets]`. Linked rack definitions stay in `racks.json`. | Yes. One walk, one clash rule, one picker. | B3, G5 (TASK-284) | Before phase 3 |
| Q5 | Producers and perform: derived lanes in three tiers (the audio graph, a kernel function under 50 ms, a bake job), and no producer on the audio thread; a producer can read lanes of another track (with a cycle check); an extension's producer can run an outside process in a bake job, with a scratch home, and its result is kept so the project plays without it; freeze becomes the producer `render`. perform stays "write the MIDI and keep provenance", and a `perform` modifier kind can come later. | Yes. The outside process is the main risk: it runs only in a bake job, as plugins run in their sandbox. | C5, PF (TASK-9) | Can wait until phase 4 |
| Q6 | TASK-298 says "a Rust trait". The plan makes the Template contract a Teal record in core (`paw.templates.define`) with a Rust list of kinds, and adds a Rust trait when two Rust template kinds exist. Extensions still define their own format and can generate templates. | Accept the new words of AC 1. The intent (one generic contract in core) holds. | B3 (store shape), B8 | Before phase 3 |
| Q3b | (part of Q3, for docs) The user word for a row inside a track is "lane"; today's automation lanes keep the word "lane" in the user guide, and the model field becomes `automation`. | Yes. | C3 docs | Before C3 |
| Q7 | Video in the terminal: a monitor view draws pictures with half blocks, and with the kitty protocol where the terminal has it; the arrange view draws a video lane as a strip with times and names. | Yes. | C6 | Can wait until phase 5 |

Questions that do not block anything now and need no answer: the
event-loop questions (answered by TASK-292 to 297), the devices-graph
questions (answered in TASK-278), and RUST R1 to R4.

---

## 6. The ticket plan for phases 1 and 2

Replaced by V2.15 where they differ.


Nothing below is written to the Backlog. The coordinator or the product
owner agent makes these edits. "NEW-x" is a placeholder for the id that
`backlog task create` gives.

### 6.1 Edits for phase 0 (now)

| Ticket | Edit |
| --- | --- |
| TASK-279 | Add a note: "Landed as built in batch 19. The alignment to `architecture-plan.md` is NEW-A1." Close it when batch 19 merges. |
| TASK-281 | Add a note: "Keep `winnow` (`architecture-plan.md` C1). Header names no track." Close it when batch 19 merges. |
| TASK-287 | Add AC: "The language server and `chain check` take an optional host context (external streams and sinks, JSON, `chain_context`), empty by default. No lint, completion or hover assumes that every port is audio. The codes E213 to E218 and W302 stay free." Add a note: "If the server needs a lossless tree inside a line, write it in the notes; do not rewrite the parser in this ticket." |
| TASK-3 | Add a note (if not there): "The lazy `kind` trigger is a key of any `paw.registry`. TASK-218 AC 1 to 3 are done in this branch." |
| TASK-218 | Mark AC 1 to 3 as done by TASK-3 + 217 when it merges. Add AC: "`midifile.tl` names no extension's device kind (a device kind field `drum_channel`), and reads no `meta.lyric` (A2 makes `Note.lyric`)." Add a dependency on NEW-A2 for the lyric part. |
| TASK-208 | Add AC: "Language server subjects, view zoom, help pages and `paw.layouts` are registries. `options` uses the shadow stack of `paw.registry`. No second registry type." |
| TASK-298 | Move to m-10. Replace AC 1 with: "A Teal contract `TemplateKind` in `contracts.tl` and `paw.templates.define`; template kinds are entries of `Kinds<TemplateFamily, TemplateMeta>` in Rust (no Rust trait until two Rust kinds exist); a test registers a kind from Lua." Add to AC 2: "in `templates/<kind>/` of the project, the user data folder and the runtime." Add dependencies on NEW-B3 and NEW-B4. Add a note: "Split: the store is NEW-B3; this ticket is the rest (bundle B8)." (Waits for Q6.) |
| TASK-284 | Add dependencies on TASK-298 and NEW-C4. Change "`:rack.save` and `:rack.load` with user, project and bundled places" to "through the store (`templates/rack/<name>.chain`)". (Waits for Q4.) |
| TASK-23 | Add a note: "B2, B3 and E1 move to NEW-B6 (m-10). This ticket keeps A2b, C1 to C3, E2 to E6." Remove AC 2 (B2 and E1) and move it to NEW-B6. |
| TASK-10 | Add a note: "M6 and M7 use `Modifier { kind, version, on, scope, params }` of TASK-75.1. The scheduler is the `Bakes` `Upkeep`." Add a dependency on TASK-75.1 for M6 and M7. |
| TASK-214 | Add AC: "No new model field for freeze: `meta.frozen` stays until the producers bundle (m-17) moves freeze to a derived lane." |
| TASK-97 | Add AC: "Each factory entry has an `Owner` and a `KindId<DeviceFamily>`; an unload removes the entries of its owner." |
| TASK-96.2 | Add AC: "One `ParamSchema` (JSON Schema words, `unit`, `stream`, `main`) that `schemars` gives for built-ins; the chain host schema and the Teal `ParamSpec` use it." |

### 6.2 Phase 1

**NEW-A1 (m-16, HIGH). "Devices graph: align the kernel model to the architecture plan (owner-free graph, pure edits, owner handle, typed ids, Linkable and `Defs`, the shared kinds core)"**

Description: TASK-279 landed with `Track.graph`, `Linked<D, O>` with
string keys, `Project.racks`, split kinds as `Word` and the edits in the
session. NEW-A1 makes the shape of `architecture-plan.md` sections 1.1
(K1, K6, K7, K11) and 1.3 (L1 to L8), one time, before TASK-280 and
TASK-282 build on it. It also adds the shared core types that A2, M1 and
B3 use, so the graph does not change twice. Read
`architecture-plan.md`, `rust-architecture.md` parts 2, 3.2, 6.2 and 10,
and the TASK-279 notes. Do not change the engine (TASK-280) or the file
format of `devices.json` and `racks.json` beyond the id new types (the
text stays a number).

Acceptance criteria:

1. `model/kinds.rs` has `Family` (sealed), `Absent`, `KindId<F>`
   (dot-joined words, `FromStr`, serde as text), `Version`, `Stored<F>`,
   `Loaded<F, T>`, `Owner` and `Kinds<F, S>` with `put`, `get`,
   `remove`, `unload`, `owned_by` and a shadow stack. The families of
   table 2.3 exist as types. A Rust test puts two owners on one key,
   unloads the top one, and gets the lower one back.
2. Split kinds are `KindId<SplitFamily>` in the model, and the built
   registry is `Kinds<SplitFamily, SplitImpl>`. An unknown split kind
   loads, saves the same bytes, and `Graph::validate` gives
   `GraphError::AbsentKind`.
3. `model/graph.rs` and its submodules name no `Track` and no track id.
   Each edit is a pure function `fn(&Graph, ..) -> Result<Graph,
   GraphError>` in `model/graph/edit.rs`. `session/document/graph.rs`
   only finds the owner, calls the function, makes one undo step and
   gives the message. The existing tests of TASK-279 pass with no change
   of keys.
4. `DeviceId`, `NodeId`, `ParamKey` and `DefId<D>` replace `Id` in the
   graph, racks and links. `devices.json` and `racks.json` do not change.
5. `Linked<D: Linkable> { of: DefId<D>, overrides: D::Overrides }`,
   `Defs<D>`, and `Keyed<K: Ord>` with the built `follow` rule.
   `RackDef: Linkable` with `RackOwn { ids, values: Keyed<ValueKey> }`.
   `ValueKey` is an `enum` whose text form is the chain reference
   (`#5.ratio`). `Project.racks` is `Defs<RackDef>`. The linked rack
   tests pass.
6. No `meta` on a split. A test that set split `meta` is removed or moves
   to a declared key.
7. `paw.graph.of(owner)` gives a handle, and each function of
   `paw.graph` takes it (`{track = id}` today). The Teal types and
   `docs/reference/api.md` come from the doc comments.
8. If TASK-281 merged: its mapping to the model (`chain_schema.rs` and
   the lowering) uses the new types, and its tests pass.
9. Docs: `docs/reference/project-files.md` and the graph pages are true;
   Vale reports 0 alerts.

Dependencies: TASK-279 and TASK-281 merged (batch 19). Blocks TASK-280,
TASK-282, NEW-A2, TASK-75.1, TASK-95.1 (merge order).

**TASK-292 becomes EL1 (m-10, HIGH). Title: "Event loop S1+S2+S5: one turn function, one clock rule, an honest stepped backend"**

Edits: merge TASK-293 and TASK-296 into it (archive both with a note
"merged into TASK-292"). Description: `event-loop-review.md` S1, S2 and
S5, with the Rust shapes of `rust-architecture.md` 5.2 and
`architecture-plan.md` E1, E2, E5. Do after batch 18.

Acceptance criteria:

1. `Kernel::turn(now: ScheduleTime) -> Agenda` is the one turn.
   `run`, `api.step`, `api.wait` and `request` (through `close_turn` and
   `agenda`) use it. `Shared::turn`, the second `IDLE_PERIOD` and the
   work inside `api.events_take` are gone. A Rust test with a recording
   frontend and `Clock::Manual` records the same order of steps through
   `run` and through `api.step` (EVL I1).
2. The order of a turn has a slot for `ExternJob`s after the sync (E5),
   empty until TASK-75.3.
3. `enum Clock { Wall, Manual }` and `ScheduleTime` replace
   `Arc<dyn Clock>`. The five `clock` fields of the session go;
   `Upkeep`-style polls get `now`.
4. `crates/paw-core/clippy.toml` refuses `Instant::now` with a reason;
   each budget site has `#[expect(clippy::disallowed_methods, reason)]`.
   `cargo clippy` passes.
5. The sweep merge and the touch release run on the schedule clock, each
   with a test on the manual clock that steps the clock.
6. `StreamInfo` reports `Backend::Step`; `null_steps` is gone;
   `api.wait_blocks` on a backend that is not stepped gives an error;
   `:engine threads=` does not wait 500 ms.
7. A reference page "The order of a turn" in `docs/reference/` names
   the same steps as the test of AC 1. Vale reports 0 alerts.
8. The full Lua suite passes. The tests whose result changed with the
   order (MIDI before timers in scripts) are listed in the notes.

Dependencies: batch 18 (TASK-147). Blocks TASK-294.

**TASK-95.1 (m-10). Edit:** add a note "Merge after NEW-A1; merge it after NEW-A1.
Both edit `model/`." Add a dependency on NEW-A1 (merge order only).

**TASK-222.5 (m-2). Edit:** remove AC 1 and AC 3. Add AC: "The presets
are a plain list of built-ins in one module, with a `source` field, so
that NEW-B3 adds the user and project layers with no second layering
code." Add a note: "AC 1 and 3 move to NEW-B3 (`architecture-plan.md`
T2)." In AC 5, keep the key test on the built-in presets.

**TASK-280 (m-16). Edit:** add a dependency on NEW-A1. Add AC: "The
compiler resolves `KindId<SplitFamily>` through `Kinds<SplitFamily,
SplitImpl>`; an absent kind compiles as its first branch in series with
a diagnostic. `GraphPlan` keeps its buffers in one `Box<[f32]>`, its
indices are `Buf`, and only `compile` makes one. `Msg::SetGraph` names a
processor slot, not a track."

**TASK-282 (m-16). Edit:** add a dependency on NEW-A1 (the owner handle
`paw.graph.of`).

### 6.3 Phase 2

**NEW-A2 (m-10, HIGH). "Kinds: one contract for clip, stream, track and meta kinds; the track tree and kind in the model"** (M10 B2 + CONT C2)

Description: `architecture-plan.md` 1.1 and 2.3, `m10-generalization-review.md`
2.1 and 2.2, `containers.md` C2. The built-in clip kinds become entries of
owner `paw.clips`. `RESERVED` and `ClipKindId` go. `meta.kind` becomes
`Track.kind`, `meta.group` becomes `Track.parent`, `meta.lyric` becomes
`Note.lyric`. Takes do not move here (P1). The drawing of clips does not
move here (NEW-B6).

Acceptance criteria:

1. `paw.kinds.define(family, name, spec)` puts the spec in the family's
   `paw.registry` and mirrors it into `Kinds<F, S>` through one
   `paw.api.kinds_put`. Clip, track and meta kinds use it. A test defines
   a clip kind from Lua, unloads its extension, and the project still
   opens and plays its kept sound.
2. `midi`, `audio` and `nest` are entries of owner `paw.clips` with
   `gives` = their stream kind. `RESERVED` and `ClipKindId` are gone
   (`git grep`).
3. `StreamFamily` has `midi` and `audio`; each clip kind names the
   stream it gives.
4. `Track.kind: Option<KindId<TrackFamily>>` and `Track.parent:
   Option<TrackId>`; `paw.track_kinds` and `paw.groups` read the fields;
   no runtime file reads `meta.kind` or `meta.group` (`git grep`). A
   group still sums.
5. `paw.meta.define(key, spec)` declares a key with a version; `K` names
   the owner of each declared key; an undeclared key stays as it is.
6. `Note.lyric` is a model field; `midifile.tl` writes it with no read
   of `meta`; utau reads and writes the field.
7. Each family moves in its own commit with a round trip test of the
   project folder.
8. Docs: `about-midi-as-the-truth.md`, `about-core-and-extensions.md`,
   the project files reference and the extension skill are true; an
   explanation page "About kinds" exists; Vale reports 0 alerts.

Dependencies: NEW-A1, TASK-95.1, TASK-208, TASK-133 (for the generated
records). Waits for Q3 for AC 4 only (the field names).

**NEW-M1 = TASK-75.1 (m-5, HIGH). "Modifier stacks 1: the core stack, Overrides become transpose and velocity, Apply"** (MOD S1)

Edit of TASK-75 first: status "design approved" after Q2; label it the
parent of 75.1 to 75.6; add a note that `midi-modifier-stacks.md` is
superseded where it differs by `architecture-plan.md`.

Description: `midi-modifier-stacks.md` 3.3, 3.4, 4.3, 4.4, 4.7, 4.8 and
6.3, with `rust-architecture.md` 4.2 to 4.4 and `architecture-plan.md` M1,
M2, M9. Pure Rust: no Lua kind yet (that is TASK-75.3).

Acceptance criteria:

1. `Modifier { kind, version, on, scope, params }`, `enum Builtin`
   (`transpose`, `velocity`), `ModImpl`, `ChainKey` (128-bit BLAKE3),
   `evaluate` and `ModError` (`thiserror`) in `model/modifiers.rs`;
   `ModifierFamily` built-ins have owner `paw.modifiers`.
2. `Clip.overrides` is gone. The loader folds an old `overrides` field
   into two entries and does not write it. `tests/clip_overrides.lua`
   and the sync test of copies pass with no change of keys.
3. The sync keys compiled events by the last `ChainKey`; copies with the
   same notes and the same stack compile one time (a count, as
   `COMPILES`).
4. A change of entry 3 runs entries 3 to the end only (a count).
5. `:clip.stack add|set|on|off|move|rm`, `:clip.apply [n]` and
   `:clip.apply! [n]` work, each one undo step with its message. Apply of
   an entry that is not in the prefix and Apply on a linked clip are
   refused with the texts of MOD 4.8.
6. `:clip.override` sets the `transpose` and `velocity` entries (Q2).
7. `paw.api.clip_get` gives `modifiers`; `Clip:shifted` keeps its name.
8. `track.json` writes `modifiers` with sorted keys; a change of one
   parameter is one line in `git diff`.
9. A bench scenario `stacks` in `bench/edit.lua`; no time in a test.
10. Docs: the project files reference, the arrange view and piano roll
    references (the parts on overrides); Vale reports 0 alerts.

Dependencies: NEW-A1, Q2.

**TASK-294 becomes EL2 (m-10, HIGH). Title: "Event loop S3+S4: an agenda of upkeep, the doorbell, quiet in the kernel"**

Edits: merge TASK-295 (archive it with a note). Description:
`event-loop-review.md` S3 and S4 with `rust-architecture.md` 5.2 and
`architecture-plan.md` E3, E4, M5, M6.

Acceptance criteria:

1. `trait Upkeep { fn kind(&self) -> Woken; fn poll(&mut self, now,
   &mut Vec<Outcome>); fn agenda(&self, now) -> Agenda; }` with eight
   implementations in `Upkeeps`; `Session::idle` loops over them and
   applies the outcomes. `needs_idle` and the fixed 16 ms poll are gone.
2. `Doorbell` with `mio::Waker`: worker threads `ring`, the audio thread
   only `mark`s. The main loop waits in `mio::Poll`; the `inotify`
   descriptor is a token and its thread is gone. The browser build keeps
   `recv_timeout` behind one `#[cfg]`.
3. For each `Upkeep`, a Rust test with a fake worker sees its bit after
   the work ends (EVL I4), with no sleep.
4. A quiet session after `settle` has no `next_due`, nothing in flight,
   and the loop waits with no timeout (EVL I3).
5. The safety tick (250 ms while work is in flight; 16 ms only for a
   controller that asks) counts missed wakes; the suite fails on a
   missed wake.
6. `api.settle()`, `api.clock()`, and `api.pending()` with `ready` and
   `quiet`. `T.settle` calls `api.settle`; `T.until_` fails on quiet with
   no due time. `working`, `busy`, `POLL_TURNS`, the `collector` name and
   `MANUAL = api.now() == 0` are gone from the runner.
7. Idle jobs (`paw.slices`, the collector, help) mark their timers
   `idle = true`.
8. bench: wakes a second and CPU over 30 s with a plugin, before and
   after, in `bench/RESULTS.md`.
9. Docs: the lua-testing skill, the how-to on tests, "The order of a
   turn". Vale reports 0 alerts.

Dependencies: TASK-292 (EL1). Alone in its batch with respect to
`Session::idle`.

**TASK-283 (m-16). Edit:** no change of scope. Add a note: "The stack
panel of TASK-75.4 reuses the inspector rows; keep `device_rows` as a
public function of the view."

**NEW-CL2 (m-16, MEDIUM). "Chain language 2: stream kinds, typed ports, producers, sinks and references across containers"**

Description: `containers.md` 7.3 to 7.6, with `architecture-plan.md` C2,
C3, C4, K3. The crate stays free of paw. paw writes only `audio` and
`midi` ports and no producers until the producers bundle.

Acceptance criteria:

1. The ten items of `containers.md` 7.6, with `VERSION` 2; a reader of 2
   reads text of version 1.
2. The host schema `chain_schema: 2` embeds `ParamSchema` words for
   parameters (C4), with `stream` and `main` on a `source` parameter.
3. E213 to E218 and W302, each with a golden diagnostic and a test that
   does not fire.
4. Property tests: print then parse with `produce`, sinks and external
   references; the fuzz target covers the new tokens.
5. paw: `chain_schema.rs` writes `streams` (`audio`, `midi`) and the
   ports of the built-in devices; `paw chain context <track>` writes an
   empty context.
6. `chain-lsp` completes external names and sinks from the context.
7. `chain-language.md` and `chain-schema.md` are true; every example
   parses; Vale reports 0 alerts.

Dependencies: TASK-287 merged.

**NEW-B7 (m-10, MEDIUM). "Editor subject for every note editor, and every view on window instances"** (M10 E + TASK-177)

Edits: merge TASK-177 into it (archive with a note).

Description: `m10-generalization-review.md` 2.7 and 3, with
`architecture-plan.md` P4. The piano roll stops being the hub: Ex ranges,
the language servers, snippets, diagnostics, the quickfix list, locators
and completion read the subject of the focused lens.

Acceptance criteria:

1. `paw.editor.define(stream, view, impl)` and
   `paw.editor.current(stream)` with `{ owner, lane, clip, cursor,
   selection }` (`lane` is nil until C3). The piano roll registers for
   `midi`.
2. No module outside the piano roll imports its private `Roll` type,
   and `views:get("pianoroll")` appears only in an allow-list that
   `tools/privatepath.lua` checks (the lint runs in the suite).
3. A second note editor registered in a test (a minimal view) gets Ex
   ranges and diagnostics with real keys.
4. TASK-177's criteria 1 to 3.
5. Docs: the extension skill and the API reference. Vale reports 0
   alerts.

Dependencies: none. Run it in a batch with no bundle that edits
`layout.tl` or the roll.

**TASK-286 (m-16). Edit:** add a dependency on TASK-280 (exists) and a
note: "taps use `NodeId`; refuse a tap to a later node with
`GraphError`."

**New milestone m-17.** Create "Tracks as containers: lanes, mix and
producers" with the description of `containers.md` the verdict and the
words of `architecture-plan.md` K3, K5, L4, M3 to M7. Create four tickets
with a title and a one-line description only, to fill when phase 3
starts: "Lanes: source and take lanes in the model and the arrange view
(C3)", "Optional mix: the strip in `Mix`, `Mix.graph`, folders that do
not sum (C4)", "Derived lanes and producers; freeze becomes the producer
render (C5)", "Video lanes, the monitor view and the performer layout
(C6)". Each gets the dependencies of table 4.1.

---

## 7. What this plan could not resolve

Version 2: item 6 is resolved (`PartFamily`, the word "part"). Item 4 stays (a `nest` clip gives `audio`). Items 1, 2, 3 and 5 stay. V2.16 adds the new points.


1. **The exact content of batches 18 and 19.** The plan assumes batch 18
   holds the STEP, HASH and RUNNER branches (TASK-147 and parts of
   TASK-145 and 148), and batch 19 holds TASK-279 and TASK-281. Neither
   branch is on main at deb79a0f. If TASK-281 lands after A1 starts, A1
   AC 8 moves to a short follow-up.
2. **A1's size.** The TASK-279 agent estimates 5 to 7 hours for the
   graph alignment. The shared core types add about a day (a scratch
   crate of RUST already compiles them). If A1 runs over, split the core
   types (AC 1) into their own commit first, so that M1 can start from
   them.
3. **`winnow` against `rowan`.** The plan keeps `winnow` on the facts of
   the built lexer. TASK-287 is the test: if its language server needs a
   lossless tree inside a line, a rewrite becomes a ticket then. This is
   a risk, not a decision for the owner.
4. **What a `nest` clip gives.** A nest clip plays the audio of its
   tracks, so its stream is `audio`. If a producer must read the MIDI of a
   nest, the clip kind needs two streams. No use exists now; A2 gives
   `nest` the stream `audio` only.
5. **Tier 2 producers that are slow.** The rule "tier 2 under 50 ms, or
   it is tier 3" can move a producer between tiers when a project grows.
   C5 must give a clear message when that happens. The design of that
   message waits for C5.
6. **`TrackFamily` after C4.** RUST 10.1 says the container design may
   turn the track family into container kinds. With "generalize in
   place", `TrackFamily` stays. If the owner answers Q3 with a rename,
   A2's field names change before A2 merges.
7. **Owner questions that this plan answered on its own.** The owner may
   want to see some of them (M10 2 "replace a built-in clip kind", RUST
   R1 "dotted kind names"). They are listed in 5.1 so that the owner can
   reopen any of them.
