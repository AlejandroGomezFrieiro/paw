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
local registry = require("paw.registry")
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
--- paw/nest.tl, the part of it that this module reads: the rows of a
--- subproject shown under its return row (`za`).
local record Nest
  shown_under: function(track: integer): integer
  returns: function(row: integer): integer
  is_open: function(row: integer): boolean
  toggle: function(track: integer): boolean
end
local record Paw is partial.Paw
  nest: Nest
  groups: GroupsModule
  folds: FoldsModule
  draw: DrawModule
  frontend: Frontend
  scope: Scope
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

--- A component placed for one draw: where it starts and how wide it is.
local record Portion
  component: Component
  x: integer
  width: integer
end

--- The column for one draw (`paw.trackcolumn.layout`): its parts, its
--- width, how many of its columns the headers give (its parts with
--- `from_header`), and the frame they were measured on.
local record Layout
  portions: {Portion}
  width: integer
  from_header: integer
  frame: Frame
end

local record M
  type Portion = Portion
  type Layout = Layout
  --- The components by name, with the extension that added or changed
  --- each one (`add`, `set`).
  components: registry.Registry<Component>
  --- The signs of the `signs` component by name, with the extension that
  --- added or changed each one (`sign`, `set_sign`).
  signs: registry.Registry<Sign>
  --- How many times the column worked out the tree of groups: at most one
  --- time for each draw of the arrange view. Tests count the work with it.
  tree_builds: integer
end
M.tree_builds = 0

