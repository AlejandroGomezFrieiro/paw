# Takes

<!-- tags: takes take-lanes comping -->

A clip can hold several versions of what it plays, and the version that
plays is the active take. Recording round the loop makes takes (see
[Recording](recording.md#rules)), and `:take.new` makes a take by hand. For the
steps, see
[How to record takes over a loop and comp them](../how-to/record-takes-and-comp.md).

## Keys and commands

| Keys, command | Effect |
| --- | --- |
| `]t` `[t`, `:take next`, `:take prev` | Make the next take of the clip active, or the take before. |
| `:take 2` | Play the second take. |
| `:take.list` | Select a take from a list. |
| `:take.new` | Keep what the clip plays as a take, and continue in a copy of it. |
| `:take.remove`, `:take.remove 1` | Delete the active take, or take 1. |
| `:take.keep` | Delete all the takes but the active take. |
| `:take.explode` | Put each other take as a clip on a new track of its own. |
| `zt`, `:take.lanes` | Show the takes of the track as lanes below its clips, or hide them. |

In the graphical window, the menu of a clip has a Takes entry with the actions in the table above.

## Comp

To comp is to select the best part of each take.

- Cut the clip where the choice changes (`s`), and select a take for each
  piece.
- Each piece keeps all the takes, aligned, so you can move a cut and change
  a choice later.
- A trim or a slip of the start moves all the takes by the same amount.
- With a time selection, `:take 2` cuts at its ends and plays the second
  take there.
- A piece has the name of the take that it plays. A recording round the
  loop is `take 1`, and its takes are `take 1.1`, `take 1.2` and so on, so a
  piece that plays the second take is `take 1.2`. A name that you gave the
  clip stays.

## Take lanes

`zt` shows the takes of a track as lanes below its clips. `:take.lanes`,
the Takes entry of the menu of a clip, and the menu of the track in the
graphical window do the same.

- Lane k holds take k of each clip of the track that has takes, each over
  the time range of its clip, so the pieces of a comp align in lanes.
- The active take is bright and the other takes are dim, and each piece shows
  the waveform or the notes of its take, and its name.
- After recording round the loop, the lanes do not open automatically, and
  `zt` shows each time round.
- In the terminal, the lanes are one line each below the track, and they are
  read-only, with the active take bright and showing its name. To comp, use
  `:take 2` on a selection.
- paw remembers which tracks show take lanes for the session, as it does for the
  automation lanes that show as rows, and it does not save them in the project.

### Swipe comping (graphical window)

- Press on lane k and drag across a time range. On release, take k plays
  over that range exactly, and paw cuts the clips at the ends of the range
  where necessary, all as one undo step.
- A click on lane k selects take k for the piece under the pointer.
- The ends go to the grid, unless you hold Shift, and a drag shorter than a
  grid step is a click.
- Adjacent pieces that then play the same take join into one piece where
  the join is exact, so swipes back and forth leave no small pieces. The join is exact under the following conditions.
  - For audio, each take aligns across the join (the same file and gain, and
    the second piece starts in each take where the first ends), the clips have
    the same name and mute state or each has the name of its take, and the
    join has no fade.
  - For notes, the names of the takes match and no note is hidden past the edge
    of either piece. A note cut in two by an earlier cut stays as two notes
    after the join, as it played.

## Stretch and loop

The active take and the other takes all play through the stretch and the
loop of the clip, and a comp keeps both on each piece. paw joins pieces again
only where they have the same stretch, shift and loop, and the second
piece continues the repeats of the first. In the take lanes, the active
take shows as it plays, and a different take shows its file, compressed or
expanded in time by the stretch of the clip and repeated as the clip
loops.

## Lua

| Function | Effect |
| --- | --- |
| `paw.takes.count(clip)` | The number of takes. |
| `paw.takes.select(clip, n)` | Make take n the active take. |
| `paw.takes.step(clip, 1)` | Play the next take. |
| `paw.takes.new(clip)` | Make a take. |
| `paw.takes.remove(clip, n)` | Delete take n. |
| `paw.takes.keep(clip)` | Delete all the takes but the active take. |
| `paw.takes.explode(clip)` | Put the other takes on new tracks. |
| `paw.takes.comp(track, n, from, to)` | Play take n over beats `from` to `to`, then join the pieces as above. |
| `paw.takes.choose_at(track, n, beat)` | Play take n in the piece at a beat. |
| `paw.takes.join_pieces(track, from, to)` | Join the pieces in a range where the join is exact. |
| `paw.takes.content(clip, n)` | What take n plays: the file, offset and gain, or the notes. |
| `paw.takes.show_lanes(track, on)` | Show or hide the take lanes. |
| `paw.takes.lane_count(track)` | The number of lanes. |
| `paw.frontend.act.take_lanes(track)` | The gesture that shows the lanes. |
| `paw.frontend.act.comp(track, n, from, to, free)` | The swipe gesture. |
| `paw.frontend.act.take_click(track, n, beat)` | The click gesture. |
| `paw.frontend.take_preview(clip, n, points)` | The drawing of a take that does not play. |
| `paw.api.media_peaks(file, offset, seconds, points)` | The waveform of a part of a file. |

- The takes are in `clip.meta.takes` (`runtime/lua/paw/takes.tl` shows
  the format).
- The files of takes that do not play count as files of the project, so paw
  moves them into `media` at the first save, and looks for them as it does for
  other files that it cannot find.
