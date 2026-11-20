# How to write an extension in Teal

This guide shows you how to write an extension in Teal. Teal is Lua with
types. paw compiles a `.tl` file when it loads the file, so you do not
build anything. A checker finds errors of type before you run the
extension. [About Teal in paw](../explanation/about-teal.md) tells why
paw uses Teal.

## Write the extension

1. Make a file in `~/.config/paw/extensions`, for example
   `~/.config/paw/extensions/scale.tl`. An extension can also be a
   directory with an `init.tl`, and with modules in `lua/<name>/*.tl`.
2. Write the extension. This extension adds the command `:scale.notes`:

   ```lua
   local record Args
     {string}
   end

   paw.command("scale.notes", function(ctx: paw.Untyped)
     local args = ctx.args as Args
     local root, scale = args[1] or "C4", args[2] or "major"
     local names: {string} = {}
     for degree = 1, #paw.music.scales[scale] + 1 do
       names[#names + 1] = paw.music.name(paw.music.degree(root, scale, degree))
     end
     paw.notify(table.concat(names, " "))
   end, { desc = "Say the notes of a scale" })
   ```

3. Start paw again. paw loads each extension in
   `~/.config/paw/extensions` when it starts. To load it in this session,
   type `:lua paw.ext.load("/home/you/.config/paw/extensions/scale.tl")`
   with the full path of the file.
4. Type `:scale.notes C4 dorian`. paw shows
   `C4 D4 D#4 F4 G4 A4 A#4 C5`.

`config/extensions/scale.tl` in the source tree is the same extension.

## Check the types

paw checks the types of the file when it compiles it. A file with type
errors loads all the same. When paw compiles the file, the message line
shows the number of errors and the first error. To see all of the
errors, type `:checkhealth teal`.

The first check after you change a file or update paw takes about half a
second. In that time, paw reads the types of its own modules. paw keeps
the result, so the next start takes no time for the file.

To check the types before you load the file, do one of these:

- In paw, type `:lua print(#paw.lang.check({ "/path/to/scale.tl" }))`.
  The function returns a list of errors, with the file, the line and the
  message of each. An empty list means that the types are correct.
- In a shell, in the source tree of paw, type `tl check` and the file.
  The file `tlconfig.lua` tells `tl` where the types of paw are.

An editor that uses the Teal language server reads `tlconfig.lua` too.
To use it outside the source tree, copy `tlconfig.lua` and point its
`include_dir` at the `runtime/types` and `runtime/lua` directories of
paw.

## Give a type to each value

Write no `any`. Give each table a record, and each function its types.
These are the usual cases.

**Options tables.** Write a record with the fields. A field that the
caller can leave out is nil when it is not there:

```lua
local record FillOptions
  steps: integer
  hits: integer
  pitch: string
end

local function fill(opts: FillOptions)
  local pitch = opts.pitch or "C2"
end
```

**Events.** In Teal, `paw.on` takes the descriptor of an event: its name
and the record of its payload. `paw.events.kernel` has a descriptor for
each event of the kernel, and a record for each payload. Give the handler
the record of the payload. The checker finds a handler that takes a
different record:

```lua
local kernel = require("paw.events.kernel")

paw.on(kernel.project_saved, function(payload: kernel.Saved)
  paw.notify("saved " .. payload.path)
end)
```

For an event of your extension, write a record for its payload and make
its descriptor with `paw.events.event`. `paw.emit` takes the descriptor
or the name:

```lua
local record Filled
  steps: integer
end

local filled: paw.events.Event<Filled> = paw.events.event("fill.done")
paw.emit(filled, { steps = 16 })
```

For a family of events (`track.*`), use `paw.events.pattern("track.*")`.
Its handler gets a payload with no fields: cast the payload to read it.

**The kernel's setters.** `paw.api.track_set` and the other setters
(`clip_set`, `device_set`, `lane_set`, `project_set`, `transport_set`)
take a table of the fields to change, with the record of the object.
The key form, `paw.api.track_set(id, "output", nil)`, only clears a field:

```lua
paw.api.track_set(id, { name = "Bass", volume = -6 })
```

**`meta`.** The data that an extension keeps in `meta` is its own. Write a
record for it, and read it with that type:

