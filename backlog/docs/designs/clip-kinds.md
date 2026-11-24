# Custom clip kinds: the design

Author: CLIPKINDS (design agent), 2026-11-21. No file of the repository changed.
Status: a proposal. The owner confirms before anyone builds it.

## 0. The short version

- A clip gets a third content: `ClipContent::Custom(Box<CustomContent>)`, next to `Midi` and
  `Audio`. MIDI and audio stay built in (section 3.6 tells why).
- A custom clip holds four things. The kind owns **data**. Files are **media**. What it makes
  you hear is **sound**: a built-in MIDI or audio content that the kind compiled. What it makes
  happen is **signals**: timed messages to the kernel or to an OSC port.
- Sound and signals are saved with the project. So a project **plays and performs without the
  extension**: its sound plays, its OSC signals go out. Only its Lua actions and its look need
  the extension.
- The engine gets one new generic thing: a **signal stream**. Signals are `Copy` records in the
  clip parts. The audio thread emits them at their frame into one `rtrb` ring, the same way it
  sends MIDI to ports today. A small thread reads the ring. It sends OSC at the heard time and
  wakes the kernel for Lua actions. Nothing allocates on the audio thread.
- Extensions define kinds in Teal: `paw.clip_kinds.define(name, spec: ClipKind<D>)`. The
  default edits (move, trim, split, slip, loop, copy, undo, save) are generic offset math on the
  clip. A kind adds hooks only where it needs them.
- Rule 4 changes from "MIDI is the truth" to "**the clip's owner is the truth; what it plays is
  saved**". One owner per piece of data stays. "Only MIDI and audio exist" goes.

