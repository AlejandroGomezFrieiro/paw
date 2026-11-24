# Derived data: one dependency graph (TASK-77)

Status: design for the owner's approval. The design changes no code.
Base: `main` at cf15cd12 (TASK-82.1 merged). Date: 2026-11-22.
Measurements: release build of that commit, `-j 4`, measured under external load.

## 0. The short version

paw has more than 30 caches of derived data. Each cache has its own key and its own
rules. Some keys are good: content stamps (the compiled events of TASK-7.2, the bake
keys of the media design, `Notes::stamp`). Some keys are poor: a global edit counter
(`roll_clips.context`, the notation score), "any change" (the GUI state, the arrange
previews), or no key at all (search, query, the LSP document key).

The chord reading (HARMONY-FAST, TASK-79, TASK-88) shows the method that works:

1. a content stamp for each input,
2. work again only for what an edit touches,
3. work in slices between keys,
4. views read the value as it stands.

The design makes that method one mechanism for all derived data that Lua makes.
The Rust caches keep their own types. They already use content keys, and they run on
other threads. The two sides share four things:

- the stamps that the kernel gives for each source of data,
- the change events that name the dirty sources,
- one order of priorities (playing, visible, background),
- one rule for a view: read the value as it stands, and draw again when its revision changes.

The first consumer is the chord reading. It gets a node for each track and window, and a
join. Then a mute of a track that spans the song does not weigh the notes of the other
63 tracks again. The target: a mute costs 10 ms of reading or less, against 28 to 46 ms
today.

## 1. Words

| Word | Meaning in the design |
| --- | --- |
| source | Data that the user edits: a clip's notes, a clip's place, a track's fields, the tempo map, the markers, an option. |
| stamp | A number that changes when a source changes, and that is the same for the same content. |
| derived value | A value that paw makes from sources and other derived values. paw can always make it again. |
| node | One derived value, with its key and its state (fresh, stale, being made). |
| key | The stamps of everything a node read when it was made. |
| family | Many nodes of one kind, one for each item (one for each clip, or each track and window). |
| join | A node that combines the nodes of a family (a sum, a lowest value). |
| early cutoff | A node made again gives the same key or the same value: its dependents stay fresh. |
| slice | A piece of work of at most a few milliseconds, between two keys (`paw.slices`). |
| consumer | Code that reads a derived value: a view, a command, the engine, an extension. |

## 2. Inventory of the caches today

"Cost" is the cost to make the value again on `bench/profile/project.lua` (64 tracks,
2 000 MIDI clips, 50 000 notes), where it was measured (see the measurements, part 3).
"Kernel" is the kernel thread: Lua and the Rust session.

### 2.1 Rust

| Cache | Where | Derived from | Key | Out of date when | Cost to make again | Thread | Memory limit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Notes stamp | `model/notes.rs` `Notes::stamp` | the notes of a clip | 53-bit hash of every note and its meta (`DefaultHasher`) | each `&mut` method clears the `OnceLock` | one pass over the clip's notes | kernel | one `u64` for each clip |
| Compiled events | `sync/clips.rs` `Compiled` | runs of notes, controllers, length, loop | runs by `Arc` identity (the entry holds the runs), the rest by value | never: a new source is a new key; `sweep` drops entries that no clip holds | the compile of one clip; 1.9 ms at 96 notes, 17.5 ms at 384 notes, for one clip (the N0 results of the nest design) | kernel | swept when entries are more than twice the count of the last sweep, plus 64 |
| What the engine was sent | `sync/mapper.rs` `Mapper`, `sync/mod.rs` | the project snapshot | `Arc::ptr_eq` of tracks, clips, devices, lanes, the tempo map (27 uses) | each sync compares the old and the new snapshot | the sync of what changed: 0.15 to 1.7 ms for one edit (part 3) | kernel | one entry for each item sent |
| Decoded audio | `sync/audio.rs` `AudioCache.files`, `converted` | an audio file, the engine's rate | path, (path, rate) | `retain` (files no clip uses), `forget_loaded` | the decode of the file | kernel (decode), disk store for long files | files that clips use |
| Peaks memo and overviews | `sync/audio.rs` `peaks`, `summaries`; `peaks.rs` | the decoded sound | (path, offset, length, points); the overview by `SourceHash` in the bake store | the memo is cleared when it is large; overviews by content | one pass over the samples of the file | kernel; the store on the disk | memo cleared past its size; store by `media_cache` |
| Stretch bakes | `stretched.rs` `Renders` = `bake::Scheduler<Key>` | file hash, warp, stretch, pitch, rate | `BakeJob` hash (the keys of the media design) | never: a new key; unwanted jobs cancel; 8 spare | the stretch of the file | worker threads (`clamp(cores / 4, 1, 4)`) | `SPARE` = 8 bakes not wanted; cache by `media_cache` |
| The bake store | `bake/store.rs` | any bake | 128-bit BLAKE3 entry (the keys of the media design) | eviction, least recently used | as the bake | worker | `paw.opt.media_cache` (16 GB) |
| Media hashes | `media/sources.rs` `Sources`, `media/index.rs` `LocalIndex` | the bytes of a file | path, then the hash of the bytes | a file event; a look for new files twice a second | a read of the whole file | worker | the files of the project |
| File check | `session/file_check.rs` | whether a path is a file | path, at most 1 s old | each edit, undo, load, save, file event | one `stat` | kernel | the paths of the clips |
| Folder layout | `session/folder.rs` `TrackCache` | a track's files in a project folder | `Arc` address of the track and the folder | never: the last two layouts stay | the serialization of one track | kernel (save), worker (undo file) | two layouts |
| Undo file blobs | `undofile.rs`, `session/undo_file.rs` | the files of each undo state | BLAKE3 of each file | unused blobs go after each write | the layout of a state | worker, after `:w` | `paw.opt.undofile_mb` (256 MB) |
| Undo weights | `history.rs` (`weigh`) | the memory of each state | the state | weighed again after 32 drops | a walk of the state | kernel | none |
| Frozen tracks | `freeze.rs`, `freeze.lua` | a track, its devices, what feeds it | none: the file in the track's meta | never; an edit asks the user to unfreeze | a render of the track | render thread | the files the user keeps |
| Scenes | `scene.rs` `Scenes` | what a view draws for a window | node names (`t3,5`); pictures over 16 kB by a content hash | each draw, compared with what the client has | the draw of the view | kernel | what each client was sent |
| Kept grid rows | `grid.rs` `grid_keep`, `roles.tl` (TASK-88) | the cells of one row of the arrange view | the row's clips (every field) and its ground | `hl_set`; a row whose clips changed | the Lua drawing of that row | kernel | the rows of the screen |

