# Step input from a MIDI controller (TASK-55)

Status: design only, for the owner's approval. Nothing is built.
Date: 2026-11-22.

## Summary and recommendation

`I` in the piano roll starts **step input**. It is the pencil of insert
mode, with a MIDI controller as the source of the pitches. The controller
is a keyboard, pads, a wind controller, or a guitar through vinput. Each key, or each chord
of keys held together, enters notes at the caret, and the caret sits
at their end, ready for the next. All the computer keys of the pencil
work at the same time. `h` `l` change the length of the last notes.
`=8.` sets the value of the next notes. `<Space>` is a rest, `<BS>` takes
the last note back, `c` makes a chord, `.` enters it again, and a count
repeats. `Esc` writes it all as **one undo step**, as
the pencil does today.

The main decisions that I recommend:

1. **`I` is step input; `i` stays the pencil without the controller.**
   In `i`, a played key only sounds (an audition). Nothing enters by
   accident while you draw.
2. **The pen model.** A key fills the pen. A chord is the keys that
   you press while another key of the chord is still held. When you
   release the last key, the chord is closed. The next key keeps it and
   enters after it (as MuseScore, Dorico and Logic without chord mode do).
   The notes stay in the pen until the next key, so the computer keys
   fix them first (a wrong key: `+`, or `x` and play again).
3. **The length is sticky.** A key enters a note as long as the **step**:
   the roll's note length (`roll:step_length()`, the grid when unset).
   `=` sets the step for the pen and for what follows, and `<Space>`
   rests one step. `h` `l` change only the note in the pen.
4. **Velocity comes from the key** (MIDI 2.0 resolution, and the MIDI
   2.0 attribute, kept). `paw.opt.step_velocity = 100` fixes it.
5. **The input.** paw listens to the `midi_input` of the track of the
   active clip (its port and channel), else to all ports, as the
   recording rule does. The note sounds through that track. **Nothing is
   recorded**, and nothing enters while the transport plays.
6. **Controller controls are a generic map** (`paw.step.bind`), in the
   state of the user and not in the project. A mapped key or pad does an
   action (`rest`, `tie`, `back`, `dur.8`, `dot`, …) or types keys of the
   pencil (`"=8t"`). The message of a mapped key is **consumed**: it does
   not enter, and it does not sound. The sustain pedal has a default: with
   no key held it is a rest, and with keys held it ties them one step on
   (Logic and Ableton). `:step.learn rest` learns a control.
7. **Views are targets.** `paw.step.target(view, spec)` lets a view take
   step input: the piano roll in the core, notation and the vocal editor
   in their extensions, and later the drum grid. The core stays generic.
8. **Remove the computer keyboard as a piano** (`paw.opt.roll_insert =
   "keys"`, the `pianoroll.keys` keymap) and the old step input of
   normal mode (`:notes.step_input`, the Step button that writes each
   note as its own undo step). The owner does not use the first, and `I`
   replaces the second. paw needs no compatibility before a release.
9. **Tests use `paw.midi.inject` with a port name under `--audio null`.**
   The engine part (consumed messages, the track that sounds) has Rust
   unit tests. A real ALSA port is only for the e2e suite.

## What is there today (read from the code)

- **The pencil** (`runtime/lua/paw/roll_draw.tl`): a `Session` with
  `notes` (kept), `pen` (being drawn, `pen[1]` under the cursor, more for
  a chord), `edge`, `count`, `removed`, `undo`. A new pen note has no
  length (`fresh`). `M.next("legato"|"rest"|"chord")`, `M.again`,
  `M.back`, `M.back_all`, `M.erase`, `M.length_key`, `M.digit`,
  `M.chord(pitches)`, `M.pen()`/`M.shown()` and `M.key(lhs, spec)` for
  extensions. `M.finish()` writes all at `Esc` and joins one undo step.
  `<Space>` rests `n * note_grid`. `=` sets only the pen.
- **The computer piano** (`I`, `paw.opt.roll_insert = "keys"`): the
  `pianoroll.keys` scope in `defaults/keys.lua`, `view:enter`,
  `view:backspace`, `view:set_octave` in `views/pianoroll.lua`. Each key is
  a separate `edit_notes` call, so each is an undo step (as
  `docs/reference/limits.md` says).
