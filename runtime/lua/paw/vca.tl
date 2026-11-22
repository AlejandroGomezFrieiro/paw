-- VCAs: a fader, a mute and a solo that belong to other tracks without
-- carrying their sound, as on a desk. Nothing is routed: the members play
-- where they played, each at its own fader, and the VCA moves them all.
--
--   local drums = paw.vca.make({ kick, snare, hats }, "Drums")
--   drums.volume = -3        -- every member 3 dB quieter than its own fader
--   drums.mute = true        -- and silent
--   paw.vca.assign(room, drums)
--   paw.vca.unassign(snare, drums)
--
-- A track may be in several VCAs; their gains add in dB. The VCA is a track
-- marked in its `meta`, which is how its fader can have automation lanes
-- like any other; each member names its VCAs in its own. Both are saved,
-- undone and copied with the tracks. The sync reads the marks: it folds the
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

--- A track: its id, or the track itself (`paw.track`).
local type TrackRef = integer | contracts.TrackHandle

--- What this module keeps in a track's `meta`: `vca` on a VCA, and on a
--- member the VCAs it is in, by id.
local record Marks
  vca: boolean
  vcas: {integer}
end

-- What this module reads of `paw`, which paw/init.lua makes.
local record Paw is partial.Paw
  add_track: function(opts?: objects.TrackInput): objects.Track
end
local paw = (_G as {string: Paw}).paw

local record M
  type TrackRef = TrackRef
end

local function id_of(track: TrackRef): integer
  if track is contracts.TrackHandle then
    return track.id
  end
  return track
end

-- One entry of a track: quicker than the whole track, which lists its clips (api.rs).
local track_meta = api.track_get as function(integer, string): types.Meta

local function meta(id: integer): Marks
  local ok, m = pcall(track_meta, id, "meta")
  return ok and m as Marks or {}
end

local function set_meta(id: integer, m: Marks)
  api.track_set(id, {meta = m as types.Meta})
end

--- True if a track is a VCA.
function M.is_vca(track: TrackRef): boolean
  return meta(id_of(track)).vca == true
end

--- The VCAs of a track (their ids), in the order in which paw put the track in them.
function M.of(track: TrackRef): {integer}
  local out: {integer} = {}
  for _, id in ipairs(meta(id_of(track)).vcas or {}) do
    if M.is_vca(id) then
      out[#out + 1] = id
    end
  end
  return out
end

--- The tracks in a VCA, in the order of the track list.
function M.members(vca: TrackRef): {integer}
  local vid = id_of(vca)
  local out: {integer} = {}
  for _, id in ipairs(api.track_list()) do
    for _, v in ipairs(meta(id).vcas or {}) do
      if v == vid then
        out[#out + 1] = id
      end
    end
  end
  return out
end

--- Every VCA, in the order of the track list.
function M.list(): {integer}
  local out: {integer} = {}
  for _, id in ipairs(api.track_list()) do
    if M.is_vca(id) then
      out[#out + 1] = id
    end
  end
  return out
end

--- Put a track under a VCA.
function M.assign(track: TrackRef, vca: TrackRef)
  local tid, vid = id_of(track), id_of(vca)
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

--- Take a track out of a VCA, or out of all of them without `vca`.
function M.unassign(track: TrackRef, vca?: TrackRef): boolean
  local tid = id_of(track)
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

--- A new VCA over `tracks` (ids or tracks), after the last track. Returns
--- its track.
function M.make(tracks?: {TrackRef}, name?: string): contracts.TrackHandle
  local vca = paw.add_track({name = name or "VCA"})
  local m = meta(vca.id)
  m.vca = true
  set_meta(vca.id, m)
  for _, track in ipairs(tracks or {}) do
    M.assign(track, vca.id)
  end
  return vca
end

--- Take a VCA away: its tracks stay, at their own faders.
function M.dissolve(vca: TrackRef): boolean
  local vid = id_of(vca)
  if not M.is_vca(vid) then
    return false
  end
  for _, id in ipairs(M.members(vid)) do
    M.unassign(id, vid)
  end
  api.track_remove(vid)
  return true
end

-- A VCA that is removed (or restored) leaves its members' lists holding an id
-- that names nothing, which is ignored; they are tidied when it is removed.
events.on(
  kernel.track_removed,
  function(event: kernel.TrackId)
    if event.restored then
      return
    end
    for _, id in ipairs(api.track_list()) do
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
