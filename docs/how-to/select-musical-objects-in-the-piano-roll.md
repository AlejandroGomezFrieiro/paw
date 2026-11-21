# How to select a chord, a phrase, a voice or a pitch in the piano roll

<!-- tags: select-objects text-objects chord phrase voice -->

This guide shows you how to select a chord, a phrase, a voice or a
pitch. For each object, see
[Objects of the piano roll](../reference/grammar.md#objects-of-the-piano-roll).
The guide uses a clip. It has a melody over two chords, a rest, and a
broken chord.

1. In the arrange view, put the cursor on the clip and press `Enter`. The
   piano roll opens.
2. Go to a note with `w`, `b`, `j` and `k`.

## Work on a chord

1. Put the cursor on one note of a chord. Press `yic` to copy the notes
   that start with it, or `dic` to delete them.
2. To include the notes of a broken chord, press `yac`. paw reads the
   chord as [the harmony](../reference/harmony.md) does: every note of
   its phrase that starts while that chord holds.
3. To take in the next chord too, press `vic`, then `ic` again. Press an
   operator to act on both.
4. To go to the next chord or the one before, press `]c` or `[c`.

## Work on a phrase

1. Put the cursor on a note of the phrase. Press `yip` to copy it, or
   `>ip` to move it one step later.
2. To include the rest after the phrase, press `yap`.
3. To go to the next phrase, press `)`. To go to the start of this phrase,
   press `(`.

A rest longer than half a beat ends a phrase. To change this, type
`:set phrase_rest=1.5`.

## Work on a voice

1. Put the cursor on a note of a line. Press `yiv` to copy the line: the
   top line, the second line, or the bass.
2. Press `div` to delete the line. The notes between its notes stay.

## Work on a pitch

1. Put the cursor on a note. Press `vi=` to select every note of its
   pitch.
2. Press `+` to transpose them a semitone up. Press `u` to undo.
3. To select the pitch class in every octave, press `va=`.

## See also

- [How to change the velocity, length and pitch of notes, and quantize them](edit-notes.md)
- [Motions, operators and modes](../reference/grammar.md)
