# Containers in place of Track: a review

Superseded where it differs by [architecture-plan.md](architecture-plan.md) (2026-11-23).

**Version 2 (2026-11-23).** The owner answered every question of this
review ([owner-answers-2026-11-23.md](owner-answers-2026-11-23.md)).
The answers change the design more than this review expected. The
result is part "Version 2" of
[architecture-plan.md](architecture-plan.md) and the decision records 0017 to
0032 in `architecture/decisions/`. Read them first. What changed against
this review:

1. The verdict "generalize `Track` in place, keep the word" is replaced.
   The **lane** is the first-class unit and the truth. The container is
   a **part**: a named folder of lanes that nests (user word "part", not
   "track"). The rename is bundle W1.
2. A lane holds **one** kind of clip (no lane 0 that takes every kind).
   A lane is typed: its clip kind gives a stream, plus **properties**
   (channels, lyrics present, rig, frame rate). Ports declare what they
   need; paw inserts a **converter** or refuses with a message that names
   the missing property (3.1, 3.5, Q4 of this review).
3. `mix: Option<Mix>` (3.1, C4) is replaced. A mix is the live audio
   part of the graph: **strips, buses, sends, master and VCAs are
   nodes**. A strip is a free node; a new audio lane gets its own strip
   by default; two lanes can share one. Arm is on recordable source
   lanes, mute on any lane or node, solo on strips and buses.
4. **One project graph**, composed from the graph of each part. Two
   kinds of arrows: stored lanes and live signals. The chain document is
   the graph of one part (7.2 changes: strips, buses and wires are in
   the text; the `produce` block of 7.3 goes, a producer is a node and
   its sink is a store wire).
5. "Apply" (3.3) becomes **render**, with **provenance** (a recipe and a
   hash of the source), "re-derive as a new take", and `:lane.detach`.
   Render turns any signal into a lane: freeze, print, a stack prefix,
   a derived take.
6. Takes are not lanes with `role: Take` (3.1). **Every lane has
   takes**; source or derived is a property of each take; a **comp** is
   source data of the lane.
7. Automation (`Track.automation` in 3.2) becomes lanes of kind
   `curve` that feed a node parameter.
8. Producer tiers are named live, kernel and bake. Per-note producer
   controls live on the source notes. Outside programs run only in bake
   jobs and not when a project opens. paw asks one time for each
   program. The jobs run in a sandbox.
9. Project folder: a folder for each part (nested), a folder for each
   lane inside it, `devices.chain` for each part, `ext/<name>/` (6.1 "Files").
10. Rule 4 becomes "Lanes are the truth" (3.3).
11. The steps C2 to C6 (6.3) become the bundles A2, LA, MX, CV, TK, RD,
    TY, OP and VD of the plan's V2.11.

Status: review in progress. No tracked file changed. Nothing was built.
Base: main at deb79a0f. Date: 2026-11-23. Internal text (ASD-STE100).

## Interim: running work

The owner asks if `Track` must stop being the first-class container. The
full answer is below. The answer for the running work does not wait for
it, because both answers are the same for each possible result: the
devices graph and the chain language are already generic parts. They
only must not tie themselves to `Track`.

| Bundle | Verdict | Change |
| --- | --- | --- |
| TASK-279 (devices graph kernel model, `Track.graph`, racks, `Linked<D>`, split kinds as open words) | Continue, with one change | Make `Graph` a value that does not know its owner. 1. `Graph`, its nodes, splits and racks are in their own module (for example `model/graph.rs`). No type in that module holds a track `Id` or reads a `Track`. `Track` holds `graph: Option<Arc<Graph>>` and that is the only link. 2. The edit functions take a graph and give a graph (`fn wrap(&Graph, ..) -> Result<Graph, GraphError>`). The session finds the owner and does the undo step. 3. `paw.graph` names the graph by an owner handle (`paw.graph.of(track)` or `{track = id}`), not by a bare track id in each function. Then a later container (an entity, a nest, a clip) can own a graph with no change of the graph code. Do not add stream types or video ports now. |
| TASK-281 (generic `chain-syntax` crate) | Finished as it was; refine it in a follow-up ticket | The crate knows no host, so it knows no track: keep it so. The owner asked to refine the language for containers. Section 7 gives the changes (typed ports and stream kinds from the schema, a `produce` block, sinks, references across containers, `chain 2`, `chain_schema: 2`). They go in one follow-up ticket after TASK-287 merges, because both change `check.rs`. |
| TASK-287 (chain tools: lints, command line, `chain-lsp`, MCP) | Continue, with one change | No lint, completion or hover assumes that each port is audio or that each reference is inside the document. Keep the codes E213 to E218 and W302 free for section 7. Let the server take an optional host context (the streams outside the document and the sinks) from the client now, empty by default, so that section 7 adds data and not a new protocol. |

Nothing that runs now must stop.

## 0. Verdict

The owner is right about the problem and too large about the cure. paw
already has most of the generic container: a track holds clips of any
kind (`ClipContent::Custom`, `model.rs:696`), groups are tracks in a tree
(`groups.tl:1-15`), track kinds exist (`track_kinds.lua:1-21`), and a
subproject has its own tracks (`model/nest.rs:1-22`). Three things are
missing, and they are the parts of the owner's examples that do not fit
today:

1. **Several typed rows inside one container.** A track has one row of
   clips (`Track.clips`, `model.rs:135`). Takes hide in
   `clip.meta.takes` (`takes.tl:33`), and automation is a separate list
   (`Track.lanes`, `model.rs:138`). "Violin I source" with its MIDI, its
   printed audio, its performer notes and its video is four tracks today,
   not one thing with four rows.
2. **Derived rows with a recipe.** Audio made from MIDI is a freeze
   (`freeze.rs:1-23`), a special case in `meta`. Keyframes made from
   MIDI, or video made from keyframes, have no place. paw has the parts
   (Modifier, `midi-modifier-stacks.md`; recipes and bakes, `media.md`;
   the derived graph, `derived.md`), but no row that says "I am made
   from that row by this producer".
3. **A container that makes no sound.** Each track has a fader, a pan,
   devices and an output (`model.rs:125-134`), and the engine makes a
   `TrackRt` for each (`paw-engine/src/engine/track.rs:11`). A folder of
   video or of notes for performers pays for a mixer strip that it does
   not need.

So the recommendation is **"generalize Track in place"**, not a new
entity model. Keep the container and its name. Give it a parent (a tree
in the model, not in `meta`), typed **lanes** (source, take or derived),
and an optional **mix** (the audio part: fader, devices, graph, routing).
Add **producers** as kinds that make a derived lane from other lanes, in
three tiers: the realtime audio graph (exists), kernel functions
(Modifier), and bake jobs (media). Do it in six steps. Each step leaves
paw working. A full ECS or a rename of every "track" costs months, breaks
344 runtime and extension files, and gives the user nothing that the
steps do not give.

## 1. What exists: the evidence

References are at main deb79a0f.

### 1.1 The track in the kernel

