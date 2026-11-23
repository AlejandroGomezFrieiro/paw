# Extensions

<!-- tags: extensions-extensions -->

An extension is a directory of Lua that paw loads, and the page below describes how paw loads it and what it can register. [About the core and extensions](../explanation/about-core-and-extensions.md) explains why the line between the core and the extensions is where it is.

## Bundled extensions

Each extension has a README. Its pictures are in `extensions/<name>/images`, and the scenes in its `images/make` make them (`docs/images/make/make.sh <name>`).

| Extension | What it adds | Needs |
| --- | --- | --- |
| [`ara`](../../extensions/ara/README.md) | ARA plugins on audio tracks: the plugin reads whole clips (Melodyne, audio to MIDI), and its edits stay in the project | `native` |
| [`articulations`](../../extensions/articulations/README.md) | the articulation of each note as its MIDI 2.0 attribute, with names for each instrument from `.art.toml` maps, and keyswitches for MIDI 1.0 instruments. Maps from SFZ, Decent Sampler, folders and Reaticulate banks, and maps of plugins (MODO BASS 2, SINE Player) that bind themselves | none |
| [`columnplus`](../../extensions/columnplus/README.md) | an example that personalizes the track column: a color strip, clip counts, signs for takes and frozen tracks, other fold glyphs | none |
| [`continue`](../../extensions/continue/README.md) | a small completion source: how the phrase before the cursor in the piano roll can continue | none |
| [`doctor`](../../extensions/doctor/README.md) | a guided check of the hardware (audio, MIDI, recording, plugins), with a written report, also from the shell | `ffi` |
| [`drums`](../../extensions/drums/README.md) | drum tracks in one step, and a grid of the pieces of the kit by name | none |
| [`interop`](../../extensions/interop/README.md) | opens and writes REAPER projects and DAWproject files (Bitwig Studio, Studio One, Cubase) with `:e`, `:import` and `:export`; the example of how to add a format of files | none |
| [`launcher`](../../extensions/launcher/README.md) | the clip launcher: slots and scenes in the session view, launched on the beat while the song plays, and a capture of the performance into the timeline | none |
| [`luafx`](../../extensions/luafx/README.md) | devices written in Lua, to use and to copy | `ffi` |
| [`midilsp`](../../extensions/midilsp/README.md) | MIDI LSP, the language server for music, in `paw.lsp`: diagnostics of voice leading with fixes, the chords it hears, suggestions | `processes` |
| [`mixdiag`](../../extensions/mixdiag/README.md) | measurements of the mix (LUFS, true peak, phase), as findings to jump to | none |
| [`musicops`](../../extensions/musicops/README.md) | musical operators: humanize, strum, arpeggiate, scales | none |
| [`notation`](../../extensions/notation/README.md) | a MIDI clip as staff notation, in the terminal and in the graphical window | none |
| [`pattern`](../../extensions/pattern/README.md) | clips written as patterns of text, as in TidalCycles | none |
| [`plugstate`](../../extensions/plugstate/README.md) | the models, impulse responses and instrument files of plugins, set without their windows, and snapshots of the state of a device | `ffi`, `processes`, `network` |
| [`projdiff`](../../extensions/projdiff/README.md) | the changes between two versions of a project, and three-way merges for git | `processes` |
| [`rulerplus`](../../extensions/rulerplus/README.md) | an example that personalizes the bar labels of the ruler: phrase marks, the chord and the key, signed relative bars | none |
| [`sampler`](../../extensions/sampler/README.md) | the sample player of paw, a CLAP plugin written in Rust | `native` |
| [`sections`](../../extensions/sections/README.md) | named sections of the song as text objects, and edits by section | none |
| [`snippets`](../../extensions/snippets/README.md) | a set of snippets to start with: chords, parts and voices | none |
| [`templates`](../../extensions/templates/README.md) | a track, a group of tracks or a chain of devices, saved under a name | none |
| [`tutor`](../../extensions/tutor/README.md) | a course for new users, inside the program | none |
| [`undotree`](../../extensions/undotree/README.md) | a window on the undo tree, named checkpoints, A/B comparison | none |
| [`utau`](../../extensions/utau/README.md) | singing synthesis: vocal tracks, a vocal editor, the device that plays the voice and the engine that sings | `ffi`, `processes`, `native` |
| [`vinput`](../../extensions/vinput/README.md) | virtual inputs: a guitar heard as MIDI through gdi2m, as a port that any track takes | `processes` |

