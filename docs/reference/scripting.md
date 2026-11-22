# The Lua interface

<!-- tags: scripting scripting-the-scripting-interface -->

The `paw` module is the interface for configuration, scripts and
extensions, and it is also the global `paw`.

```lua
local paw = require("paw")
```

## Layers

- `paw.api` is a flat set of functions over plain data, for example
  `paw.api.track_set(id, { volume = -6 })`. The kernel in Rust defines them.
  A setter also takes one key and its value,
  `paw.api.track_set(id, "volume", -6)`, and only this form clears an entry
  (`paw.api.track_set(id, "output", nil)`).
- The objects of the `paw` module are a thin layer over `paw.api`, in
  [objects.tl](../../runtime/lua/paw/objects.tl).
- The other modules of `paw` are Lua or Teal in `runtime/lua/paw`.

## Units

| Quantity | Unit |
| --- | --- |
| Volume | dB |
| Pan | -1 (left) to 1 (right) |
| Position, length | beats |
| Position in a list | counts from 1 |
| Time in `paw.api.now()` and timers | milliseconds |
| Pitch | a MIDI number (60) or a name (`"C4"`) |

## Pages of this reference

| Page | What it describes |
| --- | --- |
| [Project objects](lua-objects.md) | the project, tracks, devices, clips, notes, MIDI files, note attributes, the transport, the tempo map, automation |
| [Commands, keys and options](lua-commands.md) | commands, ranges, fields of `:s` and `:g`, keys, operators, options |
| [Views and buffers](lua-views.md) | views, roles, buffer types, windows and tabs, text buffers, the pointer, curves, completion, the layers of the piano roll |
| [Addresses and lists](lua-addresses.md) | addresses, diagnostics, the quickfix list, annotations, language servers, queries |
| [Timers, programs and other modules](lua-other.md) | timers, helper programs, seats, other modules |
| [Events](events.md) | every event, with its payload |
| [Scripts and `paw ctl`](ctl.md) | `paw -l`, `paw ctl`, `paw attach` |
| [Lua API](api.md) | each function, made from the comments in the source |
| [Extensions](extensions.md) | what an extension is and what it can register |

The Lua API page is generated, and the pages above it describe how the
functions fit together.
