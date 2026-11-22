# undotree

The undotree extension brings the undo tree of Neovim to paw. When you undo and then make a change, you do not lose an edit, because the change starts a new branch and the old branch stays.
You can return to any earlier state by walking the tree, by stepping through time
across branches, or by giving a time (`:earlier 2m`). You can also name states,
write named states beside the project as checkpoints and restore them
after the project opens again, and you can compare two states by ear while the
song plays.

```lua
paw.ext.load("extensions/undotree")   -- or put the directory in ~/.config/paw/extensions
```

![The melody moved with 3>ic, undone and moved with 2>ic instead. Then ,uu shows both branches, and Enter returns to the first](images/tui-undotree.gif)

## Try it

1. Type `:ext.load undotree`, and open a song.
2. Put the cursor on a clip. Type `3>ic`, and the clip moves three steps later.
3. Press `u`, then type `2>ic`, and the clip moves two steps later. The first
   edit is now on another branch.
4. Press `<Space>pu`, and the window of the tree shows two branches.
5. Press `j` to select the state of the first edit, and press Enter, and the
   clip is three steps later again.

## How to

### How to return to an earlier state

- To return two minutes, type `:earlier 2m`. To go forward, type
  `:later 2m`.
- To step through states in the order that they were made, press `g-` or
  `g+`.
- To choose a state, press `<Space>pu`, select the state and press Enter.

### How to compare two versions by ear

1. Press `<Space>pa`, which marks this state as A.
2. Continue to work, or go to another state of the tree.
3. Start playback, and press `<Space>pb`, and you hear A.
4. Press `<Space>pb` again, and you hear where you were, which is B.
5. To forget A and B, press `<Space>pB`.

### How to keep a version after paw closes

1. Save the project.
2. Type `:checkpoint before the bridge`, or press `<Space>pc` and type the name.
3. Later, to restore it, type `:checkpoints` and choose it.

The restore is a new step, so `u` returns to where you were.