- **Step input of normal mode** (`frontend.tl`, `A.toggle_step_input`,
  `:notes.step_input`, the Step button of the roll toolbar): with the
  transport stopped, it hears `midi.in` from **all ports**. It enters each
  note at once with `edit_notes`, makes chords of held keys, and steps on
  when the last key is released. Its test is in `tests/frontend.lua`.
- **MIDI input**: `paw.on("midi.in", e)` with `type pitch velocity
  (number) channel attr port`. `paw.midi.inject{ …, port = "…" }` and
  `paw.midi.note_on` work on the null backend.
  `paw.opt.midi_follows_selection` with `api.engine_follow(track)` makes the
  cursor's track play the keyboard while no track is armed. A track's
  `midi_input = { port, channel }` filters what it records.
- **Learn** (`runtime/lua/paw/learn.lua`): bindings in `project.meta.learn`
  by cc or note and channel, **not by port**. It does not consume the
  message: a bound pad also sounds.
- **Notation** (`extensions/notation`): its insert mode is MuseScore's
  note input. `view:enter(letter, advance)`, `enter_rest`, `tie_last`,
  `inflect_last`, `octave_last`, `add_interval`, `R` re-pitch
  (`P.re-pitch_enter`), `I` push-insert. A value comes first (`2`…`7`).
- **Vocal editor** (`extensions/utau`): no insert mode for notes. `i`
  toggles a note (`length = 2 * note_grid`), and `c` types its lyric.
  `I` is free there.

## The grammar

### Start and stop

