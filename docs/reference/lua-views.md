# Views and buffers in Lua

The reference page describes how Lua draws on the screen, and it covers views, roles, buffer types, windows and tabs, text buffers, the pointer, curves, completion and the layers of the views. The terms window, buffer and tab have the meanings that [Windows, buffers and tabs](windows.md) gives under "Windows, buffers and tabs".

## `paw.ui.view`

A view is a table with a `render` function, and `render` draws into a buffer of cells. An error in a view shows in the place of the view, and the other views are not affected.

```lua
paw.ui.view("clock", {
  render = function(self, buf, ctx)
    buf:fill(0, 0, buf.width, buf.height, " ", "StatusLine")
    buf:text(1, 0, paw.time.format(paw.transport.position), { fg = "#ff9e64", bold = true })
  end,
  on_key = function(self, key) end,           -- keys with no mapping
  on_mouse = function(self, event) end,
})
paw.ui.dock("clock", { side = "top", size = 1 })
paw.ui.toggle("mixer")   paw.ui.focus("arrange")   paw.ui.open("help", { title = "Keys" })
paw.ui.input({ prompt = "Name: " }, function(text) end)
paw.ui.menu({ { label = "Rename", run = function() end }, "-", { label = "Delete", keys = "x", run = function() end } }, { x = 10, y = 4 })
paw.notify("message", "warn")
```

A view has the same fields in both frontends, and the graphical window shows a view of an extension with no code of its own. [Extensions](extensions.md) lists the fields for the graphical window (`title`, `window`, `paint`, `pointer`, `painted`).

