# Smart articulations and dynamics: the `perform` extension

Author: SMART-ARTIC (design agent), 2026-11-21. No file of the repository changed.
Status: a proposal. The owner confirms section 10 before anyone builds it.

Research notes, same folder:
- `research-rules.md`: the KTH rule system, Todd, Widmer, Friberg; what is established.
- `research-mockup.md`: CC1/CC11/CC7/velocity/CC2/CC21 practice per library, orchestration idioms,
  dynamic mappings in notation programs.
- `research-datasets-tools.md`: datasets and their licenses; tools users like and dislike.

Read with: `extensions/articulations/README.md` (maps, `[linked]`, M2-123 attributes),
`extensions/notation/lua/notation/midi.lua` (the `wrote` stack: "a mark writes MIDI, the MIDI is
then free to change"), `scratchpad/media/DESIGN.md` (modifiers, seeds, Apply),
`docs/reference/completion.md`, `docs/reference/language-servers.md`, `paw.audition.try`.

---

## 0. The short version

- **A new extension, `perform`**, depends on `articulations` (and uses `musicops`, `notation`,
  `sections`, `drums`, `utau` when they are loaded). It reads the notes and writes a *performance*:
  articulations (the MIDI 2.0 attribute of each note), velocities, note lengths, small onset
  offsets, and controller lanes (CC1, CC11, CC2, CC21, CC64), each one through the instrument's
  map. The result is ordinary MIDI. The project plays without `perform` (rule 4).
- **Three layers, kept apart:**
  1. **Analysis** (pure Teal): phrases, metrical weight, melodic and harmonic charge, register,
     texture, section level, tempo in ms per note. No instrument.
  2. **Rules** (pure Teal): each rule reads the analysis and adds *abstract* contributions:
     loudness in dB, a length factor, an onset in ms, a tempo factor, vibrato and breath, and
     scores for articulation *families* (long, legato, short, detached, accented, tremolo…).
     Each contribution keeps its rule, its weight and a sentence: the "why".
  3. **Rendering** (instrument aware): the map of the track turns the abstract performance into
     MIDI. Its new `[perform]` table says which controller carries what (CC1 dynamics crossfade,
     CC11 expression, velocity for shorts, CC2 breath, CC21 vibrato), its curves, and how its
     articulations fit the families.
- **Articulation choice is a path, not a per-note guess.** Rules give each note a score for each
  articulation of the map. A small Viterbi pass picks the best sequence, with a cost for each
  change (a keyswitch that flips on every note is the classic mockup mistake). The cost is lower
  on a sampler that takes per-note attributes.
- **Templates are plain TOML** (`*.perf.toml`): a *style* (weights and parameters of the rules,
  the dynamic plan) and an *idiom* per instrument family (breath limits, bow lengths, which
  articulation at which tempo). The first set ships with sources. Users add their own in
  `~/.config/paw/perform/`.
- **Non-destructive by provenance, like notation's marks.** The MIDI is the truth; `perform`
  keeps beside it *how* it was made (`clip.meta.perform`: style, parameters, seed, scope) and on
  each value *what it wrote* (`note.meta.perform.wrote`, and a fingerprint of each generated
  lane segment). Run again: values still as `perform` left them are recomputed; values the user
  changed are kept ("user wins"); a lock (`\el`) pins a range. `:perform.bake` forgets the
  provenance (Blender's Apply). The seed is kept, never a second copy of the result.
- **The user**: `g=ip` performs the phrase (an operator, Vim's `=` "format", here "format the
  performance"), `g=ie` the clip, `\ee` the selection or the track, `:perform` over any Ex range.
  The result shows and plays at once as an *audition trial* (`paw.audition.try`): `Enter` or
  `\ey` keeps it (one undo step), `Esc` takes it back with no trace. A panel lists what changed
  per part and per aspect (dynamics, articulations, lanes, timing); `Space` switches one off
  before `Enter`.
- **Live expression** (owner's decision): `:perform.live on` for the project (or `\ei` for the
  track under the cursor) makes articulations and
  dynamics while you write, in insert mode, the score and step entry, inside the insert's undo
  step: one `u` takes back the notes and their expression. Under 3 ms per note; phrase-level work
  waits for the idle or `Esc`. A recorded take gets articulations and lanes after it ends (1.8).
- **"Why" everywhere.** The extension is also an in-process language server: `gK` on a note
  gives its rules ("spiccato: eighths at 138 bpm are 217 ms, below 250 ms"), `<Space>ca` gives
  actions on a selection ("Shape this phrase", "Make this run spiccato", "Add a breath here"),
  hints mark idiom problems (a horn phrase 14 s long with no rest). A completion source suggests
  velocities and articulations for notes you just entered.
- **Plan**: 14 parts of 30–90 min (section 9). The first useful slice is parts P1–P6:
  analysis, five rules, the dynamics renderer, the trial, the provenance. Articulation choice and
  the LSP come next.

Words used here: a **performance** is what `perform` writes. A **rule** makes contributions. A
**style** is a set of rule weights and parameters. An **idiom** is what an instrument family can
play. A **profile** is the `[perform]` table of a map: how this instrument hears the abstract
values. **Generated** means written by `perform` and not changed since; **owned** means changed
by the user.

---

## 1. What the user does

Terminal first. Each step works in the terminal; the window shows the same scene.

### 1.1 The first time: a string line in thirty seconds

1. Load the extensions: `:ext.load articulations`, `:ext.load perform`. Bind a map to the violin
   track: `:art.map examples/violin-section` (or a plugin's map, bound by itself).
2. Open the clip in the piano roll. Put the cursor on the first phrase. Type `g=ip`.
3. paw shows the result at once and plays the phrase from one bar before it (as `gh` does). The
   notes have tags (`leg`, `spc`), new velocities, and the strip under the roll shows CC1. The
   message line says:
   `perform: phrase of 14 notes · romantic-strings · 3 articulations, CC1 CC11, velocity · Enter keeps, Esc drops, \e? why`
4. `Enter` keeps it: one undo step, named `perform phrase (romantic-strings)`. `Esc` takes it
   back. `u` after `Enter` undoes it as any edit.
5. Correct with the normal keys: `\a` on a note to change its articulation, `]` `[` on a note for
   its velocity, `\c` to draw the dynamics lane. Each correction is the user's: a later `g=`
   keeps it.

### 1.2 Keys

The operator and the keys of the piano roll are on `g=` and `<localleader>e` (`\e`, free in the
piano roll, the score and the arrange view today). They obey the key rule: no motion changes,
`+ -` and `] [` keep their meaning, `K` describes, `Esc` cancels.

| Keys | View | Effect |
| --- | --- | --- |
| `g={motion}` | roll, score, arrange | perform what the motion covers: `g=ip` the phrase, `g=ie` the clip, `g=is` a section (with `sections`), `g=it` the track (arrange). Visual: `g=` on the selection. Doubled, as every operator: `g==` the row (roll: every note of the pitch under the cursor; arrange: the track), `3g==` three rows or tracks. The whole clip in the roll is `g=ie` |
| `\ee` | roll, score, arrange | the same as `g=` on the selection, else on the phrase at the cursor (roll) or the clip (arrange) |
| `\ed` `\ea` `\el` `\et` | roll, score, arrange | only one aspect: **d**ynamics (velocity and dynamic lanes), **a**rticulations, **l**anes other than dynamics (breath, vibrato, pedal), **t**iming (lengths and onsets) |
| `\es` | all three | choose the style of the track from a list (`:perform.style`). The list plays the phrase at the cursor with each style as the highlight rests on it, as `\a` does |
| `\e+` `\e-` | all three | more or less of it: the *amount* of the performance at the cursor, 0 to 200 % in steps of 25 (re-renders the trial or the kept performance; one undo step). A count repeats the step: `3\e+` is 75 % more, as `6 Ctrl-x` is six steps |
| `\e!` | all three | pin (lock) the notes of the selection, or the note under the cursor: `perform` never changes them. Again: unpin. A switch: a count is ignored |
| `\e?` | all three | why: a page with each rule that changed the note under the cursor, with its amount and sentence (`:perform.why`) |
| `\er` | all three | perform again with the next seed (only the humanize rules draw numbers). A count repeats it: `3\er` moves three seeds, as `pattern`'s `\tr` does |
| `\eb` | all three | bake: forget how the performance was made (`:perform.bake`). The MIDI stays |

During a trial (the performance shows but is not kept):

| Keys | Effect |
| --- | --- |
| `Enter`, `\ey` | keep the checked aspects and parts, as one undo step |
| `Esc` | drop the trial: the project is as before, no undo step |
| `j` `k` in the panel, `Space` | choose a part or an aspect, check or uncheck it: the trial changes at once |
| `\e+` `\e-`, `\er`, `\es` | as above, on the trial |
| `gh` | hear it again from one bar before |

Why an operator: the musician thinks "this phrase", "this section", "the whole cue", and the
grammar already has text objects for them (`ip` from `musicops`, `is` from `sections`, `ie`,
`ib`). `=` snaps to the grid in paw; `g=` is free and reads as "format", Vim's meaning for `=`.

### 1.3 Commands

| Command | Effect |
| --- | --- |
| `:perform [aspects] [style=name] [amount=80] [seed=n]` | perform over a range (`:'<,'>perform`, `:%perform`, `:t/Strings/perform`, `:g/art=sus/perform dynamics`) or the selection. Aspects: `all` (default), `dynamics`, `articulations`, `lanes`, `timing`. Opens the trial |
| `:perform!` | the same, kept at once (no trial): for scripts and macros |
| `:perform.style [name]` | the style of the track (saved in `track.meta.perform.style`); alone, the list |
| `:perform.styles` | every style and idiom, where it comes from, and its source |
| `:perform.why` | the page of rules for the note under the cursor |
| `:perform.lock`, `:perform.unlock` | over a range or the selection |
| `:perform.bake [range]` | forget the provenance |
| `:perform.again` | perform every performed clip again with its own settings: what the user changed stays (after a change of style, map, or tempo) |
| `:perform.check` | idiom hints of the range into the quickfix list (the same as the language server's diagnostics) |
| `:perform.plan` | the dynamic plan of the song: one row per section, its level (`mp`, `f`), editable as text (section 1.6) |
| `:perform.marks` | write the performance's dynamics into the score as marks and hairpins (with `notation`) |

### 1.4 The panel of a trial

A float under the roll (a `paw.ui` list; the same scene in the window):

```
perform · romantic-strings · amount 100 % · seed 1                      Enter keep · Esc drop
 [x] Violins I    bars 1-8   art: leg 9 · spc 4 · stc 1   vel 14   CC1 ▁▂▄▆▇▆▄▂  CC11 flat 100
 [x] Violins II   bars 1-8   art: leg 6 · spc 8           vel 14   CC1 ▁▂▃▅▆▅▃▂
 [ ] Celli        bars 1-8   (you changed 5 notes here: kept)      vel 9    CC1 ▂▃▄▄▃▂
     dynamics [x]  articulations [x]  lanes [x]  timing [ ]
```

- One row per part (a track in the range). The aspects row applies to all parts.
- The sparkline is the dynamics lane in cells (the strip glyphs the roll uses).
- `K` on a row gives the counts of each rule in that part.

### 1.5 Suggestions while you write

- **Live expression** (the owner's decision, section 12): with `:perform.live on`, the notes get
  their articulation and dynamics *while you write them*, in the same undo step as the insert.
  Section 1.8 describes it. It replaces the "smart pen" of the first draft.
- **Completion.** `perform` is a source of `paw.complete` (priority below `continue` and MIDI
  LSP). While live expression is **off**, after notes are entered and the idle time passes, it
  offers one item: "perform the phrase just entered", with `velocities`, `attrs` (a small generic
  extension of the item, see section 4.1) and `controls`. `Tab` accepts it, `Esc` dismisses it.
  It never offers notes. While live expression is on, the source offers nothing (the notes already
  have it): one engine, two ways to deliver it (1.8.7).
- **Code actions** (`<Space>ca`) on a selection or a note: "Shape this phrase (romantic-strings)",
  "Articulate only", "Make these notes spiccato: eighths at 138 bpm", "Add a breath before bar
  5", "Crescendo to the next downbeat". Each is a workspace edit: one undo step.
- **Diagnostics** of severity `hint`, from the idiom (section 2.6): never errors. `]d` goes to
  them, `<Space>ca` fixes them.
- **Hover** (`gK`): the "why" of the note, short. `\e?` opens it as a page.

### 1.6 The song as a whole: the dynamic plan

A cue needs a shape over minutes, not only phrase arches. `:perform.plan` opens a text buffer
(`paw://perform/plan`):

```
# section   level   shape          note
Intro       p       swell
Verse       mp      arch
Chorus      f       sustain        climax at bar 41
Bridge      mf      dim
Outro       pp      fade
```

- The sections come from the `sections` extension; without it, from markers; without them, the
  plan has one row (the whole song) and phrases do the rest.
- The rows are defaults that the plan rule (section 2.4, `section-level`) reads. A dynamic mark
  in the score, where there is one, wins over the plan (section 4.2).
- `:w` writes the plan into `project.meta.perform.plan`: one undo step.
- With no plan, `perform` proposes one (`:perform.plan auto`): the level of each section from its
  note density, register and the number of sounding tracks (a texture measure). It shows as a
  trial like any performance.

### 1.7 Many tracks at once

`:%perform` over the whole song, or `g=is` on a section in the arrange view, performs every track
in the range in one trial and one undo step. Tracks with no map get the dynamics and timing that
need no map (velocity, CC11 if the style says so, lengths). The panel lists them; drum tracks go
to the drum rules (section 4.4), vocal tracks to the vocal rules (4.3).

Balance between sections (strings under a horn melody) is a rule (`texture-balance`, section
2.4): a part that is not the melody of its moment gets less level, by its role in the analysis.

---

### 1.8 Live expression: while you write

The owner decided (section 12) that expression can be made **while** MIDI is written, as an
option that a command switches on and off.

#### 1.8.1 The command, the option, the key, the status line

| Command, key | Effect |
| --- | --- |
| `:perform.live on`, `:perform.live off`, `:perform.live` (alone: toggle) | for the project |
| `:perform.live on track`, `:perform.live off track`, `:perform.live default track` | for the track under the cursor only, for scripts; `default` follows the project again |
| `:perform.live on aspects=art,dyn` | which aspects run live: `art` (articulations), `dyn` (velocity and the dynamics lane), `lanes` (breath, vibrato, pedal). Default `art,dyn,lanes`. `timing` is never live (1.8.2) |
| `\ei` | toggle for the **track under the cursor**, in the piano roll, the score and the arrange view (`i`: "while inserting"). It sets the track's value to the opposite of what the track has now (its own value, or the project's). A key acts on what is under it. A count is ignored, as for the other switches in paw (`gzL`, the scale lock): the keymap passes `ctx.count` and a switch does not read it |
| `:set perform_live`, `:set noperform_live` | the same as the command, for the project |

- **The option.** `paw.opt.perform_live` (`false` by default) is the project's value, saved in
  `project.meta.perform.live` (`{ on = true, aspects = { "art", "dyn", "lanes" } }`), so a project
  opens as it was left. A track's value, in `track.meta.perform.live`, wins over it. A change of
  either is one undo step with a message: `live expression on (romantic-strings): art, dyn, lanes`.
- **The key** obeys the key rule: `\ei` is on the local leader of the views where notes are written,
  and it is a switch of the track under the cursor, not a motion or a value. A count means
  repetition in paw, never scope, so no count chooses between the track and the project: the
  project's setting is the command and the option. `~` stays "switch a property of the note under
  the cursor".
- **The status line.** A component `perform` (`paw.statusline.component`) shows `≈live` while live
  expression is on for the track of the cursor, `≈live·art` when only some aspects are on, and
  `≈live…` while work waits for the idle (1.8.3). Off: nothing shows. In the window, the same text
  is in the status bar, and a click on it toggles the track, as `\ei` does.
- Live mode needs nothing else: with no map on the track, only `dyn` runs (velocity), as `g=` does.

#### 1.8.2 What happens while you write

One engine (sections 2–3) runs on a **window**: the notes around the change, inside the phrase
that is being written. Three moments:

| When | What runs | Where the edits go |
| --- | --- | --- |
| **each note** (the key that adds it, in the same turn) | the local rules on the new note and its two neighbours: tempo articulation (R16), repeated notes (R10), legato line (R17), leap articulation (R9), duration contrast (R6), metrical accent (R7), written marks (R24); the articulation path (2.5) over the open window; the velocity from the level the phrase has so far | an `edit.before` handler: its edits join the step of the key, so they join the insert (1.8.4) |
| **idle** (`paw.opt.perform_live_idle_ms`, 600 ms with no key, while still in insert mode) | the phrase-level rules: the phrase arch over the phrase as written so far, punctuation, harmonic and melodic charge, the dynamics lane, breath, vibrato and pedal lanes | joined to the insert's step (`api.undo_join`) |
| **`Esc`** (the end of the insert) | a flush: what the idle did not do yet, on the last phrase, with its real end now known (the arch's descent, the last note) | in the `Esc` turn, so in the insert's step |

Why a note's articulation can change after it was entered: legato is a property of a note *and the
next one*. The note before the new note is in the window, so the previous note can turn from `sus`
to `leg` when a stepwise note follows it. The roll redraws both; nothing else moves.

**Timing is never live.** Live mode does not change a start or a length while you write: it would
move the notes under the cursor and fight the grid. Lengths for legato overlap are written only by
`g=` or `\et`. (Rubato while writing is an open question for later, not now.)

Where notes are written:

| Entry | What live mode does |
| --- | --- |
| **insert mode in the piano roll** (keys, the keyboard as a piano `I`, a click) | as above |
| **notation entry** (the score's insert, `i` by name) | the same: the score's edits are MIDI edits of the clip, in insert mode. A mark typed in the score (`\d p`, a slur, a staccato) is a constraint at once (R24): the next notes follow it |
| **step entry** (a MIDI keyboard while insert mode is on, one note or chord per step) | the same, per step. The notes of a chord that arrive in one turn are one event: the window holds the chord |
| **a paste, an operator, a snippet, `:g`, a script** | nothing: these are not "writing notes". `g=` performs them when the user asks |
| **MIDI recording** | after the take ends, only articulations and lanes (1.8.6) |
| **a pattern clip** | nothing (it follows its text) |

Scope: the phrase being written, never the whole clip. A phrase is closed by a rest longer than
`musicops_phrase_rest` or a slur end. Notes before the window keep what they have.

#### 1.8.3 Speed

Rule 7: a key stays well under 100 ms. The budget, measured in `bench/perform.lua`:

| Work | Budget (p95, a 2,000-note clip) |
| --- | --- |
| each note (the `edit.before` handler) | **under 3 ms** |
| the idle pass on one phrase (up to 64 notes) | under 10 ms, in one slice |
| the `Esc` flush | under 15 ms |
| a longer phrase at idle | slices of 10 ms on the idle loop |

How the analysis stays incremental:

- **A cache per clip**, kept between keys: the features of each note (2.3), the phrase boundaries,
  the beat weights and the path's state (the best cost of each articulation at each note). It is
  keyed by note id. The clip's version tells when it is stale.
- **A dirty window.** An insert, a delete or a move marks the notes from the boundary before the
  change to the boundary after it. Only those get new features. A new boundary (a rest made longer)
  splits a phrase; nothing outside the two halves runs.
- **The path from a fixed entry.** Viterbi starts from the articulation of the note before the
  window (fixed, not recomputed) and runs over at most 16 notes. 16 × 12 × 12 is 2,304 steps.
- **Harmony** comes from `paw.harmony`, which reads again only when the project changes and costs
  almost nothing per call. Charges (R4, R5) wait for the idle, when the new chord is read.
- **Deferred to the idle**: every rule whose result depends on the end of the phrase (arch,
  punctuation, final ritard is not live at all), every lane, the harmony rules, breath. The
  per-note pass writes velocity from the *rising* half of an arch: a phrase that is not finished
  has no descent yet.
- If a per-note pass ever passes 3 ms (the clip is huge, the machine is busy), it writes only the
  articulation and leaves the rest to the idle; `:perform.live` reports the slow passes it counted.

#### 1.8.4 Undo

- An insert from `i` to `Esc` is one undo step (FX1: `keymap.dispatch` joins each key's edits to the
  step the insert made first, with `api.undo_join`). The per-note edits of live mode are made in the
  same turn as the key (`edit.before`), so they join that step with no extra work.
- The idle pass is a turn with no key. It calls `api.undo_join(step)` with the insert's step. That
  needs one small generic getter in the core: `paw.keymap.insert_step()` (the `insert_undo` that
  `keymap.lua` keeps today as a local). The `Esc` flush runs in the `Esc` turn.
- So **one `u` takes back the notes and their expression together**, and redo brings both back.
- Live mode ignores the turns of undo and redo (it never answers an undo with edits).
- If the insert's step is no longer the current step when an idle pass would run (the user did
  something else, the transport started), the pass is dropped, never made a step of its own. The
  phrase is marked unfinished: a `hint` diagnostic "expression unfinished: `\ee`" on it.
- A single note added outside insert mode (a click in normal mode) is one step already; its per-note
  pass joins it the same way.

#### 1.8.5 User wins, locks, deletes and moves

Live mode uses the provenance of section 3, with no exception:

- It writes only values that are **generated** or **new**: a note it never touched, or a value still
  as it wrote it. A value the user set is **owned** and never overwritten: a velocity set with `]`,
  an articulation set with `\a`, a lane drawn with `\c`, a locked note (`\e!`).
- What a new note already has counts too:
  - a note played on a MIDI keyboard has the velocity the user played: that velocity is owned
    (live mode still gives it an articulation, and its level feeds the phrase);
  - a note entered from the computer keyboard has the default velocity (`paw.opt.velocity`): that is
    not a choice, so live mode may write it;
  - the articulations pen (`:art.pen`, `\a` in insert mode) is the user's choice: notes entered with
    a pen keep its articulation, and live mode writes only their dynamics.
- **A deleted note** takes its provenance with it. Its neighbours are in the dirty window: the note
  before it can stop being legato. Generated values there are computed again; owned ones stay.
- **A moved note** (same id) keeps its `wrote`. Its old and its new place are both dirty windows.
  Its own generated values are computed again (its articulation can change at the new tempo or next
  to a repeated pitch).
- **A changed pitch or length**: as a move, for that note and its neighbours.
- These answers to deletes and moves run only while live mode is on. Off, a later `g=` or
  `:perform.again` does the same work in one pass.

#### 1.8.6 Recording

*Recommendation, built this way:* **no expression during the take; after the take ends, only
articulations and lanes.**

- During a take, nothing runs: the musician hears and plays what is there, the kernel records
  without Lua answering every note, and a take that is discarded costs nothing.
- When the take ends (the transport stops, or a loop take closes), live mode runs once on the new
  notes of the take, on the idle, and joins the take's undo step (the recorder already joins the
  take into one step, as `defaults/transport.lua` does with `api.undo_join`).
- What it writes: **articulations** (when the track has a map and the notes have none) and the
  **lanes** that the take does not have (no CC1 recorded: a dynamics lane from the played
  velocities; breath for winds). It never writes velocities, starts or lengths of a recorded take:
  they are the player's, so they are owned from the start.
- `paw.opt.perform_live_record` = `"art,lanes"` (default), `"off"`, or `"all"` (for a take played
  stiffly on purpose, to be performed like a typed line).

#### 1.8.7 Live mode, the smart pen and completion

- The **smart pen** of the first draft and live mode are the same thing: the smart pen is removed,
  and live mode replaces it. `paw.opt.perform_pen` does not exist.
- The **completion item** stays, and differs in one way: it *proposes* (a ghost that writes nothing
  until `Tab`); live mode *writes* (and undo takes it back with the notes). Both use the same engine
  and give the same result for the same notes. While live mode is on, the item is not offered, so
  the two never show the same thing twice. Off, the item is how a user who does not want live mode
  gets the same result on request.
- **`g=`** stays the full performance: timing, the whole phrase or clip, the trial with its panel.
  Live mode is the subset that is safe while typing.

---

## 2. The model

### 2.1 The pipeline

```
notes, meter, tempo, key, chords, sections, marks, plan        (inputs, read only)
        │
        ▼
   analyze()  ──────────────▶ Features per note and per phrase        (pure, no instrument)
        │
        ▼
   rules (ordered)  ─────────▶ Contributions { rule, aspect, value, weight, why }
        │                       summed per note into an abstract Performance
        ▼
   choose_articulations()  ──▶ a path over the map's articulations (Viterbi, section 2.5)
        │
        ▼
   render(profile)  ─────────▶ MIDI: attrs, velocities, lengths, onsets, controller moves
        │
        ▼
   merge(provenance)  ───────▶ only generated values change; owned and locked stay (section 3)
        │
        ▼
   paw.audition.try(edit)  ──▶ the trial; keep = one undo step
```

Each stage is a pure function of its inputs, with one exception: the humanize rules draw from a
named random stream (`seed`, section 2.4). The same inputs and seed give the same MIDI on every
machine. A test can feed each stage alone.

### 2.2 Inputs

| Input | From | Used by |
| --- | --- | --- |
| notes (pitch, start, length, velocity, attr, meta, id) | the clip | all |
| meter, bar lines | the tempo map (time signatures) | metrical weight, phrase ends |
| tempo (bpm at each beat) | the tempo map | ms per note: the tempo rules for shorts, breath, tremolo |
| key, chords, numerals | `paw.harmony.key`, `paw.harmony.chords` | melodic charge, harmonic charge, cadences |
| phrases | `musicops.phrases` (rests), then boundaries (2.3) | phrase arch, punctuation, breath |
| sections and their names | `sections` extension, else markers | section level, the plan |
| written marks: dynamics, hairpins, slurs, articulations, techniques, tempo text | `notation` clip meta (`meta.notation.marks`, `note.meta.notation.art`), also MusicXML import | constraints (4.2) |
| the instrument | the track's map: `family`, `range`, `comfortable`, articulations with `class`, `[linked]`, `[perform]` | idioms, render |
| the other tracks that sound | the clips of the project in the range | texture, role (melody, bass, inner, pad), balance |
| the style and the amount | `track.meta.perform`, else the project's, else the family default | all rules |

### 2.3 Analysis: features

`perform.analyze(ctx): Analysis`, in Teal, about 400 lines. For each note:

| Feature | Meaning | How |
| --- | --- | --- |
| `ioi_ms`, `len_ms` | time to the next onset, length, in ms at the local tempo | tempo map |
| `beat_weight` | 0..1, the metrical weight of its onset | the meter's hierarchy: downbeat 1, half bar 0.75, beat 0.5, eighth 0.25, sixteenth 0.125; syncopation flag when a weak onset holds over a stronger one |
| `phrase`, `phrase_pos` | the phrase id; 0..1 position in it; first, last | 2.3.1 |
| `interval_in`, `interval_out` | semitones from the note before, to the note after in the same voice | voice = the skyline (top line) for a melody track; each pitch class line for polyphony is not attempted (see risks) |
| `leap` | `abs(interval) >= 5` (a fourth or more) | |
| `repeated` | the same pitch as the note before | |
| `melodic_charge` | 0..6.5, Friberg's table: distance of the pitch from the root of the chord on the circle of fifths | `paw.harmony.at(beat)` |
| `harmonic_charge` | the chord's charge relative to the key (Friberg/Sundberg) | `paw.harmony.chords`, key |
| `cadence` | `V-I`, `IV-I`, `V-vi`, half cadence on `V`: a flag on the chord's last note | numerals |
| `register` | 0..1 in the instrument's range (the map's `range`), else in 21..108 | |
| `role` | `melody`, `bass`, `inner`, `pad`, `rhythm` | the track's highest line against the others that sound; a track name or a `role` in the plan wins |
| `density` | notes per second in a window of two beats | |
| `texture` | the number of tracks that sound, 0..1 | |
| `section`, `section_level` | the section and its plan level | `sections`, the plan |
| `written` | the marks that hold at the note (dynamic, hairpin, slur, articulation mark, technique) | notation |

#### 2.3.1 Phrases

1. Rest boundaries from `musicops.phrases(notes, rest)` (a rest longer than half a beat, an option).
2. Inside a long phrase (more than `phrase_max` beats, default 8 bars at 4/4), the **Local Boundary
   Detection Model** (Cambouropoulos 2001) proposes boundaries where the interval and IOI
   profiles change most; the strongest boundary near a cadence or a bar line of a 2/4/8 bar group
   wins.
3. A written slur end (notation) is a phrase boundary; a written slur makes its notes one phrase.
4. Two levels are kept: **phrases** (2–8 bars) and **sub-phrases** (1–2 bars). The phrase arch
   rule runs on both, as Friberg's phrase arch does, with smaller amounts on the lower level.

The user sees the phrases: `\e?` on a note names its phrase ("phrase 3, bars 9–12, the note is at
70 %"), and `ip` in the roll uses the same boundaries when `perform` is loaded (it gives
`musicops` its boundaries through an option, not a second text object).

### 2.4 Rules

A rule is a Teal record:

```lua
local record Rule
   name: string                 -- "phrase-arch"
   aspects: {Aspect}            -- what it touches: "dyn", "len", "onset", "tempo", "art", "vib", "breath"
   default_k: number            -- its default weight (KTH's k)
   params: {string:number}      -- its defaults; a style changes them
   source: string               -- where it comes from (a citation)
   apply: function(a: Analysis, i: integer, p: Params, out: Contributions)
end
```

`Contributions:add(aspect, value, why)` records the rule's name and weight with each value. The
`why` is a short sentence with the numbers that caused it. Rules run in a fixed order; a rule can
read the contributions before it (`final-ritard` reads the tempo so far).

Combination, per note:

- **Loudness** (`dyn`) in dB, summed (KTH sums sound-level deviations in dB). The sum is clamped to
  the style's range and then mapped to the dynamic scale (2.7).
- **Length** (`len`) as a factor of the written length, multiplied. A factor below 1 is a gap
  (detached), above 1 an overlap (legato on an instrument that needs it).
- **Onset** in ms, summed, clamped to ±40 ms (more is a rhythm change, not an expression).
- **Tempo** as a factor of the local tempo, multiplied; written as onsets (2.8).
- **Articulation scores** per family, summed into the emission scores of 2.5.
- **Vibrato**, **breath**: values 0..1 for the lanes.

The first set of rules. Each has a source (see `research-rules.md` for the citations), an aspect,
and a test that guards it (section 7). "Established" means replicated in several studies;
"practice" means mockup and orchestration practice rather than measured performance.

| # | Rule | Aspect | What it does | Source | Status | Default k |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | `section-level` | dyn | the plan's level of the section (or the written dynamic) is the base of each note | the plan; notation | input | 1 |
| R2 | `phrase-arch` | dyn, tempo | louder and faster to a peak (default at 60–70 % of the phrase), softer and slower to its end, on the phrase and sub-phrase levels (two levels only: deeper levels are rarely seen in performances) | Todd 1985/1992; Friberg 1995 [K1, K4] | established (phrase-final slowing); the exact parabola is a model | 1 |
| R3 | `high-loud` | dyn | louder with pitch, in melodies of voice, winds and brass (KTH applies it less to keys and strings) | KTH [K1]; also found by Widmer and basis models [K6] | some support; no published dB/semitone: we set 2 dB per octave and tune by ear | 0.5 |
| R4 | `melodic-charge` | dyn, len, vib | notes far from the chord root on the circle of fifths louder, a little longer, more vibrato | KTH [K1] (preferred k ≈ 1.4 in its listening tests) | weak: effects near the threshold of hearing, needs a right chord reading | 0.5 |
| R5 | `harmonic-charge` | dyn, tempo | crescendo toward charged chords, relaxation on the tonic | KTH [K1] (preferred k ≈ 1.2) | weak, and it conflicts with the phrase arch [K1]: off in most styles | 0 |
| R6 | `duration-contrast` | dyn, len | short notes shorter and softer, long notes longer and louder (about 5 % on eighths at k = 1; preferred k ≈ 1.6) | KTH [K1]; Gabrielsson; Widmer TL2 [K5] | established | 1 |
| R7 | `metrical-accent` | dyn | the beat weight adds 0..+2 dB (more in dance styles, less in legato lines) | practice | practice | 0.5 |
| R8 | `punctuation` | len | a micro-pause at a melodic gesture boundary: the last note before it shortened (KTH's rule matched 66–72 % of the pauses of performers) | Friberg et al. 1998 [K3] | established | 1 |
| R9 | `leap-articulation` | len | a gap before a leap (non-legato) in detached styles; legato kept across steps (preferred k ≈ 1.9) | KTH [K1]; rediscovered by Widmer as AS3 ("a break after a note before an upward leap larger than a fourth") [K5] | established (two methods agree) | 1 |
| R10 | `repeated-notes` | len, art | repeated notes are detached, never legato: a legato patch cannot repeat a pitch | library practice (legato patches play transitions between pitches) | practice; a hard constraint in 2.5 | 1 |
| R11 | `final-ritard` | tempo, len | the last phrase of a section or the piece slows by the runner model `v(x) = [1 + (w^(q-1) − 1)·x]^(1/q)` with q = 3 (constant braking power), w ≈ 0.3 to be checked by ear; the last note longer | Friberg & Sundberg 1999 [K2] | established (existence and place); the shape is a model | 1 |
| R12 | `cadence-ritard` | tempo | a small slowing on a perfect cadence that ends a phrase (not a section) | phrase-final lengthening [K1, K4] | established, small | 0.5 |
| R13 | `melody-lead` | onset, dyn | the melody of a piano texture 10–30 ms early and louder | Goebl 2001 [D1] | established for piano | style |
| R14 | `texture-balance` | dyn | a part that is not the melody of its moment is lower by its role: inner −4 dB, pad −6 dB, bass −2 dB | orchestration balance (practice) | practice | 1 |
| R15 | `long-note-swell` | dyn (lane) | a note of more than about 1.5 s on a long articulation gets a lane shape: a small swell (messa di voce) or a decay, by style ("for long notes, crossfade on CC1 and add a decrescendo at the end", VSL) | practice [M4]; Todd's arch at note level | practice | 1 |
| R16 | `tempo-articulation` | art | short notes by their duration in ms (2.4.1) | violin pedagogy and library practice [M6] | practice, the thresholds are ours and tuned by ear | 1 |
| R17 | `legato-line` | art, len | a stepwise line of notes that touch, under a slur or in a cantabile style, legato: one voice only, the length factor that the library needs (overlap) | practice | practice | 1 |
| R18 | `accent-from-meter` | art | a marcato or accented short on syncopations and the downbeat of a phrase in "epic" styles | practice | style only | 0 |
| R19 | `tremolo-sustain` | art | a long note under a crescendo in a "tension" style becomes tremolo (string families only) | practice | style only | 0 |
| R20 | `breath` | breath, len | a wind or voice phrase longer than the idiom's breath limit gets a breath (a shortened note) at the best boundary inside it | practice; idioms | practice | 1 |
| R21 | `vibrato-by-length` | vib | vibrato depth 0 on short notes, rising over the first 200–400 ms of a long note, a little more at the phrase peak | practice | practice | 1 |
| R22 | `pedal` | lanes | piano: CC64 down just after each chord change, up just before the next (a legato pedal), off in staccato passages | practice | practice | 1 |
| R23 | `humanize` | onset, dyn | small random offsets (named stream, seed), limited, drawn per voice, near the beat | practice; Ableton's groove pool [D2] | practice | 0.5 |
| R24 | `written-marks` | all | the written dynamics, hairpins and articulation marks are constraints (4.2): they set the base and veto contrary choices | notation | input | 1 |

As in KTH, k = 0 turns a rule off, a negative k inverts it, and contributions add (dB, ms) or
multiply (length and tempo factors). KTH's listeners preferred moderate k (about 1 to 2) and found
rules overdone at high k [K1]; our defaults are at or below 1 for that reason. Rules marked *weak*
(R4, R5) and Todd's strict "faster is louder" coupling (Windsor & Clarke 1997 found it a partial
account [K4]) are in the library but low or off by default.

#### 2.4.1 Shorts by duration (R16), the first table

| Note length at the local tempo | Strings | Woodwinds, brass |
| --- | --- | --- |
| below 110 ms (sixteenths above ~136 bpm) | spiccato, else a fast short; détaché in tremolo-like runs | double tongue (style), else staccato |
| 110–250 ms (eighths 120–270 bpm, sixteenths 60–136 bpm) | spiccato | staccato |
| 250–450 ms | staccato, or détaché in a cantabile style | staccato, tenuto by style |
| 450–600 ms | détaché / sustain short (by style) | tenuto |
| above 600 ms | a long articulation (sustain, legato by R17) | sustain, legato by R17 |

The violin sources disagree on where bounced strokes give way (about 100 bpm for sixteenths in one,
120–140 in another [M6]); a sample library's spiccato patch also plays well slower than a player's
bounce would. The table is a starting point for the listening notes (7.3), not a fact.

What this first set leaves out, on purpose:

- **Rubato by learning** (Widmer's and Cancino-Chacón's basis models): they need fitted
  parameters from data that is NC-SA (MAESTRO, ASAP). Not shippable (section 5.4).
- **Intonation rules** (KTH's mixed intonation): out of scope; MIDI 2.0 pitch per note could do it
  later.
- **Swing and inégales** go to the groove templates (4.4), not to the rules of lines.

### 2.5 Choosing articulations: a path

The rules give each note `i` a score `e_i(f)` for each articulation **family** `f` (sustain,
legato, détaché, staccato, spiccato, marcato/accented, tenuto, pizzicato, tremolo, trill, effect).
The map says which of its articulations belong to which family (the M2-123 classification and
subclass give it: `10.2` legato, `11.5` spiccato; `[perform].families` can override). A family
the map does not have is not a candidate.

A **transition cost** `c(a, b)` makes the line consistent:

- `0` to stay in the same articulation;
- `switch` (default 2.0) to change, on a keyswitched instrument (`send = "change"`);
  `switch_attr` (default 0.5) when the device takes the attribute per note (the sampler, a MIDI 2.0
  CLAP plugin): changes are cheap there;
- `+∞` for what the instrument cannot do: legato into a repeated pitch; legato on a chord when the
  articulation is `mono = true`; an articulation outside its `range`.
- A *minimum run* (default two notes or one beat) for families that sound wrong alone (a single
  legato note).

Viterbi over the notes of each voice gives the best path; ties keep the current articulation (so
a second run changes nothing). The cost is O(notes × articulations²): 2,000 notes × 12
articulations is 288,000 steps, a few ms in LuaJIT.

The "why" of the choice keeps the winning family's top three contributions and, when the path
overrode the best single choice, says so: "spiccato (best alone: staccato, +0.4) kept with the run
to avoid a switch".

### 2.6 Idioms: what an instrument family can play

An idiom is a TOML table per family (strings, woodwinds, brass, voice, keys, plucked, percussion,
synth). It holds facts that rules read:

| Field | Strings | Woodwinds | Brass | Voice |
| --- | --- | --- | --- | --- |
| `breath_s` (longest phrase without a breath at mf) | none (bow changes: `bow_s`) | 8 (flute 6, oboe 10) | 8 (tuba 5, horn 10) | 8 |
| `breath_ms` (the gap a breath takes) | | 150 | 200 | 250 |
| `bow_s` (a long note at p before a bow change is audible) | 6 at p, 3 at ff | | | |
| shorts by duration | spiccato < 250 ms, staccato < 500 ms | staccato, double tongue below ~90 ms | staccato, double tongue below ~110 ms | |
| `tremolo` | yes | flutter-tongue (flute, clarinet in style only) | flutter (style only) | no |
| `legato_repeat` | no | no | no | no |
| `dynamic_range_db` | 35 | 30 | 40 | 30 |

The numbers are ours: rounded estimates to start from, not measured (the research found no source with breath or bow limits in seconds; see
`research-mockup.md`). They are defaults: the user changes them in a copy. The idiom makes hints
(section 4.1): "this horn phrase holds 14 s with no breath" with a fix "add a breath at bar 7".

### 2.7 Dynamics: from dB to controllers

The abstract loudness of a note is a **level** on one scale: `L` in 0..1 where 0 is the softest
the instrument plays (`ppp`) and 1 its loudest (`fff`). The written dynamics sit on it at fixed
points (`ppp` 0.05, `pp` 0.18, `p` 0.32, `mp` 0.45, `mf` 0.57, `f` 0.70, `ff` 0.84, `fff` 0.95),
the same order as notation's table (`M.DYNAMICS`). A dB contribution moves `L` by
`dB / dynamic_range_db` of the idiom.

The profile (`[perform]` of the map) then says what carries `L`:

```toml
[perform]
family = "strings"            # the idiom (falls back to the map's `family`)
dynamics = "cc1"              # what makes a long note louder: "cc1" (layer crossfade), "cc11", "cc2", "velocity", "none"
expression = "cc11"           # the second, slower controller: section balance and fades; "none"
shorts = "velocity"           # what makes a short note louder: "velocity", "cc1", "both"
velocity_on_longs = "attack"  # what velocity means on a long note: "attack" (accent of the start), "dynamics", "legato-speed", "ignore"
breath = "none"               # winds: "cc2"
vibrato = "cc21"              # or "none"; with `vibrato_curve`
curves = { cc1 = "0:0.1 0.5:0.55 1:1", cc11 = "0:0.55 1:1", velocity = "0:20 0.57:80 1:120" }
legato_speed = { by = "velocity", slow = 30, fast = 100 }   # libraries where velocity picks the legato transition
smooth_ms = 80                # the shortest ramp on a lane (no stepped CC1)
```

- A **long** articulation writes `L` on its `dynamics` controller as a lane: one point at each note
  start, interpolated with the curve shape of the rules (the swell of R15 adds points inside long
  notes), thinned so that no two points are closer than `smooth_ms` and no change is smaller than
  1/127.
- A **short** articulation writes `L` as velocity (the `velocity` curve).
- `expression` (CC11) carries the slow part only: the section level and the balance of R14, as a
  flat value per section or a slow ramp. So a user who rides CC1 for phrasing keeps an overall
  trim on CC11, and the reverse. This is the split that mockup practice uses (research notes).
- `CC7` is **never** written: it is the mixer's (the fader of the track in paw).
- When the map has `[linked] dynamics`, `perform` writes through it (its curves), so `\c` shows the
  performance as one curve and edits it as one.
- When the track has no map, a default profile applies: velocity for every note, CC11 for the
  section level only if the style asks it. It works on any synth.

The table of libraries (from `research-mockup.md`: V = read on the vendor's page or manual, S =
from a forum or a secondary source; the shipped profiles say "from the manual, not checked with the
plugin", as maps do):

| Library | Long notes: dynamics | Overall | Shorts | Velocity on longs | Other controllers | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| Spitfire (BBC SO, Symphony Orchestra, Albion; the current plugin) | CC1 | CC11 | velocity; the Dynamics fader has four velocity modes, one maps velocity to dynamics so CC1 moves shorts too | attack | CC7 gain, CC17 release, CC18 tightness, CC20 variation, CC21 vibrato, CC32 UACC articulation | V: BBC SO Pro manual [M1] |
| Orchestral Tools SINE (Berlin, Metropolis Ark) | CC1 "Dynamic XFade", default on longs, can be on for shorts | CC11 ("Instrument Vol. 2"; CC7 and CC11 together set the level) | velocity | layers and legato transitions by velocity on some | CC14 switches crossfade/velocity mode; CC3 vibrato style; CC64 sustain with retrigger | V: OT controller table [M2] |
| VSL Synchron | the Dynamics fader: CC1 or velocity, per instrument; "Velocity XF" switchable (off: a held note cannot change its layer) | CC11, a percentage of CC7 | velocity | dynamics when Vel. XF is off | (the Special Edition may crossfade on CC2: not verified) | S: VSL forum and recipes [M3] |
| EastWest Hollywood / Opus | CC1 | CC11 for sustain dynamics in "All VS" presets | velocity | in "All VS", velocity picks the legato behavior | (CC2, CC21: not found) | S: Sound On Sound review |
| Cinematic Studio Strings, Brass, Woodwinds | CC1 (three sampled dynamics) | CC11 (by analogy, not confirmed) | velocity, with about −60 ms delay | **legato speed** by the velocity of the new note: zones and delays differ between manual versions (0–64 / 65–100 / 101–127, or slow ≈ 333 ms, medium ≈ 250 ms, fast ≈ 100 ms) | vibrato by CC (con/senza) | S: manual copies, forums [M5]: the profile must be checked with the user's version |
| Generic SFZ / Decent Sampler / paw sampler | velocity (no crossfade) or the CC of `xf_cc` | CC11 if routed | velocity | dynamics | from `describe` | the instrument file |
| Piano (any) | velocity | | velocity | dynamics | CC64 | practice |
| Breath-driven winds (SWAM and others) | CC2 or CC11 (per product) | | CC2 | attack | vibrato on CC1 or CC21 | to check per product |

What the vendors agree on (V on two vendors, S on more): CC1 crossfades the layers of long notes;
CC11 is a second volume inside the patch; CC7 is set once (paw's fader does that job); velocity
drives shorts and attacks. "Use one dynamics controller per patch": mixing a keyswitch-driven short
and CC1 on the same notes confused CSS users [M5]. So the profile names exactly one `dynamics` and
one `shorts` controller per articulation class.

The **dynamic scale** of 2.7 against what notation programs send (velocities, for reference):

| Mark | ppp | pp | p | mp | mf | f | ff | fff |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| paw notation (`M.DYNAMICS`) | 25 | 38 | 52 | 66 | 80 | 96 | 112 | 124 |
| Sibelius 6.2 playback dictionary [S] | 20 | 39 | 61 | 71 | 84 | 98 | 113 | 127 |
| Dorico (one user's export; not fixed) [S] | 12 | 24 | 41 | 52 | 76 | 87 | 104 | 116 |
| MusicXML `dynamics` attribute: percent of f = 90 | | 41 % | | | | 100 % | | |

`perform` keeps notation's values for velocity on an unmapped track (one truth in paw), and the
level `L` points of 2.7 for controllers. The profile's `velocity` curve can bend it per library.

### 2.8 Timing: lengths, onsets, tempo

- **Lengths** are written on the note (`length`), as notation's gates do. A legato line on a
  library that needs overlap gets `len_factor` so that the note ends `overlap_ms` after the next
  starts (profile field, default 0).
- **Onsets** move the note's start by ms converted to beats at the local tempo. They never move a
  note across another note of its voice, and never more than 40 ms. A grid-locked style (pop, EDM)
  sets the onset aspect off.
- **Tempo**: the tempo map is one for the project. A phrase arch's tempo part on one track would
  pull the whole band. So:
  - In a performance of one track among others, the tempo contributions become **onsets**
    (micro-rubato inside ±40 ms) and lengths. The arch is then subtle, as an orchestral player
    inside an ensemble plays it.
  - `:perform tempo` on the **whole song** (all tracks) writes the tempo contributions of the
    melody into the tempo map: final ritards, cadence ritards, a fermata's hold. It is one
    aspect, off by default, and the trial shows the tempo lane. With `sections`, it is per
    section.
  - A delay of the map (`delay = "-80ms"`) is not the performance's: the kernel applies it, and
    `perform` never writes it into notes.

### 2.9 The output, in MIDI

| Output | Written as | Plays without `perform` |
| --- | --- | --- |
| articulation | `note.attr` (M2-123), sent by the map's downgrade map as keyswitches, CCs or programs, or as the attribute itself to a sampler | yes |
| velocity | `note.velocity` (7-bit, the core keeps more where MIDI 2.0) | yes |
| length, onset | `note.length`, `note.start` | yes |
| dynamics, expression, breath, vibrato, pedal | controller moves of the clip (`clip:controls()`), CC numbers from the profile | yes |
| per-note vibrato or dynamics on a sampler (optional) | controller moves with a `key` (per-note), when the profile says `per_note = true` and the device takes them | yes (MIDI 2.0 / CLAP note expressions) |
| tempo nuance (song only) | the tempo map | yes |
| the provenance | `clip.meta.perform`, `note.meta.perform` | ignored without the extension |

### 2.10 Teal types (in `extensions/perform/lua/perform/types.tl`)

```lua
local enum Aspect "dyn" "len" "onset" "tempo" "art" "vib" "breath" "pedal" end
local enum Family "sustain" "legato" "detache" "staccato" "spiccato" "accented" "tenuto"
                  "pizzicato" "tremolo" "trill" "effect" end

local record NoteFeatures
   id: integer; place: integer; pitch: integer; start: number; length: number
   ioi_ms: number; len_ms: number; beat_weight: number; syncopated: boolean
   phrase: integer; subphrase: integer; phrase_pos: number; first: boolean; last: boolean
   interval_in: integer; interval_out: integer; leap: boolean; repeated: boolean
   melodic_charge: number; harmonic_charge: number; cadence: string
   register: number; role: string; density: number; texture: number
   section: string; section_level: number
   written: Written
end

local record Contribution
   rule: string; aspect: Aspect; value: number; family: Family; why: string
end

local record NotePerformance
   level: number            -- L, 0..1
   len_factor: number; onset_ms: number; tempo_factor: number
   vib: number; breath: boolean
   scores: {Family:number}
   art: string              -- the chosen articulation id of the map, after 2.5
   because: {Contribution}
end

local record Style            -- read from *.perf.toml
   name: string; extends: string; source: string
   amount: number
   rules: {string:RuleSetting}          -- k and params per rule; enabled
   art_cost: ArtCost
   plan: {string:string}                -- section name pattern -> level
end
```

No `any`: TOML is read into these records by a checked reader that names the field and the file on
a mistake ("romantic-strings.perf.toml: rules.phrase-arch.k is a string, not a number").

---

## 3. Non-destructive by design

### 3.1 The choice: provenance over a live layer

Three designs were weighed:

1. **A live modifier at playback** (a transform in the engine that adds dynamics on the fly): the
   media design's live parts. Rejected: the project would not play the same without the extension,
   the piano roll and the score would show notes that do not sound as drawn, and the user could not
   correct one velocity with `]`. Users of every tool in the survey ask for editable MIDI, not a
   hidden layer (`research-datasets-tools.md` B4).
2. **A custom clip kind** that owns the "intent" and compiles MIDI: the clip-kinds design allows it.
   Rejected: every other extension (notation, articulations, musicops, the roll's keys) works on
   MIDI clips; a performed clip would stop being one.
3. **MIDI plus provenance** (chosen). `perform` writes ordinary MIDI and notes beside it what it
   wrote and how. This is the pattern notation already uses for marks (`meta.notation.wrote`:
   "the mark writes MIDI, the MIDI is then free to change, taking the mark away puts back only
   what is still as the mark left it"). It keeps the spirit of the media design: the *recipe*
   (style, parameters, seed, scope) is small saved data that can run again; Apply is `:perform.bake`.
   The one difference from the media design: the result is saved too, because MIDI is the truth
   and must play without the extension. The seed lets the result be made again, not replace it.

### 3.2 What is kept

On the clip, `clip.meta.perform`:

```lua
{
  version = 1,
  runs = {                                 -- each performance kept on this clip, in order
    { id = 7, style = "romantic-strings", amount = 1.0, seed = 1, aspects = { "dyn", "art", "lanes" },
      from = 0, to = 32,                   -- beats of the clip it covered
      engine = "perform 0.1.0", map = "examples/violin-section" },
  },
  lanes = {                                -- the generated part of each lane it wrote
    { cc = 1, from = 0, to = 32, run = 7, digest = "9f3a…" },  -- a digest of the moves it wrote there
  },
  locks = { { from = 12, to = 14 } },      -- ranges the user locked (beats of the clip)
}
```

On each note it changed, `note.meta.perform`:

```lua
{ run = 7,
  wrote = { velocity = { v = 74, from = 90 }, attr = { v = "11.5", from = nil }, length = { v = 0.42, from = 0.5 },
            start = { v = 3.98, from = 4.0 } },
  lock = nil }                              -- true when the user locked the note
```

- `from` is the value before the first performance. `:perform.undo-run` (and taking a run away) puts
  back `from` only where the value is still `v`, as notation does.
- The digest of a lane covers its moves in the range, in order, rounded to 1/127. A lane range whose
  digest no longer matches was edited by the user: it is owned.

The size: about 60 bytes per changed note in `data.json` of the clip. A 2,000-note clip adds
120 kB. The owner's project-as-files design keeps clips in their own files, so this stays with the
clip. A cheaper form (only `v`, the run id, no `from`) is an open question (10.6).

### 3.3 User wins

When `perform` runs again over notes it performed before:

| The value now | What `perform` does |
| --- | --- |
| equal to the `v` it wrote | **generated**: it recomputes and writes the new value |
| different from `v` | **owned** by the user: it keeps the value, drops `wrote` for it, and counts it in the panel ("5 notes you changed: kept") |
| the note is locked, or in a locked range | keeps everything |
| the note has no `meta.perform` (new, or never performed) | writes it, if it is in the range |
| a lane range whose digest matches | rewrites it |
| a lane range edited by the user | keeps it, and keeps the generated points outside the edited stretch: the lane is split at the edges of the edit (the edit's first and last move) and only the untouched pieces are rewritten, joined to the user's with a ramp of `smooth_ms` |

Owned values still feed the analysis: a velocity the user set is an input of the next note's
level (the user's accent stays an accent, and the phrase arch around it bends to it).

An **edit of the notes** (pitch, start, a new note) does not make other values owned. A run after
it recomputes the generated values around the change. `:perform.again` does that for every run of
the project after a change of style, map, or tempo.

**Notation interop**: a value notation wrote (`meta.notation.wrote`) is a written mark's. `perform`
treats it as owned unless the style says `follow_marks = "shape"` (4.2).

### 3.4 Undo, trials, speed

- A trial is `paw.audition.try(fn)`: the edits show and sound, `revert` removes them with no
  trace, `keep` makes them one undo step. `perform` builds one workspace edit for all clips of the
  range, so one keep is one step even over twenty tracks.
- A change in the panel (uncheck a part, `\e+`) recomputes from the stored analysis and replaces the
  trial (`try` replaces the last trial). Analysis is cached per clip and version of the clip.
- **Budget** (rule 7: a key well under 100 ms): the analysis of a phrase (50 notes) and its render
  take under 5 ms in LuaJIT; the full song of 30 tracks and 20,000 notes is not a key but a
  command: it runs in steps of 2,000 notes on the idle loop with a progress item in the status line,
  `Esc` stops it, and the trial shows when it ends. The bench file (section 7.4) holds the numbers.

---

## 4. Synergies with the other extensions

### 4.1 The language server, completion and the LSP of MIDI LSP

`perform` registers a **Lua server** (`kind` Lua table, in-process) on the `clip` subject:

| LSP feature | `perform` gives |
| --- | --- |
| diagnostics (`hint`) | idiom problems: a wind or brass phrase over the breath limit; legato on repeated notes; a short articulation on a note longer than 1 s at a slow tempo ("spiccato on a half note at 60 bpm"); a keyswitch that changes on more than half of the notes of a bar; a long note with a flat dynamics lane on a crossfade library ("CC1 does not move for 8 s"); a part over its `comfortable` range at `pp` (hard to play soft) |
| code actions | "Shape this phrase", "Articulate", "Dynamics only", "Add a breath here", "Make the run spiccato", "Crescendo to the next downbeat", "Lock these notes" |
| hover | the short why |
| completion | velocities, attributes and controls for the notes just entered (never pitches) |

The diagnostics are hints, so they never crowd the counts of MIDI LSP's errors (`E1 W2` stays about
counterpoint).

**Overlap with MIDI LSP.** MIDI LSP's suggestion role "suggests melodies, velocities and controller
curves". The two do not compete: `perform` is local, deterministic, instrument-aware and explains
itself; MIDI LSP is an external engine. Both are completion sources; their items show as
alternatives (`1/3 perform: phrase`, `2/3 midi-lsp: velocities`). If MIDI LSP publishes
`paw/publishAnalysis` (chords, keys), `perform` reads it through `paw.harmony` like any provider. No
code of MIDI LSP is needed.

**A generic core change** (rule 5, generic): completion items can set `velocities` and `controls`
today, not attributes or lengths. Add `attrs = {[place] = attr | false}` and
`lengths = {[place] = beats}` to the item, drawn in the ghost (a tag on the note, a dashed end).
Any source can use them (a snippet with articulations). Owned by part P11.

### 4.2 Notation: marks in, marks out

- **In.** Written marks are constraints (rule R24):
  - a dynamic sets the level of the notes it reaches (it replaces the plan's level there);
  - a hairpin sets a ramp between its ends (with a target of the next dynamic, or ±2 steps);
  - an articulation mark vetoes the contrary family (a staccato dot: no legato; a tenuto: no
    short) and adds score to its family; a slur forces legato inside and a phrase boundary at its
    end; a technique text (`pizz.`, `arco`) fixes the family until it ends;
  - `sf`, `fp` are moments (notation's `MOMENTS`).
  `follow_marks` in the style: `"strict"` (marks win; the rules only shape inside them: the arch
  inside a `p`, the swell inside a hairpin), `"shape"` (marks are the base; rules may add ±1
  step), `"ignore"`. Default `strict`.
- **MusicXML import** (notation's import) brings the marks of a score, so an imported score is
  performed by its own marks. This is the best input: the composer's intent plus the rules.
- **Out.** `:perform.marks` writes the performance's levels into the score as marks: a dynamic where
  the level holds a new step for at least a bar, a hairpin where it ramps more than one step. It
  writes them as notation's marks with `meta.notation.wrote` empty, so notation does not write the
  velocities again (they are already the performance's). The default is off: a score with marks a
  machine wrote is not what most composers want; for a mockup sent to players it helps.
- Articulations already go to the score through `articulations` (the `mark` and `text` of the map).

### 4.3 utau: the voice

The vocal track is a performance too:

- `perform` gives utau the abstract performance of the vocal notes: level per note and phrase,
  breath points, vibrato depth. A small adapter (in `perform`, loaded when `utau` is) writes them
  as utau's curves: dynamics as `DYN`, breath as `BRE` at phrase starts, vibrato as the note's
  vibrato (`utau.note vibrato=on depth=…`), and the tension rule on high notes as the existing
  `utau.preset` "tension on high notes" logic. The utau extension owns its curves: the adapter
  calls its Lua API (`utau.curve`, `utau.note`), not its data.
- The vocal idiom (`voice.idiom.toml`) sets breath every 6–8 s, at phrase starts and at commas of the
  lyrics (a lyric that ends with `,` or `、`), and never in the middle of a word (a note whose lyric
  is `-` or `+` continues the word).
- Provenance works the same: utau's curves keep a digest per range in `clip.meta.perform.lanes`.

### 4.4 Drums: accents, ghosts, grooves

Drum tracks (a drum map from `drums`) take different rules, in a `drums` idiom:

| Rule | What it does |
| --- | --- |
| D1 `kit-roles` | the drum map gives each row a role: kick, snare, hat, ride, tom, crash, perc |
| D2 `backbeat` | snare on 2 and 4 accented, kick on 1 accented (style: rock, pop, funk) |
| D3 `hat-pulse` | hi-hat velocity by metrical weight (strong-weak eighths, or the 16th pattern of the style) |
| D4 `ghost-notes` | snare hits on weak 16ths with a velocity under the ghost threshold become ghosts (velocity 20–45), and a style may *add* them only with `add_ghosts = true` (default off: no notes unasked) |
| D5 `fill-crescendo` | a fill (a run of toms or snares before a section change) rises in level |
| D6 `crash-on-section` | the first hit of a section's crash accented |
| D7 `groove` | a groove template: microtiming and velocity per 16th step, by style and tempo |

**Groove templates** come from the **Groove MIDI Dataset** (CC BY 4.0, Magenta; attribution
shipped). A script (not shipped as a runtime part: `tools/perform/groove-from-gmd.lua`, run once by
a maintainer) averages the microtiming offset and the velocity per step of each style and tempo
band, and writes rounded numbers into `grooves/*.groove.toml` with the credit. The `drums`
extension's `gs` (swing) stays; a groove is a superset of swing. A groove applies to any track in
the "rhythm" role too (a bass, a comping piano), so the band locks to one feel.

### 4.5 The sampler

- The sampler's `describe` gives articulations (with M2 codes), `ccs` and `delay_ms`. `perform` reads
  `ccs` labels to build a default profile: a CC labelled "Dynamics" or used in `xf_cc` becomes
  `dynamics`; otherwise velocity.
- The sampler takes per-note attributes: the path's switch cost is `switch_attr` (cheap), and a chord
  may mix articulations (a sustained bass note under staccato chords).
- Per-note controllers (`key` on a move) let the swell of a long note in a chord not swell the others.
  `per_note = true` in the profile, default off until the sampler's per-note gain is checked.

### 4.6 Sections, musicops, pattern, mixdiag, templates

- **sections**: the units of the plan; `g=is` performs a section; `is` in the arrange view.
- **musicops**: `perform` reuses `musicops.phrases`, `chords`, `random` (Park–Miller, the same on
  every machine) and its `scale` module. `gz>` (crescendo) and `gzh` (humanize) stay simple edits;
  `perform` is the contextual one. A note in `musicops`' README points to `perform`.
- **pattern**: a clip that follows a pattern is regenerated from text; `perform` refuses to write it
  and says so ("pattern clip: `\td` detaches it first"). Its notes can still feed the texture of
  others.
- **mixdiag**: no overlap. The balance rule (R14) is about written level, not the mix. One link: a
  hint when a performance makes a track's CC11 sit below 30 % for a full section ("raise the
  fader, not the expression").
- **templates** (track templates): a template can carry `perform.style` in its `track.meta`, so a
  "Strings (CSS)" template comes with its style.

---

## 5. The library

### 5.1 Files

```
extensions/perform/
  styles/        *.perf.toml       styles (weights and parameters of rules, plans)
  idioms/        *.idiom.toml      families: strings, woodwinds, brass, voice, keys, plucked, drums, synth
  profiles/      *.profile.toml    controller profiles of libraries, matched like maps (or a [perform] table in a map)
  grooves/       *.groove.toml     drum and rhythm grooves (GMD-derived, with credit)
  DATA-LICENSES.md                 where each number comes from
```

Lookup, as maps do: `~/.config/paw/perform/**` first, then `perform/` in any loaded extension, then the
extension's own. The id is the path without the suffix. A file can `extends = "romantic-strings"`
and change only what it names.

### 5.2 A style, in full

```toml
# Romantic strings: long lines, arches over phrases, legato where the line steps.
format = 1
name = "Romantic strings"
source = "KTH defaults (Friberg 2006) for the arches; orchestration practice for articulations"
families = ["strings"]           # where it is offered first
amount = 1.0
follow_marks = "strict"
range = ["p", "ff"]             # the levels this style uses without written marks
base = "mf"                      # the level with no plan and no mark

[rules]
phrase-arch       = { k = 1.2, peak = 0.65, levels = 2, dyn_db = 6, tempo = 0.04 }
high-loud         = { k = 0.5 }
melodic-charge    = { k = 0.8 }
harmonic-charge   = { k = 0.6 }
duration-contrast = { k = 0.4 }
metrical-accent   = { k = 0.3 }
punctuation       = { k = 1.0 }
final-ritard      = { k = 1.0 }
long-note-swell   = { k = 1.0, shape = "messa-di-voce", db = 3 }
tempo-articulation = { k = 1.0, spiccato_ms = 250, staccato_ms = 450, long_ms = 600 }
legato-line       = { k = 1.5 }
vibrato-by-length = { k = 1.0, onset_ms = 300 }
humanize          = { k = 0.5, onset_ms = 6, db = 0.8 }
melody-lead       = { enabled = false }

[art_cost]
switch = 2.0
switch_attr = 0.5
min_run_beats = 1

[plan]                           # section names (patterns) to levels, when no plan is set
"intro" = "p"
"verse" = "mp"
"chorus|climax" = "f"
"outro|coda" = "pp"
```

### 5.3 The first set

| Id | Kind | What | Source |
| --- | --- | --- | --- |
| `neutral` | style | the KTH defaults with small k; no style choices; the default of an unknown family | Friberg et al. 2006 |
| `baroque` | style | terraced dynamics (section levels, small arches), détaché by default, short leap articulation, no vibrato on shorts, final ritard on cadences only; inégales off (a groove) | KTH; baroque practice (terraced dynamics) |
| `classical` | style | clear phrase arches on 4/8-bar phrases, cadence ritards, duration contrast | KTH |
| `romantic-strings` | style | above | KTH; practice |
| `film-epic` | style | big section plan, marcato on downbeats of phrases in brass/low strings, CC1 swells into downbeats, tremolo under crescendos | practice (research-mockup) |
| `film-intimate` | style | narrow range (pp–mf), long swells, legato, little metrical accent | practice |
| `pop-ballad` | style | grid-locked onsets (onset aspect off), velocity accents on the backbeat for keys, pedal for piano, small arches | practice |
| `jazz-small-band` | style | swing groove on rhythm parts, accent on syncopations and the ends of lines (bebop phrasing), ghosted notes in lines by beat weight | practice; GMD jazz grooves |
| `piano-solo` | style | melody lead (Goebl), pedal, phrase arch with tempo off unless song-level | Goebl 2001; KTH |
| `strings`, `woodwinds`, `brass`, `voice`, `keys`, `plucked`, `drums`, `synth` | idioms | section 2.6 | Rimsky-Korsakov *Principles of Orchestration* (PD); Adler (as a check, not quoted); library manuals |
| `spitfire-cc1-cc11`, `sine-cc1-cc11`, `css`, `csb`, `synchron-vel-xf`, `hollywood`, `sfz-velocity`, `paw-sampler`, `gm-synth`, `piano` | profiles | 2.7 table | the manuals (URLs in the files) |
| `rock`, `funk`, `jazz-swing`, `hiphop`, `latin`, `pop` at 2–3 tempo bands | grooves | 4.4 | GMD, CC BY 4.0 |

### 5.4 Data, licenses, and what only informs

- **Shipped numbers are ours**: rounded constants written by hand, each with a comment naming the
  study or manual it follows. The KTH papers publish their rule formulas and default k; formulas are
  not copyrightable, and the papers are cited.
- **GMD** (CC BY 4.0): grooves derived and shipped with attribution in `DATA-LICENSES.md` and in each
  groove file.
- **Vienna 4x22, Batik-plays-Mozart** (CC BY 4.0): used to *check* magnitudes (the tests' expected
  ranges, 7.2) and could ship derived numbers with credit; small, few pianists: a check, not a norm.
- **OpenScore Lieder and String Quartets** (CC0): the source of golden examples (score in, the
  performance out, checked by properties and by ear). A few short excerpts can ship as fixtures.
- **MAESTRO, ASAP, (n)ASAP** (CC BY-NC-SA 4.0): research only. A maintainer can measure with them
  offline to choose a constant; nothing fitted to them ships. `DATA-LICENSES.md` says which constant
  was checked against what.
- **CrestMuse PEDB, KernScores**: terms unclear or restrictive: not used until read.

### 5.5 How users add their own

- Copy a style: `:perform.style.edit` copies the track's style into `~/.config/paw/perform/styles/`
  with `extends` and opens it. paw reads it again on write, as maps are read again.
- A profile for a library: a `[perform]` table in its `.art.toml` (the simplest), or a profile file
  with a `match` like a map's.
- **Learn a style from your own corrections** (later, part P14): `:perform.learn` compares the
  generated values with what the user changed in the project (the owned values) and proposes new
  k values for the rules (least squares on the dB and length contributions). It writes a style that
  `extends` the one used. The data stays in the user's folder.
- **Learn from a reference MIDI** (later): `:perform.learn file.mid score.musicxml` aligns a
  performance to its score (the user's own, or a CC BY one) and fits k the same way.

---

## 6. Rule interactions: how the CC lanes work together and separately

- **Velocity vs CC1 on the same note.** On a crossfade library, velocity on a long note shapes the
  attack only (`velocity_on_longs = "attack"`); CC1 is the body. `perform` writes velocity from the
  level *and* the accent rules (R7, R18) on longs, so an accented long note bites and then sits at the
  phrase's level. On CSS, velocity is the legato speed: `perform` writes it from the interval and
  tempo (slow transition for a lyrical leap, fast for quick steps) and never from the level.
- **CC1 vs CC11.** CC1 moves with the phrase (seconds); CC11 moves with the section (bars to
  minutes) and the balance. A user who draws CC11 by hand keeps it (owned); the next run then writes
  the section level into CC1 only. A table in the README shows which aspect writes which controller
  per profile, generated from the profiles (a test checks it is complete).
- **CC2 breath** (winds with breath control): the dynamics *and* the breath gaps: it drops to 0 for
  `breath_ms` at each breath point. With `dynamics = "cc2"`, CC1 is free for vibrato (SWAM style).
- **CC21 vibrato**: from R21. Linked to dynamics only through the style (`vib_follows_dyn = 0.3`:
  a little more vibrato when louder, practice).
- **CC64 pedal**: piano only (R22). Never on a track whose map has no pedal and no `keys` family.
- **Chase**: the map's `chase` already restores CC1, CC11, CC64 at a seek. `perform` adds a point at
  the start of each run, so a run that starts mid-clip does not inherit the end of the previous one.

---

## 7. Quality: how to judge "good enough"

"Good enough" means: a musician needs only a correction pass, not a rewrite. Four kinds of evidence.

### 7.1 Properties (unit tests, Teal, no audio)

Each rule has one test that guards its behavior and fails only when it breaks (prune-tests rule):

- phrase arch: in a phrase of 16 equal notes, the loudest note is between 50 % and 80 % of the
  phrase, the last note is softer than the peak by at least the k·dB set, and the curve has one
  maximum (no zigzag) when the other rules are off;
- final ritard: the last four IOIs grow, the last note is the longest;
- tempo articulation: eighths at 140 bpm (214 ms) choose spiccato on the example map; at 70 bpm
  (429 ms) staccato or détaché; half notes at 60 bpm a long articulation;
- repeated notes are never legato; a slur forces legato; a staccato mark vetoes legato;
- the path: an alternating pattern long-short-long-short at 120 bpm switches at most once per beat
  on a keyswitched map, and per note on the sampler;
- breath: a horn line of 14 s gets one breath at its strongest inner boundary;
- the renderer: CC1 has no two points closer than `smooth_ms`, values in 0..1, monotone between
  rule points; shorts carry level in velocity and do not move CC1;
- determinism: the same input and seed give the same edit; a second run changes nothing
  (idempotence);
- user wins: change one velocity, run again: it stays, its neighbours may change; edit a stretch of
  CC1: it stays, the lane outside is rewritten, joined by a ramp;
- locks: nothing in a locked range changes;
- trial: `Esc` leaves the project equal to before (a hash of the clips); `Enter` is one undo step.

### 7.2 Magnitudes against data (a check, not a fit)

A script in `tests/perform/magnitudes.lua` (run in the suite, fast) performs four CC0 OpenScore
excerpts and one Vienna 4x22 melody (CC BY 4.0, shipped as a fixture with credit) and checks
ranges reported in the literature: the dynamic range inside a phrase (about 6–12 dB at mf),
final lengthening (the last note 1.2–2× its written length), the share of IOI variation under
10 % outside phrase ends. These ranges are written in the test with their citation.

### 7.3 Listening notes

`tools/perform/ab.sh` renders, with `--audio null`, offline, a set of short golden excerpts twice
(raw MIDI, performed) through the paw sampler with the VSCO 2 CE strings and the built-in synth, into
the scratch folder. The owner listens and writes a short note per excerpt in
`extensions/perform/doc/listening.md` (date, version, "better / same / worse", what was wrong). A
change of a default k needs a line in this file. Not automated; it is the ground truth for taste.

### 7.4 Speed

`bench/perform.lua`: the analysis and render of a 50-note phrase (budget 5 ms), of a 2,000-note
clip (budget 60 ms), of a song of 20,000 notes in steps (each step under 30 ms).

### 7.5 The e2e scenario (for the owner's suite, later; not run by agents)

`e2e/perform-quartet`: open the OpenScore string quartet fixture (MusicXML import with marks), bind
the example maps to four sampler tracks, `:%perform`, keep, render with `--audio null`; expected:
the per-seed hash of the clips' MIDI, the counts of articulations per track, and the loudness
envelope of the render within tolerance. Then one correction with real keys (`]` on a note, `\a`
on another), `:perform.again`, and the expected output shows both corrections kept.

---

## 8. What changes outside the new extension

| Where | Change | Why it is generic |
| --- | --- | --- |
| `paw.complete` (runtime) | items may carry `attrs` and `lengths`; the ghost draws them | any source |
| `paw.keymap` (runtime) | `paw.keymap.insert_step()`: the undo step of the insert in progress, or nil (today the local `insert_undo`) | any extension that answers an insert at idle |
| `articulations` | the map reads an optional `[perform]` table and gives it to whoever asks (`art.profile_of(track)`); its README documents the table | the map is the instrument's one file |
| `articulations` | `art.set` takes a list of places with *different* choices in one call (today one choice per call), so a path of articulations is one edit per clip | used by `:art.from-keyswitches` too |
| `musicops` | `phrases` takes an optional boundary provider (so `ip` follows `perform`'s boundaries when loaded) | any extension can give boundaries |
| `notation` | `marks.add(clip, mark, { wrote = false })` for marks that play nothing (used by `:perform.marks`) | a mark that does not write velocities |
| `utau` | a small Lua API to set a curve over a range (`utau.set_curve(clip, abbr, points)`) if it is not public now | any script |
| docs | `docs/reference/completion.md`, the articulations README, `docs/explanation/about-performance.md` (new), the how-to "Shape a phrase" | |

No Rust change.

---

## 9. Plan

Each part is 30–90 minutes for one agent, in its own worktree, with its tests. All new code is Teal.
Parts on one line can run in parallel.

| Part | What | Owned files | Model | Tests | After |
| --- | --- | --- | --- | --- | --- |
| P1 | skeleton: manifest, init, types (2.10), the TOML reader for styles/idioms/profiles with errors that name the field | `extensions/perform/{manifest.lua,init.tl,lua/perform/types.tl,lua/perform/library.tl}`, `styles/neutral.perf.toml`, `idioms/*.idiom.toml` | sonnet | the reader: a good file, a wrong type, `extends` | — |
| P2 | analysis: features, phrases (rests, LBDM, slurs), roles, texture | `lua/perform/analyze.tl` | opus | phrases of a fixture; beat weights in 4/4, 6/8, 7/8; roles of a melody over chords | P1 |
| P3 | rules R1–R12 and the combiner | `lua/perform/rules/*.tl`, `lua/perform/combine.tl` | opus | 7.1 per rule | P2 |
| P4 | dynamics renderer: level → CC1/CC11/velocity via a profile; `[linked]`; thinning | `lua/perform/render.tl`, `profiles/*.toml` (generic three) | sonnet | 7.1 renderer | P3 |
| P5 | provenance and merge: `wrote`, digests, locks, user wins | `lua/perform/provenance.tl` | opus | user wins, locks, idempotence | P4 |
| P6 | the user: `g=`, `\e` keys, `:perform`, the trial panel, keep/drop, the message | `lua/perform/commands.tl`, `lua/perform/panel.tl` | opus | real keys: `g=ip` then `Enter`; `Esc` leaves the project equal; one undo step | P5 |
| P7 | articulation path (2.5) and R16–R19; `art.set` with many choices | `lua/perform/path.tl`; `articulations/lua/articulations/init.lua` (small) | opus | path tests | P3 ∥ P4 |
| P8 | lanes: breath, vibrato, pedal, long-note swell (R15, R20–R22); the CSS legato-speed profile | `rules/lanes.tl`, profiles | sonnet | breath, pedal | P4 |
| P9 | timing: lengths, onsets, melody lead, humanize stream; `:perform tempo` for the song | `rules/timing.tl`, `lua/perform/tempo.tl` | sonnet | final ritard, onsets clamped, song tempo one undo step | P5 |
| P10 | notation in and out: marks as constraints, `follow_marks`, `:perform.marks`, the generic `marks.add` | `lua/perform/notation.tl`; `notation/lua/notation/marks.lua` (small) | opus | a hairpin is followed; a staccato vetoes legato; marks out | P6 ∥ P7 |
| P11 | the language server, hover, code actions, completion source; the generic `attrs`/`lengths` items in `paw.complete` | `lua/perform/lsp.tl`, `lua/perform/complete.tl`; `runtime/lua/paw/complete.tl` | opus | `gK` text; an action is one undo step; an item with attrs accepted by `Tab` | P6 |
| P12 | drums: kit roles, D2–D6, grooves format, the GMD script, a first set of grooves with credit | `lua/perform/drums.tl`, `grooves/`, `tools/perform/groove-from-gmd.lua`, `DATA-LICENSES.md` | sonnet | backbeat, ghosts not added unless asked, groove applied | P6 |
| P13 | utau adapter: DYN, BRE, vibrato from the performance | `lua/perform/utau.tl`; `utau` (small API) | sonnet | a vocal phrase gets breath at its start, never mid-word | P8 |
| P15 | live expression (1.8): `:perform.live`, `\ei` (the track), `:set perform_live` (the project), the option and track override, the status line component, the per-note `edit.before` pass, the dirty-window cache, the idle pass and the `Esc` flush, the join to the insert step, `paw.keymap.insert_step()`, recording after the take; the completion source silent while live | `lua/perform/live.tl`, `lua/perform/cache.tl`; `runtime/lua/paw/keymap.lua` (the getter) | opus | real keys: `:perform.live on`, `i` + notes + `Esc` gives articulations and velocities, and one `u` removes notes and expression together; a velocity set with `]` survives more notes; a deleted note makes its neighbour lose `leg`; a MIDI-keyboard velocity is kept; nothing runs during a take, articulations after it in the take's step; the bench budget (3 ms per note on a 2,000-note clip) | P5, P6, P7 |
| P14 | the plan (`:perform.plan`, auto plan), `:perform.again`, styles of 5.3, README, `doc/reference.md`, explanation page, how-to + guide test, bench, `:perform.learn` (optional) | docs, `styles/`, `bench/perform.lua` | sonnet (docs: opus review) | guide test; bench budgets | all |

Order: P1 → P2 → P3 → (P4 ∥ P7) → P5 → P6 → P15 → (P8 ∥ P9 ∥ P10 ∥ P11 ∥ P12) → P13 → P14.
P15 comes right after P6 because the owner asked for it; P8's lanes and P10's marks then join the
live passes as they land (each part adds its rules to the idle pass and its tests to P15's file). The first
slice the owner can try is after P6: dynamics of a phrase with a trial, kept with user wins.

### 9.1 Risks

| Risk | Effect | Mitigation |
| --- | --- | --- |
| Taste: rules that measure well sound mechanical | the user rewrites, the feature fails | small default k; the listening notes (7.3) gate default changes; `amount` on a key; styles easy to copy |
| Polyphony in one clip (piano, a divisi in one track) | voices mixed, wrong intervals and roles | skyline for the melody, chords as blocks; per-voice analysis uses notation's `voice` when written; else said in `\e?` ("one voice assumed") |
| Library profiles from manuals, not checked | wrong controller → no change heard | "checked" field as maps have; `:perform.check` hints a flat lane; `:art.measure` style self-check later |
| Size of `meta.perform` on large clips | larger files, slower saves | 60 B per changed note; open question 10.6 |
| Conflict with notation's `wrote` | two owners of a velocity | 3.3: notation's value is owned unless `follow_marks = "shape"`; tests cover both |
| A global tempo for one track's rubato | the band follows the violin | tempo only at song level; per-track rubato as onsets (2.8) |
| Keyswitched libraries and chords of two articulations | the last keyswitch wins | the path forbids it (`+∞`) on keyswitched maps; `articulations` already warns |
| Speed on a whole song | a stall | stepped on the idle loop; `Esc` stops; bench |
| Data licenses | a shipped table derived from NC data | 5.4; `DATA-LICENSES.md`; review in P12/P14 |

---

## 10. Open questions for the owner

1. **The name and the keys.** `perform` with `g=` (operator) and `\e` (the view's keys). Other
   names: `expressive`, `shape`. *Recommendation:* `perform`, `g=`, `\e`. "Expression" is taken
   by note expressions (`gX`).
2. **A trial before keeping, or write at once?** *Recommendation:* a trial by default for keys and
   `:perform`, kept with `Enter`; `:perform!` and `paw.opt.perform_trial = false` write at once.
   It matches the articulation popover ("you hear it before Enter").
3. **Marks by default.** Should written dynamics and articulation marks be strict constraints?
   *Recommendation:* yes, `follow_marks = "strict"` in every style except `film-epic`
   (`"shape"`). A composer's mark is the composer's.
4. **Tempo.** Should `perform` ever write the project's tempo map? *Recommendation:* only by
   `:perform tempo` over the whole song, as its own aspect, off by default; per-track rubato stays
   inside ±40 ms onsets.
5. **The smart pen and auto suggestions.** *Decided by the owner* (section 12): live expression
   while writing, as an option switched by a command. The smart pen is merged into it.
6. **Provenance size.** Keep `from` (the value before the first run, for a clean "take the run
   away") on every note, or only `v` and the run id? *Recommendation:* keep `from`: 60 bytes a note
   is small, and a clean take-away is what notation's marks already promise.
7. **Ghost notes and added notes.** Should a drum style ever add notes (ghosts, flams)?
   *Recommendation:* never by default; `add_ghosts = true` in a style, shown as a separate aspect
   in the panel.
8. **GMD grooves in the repository.** Ship the derived groove files with the CC BY credit?
   *Recommendation:* yes; they are small averaged numbers, and the credit is in each file and in
   `DATA-LICENSES.md`.
9. **Learning from corrections** (`:perform.learn`): build it in the first release, or later?
   *Recommendation:* later (after P14), when there are corrections to learn from.
10. **Per-note controllers on the sampler.** Default on for the paw sampler (a swell on one note of
   a chord)? *Recommendation:* off until the sampler's per-note gain is tested with `--audio null`
   renders; then on for the sampler only.

---

## 11. Sources

Full notes, with the status of each claim (read, snippet, or memory), are in `research-rules.md`,
`research-mockup.md` and `research-datasets-tools.md`. The ones this design relies on:

- [K1] Friberg, Bresin, Sundberg (2006), "Overview of the KTH rule system for musical performance",
  Advances in Cognitive Psychology 2(2–3):145–161, doi:10.2478/v10053-008-0052-x. Mirror:
  https://continuum-hypothesis.com/music/kth.pdf. Thesis with the preferred k values:
  https://www.speech.kth.se/music/publications/thesisaf/sammfa2nd.htm. Director Musices:
  https://www.diva-portal.org/smash/get/diva2:1246181/FULLTEXT01.pdf
- [K2] Friberg & Sundberg (1999), "Does music performance allude to locomotion? A model of final
  ritardandi derived from measurements of stopping runners", JASA 105(3):1469–1484:
  https://continuum-hypothesis.com/music/Does_music_performance_allude_to_locomotion_A_mode.pdf
- [K3] Friberg, Bresin, Frydén, Sundberg (1998), "Musical punctuation on the microlevel":
  https://www.speech.kth.se/~roberto/punctuation
- [K4] Todd (1985, 1992); Windsor & Clarke (1997), the test of Todd's model:
  https://continuum-hypothesis.com/music/Windsor-ExpressiveTimingDynamics-1997.pdf
- [K5] Widmer (2002, 2003); Widmer & Goebl (2004), "Computational models of expressive music
  performance: the state of the art", JNMR 33(3): https://iwk.mdw.ac.at/goebl/papers/Widmer-Goebl_JNMR2004.pdf ;
  "In search of the Horowitz factor": https://www.cp.jku.at/people/widmer/papers/AIMag24-03-010.pdf
- [K6] Cancino-Chacón, Grachten, Goebl, Widmer (2018), "Computational models of expressive music
  performance: a comprehensive and critical review", Front. Digit. Humanit. 5:25:
  https://www.frontiersin.org/articles/10.3389/fdigh.2018.00025 ; the Basis Mixer:
  https://github.com/OFAI/basismixer
- [D1] Goebl (2001), "Melody lead in piano performance: expressive device or artifact?", JASA 110(1).
- [D2] Tools and their reception: `research-datasets-tools.md` B (Reaticulate, Cubase and Dorico
  expression maps, NotePerformer, MuseScore 4, Finale Human Playback, Ableton's groove pool, a KVR
  survey where users ask for "a workable foundation which I could refine by hand later":
  https://www.kvraudio.com/forum/viewtopic.php?p=9183472).
- [D3] Datasets and licenses: Groove MIDI Dataset, CC BY 4.0: https://magenta.tensorflow.org/datasets/groove ;
  MAESTRO, CC BY-NC-SA 4.0: https://magenta.tensorflow.org/datasets/maestro ; ASAP, CC BY-NC-SA 4.0:
  https://github.com/fosfrancesco/asap-dataset ; Vienna 4x22, CC BY 4.0:
  https://datasets.mdw.ac.at/datasets/dataset/98ea25fa-2468-43ff-929b-3c926e163583 ; OpenScore Lieder
  (CC0): https://github.com/OpenScore/Lieder
- [M1] Spitfire BBC SO Pro manual: https://www.spitfireaudio.com/cdn/shop/files/BBCSOPro_Manual_v4_96703953-4d7b-4d52-bdc8-a7b176ed342c.pdf ;
  UACC: https://support.spitfireaudio.com/en/articles/11816188-using-expression-maps-with-uacc
- [M2] Orchestral Tools controller table: https://orchestraltools.helpscoutdocs.com/article/199-controller-table-annotated-list ;
  terms: https://orchestraltools.helpscoutdocs.com/article/167-technical-terms
- [M3] VSL orchestration recipes: https://vsl.co.at/tutorials/guides/orchestration-recipes/intro ;
  forum: https://forum.vsl.co.at/post/289083
- [M4] Layers of control (CC7 once, CC1 per phrase, CC11 overall, velocity for attacks):
  https://beatkitchen.io/guides/orchestral/12-from-score-to-mix/
- [M5] Cinematic Studio Strings: https://forums.steinberg.net/t/expression-maps-with-cinematic-studio-strings/121616 ;
  https://medium.com/pragmatic-sound/how-to-create-expression-maps-for-cinematic-studio-strings-ae8963cf1896
- [M6] Bow strokes by tempo: https://violinlounge.com/blog/sautille-vs-spiccato ;
  https://www.thestrad.com/improve-your-playing/spiccato-and-sautille-two-important-bow-strokes-which-are-often-confused/13970.article
- [M7] MIDI 2.0 Note-On Orchestral Articulation Profile (M2-123):
  https://amei-music.github.io/midi2.0-docs/amei-pdf/M2-123-UM_v1-0_Note-On_Orchestral_Articulation_Profile.pdf
- Rimsky-Korsakov, *Principles of Orchestration* (public domain): https://www.gutenberg.org/ebooks/33900

What is **not** verified and must be before a number ships: the KTH 2006 default tables (read the PDF
with pdftotext), the final-ritard w, Widmer's repeated-note rule (memory only), the Synchron CC2
claim, the CSS legato zones per version, and the full UACC table. Part P3 and the profile files of
P4/P8 carry a "checked" line per number.

---

## 12. Owner's decisions

| # | Date | Question | Decision | Where |
| --- | --- | --- | --- | --- |
| 1 | 2026-11-21 | Open question 5: the smart pen and suggestions while writing | "I would like to have the smart expression generate while I am writing MIDI, at least as an option that I can turn on/off through a command." Built as **live expression**: `:perform.live on\|off` (alone: toggle), `\ei`, `paw.opt.perform_live` per project with a track override, a `≈live` status-line item; per note in the insert's undo step, phrase work at idle and on `Esc`; never timing; recorded takes get articulations and lanes after the take. The smart pen is merged into it; the completion item stays for when live mode is off | 1.8, plan P15 |
| 2 | 2026-11-21 | The key of live expression | "`2\ei` is a weird non-idiomatic combination." A count means repetition in paw, never scope. So: `\ei` toggles live expression for the **track under the cursor** (a key acts on what is under it); the project's setting is `:perform.live` (alone: toggle; `on`/`off`) and the option (`:set perform_live`, `:set noperform_live`); `:perform.live on\|off track` stays for scripts. A count before `\ei` is ignored, as for the other switches in paw (`gzL`, the scale lock). The same check on the other keys changed `g==` (the row, as every doubled operator, not the clip) and wrote down what a count does on `\e+` `\e-` (repeats the step), `\er` (repeats: more seeds) and `\e!` (ignored) | 1.2, 1.8.1 |