Words used here: a **kind** is what an extension defines (`video`, `lyrics`). A **signal** is a
timed message that is not sound. (Not "cue": `Track.cues` is already the launcher's clips.)

---

## 1. Brainstorm: clips a user might want

Each entry: what it holds, what it does at time t, what it shows, what it needs from the kernel.
**N** marks a kind that is not about making sound. 14 kinds, 9 of them N.

1. **Video.** Holds a video file (media), an offset into it, maybe a proxy and a strip of
   thumbnails (derived media). At t: shows the frame of t in a monitor view. Its sound is the
   video's audio, extracted to a sound file. Shows a film strip in the arrange view. Needs:
   media, derived media made by a helper (ffmpeg), sound as audio, a picture primitive for raw
   frames, timeline in seconds (picture follows time, not beats), export (mux to mp4).
2. **Lyrics, subtitles, karaoke (N).** Holds lines of text with times (or syllables bound to
   the notes of a vocal clip). At t: the current line is shown big in a performer view, the sung
   word is lit. Optionally a signal to OBS for a caption. Shows the words in the clip. Needs:
   text data (an `.lrc` file reads well in git), a view that follows the playhead, export (SRT,
   LRC, WebVTT), a link to another clip (the vocal).
3. **Light cues: DMX through OSC (N).** Holds a list of cues: time, name, the values of
   channels or OSC messages, a fade time. At t: sends the cue's OSC messages to the lighting
   program (QLC+, OLA), on time with the sound. A jump into the middle of the song sends the
   state that is in effect there (chase). Shows cue names as marks. Needs: signals to OSC ports,
   heard-time alignment, chase by latch key, an editor list view, export (a cue list).
4. **Script and action clips (N).** Holds a few Ex lines (`:stop`, `:launch 3`, `:view lyrics`,
   `:record`). At t: the kernel runs them. Uses: stop at the end of the song, punch in at a bar,
   switch a view for a performer, start a launcher scene, tell OBS to change scene through a
   helper. Shows its first line. Needs: signals to the kernel, Lua at a beat with a stated
   latency, a write guard (an action at play does not edit the project), trust for code.
5. **Remote control of another program (N).** OBS scene changes, REAPER through OSC, a PTZ
   camera preset, TouchDesigner. Holds messages and times. At t: sends them. This is kind 3 with
   other addresses (OSC) or kind 4 with a helper (websocket). It needs nothing new beyond 3 and
   4, and it is the proof that signals must be generic, not "lighting".
6. **Comment and review (N).** Holds text, an author, a state (open, done), a region. At t:
   nothing (or a soft mark in the status line while it plays). Shows a colored band and the first
   words. A quickfix list of open comments. Needs: data only, look, export (a review text). It is
   the simplest kind: the test that a kind with no sound and no signals is cheap.
7. **Generative clip.** Holds a rule: a TidalCycles pattern (the pattern extension today), a
   Euclidean rhythm, a Markov melody, a seed. At t: plays MIDI that the rule made. "Roll again
   each pass" makes new notes for each loop pass. Needs: sound as MIDI, a compile hook, a signal
   to the kernel at the end of each pass (to compile the next pass ahead).
8. **Analysis clip (N).** Holds what an analysis found over a region of an audio clip: tempo,
   beats, pitch curve, chords, loudness. At t: nothing. Shows a curve or labels. Has actions:
   "make a tempo map", "make notes". Is stale when its source changes. Needs: a link to another
   clip, derived data made by a helper, a picture primitive (a spectrogram), look.
9. **Performer cue clip: click, count, "Verse 2 in 4" (half N).** Holds a section name, a
   count, a voice. At t: a click or a spoken count to a separate output pair, a big countdown on
   a performer screen, an OSC signal to an in-ear mixer. Needs: sound as audio (rendered speech),
   look, signals to OSC, a frontend view that follows the playhead.
10. **Teaching and tutor clip (N).** Holds an instruction ("play the C major scale now"), the
    expected notes, a hint. At t: the text is shown. While it plays, the notes that the student
    plays are compared, and the clip shows the score after. Needs: look, signals to the kernel
    (start and end of the exercise), the MIDI input events that exist now.
11. **Sample-slice clip.** Holds one audio file and slice points. Each slice is a "note" that
    the user moves. At t: plays the slices at their places. Needs: sound as audio (rendered
    from the slices, or audio regions), media, an editor. It shows that sound must be computed
    from data.
12. **Text to speech or a sung voice.** Holds text and a voice. At t: plays speech. Needs: sound
    as audio, made by a helper process in the background (like utau), content-addressed files so
    that undo needs no new render.
13. **Picture and slideshow clip (N).** Holds images and times. At t: shows the image in the
    monitor view. Exports into the video. Needs: media, the picture primitive, timeline in
    seconds, export.
14. **Chord chart and section clip (N).** Holds chord symbols or a section name over a region.
    At t: nothing. The harmony LSP and other extensions read it. Exports a lead sheet. Needs:
    data, look, export. (The sections extension and `project.key` already cover parts of it, so
    it is the last in priority.)

The examples that are only about sound (7, 11, 12) and half sound (1, 9) matter too: they show
that "sound computed from data the kind owns" is the common case, not only video.

---

## 2. The capabilities they need

Rule: a capability goes into the design only when two kinds or more use it. The kinds are
numbered as in section 1.

| Capability | What | Used by | In? |
|---|---|---|---|
| **Data** | JSON owned by the kind, kept untouched without it | all | yes |
| **Text data** | the data as a text file of the kind's format (`.lrc`, Ex lines) | 2, 4, 6, 7 | yes |
| **Data schema version** | the kind's data has a version, and the kind migrates it | all | yes |
| **Media** | files that the clip uses, managed as audio files are | 1, 8, 11, 13 | yes |
| **Derived media** | files made from media by a helper, content-addressed | 1, 8, 9, 12 | yes |
| **Sound: MIDI** | the kind compiles data to notes and controllers | 7, 9 (click), 11 (as slice triggers) | yes |
| **Sound: audio** | the kind compiles data to a sound file | 1, 9, 11, 12 | yes |
| **Signals to the kernel** | timed Lua actions | 4, 7, 10, 2 (OBS) | yes |
| **Signals to OSC** | timed messages to another program, at the heard time | 3, 5, 9 | yes |
| **Chase** | on a jump, send the state that is in effect | 3, 5, 4 (optional), 1 | yes |
| **Lead time** | a signal goes early so that its effect lands on time | 4, 5 (OBS is slow), 7 (compile ahead) | yes |
| **Timeline in seconds** | the data follows time, not beats | 1, 13, 2 (subtitles of a film) | yes |
| **Look in the arrange view** | a label, colors, a small picture | all | yes |
| **Editor view** | a view or buffer to edit the data | 3, 4, 6, 8, 10, 11 | yes (exists: track kind `editor`) |
| **Playhead views** | a view that shows the data at the playhead | 1, 2, 9, 10, 13 | yes (exists: views + playhead live value) |
| **Picture of pixels** | a raster image in a view (frames, a spectrogram) | 1, 8, 13 | yes, new generic primitive |
| **Edit hooks** | split, trim, slip that are not offset math | 2 (split text), 6, 11 | yes, optional |
| **Export** | write the kind's data in another program's format | 1, 2, 3, 13, 14 | yes (exists: `paw.formats`) |
| **Links to other clips** | the analysis of a clip, the lyrics of a vocal | 2, 8 | yes, as data plus a generic "stale" event |
| **Live MIDI input** | read what the user plays | 10 (and recording a cue list) | already exists (events) |
| **OSC input** | read OSC from other programs | only "record light cues" | **no**: one user. Later. |
| **DMX output in the core** | 44 Hz universes from paw | only 3 | **no**: OSC to QLC+ or OLA does it |
| **Lua that changes sound at play** | a script that sets a parameter at a beat | none that automation or a state lane cannot do | **no**: see 3.3 |
| **A Rust trait per kind** | kinds compiled into the kernel | none (MIDI, audio are enum arms) | **no**: see 3.6 |

Lifetime events (a clip made, removed, its source changed, the project opened) are used by
1, 8, 12 (start background work) and 2, 8 (links). They reuse `paw.on` events.

---

## 3. The architecture

### 3.1 The Rust model

#### The kind's name: a newtype

```rust
/// The name of a kind of clip that an extension defines: a lowercase word
/// (`video`, `lyrics`), never one the core keeps for itself.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct ClipKindId(Arc<str>);

impl FromStr for ClipKindId { /* [a-z][a-z0-9_-]{0,31}, not in RESERVED */ }
pub const RESERVED: &[&str] = &["midi", "audio", "empty", "folder", "custom"];
```

`Arc<str>`: clips of one kind share the name. Clone is a count, which matters because the undo
history keeps snapshots. A new built-in content later takes one of the reserved words, so it can
never meet an extension's kind of the same name in an old project.

R10's `session::ClipKind` (the parsed `ClipOpts.kind`) becomes:

```rust
pub enum ClipKind { Midi, Audio, Custom(ClipKindId) }
```

It stops being `Copy`. The text of the errors stays the same for `midi` and `audio`. An unknown
word is now a custom kind, and `clip_add` refuses it only if Lua did not register it (the core
keeps a set of registered names, filled by `paw.clip_kinds.define`; see 3.4).

#### Where things live: `Clip` versus `ClipContent`

`Clip` keeps all that is generic: `id, name, start, length, muted, fade_in, fade_out, timebase,
looped, loop_length, loop_start, meta`. These work on every kind with no code of the kind.
The audio-only fields (`stretch, pitch, stretch_mode, source_tempo, warp, formants`) stay on
`Clip` as they are now. For a custom clip they apply to its sound when the sound is audio, and
are refused otherwise (the checks in `stretching::check_playing` take the playable content, see
below). This keeps the R10/R16 work and the save format unchanged.

```rust
pub enum ClipContent {
    Midi { notes: Notes, controls: Vec<Control> },
    Audio { file: PathBuf, offset: f64, gain: f64, edits: Vec<AudioEdit> },
    /// A clip of a kind that an extension defines. Boxed: the enum stays the
    /// size it is now, and MIDI clips (most clips) pay nothing.
    Custom(Box<CustomContent>),
}

pub struct CustomContent {
    pub kind: ClipKindId,
    /// The version of the kind's data, for its migrations. 1 when not said.
    pub version: u32,
    /// What the clip's own positions count: beats, or seconds (a film).
    pub timeline: Timeline,
    /// Where the clip starts in its data, in its timeline: what trimming the
    /// start or slipping changes. The data itself does not change.
    pub offset: f64,
    /// The kind's data: never read by the core, kept byte for byte.
    pub data: KindData,
    /// Files the clip uses, by the kind's word for each.
    pub media: Vec<MediaRef>,
    /// What it makes you hear: a MIDI or audio content, as the kind compiled it.
    pub sound: Option<Sound>,
    /// What it makes happen, in its timeline from the data's start.
    pub signals: Arc<[Signal]>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Timeline { Beats, Seconds }

pub enum KindData {
    /// JSON as it was read: `serde_json::value::RawValue` (feature `raw_value`).
    Json(Arc<RawValue>),
    /// Text in the kind's own format, with the file extension it is saved with.
    Text { ext: FileExt, text: Arc<str> },
}

pub struct MediaRef {
    /// The kind's word for it: "source", "proxy", "thumbs", "audio".
    pub role: MediaRole,           // newtype of Arc<str>, a word
    pub path: PathBuf,
    /// Made from other files by the kind, named by the hash of what made it:
    /// it can be made again, and it is never collected into `media/` twice.
    #[serde(default, skip_serializing_if = "is_false")]
    pub derived: bool,
}

/// A built-in content that a custom clip sounds as: `Midi` or `Audio`, never
/// `Custom` (the constructor refuses it, so the sync never recurses).
pub struct Sound(ClipContent);
impl TryFrom<ClipContent> for Sound { type Error = SoundError; /* refuse Custom */ }
impl Sound { pub fn content(&self) -> &ClipContent { &self.0 } }
```

Why `Sound` wraps `ClipContent` and is not a new enum: every function that plays, stretches,
splits, peaks and renders MIDI and audio already takes `&ClipContent`. One helper gives them the
content that sounds:

```rust
impl Clip {
    /// What the clip plays: its own MIDI or audio, or a custom clip's sound.
    pub fn playable(&self) -> Option<&ClipContent> {
        match &self.content {
            ClipContent::Custom(c) => c.sound.as_ref().map(Sound::content),
            built_in => Some(built_in),
        }
    }
}
```

`sync/clips.rs` changes `match &clip.content` to `match clip.playable()` in `parts_of`,
`orders_taken`, `build_cues` and `pieces_of`. Nothing else in the sound path changes. The
newtype makes the invariant (no nested custom) a type, not a comment
(rust-skills: api-parse-dont-validate).

Why `RawValue` and not `serde_json::Value`: the rule "an unknown kind round-trips byte for
byte" is only true if the core never re-encodes the data. `Value` would sort the keys and
rewrite numbers and spaces of a file that a person or another tool wrote. `RawValue` keeps the
text. Lua parses it when the kind asks (`clip:data()`), and caches the table by the `Arc`'s
address. Equality for undo and for the save is a string compare. The cost: one workspace
feature (`raw_value`) of a crate that paw already builds.

#### Signals

```rust
pub struct Signal {
    /// Where it happens, in the clip's timeline from the data's start.
    pub at: f64,
    /// How early it goes, in milliseconds, so that a slow receiver acts on time.
    #[serde(default, skip_serializing_if = "is_zero_u16")]
    pub lead_ms: u16,
    /// Signals with the same latch are states: on a jump, the last one
    /// before the play position is given again (chase).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latch: Option<Latch>,          // newtype of Arc<str>
    pub to: SignalTo,
}

pub enum SignalTo {
    /// To the kind's `on_signal` in the kernel, with this payload.
    Kernel { body: Arc<RawValue> },
    /// An OSC message to a port named in `paw.opt.osc_ports` (a machine's
    /// setting: the project names the port, the user says where it is).
    Osc { port: PortName, address: OscAddress, args: Vec<OscArg> },
}

pub enum OscArg { Int(i32), Float(f32), Str(Arc<str>), Bool(bool) }
```

OSC is in the core because three kinds use it (3, 5, 9) and the core cannot leave it to Lua:
Lua cannot send on the heard time with the precision of the MIDI out thread. Encoding uses the
`rosc` crate (paw-crates.md: no hand-written codec). MIDI to a port needs no signal: it is the
track's MIDI output, sample-accurate today.

#### Serde: old projects, unknown kinds

`ClipContent` is now `#[serde(tag = "kind")]`. An internally tagged enum has no "other" arm, so
`ClipContent` gets a hand-written `Deserialize` of about 30 lines: read the map, look at `kind`,
give `"midi"` and `"audio"` to the derived code of two private shadow enums (the same fields as
now), and give any other word to `CustomContent` (its `kind` field is the word). `Serialize`
writes `CustomContent` flat with its `kind` first. So:

- An old project has no custom clips: it reads as now, and is written byte for byte as now. The
  existing save tests prove it. Add one: a project folder with a custom clip of an unknown kind
  is read and written, and each file is the same bytes.
- `FILE_VERSION` does not change: old files read, and a custom clip in a file read by an old paw
  is an error of that paw ("unknown variant `video`"). That is right: an old paw must not save
  over a clip it does not know and lose it. The message is clear. (Open question 4.)

#### Undo and the diff

The undo history keeps project snapshots that share what did not change (`Arc`). A custom
clip's data, media and signals are `Arc`s, so a move of a video clip copies a few words.

`impl Part for Clip` in `session/undo.rs` gains one arm:

```rust
(ClipContent::Custom(was), ClipContent::Custom(now)) => {
    for (field, differs) in [
        ("data", !was.data.same(&now.data)),
        ("offset", was.offset != now.offset),
        ("media", was.media != now.media),
        ("sound", !same_sound(&was.sound, &now.sound)),
        ("signals", !Arc::ptr_eq(&was.signals, &now.signals) && was.signals != now.signals),
    ] { if differs { fields.push(field.into()) } }
}
```

and `label()` says the kind: "video clip intro". A sound that is MIDI counts its notes as MIDI
clips do. One user action is still one undo step: a kind's edit is one `clip_set_custom` call
that replaces data, sound, signals and media together (3.4).

#### Sync

`sync/clips.rs` builds engine `Part`s from `clip.playable()` (above) and, new, from
`signals`. The conversion of a signal's `at` to a project beat is done here, once per edit:

- `Timeline::Beats`: `beat = clip.start + at - offset`.
- `Timeline::Seconds`: `beat = tempo.beat(tempo.seconds(clip.start) + at - offset)`.
- Lead: `beat = tempo.beat(tempo.seconds(beat) - lead_ms / 1000)`.
- Signals outside `[start, start + length)` are dropped. A looped clip repeats them per pass with
  the `repeats()` function the MIDI path uses, and each copy knows its pass.

The kernel keeps a `SignalTable` beside the `Mapper`: for each `(clip id, index)`, what the
signal is (payload, port, latch). The engine sees only numbers (3.2).

### 3.2 Timing: where each thing happens

There are four places. Each kind of output goes to one of them, never more.

| Where | What | Precision |
|---|---|---|
| **Audio thread** (engine) | sound (MIDI, audio from `Sound`), emitting signals at their frame | sample-accurate |
| **Signal thread** (new, small) | OSC sends at the heard time; forwarding to the kernel | about 1 ms of jitter, latency-aligned with the sound |
| **Kernel main loop** (Lua) | `on_signal`, `chase`, `on_stop` of kinds; Ex actions | 2 to 15 ms after the frame, more if a key or a redraw is running; no bound |
| **Frontends** (via views) | video frames, lyrics, countdowns | at the frame rate (`paw.opt.fps`), from the playhead |
| **Helper processes** | ffmpeg decode and extract, analysis, speech | background; never waited on by a key |

The rule that keeps renders honest: **only the audio thread makes sound.** No signal changes
sound. A Lua action that wants to change sound at a beat is automation or a state lane, which the
render already plays.

#### The engine primitive: the signal stream

New engine types (paw-engine, `signal.rs`):

```rust
/// A signal in a clip part: where, and which (the kernel's table knows what).
#[derive(Clone, Copy, Debug)]
pub struct SignalEv { pub beat: f64, pub clip: u64, pub index: u32, pub pass: u32 }

/// What the audio thread tells the signal thread.
#[derive(Clone, Copy, Debug)]
pub enum Fired {
    Signal { at_ns: u64, beat: f64, clip: u64, index: u32, pass: u32 },
    /// The play position jumped or the transport changed: the reader chases.
    Jump { at_ns: u64, beat: f64, why: Jump },
}
#[derive(Clone, Copy, Debug)]
pub enum Jump { Play, Seek, LoopWrap, Launch, Stop }
```

- `Part` gets `signals: Arc<[SignalEv]>`, sorted by beat, next to `midi`. `ClipSet` walks them
  in `events(start, end, ..)` as it walks MIDI (same sounding-parts index, same `from/to`
  bounds, so a part with only signals still costs one comparison per block when it is not under
  the playhead).
- `TrackRt` gets `fired: ArrayVec<FiredSig, 64>` beside `sent: Vec<Event>` (which is made with
  capacity 1024 and never grows). Tracks run on pool threads, and an `rtrb` producer has one
  writer. So each track writes only its own `ArrayVec`.
- The mixing step that drains `t.sent` into the MIDI out ring today (engine/process.rs, the
  `if t.midi_out != 0` block) also drains `t.fired` into `self.signal_out:
  Option<Box<Producer<Fired>>>`, with `at_ns = self.heard_ns + frame * ns_per_frame`. The same
  `heard_ns` as MIDI out: the block's callback time plus the plugins' delay plus the output
  latency. So OSC lands with the sound that the listener hears.
- `Play`, `Seek`, `Stop`, the loop wrap (the block split at `loop_end` that exists) and a
  launch push a `Jump`.
- New messages: `Msg::SetSignalOut(Option<Box<Producer<Fired>>>)`, and its `Garbage` arm, as
  `SetMidiOut` has. The `Shared` block gets `signals_dropped: AtomicU32`.

Proof that the audio thread does not allocate, lock or wait:

1. `SignalEv` and `Fired` are `Copy` and hold no heap data. The `Arc<[SignalEv]>` of a part is
   made on the kernel thread and moved in through `Msg::SetClips`/`EditClips`, as MIDI is. It
   is freed on the kernel thread through `Garbage::Clips` / `Garbage::PartEdit`, as now.
2. `ArrayVec::try_push` writes into a fixed array. When it is full the signal is counted in
   `signals_dropped` and lost (64 signals on one track in one block is a bug of a kind, not
   music).
3. `rtrb::Producer::push` is wait-free and writes into a buffer made at the start (4096 slots).
   Full: count and drop, as `crate::event::count_dropped()` does for MIDI out.
4. `tests/no_alloc.rs` gets a case: a track with a part of 1000 signals and MIDI, looped,
   played across the wrap, sought twice and stopped, under `assert_no_alloc`.

When no clip has signals, `signal_out` is `None` (the kernel sends it only when the
`SignalTable` is not empty). Then the cost is one `Option` test per track per block.

#### The signal thread

A thread made by the kernel the first time a project has signals (paw-core `signals.rs`). Like
the MIDI output thread: it sleeps 1 ms between reads while the transport plays, and parks
(no wakeups) while it is stopped. Rule "quiet when idle" holds: the idle program does not wake.

- It holds an `Arc<SignalTable>` (swapped by the kernel at each sync; the old one is dropped on
  this thread, not the audio thread).
- For a `Fired::Signal` to OSC: it waits until `at_ns` (minus nothing: `heard_ns` already
  counts the latency), and sends the packet on a UDP socket through `rosc`. A port that is not in
  `paw.opt.osc_ports` or does not answer: one message per play, "lights: no OSC port `lights`
  (set paw.opt.osc_ports)".
- For a `Fired::Signal` to the kernel: it sends `KernelMsg::Signal { clip, index, pass,
  beat, at_ns }` on the kernel's channel. This wakes the kernel's `recv_timeout`.
- For a `Fired::Jump`: it chases its OSC latches (the last OSC signal per latch at or before
  `beat` in each clip that covers or came before `beat`, from the table, sent at once), then
  forwards the jump to the kernel, which chases Lua kinds.

Why a thread and not a `tokio` task: the job is "poll a lock-free ring every millisecond while
playing, and send on time". paw-crates.md gives tokio for I/O that waits. This waits on a
clock and a ring, like `midi_out.rs`. The UDP send is one non-blocking `send_to`. If the owner
prefers, it can be a task on the shared I/O runtime with `tokio::time::interval`, same behavior.
(The MIDI out thread and this thread could later become one "timed output" thread. Not now:
two working paths, one refactor at a time.)

#### Lua at a beat: latency and guards

The kernel handles `KernelMsg::Signal` in its turn: it finds the kind, and calls
`spec.on_signal(clip, signal)` under `paw.limit` with a short budget,
`paw.opt.clip_kind_limit` (default 50 ms; a key must stay under 100 ms, and a signal handler can
run between two keys).

Latency, stated in the docs: the block (5.3 ms at 256 frames, 48 kHz) plus up to 1 ms of the
signal thread, plus the time the kernel needs to finish what it is doing. Usually under 10 ms.
It is not sample-accurate. A kind that needs its effect on time asks for a lead
(`lead_ms`) and gets `signal.at_ns` (the heard time) to act at that moment itself, for example
by a helper that sends at a time.

The write guard: while a signal handler, a chase or a stop handler runs, the session refuses
edits of the project: "a clip's action does not change the project; use automation". Reason:
rule 6 says one *user* action is one undo step. An action at play is not a user action, and an
undo step at each bar of a loop would bury the user's steps. The guard is one flag checked where
an edit begins (the place that starts an undo step in `session`), so it holds for Lua, Ex and
the API alike. Allowed: the transport, the launcher, views, messages, OSC, helper processes,
timers.

Errors: a handler error is a message, never a trace (`paw.limit.guard` does this). Three errors
of one kind in one play pause that kind's signals until the next play, with one message
("lyrics: stopped its actions after 3 errors; :messages has them").

#### Loop, seek, stop, launch

- **Loop wrap.** The engine splits the block at the loop end now. Signals of the second piece
  fire with their frame. A `Jump::LoopWrap` comes first, so latched states (lights) chase to the
  loop start.
- **Seek and play.** `Jump::Seek`/`Jump::Play` with the beat. OSC latches chase on the signal
  thread. Lua kinds get `chase(clip, beat)` for clips under the beat or ending before it
  (a kind says how far back it cares: `chase_back = "clip" | "track"`; lights need "track": the
  last cue of an earlier clip still holds).
- **Stop.** `Jump::Stop`. The kernel calls `on_stop` of each kind with signals (video pauses,
  lights can black out if the user asked).
- **Launcher.** Custom clips in launcher slots play their sound and signals as arrangement clips
  do: the launch builds parts from the same `ClipSet` code. A `Jump::Launch` per launched track.

#### Offline render and freeze

- A render makes its own engine and gives it **no** `signal_out`. So no OSC goes out and no Lua
  action runs while it renders faster than real time. The sound of custom clips is in the parts,
  so it renders bit for bit as it plays.
- The render report says what it did not do: "not sent while rendering: 42 light cues, 3
  actions". A kind that has a file form of its signals (a cue list, subtitles) exports it with
  `:export`, not with the render.
- **Freeze.** The frozen file holds the sound. The track's signals still fire: sync keeps the
  signal parts of a frozen track, and gives the engine the frozen file as the sound. The tests
  for freeze get a case: a frozen track with a lights clip still sends its OSC.

#### Frontends: things that follow the playhead

Video frames, lyrics and countdowns are not signals. A view reads the playhead and draws. The
window already gets the playhead as a live value; the kernel redraws a view that `follows` at
`paw.opt.fps` while playing. A monitor view draws the frame for
`clip_time = seconds(playhead) - seconds(clip.start) + offset`, shifted back by the output
latency so the picture matches what you hear.

### 3.3 What a kind cannot do, on purpose

- Change sound from Lua at play time (see the rule above). Its sound is compiled ahead.
- Own another clip's data. A lyrics clip links to a vocal clip by id in its own data. It reads
  the vocal's notes; it never writes them unless the user asks (then it is a normal edit of that
  clip, one undo step).
