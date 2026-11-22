# The file manager

<!-- tags: files oil fyler -->

paw shows a folder as text, in the same way as it shows the [lists edited as text](lists-edited-as-text.md) and as oil.nvim shows a directory, and it shows a folder as a tree as fyler.nvim does. You move files and open sound files with the same keys as the rest of paw.

## Commands and keys

| Keys or command | Effect |
| --- | --- |
| `:e some/folder`, `:files [folder]` | Shows the folder in this window: `paw://files/home/me/music`. `:files media` shows the `media` folder of the project. `:files` alone shows the folder of the buffer, else of the project, else the folder where paw started. |
| `:Files [folder]`, `:files.tree` | Shows the folder as a tree in a split: `paw://tree/home/me/music`. |
| `-` | Goes up to the folder above. In the tree, the tree shows that folder. |
| `Enter` | On a folder, goes into it (in the tree, opens or closes it, as `za` does). On a project, opens it, and asks about unsaved work first. On a sound or MIDI file, puts it at the track and time of the cursor, or on a new track if the project has no tracks. |
| `go` | Puts a sound or MIDI file on a new track. On a selection, it makes one track for each file. |
| `gh` | Plays the sound file under the cursor (a MIDI file through an instrument). |
| `gH` | Plays each sound file when the cursor stops on it for `paw.opt.audition_delay` ms (`paw.opt.files_hear`). |
| `g.` | Shows or hides the files whose names start with a dot (`paw.opt.files_hidden`). |
| `za`, `zR`, `zM` | In a tree: open or close a folder, open all, close all. |
| `:media.unused` | Lists the sound files in the `media` folder of the project that no clip plays. |

## The lines

A line is a file, and a folder ends in `/`. Columns after the name give what is known of the file. For a sound file, they give the length, sample rate and channels (from its header), and for all files, they give the size. In the `media` folder of the project, `unused` marks a sound file that no clip plays.

```
samples/
songs/
kick.wav        0.4s  8k    1ch  4.0K
pad.mp3         2.0s  44.1k 2ch  2.5K
notes.txt                        5B
```

## Edits

The edits are those of text, as the table below shows.

| Edit | Effect at `:w` |
| --- | --- |
| `cw` | renames the file |
| `dd` | deletes the file (to the trash) |
| `yyp` and a different name | copies the file |
| `o` and a name | makes a file. `name/` makes a folder. |
| a path in the name | moves the file: `songs/drums/kick.wav`, `../kick.wav`, `~/kick.wav`. paw makes the folders that the path needs. |
| a line indented less in the tree | moves the file up one folder. A line indented under a folder is in it. |

`:w` shows the plan (`rename kick.wav → kick-old.wav`,
`delete notes.txt (to the trash)`), and `y` does it.

- paw never removes a file. A deleted file goes to the freedesktop trash (`~/.local/share/Trash`), with the record that the desktop needs to restore it.
- paw refuses a name that a file has already, and it does not write over the file.
- If a plan fails in the middle, paw puts back what it did.
- An undo in the history of the project does not undo files, so restore a deleted file from the trash.

To delete the sound files that no clip plays, type `:media.unused`, then `dd` on each line and `:w`. A file that a deleted clip played may be necessary for `u`, and the trash keeps it. `:media.collect` copies files from other folders into `media`, and [Media files and audio clips](media.md) describes it.

## Lua

| Function | Effect |
| --- | --- |
| `paw.files.open(folder, { tree = true })` | Shows a folder. |
| `paw.files.sound_info(path)` | Reads the header of a sound file. |

An extension makes its own kind of list with `paw.textbuf.kind` (see [The Lua interface](scripting.md)).
