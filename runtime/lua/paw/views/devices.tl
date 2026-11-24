-- The devices view: the chain of a part as a graph. Devices in series,
-- splits with a lane for each branch, and racks in a frame (the flow
-- layout of paw/views/devices_layout.tl), or one row for each node in a
-- narrow window (the outline layout). A header gives the counts, the
-- latency and the keys of the chain; a second row gives the path of the
-- cursor and the chips of the states that change what you hear.
--
-- The cursor of the graph is on a node: a device, a split, a rack or a
-- branch. The inspector (paw/views/inspector.lua) is a window under the
-- graph: it shows the node under this cursor.
--
-- Containers start folded. The path to the cursor opens, and `za` `zo`
-- `zc` `zR` `zM` fold and open as in Vim. A container off the path that
-- does not fit in the width folds itself.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local layout = require("paw.views.devices_layout")
local type types = require("paw.types")
local type contracts = require("paw.contracts")

local type Node = layout.Node
local type Branch = layout.Branch
local type Laid = layout.Laid

--- The parts of `paw.routes` (paw/routes.lua, still Lua) that the view reads.
local record Routes
  sidechain_text: function(d: types.Device): string
end

--- What the view knows of a node of the chain besides its layout: the
--- split around it and the branch it is in (nil at the top level), its
--- place in that branch, and the kernel's record of a split or a device.
local record Place
  node: Node
  split: integer
  branch: integer
  index: integer
  depth: integer
  chain_split: types.ChainSplit
  device: types.Device
  --- On a split that the engine does not play as its kind says: why.
  why: string
end

--- The tree of a part as the view drew it last.
local record Tree
  items: {Node}
  places: {integer: Place}
  devices: integer
  containers: integer
  links: {integer: boolean}
  solo: string
  bypass: boolean
end

local record Devices is contracts.View
  --- The id of the node under the cursor, or nil for the first node.
  cursor: integer
  --- The folds that a key chose, by the id of a container: true open,
  --- false folded. A container with no entry is open only on the path to
  --- the cursor.
  open: {integer: boolean}
  --- The part that the window shows whatever the cursor is on, or nil.
  pin: integer
  scroll: integer
  --- The part the cursor and the folds were chosen on.
  row_part: integer
  geometry: {string: integer}
  tree: Tree
  part_id: function(self: Devices): integer
  part: function(self: Devices): types.Part
  node: function(self: Devices): Place
  go: function(self: Devices, id: integer)
  stops: function(self: Devices): {integer}
  set_pin: function(self: Devices, part: integer)
  part_named: function(target: string | integer): integer
  path: function(self: Devices): {Place}
  series: function(self: Devices, place: Place): {integer}
end

local view: Devices = {
  cursor = nil,
  open = {},
  scroll = 0,
  window_state = {"cursor", "open", "scroll", "pin", "row_part"},
  window_fresh = {},
}
paw.seats.fields(
  "devices",
  view as {string: util.Data},
  {"cursor", "open", "scroll", "pin", "row_part"},
  {open = {}, scroll = 0} as {string: util.Data}
)

local BUILTIN_KINDS: {string: boolean} = {}
for _, word in ipairs({"chain", "layer", "band", "ms", "lr", "key", "vel", "select", "outs"}) do
  BUILTIN_KINDS[word] = true
end

-- The part ---------------------------------------------------------------------------

--- The pinned part of the window, if it is still in the project.
local function pinned(self: Devices): integer
  local id = self.pin
  if id and id ~= 0 and pcall(api.part_get, id) then
    return id
  end
end

--- The id of the part whose chain the window shows: its pinned part, else
--- the cursor's.
function view:part_id(): integer
  return pinned(self) or paw.cursor.part_id()
end

function view:part(): types.Part
  local id = self:part_id()
  return id and api.part_get(id) or nil
end

