# Timers, programs and other modules in Lua

The reference page describes the timers, the helper programs, the state of each seat, and the small modules of `paw`.

## Timers and state

| Name | Effect |
| --- | --- |
| `paw.defer(fn, ms)` | runs `fn` one time, after `ms` milliseconds |
| `paw.every(ms, fn)` | runs `fn` each `ms` milliseconds |
| `paw.cancel(handle)` | stops a timer |
| `paw.timers` | the timers that wait, by handle |
| `paw.state.key = value` | a value that stays through `:reload` |
| `project.meta`, `track.meta` | tables saved with the project, for the data of extensions |

## Other modules

| Name | Effect |
| --- | --- |
| `paw.music.pitch("F#3")` | the MIDI number of a pitch name |
| `paw.music.degree("A4", "minor_pentatonic", 3)` | a degree of a scale |
| `paw.time.format(beats)` | a position as text |
| `paw.harmony` | the chords and the key that sound at a time, with `paw.harmony.at(8)`, `.next(8)` and `.key(8)`, and providers with `.provide`. See [Completion](completion.md) |
| `paw.snippet` | writes named music from the chords: `paw.snippet.add`, `.expand("dominant")`. See [Completion](completion.md) |
| `paw.cursor` | the edit cursor |
| `paw.inspect(value)` | a value as text |
| `paw.json.encode(value, pretty)`, `paw.json.decode(text)` | JSON, for the files of an extension |
| `paw.render` | renders. It sends `render.before` and runs its handlers before it starts |

## Helper programs

An extension can run a program of its own and talk to it over a Unix socket, in plain bytes.

| Function | Effect |
| --- | --- |
| `paw.api.proc_spawn(argv, { env, cwd, log, pipe })` | starts a program and returns its id |
| `proc_status(id)` | the state of the program |
| `proc_stop(id)` | asks the program to stop, in the way that Ctrl-C does, and gives it time to stop |
| `proc_kill(id)` | stops the program now |
| `sock_listen(path)`, `sock_connect(path)`, `sock_accept(id)` | open a socket |
| `sock_read(id)` | the bytes that arrived. `""` when nothing arrived, nil when the socket is closed |
| `sock_write(id, bytes)`, `sock_close(id)` | write, close |

With `{ pipe = true }`, paw talks to the program over its standard input and output, and its errors still go to `log`.

| Function | Effect |
| --- | --- |
| `proc_write(id, bytes)` | writes to the input of the program |
| `proc_read(id)` | the output. `""` when nothing waits, nil when the program closed its output |
| `proc_close_input(id)` | closes the input of the program |

The event `proc.output` (`{ id }`) tells when there is output to read, so nothing polls. When paw stops, it asks each helper program to stop.

### Data for devices

| Function | Effect |
| --- | --- |
| `paw.api.device_call(device, method, bytes)` | sends data to one device. A device in Lua answers with its `dev.call` (see "Writing a device in Lua" in [How to write a device in Lua](../how-to/write-a-device-in-lua.md)) |
| `paw.api.device_post(kind, topic, bytes)` | sends data to every device of a kind, both the devices that exist now and each device made later. The devices of an offline render get the data before their first block |
| `paw.api.device_alias(old, new)` | makes devices of a renamed kind as the new kind |
| `paw.track_kinds` | defines kinds of track |
| `paw.clip_kinds` | defines kinds of clip |

[Extensions](extensions.md#what-the-core-gives-an-extension) describes the functions in the last two rows.

## `paw.seats`: the state of each seat

A seat is a terminal or a graphical window that is attached to an instance, and each seat has its own cursor, mode, selection and keys in the same project. The state of what a person looks at belongs to a seat, e.g., a cursor, a scroll, a selection, a drag, the hover of the pointer, a prompt, a suggestion or a snippet that is not complete.

```lua
local active, shown = nil, {}   -- module locals
paw.seats.keep("mymod",
  function() return active, shown end,              -- the values now
  function(a, s) active, shown = a, s end,          -- put the values of another seat back
  function() return nil, {} end)                    -- the values of a new seat

-- Fields of a table (of a view): the names, and the values of a new seat.
paw.seats.fields("mymod.view", view, { "scroll", "hover", "drag" }, { scroll = 0 })
```

- When the turn of another seat starts, paw puts the values of that seat in place, so code that reads them does not change. With one seat, nothing moves.
- Keep in a seat only the state of the view. The state of the project stays shared, which means its notes, the shown lanes that the project saves, and the diagnostics of the project.
- paw changes a kept table as a whole, so a new seat must get a new table with `function() return {} end`. Do not use a table made one time outside the function.
- Timers run in the seat that started them.
- `paw.seats.current` is the seat whose turn it is, and `paw.seats.within(id, fn, ...)` runs `fn` in another seat and then returns to the current seat.

See `runtime/lua/paw/seats.tl` and [About seats](../explanation/about-seats.md).