| Field | Effect |
| --- | --- |
| `render(self, buf, ctx)` | draws the view in cells |
| `stamp(self, ctx)` | a text of what `render` reads that no event tells, so that a window without the keyboard keeps its cells while the text stays the same (see [A stamp for each window](#a-stamp-for-each-window)) |
| `on_key(self, key)` | gets the keys that have no mapping |
| `on_mouse(self, event)` | gets the pointer (see [The pointer](#the-pointer)) |
| `gestures` | functions for the hit regions of roles (see [Roles](#roles)) |
| `grid` | the cursor of the view (see [Commands, keys and options](lua-commands.md#a-grid-for-a-view)) |
| `status(self, line)` | the part of the status line for the view |
| `help` | the topic of `:help` for the key line of the view |
| `live_roles` | the roles that change while the song plays (see [Roles](#roles)) |
| `still` | true when nothing in the view changes while the song plays (see [Roles](#roles)) |
| `live_part` | true when all of the view changes while the song plays, as the status line does (see [Roles](#roles)) |
| `live_stamp(self, width)` | for a `live_part` view, a text of what it shows now, so that the terminal draws it again only when the text changes (see [Roles](#roles)) |
| `live_values()` | values of its own for the live messages, by name (see [Roles](#roles)) |
| `moving(self)` | true while the view also shows something else that moves (see [Roles](#roles)) |
| `redraw_every` | the milliseconds between two scenes of a view that moves while the song plays |
| `scene_key(self)` | a string that says what the drawing of the view in a window shows, without the live values (see [Roles](#roles)) |
| `scene_roles` | the roles that a window must paint for `scene_key` (see [Roles](#roles)) |
| `title_of(self)` | the title of its pane in the graphical window, for what the view shows now |
| `window_state` | the names of the fields of the view that each window has for itself (see [A state for each window](#a-state-for-each-window)) |
| `window_fresh` | the fields of `window_state` that a new window starts without, e.g., caches |
| `window_instances` | true to give each window its own table of the `window_state` fields (see [A state for each window](#a-state-for-each-window)) |
| `open_target(self, target)` | opens a thing by name in the window, for `:e view://target`. It returns false and a message when it cannot |
| `window_target(self)` | the name of what the window shows, for a saved layout. It gives nil when that thing is gone (undone or deleted) |
| `share` | the part of the room that the view keeps: `column`, `least` and `most`, fractions (see [Windows, buffers and tabs](windows.md#sizes)) |

### A state for each window

A view keeps its state in its own table, e.g., `self.clip_id`. Without `window_state`, the view shows in one window at a time, and with `window_state`, any number of windows show the view and each has its own values of those fields. paw puts the values of a window into the table before the view draws in that window, and also before a key, the pointer or a command acts in the window, so the code of the view does not change.

```lua
paw.ui.view("score", {
  clip_id = nil, beat = 0, cache = nil,
  window_state = { "clip_id", "beat", "cache" },
  window_fresh = { "cache" },
  open_target = function(self, target)
    local clip = paw.layout.clip_named(target)
    if not clip then return false, "no clip " .. target end
    self.clip_id, self.beat = clip.id, 0
  end,
  window_target = function(self)
    if self.clip_id and pcall(paw.api.clip_get, self.clip_id) then return self.clip_id end
  end,
  render = function(self, buf, ctx) end,
})
```

With `window_instances = true`, each window has its own table, which holds the fields of `window_state` and takes the other fields and the functions from the view. The view draws in a window with that table as `self`. The view that `paw.ui.view` returns reads and writes the fields of `window_state` in the window that drew or acted last, as before. The piano roll works this way.

| Function | Effect |
| --- | --- |
| `paw.ui.instance(view)` | the table of a view with `window_instances` in its window with the keyboard, else in the window that had it last. With no window, it gives the view |
| `paw.ui.instance_of(win)` | the table of the window `win`, for a view with `window_instances` |
| `paw.layout.window_keep(view, get, set, fresh)` | keeps other state of a view for each window, e.g., locals of a module. `get()` gives one value, `set(value)` puts it back, `fresh(value)` gives the value of a new window |
| `paw.layout.within(win, fn, ...)` | runs `fn` with the state of the window `win` in the table, then puts the state before back |
| `paw.layout.bound(view)` | the window whose state the table of the view has now |
| `paw.layout.clip_named(target)` | the clip of a number, an address or a name |
| `paw.layout.loose(view, from)` | a window in no tab, for a view in a window of its own of the graphical window, with the state of the window `from` to start |
| `paw.layout.hand_over(from, to)` | gives the state of the window `from` to the window `to` of the same view |
| `paw.layout.project_screen()` | the layouts that the project keeps: `{ default, seats }`, `seats` by the kind of seat |
| `paw.seats.kind(seat)` | the kind of a seat, `"window"` or `"terminal"`: the key of its layout in the project |

A command can act on a view from a different window, e.g., `Enter` on a clip in the arrange view, and it then acts in the window of that view that had the keyboard last. A view in a window of its own of the graphical window has a state of its own too, which starts from the state of the pane that it left. When the view returns to the main window, that pane takes its state.

### A stamp for each window

A view with `stamp(self, ctx)` gives a text of what its drawing reads, and paw keeps the cells of each of its windows under that text. On a later frame, a window that doesn't have the keyboard and has the same text gets its cells back, and paw doesn't call `render`. The playhead and the meters of the window still move. The window with the keyboard is always drawn.

```lua
stamp = function(self, ctx)
  return table.concat({ tostring(self.clip_id), self.beat, self.scroll, tostring(ctx.follower) }, " ")
end,
```

paw adds to the text what each window can read, so `stamp` gives only the rest:

| paw adds | Example |
| --- | --- |
| the count of events so far (`paw.events.emitted()`) | an edit, an option, the mode, the cursor of the arrange view, a chord that paw reads again |
| the count of edits of the project | a note, a fader |
| the transport | play, record, the playhead, the loop and the punch range |
| the place and the size of the window, its background, and its winbar | a window made larger |

What `stamp` gives is the state of the window that changes without an event, for example its cursor and its scroll, and what its drawing reads from other modules without an event. A change of a highlight group draws every window again. A window that shows pixels (`buf:surface`, `buf:strip`) is always drawn. A view without `stamp` is drawn on each frame.

A stamp that misses something shows an old picture. With `paw.opt.check_stamps`, paw draws each window anyway and logs each window that drew other cells with the same stamp. The test suite runs with it on, and a test fails on such a window. The arrange view, the piano roll and the mixer give a stamp.

### Pictures

Where the terminal shows pictures, a view can keep a rectangle of its buffer for pixels under its cells, and it draws cells there only when it cannot show pixels.

```lua
local pictured = buf:strip(0, 1, buf.width, buf.height - 1, { key = "level", under = true,
  draw = function(g, px) paw.plot.curve(g, px, { points = points, from = 0, pixels_per_beat = 4 * px.cell.w }) end })
if not pictured then draw_it_in_cells() end
```

A picture of pixels (a frame of a video, a spectrogram) shows with `buf:image(x, y, w, h, key)`, and where there are no pictures, paw writes it in half blocks. `buf:strip`, `buf:surface`, `buf:image` and `paw.plot` are in [Pictures in the terminal](pictures.md).

## Roles

<a id="roles"></a>A view is written one time, and every frontend shows it, so the terminal draws its cells and the graphical window draws the same layout in its own font.

A control (a fader, a switch, a button) is a role. The view marks the role over a rectangle, with props that say what the role shows, and the terminal draws the cells of the role while the graphical window paints it as a widget.

The pointer works through hit regions. A press, a move or the wheel on a region goes to the gesture of the view for its `kind`. The terminal gives whole cells and the graphical window gives fractions of a cell (`e.fine`), and the same function gets both.

```lua
paw.ui.role("hit", {                                -- a role of an extension
  props = { velocity = "number 0..127" },
  cells = function(buf, p) buf:text(0, 0, p.velocity > 90 and "█" or "▄", "Title") end,
})
paw.ui.view("pads", {
  render = function(self, buf, ctx)
    buf:mark("hit", 2, 1, 2, 1, { velocity = 100, hit = { kind = "pad", n = 1 } })
    buf:mark("fader", 6, 1, 3, 8, { at = 0.7, zero = 0.8, hit = { kind = "level" } })
    buf:mark("meter", 10, 1, 2, 8, { levels = { l, r }, bind = "meter:" .. track })
    buf:mark("button", 0, 9, 6, 1, { text = "play", hit = { cmd = "play" } })
    buf:hit(0, 0, buf.width, 1, { kind = "title", hint = "the pads" })
    local left, right = buf:columns({ 12, "*" }, 1)   -- buffers side by side
  end,
  gestures = {
    pad = function(self, e)                           -- e.hit, e.rect, e.x, e.y, e.kind, e.button
      if e.kind == "down" then paw.mouse.grab(e, { drag = function(d) end, up = function(u) end }) end
    end,
  },
})
```

The widget roles are in this table.

| Role | Props |
| --- | --- |
| `label` | `text`, `align`, `font` (`sans` or `title` in the window), `capital`, `strike` |
| `button` | `text`, `on`, `menu`, `quiet`, `icon` (the window shows the icon in place of the glyph) |
| `switch` | `letter`, `on`, `style`, `tone` |
| `knob` | `value`, -1 to 1 |
| `fader` | `at` and `zero`, 0 to 1 along its travel |
| `meter` | `levels`, `hold`, `clipped` |
| `peak` | `hold`, `clipped`: the loudest recent level, in dB |
| `chip` | `text`, `style`, `color` |
| `param` | `fraction` (0 to 1), `text` (the value), `bar` (the columns of the slider), `centred`, `steps` |
| `power` | `on`: a device's power chip |
| `band` | `off`: the heading of a group of rows, a band in the window and nothing in cells |

- `style` is how the terminal draws the role, `tone` is a color of the palette of the graphical window, by name, and `label` is the name of the role for a screen reader.
- The action of a hit region can be `keys` to type or `cmd` to run, in place of a gesture, and `hint` is what the status line shows for the region.
- A gesture that returns false gives the event to `on_mouse`.
- `paw.ui.roles` lists the roles with their props, and the mixer (`runtime/lua/paw/views/mixer.lua`) is made of roles.
- `view.live_roles` names the bound roles that change while the song plays, e.g., `{ "meter", "peak" }` in the mixer. If those are the only parts that change, and the graphical window paints them all, the window gets only the live values and no new scenes. The piano roll names `{ "playhead" }`, and the terminal also draws only these roles again while the song plays, not the whole view.
- A view with `still = true` shows nothing that changes while the song plays, e.g., the command line. A view with `live_part = true` is drawn again whole, as one part, e.g., the status line. A view with none of `live_roles`, `still` and `live_part` makes the terminal draw the whole screen for each frame while the song plays.
- The terminal draws a bound role again only when its value changes, so a playhead keeps its cells while the song is stopped. A role can also give `stamp(buf, props)`, a text of what its cells show for these props, and then the terminal draws it again only when the text changes. The meter of the arrange view uses it, because a falling level changes a cell only now and then. A `live_part` view can give `live_stamp(self, width)` in the same way, and the status line gives it from its components.
- A view can add values of its own to the live messages, because `view.live_values()` returns a table and each of its fields goes into the message under its name. The device panel sends `params`, the parameters that lanes move, for its `param` roles bound to `param:<device>:<key>`.
- `view:moving()` returns true while the view shows something else that moves, such as the gain reduction of a compressor, and the window then gets new scenes while the song plays. `view.redraw_every` is the time between the scenes, in milliseconds (30 by default, and 100 for the device panel).
- `view:scene_key()` returns a string that says what the drawing of the view in a window shows, other than what the live values move. While the song plays, the window gets a new scene of the view only when the key changes. Notation gives the system of the playhead, and the session view gives the cells that the slots that play fill. `view.scene_roles` names the roles that the window must paint, e.g., `{ "playhead" }`.
- A view that paints (`view:paint`) can put roles over its picture. When the context of the paint has `marks`, the view adds `{ role, x, y, w, h, props }` to it, in pixels, and Notation puts its playhead there, bound to `position`, with `segments`, which are the pieces of its systems as `{ from, to, x0, x1, top, bottom }`, in beats and pixels.
- A view whose title row has buttons of its own has `titled = true`, and a window then gives it no title of its own.
- A `button` with `menu` opens a menu (it shows a caret).

### Planes

A plane is a rectangle with a domain of its own on each axis, e.g., beats along and pitches up, or time down for a tracker. A mark in a plane has its place in the domain, not in cells.

- The terminal shows a mark on the cells that its edges round to.
- The graphical window paints the mark at its place, between cells.
- A press on the plane, or on a mark in it, comes with `e.at`, which is the place in the domain.

```lua
local roll = buf:plane(5, 2, buf.width - 5, 20, {
  key = "roll", hit = { kind = "grid" },                        -- its empty part is a hit region
  x = { domain = "beat", from = scroll, per = zoom },           -- `per` cells a beat, `from` at its left edge
  y = { domain = "pitch", from = top + 1, per = -1 },           -- a row a pitch, up
})
roll:mark("note", 1.5, 60, 0.5, 1, { label = "C4", style = "Title", color = "#e0a050", hit = { kind = "note", n = 1 } })
roll:hit(4, 60, 1, 1, { kind = "here" })
local x, y, w, h = roll:cells(1.5, 60, 0.5, 1)                  -- where the terminal shows it
```

The grid of the piano roll is a plane. Its notes are `note` roles on it,
with the props `label`, `style`, `color`, `velocity`, `selected`, `cursor`,
`pending` and `ghost`. Beside it are the roles `keyboard`, `playhead`
(bound to `position`) and `scrollbar`.

## Buffer types

A view is a buffer type with one buffer, and without `window_state` it shows in one window at a time. `paw.buftype` makes a type that has a buffer for each target, and any number of windows can show each buffer.

```lua
paw.buftype("notes", {
  create = function(target, buf) return { text = "notes on " .. target } end,  -- the state of the buffer
  render = function(win, canvas, ctx)        -- ctx.buf is the buffer, win.state the state of the window
    canvas:text(0, 0, ctx.buf.state.text, ctx.focused and "Title" or "Normal")
  end,
  on_key = function(win, key) end,           -- keys with no mapping
  on_mouse = function(win, event) end,
  title = function(buf) return "Notes" end,
  -- For `timebind`: the beat at the left edge, columns per beat, beats shown.
  time = { get = function(win) end, set = function(win, left, zoom) end },
  claims = function(name) end,               -- true when `:vs <name>` names one of its targets
  window = function() end,                   -- the window to draw when no tab has one (for a graphical frontend)
})
paw.keymap.set("x", function() end, { view = "notes" })   -- keys of its windows
```

`:vs notes://verse` then shows the buffer `notes://verse`.

A buffer type can do all that a view does, for each window. It can have a cursor that the keymap moves, and keys, motions, text objects and operators of its own, and it can give the text of `K` and its part of the status line. Counts, visual mode, operators, marks and `.` then work in its windows.

```lua
paw.buftype("tally", {
  create = function(target) return { marks = {} } end,
  render = function(win, canvas, ctx) canvas:text(0, 0, #ctx.buf.state.marks .. " marks") end,
  grid = function(win)                       -- the cursor of this window, as the grid of a view
    return { get = function() return 0, win.state.col or 0 end,
             set = function(_, col) win.state.col = math.max(0, col) end,
             step = function() return 1 end }
  end,
  keymaps = { ["<localleader>m"] = { function(ctx) table.insert(ctx.buf.state.marks, ctx.win.state.col) end, desc = "Mark" } },
  motions = { ["]t"] = function(ctx) ctx.win.state.col = (ctx.win.state.col or 0) + 4 end },
  textobjects = { it = function(ctx) return { kind = "char", r0 = 0, r1 = 0, c0 = ctx.win.state.col, c1 = ctx.win.state.col + 2 } end },
  operators = { ["g!"] = function(region, ctx) end },
  describe = function(win) return { only = true, title = "Tally", "at " .. (win.state.col or 0) } end,  -- K
  status = function(win, ctx) return "tally@" .. (win.state.col or 0) end,  -- the `view` component of the status line
  paint = function(win, g, ctx) end, pointer = function(win, e) end,          -- pixels, in the graphical window
})
```

`keymaps`, `motions`, `textobjects` and `operators` each map keys to one of these:

- A function, which gets `ctx.win` and `ctx.buf`.
- A command line.
- `{ fn, desc = ..., mode = ... }`, with the options of `paw.keymap.set`.

`paw.layout.powers(scope, def)` maps the same four tables for any scope of
keys.

### Buffers, windows and tabs

| Module | Functions |
| --- | --- |
| `paw.buf` | `list()`, `get(name)`, `create(type, target)`, `delete(name)`, `current()`, `of(win)` |
| `paw.win` | `current()`, `list()` (the windows of the tab on the screen, each with `id`, `view`, `opts`, `state`), `split({ vertical, view })`, `close(win)`, `only()`, `show(win, name)`, `enter(win)`, `resize(win, "height" or "width", n, relative)`, `equalize()`, `maximize()`, `option(win, name, value)` |
| `paw.tab` | `list()`, `current()`, `new(name, buffer)`, `go(i)`, `close(i)`, `move(i, to)` |
| `paw.layout` | `capture()` gives the tabs and windows as plain data. `restore(data)` makes them again |
| `paw.layouts` | `paw.layouts.name = {...}` names a layout for `:layout name` |

The events are `win.enter`, `win.leave`, `win.resized`, `buf.enter`,
`buf.leave`, `tab.enter` and `view.focused` (see [Events](events.md)).

A view keeps a window of its own size and time with `view:time_axis()` and `view:set_time_axis(left, zoom)`, as the arrange view and the piano roll do, and `ctx.follower` draws a window that follows another window.

## Text buffers

`paw.textbuf.kind` adds a list that you edit as text, as `paw://tracks` is (see "Lists edited as text" in [Lists edited as text](lists-edited-as-text.md)). First, the kind reads the project into items. Second, it writes each item as cells. Third, it reads a line back into fields. Fourth, it turns the differences into a plan.

The text core does the edits, the hidden ids, the comparison, the float that shows the plan, and the one undo step that applies the plan.

```lua
paw.textbuf.kind("clips", {
  pattern = "^paw://track/(%d+)/clips$",   -- the names it takes. The captures are ctx.args
  title = function(ctx) return "Clips of track " .. ctx.args[1] end,
  read = function(ctx)                      -- one item for each line, each with an id
    local out = {}
    for i, clip in ipairs(paw.api.clip_list(paw.api.track_list()[tonumber(ctx.args[1])])) do
      out[i] = { id = clip.id, clip = clip }
    end
    return out
  end,
  format = function(item)                   -- the cells, in columns two spaces apart
    return { paw.textbuf.quote(item.clip.name), "at " .. item.clip.start }
  end,
  parse = function(text)                    -- the fields of a line, or nil and the problem
    local cells = paw.textbuf.cells(text)
    local at = cells[2] and tonumber(cells[2].text:match("^at (%S+)$"))
    if not at then return nil, "a clip is a name and `at` a beat" end
    return { name = paw.textbuf.unquote(cells[1].text), start = at }
  end,
  plan = function(changes, ctx)             -- steps: { text, run(state) }, or an error
    local steps = {}
    for _, e in ipairs(changes.changed) do
      steps[#steps + 1] = { text = "move " .. e.fields.name .. " to " .. e.fields.start,
        run = function() paw.api.clip_set(e.id, "start", e.fields.start) end }
    end
    for _, d in ipairs(changes.deleted) do
      steps[#steps + 1] = { text = "delete " .. d.base.name, run = function() paw.api.clip_remove(d.id) end }
    end
    return steps
  end,
  keywords = { at = true },                 -- words drawn dim before a value. `if` skips them
  open = function(ctx, line, text) end,     -- Enter on a line
  parent = function(ctx) return "paw://tracks" end,  -- `-`
})
```

`:e paw://track/1/clips` then shows the list.

The fields of `changes`:

| Field | Each entry |
| --- | --- |
| `changed` | `id`, `fields`, `base` (the fields as read), `keys` (the fields that are different) |
| `deleted` | `id`, `base` |
| `copied` | `copy_of`, `fields` |
| `added` | `fields` |
| `lines` | every line that paw can read, in order, with `place` |
| `moves` | the lines that moved, with `from` and `place` |

The steps of a plan:

- The `run` of a step gets a table that all the steps share, and `state.made[line]` holds what an earlier step made for a line.
- `quiet = true` keeps a step off the list that paw shows.
- paw checks the plan before a step runs, and an error in `plan` stops the write, with its message.
- If a step fails, paw undoes the steps before it. A step that changes something outside the project puts a function on `state.undo` that reverses the change, and these functions run with the last first. The file manager uses this.

Other fields of a kind:

| Field | Effect |
| --- | --- |
| `readonly` | the message when you try a change, and the text cannot change, as in help |
| `gutter = false` | no line numbers |
| `static` | paw does not read it again when the project changes |
| `paint(canvas, x, y, text, kind, width, row, buf)` | draws a line |
| `keymaps`, `motions`, `textobjects`, `operators` | keys, as a buffer type has them. Their `ctx` has `buf`, `kind`, `args` and `target`. They are in the scope `textbuf.<kind>`, before the keys of the text |
| `describe(ctx)` | the text of `K` |
| `status(ctx, line)` | its part of the status line. `line` is what the status line gives the view (`paw.contracts.StatusContext`) |
| `keys` | the list for the key line |

`paw.textbuf.open(name, opts)` shows a buffer, with the options `here`, `vertical` and `window`. `paw.textbuf.buf()` is the current text buffer, and its `state.text.lines` are its lines, each `{ text, id }`.

The file manager is a kind of text buffer (`paw/views/files.lua`), with `paw.files.open(folder, { tree = true })` and `paw.files.sound_info(path)`. It uses `paw.api.fs_stat`, `fs_sound`, `fs_move`, `fs_copy`, `fs_trash` and the other `fs_` functions.

## The status line

`paw.statusline.setup` and `paw.statusline.component` change and add to the status line, a winbar and the tab line. See "The status line" in [The status line](status-line.md).

## The track column and the bar labels

`paw.trackcolumn` adds, changes and removes the parts of the column at
the left of the track headers: the numbers, the signs and the folds of
groups. `paw.ruler` does the same for the label of each bar on the ruler, and
for the lanes of rows under it, as the lane of regions.
See [The track column and the bar labels](trackcolumn.md).

## Help

The `README.md` of an extension, and each `doc/*.md` beside it, are pages of `:help`, also when the extension is not loaded.

- The title of the page has the name of the extension as its tag, and `doc/more.md` has the tag `name-more`.
- Each heading has the tag of the page and the words of the heading, so `## About` in the README of notation is `notation-about`.
- Each key, command (`:name.open`), option and Lua name in code has a tag where the page describes it, which is the first column of a table or the start of a list item.
- `<!-- tags: name-popovers name-hover -->` on a line of its own adds tags at its place, and GitHub does not show it.

| Function | Effect |
| --- | --- |
| `paw.help.add(path, { tag, ext, dir })` | adds a Markdown file to help |
| `paw.help.open(topic)` | opens help at a topic |
| `paw.help.find(topic, limit)` | the tags of a topic, best first |
| `paw.help.lookup(topic)` | where a topic is |
| `paw.help.grep(words)` | the lines that have the words, for `:helpgrep` |
| `paw.help.index()` | every page and tag |
| `paw.markdown.parse(text)`, `paw.markdown.render(blocks, { width })` | change Markdown into lines of text with styles, links and code |

The `help` field of a view names its topic for the bottom line.

## The pointer

`on_mouse` gets the pointer of the terminal in the cells of the view, with these fields.

| Field | Value |
| --- | --- |
| `kind` | `down`, `up`, `drag`, `move`, `scroll_up`, `scroll_down`, `scroll_left`, `scroll_right` |
| `button` | the button |
| `x`, `y` | the cell, from the corner of the view |
| `mods` | any of `C`, `A`, `S` |
| `double` | true on the second press of a double click |
| `view_x`, `view_y`, `w`, `h` | the place and the size of the view |

`paw.mouse.grab(event, { drag = fn, up = fn })` on a press sends the drags and the release to the view, wherever the pointer goes, and they have `dx` and `dy` from the press. `paw.mouse.hint(text)` shows on the status line what is under the pointer. See `runtime/lua/paw/mouse.tl`.

## Curves

`paw.curves` reads and writes every curve the same way, by its address, and the points are `{ beat, value, shape, tension }`, in beats of the project.

The addresses of curves are `paw://lane/9`, `paw://track/3/device/5/param/cutoff`, `paw://clip/7/control/cc/74`, `paw://clip/7/control/bend#key=60` and `paw://tempo`.

```lua
local c = paw.curves.target("paw://lane/9")    -- nil and the reason, for other addresses
c.points()   c.write(points)   c.format(-6)     -- "-6.0 dB"
c.lo, c.hi, c.min, c.max, c.step, c.has("smooth")
paw.curves.thin(points, 0.01, c.frac)   paw.curves.smooth(points, 2)   paw.curves.quantize(points, 0.25)
paw.curves.generate("sine", 0, 8, { rate = 1, depth = 0.5, unfrac = c.unfrac })
paw.curves.editor.open("paw://tempo", { vertical = true })
```

The curve editor is a buffer type named `curve` (see [The curve editor](curve-editor.md)).

`paw.curves.provide(name, fn)` adds curves for more addresses. `fn(uri, parts)` returns a target with the fields above (`points`, `write`, `name`, `format`, `lo`, `hi`, and others), or nil for an address that it does not know. The articulations extension shows several controllers as one curve this way (`paw://clip/7/control/cc/1#linked=dynamics`).

## Completion

`paw.complete` shows suggestions as ghost notes in the piano roll, and the suggestions come from sources that extensions register. "Writing a source" in [Completion](completion.md) describes the context and the items.

```lua
paw.complete.register({ name = "mine", priority = 10, views = { "pianoroll" }, auto = true,
  complete = function(ctx, done) done({ { label = "a fifth up", notes = { { pitch = ctx.pitch + 7, start = ctx.at, length = 1 } } } }) end })
paw.complete.request("manual")    paw.complete.current()    -- { items, index, item, clip } or nil
paw.complete.select(1)            paw.complete.select(3, true)   paw.complete.accept()   paw.complete.accept(true)  -- only the next notes
paw.complete.dismiss()            paw.complete.audition()   paw.complete.unregister("mine")
paw.complete.show(items, { keys = false })   -- ghost notes for a preview, from any module
paw.on("complete.changed", function(e) end)  -- e.shown
```

## Layers of the piano roll

A module draws over the grid of the piano roll in a layer, and the layers have a fixed order from back to front, as the table shows.

| Order | Layer |
| --- | --- |
| 10 | the notes of other tracks |
| 20 | the notes of the clip |
| 30 | diagnostics |
| 40 | an active snippet |
| 50 | suggestions |
| last | the cursor |

A layer draws with `paint(p)`, one time for both frontends.

- What a layer writes in cells shows in the graphical window as in the terminal, and when it draws after the notes, it is over them.
- What a layer marks on the plane of the roll (`p.plane:mark(role, beat, pitch, length, 1, props)`, e.g., a note) the graphical window paints at its place, between cells.
- A chip that does something is a hit region of kind `act`.
- Keys that apply while a state continues go in a scope of keys, before
  the keys of the piano roll.
- The row of tools of the roll takes switches.

```lua
local roll = paw.ui.views.pianoroll
roll.layer("lint", 30,
  function(p)                           -- p.roll, p.plane, p.x(beat), p.row(pitch) (nil off the screen), p.data, p.hue
    local row = p.row(60)
    if not row then return end
    local w = p.roll:text(p.x(4), row, "! parallel fifths", "Error")
    p.roll:hit(p.x(4), row, w, 1, { kind = "act", act = "my_fix", arg = 1, tip = "fix it" })   -- a chip to click
  end)
roll:key_scope("pianoroll.lint", 30, function() return showing end)   -- then map keys in the view "pianoroll.lint"
roll:tool("lint", function() return { label = "Lint", on = enabled, act = "toggle_lint", tip = "..." } end)
paw.ui.keybar.set("pianoroll.lint", "n", { { "<C-y>", "fix" } })     -- the key line while the scope is on
```

- `p` also has `ruler`, `clip`, `parts` (every clip that the roll edits), `scroll`, `from` and `to` (the beats that show), `zoom`, `top`, `rows`, `width` and `focused`, and beats are the beats of the active clip.
- The `act` of a chip names a function of `paw.frontend.act`, which paw calls with the clip and `arg`, and `tip` is what the pointer over the chip shows.
- A scope of keys that maps `<Esc>` gets the key before paw leaves insert or visual mode.
- paw does not draw a layer that fails, and it draws the other layers.

`paw.roll_clips.parts()` and `paw.roll_clips.open(ids, active)` give and set the clips that the piano roll edits (see [Several clips in the piano roll](roll-clips.md)).

### Hooks for an instrument

Four more hooks tell the piano roll about an instrument whose keys are not only pitches (keyswitches, a range that it plays). Each hook has a name, and nil removes it.

```lua
roll.rows("mine", function(pitch, track)       -- the edge of the keyboard and the shade of the row
  if pitch < 55 then return { shade = "RollOutside" } end
  if pitch == 24 then return { label = "sus", style = "PianoC" } end
end)
roll.band("mine", 10, {                         -- a row of its own above the ruler
  title = "art", active = function(clip) return true end,
  paint = function(buf, b) buf:text(b.x(0), 0, "│sus") end,   -- b.x(beat), b.from, b.to, b.width, b.clip
})
roll.describer("mine", function(note, part) return { "  played as  sustain" } end)   -- lines that K adds for a note
-- With `articulation = true` in the table, the lines give the articulation of the note, and K does not
roll.entering("mine", function(note, clip) note.velocity = 90 end)   -- a note that keys, insert mode or a click add
```

The articulations extension uses all four.

## Layers of other views, and locators

| Function | Draws on |
| --- | --- |
| `paw.ui.views.pianoroll.layer(name, order, paint)` | the piano roll, in order. Below 20 is under the notes of the clip. `paint(p)` gets the cells of the roll and the ruler, the clip, `p.x(beat)` and `p.row(pitch)` |
| `paw.ui.views.arrange.layers[name] = function(view, layer)` | the timeline and its ruler |
| `paw.ui.layer(view, part, name, order, paint)` | a part of a view, where the view calls `paw.ui.paint(view, part, ctx)`: the `header` and `clip` of the arrange view, the `strip` and `strip_foot` of the mixer, the `device` and `param` of the device panel |

`paw.ui.locator(view, { at, position, place, go })` tells how a view
places locations:

| Field | Value |
| --- | --- |
| `at` | the location under the cursor |
| `position` | where the cursor is |
| `place` | where a location is in the view |
| `go` | moves the cursor to a location |

`paw.ui.location()` and `paw.ui.go(location)` use the locators.
`paw.ui.location(view, win)` gives the location under the cursor of the window `win`, because each window of a view has its own cursor. `paw.ui.go` goes first to a window that already shows the location.