--- The part that a name stands for: its number, `paw://part/3`, or its name.
function view.part_named(target: string | integer): integer
  local id = math.tointeger(tonumber(target) or tonumber(tostring(target):match("^paw://part/(%d+)")))
  if id then
    return (id ~= 0 and pcall(api.part_get, id)) and id or nil
  end
  for _, other in ipairs(api.part_list()) do
    if api.part_get(other).name == target then
      return other
    end
  end
end

--- Pin the window to a part (`:e devices://Bass`, `:vs devices://3`).
function view:open_target(target: string): boolean, string
  local id = view.part_named(target)
  if not id then
    return false, "no part `" .. tostring(target) .. "`"
  end
  self.pin, self.cursor, self.scroll = id, nil, 0
  return true
end

--- What a saved layout keeps of the window: the number of its pinned part.
function view:window_target(): string | integer
  return pinned(self)
end

--- Pin the window to `part` (an id), or with nil follow the cursor again.
function view:set_pin(part: integer)
  self.pin, self.cursor, self.scroll = part, nil, 0
  if part then
    paw.notify("the devices view stays on " .. api.part_get(part).name .. "; `:devices.pin` again follows the cursor")
  else
    paw.notify("the devices view follows the cursor part")
  end
  api.ui_redraw()
end

--- Keys and commands typed in a pinned window act on its part: the part
--- of "the cursor" is the window's while that window has the keyboard, or
--- while paw draws it.
paw.cursor.lens = function(): integer
  local u = paw.ui
  local L = paw.layout
  local win = u.drawing_win
  if win then
    if win.view ~= "devices" or L.bound("devices") ~= win then
      return nil
    end
  else
    if (u.focused ~= "devices" and u.focused ~= "inspector") or u.float then
      return nil
    end
    win = L.find(u.layout, "devices")
    if not (win and L.bound("devices") == win) then
      return nil
    end
  end
  return pinned(view)
end

-- The tree ---------------------------------------------------------------------------

--- The text of a value of a parameter, as the panels write it.
local function value_text(p: types.ParamInfo, value: number): string
  return paw.frontend.format_value(p, value)
end

--- The second row of a device's card: its preset, else its first own
--- parameter and its value.
local function device_summary(d: types.Device): string
  local meta = d.meta as {string: util.Data}
  local preset = meta and meta.preset
  if preset is string then
    return preset
  end
  for _, p in ipairs(d.param_info or {}) do
    if not (p.key == "fx_wet" or p.key == "fx_gain") then
      return p.name:lower() .. " " .. value_text(p, d.params[p.key] or p.default)
    end
  end
  return ""
end

--- A peak as the cell of a meter reads it: -60 dB to 0 dB, 0 to 1.
local function level(peak: number): number
  if not peak or peak <= 0 then
    return 0
  end
  return util.clamp((20 * math.log10(peak) + 60) / 60, 0, 1)
end

--- Why the engine does not play a split as its kind says, or nil: a word
--- for the header of the split, and the whole reason for `K`. The engine
--- then plays the first branch of the split.
local function split_warning(kind: string, known: {string: boolean}): string, string
  if not known[kind] then
    return "absent", "no loaded extension defines the kind " .. kind
  elseif kind == "outs" or not BUILTIN_KINDS[kind] then
    return "not played", "the engine does not play " .. kind .. " splits yet"
  end
end

