# How to move, copy, split and trim clips

<!-- tags: edit-clips -->

You can change the clips of the arrange view with keys that act on the
clip under the cursor. A count before a key does it more than one time,
and each key is one undo step, so `u` takes it back. All the keys are in
[Motions, operators and modes](../reference/grammar.md).

To put the cursor on a clip, press `w` for the next clip or `b` for the
start of the current clip. Press `j` and `k` to go to a different part.

<!-- paw-live: {"project": "demo-song"} -->

## Move a clip

- Press `L` to move the clip one grid step later, and `H` to move it
  earlier. `4L` moves it four steps.
- To move a clip to a different part, press `x` to cut it, move the
  cursor to the new place, and press `P`.

## Copy a clip

1. Press `yic`, and paw copies the clip under the cursor.
2. Move the cursor to where the copy must start.
3. Press `P`, and the copy starts at the cursor.

To repeat the clip right after itself, press `&`, and press `&` again for
the next copy. A count makes more copies, so `4&` puts four copies after
the clip.

## Split a clip

1. Put the cursor where the clip must split, for example with `l`.
2. Press `S`, and the clip becomes two clips.

## Trim a clip

- To make the clip shorter at its end, press `<A-h>`, and to make it
  longer, press `<A-l>`. Each press is one grid step.
- To remove the start of a clip, put the cursor at the new start and press
  `S`. Then press `h` to go onto the first part, and `x` to delete it.

To make the steps finer or coarser, press `[g` or `]g`. The status line
shows the grid.

In the graphical window, drag a clip to move it, or drag it with `Ctrl` to
copy it. Drag an edge of the clip to trim it. The right-click menu of a
clip has split.

## See also

- [The arrange view](../reference/arrange-view.md): all its keys.
- [Media files and audio clips](../reference/media.md): fades and the gain of audio clips.