`crates/paw-mcp` is not an extension, but it is also outside the core. It is a Model Context Protocol server in front of the control socket.

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

Each Lua file can also be a file of Teal (`init.tl`, `lua/euclid/rhythm.tl`, `scale.tl`) or of another language that `paw.lang.add` registers. paw compiles the file when it loads it and keeps the Lua in `~/.cache/paw/lang`. paw checks the types of a file of Teal when it compiles it, and a file with type errors still loads, with `:checkhealth teal` listing the errors. `manifest.lua` stays Lua. [How to write an extension in Teal](../how-to/write-an-extension-in-teal.md) has the steps.

| Name | Effect |
| --- | --- |
| `paw.lang.add(ext, spec)` | registers a language whose files end in `.ext`: `spec.compile(source, path)` or `spec.command` (`"fennel --compile %s"`) makes the Lua |
| `paw.lang.loadfile(path)` | loads a file of Lua or of a registered language |
| `paw.lang.check(files)` | checks the types of `.tl` files, with `tlconfig.lua`, and returns the errors |
| `paw.lang.problems` | the type errors of each file in Teal that paw loaded, by its path |

Files in `~/.config/paw/lua/` replace the built-in modules with the same name, so you can replace any part of the runtime.

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

A command of an extension that is not loaded tells you so, instead of saying "no command". Extensions have no separate interface. An extension is Lua that calls `paw.command`, `paw.keymap.set`, `paw.on` and `paw.ui.view` in the same way as a configuration does. [How to load an extension](../how-to/load-an-extension.md) gives the steps.

### What an extension owns

paw records all that an extension registers while it loads, which includes the following:

- commands, keys and key groups, the lines of the key bar (`paw.ui.keybar.set`), views, buffer types, kinds of text buffer, and kinds of track
- picker sources, query fields, fields and views of `:s` and `:g`, completers, status line components, and grep sources
- the parts and signs of the track column and the parts of the bar labels (`paw.trackcolumn`, `paw.ruler`), the bands under the ruler of the window (`paw.frontend.bands`), the keys of insert mode in the arrange view (`paw.insert`), and the parts and the keys of paw that it changes with `set`
- curve providers, address schemes, completion sources, layers, language servers (`paw.lsp.config`), health checks, hooks (`paw.on`), options, and timers (`paw.every`, `paw.defer`)
- its directory of devices written in Lua, and the plugin directories that it adds (`paw.plugins.add_dir`)

paw also records what the extension registers later, from a command, a handler or a timer of its own. An entry belongs to the extension when a function of its files is in the entry, or when its code made the entry, and a key mapped from its code shows this in `map.ext`. A timer that the core starts while an extension loads belongs to the core.

`:extensions` lists what an extension owns, and `paw.ext.unload` and `paw.ext.provides(name)` use the same record. A command or a key tells its owner (`spec.ext`, `map.ext`), and `:help` uses this.

Two extensions can map the same key in the same view, or define the same command, and then the extension that loads last wins. `:checkhealth extensions` gives a warning for each such entry. To choose the other one, load the extensions in the other order, or map the key again in `init.lua`.

An extension can also map a key of the core again. When the new mapping has a different description, `:checkhealth extensions` gives a warning, because a key has the same meaning in every view. A mapping that keeps the description gives no warning, for example when it adds to the action of the core, such as Enter on a vocal track.