### 2.2 Lua and Teal

| Cache | Where | Derived from | Key | Out of date when | Cost to make again | Thread | Memory limit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Chord reading of the song | `harmony/song.tl` | notes of all unmuted MIDI clips of pitched tracks, bars, options | per clip `stamp:start:length`; a `stamp` counter of the reading | kernel events mark tracks; `edits` count; `project.loaded` resets | 7 to 16 ms after one note edit, 28 to 72 ms after a mute (part 3), in slices of 4 ms | kernel, job `harmony` | none; 15 MB of heap on the bench project |
| Chords of a range | `harmony.tl` `cache`, providers | the song reading or a provider | `cache.stamp` | `invalidate`, `harmony.changed` | a read of the range | kernel | one |
| Region tree | `markers.tl` `tree()` | the regions | a string of every region's fields, made on each call | a different string | O(regions²) for the parents | kernel | one tree |
| Scope resolution | `scope.tl` `resolve`, `tracks`, `contains` | the scope, groups, regions | none: made on each call | each call | O(tracks × depth); small with no scope | kernel | none |
| Parts of the rest of the song | `scope.tl` `held`, `gens` | the tracks outside a scope | edit counter for each track (`gens`), with members | an edit of a track inside the part | a render of the part | render thread | the files rendered |
| LSP document | `lsp/document.tl` `key_of`, `build` | the clip, the clips that overlap it, tempo, meter, the key at its start | a 32-bit hash of a string, made on each call | each call | 10 to 26 ms for each call: `clip_list` of every track, two times | kernel | none in paw; the server keeps by the hash |
| Search (`:vimgrep`) | `grep.tl` `records`, `reader` | every text in the project | none: all records are made for each search | each search | 37 to 91 ms for each search | kernel (the reader in slices) | none |
| Query | `query.tl` | the project tree | a `Cache` that lives for one query only | each query | 81 to 196 ms for `note[pitch>=c6]` | kernel | none |
| Piano roll context | `roll_clips.lua` `context` | the notes of the other clips around the active clip | global `edits` count, a generation, ids, options, span, scope | any edit anywhere | part of the 7.5 ms that a roll frame costs more after an edit | kernel | one list, `roll_context_max` notes |
| Arrange previews | `views/arrange.lua` `previews`, `rolls`, `waves`, `chains` | a clip's notes or peaks, a track's devices | per clip by its fields; mini rolls by stamp, length, loop, size; waves by id and width | `changed` clears `previews` and `waves`; `device.*` clears `chains` | one mini roll or one peaks call for each clip on screen | kernel | `KEEP` = 4 096 each |
| GUI state | `frontend.tl` `M.state`, `kept` | the transport, tracks, clips, devices, the modes | `revision`, `ui_redraws`, seat, mode, pending keys | any change | 12 to 45 ms for each call after a change | kernel | one for each seat |
| GUI clip pictures | `frontend.tl` `content_key`, `preview`; `paw-gui` textures (`window_cache`) | a clip's notes or its audio fields | the clip's note stamp, controller stamp, length and repeats, or its audio fields | a new key | one preview of the clip | kernel; the window draws | the window's cache |
| Take rows | `frontend.tl` `take_rows` | the takes of a clip | a string of the take's fields | a new key | one take preview | kernel | none |
| Notation layout | `extensions/notation` `init.lua` `make_layout`, `self.cache` | the score of the clip, options, the track's meta | a string of the score and options | a new string | about 5 ms more for a frame after an edit (part 3) | kernel | one for each view |
| Notation score of parts | `notation/parts.lua` `score_cache` | the tracks and clips of the parts | `edits` and `undo_current`, then a stamp string | any edit; a different stamp | the layout of the parts | kernel | one |
| Notation measures | `notation/midi.lua` `written_memo` | one measure's transcription and context | a string of the measure's content | a new key | one measure | kernel | 4 000 entries, then cleared |
| Notation engraved staves | `notation/engrave.lua` `E.staff` | a staff of a measure | a signature string; `used` generation | swept past 400 entries, older than two generations | one staff | kernel | about 400 entries |
| Help index | `help.tl` `parsed` | the help pages | the page's text | the text changes | the parse of a page (13 to 69 ms of slices, TASK-114) | kernel, at idle | the pages |
| Status line pieces | `statusline.tl` `cached` | each component's output | the component's `mark` | a new mark | one component | kernel | weak keys |
| Completion items | `complete.tl` `shown`, requests | the clip under the cursor | the clip's `stamp` | a different stamp | one request | kernel | one |
| Text buffers of views | `textbuf.tl` `seen` | the project | `edits` count | any edit | the text of the view | kernel | one for each buffer |
| Diagnostics | `diagnostic.tl` `revision` | the diagnostics | a counter | each change | not measured | kernel | none |
| Pictures of pixels | `canvas.tl` `image` | an extension's bytes | content key | least recently used | as the extension | kernel | 256 MB |
| Articulation maps | `extensions/articulations` `maps.lua` | a map file | the file's text | a different text; `forget` | the parse of the file | kernel | the files |
| utau pitch shapes | `extensions/utau` `strips.lua` | the notes of one strip | the note's place, for one call | the call ends | one shape | kernel | none |

