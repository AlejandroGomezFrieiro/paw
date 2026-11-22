# Ex commands: ranges, `:s` and `:g`

<!-- tags: ex ex-ranges-s-and-g ranges -->

The command line takes the Ex commands of Vim, and they act over time and tracks where the commands of Vim act over lines. A line is a range followed by a command, so `:5,8d` empties bars 5 to 8. Each line is one undo step with the line as its name, so `u` undoes `:%s/c4/d4/g` at once, and the line goes into the history (`:` then `Up`).

## Ranges of time

A bar is a number, and a beat is `bar.beat` (`5.3`), counted from 1 in the beats of the time signature. Both include the whole of the last one, so `:5,8` ends where bar 9 starts, and `:5.3,5.4` is two beats.

| Range | Covers |
| --- | --- |
| `5`, `5,8`, `5.3,6.1` | a bar; bars 5 to 8; from beat 3 of bar 5 to the end of beat 1 of bar 6 |
| `@19`, `@19.3` | bar 19 of the song, and its third beat, also in a scope with its own bars |
| `%` | the whole song, to the end of the bar where its last clip ends. In a scope with time, the time of the scope. |
| `.`, `$` | the bar of the cursor; the last bar (in a scope with time, its last bar) |
| `.+4`, `$-1`, `5.3+2` | four bars on; the bar before the last; two beats on (after a beat, offsets count beats) |
| `'a,'b` | from mark `a` to mark `b`, exactly. `'a` alone is the bar of the mark. |
| `'<,'>` | the last selection of the focused view: its time, and its tracks in the arrange view, its pitches in the piano roll (a `Ctrl-v` or `V` selection), or the clips chosen with the pointer |

## Ranges of tracks

A range of tracks comes before a range of time.

| Range | Covers |
| --- | --- |
| `t2`, `t2,t4`, `t2,4` | track 2, tracks 2 to 4 |
| `t.` | the track of the cursor |
| `t$` | the last track |
| `t*` | every track |
| `t/Drums/` | every track whose name holds `Drums` |
| `t'<,'>` | the tracks of the selection |

- A range of time alone covers every track. In the piano roll and the score, it covers the notes of the clips that the view edits.
- A range of tracks alone covers whole tracks.
- Both together cover that time on those tracks, so `:t2 5,8d` empties bars 5 to 8 of track 2.
- A range with no command goes there: `:$`, `:t3`, `:'a`, `:@19`.
- In a window narrowed to a scope ([Scopes](narrowing.md)), the ranges see only its tracks and its time. The bars that you type are the bars of the scope, from 1 at its start, and `@19` is bar 19 of the song. In `Song › Bridge`, where the bridge starts at bar 17 of the song, `:%quantize` snaps only the notes of the bridge, and `:3` and `:@19` go to the same bar.
- A number before a command that takes no range is its count: `:3snippet arp`.
- A command that an extension makes with a range gets one: `:5,8notation.transpose 2`.

## Commands

Without a range, most commands take the bar of the cursor (`.`), in the same way that the commands of Vim take the line of the cursor. `:g` and `:v` take the whole song, and the track commands take the track of the cursor.

