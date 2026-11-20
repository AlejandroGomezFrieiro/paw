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

Do one of these:

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

**Event payloads.** Write a record for the payload of the event. The
handler takes it with that type:

```lua
local record Saved
  path: string
end

paw.on("project.saved", function(payload: Saved)
  paw.notify("saved " .. payload.path)
end)
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

**The parts of paw that are in Lua.** A module of paw that is not in Teal
yet has the type `paw.Untyped`. You can call it and read its fields. Cast
each value that you keep to its type:
`local id = paw.cursor.track_id() as integer`. When the module is in
Teal, the cast is not necessary.

## Use another language

paw compiles other languages to Lua too. Tell paw the command that
compiles a file, for example in `init.lua`:

```lua
paw.lang.add("fnl", { name = "fennel", command = "fennel --compile %s" })
```

paw then loads `init.fnl`, `name.fnl` and modules in `.fnl`. paw keeps
the Lua that it makes in `~/.cache/paw/lang`, by the contents of each
file. A file that does not change compiles one time.