- Block a key. A compile that takes long (extract audio, analysis, speech) runs in a helper
  process and writes a content-addressed file (3.4, "Slow compiles").

### 3.4 The extension API

#### `paw.clip_kinds` (new runtime module, Teal: `runtime/lua/paw/clip_kinds.tl`)

```lua
paw.clip_kinds.define(name, spec)  -- register; replaces a kind of the same name
paw.clip_kinds.remove(name)
paw.clip_kinds.list()              -- names, in the order defined
paw.clip_kinds.spec(name)          -- the spec, or nil
paw.clip_kinds.add(track, name, opts)   -- a new clip of the kind: create + compile, one undo step
paw.clip_kinds.set(clip, data, opts)    -- new data: migrate-free; compile; one undo step
paw.clip_kinds.compile(clip)            -- compile again (after a link changed), one undo step
paw.clip_kinds.describe(clip)           -- "video · intro.mp4 · 0:12", or "video (no extension defines it)"
```

The contract in `contracts.tl`, typed by the record of the kind's data, as `Role<P>` is:

```lua
--- A kind of clip (`paw.clip_kinds.define`). `D` is the record of its data.
record ClipKind<D>
   name: string
   title: string               -- "Video clip"
   letter: string              -- one letter in the arrange view
   version: integer            -- the version of D; 1 when not given
   timeline: Timeline          -- "beats" (default) | "seconds"
   text: TextForm<D>           -- optional: data as text (encode, decode, ext)
   track_kind: string          -- optional: the track kind whose new clips are this kind

   -- Data
   create: function(args: ClipKindArgs): D, string          -- data, or nil and why
   check: function(data: D): string                         -- nil when good
   migrate: function(data: any, from: integer): D, string   -- `any` allowed: it is the old shape

   -- Output: what the clip sounds as and what it makes happen. Pure: no edits, fast.
   compile: function(data: D, clip: ClipInfo): Compiled, string

   -- At play (kernel, under paw.limit, writes refused)
   on_signal: function(clip: ClipHandle, s: SignalInfo)
   chase: function(clip: ClipHandle, beat: number)
   chase_back: ChaseBack       -- "clip" (default) | "track"
   on_stop: function(clip: ClipHandle)

   -- Edits (optional; the default is offset math on the clip)
   split: function(data: D, at: number): D, D               -- at: in the timeline from data start
   trim: function(data: D, from: number, to: number): D

   -- Look
   describe: function(clip: ClipHandle): string             -- for K
   look: function(clip: ClipHandle, ctx: ClipLookContext): ClipLook   -- arrange view
   editor: function(clip: ClipHandle): boolean              -- open its view or buffer

   -- Export
   formats: {string}           -- names of `paw.formats` it registers, for :help
end

record Compiled
   sound: CompiledSound        -- { kind = "midi", notes, controls } | { kind = "audio", file, offset, gain }
   signals: {SignalSpec}       -- { at, to = "kernel" | port, address, args, body, latch, lead_ms }
   media: {MediaSpec}          -- { role, path, derived }
   length: number              -- optional: the natural length
end

record ClipLook
   label: string               -- drawn in the clip's cells
   marks: {ClipMark}           -- { at, text, role } inside the clip (cue names, comments)
   strip: StripSpec            -- optional pixels (thumbnails), as `buf:strip`
   color: string               -- optional
end
```

