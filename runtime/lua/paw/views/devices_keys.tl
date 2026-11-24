-- The keys of the devices view (paw/views/devices.tl): the grammar of the
-- graph, with the five modes of `paw.keymap`.
--
-- - Normal mode moves over nodes and changes their values. It adds a node
--   only with `a` (from the picker) and `p` `P` `gp` `gP` (a register).
-- - Insert mode (`i`, `o`, `O`, `c`) adds nodes at a caret on a wire. Each
--   key of `paw.opt.graph_insertkeys` adds one node, and the caret moves
--   past it. All of one insert is one undo step (the keymap joins it).
-- - Visual mode (`v`, `V`, `Ctrl-v`) selects nodes, branches or a block.
-- - After an operator, a motion or a text object says what it acts on.
--
-- The keys act through the seam of the view: its grid (rows are the
-- places of the nodes in the order of the signal), `view:targets` (the
-- nodes that a region names), its tree of places, and `paw.chain` for the
-- edits. Some keys also read the kernel's model, and the model rework of
-- the mix (mix as nodes) must change these reads:
--
-- - `api.chain_get`: `put`, `split_now`, the value keys on a branch, the
--   solo keys and `:zone`.
-- - `api.part_get(part).devices` (the flat list of devices of a part):
--   `put` on a part with no chain, `\b` and the variants of `\a`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local events = require("paw.events")
local devices = require("paw.views.devices")
local layout = require("paw.views.devices_layout")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type objects = require("paw.objects")
local type KeymapModule = require("paw.keymap")

local type Place = devices.Place
local type Region = contracts.Region
local type KeyContext = contracts.KeyContext
local type Kind = contracts.InsertKind

local view = devices.view

-- Helpers ----------------------------------------------------------------------------

--- The handle of the chain of the window's part.
local function owner(): types.ChainOwner
  return {part = view:part_id()}
end

--- The name of the node `id` in a message.
local function name_of(id: integer): string
  local place = view:places()[id]
  return place and place.node.name or tostring(id)
end

--- "1 node", "3 nodes".
local function count_of(n: integer, word: string, words: string): string
  return n .. " " .. (n == 1 and word or words)
end

--- True when the place is the head of a branch.
local function is_branch(place: Place): boolean
  return place ~= nil and place.branch ~= nil and place.branch == place.node.id
end

--- Run `fn`, and show the error of an edit that the kernel refused as a
--- message: the first line, with no trace.
local function try(fn: function()): boolean
  local ok, err = pcall(fn) as (boolean, string)
  if not ok then
    paw.notify(tostring(err):match("^[^\n]*"):gsub("^.-:%d+: ", ""), "warn")
  end
  return ok
end