Three findings from the inventory:

1. **Content keys and counters are mixed.** A counter (`edits`, `gens`, `revision`) changes
   on undo and on redo, also when the content comes back as it was. A content stamp
   gives a hit on undo, redo and on copies. Seven caches use counters.
2. **Four consumers have no key.** Search, query, the LSP document key and scope
   resolution make their value again on each call. Search and query are the most costly
   things a user can ask for on the bench project.
3. **The Rust side is in good shape.** Each Rust cache already has a content key or an
   identity key that holds its source, and the bake scheduler already has priorities.
   The Rust side needs two small changes only (4.3 and 4.7).

## 3. Measurements: the cost of one edit, by consumer

### 3.1 Method

- Scripts (not in the repository) open the bench project, read the chords once,
  draw one frame, then repeat one edit 9 or 15 times. Each round times each consumer
  with `CLOCK_THREAD_CPUTIME_ID`: processor time of the kernel thread.
- Edits: **note** (the pitch of one note in a 25-note clip on track 3, then
  `undo_checkpoint`), **mute** (track 20, whose clips span the song), **undo** (of a note
  edit), **tempo** (120 to 121 BPM at beat 0).
- The consumers, in the order the kernel runs them: the API call (the model, the undo
  step and, for `clip_set_notes`, the sync), the delivery of the events (`paw.flush`:
  `events_take` runs the deferred sync and makes the events, then the Lua handlers),
  the chord reading to its end (in use it runs in slices), one frame of 187 by 56, then
  consumers that run on request: the GUI state, the LSP document of the edited clip,
  all search records, one query.
- Each value is the median of the rounds, with the smallest and largest value. The runs
  use the lock of `bench/profile/run.sh` and cores 16 to 23. All values were measured
  under external load (load average in each table). Two runs at load 31 to 41 differ by
  a factor of about 2. Compare values in one row, not across rows.

### 3.2 The edit and its events

Load average 8 to 16, 15 rounds, two runs:

| Edit | API call | Events, all | of which `events_take` (the sync) | of which Lua handlers |
| ---: | ---: | ---: | ---: | ---: |
| note | 1.0 ms (0.6 to 2.9) | 0.4 to 0.5 ms | 0.15 ms | 0.25 to 0.28 ms |
| mute | 0.05 to 0.09 ms | 0.9 to 2.1 ms | 0.7 to 1.7 ms | 0.17 to 0.37 ms |
| undo | 0.03 ms | 1.8 to 1.9 ms | 1.6 ms | 0.23 to 0.24 ms |
| tempo | 0.06 to 0.07 ms | 1.2 to 1.9 ms | 1.1 to 1.7 ms | 0.12 to 0.14 ms |

No single handler takes more than 0.1 ms. The largest are `scope.tl:969`
(`track.changed`, 0.04 to 0.09 ms), `address.tl:886` (`changed`) and `ui.tl:1692`.
So TASK-116's "an event handler" over 5 ms is the sum, at a high load, not one handler.

### 3.3 The chord reading after one edit

Load average 8 to 41, 9 or 15 rounds:

| Edit | Load 8 to 16 | Load 24 to 29 | Load 33 to 41 |
| ---: | ---: | ---: | ---: |
| note | 7.1 to 7.4 ms | 7.0 to 7.7 ms | 8.7 to 15.9 ms |
| mute | 28.4 to 45.7 ms | 30.2 to 34.6 ms | 30.9 to 72.4 ms |
| undo | 7.1 to 7.2 ms | 6.4 to 7.2 ms | 8.5 to 15.6 ms |
| tempo | 0.06 ms | 0.0 to 0.1 ms | 0.1 to 0.3 ms |

The parts of the reading (load 38, one run):

| Part | note | mute |
| --- | ---: | ---: |
| Look at the tracks (`clip_list`, `clip_notes`, `track_get`) | 0.1 ms | 0.0 ms |
| Windows read again (`read.window`) | 1.5 ms | 21.0 ms (68 %) |
| Bars read again (`read.bar_weights`) | 0.3 ms | 2.4 ms |
| The chords decoded (`read.decode`, all windows) | 1.7 ms | 1.5 ms |
| The key path (`read.key_path`) | 0.4 ms | 0.4 ms |
| The rest | 4.7 ms (54 %) | 5.6 ms |