Everything a kind returns is checked by the runtime with `check` and by the kernel's parse of
`Compiled` (typed Rust, `thiserror` errors with clear texts: "lights: signal 3 has no `at`").
The data is never `any` in a kind's code: the runtime decodes the JSON and casts it once to `D`
after `check` passes (the one cast in `clip_kinds.tl`, listed in the any allow-list with a
reason).

Keys come for free from the generic clip commands: `x` deletes, `y`/`p` copy and paste, `<`
`>` move, trimming keys trim, `K` describes (calls `describe`), Enter opens (`editor`). A kind's
own keys go on `<localleader>` in its editor view (key rule).

#### Relation to track kinds, views, roles, formats

- **Track kinds.** A clip kind needs no track kind. A track kind may name `clip_kind` (field
  added to `TrackKind`) so that `clip.add` on it makes that kind (a "Video" track makes video
  clips; a "Lights" track lights clips). A track kind that makes no sound sets `mixer = false`
  (new optional field): the mixer and the track's devices are hidden, the strip stays in the
  model. Used by lights, comments, lyrics tracks.
- **Views.** A kind's editor and its playhead views are normal views (`paw.views`), written once,
  in both frontends.
- **Roles.** `look.marks` use roles (`paw.roles`), so the window draws them without code of the
  kind.
