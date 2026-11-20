# How to write an importer or exporter

<!-- tags: formats-register importer exporter -->

This guide shows you how to make paw open, bring in and write the files
of another program. You register a format with one call. Then `:import`,
`:open`, `:edit` and `:export` take its files, and the ending of a file
selects the format. As an example, the guide makes a format for a small
text file of notes. Each line is a pitch, a start and a length in beats.

```text
60 0 1
64 1 1
67 2 2
```

The `interop` extension reads and writes REAPER projects and DAWproject
files in the same way. Its
[README](../../extensions/interop/README.md#how-a-format-is-made) shows
the two formats as larger examples.

## Register the format

Put this in your `init.lua`, or in the `init.lua` of an extension:

```lua
paw.formats.register({
  name = "notes", desc = "Lists of notes", extensions = { "notes" },
  import = function(path, opts)
    local notes = {}
    for line in io.lines(path) do
      local pitch, start, length = line:match("^(%d+)%s+(%S+)%s+(%S+)")
      if pitch then notes[#notes + 1] = { pitch = tonumber(pitch), start = tonumber(start), length = tonumber(length) } end
    end
    if not opts.merge then paw.project.new() end
    local track = paw.add_track({ name = path:match("([^/]+)%.notes$") })
    track:add_clip({ start = 0, length = 8, notes = notes })
    return string.format("read %d notes from %s", #notes, path)
  end,
  export = function(path)
    local lines = {}
    for _, clip in ipairs(paw.tracks()[1]:clips()) do
      for _, n in ipairs(clip:notes()) do
        lines[#lines + 1] = string.format("%d %g %g", n.pitch, clip.start + n.start, n.length)
      end
    end
    local file = assert(io.open(path, "w"))
    file:write(table.concat(lines, "\n"), "\n")
    file:close()
    return "wrote " .. #lines .. " notes to " .. path
  end,
})
```

- `import` reads the file. `opts.merge` is true for `:import`, which adds
  to the project. It is false for `:open` and `:edit`, which open the file
  in place of the project.
- `export` writes the project to the file.
- Each returns the message to show. To list what did not carry over on a
  page, return `{ said = "...", lost = { "a line", ... } }`.
- An error that they raise shows as a message, and the project stays as
  it was.

A format can leave out `import` or `export`: it then only writes, or only
reads. Add `project = true` when a file holds a whole project. Then
`:w song.notes` writes it too. Add `detect = function(path) ... end` when
the files of the format do not always have the same ending.

## Use it

1. Type `:import song.notes`. A track with the notes appears.
2. Type `:export copy.notes`. paw writes the notes to `copy.notes`.
3. Type `:help formats`. The list shows the new format, with the formats
   of paw and of the extensions that are loaded.

`:import` and `:export` complete the names of the files of the formats
that are registered.

## Remove it

Type `:lua paw.formats.unregister("notes")`. When an extension registered
the format, `:ext.unload` removes it with the rest of the extension.

## See also

- [The interop README](../../extensions/interop/README.md): the interface
  of a format, and what REAPER projects and DAWproject files share.
- [Extensions](../reference/extensions.md): how an extension is made.
