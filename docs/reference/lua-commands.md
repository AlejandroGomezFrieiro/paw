# Commands, keys and options in Lua

This page describes how Lua defines commands, ranges, fields for `:s` and
`:g`, keys, operators, text objects, registers and options. Every
command and key of paw is in [Keys](keys.md) and in `:help`.

## `paw.command`

```lua
paw.command(name, function(ctx) end, { desc = "..." })   -- ctx.args, ctx.count
paw.cmd("track.add", { "Bass", device = "synth" })       -- run a command
paw.commands.exec("5,8bars.color red")                   -- run a line, as typed after `:`
```

A number before the name of a command is its count: `:3snippet arp`
gives `ctx.count = 3`. A command or a key press is one undo step.

### Completion of arguments

The `complete` option says what the arguments complete to on the command
line. It is one of these:

- The name of a completer, for every argument.
- A list of completer names, one for each argument by position.
- A function that returns strings, or tables `{ text = ..., desc = ... }`.

```lua
paw.command("send.to", fn, { complete = { "tracks" } })
paw.command("mood", fn, { complete = function(text, info) return { "calm", "loud" } end })
```

The completers are `commands`, `tracks`, `devices`, `track_devices`,
`options`, `views`, `pickers`, `files`, `audio_files` (sound and MIDI
files), `projects` and `openable` (projects, MIDI files and sound files).
Add more to `paw.commands.completers`. `paw.commands.complete(line)` lists
the completions of a line.

### Ranges

A range before the name of a command gives the command a part of the
project, as in Vim. The syntax of ranges is in [Ex
commands](ex.md).

| Range | `ctx.range` | Which commands get it |
| --- | --- | --- |
| `:'<,'>name` | `{ selection = true, region = ... }`: the last selection of the focused view, as an operator gets it | all |
| `:5,8name`, `:5name`, `:%name`, `:'a,'bname`, `:.+4name` | `{ bars = { 5, 8 }, from, to }`: beats of the song, without `to` | only those made with `range = true` |
| `:t2,t4name`, `t*`, `t/Drums/` | adds `tracks = { ids }` | `range = true`. Other commands run once on each track, with the cursor on it |
| `:g/pattern/name` | `{ items = <the matches> }` | all |

`:` in visual mode starts the prompt with `'<,'>`. While the command runs,
`paw.keymap.selection()` gives the region of the selection. So a command
that works on the selection takes the range without more code.
`paw.commands.range(line)` separates the range from the rest of a line.

```lua
paw.command("bars.color", function(ctx) local r = ctx.range end, { range = true })
```

### Items of a range: `paw.ex`

A range holds notes, clips or tracks. `paw.ex.items(range, kind)` gives the
items of one kind (`"note"`, `"clip"` or `"track"`). Each item is
`{ kind, track, clip, note, place, at }`, with `at` in beats of the song. A
range of time alone holds the items of every track. In the piano roll, it
holds the notes of the clips that the piano roll edits.

```lua
paw.command("vel.half", function(ctx)
  local changes = {}
  for i, item in ipairs(paw.ex.items(ctx.range, "note")) do
    changes[i] = { item = item, change = { velocity = math.floor(item.note.velocity / 2) } }
  end
  paw.ex.apply(changes)                  -- one edit for each clip. paw.ex.apply(nil, items) removes them
end, { range = true, desc = "Halve the velocity of the notes in a range" })
```

### Fields of `:s` and `:g`

`paw.ex.field(name, spec)` adds a field to the patterns of `:s` and `:g`,
for example `:%s/lyric:la/lyric=lu/g`.

| Key of `spec` | Value |
| --- | --- |
| `level` | what the field belongs to: `"note"`, `"clip"` or `"track"` |
| `type` | `"number"`, `"beats"` (takes `1/8`), `"pitch"` or `"text"` |
| `get(item)` | the value of the field |
| `set(item, value, change)` | writes the value into `change`, in the form that `paw.api` keeps |
| `desc` | a description |

```lua
paw.ex.field("lyric", { level = "note", type = "text", desc = "the sung syllable",
  get = function(item) return item.note.meta and item.note.meta.lyric end,
  set = function(item, value, change) change.meta = paw.util.merge(item.note.meta or {}, { lyric = value }) end })
```

In an extension in Teal, a command's `ctx` is a
`paw.contracts.CommandContext`, its range a `paw.contracts.CommandRange`,
an item a `paw.contracts.ExItem`, the spec of a field a
`paw.contracts.ExField` and its `change` a `paw.contracts.ExChange`.