- **Pictures.** New generic primitive: `g:image(x, y, w, h, key)` in `Painter`, and
  `paw.canvas.image(bytes, w, h, format)` that stores RGBA or PNG bytes in the blob store and
  returns its content key. The scene sends the key; the window fetches the blob once (the
  `scene.blob` path exists) and makes a texture; the terminal sends it with kitty, or draws it in
  half-block cells (`▀`, fg and bg colors) when it shows no images. Terminal first: the half-block
  path is the first one built. Used by video (frames, thumbnails), analysis (spectrogram),
  slideshow.
- **Formats.** A kind registers its export with `paw.formats.register` as other extensions do
  (`mp4`, `srt`, `lrc`, a QLC+ show). Nothing new.
- **`paw.Clip` in Lua.** `clip:get().kind` is the kind's name. New: `clip:data()` (the decoded
  data, nil for MIDI and audio), `clip:media()`, `clip:signals()`, `clip:sound_kind()`.

#### Slow compiles: content-addressed files

`compile` must return fast (the key budget). A kind whose sound needs a helper (video audio,
speech, a slice render) returns at once a `sound` that names the file it *will* write:
`media/derived/<kind>-<hash of the inputs>.flac`, with `derived = true`. It starts the helper.
The clip is in the model at once, so the undo step is whole. The engine reads a missing file as
silence and the clip shows "making its sound…". When the file is written, the existing file
watch makes the engine load it. Undo and redo point at files that stay, so they need no new
work. This is the utau model, made generic. `paw.api.hash(...)` (ring digest, exists in the
lock file) names the file.

#### Wasm later

The parts that are pure functions from data to data can run in Wasm: `create`, `check`,
`migrate`, `compile`, `split`, `trim`. They need no kernel state, they must be deterministic,
and a sandbox with a fuel limit suits them better than `paw.limit`. The parts that touch the
kernel or the screen stay Lua: `on_signal`, `chase`, `on_stop`, `look`, `editor`, `describe`.
At that time the kernel gets a `trait KindCode { fn compile(&self, ..) -> Result<Compiled,
KindError>; .. }` with two implementations (Lua and Wasm). Not before: today it would have one.

### 3.5 Files

```text
song/
├── tracks/
│   └── Video/
│       ├── track.json                 the clip entry: kind, version, timeline, offset, media, file names
│       └── clips/
│           ├── intro.video.json       the data (KindData::Json), byte for byte
│           ├── intro.signals.json     the signals, if any
│           └── intro.sound.midi2      the sound, if it is MIDI (an audio sound is a media file)
│   └── Lyrics/clips/verse.lyrics.lrc  text data (KindData::Text, ext "lrc")
├── media/
│   ├── film.mp4                       a source (collected as audio files are)
│   └── derived/video-3f9a….flac       derived files (content-addressed)
└── unused/                            as now: never deleted
```

- The entry in `track.json` names its files, as a MIDI clip names its `.midi2`. Two clips with
  the same data share one data file, as MIDI clips with the same notes share one `.midi2`. This
  is why the default split is offset math: both halves keep the same data and the same file.
- The data file is written only when its bytes differ from the disk (the rule of today). A kind
  that formats its JSON for reading in git does it in its encoder; the core never re-formats.
- `paw.media.*` (collect, relink, missing, search, list) take every `MediaRef`. `derived`
  files are not copied by `collect` from outside (they are made inside), and `missing` says
  "will be made again" for them when the kind is loaded.
- Git: JSON and text data diff as text. `.gitattributes` does not change. A `.sound.midi2` uses
  the existing `paw-midi2` driver (its glob `*.midi2` matches).

### 3.6 MIDI and audio: special, or instances of the abstraction?

Kept special, as enum arms. The reasons:

1. **The audio thread.** MIDI and audio compile into `MidiEv` and `AudioRegion` in parts. A
   custom clip compiles into the same two. There is one sound path in the engine, so nothing is
   gained by a trait there, and a `dyn` call per clip in sync would cost on a big project
   (rule 7).
2. **The "two implementations" rule.** A Rust `trait ClipKindImpl` would have no second
   implementation: custom kinds are data-driven from Lua. MIDI and audio share almost nothing in
   their edits (notes and controllers against an edit list, stretch and warp), so one trait for
   both would be the union of two APIs.
3. **The save format.** `.midi2` and the audio fields are the project format today, with tests.
4. **Without extensions.** MIDI and audio must play with no Lua at all (`--clean`, render
   helpers, `paw clip cat`). A built-in kind as a Lua kind would invert this.

What *is* shared: `Clip`'s generic fields and commands (move, trim, loop, fade, copy, undo,
save) work on all three. And a custom kind *ends* in MIDI or audio through `Sound`. That is the
real unification: "every clip sounds as MIDI, audio, or nothing".