The samples of `jit.profile` (20 rounds) put the rest of a note edit in the list of all
50 000 notes in order: the filter of the notes that went (`song.tl:317`, 15 % of the
samples) and the merges (`song.tl:92` to `118`). After a mute, `weigh` (the scan of the
notes of each window, `read.tl:188` to `343`) has about 35 % of the samples and `fit`
(the score of each chord, `read.tl:355` to `373`) about 9 %.

So:

- After a note edit, half of the reading is the list of all notes kept in order. It
  grows with the song, not with the edit.
- After a mute, two thirds of the reading weighs again the notes of the 63 tracks that
  did not change. TASK-88 left this case to the design.
- After a tempo change at the same meter, paw reads nothing again. That is correct: the
  reading is in beats.

The reading keeps 15.1 MB of Lua heap for the 50 000 notes, and the list of
`paw.harmony.notes()` 0.5 MB more.

### 3.4 Views

Frame only, nothing else runs between two frames, load average 24 to 29, 15 rounds, two runs:

| View | Frame after nothing | after a move (`j`/`k`) | after a note edit |
| --- | ---: | ---: | ---: |
| Arrange | 4.4 to 4.6 ms | 3.6 to 4.3 ms | 4.4 to 4.7 ms |
| Piano roll (the edited clip) | not measured | 4.9 to 5.1 ms | 12.5 to 12.6 ms |
| Notation (the edited clip) | not measured | not measured | 9.4 to 10.4 ms |

- The arrange view costs the same after an edit as after a move: TASK-88's kept rows
  work.
- The piano roll costs 7.5 ms more after an edit than after a move. Its context notes
  use the global `edits` count as their key, so any edit makes them again.
- When other consumers run between two frames (the GUI state, search, a query), an
  arrange frame costs 9 to 17 ms in place of 4.5 ms. A cause is not known. The ticket
  for the GUI state measures it again (D4 in the migration plan).

### 3.5 Consumers on request

The consumers below have no key, or a key that any change breaks. They cost the same
after any edit and after no edit:

| Consumer | Load 31 to 38 | Load 37 to 41 |
| --- | ---: | ---: |
| GUI state (`frontend.state`), for each change while a window is open | 12.3 to 15.3 ms | 32.4 to 41.3 ms |
| LSP document (`key_of` and `build` of one clip) | 10.6 to 13.5 ms | 23.6 to 25.9 ms |
| Search: all records (`paw.grep.records`) | 37.2 to 43.7 ms | 88.1 to 91.5 ms |
| Query `note[pitch>=c6]` | 81.3 to 101.0 ms | 179.1 to 195.6 ms |

### 3.6 Not measured

- Bakes (stretch, peaks, freeze): a MIDI edit does not touch them, and the bench project
  has no audio clips. Their keys are content keys already.
- Scenes: they need a frontend that asks for scenes. TASK-88 makes the scene work only
  while a scene is drawn.

### 3.7 The cost of one edit, in short

One note edit on the bench project costs about 1.5 ms of kernel and sync work, then
7 ms of chord reading in slices. With the piano roll open, the frame costs 7.5 ms
more. With the window open, the GUI state costs 12 to 40 ms more. A mute costs 30 to
45 ms of reading. The derived data costs 5 to 30 times more than the edit.

## 4. The design

### 4.1 What the graph does

For each derived value, the graph knows what it was made from. An edit marks its
sources dirty. The graph then makes again only the values that read a dirty source.
It does the work in slices, the values that the user hears or sees first. A consumer
reads the value as it stands, and draws again when the value changes.

The rules:

1. **Keys are content stamps.** A key is made from the stamps of what the node read.
   The same content gives the same key: an undo, a redo and a copy hit the cache.
2. **Early cutoff.** A node made again whose value equals the old value does not mark its
   dependents dirty.
3. **Nothing over the budget on a key.** The graph does its work in `paw.slices`. A
   read with `latest` makes the value at once, for a command that waits and for tests.
4. **A view never waits.** A view reads the value as it stands. When the node's
   revision goes up, the graph emits `derived.changed` and the view draws again.
5. **Memory has a limit.** Each kind of node has a limit. The graph drops the values that
   no live key holds first, then the values used least recently.

### 4.2 Where the graph lives: both sides, with one split

| Side | What it holds | Why |
| --- | --- | --- |
| Rust | The stamps of the sources. The derived data that goes to the engine or to files: compiled events, decoded audio, peaks, bakes, file checks, folder layouts, undo blobs. | These values need `Arc` identity and other threads. They already have content keys. |
| Lua (Teal) | The derived data that Lua makes and reads: the chord reading, the region tree, the LSP document, the roll context, the notation layouts, the search index, the GUI state, the arrange previews. | Lua makes these values. Extensions add their own (rule 5 of the agent rules, `AGENTS.md`). |

Rust gets no generic graph type. Each Rust cache has one implementation with its own
key, and `bake::Scheduler<K>` is already the runner for work on threads. A
`trait Node` with one implementation for each cache is the anti-pattern
`anti-over-abstraction` of the rust-skills skill. The Rust side changes in two places
only: more stamps for Lua (4.3) and the visible ranges for the bake scheduler (4.7).

The Lua side is one new Teal module, `paw.derived` (`runtime/lua/paw/derived.tl`). It
holds the nodes, their keys and states, the reverse index from sources to nodes, one
slices job, and the accounts of memory.

Rejected:

- **One graph in Rust (for example the `salsa` crate).** salsa makes Rust functions
  incremental. The consumers here are Lua functions. salsa would keep a second copy of
  the model, and an extension could not add a node.
