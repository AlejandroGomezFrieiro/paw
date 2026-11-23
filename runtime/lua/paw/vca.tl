-- VCAs: a fader, a mute and a solo that belong to other parts without
-- carrying their sound, as on a desk. Nothing is routed: the members play
-- where they played, each at its own fader, and the VCA moves them all.
--
--   local drums = paw.vca.make({ kick, snare, hats }, "Drums")
--   drums.volume = -3        -- every member 3 dB quieter than its own fader
--   drums.mute = true        -- and silent
--   paw.vca.assign(room, drums)
--   paw.vca.unassign(snare, drums)
--
-- A part may be in several VCAs; their gains add in dB. The VCA is a part
-- marked in its `meta`, which is how its fader can have automation lanes
-- like any other; each member names its VCAs in its own. Both are saved,
-- undone and copied with the parts. The sync reads the marks: it folds the
-- VCAs' faders into each member's gain, and their lanes into the member's
-- own, so what is heard (and rendered) is the sum, sample by sample.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type objects = require("paw.objects")

--- A part: its id, or the part itself (`paw.part`).
local type PartRef = integer | contracts.PartHandle

--- What this module keeps in a part's `meta`: `vca` on a VCA, and on a
--- member the VCAs it is in, by id.
local record Marks
  vca: boolean
  vcas: {integer}
end

-- What this module reads of `paw`, which paw/init.lua makes.
local record Paw is partial.Paw
  add_part: function(opts?: objects.PartInput): objects.Part
end
local paw = (_G as {string: Paw}).paw

local record M
  type PartRef = PartRef
end

local function id_of(part: PartRef): integer
  if part is contracts.PartHandle then
    return part.id
  end
  return part
end

-- One entry of a part: quicker than the whole part, which lists its clips (api.rs).
local part_meta = api.part_get as function(integer, string): types.Meta

local function meta(id: integer): Marks
  local ok, m = pcall(part_meta, id, "meta")
  return ok and m as Marks or {}
end

local function set_meta(id: integer, m: Marks)
  api.part_set(id, {meta = m as types.Meta})
end

--- True if a part is a VCA.
function M.is_vca(part: PartRef): boolean
  return meta(id_of(part)).vca == true
end

--- The VCAs of a part (their ids), in the order in which paw put the part in them.
function M.of(part: PartRef): {integer}
  local out: {integer} = {}
  for _, id in ipairs(meta(id_of(part)).vcas or {}) do
    if M.is_vca(id) then
      out[#out + 1] = id
    end
  end
  return out
end

--- The parts in a VCA, in the order of the part list.
function M.members(vca: PartRef): {integer}
  local vid = id_of(vca)
  local out: {integer} = {}
  for _, id in ipairs(api.part_list()) do
    for _, v in ipairs(meta(id).vcas or {}) do
      if v == vid then
        out[#out + 1] = id
      end
    end
  end
  return out
end

--- Every VCA, in the order of the part list.
function M.list(): {integer}
  local out: {integer} = {}
  for _, id in ipairs(api.part_list()) do
    if M.is_vca(id) then
      out[#out + 1] = id
    end
  end
  return out
end

--- Put a part under a VCA.
function M.assign(part: PartRef, vca: PartRef)
  local tid, vid = id_of(part), id_of(vca)
  if not M.is_vca(vid) then
    error("not a VCA", 2)
  end
  if tid == vid or M.is_vca(tid) then
    error("a VCA cannot be put under a VCA", 2)
  end
  local m = meta(tid)
  local list = m.vcas or {}
  for _, v in ipairs(list) do
    if v == vid then
      return
    end
  end
  list[#list + 1] = vid
  m.vcas = list
  set_meta(tid, m)
end

--- Take a part out of a VCA, or out of all of them without `vca`.
function M.unassign(part: PartRef, vca?: PartRef): boolean
  local tid = id_of(part)
  local m = meta(tid)
  local list, keep: {integer}, {integer} = m.vcas or {}, {}
  for _, v in ipairs(list) do
    if vca ~= nil and v ~= id_of(vca) then
      keep[#keep + 1] = v
    end
  end
  if #keep == #list then
    return false
  end
  m.vcas = #keep > 0 and keep or nil
  set_meta(tid, m)
  return true
end

--- A new VCA over `parts` (ids or parts), after the last part. Returns
--- its part.
function M.make(parts?: {PartRef}, name?: string): contracts.PartHandle
  local vca = paw.add_part({name = name or "VCA"})
  local m = meta(vca.id)
  m.vca = true
  set_meta(vca.id, m)
  for _, part in ipairs(parts or {}) do
    M.assign(part, vca.id)
  end
  return vca
end

--- Take a VCA away: its parts stay, at their own faders.
function M.dissolve(vca: PartRef): boolean
  local vid = id_of(vca)
  if not M.is_vca(vid) then
    return false
  end
  for _, id in ipairs(M.members(vid)) do
    M.unassign(id, vid)
  end
  api.part_remove(vid)
  return true
end

-- A VCA that is removed (or restored) leaves its members' lists holding an id
-- that names nothing, which is ignored; they are tidied when it is removed.
events.on(
  kernel.part_removed,
  function(event: kernel.PartId)
    if event.restored then
      return
    end
    for _, id in ipairs(api.part_list()) do
      local list = meta(id).vcas
      if list then
        for _, v in ipairs(list) do
          if v == event.id then
            M.unassign(id, v)
          end
        end
      end
    end
  end
)

return M