--- Put the node `id` at `place` in the chain. A part with no chain keeps
--- none while the place is at its top level: the order of its devices
--- gives the place.
local function put(id: integer, place: types.ChainPlace)
  if not place then
    return
  end
  local part = view:part_id()
  if api.chain_get({part = part}) or place.branch then
    api.chain_move({part = part}, id, place)
    return
  end
  local list: {integer} = {}
  for _, other in ipairs(api.part_get(part).devices) do
    if other ~= id then
      list[#list + 1] = other
    end
  end
  for i, other in ipairs(list) do
    if other == place.before then
      return api.device_move(id, part, i)
    elseif other == place.after then
      return api.device_move(id, part, i + 1)
    end
  end
end

--- Add a device of `kind` at `place` (the end of the chain when nil), or
--- the copy of a device (`snap`). Gives its id.
local function add_device(kind: string, place: types.ChainPlace, snap?: objects.DeviceSnapshot): integer
  local part = view:part_id()
  local id = snap and paw.restore_device(snap, part).id or api.device_add(part, kind)
  put(id, place)
  return id
end

--- Add an empty split of `kind` at `place`, as `paw.chain.wrap` makes it
--- around a device that then goes: a split is made around nodes only.
local function add_split(kind: string, place: types.ChainPlace, opts: types.ChainWrapOptions): integer
  local stand_in = add_device("utility", place)
  local id: integer
  local ok, err = pcall(function() id = api.chain_wrap(owner(), {stand_in}, kind, opts) end) as (boolean, string)
  -- The stand-in goes also when the kernel refuses the split (a kind
  -- that no extension defines, a count of branches that the kind does
  -- not take), so that no Utility stays in the chain or the undo step.
  api.device_remove(stand_in)
  if not ok then
    error(err, 0)
  end
  return id
end

--- The split of the chain with the id `id`, as the kernel has it now.
local function split_now(id: integer): types.ChainSplit
  local chain = api.chain_get(owner())
  local found = chain and paw.chain.find(chain, id)
  return found and found.split
end

--- The place in the chain after `at` nodes of the branch `branch` (nil for
--- the top level). Nil at the end of an empty top level.
local function place_at(branch: integer, at: integer): types.ChainPlace
  local items = view:items_of(branch)
  if items[at] then
    return {after = items[at].id}
  elseif items[1] then
    return {before = items[1].id}
  elseif branch then
    return {branch = branch, index = 1}
  end
  return nil
end

--- The place of the node `id` as a caret: its branch, and the nodes before it.
local function caret_of(place: Place): devices.Caret
  if is_branch(place) then
    return {branch = place.node.id, at = 0}
  end
  return {branch = place.branch, at = (place.index or 1) - 1}
end

-- Registers --------------------------------------------------------------------------

local record SplitCopy
  kind: string
  name: string
  mix: number
  values: types.Meta
  branches: {BranchCopy}
end

local record BranchCopy
  name: string
  gain: number
  pan: number
  mute: boolean
  nodes: {Copy}
end

--- A node in a register: a device, a split with its branches, or a branch.
local record Copy
  device: objects.DeviceSnapshot
  split: SplitCopy
  branch: BranchCopy
end

--- What `d` `y` `x` put in a register. Devices alone are the kinds that the
--- inspector writes too (`device`, `devices`), so that each pastes the other's.
local record Taken is KeymapModule.Register
  nodes: {Copy}
  device: objects.DeviceSnapshot
  devices: {objects.DeviceSnapshot}
end

local copy_split: function(s: types.ChainSplit): SplitCopy

local function copy_branch(b: types.ChainBranch): BranchCopy
  local nodes: {Copy} = {}
  for i, n in ipairs(b.nodes) do
    nodes[i] = n.split and {split = copy_split(n.split)} or {device = paw.device(n.device):snapshot()}
  end
  return {name = b.name, gain = b.gain, pan = b.pan, mute = b.mute, nodes = nodes}
end

copy_split = function(s: types.ChainSplit): SplitCopy
  local branches: {BranchCopy} = {}
  for i, b in ipairs(s.branches) do
    branches[i] = copy_branch(b)
  end
  return {kind = s.kind, name = s.name, mix = s.mix, values = s.values, branches = branches}
end

local function copy_of(id: integer): Copy
  local place = view:places()[id]
  if place.device then
    return {device = paw.device(id):snapshot()}
  elseif place.chain_split then
    return {split = copy_split(place.chain_split)}
  end
  local chain = api.chain_get(owner())
  return {branch = copy_branch(paw.chain.find(chain, id).branch)}
end

local function taken(ids: {integer}): Taken
  local nodes: {Copy} = {}
  local snaps: {objects.DeviceSnapshot} = {}
  for i, id in ipairs(ids) do
    nodes[i] = copy_of(id)
    if nodes[i].device then
      snaps[#snaps + 1] = nodes[i].device
    end
  end
  if #snaps == 1 and #nodes == 1 then
    return {kind = "device", device = snaps[1]}
  elseif #snaps == #nodes then
    return {kind = "devices", devices = snaps}
  end
  return {kind = "nodes", nodes = nodes}
end

--- The nodes of a register, or nil when it holds no node.
local function copies_in(value: KeymapModule.Register): {Copy}
  local t = value as Taken
  if not t then
    return nil
  elseif t.kind == "nodes" then
    return t.nodes
  elseif t.kind == "device" then
    return {{device = t.device}}
  elseif t.kind == "devices" then
    local out: {Copy} = {}
    for i, snap in ipairs(t.devices) do
      out[i] = {device = snap}
    end
    return out
  end
end

local paste_list: function(copies: {Copy}, place: types.ChainPlace): {integer}

--- Make the node of `c` at `place`. A branch goes in as its nodes in
--- series. Gives the ids of the nodes made at that level.
local function paste_one(c: Copy, place: types.ChainPlace): {integer}
  if c.device then
    return {add_device(c.device.kind, place, c.device)}
  elseif c.branch then
    return paste_list(c.branch.nodes, place)
  end
  local s = c.split
  local id = add_split(s.kind, place, {branches = #s.branches, name = s.name, values = s.values})
  local made = split_now(id)
  if s.mix then
    api.chain_set(owner(), id, {mix = s.mix})
  end
  for i, b in ipairs(s.branches) do
    local branch = made.branches[i].id
    api.chain_set(owner(), branch, {name = b.name, gain = b.gain, pan = b.pan, mute = b.mute})
    paste_list(b.nodes, {branch = branch, index = 1})
  end
  return {id}
end

paste_list = function(copies: {Copy}, place: types.ChainPlace): {integer}
  local out: {integer} = {}
  for _, c in ipairs(copies) do
    for _, id in ipairs(paste_one(c, place)) do
      out[#out + 1] = id
      place = {after = id}
    end
  end
  return out
end

-- Targets of an operator ---------------------------------------------------------

--- The nodes that an operator acts on. The operator's own key again (`dd`,
--- `3dd`) takes the node and the nodes after it in series, as many as the
--- count; on the head of a branch, the branch.
local function targets(reg: Region): {integer}
  if reg.kind == "line" and not reg.visual and not reg.object then
    local place = view:node()
    if not place then
      return {}
    end
    if is_branch(place) then
      return {place.node.id}
    end
    local list = view:siblings(place)
    local out: {integer} = {}
    local n = math.tointeger(reg.r1 - reg.r0 + 1)
    for i = place.index or 1, math.min(#list, (place.index or 1) + n - 1) do
      out[#out + 1] = list[i]
    end
    return out
  end
  return view:targets(reg)
end

--- The words of what `ids` are, for a message: one name, or a count.
local function what(ids: {integer}): string
  if #ids == 1 then
    return name_of(ids[1])
  end
  local branches = 0
  for _, id in ipairs(ids) do
    if is_branch(view:places()[id]) then
      branches = branches + 1
    end
  end
  if branches == #ids then
    return count_of(#ids, "branch", "branches")
  end
  return count_of(#ids, "node", "nodes")
end

--- Remove the nodes `ids` from the chain: a device, a container with its
--- devices, a branch with its devices.
local function remove(ids: {integer})
  for _, id in ipairs(ids) do
    local place = view:places()[id]
    if place and place.device then
      api.device_remove(id)
    elseif place then
      api.chain_remove(owner(), id)
    end
  end
end

--- Cut `ids` into the register of `ctx`, and say so. False when there is
--- nothing to cut.
local function cut(ids: {integer}, ctx: KeyContext, verb: string): boolean
  if #ids == 0 then
    paw.notify("nothing here to " .. verb, "warn")
    return false
  end
  local words = what(ids)
  paw.keymap.setreg(taken(ids), ctx and ctx.register)
  -- The cursor goes to the node that takes their place: the next in
  -- series, else the one before, else the container around them.
  local place = view:places()[ids[1]]
  local list: {integer} = {}
  if not is_branch(place) then
    list = view:siblings(place)
  end
  local first, last = 0, 0
  for i, id in ipairs(list) do
    if id == ids[1] then
      first = i
    end
    if id == ids[#ids] then
      last = i
    end
  end
  local next_id = list[last + 1] or list[first - 1] or place.split
  remove(ids)
  view.cursor = next_id
  paw.notify(verb == "cut" and ("cut " .. words) or (verb .. " " .. words))
  return true
end

-- Motions ----------------------------------------------------------------------------

local function map(lhs: string, fn: function(ctx: KeyContext), desc: string, opts?: KeymapModule.MapOptions)
  local o: KeymapModule.MapOptions = opts or {}
  o.view, o.desc = "devices", desc
  paw.keymap.set(lhs, fn, o)
end

local function motion(lhs: string, fn: function(ctx: KeyContext), desc: string)
  map(lhs, fn, desc, {motion = true})
end

--- The place of the cursor in the list of stops.
local function stop_index(stops: {integer}): integer
  view:node()
  for i, id in ipairs(stops) do
    if id == view.cursor then
      return i
    end
  end
  return 1
end

--- Move the cursor `n` stops along the signal (back when `n` is negative).
local function step(n: integer): function(ctx: KeyContext)
  return function(ctx: KeyContext)
    local stops = view:stops()
    local to = math.tointeger(util.clamp(stop_index(stops) + n * (ctx.count or 1), 1, #stops))
    if stops[to] then
      view:go(stops[to])
    end
  end
end

--- Move the cursor to the branch below (or above) in the split around it,
--- at the same place in that branch. In a narrow window, the next row.
local function across(n: integer): function(ctx: KeyContext)
  local along = step(n)
  return function(ctx: KeyContext)
    local places = view:places()
    local place = view:node()
    if not place or (view.geometry and view.geometry.width or layout.FLOW) < layout.FLOW then
      return along(ctx)
    end
    -- Up from the cursor to the innermost split with more than one
    -- branch, with the place of the cursor's line in its branch (0 for
    -- the branch's head).
    local index = is_branch(place) and 0 or (place.index or 0)
    local p = place
    while p and p.branch do
      local split = places[p.split]
      if split and split.node.kind == "split" and #split.node.branches > 1 then
        local branches = split.node.branches
        local at = 1
        for i, b in ipairs(branches) do
          if b.id == p.branch then
            at = i
          end
        end
        local to = branches[math.tointeger(util.clamp(at + n * (ctx.count or 1), 1, #branches))]
        local item = index > 0 and to.items[math.min(index, #to.items)] or nil
        return view:go(item and item.id or to.id)
      end
      index = split and split.index or 0
      p = split
    end
    along(ctx)
  end
end

--- The container (a split or a rack) that holds the cursor, `levels` out.
local function container_around(id: integer, levels: integer): Place
  local places = view:places()
  local place = places[id]
  local found: Place
  for _ = 1, levels do
    local up = place and place.split and places[place.split]
    if not up then
      break
    end
    found, place = up, up
  end
  return found
end

--- The last stop inside the node `id`, or its own stop.
local function last_inside(stops: {integer}, id: integer): integer
  local places = view:places()
  local at = 0
  for i, other in ipairs(stops) do
    if other == id then
      at = i
    end
  end
  local last = at
  for i = at + 1, #stops do
    local p = places[stops[i]]
    local inside = false
    while p do
      if p.node.id == id then
        inside = true
        break
      end
      local up = (p.branch and p.branch ~= p.node.id) and p.branch or p.split
      p = up and places[up]
    end
    if not inside then
      break
    end
    last = i
  end
  return last
end

motion("l", step(1), "The next node along the signal")
motion("h", step(-1), "The node before along the signal")
motion("w", step(1), "The next node")
motion("b", step(-1), "The node before")
motion("<Right>", step(1), "The next node along the signal")
motion("<Left>", step(-1), "The node before along the signal")
motion("j", across(1), "The branch below, or the next row in a narrow window")
motion("k", across(-1), "The branch above, or the row before in a narrow window")
motion("<Down>", across(1), "The branch below")
motion("<Up>", across(-1), "The branch above")
motion(
  "gg",
  function()
    local stops = view:stops()
    if stops[1] then
      view:go(stops[1])
    end
  end,
  "The first node"
)
motion(
  "G",
  function()
    local stops = view:stops()
    if #stops > 0 then
      view:go(stops[#stops])
    end
  end,
  "The last node"
)

--- A motion to a node of the cursor's branch: `pick(list)` chooses it.
local function in_branch(pick: function(list: {integer}): integer): function(ctx: KeyContext)
  return function()
    local place = view:node()
    if not place then
      return
    end
    local list = is_branch(place) and {} or view:siblings(place)
    if is_branch(place) then
      for _, node in ipairs(view:items_of(place.node.id)) do
        list[#list + 1] = node.id
      end
    end
    local id = pick(list)
    if id then
      view:go(id)
    end
  end
end

motion("^", in_branch(function(list: {integer}): integer return list[1] end), "The first node of the branch")
motion("$", in_branch(function(list: {integer}): integer return list[#list] end), "The last node of the branch")
motion(
  "e",
  in_branch(
    function(list: {integer}): integer
      for i = #list, 1, -1 do
        if view:places()[list[i]].device then
          return list[i]
        end
      end
    end
  ),
  "The last device of the branch"
)
motion(
  "0",
  function()
    local place = view:node()
    local up = place and place.split and view:places()[place.split]
    if up then
      view:go(up.node.id)
    end
  end,
  "The split at the start of the branch"
)
motion(
  "%",
  function()
    local place = view:node()
    if not place then
      return
    end
    -- On a split: its last node. Inside one: the split.
    if place.chain_split then
      local stops = view:stops()
      return view:go(stops[last_inside(stops, place.node.id)])
    end
    local up = container_around(place.node.id, 1)
    if up then
      view:go(up.node.id)
    end
  end,
  "From a split to its last node, and back"
)
motion(
  "[(",
  function(ctx: KeyContext)
    local up = view.cursor and container_around(view.cursor, ctx.count or 1)
    if up then
      view:go(up.node.id)
    end
  end,
  "The split or rack around the cursor"
)
motion(
  "])",
  function(ctx: KeyContext)
    local up = view.cursor and container_around(view.cursor, ctx.count or 1)
    if up then
      local stops = view:stops()
      view:go(stops[last_inside(stops, up.node.id)])
    end
  end,
  "The last node of the split or rack around the cursor"
)

-- Folds and scopes -----------------------------------------------------------------

--- The container that a fold key acts on: the node under the cursor when
--- it is one, else the container around it.
local function container(): Place
  local place = view:node()
  if place and place.chain_split then
    return place
  end
  return place and container_around(place.node.id, 1)
end

--- Whether the container `id` is open now.
local function is_open(id: integer): boolean
  local chosen = view.open[id]
  if chosen ~= nil then
    return chosen
  end
  for _, place in ipairs(view:path()) do
    if place.node.id == id and id ~= view.cursor then
      return true
    end
  end
  return id == view.scope
end

local function fold(want: string): function()
  return function()
    local place = container()
    if not place then
      return paw.notify("no split or rack here")
    end
    local id = place.node.id
    local open = want == "toggle" and not is_open(id) or want == "open"
    view.open[id] = open
    -- A fold over the cursor moves the cursor to the container.
    if not open then
      view.cursor = id
    end
    paw.notify((open and "opened " or "folded ") .. place.node.name)
    api.ui_redraw()
  end
end

map("za", fold("toggle"), "Fold or open the split or rack")
map("zo", fold("open"), "Open the split or rack")
map("zc", fold("close"), "Fold the split or rack")
map(
  "zR",
  function()
    for id, place in pairs(view:places()) do
      if place.chain_split then
        view.open[id] = true
      end
    end
    paw.notify("opened every split and rack")
    api.ui_redraw()
  end,
  "Open every split and rack"
)
map(
  "zM",
  function()
    view.open = {}
    for _, place in pairs(view:places()) do
      if place.chain_split then
        view.open[place.node.id] = false
      end
    end
    -- The cursor goes to the top-level node that holds it.
    local path = view:path()
    if path[1] then
      view.cursor = path[1].node.id
    end
    paw.notify("folded every split and rack")
    api.ui_redraw()
  end,
  "Fold every split and rack"
)

--- Show only the container `id` in the window, with the path at the top.
local function enter(id: integer)
  -- The container opens: the window shows what is inside it.
  view.scope, view.cursor = id, id
  view.open[id] = true
  paw.notify("in " .. name_of(id) .. " · `zW` goes out")
  api.ui_redraw()
end

local function widen()
  if not view.scope then
    return paw.notify("the window shows the whole chain")
  end
  local id = view.scope
  view.scope = nil
  view.cursor = id
  paw.notify("the whole chain")
  api.ui_redraw()
end
map("zW", widen, "Show the whole chain again")
map("zw", widen, "Show the whole chain again")

-- Text objects ---------------------------------------------------------------------

--- A region that names the nodes `ids` outright, over the rows from the
--- first to the last stop inside them.
local function object_of(ids: {integer}): Region
  if #ids == 0 then
    return nil
  end
  local stops = view:stops()
  local set: {integer: boolean} = {}
  local first, last = math.huge, 0
  for _, id in ipairs(ids) do
    set[id] = true
    for i, other in ipairs(stops) do
      if other == id then
        first = math.min(first, i)
        last = math.max(last, last_inside(stops, id))
      end
    end
  end
  if last == 0 then
    first, last = stop_index(stops), stop_index(stops)
  end
  return {view = "devices", kind = "char", r0 = first, r1 = last, c0 = 0, c1 = 0, object = true, nodes = set}
end

--- The branch around the cursor (the cursor's own on a head), `levels` out.
local function branch_around(levels: integer): Place
  local places = view:places()
  local place = view:node()
  local found: Place
  local n = 0
  while place and n < levels do
    local branch = is_branch(place) and place or (place.branch and places[place.branch])
    if not branch then
      break
    end
    found, n = branch, n + 1
    place = places[branch.split]
  end
  return found
end

--- The split (or the rack, with `rack`) under or around the cursor, `levels` out.
local function split_around(rack: boolean, levels: integer): Place
  local places = view:places()
  local place = view:node()
  local found: Place
  local n = 0
  while place and n < levels do
    if place.chain_split and (place.node.kind == "rack") == rack then
      found, n = place, n + 1
    end
    place = place.split and places[place.split]
  end
  return found
end

local function textobject(lhs: string, fn: function(ctx: KeyContext): Region, desc: string)
  paw.keymap.textobject(lhs, fn, {view = "devices", desc = desc})
end

textobject(
  "in",
  function(): Region local place = view:node(); return place and object_of({place.node.id}) end,
  "The node: a device, or a container with its inside"
)
textobject(
  "ab",
  function(ctx: KeyContext): Region
    local branch = branch_around(ctx.count or 1)
    return branch and object_of({branch.node.id})
  end,
  "The branch: its head and its nodes"
)
textobject(
  "ib",
  function(ctx: KeyContext): Region
    local branch = branch_around(ctx.count or 1)
    local ids: {integer} = {}
    for _, node in ipairs(branch and view:items_of(branch.node.id) or {}) do
      ids[#ids + 1] = node.id
    end
    return object_of(ids)
  end,
  "The nodes of the branch"
)

--- The text objects of a container: `a` the container, `i` its inside.
local function containers(letter: string, rack: boolean, word: string)
  textobject(
    "a" .. letter,
    function(ctx: KeyContext): Region
      local place = split_around(rack, ctx.count or 1)
      return place and object_of({place.node.id})
    end,
    "The " .. word .. ", with its inside"
  )
  textobject(
    "i" .. letter,
    function(ctx: KeyContext): Region
      local place = split_around(rack, ctx.count or 1)
      if not place then
        return nil
      end
      local ids: {integer} = {}
      for _, b in ipairs(place.node.branches) do
        if rack then
          for _, node in ipairs(b.items) do
            ids[#ids + 1] = node.id
          end
        else
          ids[#ids + 1] = b.id
        end
      end
      return object_of(ids)
    end,
    "The inside of the " .. word
  )
end
containers("s", false, "split")
containers("r", true, "rack")

textobject(
  "ie",
  function(): Region
    local ids: {integer} = {}
    for _, node in ipairs(view:items_of(nil)) do
      ids[#ids + 1] = node.id
    end
    return object_of(ids)
  end,
  "The entire chain"
)
textobject(
  "im",
  function(): Region
    local place = container()
    local ids: {integer} = {}
    for _, link in ipairs(place and place.chain_split.links or {}) do
      ids[#ids + 1] = link.device
    end
    if #ids == 0 then
      paw.notify("no macro of this container moves a device", "warn")
    end
    return object_of(ids)
  end,
  "The devices that the macros of the container move"
)

-- Operators --------------------------------------------------------------------------

local function operator(
  lhs: string, fn: function(reg: Region, ctx: KeyContext), desc: string, opts?: KeymapModule.MapOptions
)
  local o: KeymapModule.MapOptions = opts or {}
  o.view, o.desc = "devices", desc
  paw.keymap.operator(lhs, fn, o)
end

--- True when the key after the operator was `s`: it did its own work
--- (`ds`, `cs`), and the cursor that it moved names no region.
local function surround(ctx: KeyContext): boolean
  return ctx ~= nil and ctx.keys == "s"
end

operator(
  "d",
  function(reg: Region, ctx: KeyContext)
    if not surround(ctx) then
      cut(targets(reg), ctx, "cut")
    end
  end,
  "Cut nodes into a register"
)
operator(
  "y",
  function(reg: Region, ctx: KeyContext)
    local ids = targets(reg)
    if #ids == 0 then
      return paw.notify("nothing here to copy", "warn")
    end
    paw.keymap.setreg(taken(ids), ctx and ctx.register, true)
    paw.notify("copied " .. what(ids))
  end,
  "Copy nodes into a register"
)

-- Insert mode ------------------------------------------------------------------------

--- What one insert made, newest last, for `<BS>` and the message at its end.
local record Made
  id: integer
  split: boolean
  caret: devices.Caret
end
local made: {Made} = {}
local typed_count: integer

--- The node that the picker adds goes here: the part and the place, and
--- whether insert mode moves its caret past it.
local record Adding
  part: integer
  place: types.ChainPlace
  insert: boolean
end
local adding: Adding

--- Start insert mode with the caret at `caret`.
local function start_insert(caret: devices.Caret)
  made, typed_count = {}, nil
  paw.keymap.set_mode("i")
  view.wire_caret = caret
  api.ui_redraw()
end

--- The place of the caret in the chain.
local function caret_place(): types.ChainPlace
  return place_at(view.wire_caret.branch, view.wire_caret.at)
end

--- Note a node that insert mode made, and move the caret past it, or into
--- the first branch of a container.
local function inserted(id: integer, split: boolean)
  made[#made + 1] = {id = id, split = split, caret = {branch = view.wire_caret.branch, at = view.wire_caret.at}}
  local s = split and split_now(id)
  if s then
    view.wire_caret = {branch = s.branches[1].id, at = 0}
  else
    view.wire_caret = {branch = view.wire_caret.branch, at = view.wire_caret.at + 1}
  end
  view.cursor = id
end

--- Open the device picker; the device chosen goes at `place`.
--- The place goes when the picker closes with no choice, so that a later
--- add in another view does not go there.
local function pick_at(place: types.ChainPlace, insert: boolean)
  adding = {part = view:part_id(), place = place, insert = insert}
  local source = paw.pick.sources:get("devices") as contracts.PickSource<contracts.PickInfo>
  local spec: contracts.PickSource<contracts.PickInfo> = setmetatable(
    {
      on_cancel = function()
        adding = nil
        if source.on_cancel then
          source.on_cancel()
        end
      end,
    } as contracts.PickSource<contracts.PickInfo>,
    {__index = source} as metatable<contracts.PickSource<contracts.PickInfo>>
  )
  paw.pick(spec)
end

-- The device that the picker added goes to the place chosen, in the same
-- step as the add.
events.on(
  events.event("device.added_by_hand") as events.Event<{string: integer}>,
  function(e: {string: integer})
    local want = adding
    adding = nil
    if not (want and e.id and api.device_get(e.id).part == want.part) then
      return
    end
    put(e.id, want.place)
    if want.insert and view.wire_caret then
      inserted(e.id, false)
    end
  end
)

--- The kinds of split of the letters of `gs` and `cs`.
local SPLIT_LETTERS: {string: string} = {
  r = "chain", l = "layer", b = "band", m = "ms", s = "lr", k = "key", v = "vel", x = "select", o = "outs"
}

operator(
  "c",
  function(reg: Region, ctx: KeyContext)
    if surround(ctx) then
      return
    end
    local ids = targets(reg)
    -- `cc` on one node: a preset, or a name.
    if ctx.keys == "cc" and #ids == 1 then
      local place = view:places()[ids[1]]
      if place.device then
        paw.cmd("preset")
        return
      end
      local now = place.chain_split and place.chain_split.name or place.node.name
      paw.ui.input(
        {prompt = "Name: ", text = now},
        function(text: string)
          if text ~= "" then
            try(function() paw.chain.set(owner(), ids[1], {name = text}) end)
          end
        end
      )
      return
    end
    if #ids == 0 then
      return paw.notify("nothing here to change", "warn")
    end
    local first = view:places()[ids[1]]
    local caret = caret_of(first)
    -- A branch keeps its head: what goes is its nodes.
    if is_branch(first) and #ids == 1 then
      ids = {}
      for _, node in ipairs(view:items_of(first.node.id)) do
        ids[#ids + 1] = node.id
      end
      if #ids > 0 then
        cut(ids, ctx, "changed")
      end
    else
      cut(ids, ctx, "changed")
    end
    start_insert(caret)
    pick_at(caret_place(), true)
  end,
  "Change: cut, then insert at its place from the picker; cc a preset or a name"
)

--- Move the nodes `ids` (in a row of one branch) `n` places later in the
--- signal, earlier when `n` is negative. At the end of a branch they go out
--- of the split. Says what it did.
local function shift(ids: {integer}, n: integer)
  if #ids == 0 then
    return
  end
  local places = view:places()
  if is_branch(places[ids[1]]) then
    return paw.notify("`<A-j>` `<A-k>` move a node to another branch; `>` `<` move nodes along the signal", "warn")
  end
  local moved = 0
  for _ = 1, math.abs(n) do
    local place = view:places()[ids[1]]
    local list = view:siblings(place)
    local first, last = 0, 0
    for i, id in ipairs(list) do
      if id == ids[1] then
        first = i
      end
      if id == ids[#ids] then
        last = i
      end
    end
    local ok = try(
      function()
        if n > 0 and list[last + 1] then
          put(list[last + 1], {before = ids[1]})
        elseif n < 0 and first > 1 then
          put(list[first - 1], {after = ids[#ids]})
        elseif place.split then
          -- Out of the split, after it or before it.
          for k = 1, #ids do
            local id = n > 0 and ids[#ids - k + 1] or ids[k]
            put(id, n > 0 and {after = place.split} or {before = place.split})
          end
        else
          error((n > 0 and "the end" or "the start") .. " of the chain", 0)
        end
      end
    )
    if not ok then
      break
    end
    moved = moved + 1
  end
  if moved > 0 then
    paw.notify(string.format("moved %s %s", what(ids), n > 0 and "later" or "earlier"))
  end
end

--- What `>` and `<` move: the node alone when the key is doubled (`3>>`
--- moves it three places), else what the region names.
local function shifted(reg: Region): {integer}
  if reg.kind == "line" and not reg.visual and not reg.object then
    local place = view:node()
    return place and {place.node.id} or {}
  end
  return targets(reg)
end

operator(
  ">",
  function(reg: Region, ctx: KeyContext) shift(shifted(reg), ctx.op_count or 1) end,
  "Move nodes later in the signal",
  {count = "operator"}
)
operator(
  "<lt>",
  function(reg: Region, ctx: KeyContext) shift(shifted(reg), -(ctx.op_count or 1)) end,
  "Move nodes earlier in the signal",
  {count = "operator"}
)

--- Every device in `ids` and inside the containers and branches of `ids`.
local function devices_in(ids: {integer}): {integer}
  local out: {integer} = {}
  local function walk(nodes: {layout.Node})
    for _, node in ipairs(nodes) do
      if node.kind == "device" then
        out[#out + 1] = node.id
      else
        for _, b in ipairs(node.branches) do
          walk(b.items)
        end
      end
    end
  end
  for _, id in ipairs(ids) do
    local place = view:places()[id]
    if is_branch(place) then
      walk(view:items_of(id))
    elseif place then
      walk({place.node})
    end
  end
  return out
end

operator(
  "gc",
  function(reg: Region)
    local ids = targets(reg)
    local all = devices_in(ids)
    if #all == 0 and #ids == 0 then
      return paw.notify("nothing here to bypass", "warn")
    end
    -- A branch mutes; a device or a container bypasses its devices.
    local any_on = false
    for _, id in ipairs(all) do
      any_on = any_on or not api.device_get(id).bypass
    end
    for _, id in ipairs(ids) do
      local place = view:places()[id]
      if is_branch(place) then
        local muted = paw.chain.find(api.chain_get(owner()), id).branch.mute
        api.chain_set(owner(), id, {mute = not muted})
      end
    end
    for _, id in ipairs(all) do
      if not is_branch(view:places()[id]) then
        api.device_set(id, {bypass = any_on})
      end
    end
    paw.notify((any_on and "bypassed " or "playing again: ") .. what(ids))
  end,
  "Bypass nodes, or mute branches; again lets them play",
  {role = "mute"}
)

--- The peak of the node `id` as the engine measured it last, linear.
local function peak(id: integer): number
  local ok, meters = pcall(paw.chain.meters, owner()) as (boolean, types.ChainMeters)
  return ok and meters.peaks[id] or 0
end

operator(
  "=",
  function(reg: Region)
    local done = 0
    for _, id in ipairs(devices_in(targets(reg))) do
      local place = view:places()[id]
      local list = view:siblings(place)
      local before = list[(place.index or 1) - 1]
      local input, output = before and peak(before) or 0, peak(id)
      if input > 0 and output > 0 then
        local d = api.device_get(id)
        local gain = (d.params.fx_gain or 0) + 20 * math.log10(input / output)
        api.device_set_param(id, "fx_gain", util.clamp(gain, -60, 24))
        done = done + 1
      end
    end
    if done == 0 then
      return paw.notify(
        "play the song first: `=` sets the output gain from what the device and the one before it played", "warn"
      )
    end
    paw.notify("matched the gain of " .. count_of(done, "device", "devices"))
  end,
  "Match the output gain of devices to their input, from what played"
)

--- Ask for the letter of a kind of split (and a count of branches before
--- it), then call `fn` with the kind and the count.
local function ask_kind(fn: function(kind: string, branches: integer))
  local digits = ""
  paw.notify("kind of split: r rack, l layer, b band, m mid/side, s left/right, k key, v velocity, x select, o outs")
  paw.ui.grabber = function(key: string)
    if key:match("^%d$") then
      digits = digits .. key
      return
    end
    paw.ui.grabber = nil
    local kind = SPLIT_LETTERS[key]
    if not kind then
      if key ~= "<Esc>" then
        paw.notify("`" .. key .. "` names no kind of split", "warn")
      end
      return
    end
    fn(kind, math.tointeger(tonumber(digits)))
  end
end

--- Wrap `ids` in a split of `kind`; a rack asks for its name.
local function wrap(ids: {integer}, kind: string, branches: integer)
  local function make(name: string)
    try(
      function()
        local done = paw.chain.wrap(owner(), ids, kind, {branches = branches, name = name})
        view.cursor = done.id
      end
    )
  end
  if kind == "chain" then
    return paw.ui.input({prompt = "Rack name: ", text = "Rack"}, make)
  end
  make(nil)
end

operator(
  "gs",
  function(reg: Region)
    local ids = targets(reg)
    if #ids == 0 then
      return paw.notify("nothing here to wrap", "warn")
    end
    ask_kind(function(kind: string, branches: integer) wrap(ids, kind, branches) end)
  end,
  "Wrap nodes in a split: then its letter, r l b m s k v x o"
)

--- The container around the node `id` that a macro goes on, or nil with a message.
local function macro_home(id: integer): Place
  local place = view:places()[id]
  local up = place and (place.chain_split and is_branch(place) and place or container_around(id, 1))
  if not up then
    paw.notify("a macro belongs to a split or a rack: wrap the nodes first (`gs`)", "warn")
  end
  return up
end

--- The first parameter of a device that is its own (not the wet mix or
--- the output gain of the host).
local function main_param(id: integer): types.ParamInfo
  for _, p in ipairs(api.device_get(id).param_info or {}) do
    if p.key ~= "fx_wet" and p.key ~= "fx_gain" then
      return p
    end
  end
end

operator(
  "gm",
  function(reg: Region)
    local all = devices_in(targets(reg))
    local home = all[1] and macro_home(all[1])
    if not home then
      return
    end
    local s = home.chain_split
    local macro = s.macros and s.macros[1] and s.macros[1].id or api.chain_macro_add(owner(), s.id, "Macro 1")
    local linked = 0
    for _, id in ipairs(all) do
      local p = main_param(id)
      if p then
        api.chain_link(owner(), macro, id, p.key, 0.25)
        linked = linked + 1
      end
    end
    paw.notify(
      string.format(
        "linked %s to the macro of %s at 25 %%",
        count_of(linked, "device", "devices"),
        s.name ~= "" and s.name or s.kind
      )
    )
  end,
  "Modulate: link the macro of the container to the main parameter of each device"
)
operator(
  "gM",
  function(reg: Region)
    local all = devices_in(targets(reg))
    local home = all[1] and macro_home(all[1])
    local p = all[1] and main_param(all[1])
    if not (home and p) then
      return
    end
    local macro = api.chain_macro_add(owner(), home.chain_split.id, p.name)
    local linked = 0
    for _, id in ipairs(all) do
      for _, other in ipairs(api.device_get(id).param_info or {}) do
        if other.key == p.key then
          api.chain_link(owner(), macro, id, p.key, 1)
          linked = linked + 1
        end
      end
    end
    paw.notify(string.format("made the macro %s of %s", p.name, count_of(linked, "device", "devices")))
  end,
  "Make the main parameter of the devices a macro of their container"
)
operator(
  "zf",
  function(reg: Region)
    local folded = 0
    for _, id in ipairs(targets(reg)) do
      if view:places()[id].chain_split then
        view.open[id], folded = false, folded + 1
      end
    end
    paw.notify(
      folded == 0 and "no split or rack there to fold" or ("folded " .. count_of(folded, "container", "containers"))
    )
    api.ui_redraw()
  end,
  "Fold the containers that a motion covers",
  {repeatable = false}
)
operator(
  "zn",
  function(reg: Region, ctx: KeyContext)
    local home: Place
    if ctx.keys == "znn" then
      home = container()
    else
      for _, id in ipairs(targets(reg)) do
        home = home or (view:places()[id].chain_split and view:places()[id])
      end
    end
    if not home then
      return paw.notify("no split or rack there to enter", "warn")
    end
    enter(home.node.id)
  end,
  "Enter a split or rack: the window shows only its inside",
  {repeatable = false}
)

-- Normal-mode keys ----------------------------------------------------------------

--- The node under the cursor, or nil with a message.
local function here(): Place
  local place = view:node()
  if not place then
    paw.notify("no devices: `a` adds one", "warn")
  end
  return place
end

map(
  "<CR>",
  function()
    if here() then
      paw.ui.focus("inspector")
    end
  end,
  "Go to the inspector of the node"
)
map("<localleader>p", function() paw.cmd("devices.pin") end, "Pin the view to its part, or follow the cursor again")
map("s", function() paw.cmd("part.solo") end, "Solo the part")
map("M", function() paw.cmd("part.mute") end, "Mute the part")
map(
  "x",
  function(ctx: KeyContext)
    local place = here()
    if place then
      cut({place.node.id}, ctx, "cut")
    end
  end,
  "Cut the node into a register"
)
map(
  "~",
  function()
    local place = here()
    if not place then
      return
    end
    local all = devices_in({place.node.id})
    local on = false
    for _, id in ipairs(all) do
      on = on or not api.device_get(id).bypass
    end
    for _, id in ipairs(all) do
      api.device_set(id, {bypass = on})
    end
    paw.notify((on and "bypassed " or "playing again: ") .. place.node.name)
  end,
  "Bypass the node, or let it play"
)

--- Paste the register of `ctx` beside the cursor: after or before it in
--- series, or (`branch`) as a new branch below or above.
local function paste(before: boolean, branch: boolean): function(ctx: KeyContext)
  return function(ctx: KeyContext)
    local copies = copies_in(paw.keymap.getreg(ctx.register))
    if not copies then
      return paw.notify("no node in the register: `yy` or `dd` on one first", "warn")
    end
    local place = view:node()
    local at: types.ChainPlace
    try(
      function()
        if branch and place then
          local new = (place.split and not (view:places()[place.split].node.kind == "rack")) and place or nil
          local split = new and new.split
          if not split then
            -- Out of a split: the node goes into branch 1 of a new layer.
            split = paw.chain.wrap(owner(), {place.node.id}, "layer", {branches = 1}).id
          end
          local index: integer
          for i, b in ipairs(split_now(split).branches) do
            if b.id == (place.branch or -1) then
              index = before and i or i + 1
            end
          end
          local id = api.chain_branch_add(owner(), split, {index = index or (before and 1 or nil)})
          at = {branch = id, index = 1}
        elseif place and is_branch(place) then
          at = {branch = place.node.id, index = 1}
        elseif place then
          at = before and {before = place.node.id} or {after = place.node.id}
        end
        local ids: {integer} = {}
        for _ = 1, ctx.count or 1 do
          for _, id in ipairs(paste_list(copies, at)) do
            ids[#ids + 1] = id
            at = {after = id}
          end
        end
        view.cursor = ids[1]
        paw.notify("pasted " .. what(ids))
      end
    )
  end
end
map("p", paste(false, false), "Paste the register after the node")
map("P", paste(true, false), "Paste the register before the node")
map("gp", paste(false, true), "Paste the register as a new branch below")
map("gP", paste(true, true), "Paste the register as a new branch above")

map(
  "a",
  function()
    local place = view:node()
    local at = place and (is_branch(place) and {branch = place.node.id, index = 1} or {after = place.node.id})
    if not view:part_id() then
      return paw.notify("no part here", "warn")
    end
    pick_at(at, false)
  end,
  "Add a device after the node, from the picker"
)
map(
  "i",
  function()
    if not view:part_id() then
      return paw.notify("no part here", "warn")
    end
    local place = view:node()
    start_insert(place and caret_of(place) or {at = #view:items_of(nil)})
  end,
  "Insert nodes before the node"
)

--- Add a branch beside the cursor's (below, or above with `above`) and
--- start insert mode in it. Out of a split, the node goes into branch 1 of
--- a new layer first.
local function open_branch(above: boolean): function()
  return function()
    local place = here()
    if not place then
      return
    end
    try(
      function()
        local places = view:places()
        local in_split = place.split and places[place.split].node.kind == "split"
        local split = place.chain_split and place.node.kind == "split" and place.node.id or (in_split and place.split)
        local index: integer
        if not split then
          split = paw.chain.wrap(owner(), {place.node.id}, "layer", {branches = 1}).id
          index = above and 1 or 2
        elseif split == place.split then
          for i, b in ipairs(split_now(split).branches) do
            if b.id == place.branch then
              index = above and i or i + 1
            end
          end
        else
          index = above and 1 or nil
        end
        local id = api.chain_branch_add(owner(), split, {index = index})
        paw.notify("added a branch to " .. name_of(split))
        view.cursor = id
        start_insert({branch = id, at = 0})
      end
    )
  end
end
map("o", open_branch(false), "Add a branch below, and insert in it")
map("O", open_branch(true), "Add a branch above, and insert in it")

--- `ds`: unwrap the split around the cursor. The branch of the cursor
--- stays; the others go into the register.
local function unwrap_here(register: string)
  local place = here()
  local up = place and (is_branch(place) and view:places()[place.split] or container_around(place.node.id, 1))
  if not up then
    return paw.notify("no split around the cursor", "warn")
  end
  local keep = is_branch(place) and place.node.id or place.branch
  while keep and view:places()[keep].split ~= up.node.id do
    keep = view:places()[view:places()[keep].split].branch
  end
  local others: {integer} = {}
  for _, b in ipairs(up.node.branches) do
    if b.id ~= keep then
      others[#others + 1] = b.id
    end
  end
  if #others > 0 then
    paw.keymap.setreg(taken(others), register)
  end
  try(function() paw.chain.unwrap(owner(), up.node.id, keep) end)
end

--- `cs{kind}`: change the kind of the split under or around the cursor.
local function change_kind()
  local place = container()
  if not place then
    return paw.notify("no split here", "warn")
  end
  ask_kind(function(kind: string) try(function() paw.chain.set(owner(), place.node.id, {kind = kind}) end) end)
end

-- `s` after `d` or `c` is the split around the cursor, as vim-surround
-- has it. It is a key of the mode after an operator, so that `d` and `c`
-- start that mode at once and the status line says PENDING.
paw.keymap.set(
  "s",
  function(ctx: KeyContext)
    local op = paw.keymap.motion_for
    if op and op.lhs == "d" then
      unwrap_here(ctx.register)
    elseif op and op.lhs == "c" then
      change_kind()
    else
      paw.notify("`s` follows `d` (unwrap) or `c` (change the kind of the split)", "warn")
    end
  end,
  {mode = "o", view = "devices", desc = "ds unwraps the split around the cursor; cs{kind} changes its kind"}
)

--- Move the node under the cursor to the branch `n` below (above when
--- negative), at the same place.
local function to_branch(n: integer): function()
  return function()
    local place = here()
    local up = place and place.split and view:places()[place.split]
    if not up or is_branch(place) or up.node.kind ~= "split" then
      return paw.notify("the node is in no split with other branches", "warn")
    end
    local branches = up.node.branches
    local at = 1
    for i, b in ipairs(branches) do
      if b.id == place.branch then
        at = i
      end
    end
    local to = branches[at + n]
    if not to then
      return paw.notify(n > 0 and "the last branch" or "the first branch", "warn")
    end
    try(function() paw.chain.move(owner(), place.node.id, {branch = to.id, index = place.index}) end)
  end
end
map("<A-j>", to_branch(1), "Move the node to the branch below")
map("<A-k>", to_branch(-1), "Move the node to the branch above")

-- Value keys ----------------------------------------------------------------------

--- Change the main value (`main`) or the second value of the node `id` by
--- `steps` steps. Gives the words of the change.
local function nudge(id: integer, main: boolean, steps: integer): string
  local place = view:places()[id]
  if place.device then
    local key = main and "fx_wet" or "fx_gain"
    local now = api.device_get(id).params[key] or (main and 100 or 0)
    local value = main and util.clamp(now + 5 * steps, 0, 100) or util.clamp(now + steps, -60, 24)
    api.device_set_param(id, key, value)
    return string.format(main and "%s mix %d %%" or "%s out %.1f dB", place.node.name, math.floor(value + 0.5))
  elseif is_branch(place) then
    local b = paw.chain.find(api.chain_get(owner()), id).branch
    if main then
      api.chain_set(owner(), id, {gain = (b.gain or 0) + steps})
      return string.format("%s %.1f dB", place.node.name, (b.gain or 0) + steps)
    end
    local pan = util.clamp((b.pan or 0) + 0.1 * steps, -1, 1)
    api.chain_set(owner(), id, {pan = pan})
    return string.format("%s pan %.1f", place.node.name, pan)
  end
  local s = place.chain_split
  if main then
    local mix = util.clamp((s.mix or 1) + 0.05 * steps, 0, 1)
    api.chain_set(owner(), id, {mix = mix})
    return string.format("%s mix %d %%", place.node.name, math.floor(mix * 100 + 0.5))
  end
  api.chain_set(owner(), id, {gain = (s.gain or 0) + steps})
  return string.format("%s %.1f dB", place.node.name, (s.gain or 0) + steps)
end

--- A value key: on the node, or on each node of the selection.
local function value_key(main: boolean, sign: integer): function(ctx: KeyContext)
  return function(ctx: KeyContext)
    local reg = paw.keymap.mode == "x" and paw.keymap.selection()
    local ids = reg and view:targets(reg) or {view:node() and view:node().node.id}
    if reg then
      paw.keymap.set_mode("n")
    end
    local said: string
    for _, id in ipairs(ids) do
      said = nudge(id, main, sign * (ctx.count or 1))
    end
    if said then
      paw.notify(#ids == 1 and said or (what(ids) .. ": " .. said))
    end
  end
end

for _, key in ipairs(
  {
    {"+", true, 1, "main+"},
    {"<C-a>", true, 1, "main+"},
    {"-", true, -1, "main-"},
    {"<C-x>", true, -1, "main-"},
    {"]", false, 1, "second+"},
    {"[", false, -1, "second-"},
  }
) do
  local lhs, main, sign, role = key[1] as string, key[2] as boolean, key[3] as integer, key[4] as string
  local desc = main and "The main value: the wet mix of a device, the gain of a branch, the mix of a split"
    or "The second value: the output gain of a device, the pan of a branch, the gain of a split"
  map(lhs, value_key(main, sign), desc, {role = role, mode = {"n", "x"}, nowait = not main or nil})
end

-- States that change what you hear ---------------------------------------------------

--- The branch of the cursor: its own on a head, else the one that holds it.
local function cursor_branch(): Place
  local place = view:node()
  if not place then
    return nil
  end
  if is_branch(place) then
    return place
  end
  return place.branch and view:places()[place.branch]
end

--- Solo the branch `b` alone in its split, or (`off`) no branch.
local function solo(b: Place, off: boolean)
  local up = view:places()[b.split]
  for _, other in ipairs(up.node.branches) do
    api.chain_set(owner(), other.id, {solo = (not off) and other.id == b.node.id})
  end
end

--- The parts whose solo follows the cursor (`\S`).
local follows: {integer: boolean} = {}

map(
  "<localleader>s",
  function()
    local b = cursor_branch()
    if not b or view:places()[b.split].node.kind == "rack" then
      return paw.notify("the cursor is in no branch of a split", "warn")
    end
    local on = paw.chain.find(api.chain_get(owner()), b.node.id).branch.solo
    solo(b, on)
    paw.notify(on and "no branch solo" or ("solo " .. b.node.name))
  end,
  "Solo the branch alone; again: no solo"
)
map(
  "<localleader>S",
  function()
    local part = view:part_id()
    follows[part] = not follows[part] or nil
    -- On: the branch of the cursor plays alone. Off: the solo stays.
    local b = cursor_branch()
    if follows[part] and b and view:places()[b.split].node.kind ~= "rack" then
      solo(b, false)
    end
    paw.notify(follows[part] and "the solo follows the cursor: `j` `k` compare the branches" or "the solo stays")
  end,
  "The solo follows the cursor across the branches; again: it stays"
)

-- The solo that follows the cursor moves when the cursor goes to another branch.
local go = view.go
view.go = function(self: devices.Devices, id: integer)
  local before = cursor_branch()
  go(self, id)
  local b = cursor_branch()
  if follows[view:part_id()] and b and b ~= before and view:places()[b.split].node.kind ~= "rack" then
    solo(b, false)
  end
end

--- The bypass state of each device before `\b`, by part.
local held: {integer: {integer: boolean}} = {}

map(
  "<localleader>b",
  function()
    local part = view:part_id()
    if not part then
      return
    end
    local list = api.part_get(part).devices
    -- The held states count only while each device is still bypassed:
    -- after `u` or a change by hand, `\b` bypasses the chain again.
    local still = held[part] ~= nil
    for _, id in ipairs(list) do
      still = still and api.device_get(id).bypass == true
    end
    if not still then
      held[part] = nil
    end
    if held[part] then
      for _, id in ipairs(list) do
        if held[part][id] ~= nil then
          api.device_set(id, {bypass = held[part][id]})
        end
      end
      held[part] = nil
      return paw.notify("the chain plays again, each device as it was")
    end
    held[part] = {}
    for _, id in ipairs(list) do
      held[part][id] = api.device_get(id).bypass or false
      api.device_set(id, {bypass = true})
    end
    paw.notify("bypassed the whole chain: `\\b` again brings it back")
  end,
  "Bypass the whole chain, and keep the state of each device; again: back"
)

--- A variant of a chain: the parameters and the bypass of each device.
local record Variant
  params: {integer: {string: number}}
  bypass: {integer: boolean}
end

--- The other variant of each part (`:ab.store`), and whether B plays.
local variants: {integer: Variant} = {}
local playing_b: {integer: boolean} = {}

local function variant_now(part: integer): Variant
  local v: Variant = {params = {}, bypass = {}}
  for _, id in ipairs(api.part_get(part).devices) do
    local d = api.device_get(id)
    v.params[id], v.bypass[id] = util.copy(d.params) as {string: number}, d.bypass or false
  end
  return v
end

paw.command(
  "ab.store",
  function()
    local part = view:part_id()
    if not part then
      return paw.notify("no part here", "warn")
    end
    variants[part] = variant_now(part)
    paw.notify(string.format("stored the chain as variant %s: `\\a` flips", playing_b[part] and "A" or "B"))
  end,
  {desc = "Store the chain of the part as the other variant, which `\\a` flips to"}
)
map(
  "<localleader>a",
  function()
    local part = view:part_id()
    local other = part and variants[part]
    if not other then
      return paw.notify("no variant stored: `:ab.store` stores this chain as the other one", "warn")
    end
    variants[part] = variant_now(part)
    for id, params in pairs(other.params) do
      if pcall(api.device_get, id) then
        for key, value in pairs(params) do
          api.device_set_param(id, key, value)
        end
        api.device_set(id, {bypass = other.bypass[id]})
      end
    end
    playing_b[part] = not playing_b[part] or nil
    paw.notify("variant " .. (playing_b[part] and "B" or "A") .. " plays")
  end,
  "Flip between the two variants of the chain"
)

view.chips_of = function(part: integer): {string}
  local out: {string} = {}
  if part and follows[part] then
    out[#out + 1] = "SOLO follows"
  end
  if part and playing_b[part] then
    out[#out + 1] = "B"
  end
  return out
end

-- Insert mode keys ---------------------------------------------------------------

local kinds = paw.insert.view_kinds("devices")

--- What the key `key` inserts at the caret, as many as the count (for a
--- split: the count of its branches).
local function press(key: string)
  local spec = kinds:get(key)
  local count = typed_count
  typed_count = nil
  if not (spec and view.wire_caret) then
    return paw.notify("`" .. key .. "` inserts nothing: `K` lists the keys", "warn")
  end
  try(
    function()
      if spec.split then
        local name = spec.split == "chain" and ("Rack " .. (#made + 1)) or nil
        local id = add_split(spec.split, caret_place(), {branches = count, name = name})
        inserted(id, true)
        paw.notify("inserted " .. name_of(id))
        return
      end
      for _ = 1, count or 1 do
        local id = add_device(spec.device, caret_place())
        if spec.preset then
          api.device_load(id, {name = spec.preset})
        end
        inserted(id, false)
      end
      paw.notify("inserted " .. (count and count > 1 and (count .. " × ") or "") .. name_of(view.cursor))
    end
  )
end

-- The mapping made for each key from its kind, to know which are this
-- module's: those it takes away when the key goes.
local mapped: {string: Kind} = {}

--- Map each key of `paw.opt.graph_insertkeys` in insert mode, and take
--- away the mappings of keys that are no longer there.
local function sync()
  local active: {string: boolean} = {}
  for i, key in ipairs((paw.opt.graph_insertkeys or {}) as {string}) do
    local spec = kinds:get(key)
    if spec then
      active[key] = true
      if mapped[key] ~= spec then
        paw.keymap.set(key, function() press(key) end, {mode = "i", view = "devices", desc = spec.desc, order = i})
        mapped[key] = spec
      end
    end
  end
  for key in pairs(mapped) do
    if not active[key] then
      paw.keymap.del(key, {mode = "i", view = "devices"})
      mapped[key] = nil
    end
  end
end
paw.insert.on_view.devices = sync
local options = require("paw.options")
events.on(
  options.changed,
  function(e: options.Changed)
    if e.name == "graph_insertkeys" then
      sync()
    end
  end
)

for _, entry in ipairs(
  {
    {"c", "compressor", "A compressor"},
    {"e", "eq", "An EQ"},
    {"s", "saturation", "A saturation"},
    {"g", "gate", "A gate"},
    {"l", "limiter", "A limiter"},
    {"d", "delay", "A delay"},
    {"r", "reverb", "A reverb"},
    {"u", "utility", "A utility"},
    {"m", "meter", "A meter"},
  }
) do
  paw.insert.add(entry[1], {view = "devices", device = entry[2], desc = entry[3], order = 10})
end
for _, entry in ipairs(
  {
    {"R", "chain", "A rack"},
    {"L", "layer", "A layer split; a count gives its branches"},
    {"B", "band", "A band split; a count gives its bands"},
    {"M", "ms", "A mid/side split"},
    {"S", "lr", "A left/right split"},
  }
) do
  paw.insert.add(entry[1], {view = "devices", split = entry[2], desc = entry[3], order = 20})
end
sync()

local function imap(lhs: string, fn: function(ctx: KeyContext), desc: string, opts?: KeymapModule.MapOptions)
  local o: KeymapModule.MapOptions = opts or {}
  o.mode, o.view, o.desc, o.hint = "i", "devices", desc, false
  paw.keymap.set(lhs, fn, o)
end

for d = 0, 9 do
  imap(
    tostring(d),
    function()
      if d > 0 or typed_count then
        typed_count = (typed_count or 0) * 10 + d
      end
    end,
    "A count: as many as it says, or the branches of a split"
  )
end

--- Move the caret `n` nodes along its branch; past the end of a branch it
--- goes out of the split.
local function caret_along(n: integer): function()
  return function()
    local c = view.wire_caret
    local items = view:items_of(c.branch)
    local at = c.at + n
    if at >= 0 and at <= #items then
      view.wire_caret = {branch = c.branch, at = at}
    elseif c.branch then
      local split = view:places()[view:places()[c.branch].split]
      view.wire_caret = caret_of(split)
      if n > 0 then
        view.wire_caret.at = view.wire_caret.at + 1
      end
    end
    api.ui_redraw()
  end
end

--- Move the caret to the branch below (above when negative) in its split.
local function caret_across(n: integer): function()
  return function()
    local c = view.wire_caret
    local place = c.branch and view:places()[c.branch]
    local split = place and view:places()[place.split]
    if not split then
      return
    end
    for i, b in ipairs(split.node.branches) do
      if b.id == c.branch and split.node.branches[i + n] then
        local to = split.node.branches[i + n]
        view.wire_caret = {branch = to.id, at = math.min(c.at, #to.items)}
      end
    end
    api.ui_redraw()
  end
end

imap("<Right>", caret_along(1), "The caret past the next node")
imap("<Left>", caret_along(-1), "The caret before the node before")
imap("<Down>", caret_across(1), "The caret into the branch below")
imap("<Up>", caret_across(-1), "The caret into the branch above")
for _, key in ipairs({"h", "j", "k"}) do
  imap(
    key,
    function() paw.notify("use the arrow keys to move the caret, or `<Esc>` and move", "warn") end,
    "Not a move here"
  )
end
imap(
  "|",
  function()
    local c = view.wire_caret
    try(
      function()
        local place = c.branch and view:places()[c.branch]
        local split = place and view:places()[place.split]
        if split and split.node.kind == "split" then
          local id = api.chain_branch_add(owner(), split.node.id)
          view.wire_caret = {branch = id, at = 0}
          return paw.notify("added a branch to " .. split.node.name)
        end
        -- Out of a split: what is before the caret goes into a layer.
        local before = view:items_of(c.branch)[c.at]
        if not before then
          return paw.notify("no node before the caret to put in a layer", "warn")
        end
        local id = paw.chain.wrap(owner(), {before.id}, "layer", {branches = 2}).id
        view.wire_caret = {branch = split_now(id).branches[2].id, at = 0}
      end
    )
    api.ui_redraw()
  end,
  "A new branch in the split around the caret"
)
imap("<Tab>", function() pick_at(caret_place(), true) end, "Choose a device at the caret from the picker")
imap(
  "<C-r>",
  function(ctx: KeyContext)
    local copies = copies_in(paw.keymap.getreg(ctx.char))
    if not copies then
      return paw.notify("no node in the register", "warn")
    end
    try(
      function()
        for _, id in ipairs(paste_list(copies, caret_place())) do
          inserted(id, false)
        end
      end
    )
  end,
  "The nodes of a register, at the caret",
  {char = true}
)
imap(
  "<BS>",
  function()
    local last = table.remove(made)
    if not last then
      return paw.notify("nothing inserted to take back", "warn")
    end
    remove({last.id})
    view.wire_caret = last.caret
    paw.notify("took back the last node")
  end,
  "Take back the node inserted last"
)
imap(
  "<C-u>",
  function()
    local n = #made
    while #made > 0 do
      local last = table.remove(made)
      remove({last.id})
      view.wire_caret = last.caret
    end
    paw.notify("took back " .. count_of(n, "node", "nodes"))
  end,
  "Take back all that this insert added"
)
imap(
  "<CR>",
  function()
    local last = made[#made]
    paw.keymap.set_mode("n")
    if last then
      view:go(last.id)
      paw.ui.focus("inspector")
    end
  end,
  "Go to the inspector of the node inserted last"
)
imap(
  "K",
  function()
    local lines: {string} = {"Insert mode: each key adds a node at the caret; <Esc> ends"}
    for _, key in ipairs((paw.opt.graph_insertkeys or {}) as {string}) do
      local spec = kinds:get(key)
      if spec then
        lines[#lines + 1] = string.format("  %-3s %s", key, spec.desc)
      end
    end
    lines[#lines + 1] = "  |   a new branch    Tab the picker    <BS> take back"
    paw.notify(table.concat(lines, "\n"))
  end,
  "Say what each key adds"
)

-- The end of insert mode says what it added.
events.on(
  paw.keymap.mode_changed,
  function(e: KeymapModule.ModeChanged)
    if e.old ~= "i" or not view.wire_caret then
      return
    end
    view.wire_caret = nil
    local nodes, splits = 0, 0
    for _, m in ipairs(made) do
      if m.split then
        splits = splits + 1
      else
        nodes = nodes + 1
      end
    end
    made = {}
    if nodes + splits > 0 then
      local words: {string} = {}
      if nodes > 0 then
        words[#words + 1] = count_of(nodes, "device", "devices")
      end
      if splits > 0 then
        words[#words + 1] = count_of(splits, "container", "containers")
      end
      paw.notify("inserted " .. table.concat(words, ", "))
    end
  end
)
view.insert_hints = true

-- Ex commands ----------------------------------------------------------------------

--- A frequency as text: `120`, `2k`, `2.5kHz`.
local function hertz(word: string): number
  local n, k = tostring(word):lower():match("^([%d%.]+)%s*(k?)")
  local value = tonumber(n)
  return value and (k == "k" and value * 1000 or value)
end

--- The nodes that an Ex command acts on: the selection of `'<,'>`, else the node.
local function command_targets(ctx: contracts.CommandContext): {integer}
  local reg = ctx.range and paw.keymap.last_selection()
  if reg then
    return view:targets(reg)
  end
  local place = view:node()
  return place and {place.node.id} or {}
end

local function word_args(ctx: contracts.CommandContext): {string}
  local out: {string} = {}
  for i, a in ipairs(ctx.args) do
    out[i] = tostring(a)
  end
  return out
end

paw.command(
  "wrap",
  function(ctx: contracts.CommandContext)
    local args = word_args(ctx)
    local kind = args[1]
    if not kind then
      return paw.notify("usage: :wrap <kind> [branches | crossovers]: `:wrap band 120 2k`, `:wrap layer 3`", "warn")
    end
    local opts: types.ChainWrapOptions = {}
    if kind == "band" and args[2] then
      local xover: {number} = {}
      for i = 2, #args do
        xover[#xover + 1] = hertz(args[i])
      end
      opts.branches, opts.values = #xover + 1, {xover = xover} as types.Meta
    elseif args[2] then
      opts.branches = math.tointeger(tonumber(args[2]))
    end
    local ids = command_targets(ctx)
    try(function() paw.chain.wrap(owner(), ids, kind, opts) end)
  end,
  {desc = "Wrap the node or the selection in a split: `:wrap band 120 2k`, `:wrap layer 3`", range = true}
)
paw.command(
  "unwrap",
  function(ctx: contracts.CommandContext)
    local place = container()
    if not place then
      return paw.notify("no split around the cursor", "warn")
    end
    local keep: integer
    if word_args(ctx)[1] ~= "all" then
      local b = cursor_branch()
      keep = b and b.split == place.node.id and b.node.id or nil
    end
    try(function() paw.chain.unwrap(owner(), place.node.id, keep) end)
  end,
  {
    desc = "Unwrap the split around the cursor and keep the branch of the cursor; `:unwrap all` puts all the branches in series",
  }
)
paw.command(
  "branch",
  function(ctx: contracts.CommandContext)
    local args = word_args(ctx)
    local b = cursor_branch()
    local place = container()
    if args[1] == "add" then
      if not place then
        return paw.notify("no split here", "warn")
      end
      try(function() paw.chain.add_branch(owner(), place.node.id, {name = args[2]}) end)
      return
    elseif args[1] == "remove" and b then
      try(function() paw.chain.remove(owner(), b.node.id) end)
      return
    elseif args[1] == "solo" and b then
      local on = paw.chain.find(api.chain_get(owner()), b.node.id).branch.solo
      solo(b, on)
      return paw.notify(on and "no branch solo" or ("solo " .. b.node.name))
    end
    paw.notify("usage: :branch add [name], :branch remove, :branch solo (with the cursor in a branch)", "warn")
  end,
  {desc = "Branches of the split: `:branch add Name`, `:branch remove`, `:branch solo`"}
)
paw.command(
  "xover",
  function(ctx: contracts.CommandContext)
    local place = container()
    if not (place and place.chain_split.kind == "band") then
      return paw.notify("no band split here", "warn")
    end
    local xover: {number} = {}
    for _, word in ipairs(word_args(ctx)) do
      xover[#xover + 1] = hertz(word)
    end
    try(function() paw.chain.set(owner(), place.node.id, {values = {xover = xover} as types.Meta}) end)
  end,
  {desc = "Set the crossovers of the band split: `:xover 120 2k`"}
)
paw.command(
  "zone",
  function(ctx: contracts.CommandContext)
    local b = cursor_branch()
    local text = word_args(ctx)[1] or ""
    local low, high = text:match("^(%w+)%-(%w+)$")
    local function note(word: string): integer
      return math.tointeger(tonumber(word)) or (word and paw.music.pitch(word))
    end
    local lo, hi = note(low), note(high)
    if not (b and lo and hi) then
      return paw.notify("usage: :zone C1-B2 or :zone 64-127, with the cursor in a branch", "warn")
    end
    try(function() paw.chain.set(owner(), b.node.id, {zone = {low = lo, high = hi}}) end)
  end,
  {desc = "Set the notes or velocities that the branch hears: `:zone C1-B2`, `:zone 64-127`"}
)
paw.command(
  "macro",
  function(ctx: contracts.CommandContext)
    local place = container()
    local name = word_args(ctx)[1]
    if not (place and name) then
      return paw.notify("usage: :macro <name>, in a split or a rack", "warn")
    end
    try(function() paw.chain.add_macro(owner(), place.node.id, name) end)
  end,
  {desc = "Add a macro to the split or rack: `:macro Drive`"}
)
paw.command(
  "macro.link",
  function(ctx: contracts.CommandContext)
    local args = word_args(ctx)
    local place = view:node()
    local home = place and place.device and container_around(place.node.id, 1)
    local macro = home and home.chain_split.macros and home.chain_split.macros[1]
    if not (macro and args[1]) then
      return paw.notify("usage: :macro.link <param> [depth %], on a device in a container with a macro", "warn")
    end
    local depth = (tonumber(args[2]) or 100) / 100
    try(function() paw.chain.link(owner(), macro.id, place.node.id, args[1], depth) end)
  end,
  {desc = "Link the first macro of the container to a parameter of the device: `:macro.link drive 12`"}
)

return {}
