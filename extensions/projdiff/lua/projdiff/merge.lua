-- Three-way merge of project files, by what is in them rather than by lines.
--
-- Two people who changed different tracks, different clips, different notes
-- or different parameters have not conflicted, whatever the order of the
-- lines in the file: lists of things with ids (tracks, devices, clips,
-- lanes, notes, markers) are merged item by item, lists of sends, tempo
-- changes and automation points by what names each, and lists with nothing
-- to name their items (controllers) as sets. What is left is a real
-- conflict: the same thing changed in two ways, or changed in one and
-- removed in the other. The merged project holds our side there, and says
-- what the conflict was in `meta.merge_conflicts`, where `:Pmerge` finds it.
-- It is a project that loads and plays, and a project with conflicts left in
-- it says so every time it is opened.
local data = require("projdiff.data")

local M = {}

-- Lists that are kept in the order of a field, by their key.
local SORTED = { notes = "start", controls = "start", points = 1, tempo_changes = "beat", sig_changes = "beat" }

-- Lists whose items are told apart by an id of the list's own, which two
-- sides adding different items may give the same number.
local OWN_IDS = { notes = true, markers = true }

--- How a list item is named in a path: `{ id = 3 }`, `{ target = 2 }`, `{ at = 16 }`.
local function segment(field, key)
  if field == 1 then return { at = key } end
  return { [field] = key }
end

local function unsegment(seg)
  local name, key = next(seg)
  return name == "at" and 1 or name, key
end

local function sort_list(list, name)
  local field = SORTED[name]
  if not field then return list end
  local items = {}
  for i, item in ipairs(list) do
    items[i] = { i = i, item = item }
  end
  local function at(item)
    local v = item[field]
    return type(v) == "number" and v or 0
  end
  table.sort(items, function(a, b)
    local x, y = at(a.item), at(b.item)
    if x ~= y then return x < y end
    return a.i < b.i
  end)
  for i, entry in ipairs(items) do
    list[i] = entry.item
  end
  return list
end

--- An empty list that the model reads as a list: a plain empty table reads
--- as an empty object.
local function empty_list() return paw.api.json_decode("[]") end

