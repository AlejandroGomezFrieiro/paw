# The piano roll

<!-- tags: pianoroll roll -->

The piano roll shows the notes of a MIDI clip, with pitches as rows and time as columns. `Enter` on a clip in the arrange view opens it, and `<Space>vp` shows it. The keys that it shares with the arrange view are in [Motions, operators and modes](grammar.md). Its text objects name the objects of the music, which are the note, the chord, the phrase, the voice and the pitch (see [Objects of the piano roll](grammar.md#objects-of-the-piano-roll)).

## Keys

| Keys | Effect |
| --- | --- |
| `Enter` | Adds or removes a note. |
| `+` `-`, `Ctrl-a` `Ctrl-x` | Transposes the note. A count first gives the semitones. |
| `Alt-l` `Alt-h` | Lengthens and shortens the note. |
| `H` `L` | Moves the note. |
| `]` `[` | Changes the velocity of the note, by 10. |
| `K` | Describes the note. |
| `gh` | Plays the pitch. |
| `E` | Opens the event list, which shows the notes and controller moves of the clip and lets you change them in place. |
| `gC` | Opens the curve of the controller that the strip shows. |
| `gX` | Opens the curve of the note's own expression. |
| `Esc` | Releases the notes chosen with the pointer. The view stays. |
| `Ctrl-w p` | Returns to the window before (the arrange view). |
| `Ctrl-s` | Writes a snippet, e.g., the dominant of the next chord, and `Tab` and `Ctrl-n` step through its choices. See [Completion](completion.md). |

## What the view shows

A note can have an articulation (its MIDI 2.0 attribute), and such a note shows a short tag of it (`pz` for pizzicato) in place of its pitch, and `K` names the articulation. The instrument of the track can name a key (a drum of a kit, a keyswitch of a sampler), and such a key shows its name on the keyboard, and `K` gives it.

A row over the ruler names the chords that sound, read over every pitched track, with the key on the left (`paw.opt.chords`). A dot on the keyboard marks the keys that sound at the cursor, and the title names the chord there.

### Notes of other tracks

Behind the notes of the clip, the piano roll shows the notes of other tracks that sound at the same time. Each is a dashed line (`╌`) in a faint shade of the color of its track, without a name, while the notes of the clip are solid and named, and drum tracks do not show.

`paw.opt.roll_context` sets which tracks show, with the values `"all"`, `"group"` (the tracks of the group of the clip), `"none"`, or a list of track ids. `:roll.tracks` lists the tracks and their clips, and `Enter` on a track there shows or hides its notes.

## Several clips

The piano roll can edit several clips at the same time. One clip is active, new notes go into it, its name is in the title, and the title gives the number of the other clips edited.

To open several clips, select them in the arrange view (`v` over them, or the pointer) and press `Enter`.

| Keys | Effect |
| --- | --- |
| `ga` | Makes the clip of the note of a different track under the cursor the active clip, in place of the old one. |
| `gE` | Edits the clip of that note too, or stops the edit of it. |
| `gn` `gN` | Makes the next or the previous edited clip active. |
| `]t` `[t` | Makes the next or the previous track shown the edited track (its clip at the cursor). The notes of the old clip then show behind. |
| `Tab` `Shift-Tab` | Go round the tracks shown. With no track shown, `Tab` goes to the next view. |
| `:roll.only` | Edits one clip again. |

A click on a note behind makes its clip the active clip. In `:roll.tracks`, `Enter` on a clip adds it or removes it, and `Ctrl-a` makes it active.

The motions, operators, visual mode, copy and paste act on the notes of all edited clips, and so do the keys on the note under the cursor and the operators of musicops. The beats of the cursor are those of the active clip.

- A moved note stays in its own clip and stops at the edges of the clip.
- Notes copied from several clips return into them when you paste while they are edited, and otherwise they go into the clip at the cursor.
- Each command is one undo step, for all the clips that it changes.

## Insert mode: draw notes

<!-- tags: insert-mode pencil -->

Insert mode draws a new note, or it changes the note under the cursor, with a pencil that has an edge. In the arrange view, `i` and `Enter` open the clip under the cursor, or a new clip (see [Insert mode](insert-mode.md)).

- On an empty place, `i` starts a new note at the cursor, with no length, and `a` starts it one grid step after the cursor.
- On a note, `i` takes the note at its start and `a` takes it at its end. After `e`, the cursor is where the note ends, and `a` takes it there.

The edge of the pencil is the start or the end of its note, and the cursor is on that edge. `h` and `l` move the edge, so at the end `l` makes the note longer, and at the start `l` makes it shorter. The note shows in the green of insert mode, and the title and the start of the bottom line give the note and its edge, as in `DRAW C4 end  2 steps · 0.5 beats  vel 100`.

| Keys | Effect |
| --- | --- |
| `l` `h` | Move the edge one grid step right or left. A count goes first, so `4l` is a beat at the usual grid. |
| `o` | Goes to the other edge. `^` and `0` go to the start, `$` to the end. |
| `+` `-`, `Ctrl-a` `Ctrl-x` | Move the note a semitone. |
| `K` `J` | Move the note an octave. |
| `r` and a name | Moves the note to the nearest pitch of that name, e.g., `ra`, `rf#` or `rbb`. |
| `k` `j` | Bend the note up or down at its end, `bend_step` semitones for each key (one by default). |
| `>` `<` | Move the note one grid step later or earlier. |
| `=` and a value | Sets the length as a note value, so `=4` is a beat, `=8` an eighth, `=8.` a dotted eighth and `=8t` a triplet eighth. |
| `c` | Makes the note a chord (see [Chords](#chords)). |
| `C` | Makes the note a strummed chord (see [Chords](#chords)). |
| `~` | Ties the note to the next note: its end goes to the start of the next note of the clip, or of the next note that you kept. |
| `Ctrl-r` and a register | Puts the notes of the register at the note, as `p` pastes them. `Ctrl-r a` puts the notes of register `a`, `Ctrl-r "` the last yank, and a count first (`2 Ctrl-r a`) puts them twice. The pencil goes on where the last one ends. A register that holds no notes does nothing and says so. |
| `Tab` | Opens the picker of snippets, and the snippet that you choose writes its notes at the note (see [Snippets](snippets.md)). While a snippet is active, `Tab` goes to its next choice. |
| `a` | Gives the note an articulation, by name. The names come from the articulations extension, which uses the map of the track or the usual words. |
| `e` and a kind | Puts a controller point where the note starts: `em` the modulation wheel, `ee` expression, `eb` breath, `es` the sustain pedal, and `e` and a number any controller. A count first is the value (`100em`), and otherwise paw asks for it. |
| `Ctrl-n` `Ctrl-p` | Suggest what comes next, in place of the note. After a chord, the suggestions are the chords of the key that often follow it, and after a note, they are the notes of the key near it. The next key that edits takes the suggestion, and `Enter` takes it and stays. |
| `Ctrl-e` | Puts back the note from before the suggestions. |
| `m` and a kind | Puts a mark of the song at the note (see [Marks of the song](#marks-of-the-song)). |
| `[` `]` | Change the velocity of the note and of the notes after it. |
| `Enter` | Keeps the note, and draws the next one where it ends (legato). When a note starts there, the pencil takes it. |
| `Space` | Keeps the note, and draws the next one a step after it ends, with a rest between (`3 Space` three steps). A step is the note length of the roll, or a grid step when it has none. |
| `.` | Keeps the note or the chord, and draws it again after it. A count goes first: `3.`. |
| `x` | Erases the note. A note of the clip goes when insert mode ends. |
| `Backspace`, `Ctrl-w` | Take back the last kept note, to draw it again. |
| `Ctrl-u` | Takes back all that this insert drew. |
| `I` | Starts or stops [step input](#step-input). The pen stays as it is. |
| `Ctrl-o` | Writes the notes, does one command of normal mode (for example `w`, to the next note), and draws again. |
| `Esc` | Writes the notes and returns to normal mode. |

At `Esc`, paw tells what it did: `wrote 3 notes, changed 1 note`.

- Notes of one pitch do not overlap, so a note stops at the next note of its pitch, and paw tells you.
- A note does not go before the start of its clip.
- paw does not write a new note with no length, and a note of the clip that you shorten to no length goes.
- A note drawn over a note of the same pitch with the same start replaces it.
- A note that you take keeps its articulation and its data, and its own controllers (its pitch bend, its pressure) move with it.
- The clip grows by whole bars to hold notes that go past its end.
- Nothing goes into the project until insert mode ends, and all of insert mode is one undo step. When `i` in the arrange view makes a new clip, the clip is in the same undo step.
- `.` in normal mode draws the same shape again from the cursor, moved to its pitch, as Vim repeats an insert.
- Where the roll edits several clips, the notes go into the active clip (or, outside it, into the clip where the note starts).
- When a suggestion shows, its keys come first, so `Esc` dismisses it and the next `Esc` leaves insert mode.

### Bends

`k` and `j` bend the note with its own pitch bend (MIDI 2.0 per-note pitch bend). The bend rises or falls from the middle of the note to its end, and a second `k` bends one step more.

paw writes the bend as short steps of the pitch bend of that key in the clip, and a plugin that takes MIDI 2.0 or MPE plays it. The note shows the bend as an arrow at its end in the terminal and as a line in the window, and `K` in normal mode gives the bend. `gX` opens the pitch bend of the note as a curve, to draw it by hand.

### Chords

`c` opens a list of chords at the note. The first chord is the chord of the key on the pitch of the note, in thirds, so `c Enter` gives a triad, `4c Enter` a seventh chord and `5c Enter` a ninth chord. The chords of the key come next, and then the usual chords on the pitch. Type to search, or type a symbol, and `Enter` draws the chord that you typed, or the chord on the line if you typed none.

| Symbol | The chord |
| --- | --- |
| `C`, `Cm`, `Cmaj7`, `Am7b5`, `Csus4`, `C(add9)` | A chord by its root and quality. The root is the nearest to the note. |
| `C3maj7` | With the octave of the root. |
| `F#m9/C#` | With a bass note below. |
| `I`, `ii`, `V7`, `ii7`, `bVII` | A degree of the key, where upper case is major and lower case is minor, `o` is diminished, `+` is augmented and `ø` is half diminished. `7` adds the seventh of the scale, and a `b` or `#` counts from the major scale on the tonic. |
| `V6`, `V64` (`V6/4`), `V65`, `V43`, `V42` | An inversion, by its figures. |
| `V/ii`, `V7/V`, `viio7/V` | An applied chord, which is the chord in the key of that degree. |
| `N6`, `It6`, `Fr6`, `Ger6` | The Neapolitan sixth and the augmented sixths. |

The key is the key of the last key change (`mk`) before the note, or the key of the project (`:key`) if there is none. With no key, paw tells you and uses C major.

`C` opens the same list and strums the chord, so each note starts a 64th note after the note below it (`paw.opt.strum`, in beats). A count gives the 64ths, as in `2C`, and `:set strum_dir=down` strums from the highest note. The notes of a strum end together.

The picker of `C` also reads words at the end of what you type: `up`, `down` or `updown` for the way of this strum, and `@` and a number for the gap in 64ths. For example, `Cmaj7 down @2` strums C major seventh from the highest note, two 64ths apart. `updown` rises through the first, third and fifth note and so on, and falls through the others. The words and the count of `C` replace `paw.opt.strum_dir` and `paw.opt.strum` for that strum.

The chord replaces the note, and all of its notes are the note that you draw, so `h` `l` `=` `<` `>` `+` `-` `k` `j` change all of them. The title gives the name of the chord. `Enter` keeps the chord and draws a note after it, and `Esc` keeps it and leaves insert mode.

### Marks of the song

`m` and a kind puts a mark of the song where the note starts, and paw asks for its value. The marks are in the undo step of the insert.

| Keys | Mark |
| --- | --- |
| `mk` | A key change, e.g., `D minor`. At the start of a song with no key, it sets the key of the project, and otherwise it is a marker named `key D minor`. The chords after it use that key. |
| `mt` | A tempo, e.g., `96`, and `96~` ramps to the next tempo. |
| `ms` | A time signature, e.g., `6/8`, from the bar of the note (or the next bar, when the note is in a bar). |
| `mr` | A region from the note to its end (a bar when the note has no length), with a name or none. |
| `m'` | A marker with a name. |

### Keys of extensions

An extension adds keys to the pencil with `paw.roll_draw.key(lhs, spec)`. `paw.roll_draw.articulation(provider)` gives `a` its names and what they set on a note, and the articulations extension uses it. `spec.run(count, char)` changes the notes that `paw.roll_draw.pen()` gives and then calls `paw.roll_draw.shown()`, and `paw.chords.quality(suffix, steps)` adds the name of a chord.

The key bar of the pencil shows the keys of extensions after its own keys, with the start of each `spec.desc`. `spec.order` gives their order: a lower number comes first, and keys with the same number go by their names. The default is 50. `paw.roll_draw.keys` holds them by key, and when an extension unloads, its keys go.

## Step input

<!-- tags: step-input -->

Step input enters notes from the keys of a MIDI controller, such as a keyboard, pads, a wind controller, or a guitar through vinput. `I` in normal mode starts it with a caret at the cursor, and the caret is a pen with no length. `I` in insert mode starts or stops it. Step input is the pencil of insert mode, so all the keys of the pencil work at the same time, and `Esc` writes all the notes as one undo step.

| On the controller | Effect |
| --- | --- |
| A key, with no other key held | Keeps the pen if it has a length, and enters the note at its end, or at the caret when the pen has no length. The note is one step long and has the velocity of the key, and the cursor goes to its end. A count typed before it, e.g., `3`, enters the note that many times. |
| More keys while one is held | Join the pen as one chord, with the same start and length. |
| The last key released | Closes the chord, so the next key enters after it. |
| Other messages | Only sound, and step input doesn't enter them. |

| Keys | Effect in step input |
| --- | --- |
| `=` and a value | Sets the step, which is the length of the pen and of the notes and rests that follow, e.g., `=8.` for dotted eighths and `=8t` for triplet eighths. The step is the note length of the roll. |
| `Space`, `3 Space` | Keeps the pen and rests one step, or three steps. |
| `Backspace`, `Ctrl-w` | Takes back what you entered last. The pen goes, and the note or chord before it becomes the pen again. After a rest, the caret goes one step back. |
| `+` `-`, `K` `J`, `r` and a name | Change the pitch of the pen, so you can fix a wrong key without playing it again. |
| `h` `l`, `o` | Move the edge of the pen. They change only this note, not the step. |
| `x` | Erases the pen and leaves the caret at its start, so you can play again there. |
| `I` | Stops step input, and you stay in the pencil. |

The title shows what step input does, e.g., `STEP C4 E4 · 1 beat (=4) · vel key · from Keystation 49`, and while keys are held it shows `STEP holding C4 E4`. The key bar shows the keys of step input.

- The step is the note length of the roll, or a grid step when the roll has no note length. The Note tool of the roll shows it.
- `paw.opt.step_velocity` is `"key"` to use the velocity of each key, or a number from 1 to 127 to use for all notes.
- Step input listens to the MIDI input of the track of the active clip, which is its port and its channel (`:track.midi`). A track with no MIDI input listens to all ports. While step input is on, that track plays the controller, even when another track is armed.
- Step input records nothing. While the song plays or records, the keys only sound, and the title shows `STEP (paused: playing)`.
- When there is no MIDI input, `I` says why and opens the MIDI part of the list of inputs of the track. The pencil still works, and keys that arrive later enter. Step input has no input when no MIDI port is listed, when no port is open (the engine runs without an audio device), or when the port of the track is missing.
- `:step.input` says what step input listens to, and opens the same list.
- When a port goes away, step input releases the keys held on it.
- A key that an input filter maps (`paw.api.engine_midi_filter`) doesn't enter.
- A view of an extension takes step input with `paw.step.target(name, spec)`. See `paw.step` in the [Lua API](api.md).

### Controls of the controller

<!-- tags: step-controls -->

A key, pad or pedal of the controller can do an action of step input in place of a key of the computer. The sustain pedal works with no setup: pressed with no key held, it rests one step, and pressed while keys are held, it makes them one step longer.

| Action | Effect, as the key of the pencil does it |
| --- | --- |
| `rest` | Rests one step (`Space`). |
| `tie` | Makes the pen one step longer. |
| `back` | Takes back what you entered last (`Backspace`). |
| `erase` | Erases the pen (`x`). |
| `again` | Enters the pen again after itself (`.`). |
| `legato` | Keeps the pen, and the next note starts where it ends (`Enter`). |
| `dur.1` `dur.2` `dur.4` `dur.8` `dur.16` `dur.32` | Sets the step to that note value (`=1` to `=32`). |
| `dot`, `triplet` | Turns the dot or the triplet of the step on or off. |
| `octave.up`, `octave.down` | Moves the pen an octave up or down (`K` `J`). |
| `chord` | While the control is held, the keys join one chord, also after you release them. |
| `finish` | Ends insert mode and writes the notes (`Esc`). |

| Command | Effect |
| --- | --- |
| `:step.learn {action}` | Waits for the next key, pad or pedal of the controller, and binds it to the action by its port, channel and note or controller number. `Tab` completes the actions, and `Esc` stops the wait. |
| `:step.controls` | Lists the controls. `Alt-d` removes one. |

- A control works while step input is on. Then it doesn't enter a note, doesn't sound and doesn't record, and the title shows what it did for a moment, e.g., `STEP rest`. When step input is off, the control plays as before.
- An action that the view doesn't have shows `not here: <action>`.
- The controls belong to you, not to the song. `:step.learn` and a removal in `:step.controls` write them to `step-controls.json` in the state folder, and paw reads that file when it starts. With `--clean`, paw reads and writes no such file.
- In `init.lua`, `paw.step.bind(source, action)` binds a control for the session. `source` is `{ port, channel, note }` or `{ port, channel, cc }`, where `port` and `channel` are optional. `action` is a name from the table, `{ keys = "=8t" }` to type those keys of the pencil, or `{ down = "rest", held = "tie" }` for one action with no key held and another while keys are held, as the pedal has.
- `paw.step.unbind({ cc = 64 })` takes the default away from the pedal, so it sustains again. `paw.step.bindings()` lists the controls, and `paw.step.action(name, fn)` adds an action from an extension.

```lua
paw.step.bind({ port = "nanoPAD", note = 36 }, "rest")
paw.step.bind({ port = "Keystation", note = 21 }, "dur.1")
paw.step.bind({ port = "Keystation", note = 23 }, { keys = "=8t" })
```

## Suggestions

<!-- tags: suggestions -->

With a completion source loaded (`extensions/continue`, a language server), the piano roll can suggest what comes next. A suggestion shows as dashed ghost notes in the color of the track, with a badge over them, e.g., `1/3 continue: the bar again`. Suggestions come after a pause in the edits (`paw.opt.complete_auto`), or when you press `Ctrl-Space`, and they do not come while the song plays or records.

| Keys | Effect |
| --- | --- |
| `Ctrl-Space` | Asks the completion sources for a suggestion. |
| `Tab` | Accepts all of the suggestion. |
| `Ctrl-l` | Accepts its next note or chord. |
| `Ctrl-n` `Ctrl-p` | Show the next and the previous alternative. |
| `Alt-1` to `Alt-9` | Show that alternative. |
| `gh` | Plays the suggestion from a bar before. |
| `Ctrl-e`, `Esc` | Dismiss the suggestion. In insert mode, the first `Esc` dismisses it and the second leaves insert mode. |

See [Completion](completion.md).