### Unload

`paw.ext.unload(name)` removes all that the extension owns, in the following order.

- paw removes its hooks and stops its timers first, so that its code does not run while paw removes the rest.
- paw restores what the extension replaced, which is a key of the core that it mapped again, a command that it defined again, an option of the core with a different default, and a part of the track column or of the bar labels that it changed.
- Its options go, with their values, and its timers stop.
- paw no longer offers its devices in Lua and the plugins in its directories, and a script with the same name in another place takes their place.
- paw forgets its modules, so when it loads again, it runs from the start.
- paw sends `ext.unloading` and `ext.unloaded`.

paw does not unload an extension in two cases.

- Another loaded extension requires it.
- Its devices are on tracks. paw names the devices and the tracks, and `:ext.unload! name` unloads the extension anyway. The devices stay and play until you remove them, and a project saved with them opens without them when the extension is not there.

`:reload` starts the full runtime again and does not need this.

## Manifests and versions

An extension can describe itself in a `manifest.lua` beside its `init.lua`. The file returns a table, and each bundled extension has one.

```lua
return {
  name = "euclid", version = "1.2.0",
  description = "Euclidean rhythms as clips",
  requires = { paw = "^1.0", sections = ">=0.1" },   -- the API, and other extensions
  provides = { "rhythms" },                         -- names that other extensions can require
  needs = { "processes" },                          -- what the build of paw must have
}
```

- `paw.api.version` is the version of the Lua interface (`1.0.0`). Its minor number increases when something is added, and its major number increases when something is removed or changed.
- `requires` gives the versions that the extension works with. `paw` is the API, and any other name is an extension, or a name in the `provides` of an extension.

| Requirement | Matches |
| --- | --- |
| `>=1.2`, `>1`, `<=2`, `<2.0`, `=1.2.3` | the comparison |
| `^1.2` | the same first number, 1.2 or more |
| `~1.2` | the same first two numbers |
| `1.2` | as `^1.2` |
| `*` | any version |
| `>=1.2, <2` | all of the requirements |

Before an extension runs, paw loads what it requires (first from beside it, then from the bundled extensions) and checks every version. paw does not run an extension whose requirements are not met, and `:extensions` and `:checkhealth extensions` give the reason.

`needs` lists the features of the build that the extension uses. `paw.api.build()` gives what the running build has, as `{ vm, features }`. `vm` is the Lua that runs the code, `luajit` on Linux and `lua52` in the web build.

| Feature | The extension uses |
| --- | --- |
| `ffi` | LuaJIT's `ffi` library, for example in devices written in Lua |
| `processes` | helper programs, through `paw.api.proc_spawn`, `io.popen` or `paw.lsp` |
| `network` | requests over the network |
| `native` | a part that Nix builds, such as a plugin or a library |

