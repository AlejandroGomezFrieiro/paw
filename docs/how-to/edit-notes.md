# How to change the velocity, length and pitch of notes, and quantize them

<!-- tags: edit-notes quantize-notes -->

This guide shows you how to correct the notes of a MIDI clip in the piano
roll. For all the keys, see [The piano roll](../reference/piano-roll.md).

1. In the arrange view, put the cursor on the clip and press `Enter`. The
   piano roll opens with the notes of the clip.
2. Press `w` and `b` to go from note to note, and `j` `k` to change the
   pitch of the cursor.

## Change one note

| To change | Keys |
| --- | --- |
| the velocity | `]` louder, `[` softer, by 10 |
| the length | `<A-l>` longer, `<A-h>` shorter, by one grid step |
| the pitch | `+` up, `-` down, a semitone. `12+` is an octave |
| the start | `L` later, `H` earlier, by one grid step |

`K` describes the note under the cursor: its pitch, start, length and
velocity.

## Change many notes

1. Select the notes. Press `v` and move the cursor over them, or type
   `vie` to select every note of the clip.
2. Press the key of the change:
   - `]` or `[` for the velocity.
   - `12<C-a>` to transpose the notes an octave up, `5<C-x>` five
     semitones down.
3. The change ends the selection, as in Vim. To make one more change to
   the same notes, press `gv` to select them again, then the key.

## Quantize

1. Choose the grid: press `[g` for a finer grid or `]g` for a coarser
   grid. The status line shows the grid, for example `grid 1/16`.
2. Type `:notes.quantize`. paw moves the start of each note to the grid
   and gives the number of notes moved.

To quantize only a part, select it first with `v`. To move the notes only
half of the distance to the grid, type `:notes.quantize 50`.

To quantize the starts and the lengths too, press `=ie` (all the notes of
the clip). `=` takes any selection or motion, for example `=ib` for this
bar.

In the graphical window, drag a note to move it, and drag its end to
change its length. The strip under the notes shows the velocities.

## See also

- [How to undo, and return to an earlier state](undo-and-return-to-an-earlier-state.md)
- [MIDI](../reference/midi.md#edit-controller-moves): the velocities and controllers in the strip, the event list.
