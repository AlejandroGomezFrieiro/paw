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
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type DrawModule = require("paw.draw")
local type TempoModule = require("paw.tempo")
local type objects = require("paw.objects")

local type Label = contracts.RulerLabel
local type Context = contracts.RulerContext
local type Cells = contracts.ColumnCells
local type Piece = contracts.Piece

--- paw/scope.tl, the part of it that this module reads: how many bars of
--- the song come before a scope's bar 1.
local record Scope
  bar_offset: function(): integer
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
  labels: {string: Label}
end
M.labels = {}

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
  M.labels[name] = spec
  local shown = opt.barlabel as {string}
  if not spec.hidden and not has(shown, name) then
    local list: {string} = {}
    for i, n in ipairs(shown) do
      list[i] = n
    end
    list[#list + 1] = name
    opt.barlabel = list
  end
  api.ui_redraw()
  return spec
end

--- Take a part away, and its name out of `paw.opt.barlabel`.
function M.remove(name: string)
  M.labels[name] = nil
  local list: {string} = {}
  for _, n in ipairs(opt.barlabel as {string}) do
    if n ~= name then
      list[#list + 1] = n
    end
  end
  opt.barlabel = list
  api.ui_redraw()
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
  local l = M.labels[name]
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
  M.labels[name] = copy
  api.ui_redraw()
  return copy
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

--- The pieces of bar `bar`'s label, from the parts in `paw.opt.barlabel`
--- in their order. `bar` is the song's bar: in a scope with time, its
--- label counts from 1 at the scope's start (`paw.scope.bar_offset`).
--- `style` is the style of the bar's number there.
--- `room` is how many columns the label has before the next bar's: each
--- part gets what the parts before it left (`ctx.room`).
function M.label(bar: integer, beat: number, style: string, cursor_beat: number, room?: integer): {Piece}
  local list: {Label} = {}
  for _, name in ipairs(opt.barlabel as {string}) do
    local l = M.labels[name]
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