--- The values of a split in its header: the crossovers of a band split.
local function values_text(s: types.ChainSplit): string
  local values = s.values as {string: {number}}
  local xover = values and values.xover
  if not xover then
    return ""
  end
  local words: {string} = {}
  for _, f in ipairs(xover) do
    words[#words + 1] = f >= 1000 and string.format("%g kHz", f / 1000) or string.format("%g Hz", f)
  end
  return " · " .. table.concat(words, " · ")
end

local function gain_text(db: number): string
  return string.format("%.1f", db or 0)
end

--- The tree of the part `part`: its chain, or its devices in series.
local function tree_of(part: types.Part): Tree
  local tree: Tree = {items = {}, places = {}, devices = 0, containers = 0, links = {}}
  local h: types.ChainOwner = {part = part.id}
  local chain = paw.chain.get(h)
  local ok, got = pcall(paw.chain.meters, h) as (boolean, types.ChainMeters)
  local peaks: {integer: number} = ok and got.peaks or {}
  local known: {string: boolean} = {}
  for _, word in ipairs(paw.chain.kinds()) do
    known[word] = true
  end
  local routes = paw.routes as Routes
  local bypassed = 0

  local function device_node(id: integer, place: Place): Node
    local d = api.device_get(id)
    tree.devices = tree.devices + 1
    if d.bypass then
      bypassed = bypassed + 1
    end
    local badges: {string} = {}
    if tree.links[id] then
      badges[#badges + 1] = "~"
    end
    if routes.sidechain_text(d) then
      badges[#badges + 1] = "↯"
    end
    if next(d.outputs or {}) then
      badges[#badges + 1] = "⇉"
    end
    local node: Node = {
      kind = "device",
      id = id,
      name = d.name or d.kind,
      summary = device_summary(d),
      meter = level(peaks[id]),
      badges = table.concat(badges, ""),
      off = d.bypass,
    }
    place.node, place.device = node, d
    tree.places[id] = place
    return node
  end

  local walk_split: function(s: types.ChainSplit, place: Place): Node
  local function items_of(nodes: {types.ChainNode}, split: integer, branch: integer, depth: integer): {Node}
    local out: {Node} = {}
    for i, n in ipairs(nodes) do
      local place: Place = {split = split, branch = branch, index = i, depth = depth}
      out[#out + 1] = n.split and walk_split(n.split, place) or device_node(n.device, place)
    end
    return out
  end

  walk_split = function(s: types.ChainSplit, place: Place): Node
    tree.containers = tree.containers + 1
    for _, link in ipairs(s.links or {}) do
      tree.links[link.device] = true
    end
    local rack = s.kind == "chain" and #s.branches == 1
    local name = (s.name and s.name ~= "") and s.name or s.kind
    local warn, why = split_warning(s.kind, known)
    local node: Node = {
      kind = rack and "rack" or "split",
      id = s.id,
      name = name,
      meter = level(peaks[s.id]),
      branches = {},
      warn = warn,
      devices = 0,
    }
    place.why = why
    place.node, place.chain_split = node, s
    tree.places[s.id] = place
    local before = tree.devices
    local gains: {string} = {}
    for i, b in ipairs(s.branches) do
      local label = (b.name and b.name ~= "") and b.name or tostring(i)
      local branch: Branch = {
        id = b.id,
        label = (b.name and b.name ~= "") and (i .. " " .. b.name) or tostring(i),
        gain = gain_text(b.gain),
        items = items_of(b.nodes, s.id, b.id, place.depth + 1),
      }
      node.branches[i] = branch
      tree.places[b.id] = {
        node = {kind = "split", id = b.id, name = branch.label}, split = s.id, branch = b.id, depth = place.depth + 1
      }
      if b.solo then
        tree.solo = label
      end
      gains[#gains + 1] = (b.gain or 0) ~= 0 and (label .. " " .. branch.gain) or label
    end
    node.devices = tree.devices - before
    local macro = s.macros and s.macros[1]
    if macro then
      node.summary = string.format("%s %d %%", macro.name, math.floor(macro.value * 100 + 0.5))
    elseif rack then
      node.summary = node.devices .. (node.devices == 1 and " device" or " devices")
    else
      node.summary = table.concat(gains, " · ")
    end
    local mix = (s.mix or 1) < 1 and string.format(" · mix %d %%", math.floor(s.mix * 100 + 0.5)) or ""
    node.head = s.kind .. ((s.name and s.name ~= "") and (" " .. s.name) or "") .. values_text(s) .. mix
    return node
  end

  if not chain then
    for i, id in ipairs(part.devices or {}) do
      tree.items[i] = device_node(id, {index = i, depth = 0})
    end
  else
    -- The links first, so that each device knows that a macro moves it.
    local function links(s: types.ChainSplit)
      for _, link in ipairs(s.links or {}) do
        tree.links[link.device] = true
      end
      for _, b in ipairs(s.branches) do
        for _, n in ipairs(b.nodes) do
          if n.split then
            links(n.split)
          end
        end
      end
    end
    links(chain.root)
    local root = chain.root
    if root.kind == "chain" and #root.branches == 1 then
      tree.items = items_of(root.branches[1].nodes, nil, nil, 0)
    else
      tree.containers = tree.containers - 1
      tree.items = {walk_split(root, {index = 1, depth = 0})}
      tree.containers = tree.containers + 1
    end
  end
  tree.bypass = tree.devices > 0 and bypassed == tree.devices
  return tree
end

--- The tree of the window's part, made again when the project changed.
local kept: {string: Tree} = {}
local kept_at: {string: string} = {}
local function current_tree(self: Devices): Tree
  local part = self:part()
  if not part then
    return {items = {}, places = {}, devices = 0, containers = 0, links = {}}
  end
  if self.row_part ~= part.id then
    self.row_part, self.cursor, self.scroll, self.open = part.id, nil, 0, {}
  end
  local key = tostring(part.id)
  local stamp = tostring(paw.frontend.revision) .. ":" .. tostring(api.project_get().edits)
  if kept_at[key] ~= stamp or not kept[key] then
    kept[key], kept_at[key] = tree_of(part), stamp
  end
  self.tree = kept[key]
  return kept[key]
end

paw.on(require("paw.events.kernel").project_loaded, function() view.row_part = nil; kept, kept_at = {}, {} end)

-- The cursor -------------------------------------------------------------------------

--- The places from the top level down to the cursor's node, outermost first.
function view:path(): {Place}
  local tree = self.tree or current_tree(self)
  local out: {Place} = {}
  local place = self.cursor and tree.places[self.cursor]
  while place do
    table.insert(out, 1, place)
    local up = place.branch and place.branch ~= place.node.id and tree.places[place.branch]
      or (place.split and tree.places[place.split])
    place = up or nil
  end
  return out
end

--- The ids of the splits and branches around the cursor: these are open.
local function on_path(self: Devices): {integer: boolean}
  local out: {integer: boolean} = {}
  for _, place in ipairs(self:path()) do
    if place.node.id ~= self.cursor then
      out[place.node.id] = true
    end
  end
  return out
end

local function opener(self: Devices, path: {integer: boolean}): function(integer): boolean
  return function(id: integer): boolean
    local chosen = self.open[id]
    if chosen ~= nil then
      return chosen
    end
    return path[id] == true
  end
end

--- The ids that the cursor stops on, in the order of the signal: each node,
--- and in an open split each branch before its nodes.
function view:stops(): {integer}
  local tree = current_tree(self)
  local is_open = opener(self, on_path(self))
  local out: {integer} = {}
  local function walk(items: {Node})
    for _, node in ipairs(items) do
      out[#out + 1] = node.id
      if node.branches and is_open(node.id) then
        for _, b in ipairs(node.branches) do
          if node.kind == "split" then
            out[#out + 1] = b.id
          end
          walk(b.items)
        end
      end
    end
  end
  walk(tree.items)
  return out
end

--- The devices in series with the node at `place`, in their order: the
--- devices of its branch, or of the top level. A split among them is left
--- out. For a branch, the devices of that branch.
function view:series(place: Place): {integer}
  local tree = current_tree(self)
  local items = tree.items
  local split = place.split and tree.places[place.split]
  for _, b in ipairs(split and split.node.branches or {}) do
    if b.id == place.branch then
      items = b.items
    end
  end
  local out: {integer} = {}
  for _, node in ipairs(items) do
    if node.kind == "device" then
      out[#out + 1] = node.id
    end
  end
  return out
end

--- The place of the node under the cursor: the first node when the
--- cursor is on none.
function view:node(): Place
  local tree = current_tree(self)
  local place = self.cursor and tree.places[self.cursor]
  if place then
    return place
  end
  local first = tree.items[1]
  if first then
    self.cursor = first.id
    return tree.places[first.id]
  end
end

--- Put the cursor on the node `id`.
function view:go(id: integer)
  self.cursor = id
  api.ui_redraw()
end

-- Drawing ----------------------------------------------------------------------------

local function breadcrumb(self: Devices, part: types.Part): string
  local words: {string} = {part.name}
  for _, place in ipairs(self:path()) do
    local node = place.node
    if node.id ~= self.cursor or node.kind ~= "device" then
      words[#words + 1] = node.name
    end
  end
  if #words > 5 then
    words = {words[1], "…", words[#words - 3], words[#words - 2], words[#words - 1], words[#words]}
  end
  return table.concat(words, " › ")
end

--- The chips of the states that change what you hear, and of the pin.
local function chips(self: Devices, tree: Tree): {string}
  local out: {string} = {}
  if tree.solo then
    out[#out + 1] = "SOLO " .. tree.solo
  end
  if tree.bypass then
    out[#out + 1] = "BYPASS"
  end
  if pinned(self) then
    out[#out + 1] = "pinned"
  end
  return out
end

--- The header: devices, containers, latency, the CPU while the song
--- plays, and the parts that keys of the chain listen to.
local last_time: {integer: {number}} = {}
local function header(part: types.Part, tree: Tree): string
  local words: {string} = {tree.devices .. " dev"}
  if tree.containers > 0 then
    words[#words + 1] = tree.containers .. " cont"
  end
  local ok, meters = pcall(paw.chain.meters, {part = part.id}) as (boolean, types.ChainMeters)
  if ok then
    words[#words + 1] = string.format("%.1f ms", meters.latency)
    local ns = 0
    for _, t in pairs(meters.time) do
      ns = ns + t
    end
    local now = api.now()
    local before = last_time[part.id]
    last_time[part.id] = {ns, now}
    if paw.transport.playing and before and now > before[2] then
      words[#words + 1] = string.format("cpu %d %%", math.floor((ns - before[1]) / ((now - before[2]) * 1e4) + 0.5))
    end
  end
  local keys: {string} = {}
  local routes = paw.routes as Routes
  for _, place in pairs(tree.places) do
    local text = place.device and routes.sidechain_text(place.device)
    if text then
      keys[#keys + 1] = text
    end
  end
  table.sort(keys)
  if #keys > 0 then
    words[#words + 1] = "keys " .. table.concat(keys, ", ")
  end
  return table.concat(words, " · ")
end

--- The roles of the runs of a layout, in `buf` from row `top`, with the
--- cursor's node lit.
local function paint(buf: contracts.Buf, laid: Laid, top: integer, cursor: integer)
  for _, run in ipairs(laid.runs) do
    local y = run.y - top
    local h = run.sub and 2 or 1
    if y + h > 0 and y < buf.height then
      local selected = run.id == cursor and run.role ~= "wire"
      buf:mark(
        run.role,
        run.x,
        y,
        math.max(1, math.min(run.w, buf.width - run.x)),
        h,
        {
          text = run.text,
          sub = run.sub,
          style = run.style,
          sub_style = run.sub_style,
          selected = selected or nil,
          id = run.id,
          hit = run.id and run.role ~= "wire" and {kind = "node", id = run.id} or nil,
        } as contracts.MarkProps
      )
    end
  end
end

function view:render(buf: contracts.Buf, ctx: contracts.RenderContext)
  local part = self:part()
  local tree = current_tree(self)
  local inner = paw.ui.titlebar(
    buf,
    {
      name = "Devices",
      context = part and (part.name .. (pinned(self) and " · pinned" or "")) or nil,
      focused = ctx.focused,
      right = part and tree.devices > 0 and header(part, tree) or nil,
    }
  )
  local w, h = inner.width, inner.height
  if not part or #tree.items == 0 then
    inner:text(2, 1, "No devices.", "Empty")
    inner:text(2, 3, "a", "EmptyKey")
    inner:text(5, 3, "add one", "Empty")
    self.geometry = {top = 1}
    return
  end
  self:node()
  -- The path of the cursor, and the chips at the right.
  local chip_list = chips(self, tree)
  local right = table.concat(chip_list, "  ")
  local crumb = breadcrumb(self, part)
  local room = w - 2 - (right ~= "" and api.str_width(right) + 2 or 0)
  inner:mark(
    "label",
    1,
    0,
    math.max(1, room),
    1,
    {text = util.fit(crumb, math.max(1, room)), style = "Dim"} as contracts.LabelMark
  )
  if right ~= "" then
    inner:mark(
      "chip",
      w - 1 - api.str_width(right),
      0,
      api.str_width(right),
      1,
      {text = right, style = "Warn"} as contracts.MarkProps
    )
  end
  local opts: layout.Options = {
    width = w, path = on_path(self), cursor = self.cursor, open = opener(self, on_path(self))
  }
  local laid = w >= layout.FLOW and layout.flow(tree.items, opts) or layout.outline(tree.items, opts)
  local area = h - 1
  local row = laid.rows[self.cursor] or 0
  if row < self.scroll then
    self.scroll = row
  elseif row + 2 > self.scroll + area then
    self.scroll = row + 2 - area
  end
  self.scroll = math.tointeger(util.clamp(self.scroll, 0, math.max(0, laid.height - area)))
  paint(inner:sub(0, 1, w, area), laid, self.scroll, self.cursor)
  self.geometry = {top = 1, height = laid.height, width = w}
end

--- Its title where a window shows one over it.
function view:title_of(): string
  local part = self:part()
  return part and ("Devices · " .. part.name) or "Devices"
end

-- The inspector goes with the graph: it shows when the graph shows, under it.
function view:on_show()
  if paw.ui.views:get("inspector") then
    paw.layout.reveal("inspector")
  end
end

function view:on_hide()
  if paw.ui.views:get("inspector") then
    paw.ui.hide("inspector")
  end
end

--- `K` on a node: what it is, where it is, and for a split what the
--- engine plays.
function view:describe(): contracts.Description
  local place = self:node()
  if not place then
    return nil
  end
  local node = place.node
  local part = self:part()
  local lines: contracts.Description = {title = node.name}
  lines[#lines + 1] = "Path       " .. breadcrumb(self, part)
  if place.device then
    lines[#lines + 1] = "Device     " .. place.device.kind .. (place.device.bypass and ", bypassed" or "")
  elseif place.chain_split then
    local s = place.chain_split
    lines[#lines + 1] = string.format(
      "Split      %s, %d branch%s", s.kind, #s.branches, #s.branches == 1 and "" or "es"
    )
    for i, b in ipairs(node.branches) do
      lines[#lines + 1] = (i == 1 and "Branches   " or "           ") .. b.label .. "  " .. b.gain .. " dB"
    end
    if place.why then
      lines[#lines + 1] = "Plays      its first branch: " .. place.why
    end
    lines[#lines + 1] = "Keys       za fold · Enter the inspector"
  end
  return lines
end

-- The pointer: a click on a node puts the cursor there.
view.gestures = {
  node = function(self: Devices, e: contracts.MouseEvent): boolean
    if e.kind ~= "down" and e.kind ~= "press" then
      return false
    end
    local hit = e.hit as {string: integer}
    self:go(hit.id)
    return true
  end,
}

paw.ui.view("devices", view)

-- Keys -------------------------------------------------------------------------------

local function map(lhs: string, fn: function(ctx: contracts.KeyContext), desc: string, motion?: boolean)
  paw.keymap.set(lhs, fn, {view = "devices", desc = desc, motion = motion})
end

--- Move the cursor `n` stops along the signal (back when `n` is negative).
local function step(n: integer): function(ctx: contracts.KeyContext)
  return function(ctx: contracts.KeyContext)
    local stops = view:stops()
    view:node()
    local at = 1
    for i, id in ipairs(stops) do
      if id == view.cursor then
        at = i
      end
    end
    local to = math.tointeger(util.clamp(at + n * (ctx.count or 1), 1, #stops))
    if stops[to] then
      view:go(stops[to])
    end
  end
end

--- Move the cursor to the branch below (or above) in the split around it,
--- at the same place in that branch. In a narrow window, the next row.
local function across(n: integer): function(ctx: contracts.KeyContext)
  local along = step(n)
  return function(ctx: contracts.KeyContext)
    local tree = current_tree(view)
    local place = view:node()
    if not place or (view.geometry and view.geometry.width or layout.FLOW) < layout.FLOW then
      return along(ctx)
    end
    -- Up from the cursor to the innermost split with more than one
    -- branch, with the place of the cursor's line in its branch (0 for
    -- the branch's head).
    local index = place.node.id == place.branch and 0 or (place.index or 0)
    local p = place
    while p and p.branch do
      local split = tree.places[p.split]
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

map("l", step(1), "The next node along the signal", true)
map("h", step(-1), "The node before along the signal", true)
map("w", step(1), "The next node", true)
map("b", step(-1), "The node before", true)
map("<Right>", step(1), "The next node along the signal", true)
map("<Left>", step(-1), "The node before along the signal", true)
map("j", across(1), "The branch below, or the next row in a narrow window", true)
map("k", across(-1), "The branch above, or the row before in a narrow window", true)
map("<Down>", across(1), "The branch below", true)
map("<Up>", across(-1), "The branch above", true)
map(
  "gg",
  function()
    local stops = view:stops()
    if stops[1] then
      view:go(stops[1])
    end
  end,
  "The first node",
  true
)
map(
  "G",
  function()
    local stops = view:stops()
    if #stops > 0 then
      view:go(stops[#stops])
    end
  end,
  "The last node",
  true
)

--- The container that a fold key acts on: the node under the cursor when
--- it is one, else the container around it.
local function container(): Place
  local tree = current_tree(view)
  local place = view:node()
  if place and place.chain_split then
    return place
  end
  local up = place and (place.split and tree.places[place.split])
  return up
end

local function fold(want: string): function()
  return function()
    local place = container()
    if not place then
      return paw.notify("no split or rack here")
    end
    local id = place.node.id
    local now = opener(view, on_path(view))(id)
    local open = want == "toggle" and not now or want == "open"
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
    for id, place in pairs(current_tree(view).places) do
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
    local stops = current_tree(view).items
    for _, place in pairs(current_tree(view).places) do
      if place.chain_split then
        view.open[place.node.id] = false
      end
    end
    -- The cursor goes to the top-level node that holds it.
    local path = view:path()
    if path[1] then
      view.cursor = path[1].node.id
    elseif stops[1] then
      view.cursor = stops[1].id
    end
    paw.notify("folded every split and rack")
    api.ui_redraw()
  end,
  "Fold every split and rack"
)

--- Go to the inspector of the node under the cursor.
local function inspect()
  if not view:node() then
    return paw.notify("no devices: `a` adds one")
  end
  paw.ui.focus("inspector")
end
map("<CR>", inspect, "Go to the inspector of the node")
-- The keys of a device that the inspector has too: on a device of the graph
-- they act on it.
map("a", function() paw.cmd("device.add") end, "Add a device")
map("x", function() paw.cmd("device.remove") end, "Remove the device")
map("<localleader>p", function() paw.cmd("devices.pin") end, "Pin the view to its part, or follow the cursor again")
map("s", function() paw.cmd("part.solo") end, "Solo the part")
map("M", function() paw.cmd("part.mute") end, "Mute the part")

return view