### Ranges in a view of an extension

`paw.ex.view(name, spec)` tells ranges about a view whose beats are not the
beats of the song, or that edits some clips:

```lua
paw.ex.view("myview", { song = function(col) return clip_start + col end,
  clips = function() return { clip_id } end, track = function() return track_id end,
  go = function(beat) end })                -- put the cursor at a beat of the song
```

The spec is a `paw.contracts.ExView`.

## `paw.keymap`

```lua
paw.keymap.set("<leader>mz", "command and arguments", { desc = "..." })  -- the leader: a domain (m, the mix), then a key
paw.keymap.set("gx", function(ctx) end)                    -- ctx.count, ctx.register
paw.keymap.set("<localleader>x", fn, { view = "myview" })  -- the leader of one view (a backslash)
paw.keymap.set("gz", fn, { mode = { "n", "x" } })          -- normal and visual mode. "i" is insert mode
paw.keymap.set("}", fn, { view = "arrange", motion = true })  -- a motion: also after operators and in visual mode
paw.keymap.group("<leader>m", "mix")                       -- the name of a prefix in the key hints: `+mix`
```

The keys of one view use `<localleader>`. `<leader>` keys are only for
keys that apply in every view.

### Operators and text objects

An operator gets a region: rows `r0` to `r1`, beats `c0` to `c1`, and a
kind, `"char"`, `"line"` or `"block"`. Counts, text objects, visual mode,
`.` and macros then work with the operator.

```lua
paw.keymap.operator("gR", function(region, ctx)
  for _, id in ipairs(paw.edit.arrange.tracks(region)) do
    for _, clip in ipairs(paw.track(id):clips()) do
      if clip.start >= region.c0 and clip.start < region.c1 then clip.name = "take" end
    end
  end
end, { view = "arrange", desc = "Name clips `take`" })

paw.keymap.textobject("ip", function()               -- from the cursor to the playhead
  local row = paw.cursor.index()
  return { kind = "char", r0 = row, r1 = row, c0 = paw.cursor.beat, c1 = paw.transport.position }
end, { view = "arrange", desc = "Up to the playhead" })
```

### Registers, selections and typed keys

| Function | Effect |
| --- | --- |
| `paw.keymap.setreg(value, name)`, `paw.keymap.getreg(name)` | write and read a register |
| `paw.keymap.selection()` | the region of the selection while a command runs |
| `paw.keymap.last_selection()` | the selection that is open, or the last selection of visual mode (`'<,'>`) |
| `paw.keymap.with_selection(region, fn, ...)` | run `fn` with `region` as the selection, as `:'<,'>` does |
| `paw.keymap.feed("3jdd")` | keys as typed |
| `paw.keymap.normal("dic")` | keys as typed, from inside a mapping |
| `paw.edit.arrange.yank(region)`, `paw.edit.arrange.paste(value)`, `paw.edit.roll.delete(clip, region)` | the edits of the keys `y` and `p` in the arrange view and `d` in the piano roll |

### A grid for a view

A view of an extension can have a grid: where its cursor is, and how to
move it. Counts, motions and visual mode then work in the view.

```lua
view.grid = { get = function() return row, beat end, set = function(row, beat) end, step = function() return 1 end }
-- Optional: where the thing under the cursor ends (a note). A selection then includes it.
view.grid.extent = function(row, beat) return beat + 1 end
```

## Options

```lua
paw.opt.grid = 0.5                            -- every option is in runtime/lua/paw/options.tl
paw.option.define("my_option", 42)
paw.option.define("lanes", 4, { min = 1, max = 16, integer = true })
paw.option.define("look", "plain", { values = { "plain", "fancy" } })
```

- An option with a default takes values of the type of the default.
- The numbers of the runtime have ranges, for example `grid` from 1/128 to
  64 beats and `velocity` from 1 to 127.
- `paw.opt.grid = "abc"` is an error that says what `grid` takes.
  `:set grid=abc` shows the error and does not change `grid`.
- An option that nobody defined takes all values.

The third argument of `paw.option.define`:

| Key | Value |
| --- | --- |
| `min`, `max` | the range of a number |
| `integer` | true for whole numbers only |
| `values` | the only strings or booleans that the option takes |
| `type` | a list of types, for an option such as `track_height` that is a number or `"auto"` |

`paw.option.define` gives a handle of the option: `handle:get()` gives
the value and `handle:set(value)` sets it. In Teal, the handle has the
type of the default. `paw.option.spec(name)` gives the third argument of
an option.

`paw.option.check(name, value)` checks a value and does not set it.
