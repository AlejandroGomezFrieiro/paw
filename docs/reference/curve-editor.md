# The curve editor

<!-- tags: curve curves -->

The curve editor edits a curve in a window of its own. The curve can be an automation lane, a device parameter or the tempo map, and it can also be a controller of a MIDI clip (the pitch wheel, pressure, a CC) or the expression of one note.

## Open a curve

`gC` opens the curve of what the cursor is on:

| Where | Curve |
| --- | --- |
| A lane row in the arrange view (`Enter` too) | the lane |
| A parameter in the device panel (`Enter` too) | the parameter |
| The fader or the pan in the mixer | the volume or the pan |
| The piano roll | the controller that its strip shows. `gX` opens the curve of the note under the cursor. |

A curve is a buffer named by its address, so `:vs paw://lane/3`, `:e paw://tempo` and `:sp paw://clip/7/control/cc/74` show a curve, and `:setlocal timebind` scrolls it with the arrange view. A window that shows a lane that the project does not have any more (after a different project opens) closes, or becomes empty if it is the last window.

In the graphical window, the curve shows in a pane, and `:curve.window` (`Ctrl-w f`) shows it in a window of its own.

## What the view shows

The curve shows in sextants (`paw.opt.curve_glyphs`) over the bars and beats, with the values in their unit along the left side. A point shows as `◆`, as `■` where the part after it holds, and as `●` where it eases. The bottom row gives the point under the cursor, or the value of the curve at the cursor.

## Keys

The cursor is a beat and a value.

| Keys | Effect |
| --- | --- |
| `h` `l` | Move a grid step. |
| `j` `k` | Move a step of the value. |
| `Ctrl-d` `Ctrl-u` | Move ten steps of the value. |
| `w` `b` | Go to the next and the previous point, and take its value. |
| `0` `$` | Go to the first and the last point. |
| `o` | Adds a point at the cursor. |
| `A` | Adds a point on the curve at the cursor. |
| `x` | Removes the point under the cursor. |
| `+` `-` | Raise and lower the point. `Ctrl-a` `Ctrl-x` by the count. |
| `c` | Types the value of the point. |
| `~` | Gives the part after the point the next shape: straight, held, smooth. |
| `]` `[` | Bend a smooth part. |
| `i` | Draws: each move of the cursor (`h` `l` `j` `k` `J` `K`) puts a point where it stops. `Esc` writes the points over the curve, as one undo step. |
| `a` | Draws, from the value of the curve in place of the value of the cursor. |
| `d` `y` | Cut and copy points, with a motion or on a selection. |
| `p` | Puts the points at the cursor. |
| `>` `<` | Move points later and earlier. |
| `gs` | Smooths the points. |
| `gS` | Removes points that change nothing. |
| `gq` | Moves the points onto the grid. |
| `g~` | Draws a wave over the part: sine, triangle, saw, square, random or a ramp, from a menu. |
| `zi` `zo` | Zoom. |
| `[g` `]g` | Change the grid of the window. |
| `Ctrl-w f` | Shows the curve in a window of its own (graphical window). |

While a new wave shows, these keys work.

| Keys | Effect |
| --- | --- |
| `Tab` | Goes from the shape to the rate to the depth. |
| `Ctrl-n` `Ctrl-p` | Change the chosen setting, in the same undo step. |
| `Ctrl-y`, `Esc` | Keep the wave. |

`:curve.generate sine rate=1 depth=0.5` makes a wave by name.

In a selection, `x` deletes, `+` `-` raise and lower, `H` `L` move the points a grid step, and `~` sets their shape.

## Shapes of each kind of curve

Each kind of curve allows different shapes.

- A lane has every shape.
- The tempo map ramps or holds.
- A controller holds each value, and a ramp or a wave on a controller is written as a move every sixteenth of a beat.

## The mouse

- A click on a point chooses it, and a drag moves it (with Shift, off the grid).
- A press elsewhere adds a point, and a drag draws.
- The wheel scrolls, and with Ctrl it zooms.
- A right click on a point opens its menu, with its shape, its value and a way to remove it.
- A right click elsewhere opens the menu of the curve, with a wave, thin, smooth and quantize.