local function appended(path, seg)
  local out = {}
  for i, s in ipairs(path) do
    out[i] = s
  end
  out[#out + 1] = seg
  return out
end

--- The name of the list a path ends in, when it ends in one.
local function list_name(path)
  for i = #path, 1, -1 do
    if type(path[i]) == "string" then return path[i] end
  end
end

local merge

local function conflict(ctx, path, base, ours, theirs)
  ctx.conflicts[#ctx.conflicts + 1] = { path = path, base = base, ours = ours, theirs = theirs }
  return ours
end

local function merge_object(base, ours, theirs, path, ctx)
  local keys = {}
  for _, t in ipairs({ base or {}, ours, theirs }) do
    for k in pairs(t) do
      keys[k] = true
    end
  end
  local out = {}
  for _, k in ipairs(data.sorted_keys(keys)) do
    out[k] = merge((base or {})[k], ours[k], theirs[k], appended(path, k), ctx)
  end
  return out
end

--- Lists of items that are named: merged item by item.
local function merge_keyed(base, ours, theirs, path, ctx, field)
  local B, O, T = data.by(base, field), data.by(ours, field), data.by(theirs, field)
  local name = list_name(path)
  local next_id
  local function fresh()
    if not next_id then
      next_id = 0
      for _, A in ipairs({ B, O, T }) do
        for _, k in ipairs(A.order) do
          next_id = math.max(next_id, k)
        end
      end
    end
    next_id = next_id + 1
    return next_id
  end

  -- Items both sides added under the same id that are not the same item:
  -- ours keeps the id, theirs gets another.
  if field == "id" and OWN_IDS[name] then
    local moved = {}
    for _, k in ipairs(T.order) do
      if B.by[k] == nil and O.by[k] ~= nil and not data.equal(O.by[k], T.by[k]) then
        local copy = {}
        for key, v in pairs(T.by[k]) do
          copy[key] = v
        end
        copy.id = fresh()
        moved[k] = copy
      end
    end
    if next(moved) then
      local order = {}
      T = { by = {}, order = order }
      for _, item in ipairs(theirs) do
        local copy = moved[item.id] or item
        T.by[copy.id] = copy
        order[#order + 1] = copy.id
      end
    end
  end

  local keep, items = {}, {}
  for _, k in ipairs(O.order) do
    local o, t, b = O.by[k], T.by[k], B.by[k]
    local item
    if t ~= nil then
      item = merge(b, o, t, appended(path, segment(field, k)), ctx)
    elseif b == nil or data.equal(b, o) then
      -- Ours added it, or theirs removed it unchanged.
      item = b == nil and o or nil
    else
      -- Theirs removed it, and ours changed it.
      item = conflict(ctx, appended(path, segment(field, k)), b, o, nil)
    end
    if item ~= nil then
      keep[#keep + 1] = k
      items[k] = item
    end
  end

  -- What theirs added goes after the item before it in theirs.
  local result = {}
  for _, k in ipairs(keep) do
    result[#result + 1] = k
  end
  local previous
  for _, k in ipairs(T.order) do
    if O.by[k] == nil then
      local b, t = B.by[k], T.by[k]
      local item
      if b == nil then
        item = t
      elseif data.equal(b, t) then
        item = nil -- ours removed it, theirs left it
      else
        -- Ours removed it, and theirs changed it: ours holds, the conflict says so.
        conflict(ctx, appended(path, segment(field, k)), b, nil, t)
      end
      if item ~= nil then
        local pos = 0
        for i, kk in ipairs(result) do
          if kk == previous then pos = i end
        end
        table.insert(result, pos + 1, k)
        items[k] = item
      end
    end
    if items[k] ~= nil then previous = k end
  end

  local out = {}
  for _, k in ipairs(result) do
    out[#out + 1] = items[k]
  end
  if #out == 0 then return empty_list() end
  return sort_list(out, name)
end

--- Lists with nothing to name their items: sets, where an item changed is
--- one removed and one added.
local function merge_set(base, ours, theirs, path)
  local function counts(list)
    local n = {}
    for _, item in ipairs(list) do
      local c = data.canon(item)
      n[c] = (n[c] or 0) + 1
    end
    return n
  end
  local b, o, t = counts(base), counts(ours), counts(theirs)
  local want = {}
  for c, n in pairs(o) do
    want[c] = n + (t[c] or 0) - (b[c] or 0)
  end
  for c, n in pairs(t) do
    if want[c] == nil then want[c] = n - (b[c] or 0) end
  end
  local out, given = {}, {}
  for _, list in ipairs({ ours, theirs }) do
    for _, item in ipairs(list) do
      local c = data.canon(item)
      if (given[c] or 0) < (want[c] or 0) then
        given[c] = (given[c] or 0) + 1
        out[#out + 1] = item
      end
    end
  end
  if #out == 0 then return empty_list() end
  return sort_list(out, list_name(path))
end

local function is_list(t) return data.is_array(t) end

function merge(base, ours, theirs, path, ctx)
  if data.equal(ours, theirs) then return ours end
  if data.equal(base, ours) then return theirs end
  if data.equal(base, theirs) then return ours end
  if type(ours) == "table" and type(theirs) == "table" and (base == nil or type(base) == "table") then
    local lists = is_list(ours) and is_list(theirs) and (base == nil or is_list(base))
    local items = #ours > 0 or #theirs > 0 or (base ~= nil and #base > 0)
    local objects = not lists and not items
    if lists then
      local field = data.key_field(base, ours, theirs)
      if field then return merge_keyed(base or {}, ours, theirs, path, ctx, field) end
      return merge_set(base or {}, ours, theirs, path)
    elseif objects then
      return merge_object(base, ours, theirs, path, ctx)
    end
  end
  return conflict(ctx, path, base, ours, theirs)
end

-- Ids that are the project's, one number for each subproject, track,
-- device, clip and lane, so that two sides adding different things may have
-- used the same one.

local function copy(v)
  if type(v) ~= "table" then return v end
  if next(v) == nil then return paw.api.json_encode(v) == "[]" and empty_list() or {} end
  local out = {}
  for k, x in pairs(v) do
    out[k] = copy(x)
  end
  return out
end

-- Changing ids in place: each function changes the ids of the thing that it
-- takes, and what in it points at other things, by `map` (old id -> new id).

local function remap(holder, field, map)
  if type(holder[field]) == "number" and map[holder[field]] then holder[field] = map[holder[field]] end
end

local function remap_device(d, map)
  remap(d, "id", map)
  remap(d, "sidechain", map)
  for pair, id in pairs(d.outputs or {}) do
    if map[id] then d.outputs[pair] = map[id] end
  end
end

--- A clip, and the subproject that it places with the track that it plays.
local function remap_clip(c, map)
  remap(c, "id", map)
  local content = c.content
  if type(content) == "table" and content.kind == "nest" then
    remap(content, "nest", map)
    if type(content.play) == "table" then remap(content.play, "track", map) end
  end
end

local function remap_lane(l, map)
  remap(l, "id", map)
  if l.target then remap(l.target, "device", map) end
end

local function remap_track(t, map)
  remap(t, "id", map)
  remap(t, "nest", map)
  remap(t, "output", map)
  for _, s in ipairs(t.sends or {}) do
    remap(s, "target", map)
  end
  for _, d in ipairs(t.devices or {}) do
    remap_device(d, map)
  end
  for _, c in ipairs(t.clips or {}) do
    remap_clip(c, map)
  end
  for _, l in ipairs(t.lanes or {}) do
    remap_lane(l, map)
  end
  for _, c in ipairs(t.cues or {}) do
    remap_clip(c, map)
  end
end

local function remap_nest(n, map)
  remap(n, "id", map)
  remap(n, "master", map)
end

--- Each thing of a project with an id, by id: `{ holder, whole, remap }`.
--- `holder` is the id of what holds it (the track of a device, the
--- subproject of a track), `whole` is what tells it from another thing (the
--- thing, or a subproject with its tracks), and `remap(whole, map)` changes
--- the ids in a copy of `whole`.
local function things(project)
  local by = {}
  local function add(item, holder, remap_fn, whole)
    if type(item.id) == "number" then by[item.id] = { holder = holder, whole = whole or item, remap = remap_fn } end
  end
  local function track(t)
    add(t, t.nest, remap_track)
    for _, d in ipairs(t.devices or {}) do
      add(d, t.id, remap_device)
    end
    for _, c in ipairs(t.clips or {}) do
      add(c, t.id, remap_clip)
    end
    for _, l in ipairs(t.lanes or {}) do
      add(l, t.id, remap_lane)
    end
    for _, c in ipairs(t.cues or {}) do
      add(c, t.id, remap_clip)
    end
  end
  project = project or {}
  if project.master then track(project.master) end
  for _, t in ipairs(project.tracks or {}) do
    track(t)
  end
  -- Two subprojects are the same only when their tracks are the same too.
  for _, n in ipairs(project.nests or {}) do
    local tracks = {}
    for _, t in ipairs(project.tracks or {}) do
      if t.nest == n.id then tracks[#tracks + 1] = t end
    end
    add(n, nil, function(whole, map)
      remap_nest(whole.nest, map)
      for _, t in ipairs(whole.tracks) do
        remap_track(t, map)
      end
    end, { nest = n, tracks = tracks })
  end
  return by
end

--- The ids of theirs that ours also made, for another thing: by id, a
--- stand-in for the new id. A thing of theirs is another thing when it differs from ours with the
--- ids found so far changed, or when what holds it got another id. So a
--- subproject that gets another id gives its tracks, their devices and
--- clips, and the clips that place it other ids too.
local function clashes(B, O, T)
  -- A stand-in for a new id while the ids are found: no thing has it.
  local NEW = -1
  local map = {}
  local changed = true
  while changed do
    changed = false
    for id, x in pairs(T) do
      if map[id] == nil and B[id] == nil and O[id] ~= nil then
        local moved = x.holder ~= nil and map[x.holder] ~= nil
        if not moved then
          local whole = copy(x.whole)
          x.remap(whole, map)
          moved = not data.equal(O[id].whole, whole)
        end
        if moved then
          map[id], changed = NEW, true
        end
      end
    end
  end
  return map
end

--- Theirs, with the ids that it and ours both made for different things
--- changed to ones nothing else has, and what points at them with them.
local function renumber(base, ours, theirs)
  local B, O, T = things(base), things(ours), things(theirs.project)
  local found = clashes(B, O, T)
  if next(found) == nil then return theirs end
  local top = 0
  for _, set in ipairs({ B, O, T }) do
    for id in pairs(set) do
      top = math.max(top, id)
    end
  end
  -- New ids in the order of the old ones, so that a merge gives the same file each time.
  local ids = {}
  for id in pairs(found) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  local map = {}
  for _, id in ipairs(ids) do
    top = top + 1
    map[id] = top
  end
  local out = copy(theirs)
  local project = out.project
  if project.master then remap_track(project.master, map) end
  for _, t in ipairs(project.tracks or {}) do
    remap_track(t, map)
  end
  for _, n in ipairs(project.nests or {}) do
    remap_nest(n, map)
  end
  return out
end

--- Merge three versions of a project file (decoded): returns the merged
--- file and the list of conflicts, `{ path, base, ours, theirs }` with a
--- value missing where that side has none. The conflicts are also written
--- into the merged project's `meta.merge_conflicts`.
function M.files(base, ours, theirs)
  base = base or { project = {} }
  local ctx = { conflicts = {} }
  theirs = renumber(base.project, ours.project, theirs)
  local merged = merge(base, ours, theirs, {}, ctx)
  if type(merged) ~= "table" then merged = ours end
  -- Conflicts an earlier merge left unsettled stay.
  local all = {}
  for _, c in ipairs(M.conflicts(merged)) do
    all[#all + 1] = c
  end
  for _, c in ipairs(ctx.conflicts) do
    all[#all + 1] = c
  end
  M.record(merged, all)
  return merged, ctx.conflicts
end

--- Write conflicts into a file's project, in the form `M.conflicts` reads.
function M.record(doc, conflicts)
  local project = doc.project
  project.meta = project.meta or {}
  if #conflicts == 0 then
    project.meta.merge_conflicts = nil
    return
  end
  local list = {}
  for i, c in ipairs(conflicts) do
    local absent = {}
    for _, side in ipairs({ "base", "ours", "theirs" }) do
      if c[side] == nil then absent[#absent + 1] = side end
    end
    list[i] = { path = c.path, base = c.base, ours = c.ours, theirs = c.theirs, absent = #absent > 0 and absent or nil }
  end
  project.meta.merge_conflicts = list
end

--- The conflicts a project file holds, as `M.files` returned them.
function M.conflicts(doc)
  local list = doc.project and doc.project.meta and doc.project.meta.merge_conflicts
  return type(list) == "table" and list or {}
end

-- Resolving ----------------------------------------------------------------

local function find(list, seg)
  local field, key = unsegment(seg)
  for i, item in ipairs(list) do
    if type(item) == "table" and item[field] == key then return item, i end
  end
end

--- Walk a path in a file: the thing at the end of it, and what holds it.
local function walk(doc, path)
  local holder, here = nil, doc
  for _, seg in ipairs(path) do
    if type(here) ~= "table" then return nil end
    holder = here
    if type(seg) == "string" then
      here = here[seg]
    else
      here = find(here, seg)
    end
  end
  return here, holder
end

--- What a path names in a file (nil when it is not there).
function M.at(doc, path) return (walk(doc, path)) end

local function put(doc, path, value)
  local parent_path = {}
  for i = 1, #path - 1 do
    parent_path[i] = path[i]
  end
  local parent = walk(doc, parent_path)
  if type(parent) ~= "table" then return false end
  local last = path[#path]
  if type(last) == "string" then
    parent[last] = value
    return true
  end
  local _, index = find(parent, last)
  if value == nil then
    if index then table.remove(parent, index) end
  elseif index then
    parent[index] = value
  else
    parent[#parent + 1] = value
    sort_list(parent, list_name(parent_path))
  end
  return true
end

local function same_path(a, b) return data.equal(a, b) end

--- Settle a conflict by taking `side` ("ours", "theirs" or "base") of it
--- and forgetting that it was one. Returns whether the path was there to settle.
function M.resolve(doc, conflict, side)
  local meta = doc.project.meta
  local list, kept = meta.merge_conflicts or {}, {}
  for _, c in ipairs(list) do
    if not same_path(c.path, conflict.path) then kept[#kept + 1] = c end
  end
  local done = put(doc, conflict.path, conflict[side])
  meta.merge_conflicts = #kept > 0 and kept or nil
  return done
end

--- Settle every conflict one way.
function M.resolve_all(doc, side)
  local list = {}
  for i, c in ipairs(M.conflicts(doc)) do
    list[i] = c
  end
  for _, c in ipairs(list) do
    M.resolve(doc, c, side)
  end
end

-- The word for an item of each list of things with ids, as the diff names them.
local ITEM_WORDS = {
  tracks = "track",
  devices = "device",
  clips = "clip",
  lanes = "lane",
  cues = "cue",
  notes = "note",
  markers = "marker",
  nests = "subproject",
}

--- A path in words for a file: `track 3 "Lead" › device 5 "synth" › params › cutoff`.
function M.describe(doc, path)
  local parts, here = {}, doc
  for i, seg in ipairs(path) do
    if type(seg) == "string" then
      here = type(here) == "table" and here[seg] or nil
      -- A list of things with ids is named by its item: `track 3`.
      local next_seg = path[i + 1]
      local by_id = type(next_seg) == "table" and next_seg.id ~= nil and ITEM_WORDS[seg]
      if seg ~= "project" and not by_id then parts[#parts + 1] = seg end
    else
      local item = type(here) == "table" and find(here, seg) or nil
      local field, key = unsegment(seg)
      local name = item and (item.name or item.kind)
      local word = field == "id" and ITEM_WORDS[path[i - 1]]
      parts[#parts + 1] = (word and (word .. " ") or field == "id" and "" or (field == 1 and "beat " or (field .. " ")))
        .. tostring(key)
        .. (name and (' "' .. tostring(name) .. '"') or "")
      here = item
    end
  end
  return table.concat(parts, " › ")
end

return M
