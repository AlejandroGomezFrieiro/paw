-- The track column: a narrow gutter at the left of the arrange view's track
-- headers, as Neovim's 'statuscolumn'. In paw a track is a line (`5j`,
-- `5G`, `dd`), so the column shows what Neovim's shows for lines: each
-- track's number, or how many `j` or `k` reach it (`paw.opt.number`,
-- `paw.opt.relativenumber`), signs, and the folds of track groups as a tree.
--
-- It is made of components, in their `order` from the left; those named in
-- `paw.opt.trackcolumn` show. An extension adds one:
--
--   paw.trackcolumn.add("rec", {
--     order = 25, width = 1,
--     render = function(track, ctx)
--       if ctx.line == 0 and paw.track(track).armed then return { { "●", "TrackSign" } } end
--     end,
--   })
--
-- or a sign in the `signs` component, one column for all of them:
--
--   paw.trackcolumn.sign("todo", { priority = 5, render = function(track) ... end })
--
-- The arrange view draws it on each line of each track shown, in cells, so
-- the terminal and the window show the same column (paw/views/arrange.tl).
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local options = require("paw.options")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type GroupsModule = require("paw.groups")
local type DrawModule = require("paw.draw")

local type Component = contracts.TrackColumnComponent
local type Context = contracts.TrackColumnContext
local type Frame = contracts.TrackColumnFrame
local type Cells = contracts.ColumnCells
local type Sign = contracts.TrackSign
local type FoldsModule = require("paw.folds")
local type Piece = contracts.Piece
local type Patch = contracts.ColumnPatch

--- A field of a component or a sign, which `set` copies and never reads.
local record Field
end

-- What this module reads of `paw`, which paw/init.lua makes.
local record Act
  fold: function(track: integer)
end
local record Frontend
  act: Act
end
--- paw/scope.tl, the part of it that this module reads.
local record Scope
  current: function(): Field
  window: function(): contracts.Window
end
local record Paw is partial.Paw
  groups: GroupsModule
  folds: FoldsModule
  draw: DrawModule
  frontend: Frontend
  scope: Scope
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

--- A component placed for one draw: where it starts and how wide it is.
local record Part
  component: Component
  x: integer
  width: integer
end

--- The column for one draw (`paw.trackcolumn.layout`): its parts, its
--- width, and the frame they were measured on.
local record Layout
  parts: {Part}
  width: integer
  frame: Frame
end

local record M
  type Part = Part
  type Layout = Layout
  components: {string: Component}
  signs: {string: Sign}
  --- How many times the column worked out the tree of groups: at most one
  --- time for each draw of the arrange view. Tests count the work with it.
  tree_builds: integer
end
M.components, M.signs, M.tree_builds = {}, {}, 0

local function has<T>(list: {T}, value: T): boolean
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

