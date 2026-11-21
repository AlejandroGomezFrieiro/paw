# The piano roll

<!-- tags: pianoroll roll -->

The piano roll shows the notes of a MIDI clip: pitches as rows, time as
columns. `Enter` on a clip in the arrange view opens it, and `<Space>vp` shows it.
The keys that it shares with the arrange view are in
[Motions, operators and modes](grammar.md). Its text objects name the
objects of the music: the note, the chord, the phrase, the voice and the
pitch. See [Objects of the piano roll](grammar.md#objects-of-the-piano-roll).

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
| `E` | Opens the event list: the notes and controller moves of the clip, to change in place. |
| `gC` | Opens the curve of the controller that the strip shows. |
| `gX` | Opens the curve of the note's own expression. |
| `Esc` | Releases the notes chosen with the pointer. The view stays. |
| `Ctrl-w p` | Returns to the window before (the arrange view). |
| `Ctrl-s` | Writes a snippet, for example the dominant of the next chord. `Tab` and `Ctrl-n` step through its choices. See [Completion](completion.md). |

## What the view shows

A note can have an articulation (its MIDI 2.0 attribute). Such a note
shows a short tag of it (`pz` for pizzicato) in place of its pitch. `K` names the
articulation. The instrument of the track can name a key (a drum of a
kit, a keyswitch of a sampler). Such a key shows its name on the keyboard,
and `K` gives it.

A row over the ruler names the chords that sound, read over every pitched
track, with the key on the left (`paw.opt.chords`). A dot on the keyboard
marks the keys that sound at the cursor. The title names the chord there.

### Notes of other tracks

Behind the notes of the clip, the piano roll shows the notes of other
tracks that sound at the same time. Each is a dashed line (`╌`) in a faint
shade of the color of its track, without a name. The notes of the clip are
solid and named. Drum tracks do not show.

`paw.opt.roll_context` sets which tracks show: `"all"`, `"group"` (the
tracks of the group of the clip), `"none"`, or a list of track ids.
`:roll.tracks` lists the tracks and their clips. There, `Enter` on a track
shows or hides its notes.

## Several clips

The piano roll can edit several clips at the same time, as REAPER does
when its edits follow the selection. One clip is active. New notes go
into it, its name is in the title, and the title gives the number of the
other clips edited.

To open several clips, select them in the arrange view (`v` over them, or
the pointer) and press `Enter`.

| Keys | Effect |
| --- | --- |
| `ga` | Makes the clip of the note of a different track under the cursor the active clip, in place of the old one. |
| `gE` | Edits the clip of that note too, or stops the edit of it. |
| `gn` `gN` | Makes the next or the previous edited clip active. |
| `]t` `[t` | Makes the next or the previous track shown the edited track (its clip at the cursor). The notes of the old clip then show behind. |
| `Tab` `Shift-Tab` | Go round the tracks shown. With no track shown, `Tab` goes to the next view. |
| `:roll.only` | Edits one clip again. |

A click on a note behind makes its clip the active clip. In
`:roll.tracks`, `Enter` on a clip adds it or removes it, and `Ctrl-a`
makes it active.

The motions, operators, visual mode, copy and paste act on the notes of all
edited clips. So do the keys on the note under the cursor, and the
operators of musicops. The beats of the cursor are those of the active clip.

- A moved note stays in its own clip and stops at the edges of the clip.
- Notes copied from several clips return into them when you paste while they are edited. Else they go into the clip at the cursor.
- Each command is one undo step, for all the clips that it changes.

## Insert mode: draw notes

<!-- tags: insert-mode pencil -->

Insert mode is a pencil. It draws a new note, or it changes the note
under the cursor. In the arrange view, `i` and `Enter` open the clip
under the cursor, or a new clip (see [Insert mode](insert-mode.md)).

- On an empty place, `i` starts a new note at the cursor, with no length.
  `a` starts it one grid step after the cursor.
- On a note, `i` takes the note at its start, and `a` takes it at its end.
  After `e`, the cursor is where the note ends, and `a` takes it there.

The pencil has an edge: the start or the end of its note. The cursor is
on that edge. `h` and `l` move the edge, so at the end `l` makes the note
longer, and at the start `l` makes it shorter. The note shows in the
green of insert mode. The title and the start of the bottom line give
the note and its edge: `DRAW C4 end  2 steps · 0.5 beats  vel 100`.

| Keys | Effect |
| --- | --- |
| `l` `h` | Move the edge one grid step right or left. A count goes first: `4l` is a beat at the usual grid. |
| `o` | Goes to the other edge. `^` and `0` go to the start, `$` to the end. |
| `+` `-`, `Ctrl-a` `Ctrl-x` | Move the note a semitone. |
| `K` `J` | Move the note an octave. |
| `r` and a name | Moves the note to the nearest pitch of that name: `ra`, `rf#`, `rbb`. |
| `k` `j` | Bend the note up or down at its end, `bend_step` semitones for each key (one by default). |
| `>` `<` | Move the note one grid step later or earlier. |
| `=` and a value | Sets the length as a note value: `=4` is a beat, `=8` an eighth, `=8.` a dotted eighth, `=8t` a triplet eighth. |
| `c` | Makes the note a chord: see [Chords](#chords). |
| `m` and a kind | Puts a mark of the song at the note: see [Marks of the song](#marks-of-the-song). |
| `[` `]` | Change the velocity of the note and of the notes after it. |
| `Enter` | Keeps the note, and draws the next one where it ends (legato). When a note starts there, the pencil takes it. |
| `Space` | Keeps the note, and draws the next one a step after it ends, with a rest between (`3 Space` three steps). |
| `.` | Keeps the note or the chord, and draws it again after it. A count goes first: `3.`. |
| `x` | Erases the note. A note of the clip goes when insert mode ends. |
| `Backspace`, `Ctrl-w` | Take back the last kept note, to draw it again. |
| `Ctrl-u` | Takes back all that this insert drew. |
| `Ctrl-o` | Writes the notes, does one command of normal mode (for example `w`, to the next note), and draws again. |
| `Esc` | Writes the notes and returns to normal mode. |

At `Esc`, paw tells what it did: `wrote 3 notes, changed 1 note`.

- Notes of one pitch do not overlap. A note stops at the next note of its pitch, and paw tells you.
- A note does not go before the start of its clip.
- paw does not write a new note with no length. A note of the clip that you shorten to no length goes.
- A note drawn over a note of the same pitch with the same start replaces it.
- A note that you take keeps its articulation and its data. Its own controllers (its pitch bend, its pressure) move with it.
- The clip grows by whole bars to hold notes that go past its end.
- Nothing goes into the project until insert mode ends. All of insert mode is one undo step. When `i` in the arrange view makes a new clip, the clip is in the same undo step.
- `.` in normal mode draws the same shape again from the cursor, moved to its pitch, as Vim repeats an insert.
- Where the roll edits several clips, the notes go into the active clip (or, outside it, into the clip where the note starts).
- When a suggestion shows, its keys come first: `Esc` dismisses it, and the next `Esc` leaves insert mode.

### Bends

`k` and `j` bend the note with its own pitch bend (MIDI 2.0 per-note pitch
bend). The bend rises or falls from the middle of the note to its end. A
second `k` bends one step more.

paw writes the bend as short steps of the pitch bend of that key in the
clip. A plugin that takes MIDI 2.0 or MPE plays it. The note shows the
bend: an arrow at its end in the terminal, and a line in the window. `K`
in normal mode gives the bend. `gX` opens the pitch bend of the note as a
curve, to draw it by hand.

### Chords

`c` opens a list of chords at the note. The first chord is the chord of
the key on the pitch of the note, in thirds. `c Enter` gives a triad, `4c
Enter` a seventh chord and `5c Enter` a ninth chord. Then come the chords of
the key, and the usual chords on the pitch. Type to search, or type a
symbol. `Enter` draws the chord that you typed, else the chord on the
line.

| Symbol | The chord |
| --- | --- |
| `C`, `Cm`, `Cmaj7`, `Am7b5`, `Csus4`, `C(add9)` | A chord by its root and quality. The root is the nearest to the note. |
| `C3maj7` | With the octave of the root. |
| `F#m9/C#` | With a bass note below. |
| `I`, `ii`, `V7`, `ii7`, `bVII` | A degree of the key. Upper case is major, lower case minor. `o` is diminished, `+` augmented, `ø` half diminished. `7` adds the seventh of the scale. A `b` or `#` counts from the major scale on the tonic. |
| `V6`, `V64` (`V6/4`), `V65`, `V43`, `V42` | An inversion, by its figures. |
| `V/ii`, `V7/V`, `viio7/V` | An applied chord: the chord in the key of that degree. |
| `N6`, `It6`, `Fr6`, `Ger6` | The Neapolitan sixth and the augmented sixths. |

The key is the key of the last key change (`mk`) before the note, else
the key of the project (`:key`). With no key, paw tells you and uses C
major.

The chord replaces the note, and all of its notes are the note that you
draw. `h` `l` `=` `<` `>` `+` `-` `k` `j` change all of them. The title
gives the name of the chord. `Enter` keeps the chord and draws a
note after it. `Esc` keeps it and leaves insert mode.

### Marks of the song

`m` then a kind puts a mark of the song where the note starts. paw asks
for its value. The marks are in the undo step of the insert.

| Keys | Mark |
| --- | --- |
| `mk` | A key change, for example `D minor`. At the start of a song with no key, it sets the key of the project. Else it is a marker named `key D minor`. The chords after it use that key. |
| `mt` | A tempo, for example `96`. `96~` ramps to the next tempo. |
| `ms` | A time signature, for example `6/8`, from the bar of the note (or the next bar, when the note is in a bar). |
| `m'` | A marker with a name. |

### Keys of extensions

An extension adds keys to the pencil with `paw.roll_draw.key(lhs, spec)`.
`spec.run(count, char)` changes the notes that `paw.roll_draw.pen()`
gives, then calls `paw.roll_draw.shown()`. `paw.chords.quality(suffix,
steps)` adds the name of a chord.

## Insert mode: the keyboard as a piano

`I` enters notes with the keyboard as a piano. `:set roll_insert=keys`
makes `i` and `a` do the same.

| Keys | Effect |
| --- | --- |
| `a w s e d f t g y h u j k` | Enter C, C♯, D and the next notes up to the next C, and step on. The middle row is the white keys, the row above it the black keys. |
| A capital letter | Enters the note and does not step on, for chords. |
| `1` to `9` | Set the length of a note, in grid steps. |
| `Space` | Enters a rest. |
| `Backspace` | Steps back and removes the note. |
| `z` `x` | Change the octave. |
| `[` `]` | Change the velocity. |
| `Esc` | Returns to normal mode. |

The clip grows by a bar when the notes go past its end. All of insert mode
is one undo step, as when you draw. The key is `I`
for three reasons. `gi` of Vim may be necessary for "insert where you
stopped". `R` records. `I` of Vim, "insert at the start of the line", is
`0i` here.

## Suggestions

<!-- tags: suggestions -->

With a completion source loaded (`extensions/continue`, a language server),
the piano roll can suggest what comes next. A suggestion shows as dashed
ghost notes in the color of the track, with a badge over them, for example
`1/3 continue: the bar again`. Suggestions come after a pause in the edits
(`paw.opt.complete_auto`), or when you press `Ctrl-Space`. They do not
come while the song plays or records.

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
