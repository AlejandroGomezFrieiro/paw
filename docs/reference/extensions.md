# Extensions

<!-- tags: extensions-extensions -->

This page describes what an extension is, how paw loads it, and what it
can register. The reason for the line between the core and the extensions
is in [About the core and extensions](../explanation/about-core-and-extensions.md).

## Bundled extensions

Each extension has a README. Its pictures are in `extensions/<name>/images`,
made by the scenes in its `images/make` (`docs/images/make/make.sh <name>`).

| Extension | What it adds |
| --- | --- |
| [`articulations`](../../extensions/articulations/README.md) | the articulation of each note as its MIDI 2.0 attribute, with names for each instrument from `.art.toml` maps, and keyswitches for MIDI 1.0 instruments. Maps from SFZ, Decent Sampler, folders and Reaticulate banks, and maps of plugins (MODO BASS 2, SINE Player) that bind themselves |
| [`continue`](../../extensions/continue/README.md) | a small completion source: how the phrase before the cursor in the piano roll can continue |
| [`doctor`](../../extensions/doctor/README.md) | a guided check of the hardware (audio, MIDI, recording, plugins), with a written report, also from the shell |
| [`interop`](../../extensions/interop/README.md) | opens and writes REAPER projects and DAWproject files (Bitwig Studio, Studio One, Cubase) with `:e`, `:import` and `:export`; the example of how to add a format of files |
| [`drums`](../../extensions/drums/README.md) | drum tracks in one step, and a grid of the pieces of the kit by name |
| [`luafx`](../../extensions/luafx/README.md) | devices written in Lua, to use and to copy |
| [`midilsp`](../../extensions/midilsp/README.md) | MIDI LSP, the language server for music, in `paw.lsp`: diagnostics of voice leading with fixes, the chords it hears, suggestions |
| [`launcher`](../../extensions/launcher/README.md) | the clip launcher: slots and scenes in the session view, launched on the beat while the song plays, and a capture of the performance into the timeline |
| [`mixdiag`](../../extensions/mixdiag/README.md) | measurements of the mix (LUFS, true peak, phase), as findings to jump to |
| [`musicops`](../../extensions/musicops/README.md) | musical operators: humanize, strum, arpeggiate, scales |
| [`notation`](../../extensions/notation/README.md) | a MIDI clip as staff notation, in the terminal and in the graphical window |
| [`pattern`](../../extensions/pattern/README.md) | clips written as patterns of text, as in TidalCycles |
| [`plugstate`](../../extensions/plugstate/README.md) | the models, impulse responses and instrument files of plugins, set without their windows, and snapshots of the state of a device |
| [`projdiff`](../../extensions/projdiff/README.md) | the changes between two versions of a project, and three-way merges for git |
| [`sampler`](../../extensions/sampler/README.md) | the sample player of paw, a CLAP plugin written in Rust |
| [`sections`](../../extensions/sections/README.md) | named sections of the song as text objects, and edits by section |
| [`snippets`](../../extensions/snippets/README.md) | a set of snippets to start with: chords, parts and voices |
| [`templates`](../../extensions/templates/README.md) | a track, a group of tracks or a chain of devices, saved under a name |
| [`tutor`](../../extensions/tutor/README.md) | a course for new users, inside the program |
| [`undotree`](../../extensions/undotree/README.md) | a window on the undo tree, named checkpoints, A/B comparison |
| [`utau`](../../extensions/utau/README.md) | singing synthesis: vocal tracks, a vocal editor, the device that plays the voice and the engine that sings |
| [`vinput`](../../extensions/vinput/README.md) | virtual inputs: a guitar heard as MIDI through gdi2m, as a port that any track takes |

`crates/paw-mcp` is not an extension, but it is also outside the core: a
Model Context Protocol server in front of the control socket.

## Files

An extension is a directory or a single file in `~/.config/paw/extensions`:

```
extensions/euclid/init.lua      runs at startup
extensions/euclid/manifest.lua  what it is and what it needs (optional)
extensions/euclid/lua/          on the require path
extensions/euclid/devices/      devices written in Lua
extensions/euclid/README.md     its page of :help
extensions/euclid/doc/*.md      more pages of :help
extensions/clock.lua            an extension in one file
extensions/scale.tl             an extension in one file, in Teal
```

Each Lua file can also be a file of Teal (`init.tl`, `lua/euclid/rhythm.tl`,
`scale.tl`) or of another language that `paw.lang.add` registers. paw
compiles it when it loads it, and keeps the Lua in `~/.cache/paw/lang`.
paw checks the types of a file of Teal when it compiles it. A file with
type errors loads, and `:checkhealth teal` lists the errors.
`manifest.lua` stays Lua. See
[How to write an extension in Teal](../how-to/write-an-extension-in-teal.md).

