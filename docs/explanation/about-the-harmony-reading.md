# About the harmony reading

paw names the chords and the key of a song from its notes, without help
from the person. A chord name must not change on each passing tone, and a
key must not change at each chord that is not in the key. This page tells
how the built-in reading in `paw.harmony` gets this result, and how other
readings can replace it. For the functions and options, see
[Harmony](../reference/harmony.md).

## Chords: windows and scores

The reading cuts time into windows of half a beat
(`paw.opt.harmony_step`). In each window, it gives each pitch class a
weight: how long the pitch class sounds. A short note off the beat counts
half. The lowest note counts half again.

Then the reading gives a score to each possible chord: twelve roots and
twenty qualities. The score is:

- the weight of the tones of the chord,
- less the weight of the other pitch classes,
- less a value for each tone that is not there (no fifth costs little),
- less a small value for each tone after the third,
- plus a bonus when the bass is the root.

A chord continues from window to window until a different chord fits
better by more than the cost of a change. So the passing tones of a melody
do not make chords of their own, and the shortest chord is about one beat.

A window with only one pitch gets the weight of the rest of its beat too.
So an arpeggio in eighths still gives its chord. But a melody alone, one
note on each beat, gives no chords.

## Keys: profiles and the cost of a modulation

For each bar, the reading adds the pitch classes of the bar, and half of
the bars next to it. It adds a quarter of the bars after those.
It adds the roots of the chords of the bar again. It compares this sum with the major and minor key profiles
of Krumhansl and Kessler, for all twelve tonics. A key loses score for
each pitch class outside its scale, and each bar moves a little toward the
key of the full song.

A key continues until a different key fits better by more than the cost
of a modulation. This cost is about the weight of a few bars. So the reading
finds a modulation where the new key is established, usually at its
dominant. It does not find it at a pivot chord that belongs to both keys.

## How the reading follows the edits

A song can have many thousands of notes. To read all of them again after
each key takes too much time, so the reading keeps its work:

- It keeps the notes of each clip with the stamp of the clip. The stamp
  changes when the notes change.
- After an edit, it looks only at the tracks that the edit changed. A
  change that does not change the notes, for example a volume, a device or
  a selection, starts no reading.
- It reads again only the windows and the bars where the notes changed.
  The choice of chords and keys over the windows is quick, so it does
  this choice again for all of the song. So the result is the same as a
  reading of all the notes.

The reading starts some milliseconds after the edit. It works in parts of
a few milliseconds, so the next key does not wait for it. Until the new
reading is complete, the chord row of the piano roll and the ruler show
the reading from before the edit. They show the new reading when it is
complete. A Lua function such as `paw.harmony.chords` waits for the new
reading, so a script always gets the reading of the notes as they are.

## Why a provider can replace the reading

A rule-based reading is fast and works without other programs. But a
language server such as MIDI LSP knows more: it finds the function of each
chord (`T`, `S`, `D`). So `paw.harmony` takes its reading from providers,
by priority. A provider answers for the range that it knows, and the
providers below it fill the rest of the song. The piano roll, snippets
and suggestions do not need to know where a chord came from.

## How the reading is tested

The tests (`tests/harmony.lua`) use the demo song
(`examples/demo-song.lua`, in A minor: Am F C E, two times). They also use
progressions written for the tests:

- inversions and sevenths
- half-diminished and diminished chords
- a melody of passing tones over block chords
- a modulation from C major to G major.

## Limits

The limits of the reading are in
[Limits](../reference/limits.md): for example, a chord shorter than about
a beat is read as passing tones.
