# About the harmony reading

paw names the chords and the key of a song from its notes, without help
from you. A chord name must not change on each passing tone, and a key
must not change at each chord that is not in the key. The page explains
how the built-in reading in `paw.harmony` gets that result, and how other
readings can replace it. For the functions and options, see
[Harmony](../reference/harmony.md).

## How the reading finds chords with windows and scores

The reading cuts time into windows of half a beat
(`paw.opt.harmony_step`). In each window, it gives each pitch class a
weight, which is how long the pitch class sounds. A short note off the beat
counts half, and the lowest note counts half again.

Then the reading gives a score to each possible chord, which means twelve
roots and twenty qualities. The score starts with the weight of the tones
of the chord, and then the reading changes it as follows:

- It takes away the weight of the other pitch classes.
- It takes away a value for each tone that is not there, and a missing
  fifth costs little. It also takes away a small value for each tone after
  the third.
- It adds a bonus when the bass is the root.

A chord continues from window to window until another chord fits better by
more than the cost of a change. The passing tones of a melody therefore do
not make chords of their own, and the shortest chord is about one beat.

A window with only one pitch also gets the weight of the rest of its beat,
so an arpeggio in eighths still gives its chord. But a melody alone, with
one note on each beat, gives no chords.

## How the reading finds keys with profiles and the cost of a modulation

For each bar, the reading adds the pitch classes of the bar, half of the
bars next to it, and a quarter of the bars after those. It also adds the
roots of the chords of the bar again. It compares the sum with the major
and minor key profiles of Krumhansl and Kessler, for all twelve tonics. A
key loses score for each pitch class outside its scale, and each bar moves
a little toward the key of the whole song.

A key continues until another key fits better by more than the cost of a
modulation, which is about the weight of a few bars. The reading therefore
finds a modulation where the new key is established, usually at its
dominant, and not at a pivot chord that belongs to both keys.

## How the reading follows the edits

A song can have many thousands of notes, and to read all of them again
after each key takes too much time. The reading therefore keeps its work
in parts, and after an edit it makes again only the parts that the edit
changed:

1. It keeps the notes of each clip with the stamp of the clip, and the
   stamp changes when the notes change. Copies of a clip with the same
   notes share one part.
2. It keeps what each part sounds in each window, and what each part
   sounds in each bar. A window of the song adds up the parts of the
   parts.
3. After an edit, it looks only at what the edit changed. A note edit
   reads its clip again and the windows that the clip covers. A mute of a
   part takes the parts of that part out of the sums, and the parts of
   the other parts stay as they are. A change that does not change the
   notes, e.g., a volume, a device or a selection, reads nothing.

The choice of chords and keys over the windows is quick, so the reading
makes that choice again for the whole song, and the result is the same as a
reading of all the notes at once.

The reading starts some milliseconds after the edit, and it works in parts
of a few milliseconds, so the next key does not wait for it. Until the new
reading is complete, the chord row of the piano roll and the ruler show the
reading from before the edit, and they show the new reading when it is
complete. `K` on a note in the piano roll names the chord that the note
starts in, and says `reading` while the new reading is not complete. When
the reading takes more than a second, the status line shows how far it is. A Lua function such as `paw.harmony.chords` waits for the new
reading, so a script always gets the reading of the notes as they are.

## Why a provider can replace the reading

A reading based on rules is fast and works without other programs, but a
language server such as MIDI LSP knows more, because it finds the function
of each chord (`T`, `S`, `D`). `paw.harmony` therefore takes its reading
from providers, by priority. A provider answers for the range that it
knows, and the providers below it fill the rest of the song. The piano
roll, snippets and suggestions do not need to know where a chord came
from.

## How the reading is tested

The tests (`tests/harmony.lua`) use the demo song
(`examples/demo-song.lua`, in A minor, with Am F C E two times). They also
use progressions written for the tests:

- Inversions and sevenths, and half-diminished and diminished chords.
- A melody of passing tones over block chords.
- A modulation from C major to G major.

## Limits

The limits of the reading are in [Limits](../reference/limits.md). For
example, the reading takes a chord shorter than about a beat as passing
tones.
