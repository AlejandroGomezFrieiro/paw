-- Articulations: which way a note is played (staccato, pizzicato, a trill),
-- kept on the note as its MIDI 2.0 attribute, named by a map of the
-- instrument that plays it.
--
-- The truth is the note's attribute (`note.attr = { type, data }`, an
-- M2-123 code): it plays with no extension loaded. A map (`.art.toml`,
-- see `articulations.maps`) gives the codes names, tags and colours, says
-- the instrument's range and keyswitch rows, and how a MIDI 1.0 instrument
-- is told (`out`), which binding compiles into the track's `attr_map` for
-- the core to send.
--
--   local art = require("articulations")
--   art.bind(track, "violin-section")       -- find the map, keep it on the track, compile attr_map
--   art.set({ { clip = id, place = 3 } }, "pizzicato")   -- one undo step
--   art.of(track, note)                     -- the map's articulation a note plays, through M2-123's fallback
--   art.attr_of(note)                       -- { type, data } or nil
local api = paw.api
local util = paw.util
local m2 = require("articulations.m2")
local maps = require("articulations.maps")

local M = { m2 = m2, maps = maps, toml = require("articulations.toml") }

-- Notes' attributes ----------------------------------------------------------------
--
-- The core keeps `note.attr`. A core without it (before that work is
-- merged) keeps the attribute in `note.meta.art`, read and written the
-- same way through these three functions.

--- Whether the core keeps a note's attribute itself.
function M.core()
  return type(paw.attr) == "table" and type(paw.attr.m2) == "function"
end

--- A note's attribute, `{ type, data }`, or nil when it has none.
function M.attr_of(note)
  if not note then return nil end
  if m2.is(note.attr) then return note.attr end
  local kept = type(note.meta) == "table" and note.meta.art
  if m2.is(kept) then return kept end
end

--- The fields that give a note an attribute (nil takes it away), to merge
--- into a note being added or into a change of `edit_notes`.
function M.attr_fields(note, attr)
  if M.core() then return { attr = attr and { type = attr.type, data = attr.data } or { type = 0, data = 0 } } end
  local meta = util.merge(type(note.meta) == "table" and note.meta or {}, {})
  meta.art = attr and { type = attr.type, data = attr.data } or nil
  return { meta = meta }
end

--- Whether two attributes say the same (none and type 0 are the same).
function M.same(a, b)
  local ia, ib = m2.is(a), m2.is(b)
  if not ia or not ib then return ia == ib end
  return a.type == b.type and (a.data or 0) == (b.data or 0)
end

-- Tracks ---------------------------------------------------------------------------

local function track_of(which)
  if type(which) == "table" then return which.id or which end
  return which
end

--- What a track keeps: `{ map, file, hash, default, pen, names }`, or nil.
function M.info(track)
  local ok, t = pcall(api.track_get, track_of(track))
  local info = ok and type(t.meta) == "table" and t.meta.articulations
  return type(info) == "table" and info or nil
end

local function keep(track, fn)
  local id = track_of(track)
  local meta = util.merge(api.track_get(id, "meta") or {}, {})
  local info = util.merge(type(meta.articulations) == "table" and meta.articulations or {}, {})
  fn(info)
  meta.articulations = next(info) and info or nil
  -- An empty table would cross over as a list; one key keeps it a table.
  if next(meta) == nil then meta = { articulations_was = true } end
  api.track_set(id, "meta", meta)
end
M.keep = keep

--- The map a track is bound to, or nil (and why, when its file is gone).
--- With the track's keyswitch shift (`:art.shift`) applied.
function M.map_of(track)
  local info = M.info(track)
  if not info or not info.map then return nil end
  local map, err
  if info.file then map, err = maps.load(info.file, info.map) end
  if not map then map, err = maps.find(info.map) end
  if map and info.shift and info.shift ~= 0 then
    local moved = maps.shift(map, info.shift)
    if moved then return moved end
  end
  return map, err
end

--- The core's downgrade map for a map: what each articulation sends to an
--- instrument that does not take the attribute.
function M.compile(map, default)
  local arts = {}
  for _, art in ipairs(map.arts) do
    -- `delay`: how far the kernel moves the articulation's notes, in ms
    -- (-80: 80 ms early, for a sound that starts 80 ms late).
    if not arts[art.code] then arts[art.code] = { out = art.send or art.out, delay = art.delay or map.delay } end
  end
  local d = map.by_id[default or map.default] or map.by_id[map.default]
  return { send = map.send, chase = map.chase, default = d and d.code or nil, arts = arts, delay = map.delay }