| Part | Where | What it means for a container |
| --- | --- | --- |
| `Track` | `crates/paw-core/src/model.rs:121-193` | One struct mixes three concerns: identity (`id`, `name`, `color`, `meta`, `height`), content (`clips`, `cues`, `lanes`), and the audio strip (`volume`, `pan`, `mute`, `solo`, `armed`, `output`, `sends`, `devices`, `input`, `monitor`, `midi_input`, `midi_output`, `automation`, `attr_map`, `chain_source`). |
| `Project.tracks` | `model.rs:70-72` | A flat list. The song's tracks and the tracks of all nests are in one list, tagged by `Track.nest` (`model.rs:192`). Order in the list is order on the screen. |
| `Project.master` | `model.rs:69` | The master is a track with `MASTER_ID` 0 (`model.rs:38`). |
| `Track.output` | `model.rs:132` | The track that this one feeds. This is the only real tree in the model, and it is an audio tree. |
| `Track.sends` | `model.rs:133`, `Send` at `model.rs:460` | Audio only. |
| `Track.devices` | `model.rs:134` | A flat chain. TASK-279 adds `Track.graph` beside it (`devices-graph.md` 4.3). |
| `Track.clips` | `model.rs:135`, `Clips` at `model/clips.rs:31` | One row. A clip has a content: `Midi`, `Audio`, `Custom`, `Nest` (`model.rs:696-725`). Clips of several kinds can share the row. |
| `Track.lanes` | `model.rs:138`, `Lane` at `model.rs:1160` | Automation only. `Target` is `Volume`, `Pan`, `Param`, `State` (`model.rs:1308-1320`): each target is a part of the audio strip. |
| `Track.cues` | `model.rs:170` | The launcher's clips, off the timeline. |
| `Track.meta` | `model.rs:141` | Groups (`meta.group`), VCAs (`meta.vca`), track kinds (`meta.kind`), freeze (`meta.frozen`) all live here. |

### 1.2 Kinds and structure in the runtime

| Feature | Where | How it is built |
| --- | --- | --- |
| Groups (folders that sum) | `runtime/lua/paw/groups.tl:1-15`, `is_group` at `:142` | A group is an ordinary track marked in `meta`. Members name it in their own `meta`, and their `output` is the group. So a folder always sums audio. |
| VCAs | `runtime/lua/paw/vca.tl:1-17`, `is_vca` at `:67`; the sync at `sync/automation.rs:139-144` | A track marked in `meta`. The sync folds the VCA fader into each member. The VCA has a `TrackRt` that plays nothing. |
| Track kinds | `runtime/lua/paw/track_kinds.lua:1-21` | `meta.kind`. A kind says how a track is made and how its clips open. It adds no data shape. |
| Clip kinds | `runtime/lua/paw/clip_kinds.tl:1-30`, `model/custom.rs:1-15`, `CustomContent` at `:348` | Data, media, sound and signals. A timeline in beats or seconds (`Timeline`, `custom.rs:185`). The sound is saved, so the project plays without the extension. |
| Takes | `runtime/lua/paw/takes.tl:1-40` | `clip.meta.takes`. Take lanes are view rows of the arrange view, kept for the session. |
| Automation lanes as rows | `runtime/lua/paw/lanes.tl:1-15` | View rows under a track. |
| Folds | `runtime/lua/paw/folds.tl:1-30` | View state. A group is a fold by itself. |
| Subprojects | `runtime/lua/paw/nest.tl:1-16`, `model/nest.rs:1-22` | Tracks with their own timeline, a closed routing boundary, and a nest clip that places them. |
| Freeze | `crates/paw-core/src/freeze.rs:1-23` | A rendered file in `meta.frozen.file` that the engine plays in place of clips and devices. This is a derived audio row in all but name. |
| Derived data | `runtime/lua/paw/derived.tl:1-30`, `derived.md` | One dependency graph for data that Lua derives, with stamps and slices. |

### 1.3 The engine and the sync

- `sync/mod.rs:1-17` is the only place that tells the engine what the
  project is. Its order: a track, then its devices and clips, then the
  schedule.
- `sync/routing.rs:127` (`routing_of`) and `:229` (`build_schedule`)
  walk tracks by `output`, `sends` and side-chains.
- `TrackRt` (`paw-engine/src/engine/track.rs:11-45`) holds the buffer,
  the chain, the clips, the automation, the fader, the inputs and the
  meters of one track. `Msg::SetChain` (`engine/msg.rs:58`) sends a chain.
- So the engine knows "an audio strip with clips". It does not need to
  know about a container. That is the main fact for the design: the
  container can change above the sync with little change in the engine.

### 1.4 The arrange view

- `views/arrange.tl:305-313`: rows are already of several kinds: a
  track, a take lane (`kind = "take"`), an automation lane
  (`kind = "lane"`), and the closing line of a subproject (`kind =
  "end"`).
- `views/arrange.tl:2008-2011`: "Lines, not tracks, go down, because rows
  of other kinds have heights of their own." The view moved past "one
  row per track" already.
- `paw.groups.rows()` (`groups.tl:238`) gives the track order with folds.
  The arrange view calls it 4 times (`arrange.tl:394`, `:2549`, `:2574`,
  `arrange_mouse.tl:527`).
- The assumption that stays: each row belongs to one track, and the
  track header is the first row. The mixer view draws one strip per
  track.

### 1.5 The size of "track"

- 344 Lua and Teal files in `runtime/` and `extensions/` contain the word
  `track`.
- `crates/paw-core/src` has about 2300 occurrences of `track`.
- The project files have `tracks/<name>/track.json` and `devices.json`
  (`docs/explanation/about-project-files.md`).

A rename of the word costs more than any feature in this design.

## 2. Prior art