| Name | Effect |
| --- | --- |
| `paw.lang.add(ext, spec)` | registers a language whose files end in `.ext`: `spec.compile(source, path)` or `spec.command` (`"fennel --compile %s"`) makes the Lua |
| `paw.lang.loadfile(path)` | loads a file of Lua or of a registered language |
| `paw.lang.check(files)` | checks the types of `.tl` files, with `tlconfig.lua`, and returns the errors |
| `paw.lang.problems` | the type errors of each file in Teal that paw loaded, by its path |

Files in `~/.config/paw/lua/` replace the built-in modules with the same
name. So any part of the runtime can be replaced.

## Load and unload

| Name | Effect |
| --- | --- |
| `paw.ext.load(path)` | loads an extension from a directory, a `.lua` file or a `.tl` file |
| `paw.ext.load_bundled(name)` | loads a bundled extension by name |
| `:ext.load name` | loads a bundled extension now. Tab completes the names |
| `:extensions` | lists the extensions that loaded, with the version, what each registered, and the error of each extension that failed |
| `paw.ext.unload(name)`, `:ext.unload name` | unloads an extension |
| `paw.ext.unload(name, { force = true })`, `:ext.unload! name` | unloads an extension when its devices are on tracks |
| `paw.ext.loaded[name]` | true when the extension is loaded |
| `paw.ext.bundled()` | the names of the bundled extensions, in `$PAW_HOME/extensions` or in `extensions` under the working directory |
| `paw.ext.provides(name)` | what an extension registered |

A command of an extension that is not loaded tells you so, in place of
"no command". Extensions have no separate interface. An extension
is Lua that calls `paw.command`, `paw.keymap.set`, `paw.on` and
`paw.ui.view` as a configuration does. [How to load an
extension](../how-to/load-an-extension.md) gives the steps.

### What an extension owns

paw records all that an extension registers while it loads:

- commands, keys and key groups, the lines of the key bar
  (`paw.ui.keybar.set`), views, buffer types, kinds of text buffer, kinds
  of track
- picker sources, query fields, fields and views of `:s` and `:g`,
  completers, status line components, grep sources
- curve providers, address schemes, completion sources, layers, health
  checks, hooks (`paw.on`), options, timers (`paw.every`, `paw.defer`)
- its directory of devices written in Lua, and the plugin directories that
  it adds (`paw.plugins.add_dir`)

paw also records what the extension registers later, from a command, a
handler or a timer of its own. An entry belongs to the extension when a
function of its files is in the entry, or when its code made the entry. A
key mapped from its code shows this in `map.ext`. A timer that the core
starts while an extension loads belongs to the core.

`:extensions` lists what an extension owns, and `paw.ext.provides(name)`
returns it. A command or a key tells its owner (`spec.ext`, `map.ext`).
`:help` uses this.

Two extensions can map the same key in the same view, or define the same
command. Then the extension that loads last wins. `:checkhealth extensions`
gives a warning for each such entry. To choose the other one, load the
extensions in the other order, or map the key again in `init.lua`.

An extension can also map a key of the core again. When the new mapping
has a different description, `:checkhealth extensions` gives a warning:
a key has the same meaning in every view. A mapping that keeps the
description (it adds to the action of the core, for example Enter on a
vocal track) gives no warning.

### Unload

`paw.ext.unload(name)` removes all that the extension owns.

- paw restores what the extension replaced:
  - a key of the core that it mapped again
  - a command that it defined again
  - an option of the core with a different default
- Its options go, with their values. Its timers stop.
- paw no longer offers its devices in Lua and the plugins in its
  directories. A script with the same name in another place takes their
  place.
- paw forgets its modules. When it loads again, it runs from the start.
- paw sends `ext.unloading` and `ext.unloaded`.

paw does not unload an extension in these conditions:

- Another loaded extension requires it.
- Its devices are on tracks. paw names the devices and the tracks.
  `:ext.unload! name` unloads it anyway. The devices stay and play until
  you remove them. A project saved with them opens without them when the
  extension is not there.

`:reload` starts the full runtime again, and does not need this.

## Manifests and versions

An extension can describe itself in a `manifest.lua` beside its
`init.lua`. The file returns a table. Each bundled extension has one.

```lua
return {
  name = "euclid", version = "1.2.0",
  description = "Euclidean rhythms as clips",
  requires = { paw = "^1.0", sections = ">=0.1" },   -- the API, and other extensions
  provides = { "rhythms" },                         -- names that other extensions can require
}
```

- `paw.api.version` is the version of the Lua interface (`1.0.0`).
  Its minor number increases when something is added. Its major number
  increases when something is removed or changed.
- `requires` gives the versions that the extension works with. `paw` is
  the API. Any other name is an extension, or a name in the `provides` of
  an extension.