end

--- Hand the core a track's downgrade map (nil takes it away). A core that
--- does not keep `attr_map` yet gets it kept with the binding instead.
function M.set_attr_map(track, attr_map)
  local id = track_of(track)
  local ok = pcall(api.track_set, id, "attr_map", attr_map)
  if ok then
    keep(id, function(info) info.attr_map = nil end)
  else
    keep(id, function(info) info.attr_map = attr_map end)
  end
end

--- The downgrade map the track has.
function M.attr_map(track)
  local ok, t = pcall(api.track_get, track_of(track))
  if ok and type(t.attr_map) == "table" then return t.attr_map end
  local info = M.info(track)
  return info and info.attr_map
end

--- Bind a map to a track (by id, name or file; nil for the one whose
--- `match` names a device of the track). Returns the map.
function M.bind(track, which)
  local id = track_of(track)
  local map, err
  if which == nil or which == "" then
    map = maps.matching(id)[1]
    if not map then error("no map names a device of this track: name one (`:art.map violin-section`), or `:art.maps`", 0) end
  else
    map, err = maps.find(which)
    if not map then error(err, 0) end
  end
  local old = M.info(id) or {}
  local names = {}
  for _, art in ipairs(map.arts) do
    if not names[art.code] then names[art.code] = art.tag end
  end
  local default = old.map == map.id and map.by_id[old.default or ""] and old.default or map.default
  -- A shift of the keyswitches stays while the map is the same.
  local shift = old.map == map.id and old.shift or nil
  local played = shift and maps.shift(map, shift) or map
  api.undo_label("Bind articulations " .. map.name)
  keep(id, function(info)
    info.map, info.file, info.hash, info.name = map.id, map.file, map.hash, map.name
    info.default = default
    info.pen = map.by_id[info.pen or ""] and info.pen or nil
    info.names = names
    info.shift = shift
  end)
  M.set_attr_map(id, M.compile(played, default))
  paw.emit("articulations.bound", { track = id, map = map.id })
  return map
end

--- Move the keyswitches of a track's map by `shift` keys (0: as the map
--- says), for an instrument whose keyswitch area was moved. Returns the
--- moved map, or fails with why.
function M.set_shift(track, shift)
  local id = track_of(track)
  local info = M.info(id)
  if not info or not info.map then error("the track has no articulation map: :art.map", 0) end
  local map, err = maps.load(info.file or "", info.map)
  if not map then map, err = maps.find(info.map) end
  if not map then error(err, 0) end
  shift = math.floor(tonumber(shift) or 0)
  local moved, why = maps.shift(map, shift)
  if not moved then error(why, 0) end
  api.undo_label("Shift keyswitches")
  keep(id, function(i) i.shift = shift ~= 0 and shift or nil end)
  M.set_attr_map(id, M.compile(moved, info.default))
  return moved
end

--- Take the binding away: the notes keep their attributes.
function M.unbind(track)
  local id = track_of(track)
  pcall(api.track_set, id, "attr_map", nil)
  keep(id, function(info)
    for k in pairs(info) do info[k] = nil end
  end)
  paw.emit("articulations.bound", { track = id })
end

--- The articulation of a map an attribute plays, by M2-123's fallback, and
--- whether it is the very one asked for.
function M.resolve(map, attr)
  if not m2.is(attr) then return nil end
  for i, want in ipairs(m2.fallbacks(attr)) do
    if type(want) == "string" then
      local art = map.by_code[want]
      if art then return art, i == 1 end
    else
      for _, art in ipairs(map.arts) do
        if art.attr.type == want.type and m2.parts(art.attr).subclass == want.subclass then return art, false end
      end
    end
  end
end

--- The track's default articulation of its map.
function M.default_of(track, map)
  map = map or M.map_of(track)
  if not map then return nil end
  local info = M.info(track) or {}
  return map.by_id[info.default or ""] or map.by_id[map.default]
end

--- What a note plays on a track: `art, exact, map`. `art` is the map's
--- articulation (the default for a note with none); nil with no map.
function M.of(track, note)
  local map = M.map_of(track)
  if not map then return nil end
  local attr = M.attr_of(note)
  if not attr then return M.default_of(track, map), true, map end
  local art, exact = M.resolve(map, attr)
  return art, exact, map
end

