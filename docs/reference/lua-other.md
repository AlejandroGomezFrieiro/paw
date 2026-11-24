# Timers, programs and other modules in Lua

The reference page describes the timers, the helper programs, the state of each seat, and the small modules of `paw`.

## Timers and state

| Name | Effect |
| --- | --- |
| `paw.defer(fn, ms)` | runs `fn` one time, after `ms` milliseconds |
| `paw.every(ms, fn)` | runs `fn` each `ms` milliseconds |
| `paw.cancel(handle)` | stops a timer |
| `paw.timers.waiting` | the timers that wait: a registry, by handle (see [Registries](extensions.md#registries)) |
| `paw.state.key = value` | a value that stays through `:reload` |
| `project.meta`, `part.meta` | tables saved with the project, for the data of extensions |

## Long work in slices

A key should take a few milliseconds. Work that takes longer, for example reading every chord of a song or walking a large folder, runs in slices with `paw.slices`, and the keys that wait run between two slices.

| Name | Effect |
| --- | --- |
| `paw.slices(name, step, opts)` | calls `step(ms)` again and again, each time from a new timer, until it returns true, and returns the job. `step` works for at most `ms` milliseconds and keeps its place for the next call. `opts.ms` is that time (4 by default), and `opts.after` the milliseconds before the first slice (0 by default). A new job with the same name stops the old one. An error in `step` shows as a message and ends the job |
| `paw.slices.stop(name)` | stops a job, and returns true if it was running |
| `paw.slices.job(name)` | the job while it runs, or nil |
| `paw.slices.running()` | the jobs that run, sorted by name. Each job has `name`, `slices` (the number of slices so far), `ms` (their time in all) and `longest` (the longest slice) |

```lua
local i = 1
paw.slices("count", function(ms)
  local deadline = paw.api.real_ms() + ms
  while i <= #list and paw.api.real_ms() < deadline do
    -- the work for list[i]
    i = i + 1
  end
  return i > #list
end)
```

A step measures its time with `paw.api.real_ms()`, the time on the wall. `paw.api.now()` is the time that timers and delays wait for, and in a test it moves only when the test lets time pass.

paw itself uses three jobs. The job `harmony` reads the chords and the keys again after an edit. The job `pick` reads the items of a picker that has `more`, for example the files picker (`<Space>ff`) and the text of the project (`<Space>fg`). The job `help` makes the index of help a second after paw starts, so that the first `:help` opens at once.

## The budget of a callback

`paw.opt.budget_ms` finds code that makes keys slow. When it's more than 0, paw times each handler of a key, command, event handler, timer and drawing of the screen. A callback that takes longer than the budget writes one warning to `:messages`, for example `slow: the key gY (zz slow key) 20 ms (budget 5 ms)`. Each name warns once in a session. paw names a timer by the file and line of its function, for example `a timer (paw/help.tl:1123)`.

- When a slow callback runs inside another one, paw names only the inner callback.
- Time in the kernel doesn't count, for example a render, the read of a project and `paw.wait`, as for `paw.opt.lua_limit`.
- `paw.limit.slow` is the list of the slow callbacks, one for each name. Each has `name`, `ms` (the time of the first warning), `last` (the time of the last one) and `times` (how many times it took longer than the budget).
- `paw.limit.timed(name, fn, ...)` runs `fn` and checks it against the budget, for a callback of an extension that paw doesn't call itself.

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
| `paw.part_kinds` | defines kinds of part |
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
