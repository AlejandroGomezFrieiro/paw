-- The ruler of the time views: rows that the user puts in order, and marks
-- in namespaces, as Neovim's 'statuscolumn' and extmarks are. One
-- compositor turns each mark's time into a column.
--
-- A row (`paw.ruler.row`) is a named line of the ruler. paw has the rows
-- `bars`, `beats` (drawn over the bars), `regions` and `tempo` (the tempo
-- lane). `paw.opt.rulerrows` names the rows shown, in their order.
--
-- A mark (paw/marks.tl) is in the namespace of its owner, and goes to a row
-- (`row:name`) or over one (`over:name`). `paw.ruler.route` moves the marks
-- of a namespace, and `paw.ruler.set` changes the glyphs, the styles and the
-- priority of a row or a namespace.
--
-- The rules of the compositor:
--
-- - A sign is in the column that the time axis gives its time
--   (`axis:x_of`). A column of a line has one sign: the sign of the
--   highest priority.
-- - The labels of one column follow the sign, joined in the order of
--   their priority. A label never covers a hard sign, of any priority. It
--   covers a soft sign (a beat tick, an edge of the loop) of a lower
--   priority. It never covers the label of a higher priority, and keeps
--   one free cell before it, but it can end in the cell just before a
--   sign. A name gets shorter with `…`; a whole label (a number) is shown
--   whole or not at all.
-- - A mark with `to` colors the background of its stretch.
-- - `K` lists all the marks of a column, also those that are not shown.
--
-- The arrange view calls `places` for its layout, then `compose` and `paint`
-- for each frame, and keeps the composition for the pointer and `K`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local registry = require("paw.registry")
local marks = require("paw.marks")
local util = require("paw.util")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type TempoModule = require("paw.tempo")
local type objects = require("paw.objects")
local type FoldsModule = require("paw.folds")
local type CursorModule = require("paw.cursor")

local type Row = contracts.RulerRow
local type Mark = contracts.RulerMark
local type Context = contracts.RulerContext
local type Namespace = contracts.RulerNamespace

--- paw/scope.tl, the part of it that this module reads: how many bars of
--- the song come before a scope's bar 1, and the time of the scope.
local record Scope
  bar_offset: function(): integer
  span: function(): number, number
end
local record Paw is partial.Paw
  scope: Scope
  tempo: TempoModule
  time: objects.Time
  folds: FoldsModule
  cursor: CursorModule
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

local record M
  --- The rows of the ruler by name, with the extension that added or
  --- changed each one (`row`, `set`).
  rows: registry.Registry<Row>
  --- Where the user sent the marks of a namespace (`route`), by its name.
  routes: {string: string}

  --- The lines of a row on the ruler: its first line from the top of the
  --- ruler (`y`) and how many (`h`).
  record Place
    row: Row
    y: integer
    h: integer
  end

  --- A mark as the compositor placed it, shown or not: the row and the
  --- line of the ruler it is on, the column of its time (`x`), and the
  --- cells that its sign and its label take (`x0` up to `x1`; for a
  --- stretch of time, its cells). `top` is true for the mark whose sign
  --- the column shows. `sign` is false when its sign does not show: in
  --- the column, or before its label (`inline`) when another sign has the
  --- column. `label` is the text shown (nil when none is shown).
  record Placed
    mark: Mark
    row: string
    y: integer
    x: integer
    x0: integer
    x1: integer
    top: boolean
    sign: boolean
    inline: boolean
    label: string
  end

  --- A frame of the ruler: the rows' places, each mark in sight, the
  --- width in columns, the context of time it was made in, and the
  --- errors of the rows and the namespaces that failed.
  record Composition
    places: {Place}
    placed: {Placed}
    width: integer
    ctx: Context
    errors: {string}
  end
end

M.routes = {}

local function has(list: {string}, value: string): boolean
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