- **One graph in Lua for all.** The compiled events, the bakes and the decoded audio
  must stay in Rust: the engine and the worker threads read them.
- **A second Lua state on a worker thread.** Tables do not cross Lua states. A copy of
  50 000 notes costs more than the reading of a few windows. Pure work can move to Rust
  later (4.11).

### 4.3 Sources and their stamps

The kernel gives a stamp for each source. Lua never hashes notes itself.

| Source | Stamp today | Change |
| --- | --- | --- |
| A clip's notes | `clip.stamp` (53 bits) | none |
| A clip's controllers | `clip.control_stamp` | none |
| A clip's place | its fields `start`, `length`, `loop*`, `muted`, `track` | none: Lua makes the place key from the fields |
| A track | none: `track.changed` comes for any field | `track.changed` carries `fields`: the names of the fields that changed (`{ "mute" }`). The chord reading then ignores a fader, a pan or a name. |
| The tempo map and the meter | `Arc` identity in Rust only | `project_get("tempo_stamp")`: a hash of the tempo and meter points. A content hash, so that an undo gives the old stamp back. |
| The markers and regions | none | `project_get("markers_stamp")`: a hash of the markers. |
| An option | the event `option.changed` | none |
| The whole project | `project_get("edits")` | none: the coarse key for a node that reads much |

The clip events (`clip.added`, `clip.changed`, `clip.removed`) carry `stamp` too. A
handler can then stop early without a call to `clip_get`. Each change is generic: no
change names a consumer (rule 5).

### 4.4 Node types

All nodes are one Teal record with a spec. The spec says how the graph makes the node:

| Type | How it is made | Examples |
| --- | --- | --- |
| **memo** | One call, at most about 1 ms, when it is read and its key changed. | region tree, LSP document key, a mini roll, the roll context |
| **sliced** | A step function `step(ms)` that keeps its place, through the graph's slices job. | the chords of the song (decode, key path), the help index, the search index |
| **family** | One node for each item key. The graph makes the dirty items, in slices, the most wanted first. | the notes of each clip content, each track and window of the chord reading, the search records of each clip |
| **join** | Combines a family (a sum, a lowest value, a list). It is dirty when a member's value changed. | the weights of each song window, the bar weights, the search index |

A bake is not a node type of `paw.derived`. A bake's value lives in Rust. Lua sees its
status and progress through `paw.api` (`bake.progress`), as today.

The spec in Teal, as a sketch:

```teal
local record Spec<K, V>
   name: string                                  -- "harmony.track_window"
   kind: Kind                                    -- "memo" | "sliced" | "family" | "join"
   make: function(ctx: Ctx, key: K): V           -- memo, family, join
   step: function(ctx: Ctx, key: K, ms: number): V, boolean  -- sliced: the value, done
   span: function(key: K): number, number        -- its time, for its priority (optional)
   bytes: function(v: V): integer                -- its memory, estimated (optional)
   same: function(a: V, b: V): boolean           -- early cutoff on the value (optional)
   limit: integer                                -- bytes of this kind (default 4 MB)
end

-- What a node reads, through the graph, so that the graph records it:
local record Ctx
   clip: function(Ctx, id: integer): types.Clip   -- records the clip's stamp and place
   notes: function(Ctx, id: integer): {types.Note}
   track: function(Ctx, id: integer, fields: {string}): types.Track  -- records only those fields
   tempo: function(Ctx): integer                  -- records the tempo stamp
   markers: function(Ctx): integer
   option: function(Ctx, name: string): any       -- the escape: an option's value
   get: function<K2, V2>(Ctx, node: Node<K2, V2>, key: K2): V2  -- another node
end

-- What a consumer has:
local record Node<K, V>
   get: function(Node<K, V>, key: K, latest?: boolean): V, boolean  -- the value, fresh
   revision: function(Node<K, V>): integer        -- goes up when any value changes
   stats: function(Node<K, V>): Stats             -- made, hits, bytes, slices
end
```

`option` returns `any` only in the sketch. The real API has one typed function for each
option type, or reads `paw.opt` through the typed option record (the teal skill: no
`any` where a value has a shape).

The graph records the dependencies when the node runs (`ctx:clip(id)`). They are exact,
also when a node reads different clips after an edit. The graph keeps a reverse index:
source to nodes. An edit marks only the nodes in that index.

### 4.5 Keys

- A node's key is the list of (source, stamp) pairs it read, and the keys of the nodes
  it read. The graph compares the list again when a source is dirty. When all stamps
  are the same, the node stays fresh (early cutoff on the key).
- A family's item key is **content, not identity**: for the notes of a clip, the
  clip's `stamp`, `length` and loop, not its id and not its start. Two clips with the
  same notes share one node. `Compiled` uses the same key in Rust (TASK-7.2).
- A node that depends on the place reads the content node and its place:
  (content key, start). For the chord reading, a track window node reads the content
  nodes of the clips over the window, each with its start.
- Stamps are 53-bit hashes. Two different contents with one stamp have a chance of
  about 2⁻⁵³. That is acceptable for derived data, which paw can always make again. A
  saved file never uses these stamps.

### 4.6 Invalidation: events, dirty sources, early cutoff

1. The kernel emits its events at the end of a turn (`K.settle`). The graph listens to
   `clip.*`, `track.*`, `lane.*`, `device.*`, `project.changed`, `option.changed`,
   changes of the markers, and `project.loaded`.
