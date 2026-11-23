# How to insert clips, regions and markers with keys

<!-- tags: insert-with-keys insert mode -->

You can put clips, regions, markers and automation points on the timeline
from the keyboard, in insert mode. All the keys are listed in
[Insert mode in the arrange view](../reference/insert-mode.md).

<!-- paw-live: {"project": "demo-song"} -->

## Insert clips

1. Put the cursor on a track, at the bar where the clip starts, and press
   `i`. The status line shows `INSERT`.
2. Press `m`, and an empty MIDI clip starts at the cursor. The cursor moves
   to its end.
3. Press `m` again for the next clip, or `3m` for three clips.
4. Press `Esc`. All the clips that you inserted are one undo step, so `u`
   removes them.

To make a clip and put notes in it, press `i` and then `Enter`. paw opens
the clip under the cursor in the piano roll, or makes one if there is
none. The next steps are in
[How to change the velocity, length and pitch of notes](edit-notes.md).

## Insert a region, a marker or an automation point

In insert mode, you can also insert other things:

- Press `r` for a region, which is as long as a clip. `Enter` after it
  asks for its name.
- Press `'` for a marker. `Enter` after it asks for its name.
- Press `a` for an automation point, at the value that the lane has there.

## Correct a mistake

- `Backspace` removes the item that you inserted last, and the cursor
  returns to its start.
- `K` tells what each key inserts.
- A clip does not go over a clip that is already there, and a message
  tells you why.

## See also

- [How to personalize insert mode](personalize-insert-mode.md)
