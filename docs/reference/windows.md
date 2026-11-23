# Windows, buffers and tabs

<!-- tags: windows-buffers-and-tabs windows buffers tabs -->

The screen has the same layout as Neovim, built from buffers, windows and tabs.

- A buffer is a thing to show and edit. The views are buffers, namely the arrange view (`arrange`), the piano roll (`roll`), the mixer (`mixer`) and the device panel (`devices`). The event list, help and the view of an extension (`notation`, `drums`, `utau`, the session view `session` of the clip launcher and more) are buffers too.
- A window shows one buffer.
- A tab holds windows, split side by side and one above the other.

The status line and the bottom line stay along the bottom of every tab.

## The start

At the start there is one tab, and the configuration can give a start layout
(see [Layouts](#layouts)). Without a start layout, the tab shows the arrange view.
The panels open and close in their places (`<Space>mm`, `<Space>dd`, `<Space>vp`, `Enter` on
a clip).

No view is the home of the screen, so any view can be alone in a
tab, and paw never puts the arrange view in a window that you did not ask
for.

- `<Space>vp` with no clip open opens the piano roll on the clip under the cursor. If there is no clip there, it shows a message and changes nothing.
- A view that is not in the tab docks on its side of the window that has the keyboard, as a split in Neovim does. For example, `<Space>mm` puts the mixer below that window.
- The last window of a tab does not close. `Ctrl-w c`, `:close`, `<Space>mm` and the other keys that close a panel leave it. It continues to show its view.
- When a window closes, the keyboard goes to the window that had it before.
- `:view.focus` of a view that does not show puts it in the current window, so the focus is never on a view that is not visible.
- `:help` splits half of the screen, as Vim does for its help.

## The start page

An empty window shows the start page, which you get with `:vnew`, `:tabnew` without a name,
or `Ctrl-w n`. The start page is a buffer type, `empty`, with a buffer for each window.

- The first line shows the project, the tempo, and where the transport is.
- The list of recent projects follows. `j` and `k` move in it, and `Enter` or a double click opens the project.
- The last lines tell what to type to show a view in the window.

## Sizes

- A view says what part of the room it keeps where windows share it (`share` in [Lua views](lua-views.md)). Sometimes three or more panels are one above the other, and then the arrange view keeps a third of the rows (as `Ctrl-w =` gives it), and the notation view takes half or less.
- In a column, the arrange view keeps two fifths of the rows. The panels with a size of their own give rows last.
- In a panel whose height is an option (`mixer_height`), `Ctrl-w +` and `Ctrl-w -` change that option. Elsewhere they change the height of the window only. The height of tracks and keys is the vertical zoom (`Ctrl-=`, see [The arrange view](arrange-view.md#vertical-zoom)).

## Splits

`:vs roll` splits the window in two, side by side, and shows the piano roll
in the new half. `Ctrl-w h` and `Ctrl-w l` go between the two. Each window
takes its own keys, and a clip that you open shows in that window.

- The arrange view, the piano roll, the notation view, the mixer, the device panel and the session view of the clip launcher show in any number of windows. Each window has its own state: the open clip, the cursor, the scroll and the zoom of the view. The edit cursor of the arrange view (the track and the time) is one for all the windows.
- Each device panel follows the cursor track, or shows the track that it is pinned to (`devices://Bass`, `\p`). See [Two panels on two tracks](device-panel.md#two-panels-on-two-tracks).
- The views of extensions without a state for each window show in one window at a time, so if you show one of them in a different window, it moves there with a message.
- A panel window closed with `Ctrl-w c` keeps its place, and the panel returns there. A second window of a view closes for good.
- New windows go to the right of and below the window that you split. `:set splitright!` and `:set splitbelow!` put them to the left and above.

## Names of a clip in a view

A view that opens a thing of its own takes a name of the form
`view://thing`, in the way that Neovim takes `term://`. The name goes after `:e`, `:sp`,
`:vs`, `:b` and `:tabnew`, and into a layout.

| Name | Effect |
| --- | --- |
| `roll://riff` | The piano roll on the clip named riff (the first in the order of the tracks). |
| `roll://7`, `roll://paw://clip/7` | The piano roll on clip 7. |
| `notation://riff` | The notation view on the clip riff (the notation extension). |
| `devices://Bass`, `devices://3` | The device panel, pinned to the track Bass, or to track 3. |

A name that is not a clip or a track shows a message, and the window shows the view as it was.

## Keys and commands

| Keys or command | Effect |
| --- | --- |
| `:sp roll`, `:vs roll` | Split the window, one above the other or side by side, and show a buffer. Without a name, show the same buffer, as in Vim. A list edited as text and a view with a state for each window show in both windows, the new one from the state of this one. A view shown in one window at a time gives the start page. |
| `Ctrl-w s`, `Ctrl-w v` | The same as `:sp` and `:vs` without a name. |
| `:vnew`, `Ctrl-w n` | Open an empty window, with the start page. |
| `:e roll`, `:b roll`, `:b 3` | Show a buffer in this window, by name or number. The name of a buffer or a view, or an address such as `paw://tracks`, comes before a file. Only a file asks about unsaved work: `:e song`, `:e song.mid`, `:e take.wav`. A folder shows as a [file buffer](file-manager.md). |
| `:e roll://riff`, `:vs notation://7` | Show a view on a clip (see [Names of a clip in a view](#names-of-a-clip-in-a-view)). |
| `:bn`, `:bp` | Show the next or the previous buffer. |
| `:ls` | Lists the buffers. |
| `:bd roll` | Closes every window of a buffer. |
| `Ctrl-^`, `:b #` | Shows again what this window showed before (for example, from `paw://tracks` back to the arrange view). |
| `:close`, `Ctrl-w c` | Closes the window. |
| `:q`, `Ctrl-w q` | Closes the window. In the last window, quits (and asks about unsaved changes). |
| `:only`, `Ctrl-w o` | Closes every other window. |
| `Ctrl-w h` `Ctrl-w j` `Ctrl-w k` `Ctrl-w l` | Go to the window to the left, below, above, to the right. A count goes further. |
| `Ctrl-w w` `Ctrl-w W`, `Tab` | Go to the next and the previous window. |
| `Ctrl-w p` | Goes to the window that had the keyboard before. |
| `Ctrl-w H` `Ctrl-w J` `Ctrl-w K` `Ctrl-w L` | Move the window to the far left, bottom, top, right. |
| `Ctrl-w x` | Exchanges the window with the next. |
| `Ctrl-w r` `Ctrl-w R` | Rotate the windows of the row or column. |
| `Ctrl-w +` `Ctrl-w -` `Ctrl-w <` `Ctrl-w >` | Resize the window. A count goes further. In the device panel, `<` `>` change `devices_width`. |
| `Ctrl-w =` | Gives the windows equal sizes. |
| `Ctrl-w _` `Ctrl-w \|` | Gives the window the whole tab. Again: puts the other windows back. |
| `:resize 20`, `:resize +5`, `:vertical resize 40` | Set the height or the width of the window. |
| `:tabnew Mix`, `:tabnew mixer`, `:tabnew roll://riff` | Makes a new tab named Mix, or a tab that shows the mixer or the clip riff in the piano roll. Without a name, the tab shows the start page. |
| `gt` `gT`, `:tabn 2` | Go to the next and the previous tab. Go to tab 2. |
| `Ctrl-w T` | Moves the window to a tab of its own. |
| `:tabclose`, `:tabclose 2` | Closes the tab, or tab 2. |
| `:tabmove`, `:tabmove 0`, `:tabmove 2`, `:tabmove +1` | Moves the tab to the end, to the start, after tab 2, or one place on. |
| `:tabs` | Lists the tabs and their windows. |
| `:narrow Strings`, `znn` | Shows only the tracks of one group in this window (`znn`: the scope at the cursor). |
| `:widen`, `zw` | Goes up one level of scope in this window. |
| `<Space>zs` `<Space>zv` `<Space>zt` | Show the scope at the cursor in a new split, vertical split or tab. |
| `:view.open undotree` | Shows a view where it docks, else in a window split from this window (the More menu of the graphical window). |
| `:layout save edit`, `:layout edit` | Write the tabs and windows as layout `edit`. Put them back. |
| `:workspace mix`, `<Space>wm` | Goes to the workspace `mix` (see [Workspaces](#workspaces)). Without a name, chooses one in a picker. |
| `:workspace.save tracking`, `<Space>ws` | Keeps the tabs and windows as workspace `tracking`. Without a name, asks for one. |
| `:workspace.save! tracking` | Keeps the tabs and windows as workspace `tracking` in the project, which then opens in it. |

With more than one tab, a tab line along the top gives their names. A click
on a tab goes to it. In the graphical window, each tab has a close
button, and a middle click on a tab closes it. A drag of a tab moves it
(`:tabmove`). `+` after the last tab opens a new tab (`:tabnew`).

A click in a window gives it the keyboard (see
[The mouse](mouse.md)). The rule between two windows side by side is a
border to drag with the mouse, and so is the top row of a window below a
different window, where a press that the window does not use drags the
border.

## Bound in time

`:setlocal timebind` in the arrange view and in the piano roll next to it
makes them show the same time at the same zoom. The window with the
keyboard leads and the other window scrolls with it, and while the song plays,
both follow the playhead. `:setlocal notimebind` removes the bind.

## Layouts

`:layout save edit` writes the tabs and windows to the state directory,
and `:layout edit` puts them back. A layout saved with `:layout save`
comes before a layout of the same name in the configuration. A
configuration can name its own layouts, and start with one, as follows.

```lua
paw.layouts.edit = {
  { name = "Edit", layout = { dir = "h", "arrange", "roll" } },
  { name = "Mix", layout = "mixer" },
}
paw.opt.layout = "edit"
```

`paw.ui.start_layout` is the layout that paw starts with, given as a view's
name, a tree of windows, or a list of tabs. A window can name its clip, as follows.

```lua
paw.ui.start_layout = "notation"
paw.ui.start_layout = { dir = "h", "notation://riff", "roll://riff" }
```

A project keeps its tabs and windows. When you save it, paw writes the
tabs and windows of your frontend into the project's `screen.json`, with the clip
of each window, and when you open the project, paw puts them back. Putting them back is
not an edit and not an undo step. `:set noproject_screen`
(`paw.opt.project_screen = false`) keeps the screen as it is when a
project opens.

| Field | Effect |
| --- | --- |
| `dir = "h"` | Puts the windows side by side. |
| `dir = "v"` | Puts the windows one above the other. |
| `size` | The size of a window, in cells. |
| `weight` | The share of a window, 1 by default. |

Each terminal attached with `paw attach`, and each graphical window, is a
seat: it has its own tabs and windows. The project keeps the tabs and
windows of each kind of seat (the graphical window and the terminal), and
also a default, which is the layout of the seat that saved it last. When a project opens,
each seat gets its own layout, and a seat that has none in the project gets the
default. A window that attaches to paw after the project opened gets the
layout of the windows, if the project has one.

## Workspaces

A workspace is a layout for one task. `<Space>w` and a letter go to a
workspace, and the status line shows its name. paw keeps the tabs and
windows of the workspace that you leave, until a project opens, so the
screen of a workspace is as you left it when you come back.

| Key | Workspace | Windows |
| --- | --- | --- |
| `<Space>wr` | record | The arrange view and the mixer. The cursor goes to the first armed track, and when no track is armed, the cursor stays and the message says so. |
| `<Space>we` | edit | The arrange view and the piano roll. |
| `<Space>wm` | mix | The mixer and the device panel. |
| `<Space>wn` | score | The notation view, from the notation extension. |
| `<Space>ww` | any | Chooses a workspace in a picker. |
| `<Space>ws` | new | Keeps the screen as a workspace, and asks for its name. |

The four workspaces are layouts in `paw.layouts`, so `init.lua` can
change them or add more:

```lua
paw.layouts.mix = { dir = "h", "mixer", "devices" }
paw.layouts.drums = { dir = "v", "arrange", "roll" }
```

`paw.workspace.on_enter` holds, by the name of a workspace, a function that
runs each time you go to that workspace. The text that it returns goes
into the message. The record workspace uses it to move the cursor.

When you go to a workspace, paw looks for it in this order:

1. The tabs and windows that you left in it.
2. The workspaces of the project.
3. A layout saved with `:workspace.save` or `:layout save`.
4. A layout of `paw.layouts`.

`:workspace.save! tracking` keeps the workspace in the project's
`screen.json`, under `workspaces`, and names it as the workspace that the
project opens in (`workspace`). It is a change to the project but not an
undo step, and the project file gets it when you save the project. When the project opens, paw puts back its tabs and windows,
and then goes to that workspace. With `:set noproject_screen`, the
project opens with the screen as it is.

The status line component `workspace` shows the name. It is on by
default, in the right part of the status line (see
[The status line](status-line.md)).

## Scopes of windows

`:narrow Strings` (or `znag`) narrows the window to a group. Each arrange
window keeps its own scope, as each window of Vim keeps its folds, and a
split starts with the scope of the window that it comes from. The other
windows of the tab show the scope of its arrange window that had the
keyboard last. Everything in them sees only the tracks of that group,
including the mixer, the device panel, the session view of the clip
launcher, `paw://tracks`, the pickers, `:query`, the motions and the Ex
ranges. `:widen` (`zw`) goes up one level.

The status line shows `Strings`, the tab has the name of the scope,
and a split can show the whole song beside the strings.
`paw://tracks` in a narrowed window lists the tracks of the group, and `:w`
does not change the other tracks. The project keeps the scope of each
window with its windows. `paw.opt.scope_rest` sets what the other
tracks do: play, mute, or play from frozen files. See
[Render](render.md).
