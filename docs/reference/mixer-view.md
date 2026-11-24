# The mixer

<!-- tags: mixer -->

The mixer shows a strip for each part, and `<Space>mm` opens it. The strips form a grid, where `h` and `l` go from strip to strip and `j` and `k` go along the rows of a strip, from the top to the bottom. The rows of a strip are its devices (inserts), its sends, the fader, the pan, mute, solo, arm and the input monitor.

## What the view shows

- A strip has a name plate, meters with the peak held, a fader with 0 dB marked, the pan and the chips. If there is room, it also shows its first devices and sends.
- The row under the cursor has a mark on the left edge of the strip (a switch is lit) and a color of its own across the strip, and the title bar shows its name and value at the right.
- The scale to the left of the first strip is the scale of the fader for every strip, from `+6` to `-48`, and the fader uses most of its travel for the top twenty decibels.
- The meters next to the fader are linear from -60 to 0 dB. The highest recent level shows in numbers under them.
- The top row of the meters is the clip light, which goes red when a level reaches full scale and stays red until you click it (or the peak) or until the transport starts again.
- If there is room, the row under the name of a strip gives the part that it plays into (`→ Master`, `→ Drum bus`). A click there, or `:part.output`, chooses it. Four rows name its first devices, and the last row counts the others (`+2 more`). With less room, one row counts the devices and the sends.
- The Master strip comes last, after a heavier rule, and the cursor goes to it with `$` or `l`. Its rows are its devices, the fader and the pan, and `a` adds a device to it, e.g., a limiter.
- VCAs have strips after the parts. The arrange view makes them (`<Space>tv` and the other keys of [the arrange view](arrange-view.md)). See [Export](export.md).

## Keys

| Keys | Effect |
| --- | --- |
| `h` `l` | Go to the previous and the next strip. `l` on the last part goes to the Master strip. |
| `0` `$`, `5\|` | Go to the first strip, the Master strip, the fifth strip. In a selection, `$` goes to the last part. |
| `/master` | Goes to the Master strip. `/` finds a strip by its name. |
| `j` `k` | Go along the rows of the strip. |
| `gg` `G` | Go to the top and the bottom row. |
| `w` `b` | Go to the next and the previous kind of row. |
| `+` `-` | Change the row: a dB on the fader or a send, a tenth of pan, a switch on or off, an insert on or bypassed. `6 Ctrl-x` is six dB down. The fader goes from -60 to +6 dB. A level above +6 dB (typed with `grv`, up to +24 dB) goes down one dB at a time. |
| `]` `[` | Pan the strip, from any row. |
| `Enter` | Types the value of the row. On a switch, switches it. On an insert, shows its window. |
| `x` | Clears the row: 0 dB, the center, off. A send or an insert goes away. |
| `gC` | Opens the curve of the fader or the pan in the [curve editor](curve-editor.md). |
| `K` | Describes the row. |
| `M` `s` `r` `Alt-i` | Mute, solo, arm, monitor the part. |
| `dj` | Clears the fader and the pan. |
| `yj`, then `p` | Copies the fader and the pan to a different strip. |
| `gcc` | Mutes a strip. `gc2l` mutes three strips. |
| `dd` `yy` `p` | Cut, copy and paste whole parts. |
| `V`, then `-` | Lowers every selected fader. `.` does it again. |
| `grv` `grp` | Type the volume and the pan of the strip. |
| `grC` | Chooses the color of the part. |

## The session view

<!-- tags: session-view -->

The clip launcher extension (`:ext.load launcher`) adds the session view:
a column of slots under each part, and a scene for each row. `<Space>vs` shows the view, `Enter` launches a slot, and `L` launches a row as a scene. The keys of the view are in [the README of the launcher](../../extensions/launcher/README.md).
