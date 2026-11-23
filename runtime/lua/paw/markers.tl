-- Markers and regions: named places and named stretches of the song.
--
-- A marker is a beat with a name; a region is a marker with a length. They
-- belong to the project (`project.meta.markers`), move with the beats when
-- the tempo changes, are saved with it and undone like any edit.
--
--   :marker Chorus          -- a marker at the cursor
--   :region Verse           -- a region over the selection, or over the loop
--   ]' and ['               -- the next marker or region start, the one before
--   :marker.list            -- all of them; choose one to go there
--   :region.loop Verse      -- loop a region
--   :render out.wav range=Verse     -- a region is a range to render
--   :render.regions out/    -- every region to a file of its own
--   ]r and [r               -- the next region at the same level, the one before
--   :region.move Chorus +8  -- 8 bars later, with the regions and markers inside
--
-- Regions nest by time: a region inside another's time is its child (see
-- "The tree of regions" below). `2ar` takes the region around the one at
-- the cursor.
--
-- In scripts: `paw.markers.add(16, "Chorus")`, `paw.markers.add(0, "Intro", { length = 16 })`,
-- `paw.markers.list()`, `paw.markers.find("Chorus")`, `paw.markers.remove(id)`,
-- `paw.markers.tree()`, `paw.markers.parent(id)`, `paw.markers.path(beat)`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local options = require("paw.options")
local commands = require("paw.commands")
local derived = require("paw.derived")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type UiModule = require("paw.ui")
local type objects = require("paw.objects")
local type CursorModule = require("paw.cursor")
local type RulerModule = require("paw.ruler")

--- A marker, or a region when it has a `length` in beats. `id` is its own
--- for good; `color` is a colour of the theme, or nil.
local record Marker
  id: integer
  beat: number
  name: string
  length: number
  color: string
  key: string
end

--- What `paw.markers.add` takes besides the beat and the name.
local record AddOptions
  length: number
  color: string
  key: string
end

--- What `paw.markers.set` changes: `length = false` makes a region a
--- marker again, and `color = false` takes its colour away.
local record Fields
  beat: number
  name: string
  length: number | boolean
  color: string | boolean
  key: string | boolean
end

--- A marker given by its id: `paw.markers.find({ id = 3 })`.
local record ById
  id: integer
end

--- A value of the options of a render (paw/render.tl), which this module
--- passes on.
local record RenderValue
end
local type RenderOptions = {string: RenderValue}

--- A line of `:marker.list`.
local record Item
  text: string
  beat: number
  name: string
  kind: string
end

--- What `paw.ui.input` takes.
local record InputOptions
  prompt: string
  text: string
  label: string
end

--- A range that a render can use: where it starts and ends, in beats.
local type Range = function(): number, number

--- paw/render.tl, as far as this module reads it.
local record Render
  ranges: {string: Range}
end

-- What this module reads of `paw`, which paw/init.lua makes: the parts of
-- the modules in Lua that their doc comments type, and the rest here.
--- `paw.pick` (paw/pick.tl), the part of it that this module calls: opening
--- a picker.
local record Pick
  metamethod __call: function<T>(self: Pick, spec: contracts.PickSource<T>)
end

local record Paw is partial.Paw
  keymap: KeymapModule
  ui: UiModule
  pick: Pick
  cursor: CursorModule
  time: objects.Time
  transport: objects.Transport
  render: function(path: string, opts: RenderOptions)
  ruler: RulerModule
end
local paw = (_G as {string: Paw}).paw

local record M
  type Marker = Marker
  type AddOptions = AddOptions
  type Fields = Fields
  type ById = ById
  type RenderOptions = RenderOptions
end

--- Each marker and region, in order of time: { id, beat, name, length, color }.
--- A region has a `length` in beats. A marker has no length.
function M.list(): {Marker}
  local list = api.project_get().meta.markers
  if not (list is {Marker}) then
    return {}
  end
  local out: {Marker} = {}
  for i, m in ipairs(list) do
    out[i] = m
  end
  table.sort(
    out,
    function(a: Marker, b: Marker): boolean
      if a.beat ~= b.beat then
        return a.beat < b.beat
      end
      return a.id < b.id
    end
  )
  return out
end

local function save(list: {Marker})
  local meta = api.project_get().meta
  meta.markers = #list > 0 and list or nil
  api.project_set({meta = meta})
end