--- A note's articulation as a short tag: the map's, else the name the track
--- kept, else the code. Nil for a note with none.
function M.tag_of(track, note)
  local attr = M.attr_of(note)
  if not attr then return nil end
  local map = M.map_of(track)
  if map then
    local art = M.resolve(map, attr)
    if art then return art.tag, art end
  end
  local info = M.info(track)
  local code = m2.code(attr)
  return (info and info.names and info.names[code]) or code
end

--- Find an articulation by what a person types: an id, a tag, a name, a
--- code, or the start of an id or name. Without a map, a code or a word a
--- library would use (`pizz`). Returns `{ attr, art? }`, `false` for "none"
--- (the default plays), or nil and why.
function M.lookup(map, text)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local lower = text:lower()
  if lower == "" then return nil, "which articulation?" end
  if lower == "none" or lower == "off" or lower == "default" or lower == "-" then return false end
  if map then
    for _, field in ipairs({ "id", "tag", "code" }) do
      for _, art in ipairs(map.arts) do
        if tostring(art[field]):lower() == lower then return { attr = art.attr, art = art } end
      end
    end
    for _, art in ipairs(map.arts) do
      if art.name:lower() == lower then return { attr = art.attr, art = art } end
    end
    local digit = tonumber(text)
    if digit and map.arts[digit] and digit >= 1 and digit <= 9 then return { attr = map.arts[digit].attr, art = map.arts[digit] } end
    for _, art in ipairs(map.arts) do
      if art.id:lower():sub(1, #lower) == lower or art.name:lower():sub(1, #lower) == lower then return { attr = art.attr, art = art } end
    end
  end
  local attr = m2.parse(text)
  if not attr then
    local code = m2.guess(text)
    attr = code and m2.parse(code)
  end
  if attr then
    if map then
      local art = M.resolve(map, attr)
      return { attr = attr, art = art }
    end
    return { attr = attr }
  end
  if map then return nil, "`" .. text .. "` is no articulation of " .. map.name .. ": " .. M.names(map) end
  return nil, "`" .. text .. "` is no articulation: an M2-123 code (11.A) or a name such as staccato, pizz, trill"
end

--- A map's articulations in a few words.
function M.names(map)
  local out = {}
  for _, art in ipairs(map.arts) do out[#out + 1] = art.id end
  return table.concat(out, ", ")
end

-- Setting ----------------------------------------------------------------------------

--- Give notes an articulation: `places` are `{ clip = id, place = n }`
--- (a note's place among its clip's notes), `choice` what `lookup` gives
--- (false: none). One edit per clip.
function M.set(places, choice)
  local attr = choice and choice.attr or nil
  local by_clip, order = {}, {}
  for _, p in ipairs(places) do
    if not by_clip[p.clip] then
      by_clip[p.clip] = {}
      order[#order + 1] = p.clip
    end
    by_clip[p.clip][p.place] = true
  end
  local changed = 0
  for _, id in ipairs(order) do
    local notes = api.clip_notes(id)
    local set = {}
    for place in pairs(by_clip[id]) do
      local n = notes[place]
      if n and not M.same(M.attr_of(n), attr) then
        set[#set + 1] = util.merge(M.attr_fields(n, attr), { index = place })
      end
    end
    table.sort(set, function(a, b) return a.index < b.index end)
    if #set > 0 then
      paw.clip(id):edit_notes({ set = set })
      changed = changed + #set
    end
  end
  return changed
end

--- Set a track's default articulation (by id), or its pen (`which = "pen"`,
--- nil for none).
function M.set_track(track, which, art_id)
  keep(track, function(info) info[which] = art_id end)
  if which == "default" then
    local map = M.map_of(track)  -- with its shift
    if map then M.set_attr_map(track, M.compile(map, art_id)) end
  end
end

--- The pen of a track: the choice new notes get, or nil.
function M.pen(track)
  local info = M.info(track)
  if not info or not info.pen then return nil end
  local map = M.map_of(track)
  if map and map.by_id[info.pen] then return { attr = map.by_id[info.pen].attr, art = map.by_id[info.pen] } end
  local attr = m2.parse(info.pen)
  return attr and { attr = attr } or nil
end

--- Every note of a clip with its articulation, in time: `{ note, place, art, tag, attr }`.
function M.runs(clip_id)
  local c = api.clip_get(clip_id)
  local out = {}
  for place, n in ipairs(api.clip_notes(clip_id)) do
    local tag, art = M.tag_of(c.track, n)
    out[#out + 1] = { note = n, place = place, attr = M.attr_of(n), tag = tag, art = art }
  end
  return out
end

return M