| Requirement | Matches |
| --- | --- |
| `>=1.2`, `>1`, `<=2`, `<2.0`, `=1.2.3` | the comparison |
| `^1.2` | the same first number, 1.2 or more |
| `~1.2` | the same first two numbers |
| `1.2` | as `^1.2` |
| `*` | any version |
| `>=1.2, <2` | all of the requirements |

Before an extension runs, paw loads what it requires (first from beside
it, then from the bundled extensions) and checks every version. paw does
not run an extension whose requirements are not met. `:extensions` and
`:checkhealth extensions` give the reason.

`paw.ext.satisfies(version, want)` checks a version.
`paw.ext.manifest(path, name)` reads a manifest.

## The time limit of Lua

paw stops Lua that runs for more than two seconds and does not return.
The limit applies to a handler of a key, a command, an event handler, a
timer and the drawing of a view. It also applies to a request on the
control socket (`paw ctl`, the graphical window, the MCP server). The error names the code:
`the key gZ (…) ran for more than 2 s without returning, and was stopped`.
The program continues.

| Name | Effect |
| --- | --- |
| `paw.opt.lua_limit` | the limit in milliseconds. 0 is no limit. Default 2000 |
| `paw.limit.unhurried(fn, ...)` | runs `fn` without the limit, for work that is known to be long |
| `paw.api.limit_async` | tells if the build can stop compiled loops |

- Time in the kernel does not count: a render, the read of a project, the
  start of a plugin, `paw.wait`.
- `:lua` that you type gets one minute. Scripts that run with `-l` have no
  limit.
- A build without `LUAJIT_ENABLE_CHECKHOOK` uses a count hook. Then code
  that is not part of the runtime runs in the interpreter of LuaJIT.

## Views in the graphical window