The pattern extension becomes a custom kind (`pattern`, text data, MIDI sound). This is the
migration test: today its text is in `clip.meta` and its notes are the clip's notes; after, the
text is the data and the notes are the sound. Its projects migrate on load (version 1 → 2 of a
`pattern` MIDI clip with `meta.pattern` becomes a custom clip), and without the extension they
still play the same notes.

### 3.7 Without the extension; versions

**Without the extension** (not loaded, or the user deleted it):

- The clip is in the model and the files as it was. Move, trim (offset math), copy, delete,
  mute, loop, undo and save work. Nothing of the data changes.
- Its sound plays. Its OSC signals go out. Its kernel signals do nothing; one message per play:
  "2 clips of kind `script` do nothing: no extension defines it".
- It shows as `?` with its kind's name and its name; `K` says "video clip (no extension defines
  it) · plays its sound · 3 media files".
- Edits that need the kind (`clip_kinds.set`, its editor) say "load the extension that defines
  `video`" and do nothing.
- Split without the kind: offset math. Both halves share the data. The sound splits as MIDI or
  audio splits now. Signals are cut by time.

**Versions of a kind's data.** A kind has `version` (an integer). Each clip keeps the version
of its data.

- Clip version < kind version: on project load, the runtime calls `migrate(data, from)` for
  each clip of the kind and compiles it again. This is not an undo step (opening is not an
  action); the project is marked changed, and one message says "video: 12 clips moved to data
  version 3". A failing migration leaves the clip as it was, treated as without the extension,
  with the error as a message.
- Clip version > kind version (a project from a newer extension): the clip is read-only for the
  kind: it plays, shows and moves, but `set` and the editor refuse: "this clip was made by a newer
  video extension (data 4, this one knows 3)".
- When the extension is loaded after the project, the same migration runs at `define`.

### 3.8 Safety

- **Lua on the kernel thread.** Every hook runs under `paw.limit.guard`. `compile`, `check`,
  `migrate`, `split`, `trim`, `look` and `describe` get the key budget
  (`paw.opt.clip_kind_limit`, 50 ms); `paw.limit.guard` gets an optional budget argument for
  this (generic change). `look` that fails draws the clip as unknown, with the message once.
- **No stall of audio.** Lua never runs on the audio thread or the signal thread. The audio
  thread sees `Copy` numbers only.
- **No stall of keys.** Helpers (ffmpeg, analysis, speech) run as `paw.api.proc_spawn`
  processes on the shared tokio runtime; their output comes back as kernel messages.
