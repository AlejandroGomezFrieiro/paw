# The mouse

<!-- tags: the-mouse pointer -->

The mouse does in the terminal what it does in the graphical window (see [The graphical frontend](window.md)), in cells. Each gesture goes to the same function in the kernel as the gesture of the window (`paw.frontend.act`), so the two frontends give a gesture the same meaning, and the keys do not change.

## General rules

- A press gives the keyboard to the view under the pointer.
- A gesture that changes the project changes it when you release the button, as one undo step, and until then the view shows where the change will go (in the timeline and the piano roll).
- A gesture that moves a control (a fader, a pan, a parameter, the loop) moves it with the pointer.
- A cell is the grid step that it shows, so a click puts things on the step of the cell and a drag to a cell includes that cell.
- Shift moves off the grid, where the terminal sends it (see below).
- Two presses on one cell in 400 ms are a double click.
- When the pointer is over a thing, the status line says what it is and what a click there does.

## What the pointer does

| Where | What the pointer does |
| --- | --- |
| Timeline | A click puts the cursor there and releases the chosen clips. A drag across empty lanes selects that time on the parts that it crosses. A drag with the right button draws a box that chooses the clips that it touches (Shift adds, Ctrl reverses). A double click makes a clip of a bar. A right click opens the menu of the timeline (new clip, paste, marker, region, punch, count-in, the tempo lane, new part), or on a selected time the menu of the selection (delete, copy, loop, mute). The middle button held pans. |
| Clip | A click chooses it. Ctrl and a click adds or removes it. Shift and a click adds the clips between it and the last chosen clip. A drag moves it and the chosen clips, also across parts (Ctrl drops copies, Shift moves off the grid). Its first and last cells are its edges, and a drag on one trims it (Alt slips the content, Alt and Shift on the end stretches the sound). A warp marker (the line down an audio clip) drags along it, and a right click on it removes it. A double click opens the notes. A right click opens the menu of the clip (edit, rename, split at the pointer or the cursor, glue, repeat, mute, takes, stretch and loop, warp markers, delete). |
| Part header | A click selects the part. A double click renames it. A drag up or down moves it. `M` `S` `R` `I` switch. A press on `M`, `S` or `R` dragged down sets the same value on the parts that it crosses. The volume on the second line drags sideways, a decibel for each cell. The pan on the third line drags five percent for each cell (Shift: finer). A double click resets either. The `▾` or `▸` of a group in the part column folds it or opens it. A right click opens the menu of the part (rename, color, duplicate, groups, automation mode, lanes, MIDI learn, bounce, delete). |
| Ruler | A click puts the cursor and the playhead there. A drag loops the cells that it crosses. A double click turns the loop on or off. The edges of the loop and of the punch range (`▕`) drag. A tempo or time signature flag (`▾96`, `‖6/8`) drags to move it. A double click types its value. A right click offers to change or remove it. |
| Markers | In their rows under the ruler, a row for each level of regions: a click goes to a marker or region. A drag moves it, and a region takes the regions and markers inside it. A double click renames it. A right click offers to rename it, loop the region or remove it. |
| Tempo lane (`zT`) | A click adds a change at that height. Hold and drag to draw the tempo. A drag on a change moves it (an eighth of the range of the lane for each row, Shift finer). A double click makes it ramp to the next change, or hold. A right click removes it. Elsewhere, a right click hides the lane. |
| Lanes as rows | A click adds a point. Hold and drag to draw. A drag on a point moves it. A right click removes it. Elsewhere, a right click offers to edit the curve, clear the lane, bypass it or hide the rows. |
| Curve editor | A click on a point chooses it, and a drag moves it (Shift: off the grid). A press elsewhere adds a point, and a drag draws. The wheel scrolls, and with Ctrl zooms. A right click on a point opens its shape, value and remove. Elsewhere, a wave, thin, smooth and quantize. |
| Take lanes | A drag across lane k makes take k play there (see [Take lanes](arrange-view.md#take-lanes)). A click on a piece gives it take k. A click on the label gives take k to the whole part. A right click hides the lanes. |
| Piano roll | Press on the empty grid where a note starts, and drag to where it ends. A click gives the note length of the roll, and a drawn length becomes that length. A click on a note chooses it. Shift or Ctrl adds or removes it. A drag on a note moves it and the chosen notes (Ctrl copies, Shift moves off the grid). A drag on its first or last cell moves its start or its end. The right button dragged, or the left button with Ctrl, chooses the notes in its box. A right click removes a note (Ctrl and a right click offers the fixes of the diagnostics). On the empty grid, a right click opens a menu (choose all, release, delete, quantize, snap). A double click removes a note. Alt and a drag erases every note that it crosses. |
| Piano roll, several clips | A note is chosen and moved in its own clip. A new note goes into the clip where you draw it. Ctrl and a click on the note of a different part behind edits its clip too, or stops the edit. |
| Piano roll, keyboard and strip | The keyboard plays a key under a click or a drag. A right drag down the keyboard chooses the notes of those pitches. The strip under the notes takes the velocity drawn across it (only the chosen notes, if there are any). A click on its name (`vel`) shows a controller there: the pitch wheel, modulation, expression, the pedal. Draw it with the button held. A click on the head of a move (the top of its bar) chooses it (Ctrl or Shift adds it), and a drag moves the chosen moves. Ctrl and a drag chooses those in a box. The right button dragged draws a straight line, and a right click opens its menu. A click on the ruler moves the playhead. |
| Session view (clip launcher) | A click on a slot chooses it. Its play mark (`■`, `▶`) launches the clip, and the release releases a gate or one-shot clip. A double click opens the notes of a slot, or makes a MIDI clip of a bar in an empty slot. The dot of an empty slot records a bar into it. A drag moves a clip to a different slot (Ctrl copies). A right click opens the menu of the clip. The name of a scene launches its row. The bottom line stops a part, or every part under the scenes. The wheel scrolls the rows, and with Shift the parts. |
| Mixer | A drag on a fader moves it up or down (Shift: finer). The level under it drags sideways. The pan goes to the pointer. A double click resets them. `M` `S` `R` `I` switch. A click on a device selects it in the device panel. A click on the row under the name (`→ Master`) chooses where the part plays into. A click on the peak or the clip light (the top row of the meters) resets the light. The level of a send drags sideways. The wheel moves the fader a step, and with Shift goes to the next or the previous part. A right click opens the menu of the part. |
| Devices | A click or a drag on the slider of a parameter moves it to the pointer (Shift: finer). A double click resets it. `on` / `off` bypasses the device. The wheel scrolls, and with Ctrl moves the parameter under the pointer a step. |
| Menus, pickers, the list of the command line | A click on an entry chooses it. In a picker and the list of the command line, the first click selects and a second click chooses. The wheel scrolls. A click outside a menu closes it. Pages such as `:messages` scroll with the wheel. |
| Wheel | In the arrange view, scrolls the parts. With Shift (or sideways), scrolls in time. With Ctrl over the timeline, zooms in time at the pointer. With Ctrl or Alt over the headers, makes the parts taller or shorter. In the piano roll, scrolls the pitches. With Shift, in time. With Ctrl, zooms. |

## Menus

A menu opens at the pointer and takes the keys while it is open.

| Key | Effect |
| --- | --- |
| `j` `k` | Move. |
| `l`, `Enter` | Open a submenu, or choose. |
| `h` | Return from a submenu to its parent menu. |
| `Esc` | Close the menu. |

The menu also has the entries of extensions (`paw.frontend.menus`), as the menus of the graphical window have, and a script opens a menu with `paw.ui.menu(items, { x = x, y = y })` (see `runtime/lua/paw/menu.tl`).

## The terminal and multiplexers

paw asks the terminal to report every press, release and move of the pointer, with or without a button (modes 1000, 1002 and 1003). The reports use the SGR form (1006), which has no limit on columns, and paw restores the terminal when it ends, when it fails, and when it gets `SIGTERM` or `SIGHUP`.

- Under tmux, the pointer goes to paw with `set -g mouse on`. Without it, tmux keeps the pointer for the terminal.
- A different multiplexer sends the pointer to paw when it sends the request of paw to the terminal.
- Most terminals (WezTerm, kitty, foot, xterm, Alacritty) keep Shift and a press for their own selection of text, so Shift does not go to paw there. To move off the grid in those terminals, use `:set grid=…` or `:set note_snap!`.
- `:set mouse!` (`paw.opt.mouse = false`) stops the reports, and the terminal keeps the pointer, and the same command again starts the reports.
