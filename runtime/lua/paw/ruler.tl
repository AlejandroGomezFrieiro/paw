-- The labels of the bars on the arrange view's ruler, made of parts as the
-- track column is (paw/trackcolumn.tl). The part that comes with paw is
-- `number`: each bar's number, or with `paw.opt.relativebar` how many `W`
-- or `B` reach it, the cursor's bar keeping its own number, as Neovim's
-- 'relativenumber' does for lines. So `4W` lands on the bar marked 4.
--
-- An extension adds a part after the number of each bar, in its `order`:
--
--   paw.ruler.add("odd", {
--     order = 20,
--     render = function(bar, ctx) if bar % 2 == 1 then return { { "·", "RulerTick" } } end end,
--   })
--
-- `paw.opt.barlabel` names the parts shown. The arrange view draws the
-- labels in cells, so the terminal and the window show the same ruler.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local registry = require("paw.registry")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type DrawModule = require("paw.draw")
local type TempoModule = require("paw.tempo")
local type objects = require("paw.objects")
local type FoldsModule = require("paw.folds")

local type Label = contracts.RulerLabel
local type Context = contracts.RulerContext
local type Cells = contracts.ColumnCells
local type Piece = contracts.Piece

--- paw/scope.tl, the part of it that this module reads: how many bars of
--- the song come before a scope's bar 1, and the time of the scope.
local record Scope
  bar_offset: function(): integer
  span: function(): number, number
end
local record Paw is partial.Paw
  scope: Scope
  draw: DrawModule
  tempo: TempoModule
  time: objects.Time
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

local record M
  --- The parts of the bar labels by name, with the extension that added
  --- or changed each one (`add`, `set`).
  labels: registry.Registry<Label>
  lanes: {string: contracts.RulerLane}
