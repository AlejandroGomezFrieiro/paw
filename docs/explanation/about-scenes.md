# About scenes: one view, two frontends
<!-- tags: one-view-two-frontends -->

paw has two frontends, the terminal and the graphical window, and it keeps
one copy of each view for both. Many programs with two interfaces have two
copies of each view, and after some time the two copies do not agree. The
page explains how paw shares one copy, and why.

## The kernel holds everything

The window keeps no project state. The kernel holds the project, and it
also holds what each view shows and what each gesture means. The window
shows what the kernel sends, and it returns each key and each gesture to
the kernel.

A gesture therefore has one meaning in all frontends. For example, a drag
of a clip in the window calls `paw.frontend.act.drag_clips` in the kernel.
The kernel snaps the beats to the grid and makes the undo step, and the
suite tests the function in Lua. A new frontend gets the same behavior when
it sends the same calls. The window, a terminal and a script can also
control the same project at the same time, each from its own seat.

The cost is a turn of the kernel for each gesture, also over a network, and
for a fader or a note that cost is small. A frontend that decided by itself
would be faster, but it would also be a second program to keep correct.

## The kernel sends changes without being asked

The kernel sends a frontend what changed, when it changes, so the window
does not ask for the state many times a second. An idle project sends
nothing, and an idle window draws nothing. A change sends only the part
that changed.

While the song plays, the values that move come as small live messages,
and the window moves its widgets with them. The values that move are the
playhead, the clock, the meters and the parameters that lanes move. The
window does it without a pass of its layout, because it keeps the shapes of
the last pass and paints again only the parts that move.

A view can also move in other ways as the song plays. For example, notation
follows the playhead from system to system, and the session view fills the
slots that play. Such a view gives a key of what its drawing shows, without
the live values (`view:scene_key()`), and while the key does not change,
the kernel sends no new scene of the view. Notation gives the system of the
playhead, and it puts its playhead in the scene as a role that the live
values move. The session view gives the cells that the slots fill.

The full description is in
[The control protocol](../reference/protocol.md).

The terminal works in the same way. While the song plays, only the
playhead, the meters and the status line change. The kernel keeps the last
frame of each terminal, and what was under each of those parts. For a new
frame, it draws only those parts again on the last frame, with the current
values, and then it sends only the cells that changed.

When no cell changed, the kernel sends nothing, so the cost of a frame is
the cost of the parts that move and not the cost of the whole view. A key
or an edit draws the whole screen at once, as before. `paw.opt.fps` is the
highest number of frames a second, not a fixed rate.

## What a scene is

A view is written once, in Lua, as the terminal draws it, which means as
text in cells. The kernel records what the view draws as a scene, which is
a tree of named nodes in cell units. The kernel keeps the scene for each
window of each frontend, and after the first scene, it sends only the
nodes that changed.

The terminal turns the scene into its cells. The window draws the same
scene with its own fonts, at its own resolution, with crisp text and vector
pictures. A test (`tests/scene_parity.lua`) makes sure that, for each view,
the scene turned into cells is the same as what the terminal shows.

An extension's view therefore works in both frontends with no code for the
window. A view that paints in pixels, e.g., the notation or the vocal
editor, sends its drawing in the scene as a picture. The window draws the
picture, and a terminal that shows images draws the same pixels with the
same rasterizer.

## Roles give the window more than cells

Cells alone make a window that looks like a terminal, so a view can mark a
rectangle with a role, e.g., a fader, a meter, a switch or a note. The mark
has the data of the element, e.g., a fader's position or a note's pitch and
velocity, and the cells that show it in a terminal. A frontend that knows
the role paints it as a widget, e.g., a fader cap at any point along its
travel. A frontend that does not know the role draws its cells. The
terminal always draws the cells, so the terminal comes first and loses
nothing.

A mark can also be a hit region, which says what a press, a drag or the
wheel on it means. The view tells the meaning once, and the two frontends
find the region under the pointer in the same scene. The terminal sends
whole cells and the window sends fractions of a cell, so a fader in the
window moves smoothly, but the gesture is the same Lua function.

A plane places its marks in a domain of its own, e.g., beats along and
pitches up for the piano roll. A note is at its beat and pitch, and the
terminal rounds it to cells, while the window paints it where it is,
between cells.

## The kernel also owns the layout

The tabs and windows of the screen also belong to the kernel, with one
layout for each seat. The terminal draws them in cells. The graphical
window draws the same tree in pixels, with a pane for each window, and the
kernel sends a scene for each pane. A split made with `Ctrl-w v` therefore
shows in both frontends. A drag of a border, a click on a tab and the close
button of a pane go to `paw.panes`, which calls the layout code that
`Ctrl-w` calls.

An earlier window had its own fixed panels, where the arrange view was
always the main panel and the other views opened around it. Now no view is
the home of the screen, so a tab can show only the notation, or two piano
rolls. For the same reason, a view keeps a state for each window, because
two windows of one view are two scenes with two cursors.

The transport bar along the top of the window is not a scene. It is the
window's own drawing, with its buttons, the tempo and the load. Its clock
changes many times a second while the song plays, so a scene of the bar
would come again each time and the window would paint it whole. Instead,
the window reads the clock from the state that the kernel pushes
(`frontend.watch`) and paints only the bar. The terminal shows the same
values in its status line.

## What is not yet a scene

Most views come from scenes, e.g., the arrange view, the mixer, the piano
roll, the device panel and the drum grid. The arrange view's timeline is a
plane of beats along and the view's lines down. It uses lines and not
tracks, because a take lane and an automation lane have heights of their
own, and because a drag of a clip goes across all of them in one domain.
[Limits](../reference/limits.md) has the current list.

## Why the window looks as it does

The surfaces of the window are neutral, and a color always tells a state.
Blue is the selection, red is record, and the track's own color is only on
what belongs to the track. When each color has one meaning, you find the
state of a project fast. The colors are in [The graphical
window](../reference/window.md#colors-and-fonts).

The fonts are built into the program, so the window looks the same on all
machines. The window draws only when something changes, so it costs
nothing at rest, also on a machine without a graphics card.
