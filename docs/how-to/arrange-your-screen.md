# How to arrange your screen: windows, tabs and layouts

You can choose which views are on the screen and where they are. For
example, you can write a score with only the notation on the screen, or
you can put two clips side by side in two piano rolls. The steps are the
same in the terminal and in the graphical window, and every key and
command is listed in [Windows, buffers and tabs](../reference/windows.md).

## Show a view in a window

Each window on the screen shows one view. To show a different view in the
window that has the keyboard, type `:e` and the name of the view:

- `:e mixer` shows the mixer, and `:e arrange` shows the arrange view.
- `:e roll://riff` shows the clip `riff` in the piano roll. A number
  also names a clip: `:e roll://7`.
- `:e notation://riff` shows the clip `riff` as notation (with the
  notation extension).

To return to the view that the window showed before, press `Ctrl-^`.

## Put two views side by side

1. To put a view on the right of the current window, type `:vs` and its
   name, for example `:vs roll://hook`. To put a view below the current
   window, type `:sp` and its name.
2. To go to the window on the left, press `Ctrl-w h`. `Ctrl-w j`,
   `Ctrl-w k` and `Ctrl-w l` go down, up and right.
3. To close the window that has the keyboard, press `Ctrl-w c`.

Every view can show in many windows, and each window has its own clip,
cursor and scroll. As a result, you can edit two clips at the same time,
or see the notation and the piano roll of one clip. `Ctrl-w v` and
`Ctrl-w s` show the same view again, on the same clip.

## See the devices of two parts

The device panel shows the devices of the part that the cursor is on. If
you want a panel to stay on one part, pin it:

1. To put a panel for the part `Bass` on the right, type
   `:vs devices://Bass`. Its title says `pinned`.
2. Move the cursor to a different part. The other panel follows the
   cursor, and the panel of `Bass` stays.
3. To pin the panel that has the keyboard to the part that it shows,
   press `\p`. Press `\p` again to make it follow the cursor.

The keys that you type in a pinned panel act on its part. For example,
`a` adds a device to `Bass`.

## Give one view the whole screen

- To close all the other windows, press `Ctrl-w o` (`:only`).
- To give the window the whole screen for a while, press `Ctrl-w |`.
  Press it again to put the other windows back.

The last window of a tab does not close, and it continues to show its
view, for example the notation. To show something else in it, type `:e`
and a name.

## Use tabs

1. To open a new tab, type `:tabnew` and the name of a view, for example
   `:tabnew mixer`.
2. To go to the next tab or the previous tab, press `gt` or `gT`.
3. To close the tab, type `:tabclose`.
4. To move the tab, type `:tabmove` and a number. For example,
   `:tabmove 0` makes it the first tab.

A tab without a view shows the start page, which shows the transport, the
projects that you opened last, and what to type. To open a project from
the list, move to it with `j` and `k`, and press `Enter`.

## Start paw with your own layout

If you want paw to start with only the notation, put the following line in
`init.lua`:

```lua
paw.ui.start_layout = "notation"
```

A start layout can also split the screen, or have tabs:

```lua
paw.ui.start_layout = { dir = "h", "notation", "roll" }
paw.ui.start_layout = { { name = "Write", layout = "notation" }, { name = "Mix", layout = "mixer" } }
```

## Keep the layout with the project

When you save a project with `:w`, paw keeps the tabs and windows in the
project file, so the screen is as you left it when you open the project
again.

You can use paw in a terminal and in the graphical window at the same
time. Each of them is a seat, which is a place where you work, and each
seat has its own tabs and windows. The project keeps one layout for the
graphical window and one for the terminal, so you can keep the mixer in
the window and only the notation in the terminal. When you open the
project, each seat gets its own layout, and a seat without a layout in
the project gets the layout of the last save.

If you want the screen to stay as it is when you open a project, type
`:set noproject_screen`.

To keep a layout for many projects, type `:layout save write`. To use
it again, type `:layout write`.

## Switch between screens for each task

A workspace is a screen for one task, and you go from one workspace to
another with `<Space>w` and a letter. paw has four workspaces:

- `<Space>wr` goes to the record workspace, with the arrange view and the mixer. The cursor goes to the first armed part, so `R` records there.
- `<Space>we` goes to the edit workspace, with the arrange view and the piano roll.
- `<Space>wm` goes to the mix workspace, with the mixer and the device panel.
- `<Space>wn` goes to the score workspace, with the notation view. It needs the notation extension.

The status line shows the name of the workspace that you are in. When
you leave a workspace, paw keeps its tabs and windows, so when you come
back to it, the screen is as you left it. For example, you can open a
second tab in the edit workspace, press `<Space>wm` to mix, and press
`<Space>we` to find both tabs again.

To keep the screen that you have now as a workspace of your own, press
`<Space>ws` and type its name. `<Space>ww` lists every workspace, and you
choose one with `Enter`. To keep a workspace in the project instead,
type `:workspace.save! tracking`. The project then has a change to save,
and after you save it, the project opens in that workspace.

## In the graphical window

The graphical window shows the same tabs and windows as the terminal, and
you can also use the mouse:

- To change the size of two windows, drag the border between them. To
  close a window, click the close button in its title.
- To go to a tab, click it, and to move a tab, drag it along the row of
  tabs. To open a new tab, click `+` after the last tab.
- To close a tab, click the close button on the tab, or click the tab
  with the middle button.
