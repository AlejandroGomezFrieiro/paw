# Files that paw keeps

<!-- tags: state-files recent -->

paw keeps its configuration, its state and its caches in the XDG base
directories of your home directory. The paths below use the default base
directories, and `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME`
change them. Projects are not in these directories, because a project is the folder
that you save.

## Configuration: `~/.config/paw`

`--config <dir>` names a different configuration directory. `--clean` does
not read it.

| Path | Holds |
| --- | --- |
| `init.lua` | The configuration. paw runs it at the start, and `:reload` runs it again. See [How to configure paw](../how-to/configure-paw.md). |
| `extensions/` | Your extensions, one directory or Lua file each. |
| `devices/` | Devices written in Lua, one `.lua` file each. paw loads a file again each time that you save it. |

## State: `~/.local/state/paw`

The state belongs to the computer and not to a project.

| Path | Holds |
| --- | --- |
| `audio.json` | The audio devices, block size and sample rate chosen in paw. See [How to choose the audio devices](../how-to/choose-audio-devices.md). |
| `recent.json` | The recent projects (below). |
| `shada.json` | What paw keeps of your editing across restarts (see "Editing history" below). |
| `devices.json` | The favorite devices, the devices added last, and the device chosen for each search. |
| `window.json` | The layout of the graphical window. |
| `layouts/` | The layouts written by `:layout save <name>` and `:workspace.save <name>`, one JSON file each. |
| `recovery/` | The safety copies of unsaved work (`paw.opt.autosave`). `:recover` opens one. |
| `projects/` | What paw remembers about each project outside its file, for example the plugins that stopped, the marks and the last cursor (`shada.json`), and the undo file (below). |
| `media-index` | The hash of each media file that paw read on this computer, by its path, size, modification time and `inode` number. So paw hashes a file one time. See [Media files](media.md#what-a-file-is). |
| `token` | The token for network connections. paw makes it at the first start. |
| `tls/` | The certificate and key of this instance for network connections. paw makes them the first time that it listens. |
| `known_instances` | The certificate fingerprints of the instances that this computer connected to. |

## Cache: `~/.cache/paw`

paw can delete the cache and make it again, so you don't need to keep it.

| Path | Holds |
| --- | --- |
| `plugins.json` | The result of the plugin scan. paw loads a plugin file again only when it changes, or when you use one of its plugins. |
| `bakes/` | What paw makes from sound files and keeps for the next time: the waveform overviews, and the sound of stretched clips and of clips with an edit list. All projects use one cache. It stays within `paw.opt.media_cache` gigabytes, and paw removes what it used least recently. |
| `media/` | The decoded sound of long files, up to `paw.opt.media_cache` gigabytes. |
| `stderr.log` | The error output while the terminal interface runs. Plugins write there. |

## Editing history

paw keeps your editing history across restarts, as Neovim does. The file
`shada.json` in the state directory holds the history of each prompt (`:`,
`/` and the named prompts), the last search, and the registers `a` to `z`
and `0`. A register is kept when it holds plain data, such as notes, clips,
text or keys, and is smaller than 1 MB. The `shada.json` in the folder of a
project under `projects/` holds the marks, the jump list, the places of the
last edits and the last cursor (track, beat and view). Nothing goes in the
project folder.

paw reads the files at the start and when a project opens. It writes them
when it quits and when a project closes. When two paw instances write the
same file, paw merges the histories and the registers by time, so no entry is
lost. Only the local seat's state is kept.

| Option | Effect |
| --- | --- |
| `paw.opt.shada` | When `false`, paw reads and writes none of these files. The default is `true`. |
| `paw.opt.history` | The number of lines that each prompt history keeps. The default is `200`. |

`--clean` and a script run (`-l`) read and write nothing.

## The undo file

The undo file keeps the undo history of a project folder after paw closes,
as the undo file of Neovim does. When you open the project again, `u`
undoes past the last save, and the states and branches from earlier
sessions are in the list of `<Space>fu` and in the undo tree of `extensions/undotree`.

| Path | Holds |
| --- | --- |
| `projects/<project>/undo/tree.json` | The states of the undo tree: the parent, the children, the time, the label, the keys, the name and `keep` of each, and which state the project's files are. |
| `projects/<project>/undo/blobs/` | The files of each state, as a save of that state writes them, named by their BLAKE3 hash. States share the files that they did not change, so a state takes about the size of its change. |

- paw writes the undo file after each `:w` of the whole project, on a
  separate thread, so the save takes no more time. It writes the new
  states and removes the files that no state uses.
- When the project opens, paw reads `tree.json`. It reads the files of an
  old state only when you go to that state.
- When the files of the project are not the files of its last save in the
  undo file, for example after a change outside paw or a `git checkout`,
  paw does not read the undo file and says
  `the undo file is for another version of the project: not read`. The
  next save writes a new undo file.
- Past `paw.opt.undofile_mb` megabytes, paw removes the oldest states. It
  keeps the first state, the saved state, named states and states marked
  `keep`.
- `paw.opt.undofile = false` turns the undo file off. Under `--clean`, paw
  reads and writes no undo file.
- The undo file is not in the project folder, so `git` and copies of the
  project don't take it. A project kept in one JSON file has no undo file.

## Recent projects

paw remembers each project that you open or save, newest first, twenty at
most. A file that no longer exists goes out of the list, and paw does not
remember projects under `--clean` or in a script.

| Command or option | Effect |
| --- | --- |
| `:recent` | Chooses a recent project from a list (`<Space>pr`). `Alt-d` in the list removes one. |
| `:recent 2` | Opens the second recent project. |
| `:recent.clear` | Removes all projects from the list. |
| `paw.opt.reopen_last` | When `true`, a start with no project opens the newest one. If it does not open, paw shows a message and starts. |
| `paw.recent.list()` | Gives `{ path, name, time }` for each recent project, newest first. |

`:recent` asks about unsaved changes, as `:open` does. In the graphical
window, the File menu has the recent projects under "Open recent".
