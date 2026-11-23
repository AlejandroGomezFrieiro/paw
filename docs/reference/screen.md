# The terminal screen

<!-- tags: screen how-it-looks -->

The screen page describes the parts of paw's screen in a terminal. Each view
has a page for its keys, and the views are [the arrange view](arrange-view.md),
[the piano roll](piano-roll.md), [the device panel](device-panel.md),
[the mixer](mixer-view.md) and [the curve editor](curve-editor.md).

## Parts of the screen

From the top:

- The tab line, which shows when there is more than one tab and gives the name of each tab.
- The windows of the tab. Each window shows a buffer: a view, a list, help. See [Windows, buffers and tabs](windows.md).
- The status line. See [The status line](status-line.md).
- The bottom line, which shows the most important keys of the view and the mode, and messages. In insert mode, a message goes to the right end of the line.

A docked panel (the device panel, the mixer, the piano roll, the view of an
extension) has a title bar of one row. The title bar of the focused panel
shows in amber, inverted, and a panel next to a different panel has a rule on
its left side.

A screen narrower than 80 columns shows the device panel as a float over
the arrange view. A screen smaller than 60 × 16 shows only a message that
the screen is too small.

A project with no tracks shows a message about how to start.

## The bottom line

The bottom line shows the keys to know first for the view and the mode, and
a message replaces it for a time (`paw.opt.message_time`). The line ends
with the help topic of the view, such as `:help mixer` in the mixer, and `?` lists
every key. `paw.opt.keybar = false` removes the keys from the line.

An extension sets the keys of its view with
`paw.ui.keybar.set("myview", "n", { { "<CR>", "open" } })`.
`paw.ui.keybar.check()` lists each key shown that has no mapping.

## Colors

Each track has a color, and a new track gets the next of the twelve colors of
the theme. The graphical window uses the same colors. `:track.color`
sets the color of the track at the cursor to one of `coral`, `orange`, `gold`,
`lime`, `green`, `teal`, `sky`, `blue`, `violet`, `purple`, `pink`, `sand`,
or `#rrggbb`. `grC` chooses the color from a list, in the arrange view and
the mixer.

paw draws what belongs to a track in shades of its color, including
its clips, its notes in the piano roll, and its name plate in the mixer.

| Color | Use |
| --- | --- |
| amber | focus, the playhead, keys to press |
| the color of the mode | the mode pill and the cursor |
| red | recording and errors |
| the color of the track | the clips, notes and name plate of the track |

`paw.ui.hl(group, { fg = ..., bg = ... })` changes a highlight group. The
groups are in `runtime/lua/paw/theme.tl`.

paw uses 24-bit color or the nearest of 256 colors (`paw.opt.termcolors`).
`paw.opt.ascii` draws with ASCII characters only. `paw.opt.curve_glyphs`
sets the characters of curves. See [Options](options.md#screen).

## Pictures

In a terminal that shows images, the views that paint show pixels. See
[Pictures in the terminal](pictures.md).

## Parts to draw views

The views and the extensions draw with the same parts, in `paw.draw`.
The parts include the colors of a track (`track_hue`), meters, sliders, the pan,
the chips, the small pictures in clips, the ruler and grid of a roll, and
curves.
`paw.ui.titlebar(buf, opts)` draws the title bar of a panel. An extension
draws on the timeline of the arrange view through
`paw.ui.views:get("arrange").layers`, and adds a second ruler row through
`paw.ui.views:get("arrange").ruler2`. See [the Lua API](api.md).