2. Each event marks its sources dirty: `clip.changed {id, track, stamp}` marks the clip;
   `track.changed {id, fields}` marks those fields of the track; `project.changed`
   reads `tempo_stamp` and `markers_stamp` and marks what changed. `project.loaded`
   drops every node.
3. The graph finds the nodes that read a dirty source (the reverse index) and marks them
   "maybe stale". It does no work in the handler: a handler costs a table look-up.
4. The slices job takes the stale nodes in priority order (4.7). For each one, it
   compares the key first. A node whose key did not change is fresh again. The graph
   makes again a node whose key changed. When its new value equals the old one
   (`same`), its dependents stay fresh.
5. When a node's value changes, its revision goes up. At the end of a slice, the graph
   emits `derived.changed { names }` once for the node kinds whose revision went up.
   The views draw again. The harmony node still emits `harmony.changed`.

The edit counter `edits` stays as the coarse key for code that does not use the graph
yet.

### 4.7 Slices and priorities

The graph has one job in `paw.slices`: `derived`. Each slice runs for at most
`paw.opt.budget_ms` or 4 ms. The job starts 30 ms after the first dirty mark (the
chord reading's `after = 30` today), so that a held key that edits many times makes
the values once.

The priorities are those of the bake scheduler (the scheduler of the media design), in
the same order:

| Priority | Which nodes | Where the range comes from |
| --- | --- | --- |
| Playing | A node whose `span` overlaps the next 10 s after the playhead while the song plays, or the 10 s after the cursor when it is stopped | the transport, as `bake_wants` reads it in `session/stretching.rs` |
| Visible | A node whose `span` overlaps the time range of a window on screen, and whose track is shown | the views: each view tells its range when it draws |
| Background | The rest | not needed |

Lua has no Export priority. An export reads with `latest`.

The visible ranges are new. Today the bake scheduler never gets `Priority::Visible`:
`bake_wants` gives `Playing` or `Background` only. So:

- Each view calls `paw.derived.visible(window, from, to, tracks)` when it draws. The
  call keeps one small table for each window.
- The graph sends the union of the ranges to the kernel at the end of a turn when it
  changed (`api.view_ranges_set(list)`). `bake_wants` then gives `Visible` to a bake in
  those ranges. One input feeds both schedulers.

A node with no `span` is Background, or Visible when a view reads it with `get` while
it is stale (the graph raises it).

### 4.8 Reading the value as it stands

- `node:get(key)` returns the value and `true` when it is fresh. When it is stale, it
  returns the old value and `false`, and the node goes up to Visible priority. When there
  is no old value, it returns nil and `false`. The view draws what it has.
- `node:get(key, true)` makes the value now, in one piece, for a command that waits
  (an export, `:chords`), for the LSP server's request, and for tests.
  `paw.harmony.key(beat, latest)` has this form today.
- A view that keeps its drawing (the arrange rows, the GUI pictures) adds the node's
  `revision` to its own key.
- A slow node does not show a mark in a view. The status line can show the job
  `derived` as it shows `harmony` today (owner question Q1).

### 4.9 Memory limits

- Each node kind has a limit in bytes (`limit` in the spec). `bytes(v)` estimates a
  value. A kind with no `bytes` counts entries, with a limit of entries.
- After each slice, a kind over its limit drops values: first the values that no key of
  a live consumer holds (as `Compiled::sweep` keeps only the lists that a clip holds),
  then the values used least recently.
- A dropped value is not an error. A consumer that reads it gets nil and the node is
  stale. The graph makes it again in the background.
- First limits, from the measurements: the chord reading 20 MB (15 MB today on the
  bench project), notation measures 4 000 entries (today's), arrange mini rolls 4 096
  entries (today's), the search index 8 MB, the GUI state one entry for each track.
- `:checkhealth derived` lists each kind: values, bytes, limit, hits, misses, values made,
  slices and the longest slice. The tests read the same numbers (`node:stats()`).

### 4.10 Copies (the N0 results of the nest design)

The N0 spike of the nest design found that an edit inside a nest compiled every copy
again. TASK-7.2 fixed it in Rust: copies keep a stable identity across syncs, the
compiled events use the runs that they share as their key (`Arc` identity, held by the
entry), and each engine part plays one shared `Arc<[MidiEv]>` from its own start
(`Part::with_offset`). An edit with 100 copies now costs 2.3 times a plain edit, not 90
to 350 times.

The graph keys copies the same way on the Lua side:

1. **Content nodes are shared.** The notes node of a clip uses the clip's content
   (`stamp`, `length`, loop) as its key. All copies of a nest clip, of a linked clip or
   a plain duplicate have one notes node, in clip beats. An edit inside a nest makes one
   notes node again, not one for each copy.
2. **Place nodes read the content with an offset.** A node that depends on where the music
   sounds (a track window of the chord reading) reads each content node with the
   copy's start. It does not copy the notes.
3. **The work for each copy is small.** For the chord reading, an edit inside a nest
   with 100 copies remakes one notes node, then the track windows that each copy
   covers. A window reads the notes of the content node with an offset. It does not scan
   the song's notes. When a copy's start is a multiple of the window step, the copy's
   window parts are the content's parts shifted, and the graph shares them too.
4. **The nest's own content.** A nest instance (TASK-7.4) is a source with its own stamp:
   the nest's content hash and the instance's place. Views that show a nest read
   through the instance, so they get the shared nodes.

### 4.11 The chord reading as a graph (the first consumer)

Today `harmony/song.tl` keeps one sorted list of all notes and one list of windows.
In the graph:

| Node | Type | Key | Value |
| --- | --- | --- | --- |
| `harmony.clip` | family | clip content (`stamp`, length, loop) | the notes that sound, in clip beats, sorted |
| `harmony.track` | memo | the track's `mute`, its kind (drums), the place and content key of each MIDI clip | the clips of the track that sound, with their starts |
| `harmony.track_window` | family | (track, window) and the `harmony.clip` keys over the window, with their starts | the twelve weights, the total, and the lowest pitch over time in the window (a few pieces: from, to, pitch) |
| `harmony.window` | join | window | the sum of the weights of the tracks, the bass from the lowest of the tracks' lowest pitches for each piece of time, then the scores (`fit`) |
| `harmony.track_bar`, `harmony.bar` | family, join | (track, bar) | the pitch-class weights of the bar; a sum |
| `harmony.chords` | sliced | the window revisions, the bar length | `read.decode` over all windows |
| `harmony.keys` | sliced | chords, bars | `read.key_path` |

- **A note edit** makes one `harmony.clip` node, the track windows over that clip, their
  joins, then the decode and the key path. The sorted list of all 50 000 notes goes. It
  was half of the reading.
- **A mute** changes `harmony.track` of one track. Its track windows go out of the
  joins. The joins sum the 63 other tracks' parts again: 12 numbers and a few pieces of
  bass for each track and window. No note is weighed again. The graph makes the scores
  (`fit`, about 9 % of the reading) again for each window.
- **The bass is exact.** The weights add up across tracks. The bass does not: it is the
  lowest pitch over time. Each track window keeps its lowest pitch over time as a few
  pieces. The join takes the lowest of the tracks for each piece, then makes the same
  `Bass` record (`held`, `lowest`, `lasts`) that `weigh` makes. The test compares the
  reading with a reading of all notes at once, bit for bit, as the tests of HARMONY-FAST
  do.
- **A window weighed with its beat** (one pitch alone) is a join over the track windows
  of the beat. Its key holds both windows.
- **Memory:** 64 tracks × 248 windows × about 25 numbers is 400 000 numbers, 3 to 4 MB
  in flat arrays. The sorted list goes. The limit is 20 MB.
- **Later (not in D1):** the decode is a walk over all windows (1.5 to 1.7 ms). It can
  keep its forward state for each window, and start from the first changed window minus
  a margin. Measure first after D1.

### 4.12 What stays as it is

- The Rust caches of the Rust inventory (2.1) keep their types and keys. `Compiled`,
  `AudioCache`, `Renders`, the bake store, `Sources`, `FileCheck`, `TrackCache` and the
  undo file are each the one implementation that they need.
- The sync stays the only place that tells the engine (`sync/mod.rs`).
- `paw.slices` stays as it is. The graph is one job in it. Other jobs (`pick`, `help`)
  stay jobs.
- The arrange view's kept rows (TASK-88) stay. They already cost the same after an edit as
  after a move.

## 5. Migration plan

One consumer for each ticket, in this order. Each ticket goes into m-3 after the owner
approves the design. "Number" is the number to meet, measured under external load,
with the spread, on the bench project, against `main` at the time.

| # | Ticket | Test | Number to meet |
| --- | --- | --- | --- |
| D1 | **The graph, and the chord reading on it (the first consumer).** `paw.derived` (`derived.tl`): node types, keys, the reverse index, the `derived` slices job, priorities, `derived.changed`, `:checkhealth derived`. Kernel: `fields` in `track.changed`, `stamp` in clip events, `tempo_stamp`. `harmony/song.tl` becomes the nodes of 4.11. | (a) After 300 random note sets with 6 random edits each, the reading equals a reading of all notes at once (the HARMONY-FAST check). (b) A mute of a track that spans the song makes no `harmony.track_window` node of another track (`stats().made`). (c) A change of a track's volume reads nothing. (d) `tests/harmony.lua` passes unchanged. | Reading after a mute: 10 ms or less of processor time (28 to 46 ms today, load 8 to 16), and a third of today's instructions or less (258 M a mute and unmute pair, TASK-88). Reading after a note edit: 3 ms or less (7.1 to 7.4 ms today). Heap of the reading: 20 MB or less (15.1 MB today). |
| D2 | **The piano roll context.** `roll_clips.context` becomes a memo node with the context clips' content and place as its key, not `edits`. Work with TASK-113. | With the roll open, an edit of the active clip does not make the context again (`stats().made` stays). Real keys: `x` on a note in the roll. | Roll frame after a note edit: 1.5 times a roll frame after `j` or less (12.5 ms against 5 ms today). |
| D3 | **The search index.** The records of `paw.grep` and the fields that `paw.query` reads become a family with clip content (and track, marker, device fields) as the key, made in background slices; `:vimgrep` and the query read the join. | After an edit of one clip, a second `:vimgrep` makes the records of that clip only (`stats().made` = 1). The search tests pass unchanged. | Second `:vimgrep /pizz/` after one edit: 10 ms or less (37 to 91 ms today). `note[pitch>=c6]`: 20 ms or less (81 to 196 ms today). |
| D4 | **The GUI state.** `frontend.state` keeps an entry for each track as a node with the track's fields and its clips' keys as the key; the transport and modes stay as they are. Find why an arrange frame after `frontend.state` costs 9 to 17 ms. | After a note edit, `frontend.state` makes one track entry (`stats().made` = 1). `cargo test --release -p paw-gui` passes. | `frontend.state` after a note edit: 3 ms or less (12 to 41 ms today). |
| D5 | **The LSP document.** `lsp/document.tl` `key_of` becomes a memo node: the clip's stamp and place, the clips that overlap it (from the place index of `harmony.track`, not `clip_list` of every track), `tempo_stamp`, the key node. | An edit of a clip that does not overlap the document leaves its key as it was, with no `clip_list` call (an API call counter). The midilsp tests pass. | `key_of` after an edit elsewhere: 0.5 ms or less (10 to 26 ms today with `build`). |
| D6 | **Notation (the first extension consumer).** The measure memo, the layout cache and the score of parts move to `paw.derived` nodes; the first layout of a large clip runs in slices. The API becomes public here (owner question Q2). | The notation tests pass unchanged. An edit of one measure makes one measure (`M.stats.measures` + 1). | Notation frame after a note edit: 1.5 times a frame after a move or less (9.4 to 10.4 ms today). |
| D7 | **Visible ranges for the bakes.** Views tell their ranges (`paw.derived.visible`); the kernel gets the union (`api.view_ranges_set`); `bake_wants` gives `Priority::Visible`. | Rust test: with all workers busy on Background bakes, a bake in a visible range starts first. Lua test: a view drawn tells its range. | With 20 Background stretch bakes waiting, the first visible bake starts within `SETTLE` (150 ms) and one poll. |
| D8 | **The region tree and scope resolution.** `markers.tl` `tree()` becomes a memo with `markers_stamp` as its key; `scope.tl` `tracks()` a memo with the scope, the groups and `markers_stamp` as its key. | A note edit does not build the tree again (`stats().made` stays). `tests/markers.lua` and the scope tests pass. | `tree()` with 500 regions after a note edit: 0.05 ms or less. |
| D9 | **Frozen tracks: up to date or stale.** After the provenance of the kept bakes in the media design (`input_key`), the freeze node's key is the track's content key (its clips, devices, the tracks that feed it). Depends on the media tickets. | An edit inside a frozen track marks it stale with the reason ("Drums changed since: devices"), and `K` says so. An undo makes it up to date again. | The check costs 0.1 ms or less for each edit (one key compare). |

The arrange previews (`views/arrange.lua`) do not get a ticket: the kept rows of
TASK-88 already make an edit cost the same as a move. They move to the graph with D4,
when the GUI pictures share their keys, if the measurement of D4 shows a gain.

## 6. Owner questions

Q1. **Does the user see when derived data is not up to date?** For example, the chord
row draws the old chords for 30 ms to 1 s after an edit.
Recommendation: no mark in the views. The status line shows the job `derived` only
when it runs for more than 1 s, as `chords 40 %`. `K` on a chord says "reading" while
its window is stale.

Q2. **When does `paw.derived` become a public API for extensions?**
Recommendation: internal in D1 to D5 (no page in the reference). Public in D6, with
notation as the first extension that uses it, a Teal contract in `paw.contracts`, a
reference page and a how-to guide. The API can still change until then.

Q3. **Is there a user option for the memory of derived data?**
Recommendation: no option. Fixed limits for each kind (4.9), shown by
`:checkhealth derived`. An option comes when a user reaches a limit.

## 7. Sources

- `runtime/lua/paw/harmony.tl`, `harmony/song.tl`, `harmony/read.tl`, `slices.tl`,
  `events.tl`, `init.lua` (`settle`), `markers.tl`, `scope.tl`, `lsp/document.tl`,
  `grep.tl`, `query.tl`, `roll_clips.lua`, `views/arrange.lua`, `frontend.tl`,
  `freeze.lua`, `help.tl`, `statusline.tl`, `complete.tl`, `textbuf.tl`, `canvas.tl`.
- `extensions/notation` (`init.lua`, `midi.lua`, `parts.lua`, `engrave.lua`),
  `extensions/articulations`, `extensions/utau`.
- `crates/paw-core/src/sync` (`mod.rs`, `clips.rs`, `audio.rs`, `items.rs`),
  `model/notes.rs`, `bake` (`scheduler.rs`, `store.rs`), `stretched.rs`,
  `session/stretching.rs` (`bake_wants`), `peaks.rs`, `freeze.rs`, `scene.rs`,
  `session/file_check.rs`, `session/folder.rs`, `media/sources.rs`.
- The media design (`backlog/docs/designs/media.md`): keys, the cache and kept bakes,
  bakers and the scheduler. The nest design (`nest.md`): the N0 results. The
  architecture review (`architecture-review.md`): F1 and the note on TASK-77.
- The notes of TASK-14, TASK-79, TASK-88, TASK-7.2, TASK-16 and TASK-82.1; TASK-113 to
  TASK-116.
- The bench results (`bench/RESULTS.md`): the profile of 2026-11-21 and the parts of
  2026-11-22.
- The measurement scripts are in the agent's scratchpad, not in the repository:
  `derived/edit_cost.lua`, `frame_cost.lua`, `flush_cost.lua`, `hprof.lua`, `heap.lua`.

## 8. Owner decisions (2026-11-22)

The owner approved the design and the recommended answers: Q1 no mark in the views,
Q2 `paw.derived` public from D6, Q3 no user option for memory. The tickets D1 to D9 are
TASK-77.1 to TASK-77.9 in m-3.