end
--- Take the name of a part that went out of `paw.opt.barlabel`.
local function unshow(name: string)
  local list: {string} = {}
  for _, n in ipairs(opt.barlabel as {string}) do
    if n ~= name then
      list[#list + 1] = n
    end
  end
  opt.barlabel = list
end

-- A change draws the labels again. A part that goes with no part below it
-- leaves `paw.opt.barlabel`, and a part that an extension changed with
-- `set` comes back as it was.
M.labels = registry.new(
  "barlabel",
  "parts of the bar labels",
  {
    changed = function(name: string, spec: Label)
      if not spec then
        unshow(name)
      end
      api.ui_redraw()
    end,
  }
)

local function has(list: {string}, value: string): boolean
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

--- Add a part of the bar labels, or put a new one in place of one of that
--- name. It goes into `paw.opt.barlabel` (unless `hidden`).
function M.add(name: string, spec: Label): Label
  assert(
    type(name) == "string" and type(spec) == "table" and type(spec.render) == "function",
    "usage: paw.ruler.add(name, { order = 50, render = function(bar, ctx) ... end })"
  )
  spec.name = name
  spec.order = spec.order or 50
  M.labels:put(name, spec)
  local shown = opt.barlabel as {string}
  if not spec.hidden and not has(shown, name) then
    local list: {string} = {}
    for i, n in ipairs(shown) do
      list[i] = n
    end
    list[#list + 1] = name
    opt.barlabel = list
  end
  return spec
end

--- Take a part away, and its name out of `paw.opt.barlabel`. The part
--- that it replaced, if any, comes back.
function M.remove(name: string)
  if not M.labels:remove(name) then
    unshow(name)
  end
end

--- How many `W` (ahead) or `B` (behind) reach bar `bar` from the cursor
--- at `beat`: from inside a bar, the first `B` goes to its own start
--- (paw/defaults/cursor.lua). Nil for the cursor's own bar.
function M.relative(bar: integer, beat: number): integer
  local at = paw.time.bar_of(beat)
  if bar > at then
    return bar - at
  end
  if bar == at then
    return nil
  end
  return at - bar + (paw.tempo.is_bar_line(beat) and 0 or 1)
end

--- Change a part that is there, the built-in `number` too: its `order`,
--- `render`, and the `glyphs` and `styles` it draws with (merged into its
--- own). The part becomes a changed copy, as with `paw.trackcolumn.set`:
--- `paw.ruler.add(name, old)` puts back the table it had before.
---   paw.ruler.set("number", { styles = { cursor = "Title" } })
function M.set(name: string, patch: contracts.RulerPatch): Label
  local l = M.labels:get(name)
  if not l then
    error("no bar label part `" .. tostring(name) .. "`", 2)
  end
  local copy: Label = {
    name = l.name,
    order = patch.order or l.order,
    render = patch.render or l.render,
    hidden = l.hidden,
    ext = paw.ext.caller(),
  }
  for _, field in ipairs({"glyphs", "styles"}) do
    local own: {string: string} = {}
    for k, v in pairs((l as {string: {string: string}})[field] or {}) do
      own[k] = v
    end
    for k, v in pairs((patch as {string: {string: string}})[field] or {}) do
      own[k] = v
    end
    (copy as {string: {string: string}})[field] = own
  end
  M.labels:put(name, copy)
  return copy
end

-- Lanes under the bar numbers ------------------------------------------------------
--
-- Under the row of bar numbers, the ruler has lanes of rows: the regions'
-- lane (paw/markers.tl) is one, a row for each level of the tree of
-- regions. An extension adds a lane, or changes one, as it does a part of
-- the bar labels:
--
--   paw.ruler.set_lane("regions", { styles = { level1 = "Title" } })

M.lanes = {}

--- Add a lane of rows under the bar numbers, or put a new one in place of
--- one of that name.
function M.add_lane(name: string, spec: contracts.RulerLane): contracts.RulerLane
  assert(
    type(name) == "string"
      and type(spec) == "table"
      and type(spec.render) == "function"
      and type(spec.rows) == "function",
    "usage: paw.ruler.add_lane(name, { order = 50, rows = function(ctx) ... end, render = function(ctx) ... end })"
  )
  spec.name = name
  spec.order = spec.order or 50
  spec.glyphs, spec.styles = spec.glyphs or {}, spec.styles or {}
  M.lanes[name] = spec
  api.ui_redraw()
  return spec
end

--- Take a lane away.
function M.remove_lane(name: string)
  M.lanes[name] = nil
  api.ui_redraw()
end

--- Change a lane that is there, the built-in `regions` too: its `order`,
--- `rows`, `render`, and the `glyphs` and `styles` it draws with (merged
--- into its own). The lane becomes a changed copy: `paw.ruler.add_lane(name,
--- old)` puts back the table it had before.
function M.set_lane(name: string, patch: contracts.RulerLanePatch): contracts.RulerLane
  local l = M.lanes[name]
  if not l then
    error("no ruler lane `" .. tostring(name) .. "`", 2)
  end
  local copy: contracts.RulerLane = {
    name = l.name,
    order = patch.order or l.order,
    rows = patch.rows or l.rows,
    render = patch.render or l.render,
    ext = paw.ext.caller(),
  }
  for _, field in ipairs({"glyphs", "styles"}) do
    local own: {string: string} = {}
    for k, v in pairs((l as {string: {string: string}})[field] or {}) do
      own[k] = v
    end
    for k, v in pairs((patch as {string: {string: string}})[field] or {}) do
      own[k] = v
    end
    (copy as {string: {string: string}})[field] = own
  end
  M.lanes[name] = copy
  api.ui_redraw()
  return copy
end

local function lanes_in_order(): {contracts.RulerLane}
  local list: {contracts.RulerLane} = {}
  for _, l in pairs(M.lanes) do
    list[#list + 1] = l
  end
  table.sort(
    list,
    function(a: contracts.RulerLane, b: contracts.RulerLane): boolean
      if a.order ~= b.order then
        return a.order < b.order
      end
      return a.name < b.name
    end
  )
  return list
end

--- A context of a lane with only its fields of time: `here`, the beat of
--- the window's time for a beat of the song, and `from` and `to`, the
--- time of the window's scope. The regions' lane places the song's regions
--- and markers with these fields, and the mouse finds them with the same
--- fields.
function M.lane_time(): contracts.RulerLaneContext
  local ctx: contracts.RulerLaneContext = {here = paw.time.local_beat}
  if paw.scope then
    ctx.from, ctx.to = paw.scope.span()
  end
  return ctx
end

local function lane_ctx(l: contracts.RulerLane): contracts.RulerLaneContext
  local ctx = M.lane_time()
  ctx.glyphs, ctx.styles = l.glyphs or {}, l.styles or {}
  return ctx
end

--- How many rows the lanes need now, all together.
function M.lane_rows(): integer
  local n = 0
  for _, l in ipairs(lanes_in_order()) do
    local ok, rows = pcall(l.rows, lane_ctx(l))
    if ok and math.type(rows) == "integer" and rows > 0 then
      n = n + rows
    end
  end
  return n
end

--- Draw the lanes on `buf`, the rows under the bar numbers, one under the
--- other. `x` is the column of a beat; `scroll` and `span` the beats in
--- sight; `folds` the view's closed time folds (paw/folds.tl), if any.
function M.draw_lanes(
  buf: contracts.Buf, x: function(beat: number): integer, scroll: number, span: number, folds?: {FoldsModule.TimeSpan}
)
  folds = folds or {}
  local function folded(beat: number): boolean
    for _, s in ipairs(folds) do
      if beat > s.from + 1e-9 and beat < s.to - 1e-9 then
        return true
      end
    end
    return false
  end
  local function closed(id: integer): boolean
    for _, s in ipairs(folds) do
      if s.fold.kind == "region" and s.fold.id == id then
        return true
      end
    end
    return false
  end
  local y = 0
  for _, l in ipairs(lanes_in_order()) do
    local ctx = lane_ctx(l)
    local ok, rows = pcall(l.rows, ctx)
    if ok and math.type(rows) == "integer" and rows > 0 then
      ctx.buf, ctx.rows, ctx.x, ctx.scroll, ctx.span = buf:sub(0, y, buf.width, rows), rows, x, scroll, span
      ctx.folded, ctx.closed = folded, closed
      local drawn, err = pcall(l.render, ctx) as (boolean, string)
      if not drawn then
        buf:text(0, y, tostring(l.name) .. ": " .. tostring(err), "Error")
      end
      y = y + rows
    end
  end
end

-- Styles, by name: `cursor` (the cursor's bar, with `relativebar`) and
-- `relative` (the counts); a bar's number in the loop or the punch range
-- keeps their colors.
M.add(
  "number",
  {
    order = 10,
    glyphs = {},
    styles = {},
    render = function(bar: integer, ctx: Context): Cells
      if ctx.cursor and opt.relativebar then
        return {{tostring(bar), ctx.styles.cursor or "RulerBarCursor"}}
      end
      if ctx.relative then
        return {
          {tostring(ctx.relative), ctx.style == "RulerBar" and (ctx.styles.relative or "RulerBarRelative") or ctx.style}
        }
      end
      return {{tostring(bar), ctx.style}}
    end,
  }
)

--- The first and the last bar that a stretch of time (`from` up to `to`, in
--- beats of the song) touches, numbered as the ruler numbers them: in a scope
--- with time, from its own bar 1. The status line and the messages of the
--- loop use it.
function M.bars_of(from: number, to: number): integer, integer
  local offset = paw.scope.bar_offset()
  local here = paw.time.local_beat
  local first = paw.time.bar_of(here(from)) - offset
  local last = math.max(first, paw.time.bar_of(here(math.max(from, to - 1e-6))) - offset)
  return first, last
end

--- What a message says of the loop: `bars 5 to 8, on`, `bar 5, off`.
--- `from` and `to` are the loop's edges in beats of the song.
function M.loop_text(from: number, to: number, on: boolean): string
  local first, last = M.bars_of(from, to)
  local bars = first == last and ("bar " .. first) or ("bars " .. first .. " to " .. last)
  return bars .. ", " .. (on and "on" or "off")
end

--- The pieces of bar `bar`'s label, from the parts in `paw.opt.barlabel`
--- in their order. `bar` is the song's bar: in a scope with time, its
--- label counts from 1 at the scope's start (`paw.scope.bar_offset`).
--- `style` is the style of the bar's number there.
--- `room` is how many columns the label has before the next bar's: each
--- part gets what the parts before it left (`ctx.room`).
function M.label(bar: integer, beat: number, style: string, cursor_beat: number, room?: integer): {Piece}
  local list: {Label} = {}
  for _, name in ipairs(opt.barlabel as {string}) do
    local l = M.labels:get(name)
    if l then
      list[#list + 1] = l
    end
  end
  table.sort(
    list,
    function(a: Label, b: Label): boolean
      if a.order ~= b.order then
        return a.order < b.order
      end
      return a.name < b.name
    end
  )
  local song_bar = bar
  bar = bar - (paw.scope and paw.scope.bar_offset() or 0)
  local ctx: Context = {
    bar = bar,
    song_bar = song_bar,
    beat = beat,
    style = style,
    g = paw.draw.g,
    cursor = paw.time.bar_of(cursor_beat) == song_bar,
    relative = opt.relativebar and M.relative(song_bar, cursor_beat) or nil,
  }
  local left: integer = room or 1000
  local out: {Piece} = {}
  local function put(text: string, group: string)
    out[#out + 1] = {text, group}
    left = left - api.str_width(text)
  end
  for _, l in ipairs(list) do
    ctx.glyphs, ctx.styles, ctx.room = l.glyphs or {}, l.styles or {}, math.max(0, left)
    local ok, cells = pcall(l.render, bar, ctx)
    if not ok then
      put("!", "Error")
    elseif cells is string then
      put(cells, style)
    elseif cells is {Piece} then
      for _, piece in ipairs(cells) do
        put(piece[1], piece[2] or style)
      end
    end
  end
  return out
end

return M