--- Take a row's name out of `paw.opt.rulerrows`.
local function unshow(name: string)
  local list: {string} = {}
  for _, n in ipairs(opt.rulerrows as {string}) do
    if n ~= name then
      list[#list + 1] = n
    end
  end
  opt.rulerrows = list
end

-- A change draws the ruler again. A row that goes with no row below it
-- leaves `paw.opt.rulerrows`, and a row that an extension changed with
-- `set` comes back as it was.
M.rows = registry.new(
  "rulerrows",
  "rows of the ruler",
  {
    changed = function(name: string, spec: Row)
      if not spec then
        unshow(name)
      end
      api.ui_redraw()
    end,
  }
)

--- Add a row to the ruler, or put a new one in place of the row of that
--- name. Unless it is `hidden` or there already, its name goes into
--- `paw.opt.rulerrows` after the row `after` (else at the end).
---   paw.ruler.row("chords", { after = "bars", marks = function(ctx) return {} end })
function M.row(name: string, spec: Row): Row
  assert(
    type(name) == "string" and type(spec) == "table", "usage: paw.ruler.row(name, { marks = function(ctx) ... end })"
  )
  spec.name = name
  spec.priority = spec.priority or 10
  spec.glyphs, spec.styles = spec.glyphs or {}, spec.styles or {}
  M.rows:put(name, spec)
  local shown = opt.rulerrows as {string}
  if not spec.hidden and not has(shown, name) then
    local list: {string} = {}
    local put = false
    for _, n in ipairs(shown) do
      list[#list + 1] = n
      if n == spec.after then
        list[#list + 1], put = name, true
      end
    end
    if not put then
      list[#list + 1] = name
    end
    opt.rulerrows = list
  end
  return spec
end

--- Take a row away, and its name out of `paw.opt.rulerrows`. The row that
--- it replaced, if any, comes back.
function M.remove(name: string)
  if not M.rows:remove(name) then
    unshow(name)
  end
end

--- Send the marks of a namespace (its id or name) to a row: `"row:name"`
--- gives them a line of that row, `"over:name"` draws them on it. Nil
--- gives back the namespace's own place.
---   paw.ruler.route("paw.cues", "over:bars")
function M.route(ns: integer | string, where?: string)
  local space = marks.of(ns)
  if where ~= nil and not (where is string and (where:match("^row:.") or where:match("^over:."))) then
    error("a route is \"row:<row>\" or \"over:<row>\", not " .. tostring(where), 2)
  end
  M.routes[space.name] = where
  api.ui_redraw()
end

--- Merge the `glyphs` and the `styles` of `patch` into a copy of `own`'s.
local function merged(own: {string: string}, patch: {string: string}): {string: string}
  local out: {string: string} = {}
  for k, v in pairs(own or {}) do
    out[k] = v
  end
  for k, v in pairs(patch or {}) do
    out[k] = v
  end
  return out
end

--- Change a row or a namespace that is there, paw's own too: the
--- `priority` of its marks and the `glyphs` and `styles` it draws with
--- (merged into its own). A row is found first, then a namespace. It
--- becomes a changed copy, so the unload of the extension that changed it
--- puts back the one before.
---   paw.ruler.set("bars", { styles = { cursor = "Title" } })
---   paw.ruler.set("paw.meter", { glyphs = { sign = "M" } })
function M.set(name: string, patch: contracts.RulerPatch)
  local r = M.rows:get(name)
  if r then
    local copy: Row = {
      name = r.name,
      marks = r.marks,
      height = r.height,
      draw = r.draw,
      over = r.over,
      after = r.after,
      hidden = r.hidden,
      priority = patch.priority or r.priority,
      glyphs = merged(r.glyphs, patch.glyphs),
      styles = merged(r.styles, patch.styles),
      ext = paw.ext.caller(),
    }
    M.rows:put(name, copy)
    return
  end
  local ns = marks.namespaces:get(name)
  if not ns then
    error("no ruler row or namespace of marks `" .. tostring(name) .. "`", 2)
  end
  -- The copy keeps the marks of the namespace: they are one table.
  local copy: Namespace = {
    name = ns.name,
    id = ns.id,
    route = ns.route,
    source = ns.source,
    marks = ns.marks,
    priority = patch.priority or ns.priority,
    glyphs = merged(ns.glyphs, patch.glyphs),
    styles = merged(ns.styles, patch.styles),
    ext = paw.ext.caller(),
  }
  marks.namespaces:put(name, copy)
end

-- Time --------------------------------------------------------------------------------

--- The context of the time of the current window, with no axis yet: `here`
--- and the time of its scope (`from`, `to`), the folds of its time and
--- the cursor's beat. Rows and namespaces get it with their own glyphs
--- and styles.
function M.time(): Context
  local ctx: Context = {here = paw.time.local_beat, cursor = paw.cursor.beat}
  if paw.scope then
    ctx.from, ctx.to = paw.scope.span()
  end
  ctx.folded = function(_: number): boolean return false end
  ctx.closed = function(_: integer): boolean return false end
  return ctx
end

--- `ctx` with the glyphs and styles of a row or a namespace.
local function own(ctx: Context, glyphs: {string: string}, styles: {string: string}): Context
  return {
    here = ctx.here,
    from = ctx.from,
    to = ctx.to,
    left = ctx.left,
    right = ctx.right,
    axis = ctx.axis,
    folded = ctx.folded,
    closed = ctx.closed,
    cursor = ctx.cursor,
    glyphs = glyphs or {},
    styles = styles or {},
  }
end

--- Where a mark of a namespace goes: the user's route of the namespace,
--- else the mark's own `row` or `over`, else the namespace's route. Gives
--- "row" or "over", and the name of the row.
local function target_of(ns: Namespace, m: Mark): string, string
  local where = M.routes[ns.name]
  if not where and m.row then
    return "row", m.row
  elseif not where and m.over then
    return "over", m.over
  end
  local how, row = (where or ns.route or "over:bars"):match("^(%a+):(.+)$")
  return how, row
end

--- The marks of a namespace for `ctx`, in beats of the window: what its
--- source computes (unless `kept_only`), and the marks that
--- `paw.marks.set` put, from beats of the song, in the time in sight
--- (`ctx.left` to `ctx.right`). A mark outside the time of the window's
--- scope is not there, and a stretch is cut at its edges.
--- Gives the error of the source too, if it fails.
local function namespace_marks(ns: Namespace, ctx: Context, kept_only?: boolean): {Mark}, string
  local out: {Mark} = {}
  local c = own(ctx, ns.glyphs, ns.styles)
  local err: string
  if ns.source and not kept_only then
    local ok, list = pcall(ns.source, c) as (boolean, {Mark} | string)
    if ok and list is {Mark} then
      for _, m in ipairs(list) do
        m.ns = m.ns or ns.name
        out[#out + 1] = m
      end
    elseif not ok then
      err = ns.name .. ": " .. tostring(list)
    end
  end
  for _, m in ipairs(marks.within(ns.name, ctx.left or -math.huge, ctx.right or math.huge, ctx.here)) do
    local a = ctx.here(m.beat)
    local b = m.to and ctx.here(m.to) or nil
    local inside = true
    if ctx.from then
      if b then
        inside = b > ctx.from + 1e-9 and a < ctx.to - 1e-9
        a, b = math.max(a, ctx.from), math.min(b, ctx.to)
      else
        inside = a >= ctx.from - 1e-9 and a < ctx.to - 1e-9
      end
    end
    if inside then
      local placed = marks.copy(m)
      placed.beat, placed.to = a, b
      out[#out + 1] = placed
    end
  end
  return out, err
end

--- The rows of `paw.opt.rulerrows` that exist, each once, in order.
local function shown_rows(): {Row}
  local out: {Row} = {}
  local seen: {string: boolean} = {}
  for _, name in ipairs(opt.rulerrows as {string}) do
    local r = M.rows:get(name)
    if r and not seen[name] then
      seen[name] = true
      out[#out + 1] = r
    end
  end
  return out
end

--- The places of the rows shown, from the top of the ruler: a row with
--- `over` has none, and a row of no lines now is left out. A row takes
--- what its `height` gives (one line when it has none), and at least a
--- line for each line of the marks of a namespace sent to it with
--- `row:name`. `ctx` is the time of the window (`paw.ruler.time()`), with
--- the time in sight as `left` and `right`, when it is known.
--- Gives the places and the number of lines.
function M.places(ctx: Context): {M.Place}, integer
  -- The lines that the namespaces sent to a row need there: all the
  -- marks of a namespace sent to a row, in the time in sight, and the
  -- kept marks that name a row themselves.
  local wanted: {string: integer} = {}
  local seen = own(ctx, nil, nil)
  seen.left, seen.right = ctx.left or ctx.from, ctx.right or ctx.to
  for _, ns in pairs(marks.namespaces:entries()) do
    local sent = (M.routes[ns.name] or ns.route or ""):match("^(%a+):")
    for _, m in ipairs((namespace_marks(ns, seen, sent ~= "row"))) do
      local how, target = target_of(ns, m)
      if how == "row" then
        wanted[target] = math.max(wanted[target] or 0, (m.line or 0) + 1)
      end
    end
  end
  local out: {M.Place} = {}
  local y = 0
  for _, r in ipairs(shown_rows()) do
    if not r.over then
      local h = 1
      if r.height then
        local ok, n = pcall(r.height, own(ctx, r.glyphs, r.styles)) as (boolean, integer)
        h = ok and math.type(n) == "integer" and n or 0
      end
      h = math.max(h, wanted[r.name] or 0)
      if h > 0 then
        out[#out + 1] = {row = r, y = y, h = h}
        y = y + h
      end
    end
  end
  return out, y
end

-- The compositor ------------------------------------------------------------------------

--- A label that one column shows: its text, style and priority, and the placed
--- mark whose cells it takes.
local record Piece
  text: string
  style: string
  priority: integer
  whole: boolean
  placed: M.Placed
end

--- The marks of one column of a line: the placed marks, the one whose sign
--- shows (`top`), and the highest priority of them.
local record Group
  x: integer
  y: integer
  list: {M.Placed}
  top: M.Placed
  priority: integer
end

local function by_priority(a: M.Placed, b: M.Placed): boolean
  local pa, pb = a.mark.priority or 0, b.mark.priority or 0
  if pa ~= pb then
    return pa > pb
  end
  if (a.mark.ns or "") ~= (b.mark.ns or "") then
    return (a.mark.ns or "") < (b.mark.ns or "")
  end
  return (a.mark.id or 0) < (b.mark.id or 0)
end

--- The cells of one line: what took each cell (a label, its free cell
--- after it, a fold or the end of the scope: `taken`), and the signs that
--- each column shows with their priority (`signs`).
local record Cells
  taken: {integer: boolean}
  signs: {integer: M.Placed}
end

--- Place the marks of one line: the signs first, then the labels of each
--- column, in the order of priority (the higher first), each in the room
--- that the others left. `width` is the width of the ruler, `blocked(x)`
--- true for a cell that no label takes (a fold, after the scope's end).
local function place_line(list: {M.Placed}, width: integer, blocked: function(x: integer): boolean)
  local cells: Cells = {taken = {}, signs = {}}
  local groups: {integer: Group} = {}
  local order: {Group} = {}
  table.sort(list, by_priority)
  for _, p in ipairs(list) do
    local x = p.x
    local g = groups[x]
    if not g then
      g = {x = x, y = p.y, list = {}, priority = p.mark.priority or 0}
      groups[x], order[#order + 1] = g, g
    end
    g.list[#g.list + 1] = p
    if p.mark.sign and not g.top then
      g.top, cells.signs[x], p.top = p, p, true
    elseif p.mark.sign then
      -- Another sign has the column: this one shows only before its label.
      p.sign = false
    end
  end
  table.sort(
    order,
    function(a: Group, b: Group): boolean
      if a.priority ~= b.priority then
        return a.priority > b.priority
      end
      return a.x < b.x
    end
  )
  --- Whether a label of `priority` may cover the signs of column `x`:
  --- each is soft and of a lower priority.
  local function coverable(x: integer, priority: integer): boolean
    local there = groups[x]
    for _, p in ipairs(there and there.list or {}) do
      if p.mark.sign and not (p.mark.soft and (p.mark.priority or 0) < priority) then
        return false
      end
    end
    return true
  end
  --- Hide the signs of column `x`, which a label covers.
  local function cover(x: integer)
    local there = groups[x]
    for _, p in ipairs(there and there.list or {}) do
      p.sign = false
    end
    cells.signs[x] = nil
  end
  local function free(x: integer, home: integer, priority: integer): boolean
    if x >= width or cells.taken[x] or blocked(x) then
      return false
    end
    return x == home or coverable(x, priority)
  end
  for _, g in ipairs(order) do
    local x = g.x
    local top = g.top
    if top and cells.taken[x] then
      -- A label of a higher priority took the column: no sign, no label.
      top.sign = false
      cells.signs[x] = nil
    elseif not top and (cells.taken[x] or blocked(x)) then
      -- A column with no sign: its labels start in it, or not at all.
    else
      local start = top and x + 1 or x
      local pieces: {Piece} = {}
      for _, p in ipairs(g.list) do
        local text = p.mark.label
        if p ~= top and p.mark.sign and text then
          text, p.inline = p.mark.sign .. text, true
        end
        if text and text ~= "" then
          pieces[#pieces + 1] = {
            text = text,
            style = p.mark.label_style or p.mark.style,
            priority = p.mark.priority or 0,
            whole = p.mark.whole,
            placed = p,
          }
        end
      end
      local at = start
      for _, piece in ipairs(pieces) do
        local gap = at > start and 1 or 0
        -- The room: the free cells from `at`, less one free cell before
        -- what stops it, except at the end of the ruler.
        local stop = at
        while free(stop, x, piece.priority) do
          stop = stop + 1
        end
        -- A free cell keeps two texts apart. A sign is no text: the label
        -- can end in the cell before it.
        local before = cells.signs[stop]
        local flush = stop >= width or (before ~= nil and before.sign)
        local room = stop - at - (flush and 0 or 1)
        local w = api.str_width(piece.text) + gap
        local text = piece.text
        if w > room and not piece.whole and room - gap >= 2 then
          text = util.fit(piece.text, room - gap)
          w = api.str_width(text) + gap
        end
        if w <= room then
          piece.placed.label = text
          piece.placed.sign = piece.placed.sign or piece.placed.inline
          piece.placed.x0 = piece.placed == top and x or at + gap
          piece.placed.x1 = at + w
          for c = at, at + w - 1 do
            cells.taken[c] = true
          end
          at = at + w
          if text ~= piece.text then
            break
          end
        end
      end
      -- The column's sign, and its labels with a free cell after them: a
      -- soft sign of a lower priority there does not show. A sign that the
      -- labels do not cover, or an edge, can have the cell after them.
      if top then
        cells.taken[x] = true
      end
      local after = at > start and at or start - 1
      for c = start, after do
        local sign = cells.signs[c]
        -- An edge in the free cell stays: it is drawn at the far side.
        local under = c < at or not sign or not sign.mark.edge
        if c ~= x and sign and not (under and coverable(c, g.priority)) then
          break
        end
        cells.taken[c] = true
        if c ~= x and sign then
          cover(c)
        end
      end
    end
  end
end

--- Compose the ruler of a window: the marks in sight of each row in
--- `places`, each in its column of `ctx.axis`, `width` columns wide.
function M.compose(places: {M.Place}, ctx: Context, width: integer): M.Composition
  local ax = ctx.axis
  local comp: M.Composition = {places = places, placed = {}, width = width, ctx = ctx, errors = {}}
  local index: {string: M.Place} = {}
  for _, place in ipairs(places) do
    index[place.row.name] = place
  end
  -- The marks of each line, by the ruler's line.
  local lines: {integer: {M.Placed}} = {}
  local function add(m: Mark, place: M.Place, row: Row, line: integer)
    if not m.priority then
      m.priority = row and row.priority or 0
    end
    local y = place.y + math.min(math.max(0, line), place.h - 1)
    local p: M.Placed = {mark = m, row = place.row.name, y = y, sign = m.sign ~= nil}
    if m.to then
      local x0, x1 = ax:x_of(m.beat), ax:x_of(m.to)
      p.x, p.x0, p.x1 = x0, math.max(0, x0), math.min(width, x1)
      if p.x1 > p.x0 then
        comp.placed[#comp.placed + 1] = p
      end
      return
    end
    -- A mark outside the window's scope is not there: the scope ends
    -- before its `to`, but an edge there is drawn inside it.
    if ctx.to and (m.beat > ctx.to + 1e-9 or (m.beat > ctx.to - 1e-9 and not m.edge)) then
      return
    end
    -- An edge inside a fold stays, in the cell before the fold.
    p.x = ax:x_of(m.beat) - (m.edge and 1 or 0)
    p.x0, p.x1 = p.x, p.x + 1
    if p.x >= 0 and p.x < width and (m.edge or not ax:folded(m.beat)) then
      comp.placed[#comp.placed + 1] = p
      lines[y] = lines[y] or {}
      table.insert(lines[y], p)
    end
  end
  -- The rows' own marks, and the marks of the rows drawn over them.
  for _, r in ipairs(shown_rows()) do
    local place = index[r.over or r.name]
    if place and r.marks then
      local ok, list = pcall(r.marks, own(ctx, r.glyphs, r.styles)) as (boolean, {Mark} | string)
      if ok and list is {Mark} then
        for _, m in ipairs(list) do
          add(m, place, r, m.line or 0)
        end
      elseif not ok then
        comp.errors[#comp.errors + 1] = r.name .. ": " .. tostring(list)
      end
    end
  end
  -- The marks of the namespaces, where they are sent.
  for _, ns in pairs(marks.namespaces:entries()) do
    local list, err = namespace_marks(ns, ctx)
    comp.errors[#comp.errors + 1] = err
    for _, m in ipairs(list) do
      local _, target = target_of(ns, m)
      local place = index[target]
      if place then
        m.priority = m.priority or ns.priority
        add(m, place, nil, m.line or 0)
      end
    end
  end
  -- The cells after the scope's end and in a fold take no label.
  local scope_end = ctx.to and ax:x_of(ctx.to) or width
  local function blocked(x: integer): boolean
    return x >= scope_end or ax:fold_at(x) ~= nil
  end
  for _, list in pairs(lines) do
    place_line(list, width, blocked)
  end
  return comp
end

--- Draw a composition on `buf`, the ruler's lines over the timeline, and
--- the rows that draw themselves, with `header` (the ruler's lines over
--- the part headers) for their headers.
function M.paint(buf: contracts.Buf, header: contracts.Buf, comp: M.Composition)
  -- The stretches, lower priority first, so that the higher one is on top.
  local ranges: {M.Placed} = {}
  for _, p in ipairs(comp.placed) do
    if p.mark.to then
      ranges[#ranges + 1] = p
    end
  end
  table.sort(ranges, function(a: M.Placed, b: M.Placed): boolean return by_priority(b, a) end)
  for _, p in ipairs(ranges) do
    buf:fill(p.x0, p.y, p.x1 - p.x0, 1, nil, p.mark.style)
  end
  --- The style of a text at a cell: what the stretch on top there gives.
  local function style_at(y: integer, x: integer, style: string): string
    for i = #ranges, 1, -1 do
      local r = ranges[i]
      if r.y == y and x >= r.x0 and x < r.x1 and r.mark.restyle then
        return r.mark.restyle[style] or style
      end
    end
    return style
  end
  local function write(y: integer, x: integer, text: string, style: string)
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      x = x + buf:text(x, y, ch, style_at(y, x, style))
    end
  end
  for _, p in ipairs(comp.placed) do
    local m = p.mark
    if not m.to then
      if p.top and p.sign then
        write(p.y, p.x, m.sign, m.style)
      end
      if p.label then
        write(p.y, p.top and p.x + 1 or p.x0, p.label, m.label_style or m.style)
      end
    end
  end
  -- A row or a namespace that fails says so on the first line.
  table.sort(comp.errors)
  if #comp.errors > 0 then
    buf:text(0, 0, util.fit(table.concat(comp.errors, " · "), buf.width), "Error")
  end
  -- The rows that draw themselves.
  for _, place in ipairs(comp.places) do
    local r = place.row
    if r.draw then
      local c = own(comp.ctx, r.glyphs, r.styles)
      c.buf = buf:sub(0, place.y, buf.width, place.h)
      c.header = header:sub(0, place.y, header.width, place.h)
      local ok, err = pcall(r.draw, c) as (boolean, string)
      if not ok then
        c.buf:text(0, 0, util.fit(r.name .. ": " .. tostring(err), buf.width), "Error")
      end
    end
  end
end

-- What is there -------------------------------------------------------------------------

--- The mark under column `x` of the ruler's line `y`: a sign or a label
--- that shows there first, else the stretch of time there.
function M.at(comp: M.Composition, y: integer, x: number): M.Placed
  local stretch: M.Placed
  for _, p in ipairs(comp and comp.placed or {}) do
    if p.y == y and x >= p.x0 and x < p.x1 then
      if p.mark.to then
        stretch = stretch or p
      elseif p.sign or p.label then
        return p
      end
    end
  end
  return stretch
end

--- What `K` says of a column of the ruler: each mark there, on each row,
--- also those that are not shown, and why. Nil when the column has only
--- the number of its bar and the ticks of its beats.
function M.describe(comp: M.Composition, x: integer): contracts.Description
  if not comp then
    return nil
  end
  local list: {M.Placed} = {}
  local telling = false
  for _, p in ipairs(comp.placed) do
    local m = p.mark
    local here = m.to and x >= p.x0 and x < p.x1 or (not m.to and p.x == x)
    if here then
      list[#list + 1] = p
      local plain = (m.kind == "bar" or m.kind == "beat") and p.sign == (m.sign ~= nil) and p.label == m.label
      telling = telling or not plain
    end
  end
  if not telling then
    return nil
  end
  table.sort(
    list,
    function(a: M.Placed, b: M.Placed): boolean
      if a.y ~= b.y then
        return a.y < b.y
      end
      return by_priority(a, b)
    end
  )
  local lines: contracts.Description = {{text = "Ruler  column " .. x, style = "Title"}}
  for _, p in ipairs(list) do
    local m = p.mark
    local what = m.text or m.label or m.kind or ""
    -- What the ruler could not show of it, for lack of room.
    local notes: {string} = {}
    if m.sign and not p.sign then
      notes[#notes + 1] = "no room for its sign"
    end
    local shown = p.label and p.inline and p.label:sub(#m.sign + 1) or p.label
    if m.label and not shown then
      notes[#notes + 1] = "no room for " .. m.label
    elseif m.label and shown ~= m.label then
      notes[#notes + 1] = "shown as " .. shown
    end
    local text = string.format("  %-8s %s %s", p.row, m.sign or " ", what)
    if #notes > 0 then
      lines[#lines + 1] = {text = text .. "  (" .. table.concat(notes, ", ") .. ")", style = "Dim"}
    else
      lines[#lines + 1] = text
    end
  end
  lines[#lines + 1] = ""
  return lines
end

-- Bars ---------------------------------------------------------------------------------

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

--- The number that the ruler gives the song's bar `bar`: in a scope with
--- time, its bars count from 1 at the scope's start.
function M.bar_number(bar: integer): integer
  return bar - (paw.scope and paw.scope.bar_offset() or 0)
end

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

return M