```lua
local record Lyric
  text: string
  syllable: integer
end

local lyric = note.meta.lyric as Lyric
```

**Options.** `paw.opt` gives each option of paw with its type:
`local zoom: number = paw.opt.zoom`. For an option of your own, keep the
handle that `paw.option.define` gives. Its `get` gives a value of the type
of the default:

```lua
local steps = paw.option.define("euclid_steps", 16, { min = 1, max = 64, integer = true })
local n: integer = steps:get()
steps:set(n * 2)
```

**Tracks, clips and devices.** `paw.track`, `paw.clip`, `paw.device` and
`paw.lane` give objects with the types `paw.Track`, `paw.Clip`,
`paw.Device` and `paw.Lane`. A field of an object reads the kernel, and
the checker knows its type. A method checks what you give it:

```lua
local track: paw.Track = paw.track(1)
local volume: number = track.volume
track:add_clip({ start = 0, length = 4, notes = { { pitch = "C4", start = 0, length = 1 } } })
```

**The parts of paw that are in Lua.** A module of paw that is not in Teal
yet has the type `paw.Untyped`, except for the parts that it types. You
can call it and read its fields. Cast each value that you keep to its
type: `local group = paw.scope.current() as integer`. When the module is in
Teal, the cast is not necessary.

## Use the library of Lua 5.3

Teal checks your code with the standard library of Lua 5.3, and paw
gives that library on LuaJIT. Use `is integer`, the operators `&`, `|`,
`~`, `<<`, `>>` and `//`, `table.unpack` and `utf8` as in Lua 5.3:

```lua
local function note_on(channel: integer, pitch: integer, velocity: integer): {integer}
  return { 0x90 | (channel - 1), pitch, velocity }
end

local status, pitch = table.unpack(note_on(10, 36, 100))
assert(status & 0x0F == 9 and status >> 4 == 9 and pitch // 12 == 3)
assert(utf8.len("E♭ minor") == 8)
```

`string.pack` is not in paw: use `ffi` to pack bytes. To find a zero byte
with a pattern, write `%z`.
[About Teal in paw](../explanation/about-teal.md#the-standard-library)
tells what the library has.

## Use the contracts

A view, a picker, a buffer type and the other tables that you give to paw
have types in `paw.contracts`. The functions that take them check each
field, so a wrong name is an error before the extension runs.

1. Write a record for your view that is a `paw.contracts.View`. Put the
   state of the view in its own fields:

   ```lua
   local record Tally is paw.contracts.View
     count: integer
   end

   local tally: Tally = { count = 0, title = "Tally" }

   function tally:render(buf: paw.contracts.Buf, ctx: paw.contracts.RenderContext)
     buf:text(0, 0, "tally " .. self.count, ctx.focused and "Title" or "Normal")
   end

   paw.ui.view("tally", tally)
   ```

   A method of the record has all of the parameters of the contract.
   This includes the parameters that it does not use.
2. Give a picker the type of its items. `format`, `on_choose` and the
   other functions then get items of that type:

   ```lua
   local record Fruit
     name: string
   end

   local fruit: paw.contracts.PickSource<Fruit> = {
     desc = "Fruit",
     items = { { name = "apple" }, { name = "lime" } },
     format = function(f: Fruit): string return f.name end,
     on_choose = function(f: Fruit) paw.notify(f.name) end,
   }
   paw.pick.sources.fruit = fruit
   ```

3. Check the types. A field with a wrong name, for example
   `on_keys = ...` in a view, gives the error `unknown field on_keys`.

The other contracts are `Buftype`, `TextKind<I, F>`, `TrackKind`,
`Role<P>`, `StatusComponent`, `QueryField`, `GrepSource`, `HealthCheck`
and `Manifest`. `runtime/lua/paw/contracts.tl` tells the fields of each.

## Use another language

paw compiles other languages to Lua too. Tell paw the command that
compiles a file, for example in `init.lua`:

```lua
paw.lang.add("fnl", { name = "fennel", command = "fennel --compile %s" })
```

paw then loads `init.fnl`, `name.fnl` and modules in `.fnl`. paw keeps
the Lua that it makes in `~/.cache/paw/lang`, by the contents of each
file. A file that does not change compiles one time.