| Where | Keys | Effect |
| --- | --- | --- |
| Piano roll, normal mode | `I` | Step input: insert mode with the controller. A caret (a pen with no length) at the cursor. The title shows `STEP`. |
| Piano roll, insert mode (`i`, `a`) | `I` | Step input on or off. The pen stays as it is. |
| Piano roll, step input | `Esc` | Writes all notes as one undo step, and returns to normal mode: `wrote 12 notes`. |
| Piano roll, step input | `Ctrl-o` | One command of normal mode. Step input continues after it. |
| Anywhere, no input | `I` | Starts step input, and says: `step input: no MIDI input. Connect a keyboard, or choose one: :track.midi (I on the track lists the inputs)`. It opens the MIDI part of the input list of the track. The pencil works. Keys that arrive later enter. |
| Notation, insert mode (`i` `a` `I` `R`) | a played key | Enters, as the letters do (see [Notation](#notation)). |
| Vocal editor, normal mode | `I` | Step input (see [The vocal editor](#the-vocal-editor)). |

"No input" means one of these. paw has no MIDI ports open (the null
backend without `engine_restart{ midi = true }`). Or no port is listed.
Or the `midi_input` port of the track is `missing`. paw tells which one.

### The controller in step input (piano roll)

| On the controller | Effect |
| --- | --- |
| A key, with no other key held | Keeps the pen if it has a length, then enters the note at the caret, one step long, with the key's velocity. The caret goes to its end. A count before it (`3`, typed on the computer) enters the note three times. |
| More keys while one is held | Adds them to the pen: one chord, same start, same length. |
| The last key released | Closes the chord. Nothing moves: the caret is already at its end. |
| The sustain pedal down, no key held | A rest of one step (`<Space>`). |
| The sustain pedal down, keys held | Ties them: the pen grows one step (Ableton's "advance while held"). Again for each press. |
| A mapped key, pad or button | Its action (see [Controls](#controls-from-the-controller)). It does not enter, and it does not sound. |
| The pitch wheel, other controllers | Sound only. Not entered (no curves in step input; `e` does that). |

### The computer keys in step input

All keys of the pencil work. These are the ones that matter:

| Keys | Effect in step input |
| --- | --- |
| `=` and a value | Sets the length of the pen **and the step**: the notes and rests that follow have that length (`=8.` dotted eighths, `=8t` triplet eighths). Sets the roll's note length too. |
| `<Space>`, `3<Space>` | Keeps the pen, and rests one step (three steps). The step is the step length, not the grid. |
| `<CR>` | As in the pencil: keeps the pen, and takes up the clip's note that starts at its end. |
| `h` `l`, `o`, `^` `$` | Move the edge of the pen: only this note, not the step. |
| `+` `-`, `K` `J`, `r{name}` | Change the pitch of the pen: fix a wrong key without playing again. |
| `x` | Erases the pen. The caret goes to its start: play again there. |
| `<BS>`, `Ctrl-w` | Takes back what you entered last. A note or chord becomes the pen again and the pen goes. After a rest, the caret returns one step. |
| `Ctrl-u` | Takes back all of this step input. |
| `.`, `3.` | Enters the pen again after it (three times). |
| `c`, `C` | A chord on the pen, from the list (`c` then `V7`). |
| `[` `]` | Velocity of the pen, by 10. The next keys keep their own velocity unless `step_velocity` is a number. |
| `a`, `e`, `m`, `<`, `>`, `k` `j` | As in the pencil: articulation, a controller, a mark, move, bend. |
| digits | A count for the next key, also for the next **played** key. `0` with no count goes to the start edge. |
| `I` | Step input off. You stay in the pencil. |

### How a played key composes with the pen

- A played key with the pen holding notes is the same as `<CR>` and then
  a fill: the pen is kept, and the new note starts at **its end**, not at
  the edge where the cursor is. So `o` then a key does not put a note in
  the middle. To change the pen, use `+` `-` `x`.
- When `I` starts on a note of the clip, the caret is at the cursor and
  the note stays. A played note with the same pitch and start replaces it
  (the rule of the pencil). Other pitches join it. A re-pitch way, as
  notation's `R`, is a later part.
- Step input does not push the notes after it. It writes over them as
  the pencil does (a note stops at the next note of its pitch).
- The clip grows by whole bars, as in the pencil.

## Durations, rests and ties from the controller

The default: the computer gives the value (`=`), and the controller gives
the pitches and the rests and ties (pedal). Every notation program does
this. For a controller only, without the computer, map the controls:

| Action | Default control | Effect |
| --- | --- | --- |
| `rest` | pedal down, no key held | `<Space>` |
| `tie` | pedal down, keys held | the held pen one step longer |
| `back` | none | `<BS>` |
| `erase` | none | `x` |
| `again` | none | `.` |
| `legato` | none | `<CR>` |
| `dur.1` `dur.2` `dur.4` `dur.8` `dur.16` `dur.32` | none | `=1` … `=32` |
| `dot`, `triplet` | none | the step dotted, or a triplet, on and off |
| `octave.up`, `octave.down` | none | the pen an octave (`K` `J`) |
| `chord` | none | held: the keys join one chord across releases (Logic's Chord button) |
| `finish` | none | `Esc` |
| `{ keys = "…" }` | none | types those keys of the pencil, for anything else |

The how-to guide gives usual setups as examples. The lowest keys of an
88-key keyboard (A0 to G#1) are the values. The pads of a pad controller
are rest, back and values. A foot switch is `back`.

## Chords by holding

- The rule is **hold**: a key pressed while another key of the chord is
  held joins the chord. The release of the last key closes it. MuseScore
  says this: notes enter one after the other "so long as you release each
  key fully before pressing the next".
- The risk: a pianist who plays legato overlaps the keys, and two notes
  become a chord. In step input, you play slowly, so this is rare. `<BS>`
  or `x` fixes it. If it is a problem, a later option
  `paw.opt.step_chord_ms` joins only the keys that start within that time
  of the first (Renoise users asked for the opposite, so hold is the
  default).
- The mapped `chord` control holds a chord open across releases, for a
  chord wider than the hands.

## Velocity

- From the key, at MIDI 2.0 resolution (the pen keeps it as an integer
  today. The design keeps the 16-bit value where the note can hold it).
- `paw.opt.step_velocity`: `"key"` (default) or a number from 1 to 127.
- `[` `]` change the pen. The title shows `vel 87`.
- The MIDI 2.0 attribute of a note-on (an articulation from a 2.0
  controller) goes into the note's `fields.attr`, as recording does.

## Which device, and nothing recorded

- Step input listens to the active clip's track: its `midi_input` port
  and channel, when it has one, else all ports. This is the rule of
  recording, so a track configured for a keyboard works the same in both.
- vinput's ports (a guitar to MIDI) are ports of paw, so step input from
  a guitar works with no more code.
- Step input never records. It ignores the keys while the transport
  records. While it plays, the keys only sound, and the title says
  `STEP (paused: playing)`.
- A port that goes away (`midi.lost`) releases the held keys and closes
  the chord. The message of `midi.lost` already names the tracks.
- Controls bind by **port** (and note or cc, and channel), unlike learn.
  So the pads of one device do not take the notes of the keyboard.

## What you hear and see

- **Sound.** While step input is on, the active clip's track plays the
  controller, also when another track is armed. That needs a small engine
  change: `engine_follow` with a "force" flag (today the follow stops while
  any track is armed). The armed track keeps its own monitoring. paw does
  not play the note again from Lua (no double note). `audition()` stays for
  `+` `-`.
- **Consumed controls.** A mapped key or pad must not sound or reach a
  recording. The engine gets a generic **input filter**:
  `api.engine_midi_filter(list)`, a list of `{ port, channel, note | cc }`
  that go to Lua (`midi.in`, marked `e.filtered = true`) and not to
  tracks. The engine swaps the list in through its command queue. The
  audio thread reads a fixed, small table: no lock and no allocation.
  Learn can use the same filter for its pads later.
- **What shows.** The title: `STEP C4 E4 G4 · 1 beat (=4) · vel key ·
  from Keystation 49`. While keys are held: `STEP holding C4 E4`. With no
  input: `STEP · no MIDI input`. The pen is green, as in the pencil. The
  status line's `midi ●` lights for each message, as today. A consumed
  control says what it did for a moment: `rest`, `back`.
- The key bar shows the step keys (`=` value, `Space` rest, `BS` back, `I`
  off) in place of the piano keys.
- The graphical window shows the same scene. Its Step button becomes the
  switch of `I`.

## Notation

- Notation registers a target. A played key calls a new
  `view:enter_pitch(pitch, advance)`, as `view:enter(letter, advance)`
  does, with the pitch played and not the nearest octave. Its spelling
  comes from the key (`model.key_pitch` the other way round).
- Chords: hold, as in the roll. A key that comes while another is held
  is `advance = false`. The release of the last key steps on (as the old
  step input did, and as MuseScore does).
- Rest: `enter_rest`. Tie: `tie_last`. Back: Backspace's function.
  `dur.N`: the value keys `2`…`7`. `dot`, `triplet`: `.` and `t`.
- In `R` (re-pitch), each key re-pitches the next note, and the rhythm
  stays. In `I` (push), the music after it moves on.
- My recommendation: in notation, **every insert mode takes the
  controller**. Notation's insert mode is note input, as in MuseScore and
  Dorico, where the MIDI keyboard always enters. `I` is push-insert there
  and stays push-insert. This is an owner question (Q2).

## The vocal editor

- `I` starts step input in the vocal editor. A key adds a note at the
  cursor, one step long (the step: `2 * note_grid` as `i` gives, or `=`),
  and the cursor steps on at its end. The singing engine sings it for
  feedback, as a placed note does (`utau_audition`).
- A vocal track sings one note at a time. A chord enters its highest
  note, and paw says so once.
- The lyric: the default of a new note. Later, a lyric queue: the words
  of the lyric sheet that no note has yet, one for each key, as Synthesizer
  V and VOCALOID let you type lyrics first (Q8).
- `<Space>` rest, `<BS>` back, `Esc` end. All of it is one undo step.
- The utau extension registers the target. The core knows nothing of
  vocals.

## The Lua extension point

```lua
-- A view that takes step input (the core does the roll; extensions the rest).
paw.step.target("notation", {
  active = function() return paw.keymap.mode == "i" end,  -- when it listens
  note = function(e) end,      -- { pitch, velocity, attr, chord = true when another key is held }
  release = function() end,    -- the last held key is released
  actions = {                  -- what each action does here; missing ones say "not here"
    rest = function(count) end, tie = function(count) end, back = function() end,
    dur = function(beats, name) end, dot = function() end, triplet = function() end,
  },
  status = function() return "STEP C4 · quarter" end,
})

-- A control of the controller: an action, or keys of the view.
paw.step.bind({ port = "nanoPAD", note = 36 }, "rest")
paw.step.bind({ port = "Keystation", note = 21 }, "dur.1")
paw.step.bind({ cc = 64 }, { down = "rest", held = "tie" })   -- the default of the pedal
paw.step.bind({ note = 23, port = "Keystation" }, { keys = "=8t" })
paw.step.unbind(source); paw.step.bindings()
paw.step.action("accent", function(count) end)  -- a new action, by an extension
paw.step.active()   -- the target that listens now, or nil
paw.step.input()    -- the port and channel it listens to, or nil and why not
```

| Command | Effect |
| --- | --- |
| `:step.learn rest` | Waits for a key, pad or pedal of the controller, then binds it to `rest`. `Tab` completes the actions. |
| `:step.controls` | Lists the controls. `x` removes one. |
| `:step.input` | Says what step input listens to, and opens the input list of the track. |

- The bindings are the user's, not the song's: a file
  `state_dir/step-controls.json`, written by `:step.learn` and read at
  start, plus what `init.lua` binds. An extension can bring a profile for
  a known controller.
- The pencil's own keys stay the extension point for the pen
  (`paw.roll_draw.key`). A control with `{ keys = … }` reaches them.

## Tests

- **Lua, `--audio null`.** `paw.midi.inject{ type = "note_on", pitch = 60,
  velocity = 90, port = "Test Keys" }` and `note_off`, `cc` 64 for the
  pedal, then `paw.flush()`. The tests use the real keys: `I`, then the
  played notes, then `=8`, `<Space>`, `<BS>`, `Esc`, and read
  `paw.roll_draw.text()` and the clip's notes. One undo step: `u` removes
  all.
  - a chord by holding, then the next note after it
  - the port filter: a key of another port does not enter
  - the pedal: rest, and tie with keys held
  - a mapped control is consumed: it does not enter, and a Lua device on
    the track gets no note
  - the "no MIDI input" message names the reason, and the picker opens
  - nothing enters while the transport plays
  - notation and vocal editor: one test each, in their extensions
- **Rust.** The engine's input filter and the forced follow, as unit tests
  of `paw-engine`.
- **e2e only.** A real ALSA port: `paw.midi.open_port("Step test")` and a
  sequencer client that sends to it. Not run by agents.
- Delete the old tests of the computer piano and of
  `:notes.step_input` (`tests/drawinsert.lua` (the test of `I` as a piano),
  `tests/note_entry.lua` lines 24 and 26, the step block of
  `tests/frontend.lua`).

## What removing the computer piano touches

Recommendation: **remove it** (no option). An option off by default with
no key is code that nobody runs, and the key rule is cleaner without the
letters as notes. A user without a controller has the pencil. A computer
keyboard as a MIDI controller can return as a vinput source later. The
removal touches:

- `runtime/lua/paw/roll_draw.tl`: `roll_insert` option, `keys_once`,
  `M.keys_once`, `M.to_keys`, the branch in `mode.changed`, the
  `INS C%d` label, the warning of the piano letters.
- `runtime/lua/paw/defaults/keys.lua`: the `pianoroll.keys` scope and its
  `imap` block, the `roll_insert == "keys"` branch of `a`, `I` (now step
  input), the pencil's `I`, the letters that say "I types notes as a
  piano", `:notes.step_input`.
- `runtime/lua/paw/views/pianoroll.lua`: `view:enter`, `view:backspace`,
  `view:set_octave` (keep `step`, `set_step`, `step_length`), the Step
  button's tip. `views/pianoroll_mouse.lua`: the Step button calls `I`.
- `runtime/lua/paw/frontend.tl`: the `stepping` block, `M.step_input`,
  `A.toggle_step_input` (moves to `paw.step`).
- `runtime/lua/paw/key bar.lua`: the `pianoroll.keys` lines become the step
  lines.
- `extensions/musicops/lua/musicops/keys.lua` (its wrap of
  `pianoroll.keys` keys) and `extensions/musicops/README.md` line 164.
- `extensions/tutor/lua/tutor/lessons/pianoroll.lua` (the `I` paragraph),
  `extensions/tutor/tests.lua` (the list of views), and the generated
  course in `docs/tutorials/course` (run the generator, do not edit).
- `docs/reference/piano-roll.md` ("the keyboard as a piano" section),
  `docs/reference/options.md` (`roll_insert`), `docs/reference/keys.md`
  (line 239), `docs/reference/limits.md` (lines 67 and 426),
  `docs/reference/window.md` (line 637), and the generated `api.md` and
  `runtime/types` (regenerate).
- Tests as listed above.

## Plan, in order

| # | Part | Size |
| --- | --- | --- |
| 1 | Remove the computer piano and the normal-mode step input, with every page, lesson and test that tells about them. `I` is unbound until part 2 (same day). | S |
| 2 | `paw.step` (Teal): the listener on `midi.in`, the input rule (track's `midi_input` or all), held keys and chords, the target registry, the "no input" message and picker, `:step.input`. The roll's target in `roll_draw.tl`: `I` from normal mode and in the pencil, fill the caret, keep and go on, count repeats, velocity, `step_velocity`, `=` sets the step, `<Space>` rests a step, `<BS>` takes back a rest, the `STEP` title and status, nothing while playing or recording. Tests with `inject`. | M |
| 3 | Engine (Rust): forced follow of the step track, and the input filter that keeps controls from the tracks. Lock-free, unit tests. | M |
| 4 | Controls: `paw.step.bind`, the actions, the pedal default, `:step.learn`, `:step.controls`, the state file, binding by port, the filter fed from the bindings. Tests. | M |
| 5 | Notation target: `enter_pitch`, chords by hold, the actions, `R` and `I` with the controller. Tests in the extension. README and `doc/reference.md`. | S to M |
| 6 | Vocal editor target: `I`, one note per key, top note of a chord. Test, README. | S |
| 7 | Docs: a how-to guide "Enter notes from a MIDI keyboard" with its test in `tests/guides_howto.lua`, the reference section in `piano-roll.md`, the tutor lesson, the key bar. Vale 0 errors. | S |
| later | `paw.opt.step_chord_ms`, a re-pitch way in the roll, a lyric queue for the vocal editor, the drum grid as a target, a "push" mode in the roll. | |

## Questions for the owner (with my recommendations)

1. **Does `i` (the pencil) also take the controller?** Recommended: no.
   Only `I` does. In `i`, the controller only sounds, so you can try a
   phrase on the keyboard while you draw.
2. **Notation: does every insert mode take the controller,** or only a
   key of its own? Recommended: every insert mode (`i` `a` `I` `R`),
   because notation's insert mode is note input as in MuseScore and
   Dorico. `I` is push-insert there and stays.
3. **Remove the computer piano,** or keep it as an option with no key?
   Recommended: remove it.
4. **Chords: hold, or a time window?** Recommended: hold (the release of
   the last key closes the chord). A window is an option later if legato
   playing gives false chords.
5. **While the transport plays,** do the keys enter? Recommended: no.
   They sound, and the title says `paused: playing`. Never while
   recording.
6. **Is the value sticky?** Recommended: yes. `=` sets the step for the
   following notes and rests. `<Space>` then rests one step, not one grid
   step, also in the plain pencil (the same by default).
7. **The sustain pedal by default:** a rest with no key held, a tie with
   keys held? Recommended: yes, on by default, and `paw.step.unbind({ cc =
   64 })` turns it off.
8. **The vocal editor's lyrics:** the default lyric now, a lyric queue
   later? Recommended: yes.
9. **Where the controls live:** in the user's state (by port), not in the
   project as the bindings of learn are? Recommended: the user's state. A
   controller belongs to the musician, not to the song.
10. **Velocity from the key by default?** Recommended: yes, with
    `step_velocity = 100` to fix it.

## Prior art (the research)

| Program | Chord | Value | Rest | Tie | Back | Controls from MIDI |
| --- | --- | --- | --- | --- | --- | --- |
| MuseScore 4 | keys pressed together. Notes go one after the other "so long as you release each key fully" | `1` to `9` first | `0` | `T` | Backspace | MIDI mappings (Preferences), remote control in 3 |
| Dorico | keys played together (chord mode `Q` for the computer) | first, from the keypad | `,` and a value | `T`, Alt-Shift-Right | Backspace | not confirmed |
| Sibelius | step-time: keypad value, then pitches | keypad | keypad 0 | keypad Enter | Backspace | not confirmed |
| Logic Pro | play the chord, or the Chord button | buttons, dot, triplet | **sustain pedal with no key held**, Tab | "Sustain inserted notes" | Step Backward, Delete | key commands folder |
| REAPER | possible | the grid | move the edit cursor | none | none | actions |
| Cubase | possible | the quantize value | Right Arrow | none | none | |
| Ableton Live 12 | keys held when you press Right Arrow | the grid | none | **Right Arrow again while held** | Left Arrow while held | |
| Renoise | more than one key down is a chord | edit step | none | users ask for "held across a step" | none | MIDI mapping |

What paw takes:

- the value first and sticky (all notation programs)
- the chord by holding (MuseScore, Dorico, Renoise)
- the pedal as a rest (Logic), and as a tie with keys held (Ableton)
- controls mapped from the controller (MuseScore, Logic)
- Vim's grammar: a count repeats, `.` repeats, the whole insert is one
  undo step, `<BS>` and `Ctrl-u` take back.

## Sources

- MuseScore 4, entering notes and rests: https://handbook.musescore.org/basics/entering-notes-and-rests
- MuseScore 3, note input modes (remote control, real-time advance): https://handbook.musescore.org/3/advanced-topics/note-input-modes
- Logic Pro, step input: https://help.apple.com/logicpro/mac/10.4/en.lproj/lgcpb19a8406.html and https://help.apple.com/logicpro/mac/9.1.6/help/English.lproj/en/logicpro/usermanual/chapter_14_section_30.html
- Ableton Live 12, MIDI step recording (19.3.4): https://www.ableton.com/en/live-manual/12/recording-new-clips/
- REAPER, step input: https://reaper.blog/2017/04/midi_step_and_quantize/
- Renoise, recording and editing notes: https://tutorials.renoise.com/wiki/Recording_and_Editing_Notes
- Renoise forum, note-offs in step mode: https://forum.renoise.com/t/record-midi-note-off-in-step-by-step-mode/35059 and chord suggestions: https://forum.renoise.com/t/shift-or-auto-chord-mode-suggestions/25877
- Dorico, MIDI input setup: https://forums.steinberg.net/t/setting-up-midi-keyboard-for-input/992984 ; inputting chords (summary only): https://steinberg.help/dorico/v4/en/dorico/topics/write_mode/write_mode_note_input/write_mode_note_input_inputting_chords_t.html
- Cubase, step input (summary only): https://steinberg.help/cubase_pro/v13/en/cubase_nuendo/topics/midi_editors/midi_editors_step_input_t.html
- Sibelius reference (not read; summary only): https://resources.avid.com/SupportFiles/Sibelius/2020.3/Sibelius_Reference.pdf
- paw code: `runtime/lua/paw/roll_draw.tl`, `runtime/lua/paw/defaults/keys.lua`,
  `runtime/lua/paw/views/pianoroll.lua`, `runtime/lua/paw/frontend.tl` (stepping),
  `runtime/lua/paw/learn.lua`, `runtime/lua/paw/defaults/transport.lua`
  (follow), `crates/paw-core/src/api/engine.rs` (`engine_follow`),
  `extensions/notation/lua/notation/init.lua` and `keys.lua`,
  `extensions/utau/lua/utau/editor.lua`, `docs/reference/midi.md`,
  `recording.md`, `learn.md`, `piano-roll.md`, `insert-mode.md`, `key-rule.md`.

## Owner decisions (2026-11-22)
All recommended answers accepted (Q1-Q10): only `I` takes notes from the controller; every notation insert mode takes it; remove the computer-keyboard piano; chords = keys held together; no entry while playing; `=` sets the step; pedal default on; default lyric in the vocal editor; bindings per port in user state; velocity from the key (`step_velocity` to fix it). Build only as tickets (TASK-57..63); nothing started.