--- The regions alone.
function M.regions(): {Marker}
  local out: {Marker} = {}
  for _, m in ipairs(M.list()) do
    if m.length then
      out[#out + 1] = m
    end
  end
  return out
end

-- The tree of regions -------------------------------------------------------------
--
-- Regions nest by time: a region whose time is inside another's is its
-- child, so nothing is saved for it and the files do not change. The parent
-- of a region is the smallest region that holds its time; of two with the
-- same time, the one made first (the smaller id) holds the other. Two
-- regions that overlap and do not nest are siblings. A marker belongs to
-- the innermost region around its beat.

--- A region in the tree (`paw.markers.tree`): the region, its level (1 at
--- the top), its place among its siblings (1 for the first), the region
--- around it (nil at the top) and the regions inside it, in order of time.
local record Node
  region: Marker
  depth: integer
  place: integer
  parent: Node
  children: {Node}
end

local record Tree
  roots: {Node}
  order: {Node}
  by_id: {integer: Node}
end

local EPS = 1e-9

--- True when region `a` holds region `b` (and is not it).
local function holds(a: Marker, b: Marker): boolean
  if a.id == b.id then
    return false
  end
  local a1, b1 = a.beat + a.length, b.beat + b.length
  if a.beat > b.beat + EPS or a1 < b1 - EPS then
    return false
  end
  if math.abs(a.beat - b.beat) <= EPS and math.abs(a1 - b1) <= EPS then
    return a.id < b.id
  end
  return true
end

-- Earlier first; of two that start together, the longer (the outer) first.
local function in_order(a: Node, b: Node): boolean
  local x, y = a.region, b.region
  if math.abs(x.beat - y.beat) > EPS then
    return x.beat < y.beat
  end
  if math.abs(x.length - y.length) > EPS then
    return x.length > y.length
  end
  return x.id < y.id
end

--- The regions that the tree is made of, with a text of all their fields:
--- the same text gives the same tree. The regions are in the project's
--- `meta`, so the tree reads the source `project`.
local record Regions
  text: string
  list: {Marker}
end

local function read_regions(ctx: derived.Ctx): Regions
  ctx:source("project")
  local list = M.regions()
  local parts: {string} = {}
  for i, r in ipairs(list) do
    parts[i] = string.format("%d:%.17g:%.17g:%s:%s", r.id, r.beat, r.length, r.name, r.color or "")
  end
  return {text = table.concat(parts, "\n"), list = list}
end

local function make_tree(regions: {Marker}): Tree
  local t: Tree = {roots = {}, order = {}, by_id = {}}
  for _, r in ipairs(regions) do
    t.by_id[r.id] = {region = r, children = {}}
  end
  for _, r in ipairs(regions) do
    -- The smallest region that holds it; of two as small, the later.
    local best: Marker
    for _, o in ipairs(regions) do
      if holds(o, r) then
        local better = not best or o.length < best.length - EPS
        if not better and math.abs(o.length - best.length) <= EPS then
          better = o.beat > best.beat + EPS or (math.abs(o.beat - best.beat) <= EPS and o.id > best.id)
        end
        if better then
          best = o
        end
      end
    end
    local node = t.by_id[r.id]
    if best then
      node.parent = t.by_id[best.id]
      table.insert(node.parent.children, node)
    else
      t.roots[#t.roots + 1] = node
    end
  end
  local function walk(list: {Node}, depth: integer)
    table.sort(list, in_order)
    for i, node in ipairs(list) do
      node.depth, node.place = depth, i
      t.order[#t.order + 1] = node
      walk(node.children, depth + 1)
    end
  end
  walk(t.roots, 1)
  return t
end

-- The tree is a value of `paw.derived`. It reads only the source
-- `project`: an edit of a note, a clip or a track does not make it stale,
-- and a read after one is a look-up. A change of the name, the tempo
-- or another part of `meta` reads the regions again, and the same regions
-- keep the same tree. An undo gives back the tree of before without a make.
local tree_spec: derived.Spec<boolean, Tree, Regions> = {
  name = "markers.tree",
  kind = "memo",
  inputs = read_regions,
  same_inputs = function(a: Regions, b: Regions): boolean return a.text == b.text end,
  make = function(_: derived.Ctx, _: boolean, _: Tree, regions: Regions): Tree return make_tree(regions.list) end,
  undo = true,
  limit = 1,
}
local tree_node = derived.node(tree_spec)

-- The tree of the regions as they are now: the graph makes it again only
-- after a change of the project's own fields.
local function tree(): Tree
  return (tree_node:get(true, true))
end

--- The regions as a tree: the top-level regions, each a node with
--- `region`, `depth` (1 at the top), `place` (among its siblings),
--- `parent` and `children`, in order of time. Flat regions are a tree of
--- depth 1.
function M.tree(): {Node}
  return tree().roots
end

--- Every region's node in the order of the tree: each region, then the
--- regions inside it.
function M.walk(): {Node}
  return tree().order
end

--- The node of a region by its id, or nil.
function M.node(id: integer): Node
  return tree().by_id[id]
end

--- The regions one level inside a region, in order of time; with no id, the
--- regions at the top.
function M.children(id?: integer): {Marker}
  local list: {Node}
  if id then
    local node = tree().by_id[id]
    list = node and node.children or {}
  else
    list = tree().roots
  end
  local out: {Marker} = {}
  for i, node in ipairs(list) do
    out[i] = node.region
  end
  return out
end

--- The level of a region: 1 at the top, 2 inside one region, and so on.
--- Nil for a marker.
function M.depth(id: integer): integer
  local node = tree().by_id[id]
  return node and node.depth
end

--- The regions around a beat, the outermost first. Where two siblings
--- overlap, the one that starts later is taken.
function M.path(beat: number): {Marker}
  local out: {Marker} = {}
  local level = tree().roots
  while true do
    local pick: Node
    for _, node in ipairs(level) do
      local r = node.region
      if beat >= r.beat - EPS and beat < r.beat + r.length - EPS and (not pick or r.beat >= pick.region.beat - EPS) then
        pick = node
      end
    end
    if not pick then
      return out
    end
    out[#out + 1] = pick.region
    level = pick.children
  end
end

--- What a marker is called on screen: its name, or its number in the song.
function M.label(marker: Marker): string
  if marker.name and marker.name ~= "" then
    return marker.name
  end
  for i, m in ipairs(M.list()) do
    if m.id == marker.id then
      return tostring(i)
    end
  end
  return "?"
end

--- A region's names from the top down, joined by `/`: `Chorus 2/Verse A`.
--- `:render range=` and `paw.markers.region` take it when names repeat.
function M.pathname(region: Marker): string
  local names: {string} = {}
  local node = tree().by_id[region.id]
  if not node then
    return M.label(region)
  end
  while node do
    table.insert(names, 1, M.label(node.region))
    node = node.parent
  end
  return table.concat(names, "/")
end

--- Add a marker at a beat. With `opts.length`, add a region from there; its
--- `opts.key` (such as "E minor") is the key of the harmony over its time. Returns it.
function M.add(beat: number, name?: string | number, opts?: AddOptions): Marker
  opts = opts or {}
  assert(beat is number and beat >= 0, "a marker is at a beat from 0 up")
  if opts.length ~= nil then
    assert(type(opts.length) == "number" and opts.length > 0, "a region has a length above 0")
  end
  local list, id = M.list(), 1
  for _, m in ipairs(list) do
    id = math.max(id, m.id + 1)
  end
  local marker: Marker = {
    id = id, beat = beat, name = name and tostring(name) or "", length = opts.length, color = opts.color, key = opts.key
  }
  list[#list + 1] = marker
  save(list)
  return marker
end

--- The marker or region of a number (its place in the song), of an id
--- given as `{ id = n }`, or of a name. Nil if there is none.
function M.find(which: number | string | ById): Marker
  local list = M.list()
  if which is ById then
    for _, m in ipairs(list) do
      if m.id == which.id then
        return m
      end
    end
    return nil
  end
  local n = tonumber(which) as integer
  if n and list[n] then
    return list[n]
  end
  local name = tostring(which):lower()
  for _, m in ipairs(list) do
    if m.name:lower() == name then
      return m
    end
  end
  for _, m in ipairs(list) do
    if m.name ~= "" and m.name:lower():find(name, 1, true) == 1 then
      return m
    end
  end
end

-- A region by its path of names, `Chorus 2/Verse A`: each name is looked
-- for among the regions inside the one before (a whole name first, then
-- the start of one).
local function by_path(text: string): Marker
  local level = tree().roots
  local found: Node
  for part in text:gmatch("[^/]+") do
    local want = part:match("^%s*(.-)%s*$"):lower()
    local pick: Node
    for _, node in ipairs(level) do
      if M.label(node.region):lower() == want then
        pick = node
        break
      end
    end
    if not pick then
      for _, node in ipairs(level) do
        if node.region.name:lower():find(want, 1, true) == 1 then
          pick = node
          break
        end
      end
    end
    if not pick then
      return nil
    end
    found, level = pick, pick.children
  end
  return found and found.region
end

--- A region by number, id, name or path of names (`Chorus 2/Verse A`).
function M.region(which: number | string | ById): Marker
  if which is string and which:find("/", 1, true) then
    local r = by_path(which)
    if r then
      return r
    end
  end
  local m = M.find(which)
  if m and m.length then
    return m
  end
  -- A marker and a region may share a name: the region is the one meant.
  local name = tostring(which):lower()
  for _, r in ipairs(M.regions()) do
    if r.name:lower() == name then
      return r
    end
  end
end

--- Change a marker: `fields` may hold beat, name, length (false makes a
--- region a marker again) and color.
function M.set(id: integer, fields: Fields): Marker
  local list, found: {Marker}, Marker = M.list(), nil
  for _, m in ipairs(list) do
    if m.id == id then
      found = m
      if fields.beat then
        m.beat = math.max(0, fields.beat)
      end
      if fields.name then
        m.name = tostring(fields.name)
      end
      if fields.length ~= nil then
        m.length = fields.length and math.max(1e-6, fields.length as number) or nil
      end
      if fields.color ~= nil then
        m.color = fields.color as string or nil
      end
      if fields.key ~= nil then
        m.key = fields.key as string or nil
      end
    end
  end
  if not found then
    error("no marker " .. tostring(id), 2)
  end
  save(list)
  return found
end

-- The ids of the regions inside a region, at every level below it.
local function inside(id: integer): {integer: boolean}
  local out: {integer: boolean} = {}
  local function add(node: Node)
    for _, child in ipairs(node.children) do
      out[child.region.id] = true
      add(child)
    end
  end
  local node = tree().by_id[id]
  if node then
    add(node)
  end
  return out
end

--- Move a marker or a region so that it starts at `beat`. A region takes
--- the regions and the markers inside it along, in one undo step, unless
--- `alone`. Returns it and how many moved with it.
function M.move(id: integer, beat: number, alone?: boolean): Marker, integer
  local list = M.list()
  local found: Marker
  for _, m in ipairs(list) do
    if m.id == id then
      found = m
    end
  end
  if not found then
    error("no marker " .. tostring(id), 2)
  end
  local by = math.max(0, beat) - found.beat
  local along: {integer: boolean} = {}
  if found.length and not alone then
    along = inside(id)
    local stop = found.beat + found.length
    for _, m in ipairs(list) do
      if not m.length and m.beat >= found.beat - EPS and m.beat < stop - EPS then
        along[m.id] = true
      end
    end
  end
  local moved = 0
  for _, m in ipairs(list) do
    if m.id == id then
      m.beat = m.beat + by
    elseif along[m.id] then
      m.beat = math.max(0, m.beat + by)
      moved = moved + 1
    end
  end
  save(list)
  return found, moved
end

--- Remove a marker by id. With `with_inside`, a region's regions inside it
--- go too (never clips, nor markers); without, they move up one level.
function M.remove(id: integer, with_inside?: boolean): boolean
  local list, gone: {Marker}, boolean = {}, false
  local also = with_inside and inside(id) or {}
  for _, m in ipairs(M.list()) do
    if m.id == id or also[m.id] then
      gone = true
    else
      list[#list + 1] = m
    end
  end
  if gone then
    save(list)
  end
  return gone
end

--- The marker or region start nearest a beat within `reach` beats (half a
--- grid step by default), or the region the beat is inside.
function M.at(beat: number, reach?: number): Marker
  reach = reach or options.opt.grid / 2
  local best, far: Marker, number
  for _, m in ipairs(M.list()) do
    local d = math.abs(m.beat - beat)
    if d <= reach and (not far or d < far) then
      best, far = m, d
    end
  end
  if best then
    return best
  end
  for _, m in ipairs(M.list()) do
    if m.length and beat >= m.beat and beat < m.beat + m.length then
      best = m
    end
  end
  return best
end

--- The region a beat is in: the innermost of those that hold it, or nil.
--- With `level` 2, the region around that one, and so on out (the
--- outermost when there are fewer).
function M.around(beat: number, level?: integer): Marker
  local path = M.path(beat)
  return path[math.max(1, #path - (level or 1) + 1)]
end

--- The region around a region (the smallest that holds it), or around a
--- marker (the innermost at its beat). Nil at the top.
function M.parent(id: integer): Marker
  local node = tree().by_id[id]
  if node then
    return node.parent and node.parent.region
  end
  local m = M.find({id = id})
  return m and M.around(m.beat)
end

--- The first marker after a beat, and the last before it.
function M.next(beat: number): Marker
  for _, m in ipairs(M.list()) do
    if m.beat > beat + 1e-9 then
      return m
    end
  end
end

--- The last marker before a beat, or nil.
function M.prev(beat: number): Marker
  local found: Marker
  for _, m in ipairs(M.list()) do
    if m.beat < beat - 1e-9 then
      found = m
    end
  end
  return found
end

-- A region is a range to render: `paw.render(path, { range = "Verse" })`.
do
  local ranges = (require as function(string): Render)("paw.render").ranges
  setmetatable(
    ranges,
    {
      __index = function(_: {string: Range}, name: string): Range
        local region = M.region(name)
        if region then
          return function(): number, number return region.beat, region.beat + region.length end
        end
      end,
    } as metatable<{string: Range}>
  )
end

-- A region's file name: its place among its siblings and its name, for
-- each level from the top: `03 Chorus 2 - 01 Verse A`.
local function file_name(node: Node): string
  local parts: {string} = {}
  while node do
    local name = M.label(node.region):gsub("[/%z]", "_")
    table.insert(parts, 1, string.format("%02d %s", node.place, name))
    node = node.parent
  end
  return table.concat(parts, " - ")
end

--- Render every region to a file of its own in `dir`, named by its path:
--- `01 Intro.wav`, and inside a region `03 Chorus 2 - 01 Verse A.wav`
--- (each number is the place among its siblings). `opts` is as for
--- `paw.render`, plus `format` ("wav", "flac", "mp3", "ogg" or "opus") and
--- `level`: a number renders the regions of that level only (1 the top),
--- "leaves" the regions with no region inside. Returns the files.
function M.render_regions(dir: string, opts?: RenderOptions): {string}
  opts = opts or {}
  local level = opts.level as string | number
  local depth = level and math.tointeger(tonumber(level))
  if level and level ~= "leaves" and not (depth and depth >= 1) then
    error("level= is a level from 1, or leaves", 0)
  end
  local nodes: {Node} = {}
  for _, node in ipairs(M.walk()) do
    if not level or node.depth == depth or (level == "leaves" and #node.children == 0) then
      nodes[#nodes + 1] = node
    end
  end
  if #nodes == 0 then
    error(
      level and "there are no regions at that level" or "there are no regions to render: `:region name` makes one", 0
    )
  end
  pcall(api.fs_mkdir, dir)
  local files: {string} = {}
  for i, node in ipairs(nodes) do
    local region = node.region
    local each: RenderOptions = {}
    for k, v in pairs(opts) do
      each[k] = v
    end
    each.format, each.range, each.level = nil, nil, nil
    each.start, each["end"] = region.beat as RenderValue, (region.beat + region.length) as RenderValue
    files[i] = string.format("%s/%s.%s", dir, file_name(node), opts.format as string or "wav")
    paw.render(files[i], each)
  end
  return files
end

-- Commands -----------------------------------------------------------------------

local function describe(m: Marker): string
  return (m.length and "region " or "marker ") .. "“" .. M.label(m) .. "” at " .. paw.time.format(m.beat)
end

local function names(): {string}
  local out: {string} = {}
  for _, m in ipairs(M.list()) do
    if m.name ~= "" then
      out[#out + 1] = m.name
    end
  end
  return out
end

-- The words of a command as one text.
local function words(args: commands.Args): string
  return table.concat(args as {string}, " ")
end

--- The marker a command is about: the one named (or given as `id=`, as a
--- frontend's menus do), or the one at the cursor. `kind` keeps to points
--- ("marker") or to ranges ("region"); a region at the cursor is the one
--- the cursor is in.
local function wanted(ctx: commands.Context, kind?: string): Marker
  local what = kind or "marker"
  local function fits(m: Marker): boolean
    return m ~= nil and (kind == nil or (kind == "region") == (m.length ~= nil))
  end
  if ctx.args.id then
    local m = M.find({id = tonumber(ctx.args.id) as integer})
    if not m then
      paw.notify("that marker is gone", "warn")
    end
    return m
  end
  local word = ctx.args[1] and words(ctx.args)
  local m: Marker
  if word then
    if kind == "region" then
      m = M.region(word)
    else
      m = M.find(word)
      if kind == "marker" and not fits(m) then
        m = nil
        for _, x in ipairs(M.list()) do
          if not x.length and x.name:lower() == word:lower() then
            m = x
          end
        end
      end
    end
    if not fits(m) then
      m = nil
    end
    if not m then
      paw.notify("no " .. what .. " `" .. word .. "`", "warn")
    end
  else
    local beat = paw.cursor.beat
    if kind == "region" then
      m = M.around(beat)
    elseif kind == "marker" then
      local reach = options.opt.grid / 2
      local far: number
      for _, x in ipairs(M.list()) do
        local d = math.abs(x.beat - beat)
        if not x.length and d <= reach and (not far or d < far) then
          m, far = x, d
        end
      end
    else
      m = M.at(beat)
    end
    if not m then
      paw.notify("no " .. what .. " at the cursor", "warn")
    end
  end
  return m
end

--- A name for a new marker that has none: "Marker 3" for the third.
function M.default_name(): string
  local taken: {string: boolean} = {}
  local n = #M.list() + 1
  for _, m in ipairs(M.list()) do
    taken[m.name] = true
  end
  while taken["Marker " .. n] do
    n = n + 1
  end
  return "Marker " .. n
end

local type Context = commands.Context
local type Result = commands.Result
-- Ask for a line of text (`paw.ui.input`, looked up when it asks).
local function input(opts: InputOptions, on_submit: function(text: string))
  (paw.ui.input as function(InputOptions, function(string)))(opts, on_submit)
end

commands.define(
  "marker",
  function(ctx: Context): Result
    local name = words(ctx.args):match("^%s*(.-)%s*$")
    if name == "" then
      name = M.default_name()
    end
    local m = M.add(tonumber(ctx.args.at) or paw.cursor.beat, name)
    paw.notify(describe(m))
  end,
  {
    desc = "Put a marker at the cursor: `marker Chorus`; alone, it is called Marker 1, Marker 2...; `at=` a beat instead",
  }
)

commands.define(
  "marker.new",
  function(): Result
    local beat = paw.cursor.beat
    input(
      {prompt = "Marker name: ", text = M.default_name(), label = "Put a marker"},
      function(name: string) local args: commands.Args = {name}; args.at = beat; commands.run("marker", args) end
    )
  end,
  {desc = "Put a marker at the cursor, asking for its name (Marker 1, Marker 2... if none is typed)"}
)

commands.define(
  "marker.remove",
  function(ctx: Context): Result
    -- From a menu (`id=`), whichever it is; typed, markers only.
    local m = wanted(ctx, (not ctx.args.id) and "marker" or nil)
    if not m then
      return
    end
    M.remove(m.id)
    paw.notify("removed the " .. describe(m))
  end,
  {
    desc = "Remove the marker at the cursor, or the one named or numbered: `marker.remove Chorus`; regions stay (`region.remove`)",
    complete = names,
  }
)

commands.define(
  "marker.rename",
  function(ctx: Context): Result
    local m = ctx.args.id and M.find({id = tonumber(ctx.args.id) as integer}) or M.at(paw.cursor.beat)
    if not m then
      paw.notify("no marker at the cursor", "warn")
      return
    end
    if ctx.args[1] then
      return M.set(m.id, {name = words(ctx.args)}) as Result
    end
    input(
      {prompt = (m.length and "Region" or "Marker") .. " name: ", text = m.name},
      function(name: string) M.set(m.id, {name = name}) end
    )
  end,
  {desc = "Name the marker or region at the cursor: `marker.rename Bridge`; alone, asks"}
)

-- For a frontend, where a marker is dragged: `marker.set id=3 beat=17.5`.
commands.define(
  "marker.set",
  function(ctx: Context): Result
    local id = tonumber(ctx.args.id) as integer
    if not (id and M.find({id = id})) then
      paw.notify("that marker is gone", "warn")
      return
    end
    local beat = tonumber(ctx.args.beat)
    local was = M.children(id)
    if beat then
      -- Moved: a region takes the regions and markers inside it along.
      M.move(id, beat)
    end
    local length = tonumber(ctx.args.length)
    local name: string = ctx.args.name and tostring(ctx.args.name) or nil
    local m = (length ~= nil or name ~= nil) and M.set(id, {length = length, name = name}) or M.find({id = id})
    -- Resized: a region that is no longer inside becomes a sibling.
    local out: {string} = {}
    for _, child in ipairs(was) do
      local parent = M.parent(child.id)
      if not (parent and (parent.id == id or inside(id)[parent.id])) and M.find({id = child.id}) then
        out[#out + 1] = M.label(child)
      end
    end
    if #out > 0 then
      paw.notify(table.concat(out, ", ") .. (#out == 1 and " is" or " are") .. " no longer inside " .. M.label(m))
    end
  end,
  {
    desc = "Move or change a marker by its id: `marker.set id=3 beat=16`; a region takes the regions and markers inside it along",
  }
)

-- What a move says: where it went, and what went with it.
local function moved(m: Marker, along: integer, alone: boolean): string
  local text = "moved the " .. describe(m)
  if alone and m.length then
    return text .. ", alone"
  end
  if along > 0 then
    text = text
      .. string.format(
        ", with %d marker%s and region%s inside", along, along == 1 and "" or "s", along == 1 and "" or "s"
      )
  end
  return text
end

commands.define(
  "marker.move",
  function(): Result
    local m = M.at(paw.cursor.beat, math.huge)
    if not m then
      paw.notify("there are no markers", "warn")
      return
    end
    local _, along = M.move(m.id, paw.cursor.beat)
    paw.notify(moved(M.find({id = m.id}), along, false))
  end,
  {
    desc = "Bring the nearest marker or region start to the cursor; a region takes the regions and markers inside it along",
  }
)

commands.define(
  "marker.next",
  function(ctx: Context): Result
    local beat = paw.cursor.beat
    for _ = 1, ctx.count or 1 do
      local m = M.next(beat)
      if not m then
        break
      end
      beat = m.beat
    end
    paw.cursor.set_beat(beat)
  end,
  {desc = "Go to the next marker or region start"}
)

commands.define(
  "marker.prev",
  function(ctx: Context): Result
    local beat = paw.cursor.beat
    for _ = 1, ctx.count or 1 do
      local m = M.prev(beat)
      if not m then
        break
      end
      beat = m.beat
    end
    paw.cursor.set_beat(beat)
  end,
  {desc = "Go to the marker or region start before the cursor"}
)

commands.define(
  "marker.goto",
  function(ctx: Context): Result
    local m = wanted(ctx)
    if m then
      paw.cursor.set_beat(m.beat)
    end
  end,
  {desc = "Go to a marker or region by number or name: `marker.goto 3`, `marker.goto Chorus`", complete = names}
)

commands.define(
  "marker.list",
  function(): Result
    local list = M.list()
    if #list == 0 then
      paw.notify("there are no markers: `:marker name` puts one at the cursor")
      return
    end
    local items: {Item} = {}
    for i, m in ipairs(list) do
      local where = paw.time.format(m.beat)
      if m.length then
        where = where .. " – " .. paw.time.format(m.beat + m.length)
      end
      -- Regions inside regions are indented under them.
      local indent = string.rep("  ", (m.length and M.depth(m.id) or 1) - 1)
      items[i] = {
        text = string.format("%2d  %-7s %-24s %s", i, m.length and "region" or "marker", indent .. M.label(m), where),
        beat = m.beat,
        name = M.label(m),
        kind = m.length and "region" or "marker",
      }
    end
    paw.pick(
      {
        title = "Markers and regions",
        items = items,
        on_choose = function(item: Item) paw.cursor.set_beat(item.beat) end,
        -- What is typed finds a name, not the number of the line: `Chorus 2`.
        search = function(item: Item): string return item.name .. " " .. item.kind end,
        primary = function(item: Item): string return item.name end,
      } as contracts.PickSource<Item>
    )
  end,
  {desc = "List the markers and regions; choose one to go there"}
)

--- The stretch a new region covers: the selection, else the loop.
local function region_span(): number, number
  local sel = paw.keymap.selection()
  if sel and sel.c0 and sel.c1 and sel.c1 > sel.c0 then
    return sel.c0, sel.c1
  end
  local t = api.transport_get()
  if t.loop_end > t.loop_start then
    return t.loop_start, t.loop_end
  end
  paw.notify("a region is made over the selection or the loop: select a stretch of time first", "warn")
  return nil, nil
end

local function add_region(from: number, to: number, name: string)
  local m = M.add(from, name, {length = to - from})
  paw.notify(describe(m) .. ", " .. string.format("%g", to - from) .. " beats")
end

commands.define(
  "region",
  function(ctx: Context): Result
    local from, to = region_span()
    if from then
      add_region(from, to, words(ctx.args))
    end
  end,
  {desc = "Make a region over the selection, or over the loop: `region Verse`"}
)

commands.define(
  "region.new",
  function(): Result
    local from, to = region_span()
    if not from then
      return
    end
    input({prompt = "Region name: ", label = "Make a region"}, function(name: string) add_region(from, to, name) end)
  end,
  {desc = "Make a region over the selection, or over the loop, asking for its name"}
)

local function remove_region(ctx: Context, with_inside: boolean)
  local m = wanted(ctx, "region")
  if not m then
    return
  end
  local within = M.children(m.id)
  local text = "removed the " .. describe(m)
  local n = 0
  for _ in pairs(inside(m.id)) do
    n = n + 1
  end
  M.remove(m.id, with_inside)
  if with_inside and n > 0 then
    text = text .. string.format(" and the %d region%s inside it", n, n == 1 and "" or "s")
  elseif #within > 0 then
    text = text
      .. string.format(
        "; the %d region%s inside it move%s up a level", #within, #within == 1 and "" or "s", #within == 1 and "s" or ""
      )
  end
  paw.notify(text .. "; its clips stay")
end

commands.define(
  "region.remove",
  function(ctx: Context): Result remove_region(ctx, false) end,
  {
    desc = "Remove the region the cursor is in, or the one named: `region.remove Verse`; its clips, the markers and the regions inside it stay",
    complete = names,
  }
)

commands.define(
  "region.remove!",
  function(ctx: Context): Result remove_region(ctx, true) end,
  {
    desc = "Remove the region the cursor is in, or the one named, and the regions inside it: `region.remove! Chorus 2`; the clips and the markers stay",
    complete = names,
  }
)

-- `:region.move Chorus 2 +8`: the region named (or the one the cursor is
-- in) N bars later or earlier; with no count of bars, to the cursor.
local function move_region(ctx: Context, alone: boolean)
  local text = tostring(ctx.args[1] or ""):match("^%s*(.-)%s*$")
  local name, bars = text:match("^(.-)%s*([+-]%d+)$")
  if not name then
    name = text
  end
  local m: Marker
  if name ~= "" then
    m = M.region(name)
    if not m then
      paw.notify("no region `" .. name .. "`", "warn")
      return
    end
  else
    m = M.around(paw.cursor.beat)
    if not m then
      paw.notify("no region at the cursor: `region.move Chorus +8` names one", "warn")
      return
    end
  end
  local to = paw.cursor.beat
  if bars then
    local bar = paw.time.bar_of(m.beat)
    to = paw.time.bar_start(math.max(1, bar + math.tointeger(tonumber(bars)))) + (m.beat - paw.time.bar_start(bar))
  elseif name == "" then
    paw.notify("say how far: `region.move +8` moves it 8 bars later", "warn")
    return
  end
  local _, along = M.move(m.id, to, alone)
  paw.notify(moved(M.find({id = m.id}), along, alone))
end

commands.define(
  "region.move",
  function(ctx: Context): Result move_region(ctx, false) end,
  {
    desc = "Move a region with the regions and markers inside it: `region.move Chorus 2 +8` 8 bars later, `-2` earlier; `region.move Chorus 2` to the cursor; alone, the region the cursor is in",
    raw = true,
    complete = names,
  }
)

commands.define(
  "region.move!",
  function(ctx: Context): Result move_region(ctx, true) end,
  {
    desc = "Move a region alone, without the regions and markers inside it: `region.move! Chorus 2 +8`",
    raw = true,
    complete = names,
  }
)

-- The next region (`dir` 1) or the one before (-1) at the level of the
-- innermost region at the cursor; at the top level when it is in none.
local function step_region(ctx: Context, dir: integer)
  local beat = paw.cursor.beat
  local here = M.around(beat)
  local level = here and M.depth(here.id) or 1
  local list: {Marker} = {}
  for _, node in ipairs(M.walk()) do
    if node.depth == level then
      list[#list + 1] = node.region
    end
  end
  table.sort(list, function(a: Marker, b: Marker): boolean return a.beat < b.beat end)
  local found: Marker
  for _ = 1, ctx.count or 1 do
    local pick: Marker
    for _, r in ipairs(list) do
      if dir > 0 and r.beat > beat + EPS then
        pick = r
        break
      elseif dir < 0 and r.beat < beat - EPS then
        pick = r
      end
    end
    if not pick then
      break
    end
    found, beat = pick, pick.beat
  end
  if not found then
    paw.notify(dir > 0 and "no region after this at this level" or "no region before this at this level", "warn")
    return
  end
  paw.cursor.set_beat(found.beat)
end

commands.define(
  "region.next",
  function(ctx: Context): Result step_region(ctx, 1) end,
  {desc = "Go to the next region at the level of the one the cursor is in (`]r`)"}
)

commands.define(
  "region.prev",
  function(ctx: Context): Result step_region(ctx, -1) end,
  {desc = "Go to the region before, at the level of the one the cursor is in (`[r`)"}
)

commands.define(
  "region.loop",
  function(ctx: Context): Result
    local m = wanted(ctx, "region")
    if not m then
      return
    end
    local t = paw.transport
    t.loop_start, t.loop_end, t.loop_enabled = m.beat, m.beat + m.length, true
    paw.notify("loop: " .. paw.ruler.loop_text(t.loop_start, t.loop_end, true) .. " (" .. describe(m) .. ")")
  end,
  {
    desc = "Set the playback loop to the region at the cursor, or to the one named, and turn looping on: `region.loop Verse`",
    complete = names,
  }
)

commands.define(
  "render.regions",
  function(ctx: Context): Result
    local dir = ctx.args[1]
    if not dir then
      input(
        {prompt = "Render the regions into the folder: ", text = "regions", label = "Render the regions"},
        function(text: string)
          if text ~= "" then
            commands.run("render.regions", {text})
          end
        end
      )
      return
    end
    local opts: RenderOptions = {}
    for k, v in pairs(ctx.args as {string | integer: commands.Arg}) do
      if k is string then
        opts[k] = v as RenderValue
      end
    end
    opts.background = (api.ui_attached() or nil) as RenderValue
    local files = M.render_regions(dir as string, opts)
    paw.notify(string.format("rendering %d region%s into %s", #files, #files == 1 and "" or "s", dir as string))
  end,
  {
    desc = "Render every region to a file of its own: `render.regions out` (alone, it asks for the folder), `render.regions out format=flac bits=24`, `render.regions out format=mp3 quality=best`",
  }
)

-- The regions' lane on the ruler ----------------------------------------------------

--
-- Under the bar numbers, a row for each level of the tree of regions (up to
-- `regionlevels`): a region is drawn under the region around it, as a
-- track under its group. Deeper regions share the last row, marked `+`.
-- Markers are on the first row. The lane is a part of `paw.ruler`, so an
-- extension changes its look: `paw.ruler.set_lane("regions", { styles = { level1 = "Title" } })`.

options.define(
  "regionlevels", 3, {}
) -- rows of the regions' lane on the ruler; deeper regions share the last row, marked `+`

local function levels(): integer
  return math.max(1, math.tointeger((options.opt as {string: number}).regionlevels) or 3)
end

--- The row of the regions' lane that a marker or region is on: 0 for the
--- first row (the top level, and the markers).
function M.lane_row(id: integer): integer
  local depth = M.depth(id)
  return depth and math.min(depth, levels()) - 1 or 0
end

local record Label
  x: integer
  text: string
  style: string
end

local function lane_rows(): integer
  if #M.list() == 0 then
    return 0
  end
  local deepest = 1
  for _, node in ipairs(M.walk()) do
    deepest = math.max(deepest, node.depth)
  end
  return math.min(deepest, levels())
end

local function render(ctx: contracts.RulerLaneContext)
  local buf, g, s = ctx.buf, ctx.glyphs, ctx.styles
  local width, last = buf.width, ctx.rows
  local labels: {integer: {Label}} = {}
  local function put(row: integer, label: Label)
    labels[row] = labels[row] or {}
    table.insert(labels[row], label)
  end
  -- Each region as a band on the row of its level, its name where it starts.
  -- A region folded into its column (paw/folds.tl) has the `closed` glyph,
  -- and what is inside it is folded away with it.
  local closed = ctx.closed or function(_: integer): boolean return false end
  local folded = ctx.folded or function(_: number): boolean return false end
  local function hidden(node: Node): boolean
    local up = node.parent
    while up do
      if closed(up.region.id) then
        return true
      end
      up = up.parent
    end
    return folded(node.region.beat)
  end
  for _, node in ipairs(M.walk()) do
    local r = node.region
    if not hidden(node) then
      local row = math.min(node.depth, last) - 1
      local style = node.depth == 1 and s.level1 or node.depth == 2 and s.level2 or s.deep
      local x0, x1 = math.max(0, ctx.x(r.beat)), math.min(width, ctx.x(r.beat + r.length))
      if x1 > x0 then
        buf:fill(x0, row, x1 - x0, 1, " ", style)
      end
      local mark = closed(r.id) and (g.closed or "▸") or #node.children > 0 and g.open or g.start
      put(row, {x = ctx.x(r.beat), text = (node.depth > last and g.deeper or "") .. mark .. M.label(r), style = style})
    end
  end
  for _, m in ipairs(M.list()) do
    if not m.length and not folded(m.beat) then
      put(0, {x = ctx.x(m.beat), text = g.marker .. M.label(m), style = s.marker})
    end
  end
  -- Each name gets the room up to the next one on its row.
  for row, list in pairs(labels) do
    table.sort(list, function(a: Label, b: Label): boolean return a.x < b.x end)
    for i, l in ipairs(list) do
      local stop = width
      for j = i + 1, #list do
        if list[j].x > l.x then
          stop = math.min(stop, list[j].x)
          break
        end
      end
      if l.x >= 0 and l.x < width and stop > l.x then
        local text = l.text
        if api.str_width(text) > stop - l.x then
          text = util.fit(text, stop - l.x)
        end
        buf:text(l.x, row, text, l.style)
      end
    end
  end
end

-- Glyphs: `open` before a region with regions inside (as a group's fold in
-- the track column), `closed` before one folded into its column, `start`
-- before one with none, `deeper` before a region deeper than the last row,
-- `marker` before a marker. Styles: `level1`,
-- `level2`, `deep` (the third level and deeper), `marker`.
paw.ruler.add_lane(
  "regions",
  {
    order = 10,
    rows = lane_rows,
    render = render,
    glyphs = {open = "▾", closed = "▸", start = "▏", deeper = "+", marker = "▼"},
    styles = {level1 = "RulerRegion1", level2 = "RulerRegion2", deep = "RulerRegionDeep", marker = "Marker"},
  }
)

return M
