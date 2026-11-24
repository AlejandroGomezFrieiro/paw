# About scopes

<!-- tags: about-scopes -->

paw has one idea behind narrowing, folds and subprojects, which is the
scope. The page explains what a scope is, why a scope only changes what a
window shows, and what a subproject adds to it. For the keys and the
commands, see [Scopes](../reference/narrowing.md) and
[Subprojects](../reference/subprojects.md).

## A scope is a view of the one project

A project is a set of parts over time, and a scope is a piece of it: some
parts, some time, or both. The song is the scope with every part and
all the time. A group is a scope with its parts and all the time, and a
region is a scope with every part and its time. A part, a selection of
parts, and a block of parts over some bars are scopes too.

Scopes go inside each other. When you enter the strings inside the
bridge, you see what both have in common, the strings in the time of the
bridge, and the status line shows the path, `Bridge › Strings`.
`zw` goes up one level of the path, and `zW` goes up to the song.

A scope belongs to a window and not to the project, in the same way that
each window of Vim keeps its own folds. One split can show the whole song
while the split beside it shows the bridge, and both show the same
project.

## Entered, folded or open

A window can show a scope in one of three ways, and in each way it's the
same scope:

- Entered: the window shows only the scope. The bars count from 1 at its
  start, and the loop is its time.
- Folded: the window shows the scope in place, closed. A group folds
  into one row, and a region folds into one narrow column with its name
  and its bars, for example `Bridge ▸ 8`. A block of some parts in some
  bars folds into one frame over them, with its name and its bars.
- Open: the window shows the scope in place, as usual.

Because a fold and a scope are the same thing, you can go from one form
to another. `znn` on a closed fold enters it, and `zw` brings you back to
the fold, still closed. The list of `<Space>zz` shows the folds of the
window next to the groups and the regions, and `K` describes a closed
fold as it describes an entered scope, by its path, its bars and its
parts. Groups and regions are scopes without
any work from you, so you can enter or fold them at once, and `zf`
makes a fold of any other parts or bars.

## Why a fold is not an undo step

A fold, like entering a scope, changes what one window shows and nothing
in the song. Undo is for changes to the song, so `u` undoes your last
edit and never opens a group that you folded a moment ago. If folds were
undo steps, the list of undo steps would fill with folds, and undoing a
wrong note would also open and close parts of the screen.

The folds and the scopes of each window are still kept. paw saves them
with the windows of the project, so they come back when you open it. To
go back to a scope that you left, use the jump list, `<C-o>` and `<C-i>`,
which is the list of places that you visited and not the list of edits.

## Why a scope never copies

A scope shows the parts and the clips of the song itself, and never a
copy of them. An edit in a scope is an edit of the project, so every other
window shows it at once, and one undo tree holds the edits of every
window. Nothing has to be copied back into the song, and no copy can get
out of date.

The same holds for time. The song has one tempo map, so a tempo change
of the song is heard inside a scope, and a region in 6/8 is in 6/8
because the meter of the song changes there. The scope only counts its
bars from 1. You can change your mind about how to look at the song as
often as you want, because no way of looking at it changes the data.

## What a subproject adds

Sometimes a section needs something that a view of the song can't give.
A section can need parts of its own, for example a slow passage with a
piano in a loud song, or a meter that runs beside the meter of the song,
or one section that plays in two places. A subproject gives these
things. It has its own parts and its own timeline, and the song plays it
from a row of its own, the return row.

A subproject is still a scope. You enter it with `znn`, leave it with
`zw` and find it in `<Space>zz`, as you do with a region or a group, and
the status line marks it with `⧉`. Its edits are in the one undo tree of
the project. A view can become a subproject with `<Space>zw`, and a
subproject can become a view again with `<Space>zp`. Both leave the
window where it was, so the way that the project stores the section
changes, and what you see stays the same.

To put a section in another meter step by step, see
[How to work on a section in another meter](../how-to/work-on-a-section-in-another-meter.md).