| System | The container | What it gained | What it cost users |
| --- | --- | --- | --- |
| Unreal Engine Sequencer | An object binding (an actor) with typed sub-tracks under it: transform, property, animation, audio, event. Folders group bindings. Sources: [actor tracks](https://dev.epicgames.com/documentation/unreal-engine/cinematic-actor-tracks-in-unreal-engine), [track list](https://dev.epicgames.com/documentation/unreal-engine/sequencer-track-list-in-unreal-engine), [dynamic binding](https://dev.epicgames.com/documentation/unreal-engine/dynamic-binding-in-sequencer). | One row per thing in the scene, and all of its timed data folds under it. This is the owner's picture almost exactly. | Each sub-track type is C++ code. Users must know which track goes on which binding. Bindings break when the actor is renamed or respawned; "dynamic binding" exists to fix that. |
| OpenTimelineIO | Timeline > Stack > Track > Clip, Gap, Transition; a Track or Stack can nest as a clip; clips name media by reference; each object has a `metadata` dictionary. Source: [timeline structure](https://opentimelineio.readthedocs.io/en/v0.15/tutorials/otio-timeline-structure.html). | One small schema that every editor can exchange. Nesting is a clip, so nesting costs nothing new. | Track kind is only "Video" or "Audio". Everything else is blind metadata, so tools lose meaning in exchange. |
| Pixar USD | Prims in a tree; typed attributes; time samples on any attribute; composition (references, payloads, inherits) with "strongest wins". Sources: [glossary](https://openusd.org/dev/glossary.html), [NVIDIA terms](https://docs.omniverse.nvidia.com/usd/latest/learn-openusd/terms-concepts.html). | Any data on any node, over time, and reuse by reference with local overrides. | Very hard to learn. Composition rules are a field of study. Tools are needed to see why a value is what it is. |
| Blender | Objects and data blocks; the NLA holds strips of actions with blend and influence; the VSE holds strips of any media; geometry nodes make data from data. Sources: [NLA strips](https://docs.blender.org/manual/en/3.6/editors/nla/sidebar.html), [data blocks](https://docs.blender.org/manual/en/latest/files/data_blocks.html) (not checked in this session). | Non-destructive stacks with Apply. Data made by nodes, evaluated on demand. | Each editor has its own idea of a "track" (NLA track, VSE channel, dope sheet). Users find no one place. |
| Houdini, TouchDesigner | Typed node families: SOP (geometry), CHOP (channels, audio), TOP (images), DAT (tables, text), COMP (containers). Only nodes of one family connect; conversion nodes cross families. Source: [operator family](https://docs.derivative.ca/Operator_Family). | Producers of any type, and a clear type for each wire. A COMP is a generic container. | No timeline as the main view. A musician must think in a graph. Conversions are explicit nodes, which is good for clarity and bad for speed of work. |
| REAPER | One type of track. A folder is a track with children, and it can hold items and envelopes. An item has takes; a take can be audio, MIDI, video, or empty. Sources: [Cockos wiki terms](https://www.cockos.com/wiki/index.php/ReaperTerms), [video support](https://www.cockos.com/wiki/index.php/Video_Support). | "No track types" is powerful and simple. Video is a take like any other. | Each track is an audio strip even when it holds only video or notes. Takes of different kinds in one item confuse. The UX gives no meaning to a folder beyond "it sums". |
| Bitwig | A track is a device chain with clips; hybrid tracks hold audio and note clips in one row (from the Bitwig user guide, not checked in this session). | One row for a sound source, whatever its clips are. | Still one audio strip per track. No non-audio data. |
| Game engine ECS (Bevy, others) | An entity is an id; components are data; systems act on entities with a set of components (from Bevy's documentation, not checked in this session). | Open composition: any data on any entity, systems added by plugins. | Data and behavior are far apart. Order of systems is hard to see. For a UI, "what is this thing" has no answer; editors add their own concepts on top. |
| Final Cut Pro, DaVinci Resolve | Compound clips: a group of clips, audio and video, as one clip that nests; edits of the contents reach every instance. Source: [Final Cut Pro compound clips](https://support.apple.com/guide/final-cut-pro/ver8e3f3205/mac). | Containers on the time axis, with a linked definition. | Hidden content; "break apart" is a one-way trip for the instance. |

What paw takes from this:

- **From Unreal:** a container row with typed rows folded under it. Done
  as lanes of a track.
- **From REAPER:** one type of container, no track types in the model.
  A kind is a label and a set of defaults, not a different struct.
- **From TouchDesigner and Houdini:** a type for each stream and an
  explicit producer to cross types. No silent conversion.
- **From Blender and USD:** derived data is a recipe plus a cache, with
  Apply. Reuse by a link with overrides (`Linked<D>`).
- **From OTIO and Final Cut:** nesting is a clip (paw has the nest clip).
- **Not taken:** USD composition, a free ECS with systems, a graph as
  the main view.

## 3. The model

### 3.1 The picture

```text
Project
 └─ Track  (the container; one type; a tree)
     ├─ id, name, color, kind: Option<KindId>, parent: Option<Id>, meta
     ├─ lanes: [Lane]                      ← typed rows of time
     │    Lane { id, name, kind: Option<KindId>, role, clips: Clips, meta }
     │    role = Source                    the truth: the user edits it
     │         | Take { of: LaneId }       a take of another lane (comping)
     │         | Derived(Recipe)           made from other lanes; a cache
     │    Recipe { producer: KindId, version, inputs: [StreamRef],
     │             params: Stored, mode: Live | Baked, kept: Option<Bake> }
     │    StreamRef = Lane(track, lane) | Out(track)   (Out: the track's audio)
     ├─ automation: [AutoLane]             ← today's Track.lanes, unchanged
     └─ mix: Option<Mix>                   ← the audio strip; None = no sound
          Mix { role: Strip | Bus | Vca, volume, pan, mute, solo, armed,
                output, sends, devices, graph (TASK-279), input, monitor,
                midi_input, midi_output, automation mode, attr_map }

Producers (kinds, in three tiers)
  tier 1  realtime   the device graph of a Mix     audio and MIDI only; audio thread
  tier 2  kernel     Modifier-like pure function   MIDI → MIDI, MIDI → keyframes, text
  tier 3  bake job   render, external process      MIDI → audio print, keyframes → video
```

Words, one for each thing:

| Word | Meaning |
| --- | --- |
| track | The container. One type. It has a parent, lanes and maybe a mix. The user word stays (question 1). |
| lane | A row of time inside a track. It holds clips. It has a kind and a role. |
| stream | The data of a lane over time, or the audio output of a track (`Out`). A producer reads streams. |
| producer | A kind that makes a derived lane from streams. |
| mix | The audio strip of a track. Optional. |

### 3.2 Today's track, with nothing lost

| Today | In the model |
| --- | --- |
| A MIDI or audio track | A track with one source lane (lane 0, no kind filter, so MIDI, audio, nest and custom clips can share it as today) and a `Mix { role: Strip }`. |
| `Track.clips` | `lanes[0].clips`. |
| `Track.lanes` (automation) | `Track.automation`. Same data. The name `lanes` goes to the new rows, because "lane" is the user word for a row under a track. |
| `Track.cues` | Stays on the track. The launcher is not a lane of time. |
| A group | A track with children (`parent` on each child) and `Mix { role: Bus }`. The children's mix output defaults to the nearest ancestor with a mix. |
| A folder that does not sum | A track with children and no mix. New: today each folder sums. |
| A VCA | A track with `Mix { role: Vca }` and members. The sync folds it as today (`sync/automation.rs:139`). It gets no `TrackRt`. |
| Sends, side-chains | In `Mix`, unchanged. |
| Master | A track with `Mix { role: Bus }` and no output. |
| A track kind | `Track.kind` (from `meta.kind`, as m-10 question 4 decided). |
| Takes | Lanes with `role: Take { of }`. Comping stays on the clip pieces (`takes.tl:16-21`). The take lanes that `zt` shows now become real rows of the model. `clip.meta.takes` goes. |
| Freeze | A derived lane of kind `audio`, producer `render`, `mode: Baked`, with "play in place of the source" set. The engine plays it in place of the clips and devices, as `freeze.rs` does now. |
| A subproject | Unchanged: tracks with `nest`, a nest clip on a lane. The nest's master is a track with a bus mix. |
| A linked clip | Unchanged (`model/links.rs`). |
| A linked rack | In the `Mix` graph (TASK-279), through `Linked<D>`. |
| `meta` | Stays on the track, the lane and the clip, for extensions only. |

The engine does not see lanes. The sync sends, for each track with a
mix, the clips of its sound lanes that play (its source lanes, or the
derived lane that replaces them), as `build_clips` does now with one
list. Tracks with no mix make no `TrackRt`.

### 3.3 What "MIDI is the truth" becomes

The rule now (`docs/explanation/about-midi-as-the-truth.md`): notes are
the truth, views edit them, extensions keep data in `meta`. The clip
kinds design already changed it to "the clip's owner is the truth; what
it plays is saved" (`clip-kinds.md` section 0).

With lanes, the rule is:

1. **Source lanes are the truth.** The user edits them. MIDI notes stay
   the truth of a MIDI lane, and every view of notes edits them.
2. **A derived lane is a recipe and a cache.** It is never edited in
   place. To edit it, the user does **Apply**: the result becomes a new
   source lane (or replaces the source), as one undo step. This is
   Blender's Apply, Modifier's Apply (`midi-modifier-stacks.md` section
   0), and media's consolidate (`media.md` section 0).
3. **A project plays without the producer.** A derived lane whose
   producer is absent plays its kept bake (`media.md`, "some bakes are
   kept"). A tier 2 result whose producer is absent is kept as data, as
   a custom clip keeps its sound. So rule 4 of AGENTS.md stays true in
   its intent: an extension never owns source data, and a project always
   opens and plays.
4. **Performer notes are a view or a source, never a second truth.** A
   score of Violin I is a lens on the MIDI lane (notation). Free text for
   the performer ("con sord. from bar 12") is a source lane of kind
   `text`. The two never copy each other.

### 3.4 How it fits Kinds, Modifier, Template and `Linked<D>`

- **Kinds (K, rank 1 of the m-10 review).** Lane kinds are the family
  `clip` (a lane's kind filter names a clip kind). Producers are a new
  family `producer`. Each entry has the owner, version, codec and absent
  rule of K. Track kinds stay a family. No new registry type.
- **Modifier (M).** A tier 2 producer with one input of the same type is
  a modifier stack on a lane. A modifier stack on a clip is the small
  case; a derived lane is the case "the whole stream, maybe from another
  track". Both use the same `ModifierKind<C>` trait, keys and cache.
  A producer that changes type (MIDI to keyframes) is `ProducerKind<I,
  O>`; it shares the registry, the key chain and Apply, not the trait.
- **Template (T).** A track template captures a track with its lanes,
  recipes and mix. "Violin I source" as a template makes all five rows.
- **`Linked<D>` (L).** A linked track template is `Linked<TrackDef>`;
  per-instance overrides are a modifier stack, as for racks.
- **The devices graph.** It hangs on the `Mix`, not on the track. It is
  the tier 1 producer: the only producer that runs on the audio thread.

### 3.5 Rules the kernel checks

- The tree has no cycle; a nest's tracks stay in their nest
  (`check_nest`).
- The producer graph (lanes and `Out` streams) has no cycle. An `Out`
  input that comes from the track's own output into a derived lane that
  plays in the same track is refused, unless it replaces the source
  (freeze).
- A lane with a kind accepts only clips of that kind.
- A sound lane on a track with no mix is allowed (it can be an input of
  a producer) but is silent, and `K` says so.

## 4. The engine

### 4.1 Audio stays as it is

- The audio thread rules do not change: no lock, no allocation, no
  wait. The engine still gets tracks with a mix as `TrackRt`, their
  chains or graph plans, and their clips.
- The schedule walks the mix tree (`output`, sends, side-chains), not the
  container tree. A folder without a mix is invisible to the engine.
- Tier 1 producers are the devices graph only.

### 4.2 Non-audio streams

| Stream | Made by | Cached as | Played by | Time base |
| --- | --- | --- | --- | --- |
| MIDI (source) | the user | the model | the engine (clips) | beats |
| MIDI (derived) | tier 2 | the modifier cache, by key | the engine, as compiled clips | beats |
| Audio print | tier 3 `render` | kept bake (`media/baked/<key>.wav`) | the engine, as an audio clip | seconds, placed in beats |
| Keyframes | tier 2 (from MIDI) | kernel cache by key; saved as clip data when the producer is absent | the frontends and producers read them; signals if they drive OSC | beats (they follow the music) |
| Video (source) | the user | the media table (`media.md`) | a video thread outside the engine | seconds (`Timeline::Seconds`, `custom.rs:185`) |
| Video (derived) | tier 3 (external process) | kept bake | the video thread | seconds |
| Text notes | the user | the model | the views | beats |

- **The bake scheduler** of `media.md` runs tier 3. A job has a key (a
  hash of its inputs' keys, the producer version and the params), runs
  outside the kernel thread, and reports to the agenda of the event loop
  (`event-loop-review.md`, S3), so a test waits for it with no time.
- **Tier 2** runs in the kernel in slices (`derived.tl`), under the key
  budget, with the early cutoffs of `derived.md`.
- **Video playback** reads the engine's play position (an atomic that
  the engine writes, as the meters do) on a thread of its own, and
  decodes a proxy. The terminal shows the frame in a monitor view (half
  blocks, or the kitty graphics protocol where the terminal has it).
  Audio of a video is extracted into an audio file and plays as an audio
  clip (`clip-kinds.md` section 1, item 1).
- **Stale results.** A derived lane shows its last result with a stale
  mark until the new one is ready. It never blocks a key.

### 4.3 What the engine must not become

- Not a compositor. The engine never decodes, scales or mixes pictures.
- Not a general dataflow scheduler. Tier 2 and tier 3 run outside the
  audio thread. The audio thread never waits for a producer.
- Not a host of scripts on the audio thread. A Lua or external producer
  runs in a bake job or in kernel slices only.
- Not a free graph of cables between tracks. Audio stays the mix tree
  plus sends and side-chains. Cross-track data goes through producer
  inputs, which are not realtime.

## 5. UX

### 5.1 Lenses

- **Arrange** stays the main lens. A track is a row. Its lanes fold under
  it, as take lanes and automation lanes do now (`arrange.tl:305`). A
  derived lane shows its producer and its state at the left.
- **Score** (notation) is a lens on a MIDI lane.
- **Video monitor** is a window that shows the frame at the play
  position of a chosen video lane.
- **Performer** is a lens over one track: its score, its text notes and
  its video side by side. It is a layout of existing views, not a new
  view.
- **Producers** shows the derived lanes of the project as a list with
  inputs and state (`:producers`, a quickfix-like list). A graph picture
  is not needed first.

### 5.2 Keys, under the key rule

| Key or command | Does | Rule |
| --- | --- | --- |
| `j` `k` | Move across track rows and lane rows | only moves |
| `za` `zo` `zc` on a track | Open or close its lanes (as folds) | `z` is the view |
| `zt` | Show the take lanes (exists) | unchanged |
| `K` on a lane | Describe: kind, role, producer, inputs, key, state, size of the kept bake | `K` describes |
| `gd` on a derived lane | Go to its first input lane | a jump, like a definition |
| `gr` on a source lane | List the lanes that read it | like references |
| `Enter` | Open the lane's editor by kind (piano roll, video monitor, text) | as for a clip |
| `<localleader>a` | Add a lane to the track (picker of kinds and producers) | keys of one view |
| `<localleader>b` | Bake the derived lane now | keys of one view |
| `<localleader>A` | Apply: the derived lane becomes a source lane (one undo step) | keys of one view |
| `+` `-` on a lane | The lane's gain for a sound lane; else nothing | main value |
| `:lane.add {kind}`, `:lane.derive {producer} {inputs}`, `:lane.bake`, `:lane.apply`, `:lane.remove` | Ex forms of the above | |
| `:track.move {parent}` | Move a track into a container | |

Each action is one undo step and says what it did ("Lane Keyframes
derived from Violin I source/MIDI by midi-keyframes; baking").

### 5.3 The Violin I examples, 100 x 30

The arrange view with the Strings group open and Violin I source open:

```text
 Strings ▾ Violin I source                                     120 ♩ 4/4  ▶ 00:12.480   bar 7.1.000
──────────────────────────┬─────────────────────────────────────────────────────────────────────────
 TRACKS                   │1       │5       │9       │13      │17      │21      │25      │29
──────────────────────────┼─────────────────────────────────────────────────────────────────────────
▾ Strings          B  -3dB│
  ▾ Violin I source  S  0d│ ▕Theme A·········▏ ▕Theme B·········▏          ▕Coda····▏
    ├ MIDI       source   │ ▕♪♪♪ ♪♪ ♪♪♪♪ ♪♪ ▏ ▕♪ ♪♪♪ ♪♪ ♪♪ ♪♪♪▏          ▕♪♪ ♪♪♪ ▏
    ├ Audio  ← render  ✓  │ ▕▁▃▅▇▅▃▂▃▅▆▅▃▂▁ ▏ ▕▂▃▅▆▇▆▅▃▂▃▅▃▂▁▏          ▕▃▅▃▂▁  ▏
    ├ Notes      text     │ ▕con sord.      ▏ ▕senza sord. ff ▏          ▕dim.   ▏
    ├ Video      source   │ ▕▣ take3.mp4 00:00────────────────────────────────────▏
    └ Volume     auto     │ ─────────╲_______________╱‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
  ▸ Violin I performance S│ ▕▣ player.mp4───────────────────────────────────────────▏
  ▸ Violin II        S  0d│ ▕Theme A·········▏ ▕Theme B·········▏
  ▸ Viola            S  0d│ ▕Theme A·········▏ ▕Theme B·········▏
  ▸ Cello            S  0d│ ▕Theme A·········▏ ▕Theme B·········▏          ▕Coda····▏
▸ Brass            B  -6dB│ ▕Fanfare·········▏                   ▕Fanfare·········▏
▸ Percussion       B  -4dB│ ▕Timp roll▏      ▕Timp roll▏         ▕Crash▏
                          │
                          │
                          │
                          │
                          │
                          │
                          │
                          │
                          │
                          │
──────────────────────────┴─────────────────────────────────────────────────────────────────────────
 NORMAL  Violin I source › Audio   derived: render(MIDI)  baked ✓  ⟨gd⟩ input  ⟨<ll>A⟩ apply
 :
```

The letters after a name: `B` a bus, `S` a strip, `F` a folder with no
mix (none on these screens). `← render ✓` says the lane is derived by `render` and its bake is
fresh.

The second container open, with a producer at work:

```text
 Strings ▾ Violin I performance                                120 ♩ 4/4  ■ 00:00.000   bar 1.1.000
──────────────────────────┬─────────────────────────────────────────────────────────────────────────
 TRACKS                   │1       │5       │9       │13      │17      │21      │25      │29
──────────────────────────┼─────────────────────────────────────────────────────────────────────────
▾ Strings          B  -3dB│
  ▸ Violin I source  S  0d│ ▕Theme A·········▏ ▕Theme B·········▏          ▕Coda····▏
  ▾ Violin I performance S│
    ├ Player     video    │ ▕▣ player.mp4 00:00 ──────────────────────────────────────▏
    ├ Player snd ← extract│ ▕▁▂▃▅▃▂▁▂▃▅▆▅▃▂▁▂▃▅▃▂▁▂▃▅▆▇▆▅▃▂▁▂▃▅▃▂▁▂▃▅▆▅▃▂▁▂▃▅▃▂▁ ▏
    ├ Keys  ← midi-keys ✓ │ ◆ ◆◆ ◆  ◆◆◆ ◆ ◆◆  ◆ ◆◆◆ ◆  ◆◆ ◆ ◆◆◆  ◆ ◆◆  ◆◆◆ ◆ ◆◆ ◆
    └ Avatar ← vtuber ⟳41%│ ▕▣▣▣▣▣▣▣▣▣▣▣▣▣▣▣▣▣▣▣▣░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▏
  ▸ Violin II        S  0d│ ▕Theme A·········▏ ▕Theme B·········▏
  ▸ Viola            S  0d│ ▕Theme A·········▏ ▕Theme B·········▏
  ▸ Cello            S  0d│ ▕Theme A·········▏ ▕Theme B·········▏          ▕Coda····▏
 ┌ K: Avatar ─────────────────────────────────────────────────────────────────────────────────┐
 │ Lane "Avatar" of Violin I performance. Kind: video. Derived (bake job).                    │
 │ Producer: vtuber 2 (extension "vtuber"), script avatar/violinist.py                        │
 │ Inputs:   Violin I performance › Keys (keyframes)   ← Violin I source › MIDI               │
 │           Violin I performance › Player (video, for the camera angle)                      │
 │ State:    baking 41 %, part 9 of 22; the parts done play now; the rest shows the last bake │
 │ Kept:     media/baked/7f3a…e1.mp4 (plays without the extension)                            │
 │ Keys:     gd input   <ll>b bake now   <ll>A apply (make it a source)   Esc close           │
 └────────────────────────────────────────────────────────────────────────────────────────────┘
──────────────────────────┴─────────────────────────────────────────────────────────────────────────
 NORMAL  Violin I performance › Avatar   ⟳ vtuber 41 %                    1 job, 0 errors
 :
```

The performer lens over Violin I source (a layout of the score, the text
lane and the video monitor):

```text
 Performer: Violin I source                                     120 ♩ 4/4  ▶ 00:12.480   bar 7.1.000
────────────────────────────────────────────────────────────┬───────────────────────────────────────
 SCORE  (lens on MIDI)                            bars 5-12 │ VIDEO  take3.mp4          00:12.480
                                                            │
  5            6            7 ▼          8                  │  ▗▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▖
 𝄞 ┃ ♩ ♪♪ ♩ ♩ ┃ ♩. ♪ 𝅗𝅥     ┃ ♪♪♪♪ ♩ ♩  ┃ 𝅗𝅥     ♩ ♩  ┃      │  ▐░░░░░░░▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░▌
   ┃          ┃ con sord.   ┃           ┃             ┃      │  ▐░░░░░▒▒▓▓▓▓▓▓▓▓▒▒▒░░░░░░░░░░░▌
   ┃ mp       ┃             ┃ <         ┃ mf          ┃      │  ▐░░░░▒▓▓██████▓▓▓▒▒░░░░░░░░░░░▌
                                                            │  ▐░░░▒▓▓██▀▀▀██▓▓▒▒░░░░░▄▄░░░░░▌
  9            10           11           12                 │  ▐░░░▒▓▓██▄▄▄██▓▓▒▒░░░▄▀  ▀▄░░░▌
 𝄞 ┃ ♩ ♩ ♩ ♩  ┃ 𝅝          ┃ ♪♪ ♪♪ ♩ ♩ ┃ ♩ ♩ 𝅗𝅥     ┃      │  ▐░░░░▒▓▓▓████▓▓▒▒░░░▀▄▄▄▄▀░░░▌
   ┃ senza sord.            ┃           ┃             ┃      │  ▐░░░░░▒▒▓▓▓▓▓▓▒▒░░░░░░░░░░░░░░▌
   ┃ f        ┃ >           ┃ ff        ┃             ┃      │  ▝▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▘
                                                            │
────────────────────────────────────────────────────────────┤ LANES
 NOTES  (text lane)                                         │  ● MIDI        source
  bar 7   con sord.                                         │  ○ Audio       ← render ✓
  bar 9   senza sord. — watch the conductor                 │  ● Notes       text
  bar 13  dim. to the end of the phrase                     │  ● Video       source
  bar 29  Coda: lead, solo violin                           │  ○ Volume      auto
                                                            │
                                                            │  Enter open   <ll>a add lane
                                                            │
                                                            │
────────────────────────────────────────────────────────────┴───────────────────────────────────────
 NORMAL  performer  Violin I source › Notes  bar 9                                  ]] next note
 :
```

### 5.4 One view, two frontends

Each lens is a view written once in Lua. The video monitor sends a
picture element in the scene; the terminal draws it with half blocks or
the kitty protocol, the window (when it comes back) with a texture. No
view exists only in the window.

## 6. Is it worth it, and when

### 6.1 The cost

| Area | Cost of the recommended steps | Cost of a new entity model |
| --- | --- | --- |
| Model (`model.rs`, `clips.rs`, `nest.rs`) | Add `parent`, `kind`, `Lane`; move the strip fields into `Mix`. Rust compiler finds each use. | New types for everything; every function on `Track` changes. |
| Files | `track.json` gets `lanes`; `clips/<lane>/`; no compatibility needed before release (memory: no compat before release). | A new layout. |
| Sync and engine | Skip tracks with no mix; collect the sound lanes. Engine: no change. | The sync is rewritten; the engine's `TrackRt` stays or is renamed. |
| Runtime and views | `paw.groups` reads `parent`; `paw.takes` reads take lanes; the arrange rows get a lane kind; the mixer skips tracks with no mix. | 344 files. |
| Extensions | Track kinds and clip kinds keep their API. | Every extension. |
| Docs | about-groups-and-vcas, about-midi-as-the-truth, project files, takes, freeze; new: about lanes and producers. | All docs that say "track". |
| Tests | The tests of groups, takes, freeze change their setup; new tests per step. | Most tests. |

### 6.2 The options

| Option | What | Verdict |
| --- | --- | --- |
| A. Rename only | Call a track an "entity" or "part" | No. It costs the most text and changes nothing. |
| B. Generalize Track in place | Tree, lanes, optional mix, producers, in steps | **Yes.** It gives every example of the owner. |
| C. New model (ECS) | Entity + components + systems | No. It costs months, puts a working product at risk, and its open composition is what K, M, T and L already give with types. |
| D. Do nothing | Groups + clip kinds + freeze | No. The owner's examples stay four tracks for one instrument, and derived rows stay special cases. |

### 6.3 The steps (option B)

Each step is one bundle, leaves paw working, and has tests and docs in
the same commits.

| Step | Work | Size | Depends on | Place in the m-10 roadmap |
| --- | --- | --- | --- | --- |
| C0 | TASK-279: the graph does not know its owner (see the interim answer). | S (in the running ticket) | none | now |
| L2 | Chain language 2 (section 7.6): stream kinds, ports, `produce`, sinks, references across containers, in `chain-syntax` and the schema; paw writes only `audio` and `midi` ports. | M | TASK-287 merged | phase 2, beside B2 (other files) |
| C1 | Design note: lanes, roles, producers, the three tiers; one section of the B1 "kinds" note. | S | owner answers section 7 | phase 1, with B1 |
| C2 | **Tree and kind in the model.** `Track.parent` from `meta.group`, `Track.kind` from `meta.kind`; `paw.groups` and `paw.track_kinds` read the fields; a folder with no sum is not yet possible. | M | B2 starts | phase 2, inside B2 (B2 moves `meta.kind` already) |
| C3 | **Lanes.** `Track.lanes` (rows) with roles `Source` and `Take`; today's clips are lane 0; automation becomes `Track.automation`; `clip.meta.takes` becomes take lanes; the arrange view draws lanes as rows (it has the row kinds); files per lane. | L | C2 | phase 3, beside B3 and B4; before B6 (built-in kinds draw on lanes) |
| C4 | **Optional mix.** The strip fields move into `Mix`; `Track.graph` (TASK-279) moves with them into `Mix.graph`; VCA and bus become `Mix.role`; folders with no mix; the sync skips them. | L | C3, TASK-280 merged (both change the sync) | phase 3, after TASK-280; before TASK-284 racks |
| C5 | **Derived lanes and producers.** The family `producer`; tier 2 on the Modifier core; tier 3 on the bake scheduler; freeze becomes the producer `render`; `K`, `gd`, `gr`, bake, Apply; `:producers` list. | L | C4, B5, media M2 | phase 4, after B5 |
| C6 | **Video and lenses.** The video clip kind (TASK-23) on a video lane, the monitor view, extract of the audio, the performer layout. | L | C5, TASK-23 C1 | phase 5 |

What happens to the devices graph: TASK-279 builds it on `Track.graph`
now. In C4 the field moves into `Mix` with the rest of the strip. If
TASK-279 keeps the graph free of its owner (C0), that move is a
mechanical change of one field and of the session's lookup.

Before or after Kinds: C2 goes inside B2, because B2 already moves
`meta.kind` and `meta.takes` into the model, and a second pass over the
same fields would be work done twice. C3 to C6 come after Kinds, because
lane kinds and producers are families of K.

### 6.4 The risk

- **The largest risk is C4.** It touches the sync, the mixer, routing,
  freeze and every reader of the strip fields. Do it only after TASK-280
  merges, with a null test (the same project renders the same bits
  before and after).
- **C3 changes the file layout.** No compatibility is needed before a
  tagged release, but the e2e expected outputs change: the owner or CI
  updates them.
- **Scope creep in C5.** Producers invite a general dataflow system. Keep
  three tiers, no cables, a DAG check, and no producer on the audio
  thread.
- **The `paw-scene` change for pictures** (C6) can stop the build of the
  window (`crates/paw-gui`, paused). Report it then.

## 7. The chain language and containers

Read at the TASK-281 branch (`worktree-agent-ad8bc9b308ad8837e`, commit
303d0c54): `crates/chain-syntax`, `docs/reference/chain-language.md`,
`docs/reference/chain-schema.md`, `crates/paw-core/src/chain_schema.rs`.

### 7.1 What the language describes today

- A document is one chain: a header `chain 1`, the nodes of the top level
  in series, splits with branches, `mods` with links, and `checks`
  (`chain-language.md` "Grammar"; `tree.rs:36-46`).
- The signal has no type. Each node takes "the signal" and gives "the
  signal". Audio and MIDI pass along the series by a host rule that the
  text does not say.
- A reference is `@id` (an earlier node) or `@in` (the input of the
  chain) (`chain-language.md` "reference"). A param of type `source` can
  also take a word that the host gives a meaning to, "the name of a
  track" (`chain-schema.md` table of types; `schema.rs:151-154`).
- The schema has three lists of kinds: `devices`, `splits`,
  `modulators`, and `open_prefixes` (`schema.rs:16-35`). A kind has
  params and no ports (`schema.rs:37-51`).
- paw writes its schema in `paw-core/src/chain_schema.rs:16-23`: the
  devices of the registry, paw's splits and modulators, and the open
  prefixes `clap:`, `vst3:`, `lv2:`, `lua:`.

The crate is already generic: no paw word is in the grammar, and each
kind comes from the schema. That stays. What is missing for containers:
types on the signal, producers that are not in the live chain, outputs
that go to lanes, and references to streams of other containers.

### 7.2 What the language must describe

1. **Stream kinds, as open words from the schema.** `audio`, `midi`,
   `keyframes`, `video`, `text`, and any kind of an extension. The
   grammar knows none of them. The schema lists them, with a time base
   for people and tools (`samples`, `beats`, `seconds`, or none).
2. **Typed ports.** Each kind has inputs and outputs, each with a stream
   kind. One input and one output of each stream can be the main port:
   the series connects main ports. A stream that a node does not take
   passes through it, so MIDI passes through an EQ as it does today.
   Further inputs are fields of type `source` with a stream kind (as the
   side-chain `key` is today). Further outputs are named by
   `@id.port`.
3. **Producers.** Kinds that take streams and give streams, and that the
   host runs outside its realtime graph (tiers 2 and 3 of section 3.1).
   The vtuber kind takes `midi`, `keyframes` and `video` and gives
   `video`. A device can also run in a producer branch: the host then
   runs it offline (an EQ on extracted sound before it goes to a lane).
4. **Sinks.** The output of a producer branch goes to a name that the
   host gives a meaning to (for paw: a derived lane of the container).
   A derived lane's recipe (section 3.1) is the text of one producer
   branch.
5. **References across containers.** `@"Violin I source/MIDI"`: a quoted
   name after `@`. The language does not know what the name means. The
   host gives the check an optional **context**: the external streams
   and the sinks that exist, with their stream kinds. With no context,
   the check gives the warning W302 and does not check the kind.

What a document is the text of: **the graph of one container**. That is
its live chain (the `Mix` graph of section 3.1, as today) and its
producers. Not the container tree: the tree is the structure of the
project, and the arrange view, Ex and `project.toml` edit it. One
document for each container keeps one file for each track folder
(`tracks/<name>/devices.chain`), a small `git diff`, and the `rev` guard
of TASK-287 for each container.

What stays out of the language:

- the timeline data: clips, notes, keyframe values, video files, the
  text of text lanes, and the positions of clips;
- the lanes themselves (their order, kind filter, role and height): the
  text names a lane only as a sink or a reference;
- the container tree, groups, VCAs, and the strip (fader, pan, mute,
  solo, sends, output): they are in `track.json`;
- bake state: keys, kept files, progress. A bake is a cache of the text,
  not a part of it.

### 7.3 Grammar changes (language version 2)

New and changed EBNF lines. The other rules of `chain-language.md` stay.

```ebnf
chain       = header , { line } ;
header      = "chain" , version , [ name ] , { field } ;      (* version is 2; a reader of 2 reads 1 *)
line        = indent , ( node | branch | mods | modulator | checks | check
                       | produce | sink ) , [ comment ] ;
produce     = "produce" ;                                      (* new: a block, top level only *)
sink        = "=>" , ( word | quoted ) ;                       (* new: the last line of a producer branch *)
reference   = "@" , ( id-char , { id-char } , [ "." , port ]   (* @id, @id.port, @in *)
                    | quoted ) ;                               (* new: @"name", outside the document *)
port        = word ;
```

Where the lines go (the table of `chain-language.md` "Lines and
indents" gets two rows):

| Line | What goes one step under it |
| --- | --- |
| `produce` | Producer branches (`|` lines). Top level only, after the live chain and before `checks`. |
| A producer branch | Nodes in series, and at most one `=>` line as its last line. |
| `=>` | Nothing. |

Rules of the check that the grammar does not show:

- The live chain (the top level and its splits) holds only kinds with
  `realtime` true. A producer branch holds any kind.
- A node of the live chain cannot reference a node of a producer branch.
  It can reference the sink's stream from outside (`@"Avatar"`), which the
  host plays from its bake.
- A producer branch starts from the field of its first node that is a
  main input (`notes=@"Violin I source/MIDI"`), or from `@in` (the
  container's own source streams of that kind).
- Two branches cannot write one sink.
- References inside the document make no cycle. Cycles across documents
  are the host's check (section 3.5).

New diagnostics:

| Code | Severity | Problem |
| --- | --- | --- |
| `E213` | Error | A stream of the wrong kind: at a reference, at a sink, or between two nodes in series (an instrument after an audio effect that gives no MIDI, for example). |
| `E214` | Error | A kind that is not realtime in the live chain. |
| `E215` | Error | A node of the live chain that references a node of a producer branch. |
| `E216` | Error | Two producer branches with one sink. |
| `E217` | Error | A cycle of references in the document. |
| `E218` | Error | A port that the kind does not have (`@3.side` when node 3 has no output `side`). |
| `W302` | Warning | A reference outside the document, or a sink, that the host context does not have, or no context was given. Its kind is not checked. |

### 7.4 Schema changes (`chain_schema: 2`)

```json
{
  "chain_schema": 2,
  "host": "example",
  "streams": [
    { "stream": "audio", "name": "Audio", "time": "samples" },
    { "stream": "midi", "name": "MIDI", "time": "beats" },
    { "stream": "keyframes", "name": "Keyframes", "time": "beats" },
    { "stream": "video", "name": "Video", "time": "seconds" },
    { "stream": "text", "name": "Text" }
  ],
  "default_ports": {
    "inputs": [ { "port": "in", "stream": "audio", "main": true } ],
    "outputs": [ { "port": "out", "stream": "audio", "main": true } ]
  },
  "devices": [
    { "kind": "eq", "params": [ { "key": "hp", "type": "number", "unit": "Hz" } ] },
    { "kind": "compressor",
      "params": [ { "key": "key", "type": "source", "stream": "audio" } ] },
    { "kind": "synth",
      "inputs": [ { "port": "notes", "stream": "midi", "main": true } ] }
  ],
  "producers": [
    { "kind": "extract", "realtime": false,
      "params": [ { "key": "from", "type": "source", "stream": "video", "main": true },
                  { "key": "track", "type": "number", "integer": true, "min": 1, "default": 1 } ],
      "outputs": [ { "port": "out", "stream": "audio", "main": true } ] },
    { "kind": "midi-keys", "realtime": false,
      "params": [ { "key": "notes", "type": "source", "stream": "midi", "main": true },
                  { "key": "smooth", "type": "number", "unit": "ms", "default": 0 } ],
      "outputs": [ { "port": "keys", "stream": "keyframes", "main": true } ] },
    { "kind": "vtuber", "realtime": false,
      "params": [ { "key": "keys", "type": "source", "stream": "keyframes", "main": true },
                  { "key": "notes", "type": "source", "stream": "midi" },
                  { "key": "camera", "type": "source", "stream": "video" },
                  { "key": "script", "type": "text" } ],
      "outputs": [ { "port": "video", "stream": "video", "main": true } ] }
  ],
  "open_prefixes": [ "clap:", "ext:" ]
}
```

| Field | Where | Meaning |
| --- | --- | --- |
| `chain_schema` | top | `2`. A reader of 2 refuses 1 and 3 (no compatibility before a release). |
| `streams` | top, new | The stream kinds: `stream` (the word), `name`, `time` (`samples`, `beats`, `seconds`, or absent). A stream word with an open prefix may be missing. |
| `default_ports` | top, new | The `inputs` and `outputs` of a kind that gives none. Today's devices need no change: they get one main audio input and output. |
| `producers` | top, new | Kinds that may stand only in a producer branch. Same fields as a device kind. |
| `inputs`, `outputs` | a kind, new | Lists of ports: `port` (a word), `stream`, `main` (`true` for the port that the series connects; at most one for each stream). |
| `realtime` | a kind, new | `true` (the default for `devices`) when the host can run the kind in its live graph; `false` (the default for `producers`). |
| `stream`, `main` | a param of type `source`, new | The stream kind that the source must give, and whether the field is the main input of a producer branch. A `source` with no `stream` takes `audio`, as today. |

The check gets a second, optional input beside the schema: the
**context**, as JSON too, versioned with the schema:

```json
{ "chain_context": 2,
  "streams": [ { "name": "Violin I source/MIDI", "stream": "midi" },
               { "name": "Player", "stream": "video" } ],
  "sinks":   [ { "name": "Keys", "stream": "keyframes" },
               { "name": "Avatar", "stream": "video" },
               { "name": "Player snd", "stream": "audio" } ] }
```

The context is data of one document, not of the host, so it is not in
the schema. paw writes it for each container (`paw chain context
<track>`), and `chain-lsp` takes it from the client or from a file next
to the document.

### 7.5 Example documents

Today's track chain, unchanged but for the version. A reader of version
2 also reads it with `chain 1`:

```chain
chain 2 "Gtr bus"
-- the bus of the four guitars
eq #2 hp=90Hz lp=9kHz
band #8 "Tame" xover=150Hz,2.5kHz
  | Low #81
    compressor #5 ratio=4 threshold=-20dB key=@in
  | High #82 gain=-1dB
    saturation #6 drive=12dB curve=tube -- a little grit
layer #9 "Crush"
  | Dry
  | Crush gain=-12dB
    compressor #10 ratio=20 attack=0.1ms key=@2
rack #20 "Glue"
  saturation #21 drive=2dB curve=tape
  mods
    macro #31 "glue" value=40% -> #21.drive +6dB
mods
  lfo #30 sync=1/4 -> #81.gain -3dB, #9.mix +10%
checks
  latency <= 6ms
```

The Violin I performance container (section 5.3, second screen):

```chain
chain 2 "Violin I performance" rev="a41c07"
-- live: the sound of the player's video, from its lane "Player snd"
eq #1 hp=120Hz
reverb #2 "Hall" mix=18%
produce
  | Sound
    extract #p1 from=@"Player" track=1
    => "Player snd"
  | Keys
    midi-keys #p2 notes=@"Violin I source/MIDI" smooth=20ms
    => "Keys"
  | Avatar
    vtuber #p3 keys=@p2 notes=@"Violin I source/MIDI" camera=@"Player" script="avatar/violinist.py"
    => "Avatar"
checks
  latency <= 3ms
```

How the check reads it: `extract` takes `video` from `@"Player"` (the
context says `video`) and gives `audio` to the sink `Player snd` (an
audio lane). `midi-keys` gives `keyframes` to `Keys`. `vtuber` takes the
main output of `#p2` (`keyframes`), the MIDI of the other container and
the player's video, and gives `video` to `Avatar`. The live chain plays
the container's source and derived sound lanes through `eq` and
`reverb`. A typo such as `camera=@p2` gives E213: "`camera` takes
video, and `#p2` gives keyframes".

### 7.6 The changes, ready for a ticket

Title: "Chain language 2: stream kinds, typed ports, producers, sinks and
references across containers". After TASK-287 merges. Size M.

1. `chain-syntax` tree: `Document.produce: Option<Produce>`;
   `Produce { branches: Vec<Branch> }`; `Branch.sink: Option<Sink>`;
   `Reference` as an enum: `Node { id, port: Option<String> }`, `Input`,
   `External(String)`.
2. Lexer and parser: the keyword `produce`, the token `=>`, `@"..."` and
   `@id.port`; recovery as today; `VERSION` 2, and a reader of 2 reads a
   text of version 1.
3. Printer and formatter: the new lines; the formatter writes `chain 2`.
4. Schema: `SCHEMA_VERSION` 2; `streams`, `default_ports`, `producers`;
   `Kind.inputs`, `Kind.outputs`, `Kind.realtime`; `ParamValue::Source {
   stream, main }`. A schema of version 1 is refused with the message of
   `SchemaError::Version`.
5. Context: a new `Context` type and its JSON (`chain_context: 2`); the
   check takes `Option<&Context>`.
6. Check: E213 to E218 and W302, each with a golden diagnostic and a
   test that does not fire.
7. Property tests: print then parse gives the same tree with `produce`,
   sinks and external references; the fuzz target covers the new tokens.
8. Docs: `chain-language.md` (the grammar, the two rows of the indent
   table, an example for `produce`, `sink`, the new `reference` forms,
   the new codes) and `chain-schema.md` (the new fields, the context);
   the test that parses each example covers the new ones.
9. paw: `chain_schema.rs` writes `streams` (`audio`, `midi`) and the
   ports of the built-in devices (an instrument has a main MIDI input),
   and `producers` empty until step C5. `paw chain context` writes the
   context of a track (empty sinks until C3). Nothing else in paw
   changes.
10. `chain-lsp` (TASK-287): completion of external names and sinks from
    the context; hover on a port gives its stream kind; go to definition
    on `@"..."` asks the client (paw opens that container's document).

What this ticket does not do: run producers, add lanes, or change the
kernel model. Those are steps C3 to C5. The language gets ready first
because it is a published format with a version, and a change before a
release costs little.

## 8. Questions for the owner

| # | Question | Recommendation |
| --- | --- | --- |
| 1 | Does the user word stay "track" for the container, with the new meaning "a container with lanes", or does it change (part, entity, object)? | Keep "track". REAPER shows that "one type of track used in many ways" works. A rename costs 344 files and all docs, and the generality is in what a track holds, not in its name. |
| 2 | Generalize `Track` in place in steps (option B), not a new entity model? | Yes. |
| 3 | Can a track have no mix: a folder that does not sum, or a track of video or notes only? | Yes (step C4). |
| 4 | Does a lane have a kind that filters its clips, with lane 0 open to all kinds as today? | Yes. Kinds make the producers' inputs checkable. |
| 5 | Derived lanes in three tiers (realtime graph, kernel function, bake job), and never a producer on the audio thread? | Yes. |
| 6 | Can a producer read lanes of another track ("Violin I performance" reads "Violin I source")? | Yes, by lane reference, with a cycle check. Not for audio-rate signals: those stay sends and side-chains. |
| 7 | Can an extension's producer run an external process (a script that renders a video), in a bake job, with its result kept in the project? | Yes, as plugins do: declared by the extension, run in a job with a scratch home, its output kept so the project plays without it. |
| 8 | While a derived lane bakes, does it show the last result with a stale mark? | Yes. Never block a key for a producer. |
| 9 | Video in the terminal: the monitor view draws pictures with half blocks, and with the kitty protocol where the terminal has it? | Yes. The arrange view draws a video lane as a strip with times and names only. |
| 10 | Does freeze become the producer `render` on a derived audio lane (step C5)? | Yes. Freeze is the first derived lane that paw has, so it proves the design. |
| 11 | Order: C2 inside B2, C3 before B6, C4 after TASK-280 and before TASK-284 racks, C5 after B5? | Yes. |
| 12 | Does the chain language describe one container (its live chain and its producers), and not the container tree? | Yes (section 7.2). One file for each track folder, a small diff, one `rev` for each container. |
| 13 | Chain language 2 (stream kinds, ports, `produce`, sinks, `@"..."`) in one ticket after TASK-287, before the producers exist in paw? | Yes. It is a published format; change it before a release, when it costs little. |