--- Take the name of a component that went out of `paw.opt.trackcolumn`.
local function unshow(name: string)
  local list: {string} = {}
  for _, n in ipairs(opt.trackcolumn as {string}) do
    if n ~= name then
      list[#list + 1] = n
    end
  end
  opt.trackcolumn = list
end

-- A change draws the column again. A component that goes with no component
-- below it leaves `paw.opt.trackcolumn`, and a component that an extension
-- changed with `set` comes back as it was.
M.components = registry.new(
  "trackcolumn",
  "parts of the track column",
  {
    changed = function(name: string, spec: Component)
      if not spec then
        unshow(name)
      end
      api.ui_redraw()
    end,
  }
)
M.signs = registry.new("trackcolumn_signs", "signs of the track column", {changed = function() api.ui_redraw() end})

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
  M.components:put(name, spec)
  local shown = opt.trackcolumn as {string}
  if not spec.hidden and not has(shown, name) then
    local list: {string} = {}
    for i, n in ipairs(shown) do
      list[i] = n
    end
    list[#list + 1] = name
    opt.trackcolumn = list
  end
  return spec
end

--- Take a component away, and its name out of `paw.opt.trackcolumn`.
--- The component that it replaced, if any, comes back.
function M.remove(name: string)
  if not M.components:remove(name) then
    unshow(name)
  end
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
    M.signs:put(name, spec)
  else
    M.signs:remove(name)
  end
end

--- A copy of `from` with the fields of `patch` that are given: `glyphs`
--- and `styles` are merged into its own. A copy, not a change in place,
--- so that the registry holds it over the one it changed, which comes back
--- when the extension that changed it unloads. `ext` names the extension
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
--- with the table it had before puts that back. The change of an
--- extension goes when the extension unloads.
---   paw.trackcolumn.set("fold", { order = 5, glyphs = { open = "-", closed = "+" } })
---   paw.trackcolumn.set("number", { width = 4, styles = { cursor = "Title" } })
function M.set(name: string, patch: Patch): Component
  local c = M.components:get(name)
  if not c then
    error("no track column component `" .. tostring(name) .. "`", 2)
  end
  local copy = patched(c as Patch, patch) as Component
  M.components:put(name, copy)
  return copy
end

--- Change a sign that is there, as `set` changes a component: its
--- `priority`, `render`, `describe`, `glyphs` and `styles`.
---   paw.trackcolumn.set_sign("diagnostics", { glyphs = { error = "E", warn = "W" } })
function M.set_sign(name: string, patch: Patch): Sign
  local s = M.signs:get(name)
  if not s then
    error("no track column sign `" .. tostring(name) .. "`", 2)
  end
  local copy = patched(s as Patch, patch) as Sign
  M.signs:put(name, copy)
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

-- The folds of groups, as a tree: an open group has `▾` on its line and a
-- guide down its members, `╰` on the last; a folded one has `▸`. Each
-- level of nesting is a column. A subproject's return row (paw/nest.tl)
-- is a fold too: `za` shows the subproject's tracks under it, with the
-- dotted guide `┆` down them in its column and their own groups to the
-- right of it, and a closing line (`kind` `end`) that has `╰` there.
-- Worked out at most once for each layout, from the tracks that it draws
-- (`width`), and read by `render` for each line and by `click`. It is kept
-- while its key is the same: the tracks drawn, the window and the change
-- count of its folds, and the edits of the project (the groups).
local record Tree
  key: string
  depth: {integer: integer}
  chain: {integer: {integer}}
  group: {integer: boolean}
  folded: {integer: boolean}
  fold: {integer: contracts.Fold}
  last: {integer: integer}
  --- The return rows in the tree: their guide is dotted, and their last
  --- row has the closing line under it, not `╰`.
  returns: {integer: boolean}
  --- Each song track's number: its place among the song's tracks drawn.
  --- The tracks of a subproject shown in place have none.
  number: {integer: integer}
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

--- The groups a track is in, the outermost first.
local function groups_of(groups: GroupsModule, id: integer): {integer}
  local chain: {integer} = {}
  local at = groups.of(id)
  while at and #chain < 16 do
    table.insert(chain, 1, at)
    at = groups.of(at)
  end
  return chain
end

local function tree_of(rows: {integer}, key: string): Tree
  M.tree_builds = M.tree_builds + 1
  local groups, folds, nest = paw.groups, paw.folds, paw.nest
  local t: Tree = {
    key = key,
    depth = {},
    chain = {},
    group = {},
    folded = {},
    fold = {},
    last = {},
    returns = {},
    number = {},
    width = 0,
  }
  local songs = 0
  for i, id in ipairs(rows) do
    -- A track of a subproject shown in place: under the chain of its
    -- return row and the row itself, then its own groups.
    local under = nest.shown_under(id)
    local chain: {integer}
    -- The groups of the chain that this row is a member of: the song's
    -- groups above a return row end at it.
    local own_from = 1
    if under and t.chain[under] then
      own_from = #t.chain[under] + 1
      chain = {}
      for _, g in ipairs(t.chain[under]) do
        chain[#chain + 1] = g
      end
      chain[#chain + 1] = under
      for _, g in ipairs(groups_of(groups, id)) do
        chain[#chain + 1] = g
      end
    else
      chain = groups_of(groups, id)
      songs = songs + 1
      t.number[id] = songs
    end
    t.chain[id], t.depth[id] = chain, #chain
    if groups.is_group(id) then
      t.group[id], t.folded[id] = true, groups.folded(id)
    elseif not under and nest.returns(id) then
      t.group[id], t.folded[id], t.returns[id] = true, not nest.is_open(id), true
    end
    -- The first row of a fold of tracks stands for all of it.
    local fold = folds.row(id)
    if fold then
      t.group[id], t.folded[id], t.fold[id] = true, true, fold
    end
    for d = own_from, #chain do
      t.last[chain[d]] = i
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

--- A track's number among the song's tracks drawn, or nil for a track of
--- a subproject shown under its return row.
local function song_number(track: integer): integer
  return current_tree().number[track]
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
    render = function(track: integer, ctx: Context): Cells
      if ctx.line ~= 0 then
        return nil
      end
      local text: string
      local group = style(ctx, "number", "TrackNr")
      -- A track's number is its place among the song's tracks (what `5G`
      -- takes): the rows of a subproject shown under its return row have
      -- none, and the song's tracks after them keep theirs.
      local number = ctx.kind == "track" and song_number(track) or nil
      if ctx.cursor then
        -- The cursor's track: its number (with 'number'), else 0, as Neovim.
        text = opt.number and number and tostring(number) or (opt.relativenumber and "0" or nil)
        group = style(ctx, "cursor", "TrackNrCursor")
      elseif opt.relativenumber and ctx.relative then
        text = tostring(ctx.relative)
        group = style(ctx, "relative", group)
      elseif opt.number and number then
        text = tostring(number)
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
  for _, s in pairs(M.signs:entries()) do
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
    from_header = true,
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

M.add(
  "fold",
  {
    order = 30,
    from_header = true,
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
      local dotted = glyph(ctx, "nest_guide") or ctx.g.nest_guide
      local first_line = ctx.line == 0 and ctx.kind == "track"
      local out: {string} = {}
      for d, group in ipairs(t.chain[track]) do
        local last = t.last[group] == ctx.row
        if t.returns[group] then
          -- Down the rows of a subproject: the closing line ends them.
          out[d] = dotted
        elseif t.last[group] < ctx.row then
          -- A group that ended above: the rows of a subproject under its
          -- last member, and their closing line.
          out[d] = " "
        elseif first_line then
          out[d] = last and last_mark or guide
        else
          out[d] = last and " " or guide
        end
      end
      if ctx.kind == "end" then
        -- The line that closes the rows of a return row (`track`): `╰` in
        -- its column, then the dotted line to the headers.
        out[#out + 1] = last_mark
        while #out < ctx.width do
          out[#out + 1] = glyph(ctx, "nest_close") or ctx.g.nest_close
        end
      elseif t.group[track] then
        if first_line then
          out[#out + 1] = t.folded[track] and glyph(ctx, "closed") or glyph(ctx, "open")
        elseif not t.folded[track] and t.last[track] then
          out[#out + 1] = t.returns[track] and dotted or guide
        end
      end
      if #out == 0 then
        return nil
      end
      return {{table.concat(out), style(ctx, "fold", "TrackFold")}}
    end,
    -- A click on the mark of a group folds it away or opens it, as `za`;
    -- on a return row's, it shows or hides the subproject's tracks.
    click = function(track: integer, ctx: Context)
      local t = current_tree()
      if t.group[track] and ctx.line == 0 and ctx.kind == "track" and ctx.x == t.depth[track] then
        if t.returns[track] then
          paw.nest.toggle(track)
        else
          paw.frontend.act.fold(track)
        end
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

--- The column for one draw over the tracks of `frame`: the components
--- named in `paw.opt.trackcolumn`, in their order, each as wide as it
--- says. Each component with `from_header` takes its columns from the
--- headers, up to `header_room` columns in all. The other components, and
--- a component that does not fit in the headers, take their columns from
--- the timeline, up to `room` columns. A component that fails, or that has
--- no room left, takes no columns.
function M.layout(frame: Frame, room: integer, header_room: integer): Layout
  local list: {Component} = {}
  for _, name in ipairs(opt.trackcolumn as {string}) do
    local c = M.components:get(name)
    if c and not has(list, c) then
      list[#list + 1] = c
    end
  end
  table.sort(list, by_order)
  local out: Layout = {portions = {}, width = 0, from_header = 0, frame = frame}
  -- The tree of this frame's rows, before any component draws: the
  -- number component reads the song's numbers from it, also when the
  -- fold component is not in the column.
  frame_rows = frame.rows
  tree_for(frame.rows)
  for _, c in ipairs(list) do
    local w: integer
    local spec = c.width
    if spec is integer then
      w = spec
    else
      local ok, n = pcall(spec as contracts.TrackColumnWidth, frame)
      w = ok and math.floor(tonumber(n) or 0) or 0
    end
    -- A component takes all its columns from one side: the headers if it
    -- asks for them and they have room, else the timeline.
    local of_header = c.from_header and out.from_header + w <= (header_room or 0)
    if w > 0 and (of_header or out.width - out.from_header + w <= room) then
      out.portions[#out.portions + 1] = {component = c, x = out.width, width = w}
      out.width = out.width + w
      if of_header then
        out.from_header = out.from_header + w
      end
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
  for _, portion in ipairs(L.portions) do
    ctx.width = portion.width
    ctx.glyphs, ctx.styles = portion.component.glyphs or NONE_GLYPHS, portion.component.styles or NONE_STYLES
    local ok, cells = pcall(portion.component.render, track, ctx)
    if not ok then
      buf:text(portion.x, y, "!", "Error")
    elseif cells is string then
      buf:text(portion.x, y, util.fit(cells, portion.width))
    elseif cells is {Piece} then
      local x = portion.x
      for _, piece in ipairs(cells) do
        local room = portion.x + portion.width - x
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
  for _, portion in ipairs(L.portions) do
    if x >= portion.x and x < portion.x + portion.width and portion.component.click then
      ctx.width, ctx.x, ctx.g = portion.width, x - portion.x, paw.draw.g
      ctx.glyphs, ctx.styles = portion.component.glyphs or {}, portion.component.styles or {}
      portion.component.click(track, ctx)
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
    local c = M.components:get(name)
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
  return M.components:get(name) ~= nil and has(opt.trackcolumn as {string}, name)
end

return M
