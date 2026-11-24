# Media as recipes: sources, recipes, bakes

Author: MEDIA-DESIGN (design agent), 2026-11-21. No file of the repository changed.
Status: a proposal. The owner confirms section 13 before anyone builds it.

Read with: `scratchpad/clipkinds/DESIGN.md` (custom clips, and its section 8, the owner's
decisions), `scratchpad/agents/CK-A6.md` (a kind's data is a plain JSON value or UTF-8 text).

---

## 0. The short version

- **One way to use a file.** Every file that paw plays or shows is a **source**: immutable,
  named in the project by its path, and known everywhere else by the **BLAKE3 hash of its
  bytes**. What a clip does with sources is a **recipe**: small plain data, saved, diffable.
  What paw computes from a recipe is **baked**: a disposable entry in one content-addressed
  cache (`$XDG_CACHE_HOME/paw/bakes`), found again by a key, never saved, never wrong.
- **Between recipe and bake there is a plan.** Each edit evaluates the recipe into a flat list
  of parts (a pure function, in the kernel, under the key budget). A part is either **live**
  (it compiles to the engine's audio regions and plays at once) or **baked** (it names a key;
  it plays when the bake is ready). Cuts, reorders, gains, fades, loops and reverse are live.
  Stretch, pitch, sample-rate conversion, pencil and part-gain edits, effects and video
  encodes are baked.
- **The built-in audio clip becomes a recipe**: a list of **segments** (source, integer sample
  range, reverse, gain, fades) plus the clip's existing time map (stretch, warp, pitch) plus a
  small **modifier stack** (today's edit list). A plain clip has one segment. Glue, comps and
  the owner's shuffled film sound are clips with many segments, and none of them writes a
  file any more.
- **Bake per part, not per clip.** A key covers one segment, one warp section or one video
  slice. One edit re-bakes only the parts whose keys changed. Keys chain like a Merkle tree:
  a bake's input names the key of the bake before it.
- **Random ops keep the seed, never the result.** `shuffle { seed = 7 }` stays live and draws
  from a named stream of a defined generator (PCG32, in Rust). **Apply** writes the result
  into the recipe as plain edits, one undo step (Blender's Apply). **Consolidate** bakes a
  part into a new source and points the recipe at it.
- **Some bakes are kept.** A bake that another machine cannot make again (a freeze needs its
  plugins; an extension's output needs the extension) is copied into the project as
  `media/baked/<key>.<ext>` and becomes a source with a provenance record. Core bakes (stretch,
  conversion, peaks) are never kept: any paw can make them again.
- **Core and extensions.** The core owns sources and hashes, the media table, the cache, the
  scheduler (a bounded pool of threads and helper processes, priorities, progress, cancel),
  the built-in audio ops and the segment playback. An extension owns its recipe schema (its
  serializer, per CK-A6), its ops (`expand` in Teal now, Wasm later) and its bakers (helper
  processes that the core starts). A Teal library, `paw.recipe`, gives extensions the common
  parts: sources, edit lists, modifiers, named random streams, Apply.
- **The user sees** a `bake` item in the status line while work runs, a hatched range on a clip
  that waits, `K` that describes the recipe and its bake state, `:clip.recipe` (the stack as
  an editable list), `:clip.apply`, `:clip.consolidate`, `:bake` and `:cache`. Undo never
  waits for a bake.

Words: a **source** is an immutable input file. A **recipe** is what a clip does with sources.
An **op** is one kind of change (`stretch`, `video.shuffle`). A **modifier** is an op with its
parameters in a recipe's stack. A **part** is one piece of the plan. A **bake** is the work
that makes a part's output, and the **entry** is that output in the cache. A **key** names an
entry. **Kept** means copied into the project. ("Derived" in the clip-kinds design is now
"baked"; section 12 gives the changes to that design.)

---

## 1. Today: eight ways to handle a file

| Area | Where | Identity of a file | Where the output goes |
| --- | --- | --- | --- |
| Audio clip | `ClipContent::Audio { file, offset, gain, edits }` | absolute path | plays the decoded file |
| Decoded long files | `paw_engine::DiskStore`, `store_name` | FNV of path + size + mtime | `~/.cache/paw/media`, LRU 16 GB |
| Sample-rate conversion | `sync/audio.rs` `AudioCache::get` | (path, rate) | memory, or the disk store |
| Stretch, warp, pitch, edit list | `stretched.rs` `Key`, `Renders` | path + FNV of warp, edits text | memory, or the disk store; 2 worker threads, 150 ms settle |
| Waveforms | `peaks.rs` | path + size + mtime | `~/.cache/paw/peaks` |
| Glue | `session/clipops.rs` `clip_glue` | — | renders a **new file** in `media/` |
| Freeze, bounce | `freeze.rs`, `paw.freeze`, `paw.bounce` | `meta.frozen.file` | a file in `media/` |
| Recording, takes | `paw-engine/src/record.rs`, `meta.takes.list[].file` | path | a WAV in `media/` |
| Custom clip media | `MediaRef { role, path, derived }` | path; `derived` named by the kind's hash | `media/derived/` in the project |
| Sampler | the plugin's state (path of the `.sfz`) | path | the plugin loads its own samples |
| utau | its engine (C#) | its own cache | the device plays its renders |

What is good and stays: decoded sound as memory-mapped `f32` files (`samples.rs`), the
growing sink that plays a stretch while it is made, the `Hold` that fades at the edge of what
is ready, the settle delay, the 16 GB LRU by last use, the read-ahead (`madvise`) before the
playhead, parts sent to the engine per clip through `PartEdit` with the removed parts freed off
the audio thread, `unused/` and never delete.

What is wrong:

1. **Identity by path and mtime.** Moving a project, a `git checkout`, or a copy to another
   disk changes the path or the mtime, so every cache entry of the project is made again. Two
   copies of one sample are two entries. A file changed in place with the same size and a
   restored mtime plays the old cache (rare, but wrong, not only slow).
2. **One version per clip, not per part.** A warp marker moved re-stretches the whole file; a
   pencil fix re-renders the whole edit list.
3. **Glue and freeze write files** that are the result of edits: a destructive step that the
   model does not explain (what made this file?) and that git carries forever.
4. **Five caches with five key formats** (FNV of different things, `edits::text`, rate in a
   tuple) and three size policies.
5. **No place for a structural edit list**: a clip plays one range of one file. Comps are
   many clips. The shuffled film sound has no representation at all.

---

## 2. The model

### 2.1 Four layers

```text
 SOURCES            RECIPE                  PLAN                    ENGINE / CACHE
 immutable files    saved, plain data       in memory, per edit     what plays
 media.json:        clip: segments,         parts:                  live part → AudioRegion(s)
 path → blake3,     time map, modifiers;    Live { regions }        baked part → key → entry
 size, probe        kind data (Teal)        Baked { key, inputs }   (mmap f32, or a file)
        │                 │  evaluate (pure,     │  schedule (pool,      │
        └────────────────►│  key budget) ───────►│  priority) ──────────►│
```

The owner's sketch had three layers. The plan is the fourth because it is where "live or
bake" is decided, part by part, and where keys are computed. It is not saved: it is a pure
function of the recipe, the media table and the engine's rate, so saving it would only save a
second copy that could disagree. Blender has the same split: the modifier stack is saved, the
evaluated mesh is not.

### 2.2 Sources

```rust
/// The BLAKE3 hash of a file's bytes: what a source is, wherever it is.
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct SourceHash([u8; 32]);          // Display/FromStr: "b3:" + 64 hex

/// What the project knows of one source file. Saved in `media.json`.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct MediaRecord {
    pub hash: SourceHash,
    pub size: u64,
    /// What the file holds, read once at import (symphonia, or the kind's probe).
    pub probe: Probe,
    /// Set when this file is a kept bake: what made it (section 2.8).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub baked: Option<Provenance>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Probe { pub streams: Vec<StreamInfo> }

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum StreamInfo {
    Sound { rate: u32, channels: u16, frames: u64 },
    Picture { rate: Ratio, width: u32, height: u32, frames: u64 },   // Ratio = (num, den), 30000/1001
    Data { format: Word },                                           // a subtitle track, a bundle
}

/// The media table: every file that the project uses, by the path the project names it with.
pub struct MediaTable(BTreeMap<PathBuf, Arc<MediaRecord>>);
```

- **Clips keep naming files by path** (`"media/take1.wav"` in `track.json`, readable in a diff,
  as now). `media.json` at the top of the project folder maps each path to its record. The
  path is where to look; the hash is what it is. The cache, the keys, relink and dedupe use
  only the hash, so moving or renaming a project never misses the cache.
- **Hash once, when the bytes pass anyway.** Import hashes while it reads the file for the
  probe (BLAKE3 incremental). Recording hashes each block as the writer thread writes it
  (1.5 MB/s for 8 channels at 48 kHz: nothing). A copy by `:media.collect` hashes as it copies.
  A file that comes in another way (a project from git, a `media.json` without the file's
  entry) is hashed in the background on a worker thread (section 9 gives the cost).
- **The fast check.** The machine keeps a local index, not saved with the project:
  `$XDG_STATE_HOME/paw/media-index` maps (absolute path, size, mtime, inode) to a hash. On
  open, paw `stat`s each file (10 000 files: about 50 ms) and looks up the index. A hit with
  the hash of `media.json` is done. A miss is hashed in the background. mtime is not in
  `media.json`, because git and copies change it; it only says "this machine already hashed
  these bytes".
- **A file changed under the project** (same path, new hash): paw says so once ("film.mp4
  changed since the project was saved: its clips play the new file") and updates the record.
  Keys follow the new hash, so no old entry is used. A segment past the new length plays
  silence where the file ends and `:media.missing` lists it as short.
- **Playing does not wait for a hash.** Decoding needs the path only. What needs the hash is a
  key: a part that must bake waits (shown as baking) until its source hash is known.
- **Relink by hash.** A missing file is searched as now (relative, by name, in directories that
  had other lost files), then by size among the files of the search directories, and each
  candidate is confirmed by its hash. So a renamed file is found, and a different file with the
  same name is refused ("~/old/take1.wav has the same name but other sound"). `:media.relink
  <old> <new>` with a new hash asks first, and makes the new file a new source.
- **Never overwritten.** Nothing in paw writes into a source. Recording writes new files; a
  take is a new source. Consolidate and keep make new files. A pencil fix is a modifier.

### 2.3 Time units

| Where | Unit | Why |
| --- | --- | --- |
| A range of a source | integer frames of the stream: samples at the file's rate, picture frames | exact joins and splits; a key never depends on float rounding |
| Time inside a clip's sound (where a segment sits) | integer **flicks** (1/705 600 000 s) | divisible by 8, 11.025, 16, 22.05, 24, 32, 44.1, 48, 88.2, 96, 192 kHz and by 24, 25, 30, 48, 50, 60, 120 fps and 30000/1001: one integer clock for sound and picture from different rates |
| The clip on the timeline | beats, `f64`, as now (`start`, `length`, `offset` in seconds) | the timeline, the tempo map and every command stay as they are |

Lua sees seconds and frames (`seg.from`, `seg.to` in frames; `seg.at` in seconds, converted at
the API). Recipes that a person reads stay readable: frames are counted, not computed.
A rate that does not divide 705 600 000 (rare: 37 800 Hz) is rounded to the flick, and the
segment's length in frames stays exact.

### 2.4 The built-in audio clip as a recipe

```rust
pub enum ClipContent {
    Midi { notes: Notes, controls: Vec<Control> },
    Audio(Box<AudioContent>),
    Custom(Box<CustomContent>),
}

/// An audio clip: segments of sources laid out in the clip's sound, then
/// the clip's time map (stretch, warp, pitch: fields of `Clip`, as now),
/// then its window, gain, fades and loop, which the engine plays live.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct AudioContent {
    /// In the order of `at`; may overlap (a crossfade between two pieces).
    pub segments: Arc<[Segment]>,
    /// The clip's gain in dB.
    pub gain: f64,
    /// Changes in the sound's time that bake (today's edit list): a gain on a
    /// part, pencil fixes. In order.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub modifiers: Vec<Modifier>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Segment {
    pub source: PathBuf,                 // a key of the media table
    #[serde(default, skip_serializing_if = "is_zero")]
    pub stream: u16,                     // the sound stream of a file with several (a film)
    pub from: u64,                       // frames of the source
    pub to: u64,
    #[serde(default, skip_serializing_if = "is_zero")]
    pub at: Flicks,                      // where it starts in the clip's sound
    #[serde(default, skip_serializing_if = "is_false")]
    pub reverse: bool,
    #[serde(default, skip_serializing_if = "is_zero")]
    pub gain: f64,                       // dB, on top of the clip's
    #[serde(default, skip_serializing_if = "is_zero")]
    pub fade_in: Flicks,
    #[serde(default, skip_serializing_if = "is_zero")]
    pub fade_out: Flicks,
}
```

- `Clip.offset` (seconds into the sound where the clip starts) and `Clip.length` are the
  **window**: trimming and slipping change only them, and stay live. A clip made by import has
  one segment over the whole file, so a trim never touches the segment and never re-bakes.
- `stretch`, `pitch`, `stretch_mode`, `source_tempo`, `warp`, `formants`, `timebase` stay on
  `Clip` with their meaning (R10/R16 work unchanged). They act on the sound that the segments
  make. In recipe words they are the clip's **time-map modifier**, kept as fields because they
  are edited by many commands and follow the tempo (`Project::retime`).
- **A fixed order, not a free stack.** Segments → sound-time modifiers → time map → window,
  gain, fades, loop. A free Blender stack (stretch before or after a pencil fix?) gives no
  musical gain for audio, and it would make every pair of ops need a defined meaning. A kind
  that needs a free order (video) has it in its own recipe (section 2.10).
- Segment-level `reverse` replaces `AudioEdit::Reverse`. `:clip.reverse` on a clip of many
  segments reverses their order and flips each one: a structural edit, live.
- `AudioEdit::Gain` and `AudioEdit::Pencil` become the built-in modifiers `gain_part` and
  `pencil`. Their times move from seconds to flicks of the sound.

### 2.5 Modifiers

```rust
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Modifier {
    pub op: OpName,          // "pencil", "gain_part", "video.shuffle": a Word, or ext.word
    pub version: u32,        // of the op's meaning; part of every key it touches
    #[serde(default, skip_serializing_if = "is_true")]
    pub enabled: bool,       // `~` switches it; a disabled modifier is in no key
    pub params: KindValue,   // CK-A6's plain JSON value: no binary, no NaN, at most 1 MB
}
```

- **Random ops** keep `seed` (an integer) in `params`, never their result. The generator is
  PCG32 (XSH-RR), in Rust, exposed as `paw.recipe.rng(seed, name)`. A **named stream** is
  seeded from `blake3(seed, name)`, so a second random op, or a new draw in one op, never
  shifts the numbers of another. `math.random` is refused in `expand` (it is not part of the
  key). The generator's name and version are a field (`"rng": "pcg32"`), so a new generator
  is a new name, never a change of old results.
- **Apply** (Blender's): `expand` the modifier, write its result into the recipe as plain edits,
  remove the modifier. One undo step. Nothing bakes. The sound and picture do not change.
- **Consolidate**: bake the part or the clip as it sounds now into a **new source** (a kept
  bake, section 2.8) and replace the segments and the modifiers with one segment over it. One
  undo step, taken at once: the new segment names the file that the bake will write, and the
  clip plays the live or cached version until the file is there. Consolidate is for the user
  who wants a file (to share, to edit in another program); paw never needs it.
- Apply is offered for structural ops (cut, slice, shuffle, reorder: they expand to edits).
  Consolidate is offered for everything. `:clip.apply` on a sound modifier (a pencil) says:
  "pencil changes samples: use :clip.consolidate to make a file of it".

### 2.6 The plan: evaluation

```rust
/// What a clip plays, evaluated from its recipe for one engine rate.
pub struct Plan { pub parts: SmallVec<[PlanPart; 1]> }

pub enum PlanPart {
    /// Plays at once: compiles to engine regions over decoded sources.
    Live { segment: u32, data: Source },             // Source = a source's decoded samples at the engine rate
    /// Plays its entry when the entry is there; silent and marked before.
    Baked { key: BakeKey, covers: Range<Flicks>, job: BakeJob },
}

/// Everything a bake needs, and nothing else: the key is the hash of this.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct BakeJob {
    pub op: OpName,
    pub version: u32,
    pub params: KindValue,
    pub inputs: Vec<Input>,
    pub output: OutputSpec,          // { stream: sound|picture|data, rate, format, quality }
}

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(untagged)]
pub enum Input {
    Source { hash: SourceHash, stream: u16, from: u64, to: u64, reverse: bool },
    /// The output of another bake: its input key, so keys chain (a Merkle DAG).
    Bake { key: InputKey },
}
```

Evaluation of an audio clip, in order:

1. **Conversion.** A source at another rate than the engine's has one bake per source:
   `src { rate }`. Every segment of that source shares it (as `converted` does today).
2. **Segments.** With no sound modifier and an identity time map, each segment is **live**: one
   `AudioRegion` (or one per loop repeat, as now) over the decoded source.
3. **Sound modifiers** (`pencil`, `gain_part`) make the segments they touch **baked**, one key per
   touched segment. Untouched segments stay live.
4. **Time map.** A stretch, warp or pitch makes the sound baked. The parts are the **warp
   sections** (between two markers; one section without markers), each cut at fixed points of
   at most 30 s of input. A part's inputs are the segments and modifier bakes that it covers,
   plus 0.5 s of context on both sides (the stretch's pre-roll), so a part is made the same
   whatever is beside it. Moving one marker changes two sections: two parts re-bake.
5. **Window, gain, fades, loop, mute** are fields of the regions that the parts compile to.
   They never enter a key.

Evaluation runs in sync (`sync/clips.rs`) for a changed clip only (the incremental sync of
today), costs a few microseconds per segment (a BLAKE3 of a few hundred bytes per key), and
never waits. A custom clip's evaluation is its kind's `compile` (clip-kinds design 3.4), whose
`Compiled` gains `bakes` (section 2.10).

### 2.7 Keys

```text
input_key = BLAKE3( "paw.bake/1\n" ‖ canonical_json(BakeJob) )
tool      = the baker's name and version: "paw.stretch/3", "ffmpeg/7.1 + video.proxy/2"
entry     = hex( BLAKE3( input_key ‖ tool )[0..16] )         -- 32 hex characters
```

- **Canonical JSON** is CK-A6's form, compact: maps with sorted keys (`serde_json` without
  `preserve_order`, as paw builds it), numbers as `float_roundtrip` writes them, integers as
  integers, no NaN or infinity (refused at the door). `paw.bake/1` is the format of the key:
  a change of the canonical form is a new prefix.
- **Sources by hash, never by path.** A bake's input is a hash and an integer range.
- **Two halves.** `input_key` says what was asked; `tool` says who made it. The cache entry uses
  both. A kept bake records both (section 2.8): on another machine with another ffmpeg, the
  kept file still plays, and `K` says "made with ffmpeg 7.1 (this machine has 6.1)", not "stale".
  A kept bake is stale only when its `input_key` differs from what the recipe asks now.
- **What is not in a key**: the path of anything, the project, the time, the window, the clip's
  gain and fades, a disabled modifier, the clip's id or name.
- **128 bits** in the file name: collisions in a cache of millions of entries are 10⁻²⁶. The full
  `input_key` is in the entry's `meta.json`, and a lookup compares it.

### 2.8 The cache, and kept bakes

```text
$XDG_CACHE_HOME/paw/bakes/                one cache for all projects of the user
├── 3f/3f9a…c1/meta.json                 { input_key, tool, job, made, bytes, frames, rate }
│              0.f32, 1.f32              sound: one raw f32 file per channel, mapped (as today)
├── a0/a07e…19/meta.json
│              peaks.bin                 a waveform overview
├── 7c/7c22…e4/out.mkv                   a helper's file (a proxy, a slice encode)
└── tmp/                                  bakes being written; renamed into place when complete
```

- **One cache, shared by projects.** Keys are content, so two projects with the same sample, or
  two copies of a project, share entries. One size limit (`paw.opt.media_cache`, 16 GB, as now),
  one eviction. The old `~/.cache/paw/media` and `~/.cache/paw/peaks` go.
- **Eviction**: least recently used, by the mtime of `meta.json` (touched on use, as today).
  **Pinned** entries are never evicted: the entries of the open project's plan for the current
  state, the last 8 undo states (`SPARE`, as today), and every entry of a running export. When
  the pinned entries alone exceed the limit, paw says so once and evicts nothing pinned.
  `tidy` runs after a bake finishes and once at start, on a worker thread.
- **Writes are atomic**: a bake writes into `tmp/<entry>.<pid>`, then renames the folder. A
  second paw that makes the same entry at the same time does the work twice and one rename
  wins with the same content. `std::fs::File::try_lock` (stable since Rust 1.89) on
  `tmp/<entry>.lock` stops that double work when both run on one machine; it is an
  optimization, not needed for correctness.
- **Evicting a mapped entry is safe**: unlink leaves a mapping whole (the existing `SAFETY`
  argument of `samples.rs`).
- **Never saved, never in git, never moved to `unused/`.** `:cache.clear` deletes it: the "never
  delete" rule is for the user's files, and the cache holds none.

**Kept bakes.** A bake whose result another machine might not make the same, or at all, is
copied into the project:

| Bake | Kept? | Why |
| --- | --- | --- |
| Conversion, stretch, pitch, pencil, gain part, peaks, analysis | never | paw makes them again anywhere, bit for bit with the same build |
| Freeze, bounce | always | needs the plugins and their states; the reason to freeze is to play without them |
| A custom clip's sound made by an extension's helper | always (the kind can say `keep = false`) | rule 4: what plays is saved, and the project plays without the extension |
| Proxies, thumbnails, frame strips | never | only the extension shows them; without it they are useless |
| Consolidate | always | the user asked for a file |
| Export, stems | the user's path | the user asked for a file there |

A kept bake is a file in `media/baked/<name>-<entry>.<ext>` (`<name>` is the clip's or track's
name, for people), with a `MediaRecord` whose `baked` field is its provenance:

```rust
pub struct Provenance {
    pub input_key: InputKey,      // what it was made from
    pub tool: String,             // who made it
    pub made: jiff::Timestamp,
    pub what: String,             // "freeze of Drums", "consolidate of pad"
}
```

Kept files are sources like any other (hashed, relinked, collected). The provenance lets `K`
tell "frozen · up to date" from "frozen · stale: Drums changed since (devices)". A kept bake
that no clip or track uses goes to `unused/` on save, as other managed files do; sources the
user imported or recorded stay in `media/` as now.

### 2.9 Bakers and the scheduler

**The anti-over-abstraction check.** Ops: the built-in ops are a closed set (`src`, `stretch`,
`pencil`, `gain_part`, `peaks`, `mixdown`), so they are one Rust `enum BuiltinOp` and a
`match`. Extension ops are Lua tables. No `trait Op`: it would have one implementation and a
table. Bakers: there are **two real ways to run a bake today**: a function on a worker thread
(stretch, conversion, peaks: `stretched.rs` does it) and a helper process (ffmpeg in
`session/encode.rs`, the extension helpers on tokio). So one trait with two implementations:

```rust
/// Makes one entry. Runs off the kernel thread; never touches the model.
pub trait Bake: Send + 'static {
    /// Where the work runs: the thread pool, or a helper on the tokio runtime.
    fn lane(&self) -> Lane;
    /// Write the output into `out`; report progress; stop when `cancel` is set.
    fn run(self: Box<Self>, out: EntryWriter, progress: &Progress, cancel: &Cancel)
        -> anyhow::Result<EntryMeta>;
}

pub struct Native { op: BuiltinOp, job: BakeJob, inputs: Vec<Arc<AudioData>> }   // threads
pub struct Helper { argv: Vec<String>, outputs: Vec<OutputFile>, progress: Option<Regex> } // tokio::process
```

`EntryWriter` gives a growing sink (`samples::Sink::growing`) for sound whose length is known
before it is made, so a progressive bake plays while it runs, as a stretch does today.

**The scheduler** (`bake::Scheduler`, the generalization of `stretched::Renders`):

- **Wants.** Each sync gives the set of keys that the plan needs, each with a priority:
  1. **Playing**: a part that overlaps the next 10 s after the playhead while the song plays,
     or the 10 s after the cursor when it is stopped (the next Space starts there).
  2. **Visible**: a part in the time range of a view that shows it (the views know their range).
  3. **Export**: a part that a running render, freeze or export waits for.
  4. **Background**: the rest of the project, so that it is ready before it is played.
  The owner's order. An export waits for all of its parts anyway; its total time does not
  change with the order, and the user's ear does.
- **Lanes.** Threads: `clamp(cores / 4, 1, 4)` workers at nice 10 (this machine: 4). Helpers: 2
  processes at nice 10. One Playing job may preempt: if all workers run Background jobs, the
  oldest is cancelled and requeued (it restarts from the start; parts are short).
- **Settle**: a key must be wanted for 150 ms before it starts (today's `SETTLE`), so a value
  dragged through many values bakes the last one only.
- **Cancel**: a job whose key is no longer wanted by any state in the last 8 undo states is
  cancelled (stop flag; helpers get SIGTERM, then `kill_on_drop`).
- **Progress**: frames written, or the helper's stderr matched by its pattern, sent to the
  kernel as `bake.progress` events at most 4 times a second, and summed for the status line.
- **Failure**: one message with the op, the clip and the last lines of the helper's stderr
  (rule 6). The key is marked failed for the session; `:bake.retry` clears the marks.
- **The kernel never waits.** Results come back as kernel messages, as stretch results do now
  (`Session::poll_stretches` becomes `poll_bakes`), and rebuild only the parts that were waiting.

**While a part bakes**, it plays:

| Bake | What plays meanwhile |
| --- | --- |
| Progressive (stretch, conversion, sound modifiers) | what is ready, from the part's start; `Hold` fades at the edge (as now). Playing priority means the part under the playhead starts first |
| Helper output (an extension's sound) | silence, with the part hatched in the clip, and `bake 40%` |
| Picture (proxy, frames) | never waits: the extension's frame helper reads the source; the proxy only makes seeks faster |
| Export, freeze | the song plays as it is; the export waits for its parts |

A cheaper preview (varispeed for a stretch) was considered and rejected: it sounds wrong in
pitch, which is worse for a musician than silence that says "baking".

### 2.10 The extension contract (Teal)

The kind's data stays its own (CK-A6: a plain value, saved canonically). The core does not
impose a recipe schema; it accepts sources, bakes and a sound. `paw.recipe` is a library that
most kinds use, so their recipes look the same and their ops compose.

```lua
-- runtime/lua/paw/contracts.tl (additions)

--- An op that an extension defines: `paw.recipe.define_op(spec)`.
--- `P` is the record of its params.
record MediaOp<P>
   name: string                 -- "video.shuffle": the extension's name, a dot, a word
   version: integer             -- of the meaning; in every key it touches
   streams: {StreamKind}        -- "sound" | "picture" | "data"
   form: OpForm                 -- "structure": it changes edit lists (Apply expands it)
                                -- "render": it changes samples or pixels (it bakes)
   check: function(p: P): string                                  -- nil when good
   expand: function(p: P, edits: EditList, ctx: ExpandCtx): EditList, string   -- structure
   bake: function(p: P, part: BakePart): BakeSpec, string                      -- render
   describe: function(p: P): string                               -- "shuffle · seed 7"
end

record EditList                 -- one stream's edits, frames of each source
   unit: Ratio                  -- {1, 25} picture frames; {1, 48000} samples
   edits: {Edit}
end
record Edit
   src: string                  -- a role of the clip's media: "film"
   stream: integer              -- the stream of that file (0 by default)
   from: integer
   to: integer
   reverse: boolean
end

record ExpandCtx
   rng: function(name: string): Rng   -- a named PCG32 stream of the modifier's seed
   probe: function(src: string): Probe
end
record Rng
   next: function(self): integer      -- 32 bits
   below: function(self, n: integer): integer
   shuffle: function<T>(self, list: {T})
end

--- What a render op asks the core to run. Pure data: the core runs it.
record BakeSpec
   argv: {string}               -- "{in:film}", "{out:video}" are filled in by the core
   tool: string                 -- "ffmpeg": the core asks `<tool> -version` once, for the key
   outputs: {string: OutputSpec}  -- { stream = "picture", ext = "mkv" }
   progress: string             -- a Lua pattern on stderr: "time=(%d+):(%d+):([%d.]+)"
   keep: boolean                -- copy into media/baked (default true for sound, false otherwise)
end
```

- `paw.recipe` (Teal, `runtime/lua/paw/recipe.tl`) gives: `recipe.new(sources)`,
  `recipe.stream(r, name)`, `recipe.push(r, modifier)`, `recipe.evaluate(r, stream)` (runs the
  enabled structure modifiers in order; render modifiers become `BakePart`s), `recipe.apply(r,
  i)`, `recipe.sound(r, opts)` (the sound stream's final edit list as the clip's `Compiled.sound`:
  a built-in audio content of segments), `recipe.rng(seed, name)`.
- `Compiled` (clip-kinds design 3.4) gains `bakes: {BakeRequest}`: the render parts with their
  `BakeSpec`. The kernel turns each into a `Helper` bake, computes its key from the canonical
  request and the source hashes of the roles, and the `{out:…}` files become cache entries (or
  kept files). `compile` stays pure and fast: it never starts a process itself any more (the
  clip-kinds "names the file it will write" model becomes the core's job).
- **Runs where.** `expand`, `check`, `bake` (which only returns a spec) and `describe` run in the
  kernel under `paw.limit.guard` with the clip-kind budget (50 ms). They are pure: the Wasm
  candidates of the clip-kinds design. No Lua runs on a bake's thread or process.
- **Without the extension**: the saved sound plays (kept bakes, live segments). Structure
  modifiers of an unknown op are kept as they are and are not evaluated: the clip plays its
  saved sound, and `K` says "video.shuffle: no extension defines it".

---

## 3. Live or bake, per op, and the audio thread

| Op | Live or bake | Where |
| --- | --- | --- |
| Window (offset, length), trim, slip | live | region `offset`, `start`, `end` |
| Segment cut, split, reorder, shuffle, glue, comp | live | one region per segment |
| Clip gain, segment gain, normalize | live | region `gain` (normalize sets a gain) |
| Fades, crossfades, declick | live | region `fade_in`, `fade_out`, `declick_*` |
| Loop | live | repeated regions (`audio_regions`, as now) |
| Reverse of a segment | live (new) | region `reverse`: read `end - i` |
| Mute | live | no region |
| Sample-rate conversion | bake, per source | `src`: rubato, as now |
| Stretch, warp, pitch, formants | bake, per warp section | `stretch.rs`, as now |
| Pencil, gain on a part | bake, per touched segment | `edits::apply` |
| Reverse when a bake follows | inside that bake's input (`Input::Source.reverse`) | the bake reads backwards |
| Effects (plugins) | bake = freeze, kept | `render.rs` |
| Picture cut, reorder, shuffle | live (the frame helper follows the edit list) | extension |
| Picture encode for export, proxy, thumbnails | bake (helper) | extension |

**Why the live path keeps the audio thread rules.**

1. **No allocation.** Sync builds the regions on the kernel thread: `Vec<AudioRegion>` inside a
   `Part`, the samples as `Arc<AudioData>` that the cache already holds. The part goes to the
   engine through `PartEdit` on the existing `rtrb` ring, and the parts it replaces come back
   in `PartEdit::removed` to be dropped off the audio thread (`ClipSet::edit`, as today). A
   segment adds no new message: it is one more region in the part. `reverse` is a `bool` in the
   region; reading backwards is an index (`frames - 1 - i`), no buffer.
2. **No lock.** The audio thread reads `Samples` (a slice in memory, or a read-only mapping),
   `Hold` (an atomic), and the region's `Copy` fields. Nothing in the new path is shared
   mutably with another thread; the growing sink's length is an atomic, as now.
3. **No wait.** The one way the audio thread can wait is a **page fault** on a mapped file
   (decoded long files, cache entries). It is the existing risk, and the existing answer is
   the read-ahead (`read_ahead_from`: `madvise(WILLNEED)` for the next seconds of every region
   ahead of the playhead and the loop start). The new design adds nothing that the read-ahead
   does not cover: a segment is a region, and the read-ahead walks regions. To make the claim
   measurable rather than argued: a stats thread reads the audio thread's major-fault count
   (`/proc/self/task/<tid>/stat`, field 12) once a second, and `:checkhealth` reports it. A
   test plays a 2-minute mapped file with the read-ahead and asserts 0 major faults after the
   first second, on a warm page cache.
4. **Reverse and a growing sink.** A reversed region reads from the end, which a progressive bake
   writes last. So a reversed **live** region only ever reads a source that is complete (a
   decoded file); a reverse that is followed by a bake is inside the bake's input, not in the
   region. The constructor enforces it: `AudioRegion::reversed(data)` refuses incomplete data.
5. **Many segments.** `mix_audio` walks the regions of a part each block. A clip of 10 000 slices
   would cost 10 000 comparisons a block. Regions in a part get the same treatment parts got
   (`ClipSet::with_parts`): sorted by start, with the longest region's span as `reach`, so a
   block starts with a binary search and visits only the regions that sound (2 or 3).
6. **`assert_no_alloc`**: the engine's existing no-allocation test gets a clip of 1 000 reversed
   segments with fades played across a block boundary and a loop.

**Zero-copy sources (later, engine).** Today every source is decoded to `f32` (in memory, or in
the cache). A WAV at the engine's rate is already PCM on the disk. `Samples` gets a kind
`Pcm { map, format: I16 | I24 | F32, channels, stride }` that reads the source file's own mapping
and converts each sample as it reads it (a multiply). Then recordings (WAV) and most imported
WAVs need no cache entry at all: tens of GB of project media cost 0 bytes of cache. Compressed
sources (FLAC, MP3, AAC) are still decoded into the cache. This is the largest scalability win
of the design and the only one that touches the engine's hot loop, so it is its own part
(section 11, E2).

---

## 4. Worked examples

All JSON is as saved: keys sorted, CK-A6's pretty form (shortened here with `…`).

### 4.1 (a) The owner's film, sliced and shuffled separately in picture and sound

The user imports `film.mp4` (3 min, 25 fps, AAC stereo 48 kHz) on a video track, then in the
monitor view adds two modifiers: slice every 2 s and shuffle, on the picture with seed 7 and on
the sound with seed 8.

`media.json`:

```json
{
  "media/film.mp4": {
    "hash": "b3:9f2c41…e07a",
    "probe": { "streams": [
      { "frames": 4500, "height": 1080, "kind": "picture", "rate": [25, 1], "width": 1920 },
      { "channels": 2, "frames": 8640000, "kind": "sound", "rate": 48000 } ] },
    "size": 412338211
  }
}
```

`tracks/Video/track.json` (the clip entry; the kind's data and its sound are files of their own):

```json
{ "clips": [ {
  "data_file": "clips/film.video.json",
  "id": 41, "kind": "video", "length": 90, "media": [ { "path": "media/film.mp4", "role": "film" } ],
  "name": "film", "offset": 0, "sound_file": "clips/film.sound.json", "start": 0,
  "timeline": "seconds", "version": 1 } ] }
```

`tracks/Video/clips/film.video.json` (the kind's data: the recipe, built with `paw.recipe`):

```json
{
  "modifiers": [
    { "op": "video.slice", "params": { "every": 50, "stream": "picture" }, "version": 1 },
    { "op": "video.shuffle", "params": { "rng": "pcg32", "seed": 7, "stream": "picture" }, "version": 1 },
    { "op": "video.slice", "params": { "every": 96000, "stream": "sound" }, "version": 1 },
    { "op": "video.shuffle", "params": { "rng": "pcg32", "seed": 8, "stream": "sound" }, "version": 1 }
  ],
  "recipe": 1,
  "streams": {
    "picture": { "edits": [ { "from": 0, "src": "film", "to": 4500 } ], "unit": [1, 25] },
    "sound": { "edits": [ { "from": 0, "src": "film", "stream": 1, "to": 8640000 } ], "unit": [1, 48000] }
  }
}
```

Saved size: about 900 bytes, whatever the number of slices. Changing the seed is one line in
`git diff`.

`tracks/Video/clips/film.sound.json` (the compiled sound: rule 4, what plays is saved; a
built-in audio content, so the core plays it without the extension):

```json
{
  "gain": 0,
  "segments": [
    { "from": 3264000, "source": "media/film.mp4", "stream": 1, "to": 3360000 },
    { "at": 1411200000, "from": 6624000, "source": "media/film.mp4", "stream": 1, "to": 6720000 },
    …88 more
  ]
}
```

What happens:

1. **Import.** The extension's `create` probes (ffprobe, 50 ms) and returns the recipe with one
   edit per stream. The core hashes the file while it reads it for the media table (412 MB:
   about 0.2 s on this NVMe disk). One undo step: "added video clip film".
2. **Sound.** symphonia reads AAC in MP4 (features `isomp4`, `aac`, added to paw-engine), so the
   core decodes the sound stream into the cache once (`src`-like entry `decode {stream: 1}`,
   keyed by the source hash: 3 min stereo is 66 MB of `f32`, about 1 s). Each segment is a live
   region over it. **The shuffled sound never bakes.** A file whose sound symphonia cannot
   read (Opus in WebM) gets an extension bake `video.extract` (ffmpeg to FLAC), kept, and the
   segments name the kept file.
3. **Picture preview.** The monitor view asks the extension's frame helper for the frame at the
   playhead. The helper maps clip time through the evaluated picture edit list to (source,
   frame), and reads it from the proxy. The proxy is a bake `video.proxy` (480p, all key
   frames, keyed by the source hash and the quality, not kept): until it is there the helper
   reads the source itself, slower on seeks. **Shuffling the picture never bakes for preview.**
4. **Changing a seed** (`]` on the shuffle modifier in `:clip.recipe`, the second value): one undo
   step. The kernel re-runs `compile` (a 90-element shuffle in Lua: microseconds), writes the new
   `film.sound.json` content, and the sync sends 90 new regions. Heard at once.
5. **Export** (`:export film-cut.mp4`, the extension's format): one render op `video.encode_slice`
   per picture slice, keyed by (source hash, from, to, codec settings, quality) — not by the
   slice's place. Then one `video.concat` (ffmpeg concat demuxer, stream copy) keyed by the list
   of slice keys, then a mux with the song's render. **Re-exporting after a new seed** re-uses all
   90 slice encodes (same keys, other order) and re-runs only the concat and the mux: seconds,
   not minutes. This is what baking per part buys.
6. **Apply** (`\a` on the shuffle in `:clip.recipe`): the picture edit list becomes 90 explicit
   edits, the slice and shuffle modifiers go. Same picture, same keys, one undo step. The user
   can now move one slice by hand.

### 4.2 (b) An audio clip trimmed, faded, reversed, then time-stretched

`pad.wav`: 48 kHz stereo, 20 s. The user imports it, trims the start by 2 s (the window), sets
a fade-in of half a beat and a fade-out of a beat, reverses it, and stretches it to 1.5.

`tracks/Pad/track.json`:

```json
{ "clips": [ {
  "fade_in": 0.5, "fade_out": 1, "id": 12, "kind": "audio", "length": 24,
  "name": "pad", "offset": 2, "start": 8, "stretch": 1.5, "stretch_mode": "tonal",
  "sound": { "gain": -3, "segments": [ { "from": 0, "reverse": true, "source": "media/pad.wav", "to": 960000 } ] }
} ] }
```

Evaluation:

- Without the stretch, the segment is a live reversed region; trim and fades are region fields.
  Heard at once.
- With the stretch: one warp section (no markers), 20 s of input, cut into one part (≤ 30 s).
  Its job: `{ op: "stretch", version: 3, params: { formants: false, mode: "tonal", pitch: 0,
  warp: [[0, 0], [20, 30]] }, inputs: [ { hash: "b3:…", from: 0, to: 960000, reverse: true,
  stream: 0 } ], output: { rate: 48000, stream: "sound" } }`. The input reads the source
  backwards: reverse is inside the bake. The fades, the 2 s trim and the gain are applied to the
  regions over the bake's output: **trimming again never re-bakes**.
- While it bakes (about 0.5 s at an estimated 40× real time), the region plays what is ready
  from its start (the Playing priority starts it first), and `Hold` fades at the edge.
- Undo of the stretch: the plan goes back to the live reversed region; no wait. Redo: the entry
  is pinned for 8 undo states: heard at once.

### 4.3 (c) A recorded take with three comps

The user records 4 times round a 16-beat loop on the track Vox, then comps: take 2 for beats
0–6, take 4 for 6–11, take 1 for 11–16.

- Recording writes `media/rec-vox-001.wav` (one file for the whole pass round the loop, as now)
  and hashes it as it writes. At the stop, the media table gets its record. Each time round is
  a take: a segment over its range of that one file.
- The comp is three clips (pieces), as `takes.md` describes now; each piece keeps all its takes.
  The only change: a take is a segment, not a file and an offset in `meta`.

```json
{ "clips": [
  { "id": 70, "kind": "audio", "length": 6, "name": "take 1.2", "offset": 0, "start": 0,
    "sound": { "gain": 0, "segments": [ { "from": 384000, "source": "media/rec-vox-001.wav", "to": 768000 } ] },
    "takes": { "active": 2, "list": [
      { "from": 0, "to": 384000 }, { "from": 384000, "to": 768000 },
      { "from": 768000, "to": 1152000 }, { "from": 1152000, "to": 1536000 } ],
      "source": "media/rec-vox-001.wav" } },
  { "id": 71, "length": 5, "name": "take 1.4", "offset": 3, "start": 6, … },
  { "id": 72, "length": 5, "name": "take 1.1", "offset": 5.5, "start": 11, … }
] }
```

(120 BPM: a beat is 0.5 s, a time round is 8 s = 384 000 frames.) The takes move from
`meta.takes` (which the core reads by name today, `media::take_files`) to a field that the core
owns, because the media table, relink and collect must see them; `paw.takes` keeps its API.

- **Swipe comping joins** pieces "where the join is exact". With integer frames the test is
  `a.to == b.from` on the same source: no float tolerance any more.
- **`:clip.glue`** on the three pieces makes **one clip with three segments** (each with its
  crossfade as segment fades), not a new file. Nothing bakes. `:clip.consolidate` makes the file
  for someone who wants one (kept, `media/baked/take-1-…wav`).

### 4.4 (d) A frozen track

The user freezes Drums (three plugin instances, 4 min song).

- The freeze is a bake: op `mixdown`, input key = BLAKE3 of the canonical track subgraph (the
  track's and its feeders' clips as plans, devices with their state hashes, automation, tempo
  map, the render range), tool = `paw.mixdown/1` + each plugin's id and version. It runs on the
  render thread of today (`render.rs`), at Export priority, and is **kept**.

`tracks/Drums/track.json` (part):

```json
{ "frozen": { "file": "media/baked/freeze-drums-5d1e…a2.wav" }, "name": "Drums", … }
```

`media.json` (part):

```json
"media/baked/freeze-drums-5d1e…a2.wav": {
  "baked": { "input_key": "5d1e…a2", "made": "2026-11-21T12:00:00Z",
             "tool": "paw.mixdown/1; clap:com.u-he.diva/1.4.7; …", "what": "freeze of Drums" },
  "hash": "b3:0c4f…", "probe": { "streams": [ { "channels": 2, "frames": 11616000, "kind": "sound", "rate": 48000 } ] },
  "size": 92928044
}
```

- `frozen` moves out of `meta` to a field, for the same reason as takes.
- After an edit of a frozen track's hidden parts (undo of a device change, a script), `K` says
  "frozen · stale: the devices changed since the freeze (`:freeze` again)". Today paw cannot say.
- On a machine without the plugins, the file plays. Freezing again with the same input key and
  tool finds the kept file (its hash is in the table) and does nothing.
- Unfreeze leaves the file (undo can bring the freeze back); a save with no track using it moves
  it to `unused/`, never deleted.

### 4.5 (e) A sampler instrument's samples

The sampler is a CLAP plugin in its own process that loads its own samples. It does not fit as
a recipe (nothing is cut, nothing bakes), and the design does not force it to. It fits as a
**source of the kind bundle**: an instrument file plus the files it names.

- The extension's `describe` (it exists: `paw-sampler describe file.sfz`) lists the sample files.
  The core makes a bundle record: the hash is BLAKE3 over the sorted list of (path relative to
  the instrument's folder, file hash). The track's device state still holds the path; the
  extension registers it with `paw.media.use(track, path, { kind = "bundle", files = list })`.

```json
"~/.local/share/paw/instruments/Violins/violins.sfz": {
  "hash": "b3:7aa0…", "probe": { "streams": [ { "format": "sfz", "kind": "data" } ] },
  "bundle": { "files": 312, "bytes": 1840221004 },
  "size": 41022
}
```

- What it gains: `:media.missing` lists a missing instrument (today a silent plugin),
  `:media.relink` finds a moved library folder by the bundle hash, `:media.collect` copies the
  instrument with its samples into `media/instruments/Violins/` (1.8 GB: it asks first, with the
  size), and the project's media list counts it.
- What stays: the plugin's own loading and streaming (its process, its memory). The cache is
  not shared with the plugin's process: the sandbox is the point.
- **utau** likewise keeps its engine's phrase cache (it is OpenUtau's format, in the engine's
  process). Its freeze is the core's kept `mixdown` (4.4), so a frozen vocal plays without the
  extension. Its cache size shows in `:cache` if the extension reports it (`paw.cache.report`).

---

## 5. Determinism and versions

- **Same inputs, same key**: canonical JSON, hashes of sources, integer ranges, op versions.
  Floats in params are the user's numbers, written shortest-roundtrip; they are never computed
  before keying (a stretch ratio is the field's value, not `source_tempo / tempo` recomputed at
  another precision: the time map is keyed by its pieces' bits, as `Warp::bits` does today).
- **Same build, same bytes.** A native bake must give the same bytes for the same job on one
  binary: the existing render tests ("the same to the bit") extend to bakes. Threads are not a
  source of difference: a bake is one job on one thread; a native baker that uses SIMD picks the
  path by the CPU at start, so the **tool** string includes the SIMD level (`paw.stretch/3+avx2`)
  and a machine change is a new key, not a wrong entry.
- **Across builds and machines**: not bit-exact, and not needed: the cache is local. Kept bakes
  carry their file. A render golden in the e2e suite compares with a tolerance (−100 dBFS peak
  difference), as they do now.
- **A baker that changes its output on purpose** bumps its version (`paw.stretch/3` → `/4`). The
  old entries become unreachable, never wrong, and age out of the LRU. A bump is in the same
  commit as the change; a test pins each native baker's version against a hash of a short golden
  output, so a change of output without a bump fails the test.
- **Helpers**: the tool string is `<tool> -version`'s first line, read once per session.
- **An op's version** (`video.shuffle` v1 → v2) changes what a modifier means. Old projects keep
  `version: 1` in the modifier; an extension that still knows v1 evaluates it as v1, or migrates
  it with the kind's `migrate` (clip-kinds 3.7). Apply first is the user's escape hatch.

---

## 6. Files and git

```text
song/
├── project.toml
├── media.json              new: every file the project uses → hash, size, probe, provenance
├── tracks/Pad/track.json   audio clips: "sound": { segments, gain, modifiers }
├── tracks/Video/clips/film.video.json, film.sound.json
├── media/                  sources: imports, recordings (never moved or deleted by paw)
│   └── baked/              kept bakes: freezes, consolidations, extension sounds
└── unused/                 kept bakes and managed files no longer used; never deleted
```

- `media.json` is sorted by path, one source per entry, so an import is a few added lines.
- `media/derived/` of the clip-kinds design becomes `media/baked/` (the cache-only "derived"
  files leave the project; only kept bakes stay).
- `.gitattributes` adds `media/** -diff` (binary files show as "changed", not as noise) and,
  as now, `*.midi2 diff=paw-midi2`. Git LFS stays the user's choice; `:help media` tells how.
- **`:media.collect`** copies every source outside the folder into `media/` (and bundles into
  `media/instruments/<name>/`), hashing as it copies, and dedupes by hash: two clips that use
  the same sample from two folders get one copy.
- **A project on a machine without the cache** (a fresh clone): it opens at once; the stat pass
  finds no index entries, so every source is hashed in the background (a 40 GB project: about
  20 s on NVMe, 5 min on a hard disk; playing does not wait for it). Live parts play at once.
  Baked parts bake as they are wanted, the part at the playhead first; `bake 12 · 3%` shows in the
  status line. `:bake.all` asks for the whole project at Background priority. A render waits for
  its parts and says so: "render: waiting for 12 bakes (about 40 s)".
- **Never saved**: the cache, the local index, the plan.

---

## 7. Undo

- One user action is one recipe diff, one undo step: a modifier added, a seed changed, a
  segment moved, Apply, Consolidate. The undo snapshots share the clip runs and the
  `Arc<[Segment]>` as they share everything now.
- **Undo never waits**: the plan of the old state is evaluated as any plan; its keys are in the
  cache (pinned for 8 undo states) or bake again; live parts play at once.
- Consolidate's undo step is taken at once; the kept file appears later. Undo before the file is
  there cancels the bake (no state wants it). Redo starts it again.
- The undo diff (`impl Part for Clip`) names the fields: "segments", "modifiers", "gain". A
  modifier's label is its `describe`: "shuffle · seed 7 → 8".

---

## 8. Export, render, freeze, stems

All four are bakes of a project subgraph through the existing private engine of `render.rs`:

- **Render/export**: op `mixdown` of the master, at Export priority, waiting for its parts' bakes
  first. Its entry is in the cache (not kept) and copied to the user's path; a second `:export`
  with no change in between copies the entry: instant.
- **Stems**: one `mixdown` per stem, each its own key. A stem whose subgraph did not change since
  the last export is not rendered again. (A subgraph includes the sends and sidechains that reach
  it, so the key is honest.)
- **Freeze**: kept `mixdown` (4.4). **Bounce**: kept `mixdown` plus a new track that plays it.
- **Plugins that are not deterministic** (a noise generator with its own random seed) make a
  mixdown key that promises more than the plugin gives. The cache does not make this worse than
  rendering twice today. A plugin flagged as not deterministic (by the user, `:plugin.random`)
  puts the time into the tool string of its mixdowns, so they are never re-used.

---

## 9. Terminal first: what the user sees

- **Status line**: a component `bake` in section `c` (beside `render`): `bake 3 · 42%` while jobs
  run (count of wanted jobs not done, weighted progress), `bake !1` after a failure (`:bake` lists
  it), nothing when idle. The window shows the same component (one scene).
- **Arrange view**: a part that waits on a bake is drawn hatched (TUI: the clip's cells with `╱`
  in the dim role; window: diagonal lines) up to where it is ready. A failed part is in the error
  role. One view, both frontends.
- **`K` on a clip** describes the recipe and its state, one line each:

  ```text
  audio clip pad · 8–32 · media/pad.wav (b3:9f2c…, 20.0 s, 48 kHz)
  1 segment 0.0–20.0 s reversed · gain −3 dB · fades ½ / 1 beat
  stretch 1.5 tonal · baking 40% (about 1 s)
  ```

  For a custom clip, the kind's `describe` and each modifier's `describe`. For a frozen track:
  "frozen · up to date" or "frozen · stale: …".
- **`:clip.recipe`** opens the clip's stack as a list edited as text (the existing mechanism of
  `lists-edited-as-text.md`): one line per segment and per modifier. `:w` applies the changes as
  one undo step. In that buffer, by the key rule: `j`/`k` move; `+`/`-` change a modifier's main
  value (the seed, the gain), `]`/`[` its second value; `~` switches a modifier on and off; `dd`
  removes, `p` pastes; `K` describes; on `<localleader>`: `a` applies the modifier under the
  cursor, `A` applies all structure modifiers, `c` consolidates.
- **Commands**: `:clip.apply [n]`, `:clip.consolidate`, `:clip.recipe`; `:bake` (the jobs, with
  their clip, op, priority and progress, as a list that `Enter` jumps from), `:bake.cancel`,
  `:bake.retry`, `:bake.all`; `:cache` (size, limit, pinned, entries by op), `:cache.clear`.
  `Esc` in `:bake` cancels nothing (Esc cancels a pending key, not work); `:bake.cancel` does.
- **Messages** (rule 6): "pad: stretch failed (out of disk space in ~/.cache/paw): it plays
  silent; free space and :bake.retry". "film: video.encode_slice: ffmpeg said: Unknown encoder
  'libx264'".
- **Events**: `bake.start`, `bake.progress`, `bake.done`, `bake.failed` for scripts and the doctor.

---

## 10. Scale: estimates for a large project

Measured on this machine (24 cores, NVMe, load average 33–52 at the time, so the spread is
wide; page cache warm): BLAKE3 0.33–0.48 s/GB on one thread, 0.07–0.21 s/GB with all threads;
coreutils SHA-256 0.94–1.07 s/GB. On a cold file the disk is the limit, not the hash. The other
numbers are **estimates**; part M0 measures them before the parts that rely on them.

**The project**: 2 000 audio clips, 400 source files, 40 GB of sources (WAV 24-bit stereo 48 kHz:
about 70 hours), 200 stretched clips of 30 s average, 50 clips with pencil fixes, a 10-minute
video, 10 frozen tracks.

| Cost | Estimate | Notes |
| --- | --- | --- |
| Hash at import, recording, collect | 0 extra | the bytes pass anyway; BLAKE3 at 2 GB/s on one thread is faster than the disk |
| Hash of the whole project, fresh clone | 40 GB: 15–20 s NVMe, 4–5 min HDD | background, once per machine; nothing waits on it but bakes |
| Open, warm machine | 400 `stat` + index lookups: < 10 ms | 10 000 files: about 50 ms |
| A key | about 1 µs | BLAKE3 of 200–500 bytes |
| Sync of one edited clip with 1 000 segments | about 1 ms | one region and at most one key per segment |
| Decoded cache, today's model (all to f32) | 40 GB 24-bit → 53 GB f32 | over the 16 GB limit: LRU churn on every open |
| Decoded cache, with zero-copy PCM (E2) | 0 for WAV at the engine rate | only compressed and converted sources use the cache |
| Stretch bakes | 100 min of output; at an estimated 30–50× real time per worker and 4 workers: 30–50 s cold | the Playing part first: under 1 s to hear a clip at the playhead |
| Stretch cache | 100 min of f32 stereo: 2.3 GB | pinned while the project is open |
| Peaks | 4 KB per minute of source: 70 h → 17 MB | one entry per source hash, shared across projects |
| Video proxy (10 min, 480p all-intra) | 1–2 min of ffmpeg on 2 cores; about 600 MB | not kept |
| Video slice encodes for export | 10 min 1080p: 3–6 min first time; after a reshuffle: concat + mux only, about 10 s | per-part keys |
| Frozen tracks (kept) | 10 × 4 min f32 WAV: 920 MB in the project | the same as freeze costs today |
| Memory | page cache for mapped entries; in-memory decodes under 64 MB each (`paw.opt.media_stream`) | add `paw.opt.media_memory` (1 GB): over it, new decodes go to the cache even when small |

**Limits** (each refused with a message that names it):

- Segments per clip: 65 536. Modifiers per clip: 256. Recipe (kind data) size: 1 MB (CK-A6).
- Bake parts per clip: 4 096 (a longer warp map is cut into longer parts).
- Workers: `clamp(cores / 4, 1, 4)`; helpers: 2 (`paw.opt.bake_workers`, `paw.opt.bake_helpers`).
- Cache: `paw.opt.media_cache` GB (16), plus the pinned entries.

---

## 11. What changes in today's code

| Area | Changes | Stays | Deleted |
| --- | --- | --- | --- |
| `model.rs` `ClipContent::Audio` | becomes `Audio(Box<AudioContent>)`: segments, gain, modifiers | the stretch/warp/pitch/timebase/fade/loop fields of `Clip` | `file`, `offset`-in-content (now the clip's window `offset`), `edits` |
| `edits.rs` | `Gain`, `Pencil` become built-in modifiers with flick times; `apply` is the native baker of a segment | `check` | `AudioEdit::Reverse` (segment flag), `edits::text` (keys are canonical JSON) |
| `stretched.rs` | becomes `bake/` (`Scheduler`, `Native`, `Helper`, `EntryWriter`); keys from `BakeJob` | settle, spare, the growing sink, failures, `finished` | `Key`, its FNV `store_name`, `Renders` as a stretch-only type |
| `stretch.rs`, `warp.rs` | `warp` gives sections for parts; stretch takes a part with context | the algorithms | — |
| `resample.rs` | the native `src` baker, keyed by source hash and rate | rubato, 256 taps | `(path, rate)` keys |
| `peaks.rs` | a native `peaks` baker, entry in the cache by source hash | the `Summary` format | `~/.cache/paw/peaks`, `stored` by path + mtime |
| `sync/audio.rs` `AudioCache` | decoded sources by hash; asks the scheduler for entries | `playing`, `retain`, `forget_loaded` | `converted` map, `store_name` calls |
| `sync/clips.rs` | `parts_of` compiles a `Plan`: one region per live segment, regions over entries for baked parts | `audio_regions` (loops), `repeats`, `joins_itself` (now exact by frames first) | `clip_audio`'s single file |
| `paw-engine` `samples.rs` | `DiskStore` opens entries by path given by the core | `Sink`, `Growing`, `map_file`, `tidy` | `store_name` (identity by path+mtime) |
| `paw-engine` `clip.rs`, `regions.rs` (E7's area) | `AudioRegion.reverse`; regions in a part sorted with `reach`; later `Samples::Pcm` | everything else | — |
| `session/media.rs` | `MediaTable`, hashing, the local index, relink by hash, bundles, `custom_files`/`take_files` read model fields | the search by name and directory, offline clips | `meta.takes` scanning |
| `session/folder.rs` | `media.json`; audio clip `sound` object; `media/baked/` managed; `.gitattributes` line | everything else | `edits_file` (`<clip>.edits.json`: modifiers are in the clip entry, small) |
| `session/clipops.rs` | glue → segments; reverse → segment flags; `:clip.consolidate`, `:clip.apply` | normalize, crossfade | glue's render to a file |
| `freeze.rs`, `paw.freeze` | freeze is a kept `mixdown` bake; `frozen` is a track field with the file | hold, engine_hold | `meta.frozen.file` |
| `session/render.rs` | render, stems as `mixdown` entries; wait for parts | the private engine, normalizing | — |
| `paw-engine/src/record.rs` | hashes blocks as it writes | header updates every 2 s | — |
| Takes (`paw.takes`, Lua) | a take is a frame range of a source in a core field | the commands, lanes, swipe comping | `meta.takes.list[].file` |
| `model/custom.rs` (CK-A6's area) | `MediaRef` loses `derived`; `Compiled` gains `bakes`; a custom sound is an `AudioContent` | `Sound`, signals, data | `derived` flag, `media/derived/` |
| Lua API | `paw.media.list` gives `hash`, `baked`; new `paw.recipe`, `paw.bake.*`, `paw.cache.*`, `paw.media.use` | `relink`, `search`, `collect`, `missing` | `paw.api.media_store` (→ `paw.cache.limit`), `paw.media.edits`/`clear_edits` (→ `clip.recipe`) |
| Crates | add `blake3` (feature `mmap`, `rayon`); symphonia features `isomp4`, `aac` | rubato, symphonia, memmap2, tokio | FNV by hand (twice) |

**Crates, checked against paw-crates.md and the ecosystem pages:**

- **`blake3`** for source hashes and keys. paw-crates.md says `ring::digest` for "SHA-256 and other
  hashes"; this is a new job (content addressing of tens of GB) where BLAKE3 is 2–3× faster on one
  thread and scales with threads (`Hasher::update_mmap_rayon`), has an incremental API for the
  recorder, and is the reference implementation (one crate, no `unsafe` in the caller). Add a row
  to paw-crates.md: "Content hashes of files and cache keys: `blake3`". `ring` stays for TLS and
  SHA-256 where a protocol asks for it.
- **`symphonia`** (already used): enable `isomp4` and `aac` for the sound of films. No ffmpeg for
  that path.
- **Stretching**: keep paw's own `stretch.rs` (vocoder + WSOLA, formants, warp-aware). Rubber Band
  (`rubberband` bindings, GPL, C++) and Signalsmith Stretch (MIT, C++, no maintained Rust crate)
  were checked: both would add a C++ build and neither follows paw's warp maps natively. A future
  "high quality" mode could be Signalsmith via a small FFI crate, as a second native baker with
  its own tool name; not in this plan.
- **Caching**: no crate. `cacache` (content-addressed, npm-style) stores by content hash of the
  *output*, but paw needs lookup by the hash of the *input* and memory-mapped outputs; a 200-line
  module on `std::fs` does it. `moka`/`quick_cache` are in-memory caches: not this job.
- **Locks**: `std::fs::File::try_lock` (Rust 1.89), no `fs4`.
- **Times**: `jiff` (paw-crates.md) for `Provenance.made`.

---

## 12. Changes to the clip-kinds design

- "Derived media" (`MediaRef.derived`, `media/derived/`) is replaced: cache-only outputs leave the
  project and the model; outputs that must play without the extension are kept bakes in
  `media/baked/` with provenance.
- "Slow compiles: content-addressed files" (3.4): `compile` no longer starts helpers. It returns
  `bakes`; the core runs them, keys them, shows their progress and keeps them.
- `Compiled.sound` of kind audio is an `AudioContent` (segments), saved as `<clip>.sound.json`
  when it has more than one segment, in the clip entry otherwise.
- `paw.api.hash` is replaced by keys that the core computes; a kind never names a cache file.
- The video worked design (4.1 there) is replaced by example 4.1 here.

---

## 13. The plan

Each part: 30–90 minutes, its owned files, a model, tests, risks. Today E7 owns `paw-engine`, and
CK-A6 owns `model/custom.rs` and the custom parts of `session/folder.rs`, `session/clips.rs` and
`api/clips.rs`. **[now]** marks parts that can run alongside them.

### Order

```text
M0 ─┬─ M1 ─┬─ M3 ─ M4 ─┬─ M6 ─ M8 ─ M9
    │      │           ├─ M7 (after CK-A6, B1) ─ M10
    └─ M2 ─┘           └─ M5a ─ M5b ─ M5c
E1, E2 after E7 ─────────────┘ (M5b needs E1 for reverse)
M11 after M1. M12 last.
```

| Part | What | Owned files | Model | Tests | Can start |
| --- | --- | --- | --- | --- | --- |
| **M0** | Measure, then decide numbers: stretch speed (× real time, per mode), decode speed (FLAC, MP3, AAC), BLAKE3 on cold files, `stat` of 10 000 files. Add `blake3` to the workspace and a `media::hash` module (file, mmap+rayon, incremental). A row in paw-crates.md. | `crates/paw-core/src/media/hash.rs` (new), `Cargo.toml`s, `bench/media.md` (new), paw-crates.md | sonnet | one test: incremental = whole-file hash | **[now]** |
| **M1** | Sources: `SourceHash`, `MediaRecord`, `Probe`, `MediaTable`; `media.json` save and load; the local index (`$XDG_STATE_HOME/paw/media-index`); background hashing; "changed under the project" message; relink by size + hash; collect dedupes by hash. | `media/table.rs`, `media/index.rs` (new), `session/media.rs`, the media part of `session/folder.rs` | opus | Rust: save → load → save same bytes; moved file found by hash; same-name other file refused. Lua: `paw.media.list()` has `hash` | after CK-A6 merges (folder.rs) |
| **M2** | The cache: `BakeKey`, canonical JSON (CK-A6's), `bakes/` layout, `EntryWriter` (tmp + rename), `open`, LRU with pins, `try_lock`. Peaks move onto it as the first user. | `crates/paw-core/src/bake/store.rs`, `bake/key.rs` (new), `peaks.rs`, `sync/audio.rs` (peaks part) | opus | key stability (golden key of a fixed job); eviction keeps pinned; a moved file keeps its peaks entry | **[now]** |
| **M3** | The scheduler: wants with priorities, two lanes (`trait Bake`: `Native`, `Helper` on tokio), settle, cancel, progress events, failures, `poll_bakes`; port `stretched::Renders` onto it with stretch keys from `BakeJob`. | `bake/scheduler.rs`, `bake/native.rs`, `bake/helper.rs` (new), `stretched.rs` (shrinks), `session/stretching.rs` | opus | Playing preempts Background; a dragged ratio bakes once; a cancelled helper is killed; existing stretch tests pass | after M2 |
| **M4** | Conversion, edit-list bakes and stretch keyed by source hash; parts per warp section with context; delete `store_name` use and `edits::text`. | `resample.rs`, `stretch.rs`, `warp.rs` (sections), `sync/audio.rs`, `sync/clips.rs` (stretch part) | opus | moving one marker re-bakes two parts (count jobs); seam test: a part made alone equals the same frames of a whole-file stretch within −90 dB | after M1, M3 |
| **M5a** | Audio clip as segments: `AudioContent`, save format (`sound` in the clip entry), sync with one region per segment, `Flicks`. All built-in commands still work on one-segment clips. | `model.rs` (Audio arm), `session/folder.rs` (audio part), `sync/clips.rs`, `session/clips.rs` (audio part) | opus | Rust round trip; the full Lua suite unchanged (import, trim, split, slip, loop, fades); the no-alloc test with 1 000 segments | after M1; coordinate with CK-A6 on folder.rs |
| **M5b** | Ops over segments: split/trim/slip at segment edges, glue → segments, reverse → segment flags, takes as frame ranges, swipe-comp joins by frames, `:clip.consolidate`. | `session/clipops.rs`, `runtime/lua/paw/takes*.tl`, `session/stretching.rs` (reverse) | opus | real keys: `s` on a glued clip, `:clip.reverse` on three segments, swipe comp join | after M5a, E1 |
| **M5c** | Lua API and docs for segments: `clip:segments()`, `paw.media.*` changes, generated declarations, `media.md`, `takes.md`, `project-files.md`. | `api/clips.rs` (audio part), `runtime/types`, docs | sonnet | one Lua test per new function; Vale | after M5b |
| **M6** | Built-in modifiers (`pencil`, `gain_part`) as a stack; `:clip.recipe` buffer (lists edited as text), `:clip.apply`, the key rule keys in it. | `edits.rs`, `session/clipops.rs` (modifiers), `runtime/lua/paw/recipe_view.tl` (new) | opus | real keys: `~` disables a pencil (heard: the key goes back to the live part), `dd` + `:w` is one undo step | after M5a |
| **M7** | `paw.recipe` (Teal): sources, edit lists, `define_op`, `evaluate`, `apply`, PCG32 named streams (Rust, `paw.api.rng`); `Compiled.bakes`; `Helper` bakes from `BakeSpec`; `keep`. | `runtime/lua/paw/recipe.tl` (new), `contracts.tl`, `types.tl`, `api/bake.rs` (new), `model/custom.rs` (`Compiled`) | opus + teal skill | Teal: a shuffle with seed 7 gives a fixed list (golden); apply keeps the plan's keys; a helper bake's key changes with its tool | after CK-A6, B1 |
| **M8** | Kept bakes: `media/baked/`, `Provenance`, freeze and bounce as kept `mixdown`, `frozen` field, stale detection, render/stems as entries. | `freeze.rs`, `session/render.rs`, `runtime/lua/paw/freeze*.tl`, `session/folder.rs` (managed `media/baked`) | opus | freeze → change a device → `K` says stale; unchanged second export is a copy (no render) | after M3, M1 |
| **M9** | The user's view: `bake` status line component, hatched parts in the arrange view (scene, both frontends), `K` lines, `:bake*`, `:cache*`, events. | `runtime/lua/paw/statusline*.tl`, arrange view files, `api/bake.rs` | sonnet | real keys: `K` on a stretching clip says "baking"; status line item appears and goes; `cargo test -p paw-gui` | after M3 |
| **M10** | The video extension proof: example 4.1 end to end (slice, shuffle, proxy, export by slices, apply). | `extensions/video/` | opus | the extension's tests; export after reshuffle re-encodes 0 slices | after M7 and clip-kinds phase E |
| **M11** | Bundles: `paw.media.use`, the sampler registers its instrument; missing, relink, collect of a bundle. | `session/media.rs` (bundles), `extensions/sampler/lua/` | sonnet | a moved library is found by bundle hash | after M1 |
| **E1** | Engine: `AudioRegion.reverse` (complete data only), regions in a part sorted with `reach`. | `paw-engine/src/clip.rs`, `engine/regions.rs` | opus | no-alloc with reversed regions; 10 000 regions cost what 3 cost per block (a bench) | after E7 |
| **E2** | Engine: zero-copy `Samples::Pcm` for WAV at the engine rate; major-fault counter of the audio thread in stats and `:checkhealth`. | `paw-engine/src/samples.rs`, `clip.rs`, `engine/stats.rs` | opus | bit-equal playback against the decoded path for 16/24/32-bit; 0 major faults after warm-up | after E7, M5a |
| **M12** | Docs sweep: search `README.md`, `AGENTS.md`, `docs/`, `bench/`, crate and extension READMEs and `doc/`, `.claude/skills` for `derived`, `edits_file`, `media_store`, `~/.cache/paw/media`, `peaks`, `frozen.file`, `glue`, "new file"; a new explanation page "About sources, recipes and bakes". | docs | sonnet | Vale 0 errors; `tests/guides*.lua` updated | last |

**Risks**

- **Seams between stretch parts** (M4). A part made alone may differ from the continuous stretch at
  its edges. The 0.5 s context and a fixed cut grid make it deterministic; the seam test sets the
  bar. If it fails, parts fall back to one per warp section (no fixed cuts), which keeps the
  biggest gain (one marker moved re-bakes two sections).
- **The `ClipContent::Audio` change touches many files** (M5a). It lands with the suite green and
  one-segment clips behaving as now; the new behavior comes in M5b.
- **Concurrency with CK-A6 and E7** on `session/folder.rs` and `paw-engine`. M1, M5a and M8 wait for
  CK-A6; E1 and E2 wait for E7. M0, M2, M3 are new files.
- **Hashing on a slow disk** after a clone (5 min for 40 GB on an HDD). Mitigation: nothing waits on
  it except bakes, and the index makes it once per machine.
- **Page faults** on the audio thread: the measurement in E2 turns the argument into a number. If
  the number is not 0, the read-ahead window grows (a setting) before anything else.

---

## 14. Open questions for the owner

Only what you see, must relearn, or is risky.

1. **One cache for all projects** in `~/.cache/paw/bakes` (16 GB by default), not one per project.
   *Recommendation:* shared. Keys are content, so projects share samples and copies of a project
   share everything; one limit is easier to reason about. The cost: deleting a project does not
   free its cache at once (the LRU does, later; `:cache.clear` now).
2. **Kept bakes in the project**: freezes, consolidations and extension sounds are saved in
   `media/baked/`; stretches, conversions and peaks never are. *Recommendation:* yes. A project
   stays small, plays anywhere paw runs, and still plays without plugins or extensions where that
   matters. The cost: a fresh clone re-bakes stretches (seconds to a minute for a big project).
3. **Silence while a stretch bakes**, with the part hatched and the playhead part first, rather
   than a wrong-pitch preview. *Recommendation:* silence (what you have now, made faster to start).
4. **Glue makes no file.** `:clip.glue` gives one clip of several segments; `:clip.consolidate` is
   the new command that writes a file. *Recommendation:* yes; it is non-destructive and instant.
   You relearn one command name if you glued to get a file.
5. **Apply and Consolidate**: two words for two actions (expand a modifier into edits; bake into a
   new file). Keys `<localleader>a`, `<localleader>A`, `<localleader>c` in `:clip.recipe`; no key
   in the arrange view, only `:clip.apply` and `:clip.consolidate`. *Recommendation:* yes; they
   are rare enough to be commands.
6. **A source file changed on disk** (same path, other bytes): paw follows the new file and tells
   you once, rather than refusing to play it. *Recommendation:* follow and tell. The old bytes are
   gone anyway; refusing would only make the clip silent.
7. **`blake3`** as a new dependency for hashes (paw-crates.md now says `ring` for hashes).
   *Recommendation:* add it, with a row in paw-crates.md; it is 2–3× faster per thread than SHA-256
   here and scales with threads, which matters at tens of GB.
8. **Sampler libraries in `:media.collect`**: collect copies a whole instrument (it can be GBs) into
   the project. *Recommendation:* collect asks first for bundles, with their size, and does not copy
   them by default.

## 15. The owner's decisions (2026-11-21)

1. One shared cache for all projects (`$XDG_CACHE_HOME/paw/bakes`, LRU, 16 GB): as recommended.
2. Kept bakes only where they cannot be made again (freeze, consolidate, extension sounds) in
   `media/baked/`; stretches, conversions and peaks never: as recommended.
3. **Changed from the recommendation: a rough preview while a part bakes**, not silence. The part
   plays the source live (wrong pitch/speed is acceptable, e.g. plain resampling or the nearest
   cheap live path) so the rhythm is still heard; it is drawn hatched until the bake is ready, and
   the playhead's part bakes first. Swapping preview → baked happens at a block boundary on the
   audio thread with no lock or allocation (regions built off-thread, as for every edit).
4. A source changed on disk: follow the new file and tell once: as recommended.
5–8. Not asked; the recommendations stand (glue makes no file and `:clip.consolidate` does; Apply
   and Consolidate as commands plus `<localleader>a/A/c` in `:clip.recipe`; `blake3` added with a
   paw-crates.md row; sampler bundles not collected by default, collect asks with the size).
