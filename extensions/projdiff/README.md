# projdiff

The changes between two versions of a project, and the merge of two
versions that changed separately. A project is JSON in a stable form. So
projdiff compares what is in it (tracks, devices, clips, notes, automation,
the tempo map, markers), not lines.

```lua
paw.ext.load("extensions/projdiff")   -- or put the directory in ~/.config/paw/extensions
```

In the picture, `:Pdiff` lists the changes. `]c` and `za` go through them,
and `Enter` goes to one:

![The demo song saved. Then its melody moved, three notes changed, the lead renamed and the bass turned down. A list shows the six changes by track, clip and note](images/tui-projdiff.gif)

## Try it

1. Type `:ext.load projdiff`. Open a saved project.
2. Rename a track, and change the velocity of a note.
3. Type `:Pdiff`. A window opens over the project with two changes, by
   track, clip and note:

   ```
   base.json → now: 2 changes
   ▾ ~ track 1 "Lead" -> "Lead 2"
       ~ name: "Lead" -> "Lead 2"
   ...
   ```

4. Press `]c`. The cursor goes to the next change.
5. Press Enter. The window closes, and the cursor is on the changed note.

## How to

### How to see what changed since the last save

Type `:Pdiff`, or press `<Space>Pd`.

### How to compare with an older version

- With a git revision: `:Pdiff HEAD~2`.
- With a state of the undo tree: `:Pdiff #7`.
- With another file: `:Pdiff other.json`.
- To compare two versions that are not the project now: `:Pdiff a b`.

### How to keep a version to compare with later

1. Type `:Psnapshot name`, or press `<Space>Ps` and type the name.
2. Later, type `:Pdiff snap:name`.

### How to go through the changes as a list

Type `:Pdiff.qf`, or press `Q` in the window of `:Pdiff`. Then use
`:copen` and `]q`.

### How to diff and merge projects with git

1. Type `:Pgit`. paw shows the lines below, with the paths of this
   machine.
2. Add this line to `.gitattributes`:

   ```
   *.json diff=paw merge=paw          # or the names of your project files
   ```

3. Add these lines to the git configuration of the repository, or to
   `~/.gitconfig`:

   ```
   [diff "paw"]
     textconv = paw --clean --no-plugins --no-listen --audio null -l /path/to/extensions/projdiff/git.lua textconv
   [merge "paw"]
     name = paw project merge
     driver = paw --clean --no-plugins --no-listen --audio null -l /path/to/extensions/projdiff/git.lua merge %O %A %B %L %P
   ```

Then `git diff`, `git log -p` and `git show` print a project as lines. Each
track, device, clip, note, lane point and marker has a line:

```
-    note id=1 length=1 start=0 velocity=100 pitch=60(C4)
+    note id=1 length=1 start=0 velocity=100 pitch=62(D4)
```

### How to settle the conflicts of a merge

1. Open the project. paw tells you that it has conflicts.
2. Type `:Pmerge`, or press `<Space>Pm`.
3. For each conflict, press `co` for ours, `ct` for theirs, or `cb` for the
   value before both.
4. When no conflict is left, type `git add` and the file in a shell.

## Reference

### Commands and keys

| Command | Keys | What it compares or does |
| --- | --- | --- |
| `:Pdiff` | `<leader>Pd` | the saved file of the project with the project now |
| `:Pdiff HEAD~2` | | that revision of the file in git with the project now |
| `:Pdiff #7` | | undo state 7 (the numbers of the undo tree) with the project now |
| `:Pdiff snap:name` | | a snapshot with the project now |
| `:Pdiff other.json` | | another project file with the project now |
| `:Pdiff a b` | | the first with the second (any of the above. `now` is the project now) |
| `:Pdiff.qf …` | | the same, as a quickfix list, one entry for each change |
| `:Psnapshot name` | `<leader>Ps` | keeps the project as it is, to compare later |
| `:Pmerge [file]` | `<leader>Pm` | shows the conflicts of a merge |
| `:Pgit` | | shows how to configure git, with the paths of this machine |

A snapshot is a checkpoint (see the undotree extension). When the project
has a file, paw writes the snapshot beside it, and keeps it. Otherwise, it
keeps the snapshot for the session.