| Command | Effect |
| --- | --- |
| `:5,8d`, `:5,8d!`, `:t2d` | Empties bars 5 to 8 of every track, and cuts clips at the edges. `d!` removes the time and closes the gap. A range of tracks alone deletes the tracks. The deleted music goes to the register (`:5,8d a` to register `a`), for `p`. In the piano roll: the notes. |
| `:5,8y`, `:5,8y a` | Copies them to the register. |
| `:5,8co 17`, `:5,8co! 17` | Copies bars 5 to 8 to bar 17, over the music there. `co!` makes room. `:t2 co 4` copies track 2 below track 4 (`0` for the top). |
| `:5,8m 17`, `:5,8m! 17` | Moves them. `m!` closes the gap that they leave and makes room where they go. |
| `:5,8>`, `:5,8>>`, `:5,8< 3` | Moves the clips that start there a grid step later, two steps later, three steps earlier. In the piano roll: the notes, by its grid. |
| `:5,8j` | Joins the MIDI clips on each track into one. |
| `:5,8transpose 12` | Moves notes by semitones. |
| `:%quantize`, `:%quantize 1/16` | Snaps notes to the grid of the piano roll, or to a note value or a count of beats. |
| `:t2,t4 mute`, `:t* unmute`, `:t/Drums/ solo`, `:t* unsolo` | Mutes and solos tracks. `mute!` and `solo!` switch each track. `:5,8 mute` mutes the clips in bars 5 to 8. |
| `:t* volume -=3`, `:t2 volume -6` | Steps the volume of tracks down 3 dB. Sets it to -6 dB. |
| `:t2 pan -0.5`, `:t2 pan +=0.1` | Sets the pan, from -1 (left) to 1 (right). Steps it to the right. |
| `:5,8normal x`, `:t* normal gcc` | Types keys at the start of each bar of the range, on each of its tracks. With a range of tracks, at each track. |
| `:%s/pattern/replacement/flags` | Changes what matches (below). |
| `:&`, `:&&` | Does the last `:s` again on a range, without and with its flags. |
| `:g/pattern/command` | Runs a command on every match: `:g/vel<20/d`, `:g/name:Verse/mute`, `:g/c4/normal x`. With no command, `:g/vel<20/` puts the matches in the quickfix list, for `]q` and `:cdo`. |
| `:g!`, `:v` | Runs a command on everything that does not match. |

## Patterns

A pattern matches notes, clips or tracks by their properties. All terms next to each other must match, `|` in a term gives alternatives, and `!` before a term gives "not".

| Term | Matches |
| --- | --- |
| `c4`, `c#4`, `bb3`, `60` | notes on that key |
| `c`, `f#` | notes on that key, in any octave |
| `vel>100`, `vel<=20`, `vel=64` | notes by velocity |
| `len<1/8`, `len>=2` | notes by length, as a note value or in beats |
| `beat=1`, `beat>=3` | notes by where they start in their bar: 1 is the downbeat, 2.5 is the "and" of 2 |
| `name:Verse`, `name=Verse` | clips whose name holds `Verse`, or is `Verse`. Case does not count. A term has no spaces. |
| `track:Bass` | things on tracks whose name holds `Bass`, or the tracks |
| `*` | everything: notes in the piano roll, clips in the arrange view |

The deepest field in the pattern gives what matches, so `c4` matches notes, `name:Verse` matches clips, and `track:Bass` alone matches tracks. `name:Verse c4` matches the C4 notes of clips named Verse. A different character can delimit the pattern, as in Vim, for example `:%s#len<1/8#len=1/8#g`. An empty pattern is the last pattern.

## Replacements

A replacement sets fields of what matches, as the table below shows.

| Replacement | Sets |
| --- | --- |
| `d4` | the key. A key without an octave (`d`) keeps the octave of the note. |
| `+12`, `-3` | the pitch, in semitones |
| `vel=90`, `vel+10` | the velocity |
| `len*2`, `len=1/16` | the length |
| `name:Chorus` | the part of the name that the pattern found: `Verse 2` becomes `Chorus 2` |
| `name=Chorus` | the whole name |

A replacement can set several fields, for example `vel=90 len=1/8`. An empty replacement removes what matches, for example `:%s/vel<10//g`.

## Flags

| Flag | Effect |
| --- | --- |
| (none) | Only the first match in each bar changes, because a bar is the line of Ex. |
| `g` | Every match changes. `:set gdefault` reverses `g`. |
| `c` | Asks about each match in turn, lit in the view that shows it: `y` yes, `n` no, `a` this and all the others, `l` this and stop, `q` or `Esc` stop. The changes occur when the questions end, as one undo step. |
| `n` | Only counts the matches. |

## The preview

While you type, the line shows what it will do, in the same way as `inccommand` of Neovim.

- The range is shaded on the rulers, and its tracks are marked in the headers.
- The matches are lit: clips in the arrange view, with the number of their notes that match.
- A replacement shows each note as it will be, as a ghost in the piano roll.
- The right end of the command line counts the matches ("12 notes match", "12 notes match, 4 change (g: all)"), or says what is wrong with the line.

Nothing changes until `Enter`, and `Esc` keeps everything as it was. `Tab` completes command names after a range, marks after `'`, track names after `t/`, and field names in a pattern.

The query language of [Structural queries](queries.md) is a different way to find things in the project.
