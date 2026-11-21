# Plugins

<!-- tags: plugins plugin clap vst3 lv2 -->

paw hosts CLAP, LV2 and VST3 plugins. A plugin is a device, the same as a
built-in device (see [Devices](devices.md)). For why each plugin runs in a
process of its own, see
[About the plugin sandbox](../explanation/about-the-plugin-sandbox.md).

## Kinds and names

| Format | Kind |
| --- | --- |
| CLAP | `clap:<id>` |
| LV2 | `lv2:<uri>` |
| VST3 | `vst3:<name>` |

`:devices` lists the devices. `:device.add` accepts a part of a kind or of
a name (`:device.add dragonfly hall`).

```lua
local amp = guitar:add_device("lv2:urn:brummer:neuralrack")
local verb = guitar:add_device("clap:michaelwillis.dragonfly.hall")
for _, p in ipairs(verb:info().params) do print(p.key, p.name, p.min, p.max) end
verb:set("dry_level", 80)       -- by key, or by the name the plugin shows
```

## Where paw finds plugins

- `~/.clap`, `~/.lv2`, `~/.vst3`, the Nix profiles and `/usr/lib`.
- Or the directories in `CLAP_PATH`, `LV2_PATH` and `VST3_PATH`.
- For CLAP and VST3: the directories that extensions add with
  `paw.plugins.add_dir(dir)`, also with `--no-plugins`. paw lists these
  plugins as part of the extension.

### Scan

- paw reads the plugin files in a separate process, and keeps each result
  immediately. If a file stops the scan process, paw records it.
- paw remembers a file that crashed or hung during the scan, or that was
  in the scan when paw stopped, with its modification time. At later
  starts, paw does not read it again, and shows one line that names it.
  paw reads it again when the file changes, or when you type
  `:plugins.rescan`.
- `:plugins.rescan` reads every file again. `:plugins.rescan <name>`
  reads the files and plugins whose name contains `<name>`.

### Libraries

A plugin that is built for a different system needs the libraries that it
names. If these libraries are not on the path of the loader (on NixOS),
paw looks for them in:

- the nix-ld directory
- the system and user profiles
- the directories where the build found them (`PAW_PLUGIN_LIB_DIRS`, which
  the dev shell sets)
- the usual directories of other systems
- the directories in `PAW_PLUGIN_LIBS`.

paw loads the display libraries (`libX11` and related libraries) before
each plugin. The toolkit of a plugin opens them by name when it makes its
window. Without them, an editor is an empty black window.

## Notes

- A CLAP plugin gets notes as CLAP note events. If it prefers MIDI 2.0, it
  gets MIDI 2.0, and the attribute of a note (an articulation, see
  [The Lua interface](scripting.md)) is part of the note-on.
- A plugin that names its keys (the CLAP `note-name` extension: the drums
  of a drum kit, the keyswitches of a sampler) shows the names on the keys
  of the piano roll, and `K` says them. The built-in `drums` kit names
  its pieces the same way: Kick, Snare, Closed hat.
  `paw.plugins.note_names(device)` and `paw.api.device_note_names(device)`
  give them as `{ [pitch] = name }`.