### The window of `:Pdiff`

| Keys | Effect |
| --- | --- |
| `j` `k` | move. `Ctrl-d` `Ctrl-u` by ten, `gg` `G` to the ends |
| `za` `zo` `zc` | open and close a fold. Also `Tab`, and a click on its arrow |
| `zR` `zM` | open and close all folds |
| `]c` `[c` | the next and the previous change |
| `Enter` | closes the window and puts the cursor on the change: the track, the clip, the note, the parameter, the lane, the marker, the tempo map |
| `Q`, `gq` | sends every change to the quickfix list |
| `q` | closes |

A short diff opens with no folds closed. A long diff closes the folds
below the tracks and clips.

### What a diff names

- tracks added, removed, renamed and moved. The fader, pan, routing,
  sends and clips off the timeline (the slots of the clip launcher) of a track
- devices added and removed, their parameters, bypass, offline state,
  side-chain, and the saved state of a plugin
- clips added, removed, moved, resized and renamed, and their fades,
  stretch and audio file
- the notes of a clip as a count (`notes +2 -1 ~3`), with a line for each
  (30 lines, then "more")
- controllers, automation lanes and their points
- the tempo and the time signature, and their changes
- markers and regions
- the rest of the `meta` of the project

A field that the model gets later shows as a `field: old -> new` line. The
extension does not need to know about it.

### Merges

A merge keeps the changes of both sides when they are to different
things. Examples are different tracks, different clips, different notes of
one clip, different parameters of one device, tempo changes at different
beats.

- When both sides added items with the same id (a track, a clip, a note, a
  marker), the merge keeps both. The second item gets a new number. What
  points at it (outputs, sends, side-chains, automation) changes with it.
- A conflict is the same value changed in two ways, or changed on one side
  and removed on the other. The merged project holds ours there. It loads
  and plays.
- `meta.merge_conflicts` lists each conflict: its place, the value before,
  ours and theirs. git reports the file as conflicted, and paw tells you
  when the project opens.

The window of `:Pmerge`:

| Keys | Effect |
| --- | --- |
| `j` `k` | move between conflicts |
| `co` | take ours |
| `ct` | take theirs |
| `cb` | take the value before both |
| `cO` `cT` | take ours or theirs for all |
| `q` | close |

Each choice writes the file. A project that is open from that file, with
no changes after, opens again from it.

### Values

- "The project now" includes every edit, also the edits that a script made
  without an undo step. `:Pdiff` closes the open undo step first.
- A file names media files relative to its folder (`media/a.wav`). projdiff
  compares the full paths that the open project holds. So a project that
  opens again shows no change.
- Numbers show with four decimals.
- The project file is the same each time paw writes it (see [Project files](../../docs/reference/project-files.md)). So a file saved again gives an empty
  diff, and one change gives a small diff.
- The name of the project comes from the name of the file the first time
  it is saved. So a copy saved under another name has one different line.
- The views are cells. The graphical window draws them as the terminal
  does (see "Views in the graphical window" in
  [Extensions](../../docs/reference/extensions.md#views-in-the-graphical-window)).

### Lua

```lua
local pd = require("projdiff")
local from, to = pd.file("a.json"), pd.file("b.json")  -- pd.file(path, true): full media paths
local tree = pd.diff.diff(from.project, to.project)   -- { children, count }
pd.diff.lines(tree)                                    -- the text of the view
pd.diff.entries(tree)                                  -- { address, text } for paw.qf
pd.text.text(to.project)                               -- the text that git shows
local merged, conflicts = pd.merge.files(base, ours, theirs)
pd.merge.resolve(merged, conflicts[1], "theirs")
paw.api.project_file_text(merged)                      -- the text of the file, as paw writes it
```

- `paw.api.undo_project(id)` (in the core) gives a state of the undo tree
  as the project file holds it.
- `pd.version("#7")` and `pd.version("snap:x")` change the words of
  `:Pdiff` into a version.

## About

Projects are text, so git keeps them. But a line diff of JSON tells
little, and a merge of two lines of JSON breaks the file. So the extension
gives git a script for its two hooks. paw runs the script without a
window, and compares projects by what they hold.
