# Files that paw keeps

<!-- tags: state-files recent -->

paw keeps its configuration, its state and its caches in the XDG base
directories of your home directory. The paths below use the default base
directories. `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME`
change them. Projects are not in these directories: a project is the file
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

The state belongs to the computer, not to a project.

| Path | Holds |
| --- | --- |
| `audio.json` | The audio devices, block size and sample rate chosen in paw. See [How to choose the audio devices](../how-to/choose-audio-devices.md). |
| `recent.json` | The recent projects (below). |
| `devices.json` | The favorite devices, the devices added last, and the device chosen for each search. |
| `window.json` | The layout of the graphical window. |
| `layouts/` | The layouts written by `:layout save <name>`, one JSON file each. |
| `recovery/` | The safety copies of unsaved work (`paw.opt.autosave`). `:recover` opens one. |
| `projects/` | What paw remembers about each project outside its file, for example the plugins that stopped. |
| `token` | The token for network connections. paw makes it at the first start. |
| `tls/` | The certificate and key of this instance for network connections. paw makes them the first time that it listens. |
| `known_instances` | The certificate fingerprints of the instances that this computer connected to. |

## Cache: `~/.cache/paw`

paw can delete and make the cache again. It is not necessary to keep it.

| Path | Holds |
| --- | --- |
| `plugins.json` | The result of the plugin scan. paw loads a plugin file again only when it changes, or when you use one of its plugins. |
| `bakes/` | What paw makes from sound files and keeps for the next time: now the waveform overviews. All projects use one cache. It stays within `paw.opt.media_cache` gigabytes, and paw removes what it used least recently. |
| `media/` | The decoded sound of long files, up to `paw.opt.media_cache` gigabytes. |
| `stderr.log` | The error output while the terminal interface runs. Plugins write there. |

## Recent projects

paw remembers each project that you open or save, newest first, twenty at
most. A file that is not there any more goes out of the list. paw does not
remember projects under `--clean` or in a script.

| Command or option | Effect |
| --- | --- |
| `:recent` | Chooses a recent project from a list (`<Space>fR`). `Alt-d` in the list removes one. |
| `:recent 2` | Opens the second recent project. |
| `:recent.clear` | Removes all projects from the list. |
| `paw.opt.reopen_last` | When `true`, a start with no project opens the newest one. If it does not open, paw shows a message and starts. |
| `paw.recent.list()` | Gives `{ path, name, time }` for each recent project, newest first. |

`:recent` asks about unsaved changes, as `:open` does. In the graphical
window, the File menu has the recent projects under "Open recent".
