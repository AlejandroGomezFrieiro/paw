# The piano roll

<!-- tags: pianoroll roll -->

The piano roll shows the notes of a MIDI clip: pitches as rows, time as
columns. `Enter` on a clip in the arrange view opens it, and `<Space>vp` shows it.
The keys that it shares with the arrange view are in
[Motions, operators and modes](grammar.md).

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

<!-- tags: insert-mode -->

Insert mode draws a note with the cursor. In the arrange view, `i` opens
the clip under the cursor, or a new clip. In the piano roll, `i` starts at
the cursor, and `a` where the note under the cursor ends (one grid step on,
if there is no note).

A note starts at the pitch of the cursor, with no length. The cursor stays
at the end of the note, so what you see is what paw will write. The note
shows in the green of insert mode. The title and the start of the bottom
line give the note: `DRAW C4  2 steps · 0.5 beats  vel 100`.

| Keys | Effect |
| --- | --- |
| `l` `h` | Makes the note one grid step longer or shorter. A count goes first: `4l` is a beat at the usual grid. |
| `j` `k` | Moves the note a semitone. |
| `Ctrl-d` `Ctrl-u`, `J` `K` | Moves the note an octave. The arrow keys also move it. |
| `[` `]` | Change the velocity. |
| `Enter` | Keeps the note, and draws the next one where it ends (legato). |
| `Space` | Keeps the note, and draws the next one a step after it ends, with a rest between (`3 Space` three steps). |
| `o` | Keeps the note, and draws another with the same start and length, for a chord. Then `k` moves it up to its pitch. |
| `Backspace` | Removes the last kept note, to draw it again. |
| `Esc` | Writes the notes and returns to normal mode. |

At `Esc`, paw gives the number of notes written (`wrote 4 notes`), drawn or
typed.

- paw does not write a note with no length.
- A note drawn over a note of the same pitch with the same start replaces it.
- The clip grows by whole bars to hold notes that go past its end.
- Nothing goes into the project until insert mode ends. All of insert mode is one undo step. When `i` in the arrange view makes a new clip, the clip is in the same undo step.
- `.` draws the same shape again from the cursor, moved to its pitch, as Vim repeats an insert.
- Where the roll edits several clips, the notes go into the active clip (or, outside it, into the clip where the note starts).
- When a suggestion shows, its keys come first: `Esc` dismisses it, and the next `Esc` leaves insert mode.

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