- **Code in a project.** A script clip's Ex lines can contain `:lua` or `:!`. A project from
  someone else must not run code when you press play. Rule: Ex lines that only call commands of
  paw run. `:lua`, `:!` and commands marked `unsafe` run only in a trusted project
  (`:trust`, kept by the folder's path in the XDG state folder). An untrusted project says once:
  "this project has 2 script actions that run code: :trust to allow". (Open question 2.)
- **Errors are messages**: every error text names the kind and the clip.

---

## 4. Worked designs

### 4.1 Video (`extensions/video`)

**Setup.** `:ext.load video`. The extension checks `ffmpeg` and `ffprobe` with `paw.api.which`
(and `:checkhealth video` says if they are missing). It defines the track kind `video`
(`clip_kind = "video"`, a track with no devices; its fader is the film's sound) and the clip
kind `video` (`timeline = "seconds"`).

**Import.** `:import film.mp4` (the extension registers the `mp4`, `mov`, `mkv`, `webm` import
formats) or `:track.add video` then `\vi` (localleader, import) in the arrange view.

1. `ffprobe` (a helper, about 50 ms) gives the length, the frame rate, the size and if there is
   sound. The clip is made at once with data `{ source = "media/film.mp4", fps, width, height,
   has_audio }`, media `[source]`, and the sound named ahead:
   `media/derived/video-<hash>.flac`. One undo step: "added video clip film".
2. In the background: `ffmpeg` extracts the sound to that file, a proxy
   (`derived/video-<hash>-proxy.mp4`, 480p, all key frames for fast seeks) and a sprite of
   thumbnails (`derived/video-<hash>-thumbs.png`, one frame each 2 s). The arrange view shows
   "making…" until the files appear.

**Keys.** The video track in the arrange view shows thumbnails (a strip, from the sprite) or, in
a terminal without images, the clip name and timecodes. Generic keys move and trim. Slip (move the
film inside the clip) is the generic offset (`[ ]` changes the second value: the offset). `K`
says "video · film.mp4 · 1920×1080 25 fps · 0:12–1:40 of 3:05". `:video.monitor` (and
`<localleader>m`) opens the monitor view: the frame at the playhead. Scrubbing the cursor shows
the frame at the cursor.

**At play.** The film's audio is an audio sound: it plays sample-accurate through the existing
path, with fades and gain. The monitor view redraws at `paw.opt.fps` while playing: it asks the
video helper for the frame at `clip_time - output_latency`. The helper is one long `ffmpeg`
process per visible clip, reading the proxy from the play position and writing raw RGBA frames
at the view's size to its pipe. On a seek it is started again at the new place (proxy with all
key frames: under 50 ms). Frames go to `paw.canvas.image` and `g:image`. In a terminal without
images, the view draws half-block cells (80 × 24 cells is 80 × 48 pixels): rough, but the
terminal comes first and shows the cut points.

**Signals.** None. A chase on seek restarts the decoder (`chase` hook), `on_stop` stops it.

**Saved.** `track.json` entry (kind `video`, version 1, timeline seconds, offset), the data
`clips/film.video.json`, media `media/film.mp4` and the derived files.

**Render.** The sound renders as any audio clip. `:export song.mp4` (format registered by the
extension): renders the master (existing `paw.render`), then one ffmpeg run cuts and joins the
video clips of the video tracks (trim filters per clip, black for gaps, the topmost track wins
where they overlap) and muxes the render. A progress message; the work runs in the helper.

**Undo.** Move, trim, slip, delete: generic, one step each. Undo of an import: the clip goes;
the derived files stay in `media/derived` (to `unused/` on the next save, never deleted). Redo:
the files are still there; nothing is made again.

**Without the extension.** The film's sound plays at its place. The clip shows as `? film`.

### 4.2 Light cues over OSC (`extensions/lights`)

**Setup.** The user sets the port once in their config: `paw.opt.osc_ports = { lights =
"127.0.0.1:7700" }` (QLC+ listens there). `:ext.load lights`, `:track.add lights`.

**Data** (`clips/show.lights.json`):

```json
{ "port": "lights", "cues": [
  { "at": 0, "name": "intro blue", "fade": 2.0,
    "send": [ { "address": "/scene/blue", "args": [1.0] } ], "latch": "wash" },
  { "at": 16, "name": "drop strobe", "send": [ { "address": "/strobe", "args": [1] } ],
    "latch": "strobe" } ] }
```

`at` is in beats (timeline beats): lights follow the music.

**Keys.** Enter opens the cue list: one cue per line (a buffer of the kind). In it:
`j k` move between cues; `<localleader>a` adds a cue at the playhead; `+ -` and `Ctrl-a`
`Ctrl-x` change the main value of the field under the cursor (a level); `[ ]` the fade time
(second value); `< >` move the cue in time by the grid; `K` describes the cue (its messages);
`Esc` leaves. Each change is one undo step: the view calls `paw.clip_kinds.set(clip, data)`,
which checks, compiles and replaces the clip in one step. Messages: "cue drop strobe at 5.1.1".
In the arrange view, cue names are marks inside the clip (a role).

**Compile** (Lua, pure, under 1 ms for hundreds of cues): one OSC signal per message, with the
cue's latch, the fade as an extra arg when the program takes one. No sound.

**At play.** The engine emits each signal at its frame. The signal thread sends the OSC packet at
`heard_ns`: the light changes when the listener hears the beat, not 20 ms early. Seek to bar 9:
the signal thread chases. For each latch, it sends the last message before bar 9 (`wash` is
"intro blue"), in this clip or an earlier one on the track (`chase_back = "track"`). Loop: at
the wrap, the latches chase to the loop start. Stop: nothing, unless the user set
`paw.opt.lights_blackout_on_stop` (the extension's own option, its `on_stop`).

**Render.** No OSC goes out. The report says "not sent while rendering: 42 light cues".
`:export show.csv` writes a cue list with times in seconds for a lighting operator.

**Without the extension.** The OSC signals are saved in `clips/show.signals.json`, so the
lights still run in a project opened without it. Only the cue list editor is missing.

### 4.3 Script and action clips (`extensions/actions`)

**Data** (text, `clips/end.actions.ex`):

```text
:stop
:view lyrics
```

**Keys.** In the arrange view, `<localleader>a` on an empty place of an actions track asks
"Action:" with Ex completion; Enter makes a short clip (one beat) at the cursor: one undo step,
"added action :stop at 65.1.1". Enter on the clip opens its text in a buffer; `:w` (or leaving
the buffer) sets the data: one undo step. `K` shows the lines and the trust state.

**Compile.** One kernel signal per line, all at `at = 0` of the clip, with the line as the body,
in order. `lead_ms` is 0; a line that names a slow receiver can ask for more.

**At play.** The engine emits the signals at the clip start; the kernel gets them a few ms later
and runs each Ex line with the write guard on. `:stop` stops the transport. `:view lyrics` opens
a view. `:track.add` is refused: "an action at play does not change the project (end, line 3)".
A line with `:lua` in an untrusted project is refused with the `:trust` message. A seek past the
clip does not run it (`chase` is not defined: an action is an event, not a state). A loop runs it
at each pass.

**Render.** Nothing runs. Actions do not change sound by rule, so the render is the same.

**Undo.** Adding, moving, editing: one step each. The actions that ran at play made no steps.

**Without the extension.** The clip shows `? end`; at play one message says that 1 clip of kind
`actions` does nothing.

---

## 5. What changes in the docs and the rules (stated, not written)

- **AGENTS.md rule 4** becomes: "**One owner per piece of data, and what plays is saved.**
  MIDI and audio clips are core data that every view edits. A clip of an extension's kind owns
  its data; the core keeps it untouched. What a clip sounds like and makes happen is saved with
  it, so a project opens and plays without the extension. An extension keeps data about other
  data in `meta`." Link the new explanation page.
- **docs/explanation/about-midi-as-the-truth.md** becomes **about-clip-data.md** (rename, with
  the old page's tags): keep "one truth, many views" and notation in `meta` (true still for MIDI
  clips); add "kinds of clip", "sound and signals are saved", "without the extension".
- **New explanation: about-clip-kinds.md**: why custom kinds; the four places where things
  happen and the latency of each; why Lua at play does not change sound; why renders send
  nothing.
- **New reference: docs/reference/clip-kinds.md**: the spec, `Compiled`, signals, OSC ports,
  the files. `docs/reference/api.md` regenerates from `clip_kinds.tl`.
- **New how-to:** "How to send light cues with the song" (the lights extension), "How to add a
  video" (the video extension), each with its test in `tests/guides_howto.lua` style.
- **docs/reference/project-files.md**: the custom clip files, `media/derived/`.
- **about-core-and-extensions.md**: the table gets "OSC output, the signal stream" (three kinds
  use them) and "images in views" (three kinds).
- **.claude/skills/paw-extension**: a section "a kind of clip".
- **The search before the commit** (AGENTS.md): "MIDI is the truth", "MIDI as the truth",
  "only MIDI and audio", `midi-as-the-truth`, "owns clip data", in README.md, AGENTS.md, docs/,
  extension READMEs and `doc/`, `.claude/skills`, and the memory note of the owner (the manager
  updates `notation-midi-truth.md`).

---

## 6. The plan

Each part is 30 to 90 minutes, one agent, its own worktree, owned files in brackets. "Opus" for
the audio thread and the kernel, "Sonnet" for mechanical work. **Parallel** marks parts that
touch no file of the running Rust queue (see section 6.2).

### Phase A: the model (no behavior yet)

- **A1 (opus).** `ClipKindId`, `Timeline`, `KindData`, `MediaRef`, `Sound`, `Signal`,
  `SignalTo`, `OscArg`, `CustomContent`, `ClipContent::Custom`; the hand-written
  `Deserialize`/`Serialize`; `Clip::playable()`; `serde_json` `raw_value` feature. [model.rs,
  new model/custom.rs, Cargo.toml] Tests: a custom clip of an unknown kind round-trips; an old
  project's bytes do not change; `Sound::try_from(Custom)` fails.
- **A2 (sonnet).** Replace `match &clip.content` with `clip.playable()` where the sound is
  meant; refuse audio-only fields on a custom clip with no audio sound. [sync/clips.rs,
  session/stretching.rs, session/clipops.rs, session/render.rs call sites] Tests: a custom clip
  with a MIDI sound plays its notes (one Lua test with real keys later, in B2).
- **A3 (sonnet).** `ClipKind::Custom`, `clip_add`/`clip_set` for custom content (one call that
  replaces data, sound, signals, media); a registered-kinds set in the session. [session.rs,
  session/clips.rs, api/clips] Tests: add, set, undo, unknown kind refused with its text.
- **A4 (sonnet).** Folder save and load of custom clips: data files, `.signals.json`,
  `.sound.midi2`, shared data files, `media/derived`, unused. [session/folder.rs, session/media.rs]
  Tests: save and load byte for byte; two clips share one data file.
- **A5 (sonnet).** Undo diff arm and label. [session/undo.rs] Test: one diff line for a data
  change.

### Phase B: the runtime API

- **B1 (opus).** `runtime/lua/paw/clip_kinds.tl`, `contracts.ClipKind<D>`, `Compiled`, `ClipLook`;
  `paw.Clip:data()` etc.; `paw.limit.guard` budget argument; migration at load and at `define`;
  `describe` for unknown kinds. [clip_kinds.tl, contracts.tl, objects.tl, limit.tl, types,
  apidoc output] Tests (Lua): define, add, set, migrate, newer version refused, unknown kind.
  **Parallel** with A2–A5 once A1 and A3 merged.
- **B2 (sonnet).** Arrange view: draw custom clips by `look` (label, marks as roles, strip), `?`
  for unknown; `K` and Enter. [views/arrange.lua, roll_clips.lua, defaults/clips.lua] Tests with
  real keys: a comment kind defined in the test, `K`, Enter, split (offset math), undo.
- **B3 (sonnet).** Track kind fields `clip_kind` and `mixer`. [track_kinds.lua, contracts.tl,
  views/mixer.lua] Tests: a clip added on such a track has the kind; the mixer hides it.

### Phase C: signals (the audio thread)

- **C1 (opus).** paw-engine: `SignalEv`, `Fired`, `Part.signals`, walk in `ClipSet::events`,
  `TrackRt.fired` (ArrayVec), drain to `signal_out` in process.rs, `Jump`s on play, seek, stop,
  wrap, launch; `Msg::SetSignalOut`, `Garbage`; `signals_dropped`. [new signal.rs, clip.rs,
  engine/process.rs, engine/track.rs, engine/msg.rs, engine/apply.rs, engine/shared.rs]
  Tests: engine test that signals come at their frames, across a loop wrap and a seek;
  `tests/no_alloc.rs` case. **Must wait for E7** (it may touch process.rs).
- **C2 (opus).** paw-core: `SignalTable`, sync of signals (beats, seconds, lead, loop passes),
  the signal thread (park when stopped), `KernelMsg::Signal`/`Jump`, OSC through `rosc`,
  `paw.opt.osc_ports`, OSC chase by latch, freeze keeps signals, render gives no `signal_out` and
  counts what it skipped. [new signals.rs, sync/clips.rs, sync/mod.rs, kernel.rs (one arm),
  session/render.rs (report)] Tests: an OSC signal reaches a UDP socket in the test (a local
  port, no real program), at about its heard time; a seek chases; render sends nothing.
- **C3 (opus).** Kernel side: `on_signal`, `chase`, `on_stop` under the limit; the write guard;
  three errors pause a kind. [clip_kinds.tl, session (write guard, the one place an undo step
  begins), kernel.rs] Tests: a handler runs at a beat while playing (null audio); an edit from a
  handler is refused with the message; an error is a message.

### Phase D: pictures

- **D1 (opus).** `paw.canvas.image`, `Painter:image`, scene blob of pixels; terminal: kitty and
  the half-block fallback; window: texture from the blob. [canvas.tl, paw-scene, paw-raster,
  paw-tui, paw-gui picture code] Tests: the half-block cells of a 2×2 image; the window test
  of a picture blob (`cargo test -p paw-gui`). **Parallel** (frontend crates are free in the
  queue: F7 only touches tests).

### Phase E: extensions (each proves the design)

- **E1 (sonnet).** `extensions/comments`: data only, look, a quickfix list. The smallest kind.
  README, tests with keys. **Parallel** after B2.
- **E2 (sonnet).** `extensions/actions` (4.3) with `:trust`. After C3.
- **E3 (opus).** `extensions/lights` (4.2). After C2.
- **E4 (opus, 2 parts).** `extensions/video` (4.1): import, derived files, monitor view (after D1);
  then `:export mp4`. Nix: ffmpeg is in the dev shell already (encode.rs uses it).
- **E5 (sonnet).** Port `extensions/pattern` to a custom kind with its migration; projects with
  pattern clips still play without the extension. After B1.
- **E6 (sonnet).** Docs of section 5, and the rule 4 change, in the commit of the first part that
  makes it true (A3 for the model; the explanation page with C3).

### 6.1 Order

A1 → (A2, A3) → (A4, A5, B1) → (B2, B3, C1 when E7 is done, D1) → C2 → C3 → E1…E5.
A first useful slice for the owner: A1–A5, B1, B2, E1 (comments) — a kind that works end to
end with no engine change, in about six parts.

### 6.2 What can run while the Rust queue runs

The queue (rust/QUEUE.md) still has open: E7 (engine long functions: process.rs, maybe clip.rs),
C5 (paw-core B3/B4 leftovers: sync/, session/), C9, R3, R5, R7, R8, R13–R17 (R16 touches
`clip_add`), P-items (paw-plugins), T4 (Teal comments), Z2 (docs).

- **Can run now:** D1 (frontends and canvas.tl), the Teal contract drafting of B1 in a
  worktree (contracts.tl is not in the queue; T4 touches other `.tl` files).
- **Wait for R16** (clip_add) before A3, and for **C5** before A2 and C2 (sync/, session/).
- **Wait for E7** before C1 (engine/process.rs, clip.rs).
- **Z2 and E6** both touch docs: E6 after Z2, or one agent owns both files.
- R13 (clippy to zero, workspace lints) before phase A is better: the new code then meets the
  lints from its first commit.

### 6.3 Risks

- **The hand-written `Deserialize` of `ClipContent`.** Error texts for bad MIDI or audio entries
  must not change; a test of each existing error text. Medium.
- **Signal latency under load.** The kernel can be busy (a long redraw). Lua actions can be late
  by tens of ms. Stated in the docs; tight timing uses OSC or MIDI, which do not go through the
  kernel. Low, if the docs are honest.
- **The write guard** may refuse things users expect (a script that adds a marker at play). Start
  strict; the owner decides exceptions (open question 3).
- **Video in a terminal without images** looks rough. The half-block view shows the cut and the
  colors only. Accept; the window and kitty show real frames.
- **ffmpeg on the machine.** Video is an extension with a health check; the core does not need it.
- **Scope creep in the core.** OSC out and images enter the core with three users each; OSC in
  and DMX stay out. Keep the capability table in the explanation page and apply its rule.
- **Old paw opening a new project** fails on the custom clip (by design). Medium for the owner's
  habit of opening old builds; see open question 4.

---

## 7. Open questions for the owner

1. **Rule 4's new text.** "One owner per piece of data, and what plays is saved", in place of
   "MIDI is the truth". *Recommendation:* yes. It keeps the promise users care about (a project
   plays without the extension) and drops the part that blocks video and lights.
2. **Code in projects.** A script clip can hold `:lua`. *Recommendation:* Ex commands of paw run
   always; `:lua`, `:!` and unsafe commands run only after `:trust` for that project folder,
   like Neovim's `exrc` trust. The other choice (never code in clips) is safer but weaker.
3. **Actions at play do not edit the project.** *Recommendation:* strict at first: no undo
   steps from playback. If you want "add a marker at play" or "record a take on a beat", they go
   through commands that are not project edits (the recorder already is a user action).
4. **An old paw and a new project.** An old build refuses a project with a custom clip
   ("unknown variant"). *Recommendation:* accept: refusing is safer than losing a clip. The
   alternative is a `FILE_VERSION` bump with the same effect and a clearer message; I would do
   the bump only if you often open projects with older builds.
5. **OSC ports are a machine setting** (`paw.opt.osc_ports`), the project only names them.
   *Recommendation:* yes, as MIDI ports work. A project moves between venues; addresses do not.
6. **Renders send no signals.** Lights do not flash while you render. *Recommendation:* yes;
   kinds export their signals as files (`:export`), and a later "play to file in real time"
   could send them, if a user asks.
7. **The pattern extension becomes a custom kind** (its text is the data, its notes the sound).
   Users see "pattern clip" in `K`, and its notes are no longer edited in the piano roll as the
   truth (the piano roll would edit the sound, which the next compile replaces). *Recommendation:*
   yes, with "make it a MIDI clip" (`:clip.flatten`, generic: a custom clip with MIDI or audio
   sound becomes a built-in clip of that sound, one undo step) for users who want to edit the
   notes by hand.

---

## 8. The owner's decisions (2026-11-21)

The owner said: "Let's go for it, and also no need to worry about backwards compatibility yet as we
have not released any tagged version yet."

- All seven recommendations of section 7 are taken: rule 4 becomes "one owner per piece of data,
  and what plays is saved"; `:trust` gates `:lua`, `:!` and unsafe commands in script clips; no
  project edits from playback; OSC ports are a machine setting; renders send no signals; the
  pattern extension becomes a custom kind with `:clip.flatten`.
- **No backwards compatibility** until a tagged release: the project format may change freely.
  Drop the hand-written `Deserialize` whose purpose was to keep old projects byte-identical: use
  the plainest serde shape that round-trips an UNKNOWN kind's data byte for byte (that part
  stays: a project must survive a missing extension). Open question 4 is moot. Still keep the
  error texts users read clear.
