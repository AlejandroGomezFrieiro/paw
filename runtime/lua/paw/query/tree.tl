-- The clips and notes of the project as the nodes that `paw.query` gives,
-- kept by `paw.derived` (the search index of the design `derived.md`,
-- D3), so that a query or a search after an edit reads again only the
-- clips that the edit changed:
--
--   query.clip    a clip as a node, made again when the clip changes
--   query.notes   the notes of a clip as nodes, inside the clip's node
--   query.part   the clips of a part, in order, as nodes
--   query.tree    the clips and the notes of every part
--
-- The nodes are shared by every query until their clip changes: a
-- consumer reads them and does not change them. `paw.grep` reads its text
-- from the same nodes.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local derived = require("paw.derived")
local type types = require("paw.types")
local type util = require("paw.util")
local type contracts = require("paw.contracts")

local type Node = contracts.QueryNode
local type Data = util.Data

--- The nodes of one part: its clips in order, and the notes of each.
local record PartNodes
  clips: {Node}
  notes: {integer: {Node}}
end

--- The nodes of every part, by the part's id.
local record Tree
  parts: {integer: PartNodes}
end

local record M
  type PartNodes = PartNodes
  type Tree = Tree
  clip: derived.Node<integer, Node, types.Clip>
  notes: derived.Node<integer, {Node}, boolean>
  part: derived.Node<integer, PartNodes, boolean>
  tree_node: derived.Node<integer, Tree, boolean>
  same_data: function(a: Data, b: Data): boolean
  same_list: function<T>(a: {T}, b: {T}): boolean
end

--- Whether two values of plain data (the kernel's tables) are the same.
local function same_data(a: Data, b: Data): boolean
  if a == b then
    return true
  end
  if not (a is {Data: Data}) or not (b is {Data: Data}) then
    return false
  end
  local ta, tb = a, b
  for k, v in pairs(ta) do
    if not same_data(v, tb[k]) then
      return false
    end
  end
  for k in pairs(tb) do
    if ta[k] == nil then
      return false
    end
  end
  return true
end
M.same_data = same_data

local function same_list<T>(a: {T}, b: {T}): boolean
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end
M.same_list = same_list

local clip_get = api.clip_get

local clip_spec: derived.Spec<integer, Node, types.Clip> = {
  name = "query.clip",
  kind = "family",
  -- The clip as the kernel gives it: the same clip, the same node.
  inputs = function(ctx: derived.Ctx, id: integer): types.Clip
    ctx:source("clip:" .. id)
    local ok, c = pcall(clip_get, id)
    return ok and c or nil
  end,
  same_inputs = function(a: types.Clip, b: types.Clip): boolean return same_data(a as Data, b as Data) end,
  make = function(_: derived.Ctx, id: integer, _: Node, c: types.Clip): Node
    if not c then
      return nil
    end
    return {kind = "clip", id = id, data = c as contracts.QueryData, part = c.part, clip = id}
  end,
}
M.clip = derived.node(clip_spec)

local EMPTY: {Node} = {}

local notes_spec: derived.Spec<integer, {Node}, boolean> = {
  name = "query.notes",
  kind = "family",
  make = function(ctx: derived.Ctx, id: integer): {Node}
    local clip = ctx:get(M.clip, id)
    if not clip or (clip.data as types.Clip).kind ~= "midi" then
      return EMPTY
    end
    local out: {Node} = {}
    local list = api.clip_notes(id)
    for i = 1, #list do
      local n = list[i]
      out[i] = {
        kind = "note",
        id = n.id,
        data = n as contracts.QueryData,
        parent = clip,
        part = clip.part,
        clip = id,
        place = i,
      }
    end
    return out
  end,
  -- A node and the note it holds take about 500 bytes (31.7 MB of Lua heap
  -- for the 50 000 notes of bench/profile/project.lua).
  bytes = function(list: {Node}): integer return 64 + 500 * #list end,
  limit = 32 * 1048576,
}
M.notes = derived.node(notes_spec)

local part_spec: derived.Spec<integer, PartNodes, boolean> = {
  name = "query.part",
  kind = "family",
  make = function(ctx: derived.Ctx, id: integer): PartNodes
    local v: PartNodes = {clips = {}, notes = {}}
    local list = ctx:clips(id)
    for i = 1, #list do
      local cid = list[i].id
      local node = ctx:get(M.clip, cid)
      if node then
        v.clips[#v.clips + 1] = node
        v.notes[cid] = ctx:get(M.notes, cid)
      end
    end
    return v
  end,
  same = function(a: PartNodes, b: PartNodes): boolean
    if not same_list(a.clips, b.clips) then
      return false
    end
    for id, list in pairs(a.notes) do
      if b.notes[id] ~= list then
        return false
      end
    end
    return true
  end,
}
M.part = derived.node(part_spec)

local tree_spec: derived.Spec<integer, Tree, boolean> = {
  name = "query.tree",
  kind = "join",
  label = "search",
  make = function(ctx: derived.Ctx): Tree
    local tree: Tree = {parts = {}}
    -- The song's parts and each subproject's: a query in a subproject
    -- reads its parts.
    ctx:source("parts")
    local ids = api.part_list({all = true})
    for i = 1, #ids do
      tree.parts[ids[i]] = ctx:get(M.part, ids[i])
      -- The first reading of a large project goes on at the next slice.
      ctx:pause()
    end
    return tree
  end,
}
M.tree_node = derived.node(tree_spec)

--- The nodes of every part, up to date. From the first call on, the job
--- of `paw.derived` keeps them up to date after each edit, in slices.
function M.tree(): Tree
  M.tree_node:want(0)
  return (M.tree_node:get(0, true))
end

return M