--- Add a component, or put a new one in place of one of that name. It
--- goes into `paw.opt.trackcolumn` (unless `hidden`), so it shows at once.
function M.add(name: string, spec: Component): Component
  assert(
    type(name) == "string" and type(spec) == "table" and type(spec.render) == "function",
    "usage: paw.trackcolumn.add(name, { order = 50, width = 1, render = function(track, ctx) ... end })"
  )
  spec.name = name
  spec.order = spec.order or 50
  spec.width = spec.width or 1
  M.components[name] = spec
  local shown = opt.trackcolumn as {string}
  if not spec.hidden and not has(shown, name) then
    local list: {string} = {}
    for i, n in ipairs(shown) do
      list[i] = n
    end
    list[#list + 1] = name
    opt.trackcolumn = list
  end
  api.ui_redraw()
  return spec
end

--- Take a component away, and its name out of `paw.opt.trackcolumn`.
function M.remove(name: string)
  M.components[name] = nil
  local list: {string} = {}
  for _, n in ipairs(opt.trackcolumn as {string}) do
    if n ~= name then
      list[#list + 1] = n
    end
  end
  opt.trackcolumn = list
  api.ui_redraw()
end

--- Add a sign to the `signs` component: `render(track, ctx)` gives one
--- character, or nothing. Where several give one, the highest `priority`
--- shows. `nil` for `spec` takes the sign away.
function M.sign(name: string, spec: Sign)
  if spec then
    assert(
      type(spec.render) == "function",
      "usage: paw.trackcolumn.sign(name, { priority = 10, render = function(track, ctx) ... end })"
    )
    spec.name = name
    spec.priority = spec.priority or 10
  end
  M.signs[name] = spec
  api.ui_redraw()
end

--- A copy of `from` with the fields of `patch` that are given: `glyphs`
--- and `styles` are merged into its own. A copy, not a change in place,
--- so that the registry holds a new value and an extension that unloads
--- puts back the one it found (paw/ext.lua). `ext` names the extension
--- whose code made the change, nil for the user's.
local function patched(from: Patch, patch: Patch): Patch
  local out: {string: Field} = {}
  for k, v in pairs(from as {string: Field}) do
    out[k] = v
  end
  for k, v in pairs(patch as {string: Field}) do
    if k == "glyphs" or k == "styles" then
      local own: {string: string} = {}
      for name, value in pairs((from as {string: {string: string}})[k] or {}) do
        own[name] = value
      end
      for name, value in pairs(v as {string: string}) do
        own[name] = value
      end
      out[k] = own as Field
    else
      out[k] = v
    end
  end
  out.ext = paw.ext.caller() as Field
  return out as Patch
end

--- Change a component that is there, the built-in ones too: its `order`
--- (to put it elsewhere), `width`, `render`, `click`, `describe`, and the
--- `glyphs` and `styles` it draws with (merged into its own). The
--- component becomes a changed copy: `paw.trackcolumn.add(name, old)`
--- with the table it had before puts that back.
---   paw.trackcolumn.set("fold", { order = 5, glyphs = { open = "-", closed = "+" } })
---   paw.trackcolumn.set("number", { width = 4, styles = { cursor = "Title" } })
function M.set(name: string, patch: Patch): Component
  local c = M.components[name]
  if not c then
    error("no track column component `" .. tostring(name) .. "`", 2)
  end
  local copy = patched(c as Patch, patch) as Component
  M.components[name] = copy
  api.ui_redraw()
  return copy
end

--- Change a sign that is there, as `set` changes a component: its
--- `priority`, `render`, `describe`, `glyphs` and `styles`.
---   paw.trackcolumn.set_sign("diagnostics", { glyphs = { error = "E", warn = "W" } })
function M.set_sign(name: string, patch: Patch): Sign
  local s = M.signs[name]
  if not s then
    error("no track column sign `" .. tostring(name) .. "`", 2)
  end
  local copy = patched(s as Patch, patch) as Sign
  M.signs[name] = copy
  api.ui_redraw()
  return copy
end

--- A glyph of a component, by name: its own (`set`), else paw's (`paw.draw.g`).
local function glyph(ctx: Context, name: string): string
  return ctx.glyphs and ctx.glyphs[name] or (ctx.g as {string: string})[name]
end

--- A highlight group of a component, by name: its own, else `default`.
local function style(ctx: Context, name: string, default: string): string
  return ctx.styles and ctx.styles[name] or default
end

--- The first piece of cells, as text and style.
local function first(cells: Cells): string, string
  if cells is string then
    return cells, nil
  end
  if cells is {Piece} and cells[1] then
    return cells[1][1], cells[1][2]
  end
end

-- The components that come with paw ---------------------------------------------

--- Columns of the number component: wide enough for the largest number, and
--- a space after it, as Neovim's.
local function number_width(frame: Frame): integer
  if not (opt.number or opt.relativenumber) then
    return 0
  end
  local most = math.max(#frame.rows, opt.relativenumber and frame.count or 0)
  return math.max(2, #tostring(most)) + 1
end

M.add(
  "number",
  {
    order = 10,
    width = number_width,
    render = function(_: integer, ctx: Context): Cells
      if ctx.line ~= 0 then
        return nil
      end
      local text: string
      local group = style(ctx, "number", "TrackNr")
      if ctx.cursor then
        -- The cursor's track: its number (with 'number'), else 0, as Neovim.
        text = opt.number and ctx.kind == "track" and tostring(ctx.row) or (opt.relativenumber and "0" or nil)
        group = style(ctx, "cursor", "TrackNrCursor")
      elseif opt.relativenumber and ctx.relative then
        text = tostring(ctx.relative)
        group = style(ctx, "relative", group)
      elseif opt.number and ctx.kind == "track" then
        text = tostring(ctx.row)
      end
      if not text then
        return nil
      end
      -- Against the right edge, a column before the next part.
      return {{string.format("%" .. math.max(1, ctx.width - 1) .. "s", text), group}}
    end,
  }
)

-- The signs: the one of the highest priority, on a track's first line.
-- Worked out once a draw for every track, so the component's width can
-- say whether any track has one.
local shown_signs: {integer: Piece} = {}
local signs_sorted: {Sign} = {}

-- Signs by priority, the highest first, then by name.
local function by_priority(a: Sign, b: Sign): boolean
  if a.priority ~= b.priority then
    return a.priority > b.priority
  end
  return a.name < b.name
end

-- The glyphs and styles of a component that gives none: read, never written.
local NONE_GLYPHS: {string: string} = {}
local NONE_STYLES: {string: string} = {}

local function signs_width(frame: Frame): integer
  shown_signs, signs_sorted = {}, {}
  for _, s in pairs(M.signs) do
    signs_sorted[#signs_sorted + 1] = s
  end
  if #signs_sorted == 0 then
    return 0
  end
  table.sort(signs_sorted, by_priority)
  local any = false
  -- One context for every sign of every row, filled again for each.
  local ctx: Context = {line = 0, kind = "track", width = 1}
  for i, id in ipairs(frame.rows) do
    for _, s in ipairs(signs_sorted) do
      ctx.row, ctx.line, ctx.kind, ctx.width, ctx.g = i, 0, "track", 1, paw.draw.g
      ctx.glyphs, ctx.styles = s.glyphs or NONE_GLYPHS, s.styles or NONE_STYLES
      local ok, cells = pcall(s.render, id, ctx)
      local text, group = first(ok and cells as Cells or nil)
      if text and text ~= "" then
        shown_signs[id], any = {text, group}, true
        break
      end
    end
  end
  return any and 1 or 0
end

M.add(
  "signs",
  {
    order = 20,
    width = signs_width,
    render = function(track: integer, ctx: Context): Cells
      if ctx.line ~= 0 or ctx.kind ~= "track" then
        return nil
      end
      local piece = shown_signs[track]
      return piece and {{piece[1], piece[2] or style(ctx, "sign", "TrackSign")}} or nil
    end,
    -- What each sign says of the track, for `K`.
    describe = function(track: integer, ctx: Context): string
      local out: {string} = {}
      for _, s in ipairs(signs_sorted) do
        if s.describe then
          ctx.glyphs, ctx.styles = s.glyphs or {}, s.styles or {}
          local ok, text = pcall(s.describe, track, ctx)
          if ok and text then
            out[#out + 1] = text
          end
        end
      end
      return #out > 0 and table.concat(out, "; ") or nil
    end,
  }
)

-- A window in a scope (`paw.scope`) says so with `›` on its first row:
-- the rows and their numbers are the scope's, not the song's.
M.sign(
  "scope",
  {
    priority = 100,
    glyphs = {scope = "›"},
    render = function(_: integer, ctx: Context): Cells
      if ctx.row == 1 and paw.scope and paw.scope.current() then
        return {{glyph(ctx, "scope") or "›", style(ctx, "sign", "TrackSign")}}
      end
    end,
  }
)

-- The folds of groups, as a tree: an open group has `▾` on its line and a
-- guide down its members, `╰` on the last; a folded one has `▸`. Each
-- level of nesting is a column. Worked out at most once for each layout,
-- from the tracks that it draws (`width`), and read by `render` for each
-- line and by `click`. It is kept while its key is the same: the tracks
-- drawn, the window and the change count of its folds, and the edits of
-- the project (the groups).
local record Tree
  key: string
  depth: {integer: integer}
  chain: {integer: {integer}}
  group: {integer: boolean}
  folded: {integer: boolean}
  fold: {integer: contracts.Fold}
  last: {integer: integer}
  width: integer
end

local project_field = api.project_get as function(key: string): integer

local function tree_key(rows: {integer}): string
  local folds = paw.folds
  return table.concat(rows as {string}, ",")
    .. "|"
    .. tostring(paw.scope.window())
    .. "|"
    .. folds.generation
    .. "|"
    .. project_field("edits")
end

local function tree_of(rows: {integer}, key: string): Tree
  M.tree_builds = M.tree_builds + 1
  local groups, folds = paw.groups, paw.folds
  local t: Tree = {key = key, depth = {}, chain = {}, group = {}, folded = {}, fold = {}, last = {}, width = 0}
  for i, id in ipairs(rows) do
    local chain: {integer} = {}
    local at = groups.of(id)
    while at and #chain < 16 do
      table.insert(chain, 1, at)
      at = groups.of(at)
    end
    t.chain[id], t.depth[id] = chain, #chain
    if groups.is_group(id) then
      t.group[id], t.folded[id] = true, groups.folded(id)
    end
    -- The first row of a fold of tracks stands for all of it.
    local fold = folds.row(id)
    if fold then
      t.group[id], t.folded[id], t.fold[id] = true, true, fold
    end
    for _, g in ipairs(chain) do
      t.last[g] = i
    end
    t.width = math.max(t.width, #chain + (t.group[id] and 1 or 0))
  end
  return t
end

-- The tracks of the last layout, for a part that needs them all.
local frame_rows: {integer} = {}
-- The tree of the last layout's tracks.
local tree: Tree

-- The tree of `rows`: the kept one while its key is the same.
local function tree_for(rows: {integer}): Tree
  local key = tree_key(rows)
  if not (tree and tree.key == key) then
    tree = tree_of(rows, key)
  end
  return tree
end

-- The tree for `render` and `click`, of the last layout.
local function current_tree(): Tree
  return tree or tree_for(frame_rows)
end

M.add(
  "fold",
  {
    order = 30,
    -- Glyphs, by name: `open` and `closed` on a group, `guide` down its
    -- members, `last` on its last member; paw's own (`paw.draw.g`, ASCII
    -- with `paw.opt.ascii`) when not set.
    glyphs = {},
    width = function(frame: Frame): integer return tree_for(frame.rows).width end,
    render = function(track: integer, ctx: Context): Cells
      local t = current_tree()
      if not t.chain[track] then
        return nil
      end
      local guide, last_mark = glyph(ctx, "guide") or ctx.g.v, glyph(ctx, "last") or ctx.g.bl
      local first_line = ctx.line == 0 and ctx.kind == "track"
      local out: {string} = {}
      for d, group in ipairs(t.chain[track]) do
        local last = t.last[group] == ctx.row
        if first_line then
          out[d] = last and last_mark or guide
        else
          out[d] = last and " " or guide
        end
      end
      if t.group[track] then
        if first_line then
          out[#out + 1] = t.folded[track] and glyph(ctx, "closed") or glyph(ctx, "open")
        elseif not t.folded[track] and t.last[track] then
          out[#out + 1] = guide
        end
      end
      if #out == 0 then
        return nil
      end
      return {{table.concat(out), style(ctx, "fold", "TrackFold")}}
    end,
    -- A click on the mark of a group folds it away or opens it, as `za`.
    click = function(track: integer, ctx: Context)
      local t = current_tree()
      if t.group[track] and ctx.line == 0 and ctx.kind == "track" and ctx.x == t.depth[track] then
        paw.frontend.act.fold(track)
      end
    end,
    -- What `K` says: the group a track is in, and of a group what it holds.
    describe = function(track: integer): string
      local groups = paw.groups
      local words: {string} = {}
      local fold = paw.folds.row(track)
      if fold then
        words[#words + 1] = string.format(
          "the fold %s of %d tracks, folded (za opens it, zd deletes it)", paw.folds.name(fold), paw.folds.count(fold)
        )
      end
      if groups.is_group(track) then
        local n = #groups.members(track)
        words[1] = string.format(
          "a group of %d track%s, %s",
          n,
          n == 1 and "" or "s",
          groups.folded(track) and "folded (za opens it)" or "open (za folds it)"
        )
      end
      local of = groups.of(track)
      if of then
        words[#words + 1] = "in the group " .. tostring(api.track_get(of).name)
      end
      return #words > 0 and table.concat(words, "; ") or nil
    end,
  }
)

-- Laying out and drawing ---------------------------------------------------------

-- Components by their order, then by name.
local function by_order(a: Component, b: Component): boolean
  if a.order ~= b.order then
    return a.order < b.order
  end
  return a.name < b.name
end

--- The column for one draw over the tracks of `frame`, at most `room`
--- columns wide: the components named in `paw.opt.trackcolumn`, in their
--- order, each as wide as it says. A component that fails takes no room.
function M.layout(frame: Frame, room: integer): Layout
  local list: {Component} = {}
  for _, name in ipairs(opt.trackcolumn as {string}) do
    local c = M.components[name]
    if c and not has(list, c) then
      list[#list + 1] = c
    end
  end
  table.sort(list, by_order)
  local out: Layout = {parts = {}, width = 0, frame = frame}
  frame_rows = frame.rows
  for _, c in ipairs(list) do
    local w: integer
    local spec = c.width
    if spec is integer then
      w = spec
    else
      local ok, n = pcall(spec as contracts.TrackColumnWidth, frame)
      w = ok and math.floor(tonumber(n) or 0) or 0
    end
    if w > 0 and out.width + w <= room then
      out.parts[#out.parts + 1] = {component = c, x = out.width, width = w}
      out.width = out.width + w
    end
  end
  return out
end

--- Draw one line of the column for `track` at line `y` of `buf` (the
--- column's own part of the view), with what `ctx` says of the line.
function M.draw(buf: contracts.Buf, L: Layout, y: integer, track: integer, ctx: Context)
  if L.width == 0 then
    return
  end
  buf:fill(0, y, L.width, 1, " ", ctx.cursor and "TrackColumnCursor" or "TrackColumn")
  ctx.g = paw.draw.g
  for _, part in ipairs(L.parts) do
    ctx.width = part.width
    ctx.glyphs, ctx.styles = part.component.glyphs or NONE_GLYPHS, part.component.styles or NONE_STYLES
    local ok, cells = pcall(part.component.render, track, ctx)
    if not ok then
      buf:text(part.x, y, "!", "Error")
    elseif cells is string then
      buf:text(part.x, y, util.fit(cells, part.width))
    elseif cells is {Piece} then
      local x = part.x
      for _, piece in ipairs(cells) do
        local room = part.x + part.width - x
        if room <= 0 then
          break
        end
        local text = api.str_width(piece[1]) > room and util.fit(piece[1], room) or piece[1]
        x = x + buf:text(x, y, text, piece[2])
      end
    end
  end
end

--- A click at column `x` of the column on a line of `track`: the
--- component there does what its `click` says. True if one had a `click`.
function M.click(L: Layout, x: integer, track: integer, ctx: Context): boolean
  for _, part in ipairs(L.parts) do
    if x >= part.x and x < part.x + part.width and part.component.click then
      ctx.width, ctx.x, ctx.g = part.width, x - part.x, paw.draw.g
      ctx.glyphs, ctx.styles = part.component.glyphs or {}, part.component.styles or {}
      part.component.click(track, ctx)
      return true
    end
  end
  return false
end

--- What the components shown say of `track` for `K` (their `describe`),
--- a line each, in their order.
function M.describe(track: integer): {string}
  local list: {Component} = {}
  for _, name in ipairs(opt.trackcolumn as {string}) do
    local c = M.components[name]
    if c and c.describe and not has(list, c) then
      list[#list + 1] = c
    end
  end
  table.sort(list, function(a: Component, b: Component): boolean return a.order < b.order end)
  local out: {string} = {}
  for _, c in ipairs(list) do
    local ctx: Context = {line = 0, kind = "track", g = paw.draw.g, glyphs = c.glyphs or {}, styles = c.styles or {}}
    local ok, text = pcall(c.describe, track, ctx)
    if ok and text and text ~= "" then
      out[#out + 1] = text
    end
  end
  return out
end

--- True if component `name` is shown: added and named in `paw.opt.trackcolumn`.
function M.shows(name: string): boolean
  return M.components[name] ~= nil and has(opt.trackcolumn as {string}, name)
end

return M