- For controllers, MIDI 2.0 and per-note expression, see
  [MIDI](midi.md#where-controller-moves-go).

## Parameters

- paw lists the parameters of each instance, with keys made from their
  names, and the id that the plugin gives each parameter (see
  [Device parameters](device-parameters.md)).
- VST3 values are from 0 to 1. CLAP and LV2 values use the ranges of the
  plugin.
- For a plugin with many parameters, `:param` (`f` in the device panel,
  or the line "and N more parameters" on the card in the graphical window)
  finds a parameter by a part of its name. `Enter` selects it in the panel
  and puts it first on the card. The card shows sixteen parameters.
- paw keeps the parameters that you select this way with the device in
  the project. `Ctrl-x` in that picker removes one from the top of the
  card.
- The last touched parameter is the parameter that moved last, in the
  editor of the plugin or in paw. The device panel goes to it when it moves
  in the editor, and the card shows it first.

| Command | Key (device panel) | Effect |
| --- | --- | --- |
| `:param` | `f` | Find a parameter by name. |
| `:param.last` | `t` | Go to the last touched parameter. |
| `:param.last automate` | | Show the automation lane of the last touched parameter. |
| `:param.last learn` | | Bind a MIDI controller to the last touched parameter (see [MIDI controllers](learn.md)). |

## State

- The project file holds the state of each plugin. paw restores it when it
  loads the project, and gives it to offline renders and to the engine
  after a restart.
- Parameters set through the project apply after the state.
- A CLAP plugin that loads files (an instrument, a patch) takes a file by
  its path:
  `paw.api.device_load(device, { name = "Violins", factory = "file:/path/Violins.sfz" })`
  (one undo step), or
  `paw.api.device_call(device, "preset.load", "file:/path")`.
- An LV2 plugin can list properties (`patch:writable`): files and values
  outside its parameters, such as the model of an amp.
  `paw.api.device_call(device, "properties")` lists them as JSON, with the
  value that the plugin told last.
  `paw.api.device_call(device, "property.set", '{"property": "model", "value": "/path/amp.nam"}')`
  sets one, as the window of the plugin does. A path must be absolute.
- `paw.api.device_load(device, { name = "Deluxe", params = p, call = { method = "property.set", data = json } })`
  makes the same change as one undo step. The project keeps the state that
  the plugin has after the call. The
  [plugstate](../../extensions/plugstate/README.md) extension uses it.

## The calls of a plugin

`paw.api.device_call(device, method, data)` asks a plugin for one of
these. A format that does not answer a method fails with "no method".

| Method | Formats | Data | Answer |
| --- | --- | --- | --- |
| `presets` | CLAP, LV2, VST3 | nothing | the presets of the plugin, as JSON |
| `preset.load` | CLAP, LV2, VST3 | the id of a preset, or `file:<path>` | nothing |
| `preset.export` | VST3 | nothing | the state as a `.vstpreset` file |
| `note-names` | CLAP | nothing | the names of the keys, as JSON |
| `properties` | LV2 | nothing | the properties, as JSON |
| `property.set` | LV2 | `{"property": uri, "value": value}` | nothing |

The names are in `paw_engine::device::method`, where each host finds them.

## Editors

| Way | Effect |
| --- | --- |
| `ge` on a track or on a device in the panel | show or hide the editor of the plugin |
| `Enter` on a device row in the panel | the same |
| the `edit` button in the graphical window | the same |
| `device:open_editor()` | open the editor |
| `device.editor` | `"open"`, `"closed"` or nil |

- The editor windows belong to the kernel process. They also work when the
  frontend is a terminal.
- paw reads back the changes that you make in an editor. The project
  shows the value of the plugin, and stops the use of its own value for
  that parameter.
- A plugin that you add by hand (the device picker, `:device.add`, the
  "Add a device" box in the graphical window) opens its editor
  immediately, as in REAPER. Some instruments make no sound until their
  editor opens one time. `paw.opt.editor_on_add = false` stops this.
- A plugin that a script adds or that a project load adds does not open
  its editor. A plugin that paw adds with nobody at paw (`-l`, a kernel
  that no window watches) also does not open its editor.

| Kind of editor | How paw shows it |
| --- | --- |
| CLAP, VST3 and LV2 editors for X11 (JUCE, DPF, VSTGUI, Xputty, …) | In a window of paw, through XWayland on a Wayland desktop. |
| LV2 editors in any toolkit that open their own window (`ui:showInterface`, and the older "external UI"), Gtk and Qt among them | In their own window. Gtk 3 and Qt editors are native Wayland windows when the toolkit is configured for Wayland. |
| LV2 editors that are a Gtk 2 or Gtk 3 widget only | In a Gtk window, with the copy of Gtk that the editor brings. |
| CLAP editors that can only float | In their own window, a native Wayland window if they can. |

- paw tells editors the scale of the screen (`Xft.dpi`, or
  `PAW_UI_SCALE=1.5`). Then they are not too small or blurred on a dense
  screen.
- An X11 error of a plugin does not stop paw.
- paw tells the window manager when an editor cannot change size.
- paw cannot show an LV2 editor that is a Qt widget with no way to show
  itself.
- Windows plugins through yabridge draw and take the pointer in Wine, not
  in paw. See
  [How to fix a plugin editor that does not work](../how-to/fix-a-plugin-editor.md).

## Processes

Each plugin runs in a helper process, which is the `paw` program started
again.

- If a plugin crashes or hangs, paw loses only that plugin. paw tells
  which plugin and why. The track continues: an effect that is gone lets
  the sound through, an instrument is silent.
- `:device.restart` (`gR` in the device panel, the Restart button in the
  graphical window) starts the plugin again, with its last state in the
  project.
- The audio thread waits for a plugin for about the time of one block. A
  slow plugin costs its own track a block of sound, and not a dropout for
  all. The notes and controllers of that block are not lost: the plugin
  gets them at the start of the next block that it takes.
- A plugin that gives no block for two seconds has hung. paw stops it and
  reports it as a crash.
- A render waits for a block of a plugin for 20 seconds at most, one time.
  After that, the render continues without the plugin, and says so.
- Each other request has a time limit. If a plugin hangs while paw makes
  it or saves its state, paw stops it and reports it.
- `--plugins-in-process` (or `PAW_PLUGIN_SANDBOX=0`) loads the plugins
  into paw itself. This removes the cost of the transfer, and removes the
  protection.

## Status of a device

`device.status` (in `device:get()` and in the state of the frontend) is one
of these values:

| Status | Meaning |
| --- | --- |
| `running` | The device plays. |
| `loading` | The helper makes the device. An instrument is silent, an effect lets the sound through. |
| `stopped` | The device crashed, hung, failed to load, or took longer than 45 seconds to load. The message gives the reason. |
| `offline` | The device is set offline. paw does not make it. |
| `missing` | The plugin is not installed. |

### Load in the background

- When a project opens or you add a plugin, the device shows immediately,
  with the status `loading`. Its helper makes it, four plugins at a time.
- When the plugin is ready, it gets its saved state, and paw sends the
  event `device.ready`.
- `:device.restart` tries a stopped device again.
- A device with the status `loading` or `stopped` keeps the state that it
  had when the project opened. A save writes that state back with no change.
- A render waits for devices with the status `loading`. It refuses to start if paw
  cannot make a device, and names the device.
- A script run with `-l` waits for each plugin that it adds, unless it
  calls `paw.api.load_apart(true)`.

### Plugins that are not installed

A plugin that is not installed stays in the project. paw shows it by its
name, as `missing` ("not installed"), with its saved state and parameter
values. The chain does not use it, and a save writes it back with no
change. On a computer where the plugin is installed, it is the plugin
again.

### Offline devices

paw does not make an offline device: no process, no sound. The chain does
not use it. It keeps its state and parameters, and the project saves the
offline flag.

| Way | Effect |
| --- | --- |
| `o` in the device panel, `:device.offline` | Set the selected device offline, or online again. |
| `device:set_offline(true)` | The same in Lua. |
| the plug button on the card of a plugin | The same in the graphical window. An offline card says so, and has an Online button. |
| `:plugins.online` | Set every offline device online. |
| `:plugins.offline` | Set every plugin offline: CLAP, LV2 and VST3 plugins, and devices written in Lua. |

To open a project with its plugins offline:

| Way | Example |
| --- | --- |
| command line | `paw --plugins-offline song` |
| Ex | `:edit song offline` |
| Lua | `paw.open(path, { plugins_offline = true })` |
| recovery | the "(plugins offline)" entries of `:recover`, or `:recover 1 offline` |

These also set the devices written in Lua offline, because they run code
in a process of their own, as a plugin does. The devices that come with
paw stay online.

The offline flags that these set are saved with the project.

### Plugins that failed to load

If a plugin fails or hangs while a project opens, paw records it. The
record is next to the other state of the project
(`$XDG_STATE_HOME/paw/projects/`), not in the project file. The next time that the project opens, that plugin is
offline, and a message says so. `:edit song online` opens the
project with all its plugins. When the plugin loads, paw forgets the
failure.

## Attachments and ARA

An extension can load a native library that takes each CLAP plugin that
paw makes: `paw.plugins.attach(path)`. See [Attachments](attachments.md).
The [ara](../../extensions/ara/README.md) extension hosts ARA plugins in
this way.

`paw.api.device_types()` gives the `features` of each plugin: the CLAP
features, or the VST3 subcategories. An ARA plugin has the CLAP feature
`ara:supported`. paw reads the features when it reads a plugin file.

## Lua devices

Devices written in Lua also run in a helper process. See
[Lua devices](lua-devices.md).

## The sampler extension

`extensions/sampler` gives `paw sampler` (`clap:dev.paw.sampler`). It plays
SFZ and Decent Sampler instruments, and it gives sampler tracks. A MIDI 2.0
attribute or a keyswitch selects the articulation of each note.
See its [README](../../extensions/sampler/README.md).
