# How to insert clips, regions and markers with keys

<!-- tags: insert-with-keys insert mode -->

This guide shows you how to put clips, regions, markers and automation
points on the timeline from the keyboard. For all the keys, see
[Insert mode in the arrange view](../reference/insert-mode.md).

## Insert clips

1. Put the cursor on a track, at the bar where the clip starts.
2. Press `i`. The status line shows `INSERT`.
3. Press `m`. An empty MIDI clip starts at the cursor. The cursor moves to
   its end.
4. Press `m` again for the next clip, or `3m` for three clips.
5. Press `Esc`. All the clips that you inserted are one undo step: `u`
   removes them.

To make a clip and put notes in it, press `i` and then `Enter`. paw opens
the clip under the cursor in the piano roll, or makes one if there is
none. See [How to change the velocity, length and pitch of notes](edit-notes.md).

## Insert a region, a marker or an automation point

In insert mode:

- Press `r` for a region. It is as long as a clip. `Enter` after it asks for
  its name.
- Press `'` for a marker. `Enter` after it asks for its name.
- Press `a` for an automation point, at the value that the lane has there.

## Correct a mistake

- `Backspace` removes the item that you inserted last. The cursor returns
  to its start.
- `K` tells what each key inserts.
- A clip does not go over a clip that is there. A message tells you why.

## See also

- [How to personalize insert mode](personalize-insert-mode.md)