paw does not run an extension whose `needs` names a feature that the build doesn't have, and a name that paw doesn't know counts as missing. `:extensions` and `:checkhealth extensions` say what is missing, for example `needs ffi and native, which this build of paw does not have`. Each bundled extension declares its `needs`, and the table of [bundled extensions](#bundled-extensions) lists them.

An extension that works without a feature, but has one part that uses it, leaves the feature out of `needs`. The part checks `paw.ext.build_has(feature)` and says what is missing when it can't run. For example, notation's filter `!` with a shell command needs `processes`, and in a build without them it says so, while the named filters and the rest of notation still work.

`needs` isn't a security sandbox. paw only reads the list before it loads the extension, and an extension that is loaded can still call any function that the build has.

`paw.ext.satisfies(version, want)` checks a version, and `paw.ext.manifest(path, name)` reads a manifest.

## The time limit of Lua

paw stops Lua that runs for more than two seconds and does not return. The limit applies to a handler of a key, a command, an event handler, a timer and the drawing of a view, and also to a request on the control socket (`paw ctl`, the graphical window, the MCP server). The error names the code, for example `the key gZ (…) ran for more than 2 s without returning, and was stopped`, and the program continues.

| Name | Effect |
| --- | --- |
| `paw.opt.lua_limit` | the limit in milliseconds. 0 is no limit. Default 2000 |
| `paw.limit.unhurried(fn, ...)` | runs `fn` without the limit, for work that is known to be long |
| `paw.limit.within(ms, name, fn, ...)` | runs `fn` with a shorter limit, and gives its error to the caller |
| `paw.api.limit_async` | tells if the build can stop compiled loops |

- Time in the kernel does not count, for example a render, the read of a project, the start of a plugin, and `paw.wait`.
- `:lua` that you type gets one minute, and scripts that run with `-l` have no limit.
- `paw.opt.budget_ms` is a much shorter time that warns and doesn't stop the code. See [The budget of a callback](lua-other.md#the-budget-of-a-callback).
- A build without `LUAJIT_ENABLE_CHECKHOOK` uses a count hook, and code that is not part of the runtime then runs in the interpreter of LuaJIT.

## Views in the graphical window

A view that an extension registers with `paw.ui.view` and draws in cells works in the graphical window with no more code. The window offers it under More, and `:view.window name` opens it. The window draws it the way the terminal does, with its keys and its `on_mouse`. "Views in windows of their own" in [The graphical window](window.md#views-in-windows-of-their-own) describes this, and [Views that paint](window-lua.md#views-that-paint) describes `paint`.

| Field of the view | Effect |
| --- | --- |
| `title` | its name in the menu |
| `window = false` | the window does not offer it |
| `paint(g, ctx)`, `pointer(e)` | the window paints the view in pixels with `paw.canvas`. The terminal continues to draw `render` |
| `painted = "name"` | a second view, painted, beside the view of the terminal. The painted view has `window = false`. More offers it under the title of the view of the terminal |

A painted view gets `hover` events in `pointer`, which are pointer moves over the window with no button pressed. The undo tree and the mix report use this in `paint.lua` beside `view.lua`, and the vocal editor of utau uses `paint`.

Braille in a view of cells, or in `g:mono`, shows as dots in the window. A layer of the arrange view in the terminal goes into the ruler of the window as a band (see [`paw.frontend.bands`](window-lua.md#pawfrontendbands) and [Bands under the ruler](window.md#bands-under-the-ruler)).

## Health checks

`:checkhealth` runs the checks of the program and of the extensions, in the same way as in Neovim. Each result is OK, WARN (it may not be correct) or ERROR, with advice under it, and `:checkhealth audio ffmpeg` runs only those checks.

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
| `derived` | the data that paw reads from the project, such as the chords of the song: for each kind, how many values, the memory and its limit, and how many paw made again |

The utau extension checks its engine, and the sampler extension checks its plugin. An extension adds its own check, as in this example.

```lua
paw.health.register("euclid", function(h)
  h.ok("patterns loaded")
  if not paw.ext.loaded.sections then h.warn("no sections", { ":ext.load sections names them" }) end
end, { desc = "Euclidean rhythms" })
```

- `h.ok(text)`, `h.info(text)`, `h.warn(text, advice)` and `h.error(text, advice)` report, and advice is a line or a list of lines.
- A check that fails shows as an error of its own.
- `paw.health.run(name)` and `paw.health.check(names)` return the results as data.

`:doctor` (the doctor extension) is a different feature, which is a guided check of the hardware with a person.

## What the core gives an extension

The core has parts that let an extension own a full feature, and the utau extension uses all of them.

### Devices in Lua

`devices/` holds devices written in Lua (see "Writing a device in Lua" in [Devices](devices.md)). Each device runs in a helper process with its own LuaJIT state, so a device that fails stops alone.

- `paw.api.device_call(device, method, data)` sends data to the `dev.call` of one device.
- `paw.api.device_post(kind, topic, data)` sends data to every device of a kind, which means the devices that exist and each device made later. The devices of an offline render get it before their first block.
- Large data goes in files. A device maps a file with `dsp.map(path)`, and all the devices that map a file share it.

### Kinds of track

`paw.track_kinds.define(name, spec)` defines a kind of track.

| Field | Value |
| --- | --- |
| `title` | the name of the kind |
| `letter` | shown in the track header before the name |
| `create(track, args)` | makes an ordinary track this kind, with its devices or a question |
| `editor(clip)` | what Enter, a double click and `:clip.edit` open for its clips. It returns true when it opened an editor |
| `describe(track)` | a few words for `K` and the track header of the graphical window |
| `is(track)` | true for a track of the kind that does not say so |

After that, `:track.add <name> [words]`, `:track.new` (a list of every kind), the buttons and menus of the graphical window that make a track, the header, `K` and `:clip.edit` know the kind.

The kind is in `meta.kind` of the track, and the project saves it. Without the extension, the track is an ordinary track, and `K` gives the kind that it was. Vocal tracks (utau) and drum tracks (drums) are kinds. `paw.track_kinds.add(name, opts)`, `set(track, name, args)`, `clear(track)`, `of(track)` and `describe(track)` are for scripts.

### Kinds of clip

`paw.clip_kinds.define(name, spec)` defines a kind of clip, for example a film, lyrics or light cues. A clip of the kind keeps the data of the kind, and the core does not read the data. The kind compiles the data into what the clip plays, which is a MIDI or audio sound, signals and media files. The project saves these too, so the project plays without the extension. In Teal, the spec is `paw.contracts.ClipKind<D>`, and `D` is the record of the data.

The kind tells how its data is saved, and this is the job of the extension.

- `serialize(data)` gives plain data, which is text, numbers, booleans, and lists and maps of them. One text alone is data in a text format of the kind, for example an `.lrc` file. Any other value is an error that names the kind and the place, for example `` kind `film`: .frames[3]: a function is not data ``.
- `deserialize(stored, version)` gives the data back. `version` is the version that the data has in the project, and the kind changes data of an older version here.
- Bytes, for example pictures, sound or video, do not go in the data. They go in media files that `compile` names.

| Field | Value |
| --- | --- |
| `title`, `letter` | the name of the kind, and its letter |
| `version` | the version of the data, 1 if not given |
| `timeline` | `beats` (default) or `seconds`: what the positions in the data count |
| `serialize(data)`, `deserialize(stored, version)` | required: how the data is saved (see above) |
| `ext` | the file extension of data that `serialize` gives as one text, for example `lrc` |
| `create(args)` | gives the data of a new clip |
| `check(data)` | tells what is wrong with the data, or nil |
| `compile(data, clip)` | gives `{ sound, signals, media, length }` |
| `split`, `trim`, `slip` | optional: change the data for these edits. Without them, the clip keeps its data and moves its offset in it |
| `describe(clip)` | a few words for `K` |
| `look(clip, ctx)` | how the arrange view draws the clip: `{ label, marks, strip, color }` |
| `editor(clip)` | opens the clip |
| `insert` | a key of insert mode in the arrange view that inserts a clip of the kind. `Enter` after it calls `editor`. See [Insert mode](insert-mode.md) |
| `on_signal`, `chase`, `chase_back`, `on_stop` | for the time when the project plays |

The functions of a kind must be fast, and each one stops after `paw.opt.clip_kind_limit` milliseconds (50).

| Function | Effect |
| --- | --- |
| `paw.clip_kinds.add(track, name, args, data)` | makes a clip of the kind, with `data` or with the data that `create` gives. One undo step |
| `clip:data()` | gives the data of the clip |
| `clip:set_data(data)`, `paw.clip_kinds.set(clip, data)` | changes the data and compiles it again. One undo step |
| `paw.clip_kinds.compile(clip)` | compiles the data again. One undo step |
| `paw.clip_kinds.describe(clip)` | `Film clip · intro.mp4`, or `film (no extension here defines it)` |
| `paw.clip_kinds.list()`, `spec(name)`, `remove(name)` | the kinds |

Each clip keeps the version of its data. When the project opens, and when the kind is defined, paw migrates a clip with an older version, and a message tells how many clips changed. A clip with a newer version does not change, and paw shows a message such as `this clip was made by a newer film extension (data 2, this one knows 1)`. Without the extension, the clip keeps its data and its sound, and you can move, copy and delete it. When paw unloads the extension, its kinds go too.

### Plugins of an extension

An extension can include a CLAP or VST3 plugin built from its own source. Its Nix package puts the plugin beside the extension, and `paw.plugins.add_dir(dir)` adds the directory to the scan.

- paw then finds its plugins as if they were installed, for the session.
- `paw.plugins.from[kind]` lists them as plugins of the extension.
- They run in helper processes, as all plugins do.
- paw makes the devices of these plugins that a project held when the plugins were not found.
- `CLAP_PATH` and similar variables replace the plugin paths, and paw reads them one time at the start. `add_dir` adds to the paths.

The sampler extension is an example. It is a CLAP plugin written in Rust in `native/`, which is a Cargo workspace of its own, and a build of paw does not compile it. Its package puts `paw-sampler.clap` in `clap/` beside the extension.

An extension can also ship an attachment: a native library that paw
offers each CLAP plugin, loaded with `paw.plugins.attach(path)`. [Attachments](attachments.md) describes it. The ara extension is an example, and its package puts `paw-ara.so` in `lib/` beside the extension.

Scripts call such a plugin by name, in the same way as they call a device in Lua.

- `paw.api.device_call(device, method, data)` reaches a method that paw
  does not know through the extension `dev.paw.call/1` of the plugin, and the sampler answers `describe`.
- `device_call(device, "preset.load", "file:<path>")` loads a file through
  the preset-load extension of the plugin.

### Programs of an extension

An extension can start a program and talk to it over a socket or its standard input and output (see [Helper programs](lua-other.md#helper-programs)). The engine of utau is such a program, built from the `engine/` source of the extension. Its package puts it in `bin/` beside the extension, and the extension looks there first, after the `utau_engine` option and `$PAW_UTAU_ENGINE`.

### Renamed devices

`paw.api.device_alias(old, new)` makes devices of a renamed kind as the new kind, so projects saved when the utau device was part of the program get the device in Lua.

### Nix packages

The flake makes a package of each extension, which holds
`share/paw/extensions/<name>`.

- Most packages are a copy of the Lua.
- An extension with parts to build has its own `nix/default.nix`, and it gets the flake inputs that it asks for. The utau extension asks for `openutau`, the OpenUtau source of its engine, pinned in the flake.
- An extension with its own Rust workspace asks for `craneLib` and builds the way paw builds. Its dependencies are a separate derivation (the `nix/engine.nix` of the sampler).
- `withExtensions` wraps the commands of the program. `$PAW_EXTENSIONS` names the directories of the extensions, separated by `:`, and paw loads them at startup, before the configuration, also with `--clean`. A configuration that loads the same extension from another place gets the packaged one.
- `nix run .#paw-utau` is paw with utau. `nix run .` has no .NET.

## The API reference

[The Lua API](api.md) lists every public function of the `paw` modules and of `paw.api`, with the comment from the source. It is a page of `:help` (`:help paw.ext.unload`).

`tools/apidoc.lua` makes it (`paw --clean --no-plugins -l tools/apidoc.lua`), and it also writes `runtime/types/paw.lua`, a meta file for LuaLS. If you point the `workspace.library` of LuaLS at `runtime/types`, editors complete `paw.*` in a configuration or an extension. A test fails when a public function has no `---` comment, or when either file is not current.

Every event is in [Events](events.md).