After a save, the undo file also keeps every state, so the tree is there
when you open the project again. A checkpoint stays when the undo file
does not, for example after a change of the project's files with `git`. See
[Files that paw keeps](../../docs/reference/state-files.md#the-undo-file).

### How to see what a step changed

- For the last step, type `:undo.diff`, or press `<Space>p.`.
- From state 3 to now, type `:undo.diff 3`.

### In the graphical window

- Choose More, then Undo tree, or type `:view.window undotree_paint`.
- Click a state to go there. Point at a state to see the step, its time
  and the state that it came from.

## Reference

The tree is in the kernel, so `u` and `Ctrl-r` walk it when the extension
is not loaded, and the extension is the interface to the rest of the tree.

### Keys

The keys after the leader are in the domain `<leader>p` (project), and
the window is also in `<leader>v` (views).

| Keys | Effect |
| --- | --- |
| `g-` `g+` | goes to the state made before or after this state, on any branch (with a count, as in `5g-`) |
| `<leader>pu` `<leader>vu` | the window of the undo tree |
| `<leader>pa` | marks this state as A |
| `<leader>pb` | switches between A and where you were (B) |
| `<leader>pB` | forgets A and B |
| `<leader>pc` | writes a checkpoint, and asks for a name |
| `<leader>pC` | lists checkpoints, to restore one |
| `<leader>pn` | names this state, for this session |
| `<leader>p.` | shows what the last step changed |

- `u` and `Ctrl-r` are the built-in undo and redo. Undo goes to the parent
  state, and redo goes to the child that you visited last.
- To switch between A and B with one more key, set the option
  `undotree_ab_key` before the extension loads, for example
  `paw.opt.undotree_ab_key = "<F5>"`. The default is `""`, which means no key.

### The window

| Keys | Effect |
| --- | --- |
| `j` `k` | move, and `Ctrl-d` `Ctrl-u` move by ten, and `g` `G` go to the ends |
| `Enter` | goes to the selected state, and the window stays open |
| `u` `Ctrl-r` | undo and redo |
| `-` `+` | step through time, as `g-` `g+` |
| `a` | marks the selected state as A |
| `b` | switches between A and B |
| `n` | names the selected state |
| `c` | writes a checkpoint of the current state |
| `d` | switches the right side between what the step of the selected state changed, and what is different from it to the current state |
| `<Space><Space>` | plays and stops |
| `q`, `Esc` | closes |

A click on a row selects it, and the wheel moves the selection.

The tree in the terminal shows the newest state at the top:

- `@` is the current state, `*` any other state.
- `│` takes a branch down to the state where it started, and `─┘` joins it
  there.
- Each row shows the number of the state, its time and its name in
  quotes, and it shows `[A]` `[B]`, and `(saved)` for the state saved last.
- Each row then shows what made the state, which is the description of the key or the
  command followed by the keys typed (`Delete the clip  x`, `Add a track above
  O`, `Set Keys volume`). A row shows `a change` for changes by scripts, and
  `opened` for the project as it opened.

In the graphical window, the tree opens in a painted window of its own.
Each state is a node, with the newest at the top, and lines show the
branches. The way back to the first state and the current state are lit.
The window takes the same keys as the terminal, and you type a name for `n` or `c` on
its last line. `:view.window undotree`, or "Open in a window" on
`<leader>pu`, opens the view of the terminal in cells.

### Commands

| Command | Effect |
| --- | --- |
| `:undotree` | opens or closes the window |
| `:earlier 5`, `:earlier 30s`, `:earlier 2m`, `:earlier 1h`, `:earlier 1d` | back by a count of states or by a time, across branches |
| `:later …` | does the same, forward |
| `:undo.goto 12` | goes to state 12 |
| `:undo.name verse` | names the current state. The undo file keeps the name after a save of the project, but a checkpoint is a file of its own |
| `:undo.diff`, `:undo.diff 3`, `:undo.diff 3 7` | show what the last step changed, what changed from state 3 to now, and what changed from 3 to 7 |
| `:checkpoint before the bridge` | names the current state and writes it beside the project |
| `:checkpoints` | lists checkpoints, and paw restores the one that you choose |
| `:checkpoint.restore 2`, `:checkpoint.restore intro` | restores by number in the list or by name |
| `:checkpoint.delete 2` | deletes a checkpoint file |
| `:ab.mark`, `:ab.mark 12` | marks the current state, or state 12, as A |
| `:ab.toggle` | switches between A and B |
| `:ab.clear` | forgets A and B |

Time travel follows the rules of Vim. `:earlier 2m` goes to the newest state made at
least two minutes before the current state, and it stops at the oldest state, while
`:later` goes to the newest state made by that time after the current state. A count
steps through states in the order that they were made, as `g-` and `g+`
do.

### A/B

- Each switch first closes the open undo step, so B is what you heard
  last.
- A switch is an ordinary sync from one snapshot to the other, as each edit
  and undo is, so the transport does not stop or move.
- paw sends the engine only what differs between the two versions. A
  volume change is sent as a volume change, a different list of clips replaces the
  clips of that track, and a device that is only in one version is added or
  removed. A plugin added in this way starts from its saved state, and you
  can hear the start.
- paw does not prune A and B while they are marked.
- When another project opens, paw forgets A and B.

### Checkpoints on disk

- `:checkpoint <name>` names the current state and writes it to a folder
  beside the project file. The project folder `song` keeps its
  checkpoints in `song/project.checkpoints/`.
- The first checkpoint makes the folder, so a project with no checkpoints
  has no folder.
- Each checkpoint is one file, `<milliseconds since 1970>-<name>.json`.
  The name is percent-encoded, with spaces as `+`. The file holds the
  project as it was, with the state of its plugins, and the list reads only
  the folder.
- Two checkpoints can have the same name. paw keeps both.
- A project that you did not save has no folder, so `:checkpoint` then names
  the state and keeps it in memory. The first save of the project writes
  all these checkpoints, each as its state was.
- A restore does not remove history. It is a new step below the current
  state, with the name of the checkpoint, so `u` returns to where you were.
- Checkpoints are not undo history. When the project opens again, the tree
  starts from the project as it opened, and the checkpoints are what is left of
  earlier sessions.

### The limit of the tree

<!-- tags: undotree-pruning -->

- The tree keeps at most 1000 states.
- When an edit goes past that limit, paw drops the oldest state that is not
  protected. The protected states are the root (the project as opened or
  made), the current state, the state saved last, named states, A and B.
- The children of the dropped state go to its parent, so undo from them goes
  past the dropped state.
- States share all unchanged parts through `Arc`, so a state costs about
  what its edit changed.
- When all states are protected, paw keeps more than the limit, because it does not
  drop a protected state.

### API

In `paw.api`, plain data only:

| Function | Returns or does |
| --- | --- |
| `undo_tree()` | `{ current, root, saved, limit, pending, states }`. Each state is `{ id, parent, children, redo, time, label, keys, name, keep, current, saved }`, oldest first. `time` is seconds since 1970, `pending` tells you that an edit is open, and `redo` is the child that redo goes to |
| `undo_current()` | the id of the current state |
| `undo_goto(id)` | goes to a state, and returns false if there is none |
| `undo_step(n)` | goes `n` states later in the order that they were made (earlier when negative), and returns the id of the new state, or nil |
| `undo_travel(seconds)` | goes to the newest state made that long after (before, when negative) the current state, and returns the id, or nil |
| `undo_name(name, id)` | names a state, the current state by default, and returns the id. nil or `""` removes the name |
| `undo_keep(id, keep)` | protects a state from pruning, or removes the protection |
| `undo_diff(a, b)` | returns what differs from `a` to `b` (`b` defaults to the current state, `a` to the parent of `b`) as `{ from, to, same, project, tracks, devices, clips, notes, lanes, items }`. Each kind is `{ added, removed, changed }`, `project` is a list of fields, and `items` are lines such as `~ device synth on track Bass: cutoff` |
| `undo_label(text)`, `undo_keys(text)` | set what makes the open step (the first label wins) and the keys typed, and the runtime sets them from the description of the key or the command |
| `checkpoint_dir()` | the folder, or nil for a project with no file |
| `checkpoint_write(name, id)` | writes a state (the current state by default) and names it. Returns `{ file, name, time, state }` |
| `checkpoint_list()` | `{ file, name, time }` for each, oldest first |
| `checkpoint_restore(file)` | takes a path from the list, or a file name in the folder, and returns the id of the new state |
| `checkpoint_delete(file)` | deletes a checkpoint file |

- `paw.undo()` and `paw.redo()` are as before. `undo_checkpoint()` is an
  older function that closes the open undo step, and it has nothing to do with
  checkpoints on disk.
- `undo_diff` compares notes in clips that are in both states. A note at
  the same start and pitch with a different value counts as changed, and a note that
  moved counts as removed and added. The function counts clips that were added or removed,
  but not their notes.

`require("undotree")` has the Lua side: `tree()`, `rows(tree)` (the
drawing), `go(id)`, `travel(dir, amount, count)`, `mark_a(id)`,
`toggle()`, `clear_ab()`, `checkpoint(name)`, `items()`, `restore(item)`,
`choose()`.

### Limits

- paw does not save the tree, so the tree starts again when the program closes or another project
  opens, but checkpoints stay.
- Labels name the key or the command by its description (the `label`
  option of a command, else its description to the first example). Edits
  by scripts, timers or the control socket without a command have the
  label `a change`.
- A note that moves counts as removed and added. Notes in added or removed
  clips do not count.
- The comparison by ear switches the full project, so it has no A/B of one
  track and no crossfade at the switch.
- Vim has `:earlier 1f` (by file writes) and `:undolist`, and paw has neither, because the
  window does both jobs.