A view that an extension registers with `paw.ui.view` and draws in cells
works in the graphical window with no more code. The window offers it
under More, and `:view.window name` opens it. The window draws it as the
terminal does, with its keys and its `on_mouse`. See "Views in windows of
their own" in [The graphical window](window.md#views-in-windows-of-their-own),
and [Views that paint](window-lua.md#views-that-paint) for `paint`.

| Field of the view | Effect |
| --- | --- |
| `title` | its name in the menu |
| `window = false` | the window does not offer it |
| `paint(g, ctx)`, `pointer(e)` | the window paints the view in pixels with `paw.canvas`. The terminal continues to draw `render` |
| `painted = "name"` | a second view, painted, beside the view of the terminal. The painted view has `window = false`. More offers it under the title of the view of the terminal |

A painted view gets `hover` events in `pointer`: the pointer moves over
the window with no button pressed. The undo tree and the mix report use
this, in `paint.lua` beside `view.lua`. The vocal editor of utau uses
`paint`.

Braille in a view of cells, or in `g:mono`, shows as dots in the window.
A layer of the arrange view in the terminal goes into the ruler of the
window as a band (see [`paw.frontend.bands`](window-lua.md#pawfrontendbands)
and [Bands under the ruler](window.md#bands-under-the-ruler)).

## Health checks

`:checkhealth` runs the checks of the program and of the extensions, as in
Neovim. Each result is OK, WARN (it may not be correct) or ERROR, with
advice under it. `:checkhealth audio ffmpeg` runs only those checks.

| Check | What it checks |
| --- | --- |
| `paw` | the program and its Lua |
| `audio` | the audio engine and MIDI |
| `plugins` | the plugin host |
| `ffmpeg` | `ffmpeg`, for compressed renders |
| `terminal` | pictures in the terminal |
| `window` | the OpenGL renderer of the graphical window: the graphics card or the processor, and what to do about the processor |
| `fonts` | the fonts that the graphical window uses when its own font has no glyph |
| `extensions` | the extensions, their versions and their requirements |
| `teal` | the type errors of the configuration and the extensions in Teal |

The utau extension checks its engine. The sampler extension checks its
plugin. An extension adds its own check:

```lua
paw.health.register("euclid", function(h)
  h.ok("patterns loaded")
  if not paw.ext.loaded.sections then h.warn("no sections", { ":ext.load sections names them" }) end
end, { desc = "Euclidean rhythms" })
```

- `h.ok(text)`, `h.info(text)`, `h.warn(text, advice)` and
  `h.error(text, advice)` report. Advice is a line or a list of lines.
- A check that fails shows as an error of its own.
- `paw.health.run(name)` and `paw.health.check(names)` return the results
  as data.

`:doctor` (the doctor extension) is a different thing: a guided check of
the hardware, with a person.

## What the core gives an extension

These parts of the core let an extension own a full feature. The utau
extension uses all of them.

### Devices in Lua

`devices/` holds devices written in Lua (see "Writing a device in Lua" in
[Devices](devices.md)). Each device runs in a
helper process with its own LuaJIT state. A device that fails stops
alone.

- `paw.api.device_call(device, method, data)` sends data to the `dev.call`
  of one device.
- `paw.api.device_post(kind, topic, data)` sends data to every device of a
  kind: the devices that exist, and each device made later. The devices of
  an offline render get it before their first block.
- Large data goes in files. A device maps a file with `dsp.map(path)`.
  All the devices that map a file share it.

### Kinds of track

`paw.track_kinds.define(name, spec)` defines a kind of track.

| Field | Value |
| --- | --- |
| `title` | the name of the kind |
| `letter` | shown in the track header before the name |
| `create(track, args)` | makes an ordinary track this kind: devices, a question |
| `editor(clip)` | what Enter, a double click and `:clip.edit` open for its clips. It returns true when it opened an editor |
| `describe(track)` | a few words for `K` and the track header of the graphical window |
| `is(track)` | true for a track of the kind that does not say so |

After that, `:track.add <name> [words]`, `:track.new` (a list of every
kind), the buttons and menus of the graphical window that make a track,
the header, `K` and `:clip.edit` know the kind.

The kind is in `meta.kind` of the track, and the project saves it. Without
the extension, the track is an ordinary track, and `K` gives the kind that
it was. Vocal tracks (utau) and drum tracks (drums) are kinds.
`paw.track_kinds.add(name, opts)`, `set(track, name, args)`,
`clear(track)`, `of(track)` and `describe(track)` are for scripts.

### Plugins of an extension

An extension can include a CLAP or VST3 plugin built from its own source.
Its Nix package puts the plugin beside the extension.
`paw.plugins.add_dir(dir)` adds the directory to the scan.

- paw then finds its plugins as if they were installed, for the session.
- `paw.plugins.from[kind]` lists them as plugins of the extension.
- They run in helper processes, as all plugins do.
- paw makes the devices of these plugins that a project held when the
  plugins were not found.
- `CLAP_PATH` and similar variables replace the plugin paths, and paw reads
  them one time at the start. `add_dir` adds to the paths.

The sampler extension is an example: a CLAP plugin written in Rust in
`native/`, a Cargo workspace of its own. A build of paw does not compile
it. Its package puts `paw-sampler.clap` in `clap/` beside the extension.

An extension can also ship an attachment: a native library that paw
offers each CLAP plugin, loaded with `paw.plugins.attach(path)`. See
[Attachments](attachments.md). The ara extension is an example: its
package puts `paw-ara.so` in `lib/` beside the extension.

Scripts call such a plugin by name, as they call a device in Lua:

- `paw.api.device_call(device, method, data)` reaches a method that paw
  does not know through the extension `dev.paw.call/1` of the plugin. The
  sampler answers `describe`.
- `device_call(device, "preset.load", "file:<path>")` loads a file through
  the preset-load extension of the plugin.

### Programs of an extension

An extension can start a program and talk to it over a socket or its
standard input and output (see [Helper
programs](lua-other.md#helper-programs)). The engine of utau is such a
program, built from the `engine/` source of the extension. Its package
puts it in `bin/` beside the extension. The extension looks there first,
after the `utau_engine` option and `$PAW_UTAU_ENGINE`.

### Renamed devices

`paw.api.device_alias(old, new)` makes devices of a renamed kind as the new
kind. Projects saved when the utau device was part of the program get the
device in Lua.

### Nix packages

The flake makes a package of each extension, which holds
`share/paw/extensions/<name>`.

- Most packages are a copy of the Lua.
- An extension with parts to build has its own `nix/default.nix`. It gets
  the flake inputs that it asks for. The utau extension asks for
  `openutau`, the OpenUtau source of its engine, pinned in the flake.
- An extension with its own Rust workspace asks for `craneLib`, and builds
  as paw builds. Its dependencies are a separate derivation (the
  `nix/engine.nix` of the sampler).
- `withExtensions` wraps the commands of the program. `$PAW_EXTENSIONS`
  names the directories of the extensions, separated by `:`. paw loads
  them at startup, before the configuration, with `--clean` too. A
  configuration that loads the same extension from another place gets the
  packaged one.
- `nix run .#paw-utau` is paw with utau. `nix run .` has no .NET.

## The API reference

[The Lua API](api.md) lists every public function of the `paw` modules
and of `paw.api`, with the comment from the source. It is a page of
`:help` (`:help paw.ext.unload`).

`tools/apidoc.lua` makes it (`paw --clean --no-plugins -l
tools/apidoc.lua`). It also writes `runtime/types/paw.lua`, a meta file for
LuaLS. Point the `workspace.library` of LuaLS at `runtime/types`, and
editors complete `paw.*` in a configuration or an extension. A test fails
when a public function has no `---` comment, or when either file is not
current.

Every event is in [Events](events.md).
