-- Drum parts. A drum part is an ordinary part whose clips are ordinary
-- MIDI clips; what makes it one is a drum map kept in `part.meta.drums`:
-- which notes are which pieces, in which order, with what names. The drum
-- grid (`drums.grid`, one view for the terminal and a window) shows a clip
-- through that map, whatever instrument plays it.
--
--   local drums = require("drums")
--   local part = drums.make_part({ name = "Beat" })     -- the built-in kit and the GM map
--   drums.set_map(some_part, "gm-full")                    -- any part, any instrument
--   drums.rows(part)                                       -- { { note = 36, name = "Kick" }, ... }
local api = paw.api
local util = paw.util
local music = paw.music

local M = {}
M.maps = require("drums.maps")

--- The colour new drum parts get: the theme's gold.
M.colour = "#e8c765"

local function part_of(which)
  if type(which) == "table" then return which end
  return paw.part(which)
end

local function copy_rows(rows)
  local out = {}
  for i, row in ipairs(rows) do
    out[i] = { note = music.pitch(row.note), name = tostring(row.name or music.name(music.pitch(row.note))) }
  end
  return out
end

--- What a part keeps of its drum map, or nil if it is not a drum part.
function M.info(which)
  local ok, meta = pcall(function() return part_of(which).meta end)
  local info = ok and type(meta) == "table" and meta.drums
  if type(info) == "table" and type(info.rows) == "table" then return info end
end

function M.is_drum(which) return M.info(which) ~= nil end

--- Make a part a drum part with a map: the name of one in `drums.maps`,
--- or a list of rows `{ note, name }`. `label` names a list of rows.
function M.set_map(which, map, label)
  local part = part_of(which)
  local rows, name
  if type(map) == "table" then
    rows, name = map, label or "custom"
  else
    name = map or paw.opt.drums_map
    local def = M.maps[name]
    if not def then
      error("no drum map `" .. tostring(name) .. "`: there are " .. table.concat(M.map_names(), ", "), 0)
    end
    rows = def.rows
  end
  if #rows == 0 then error("a drum map needs at least one row", 0) end
  local meta = part.meta or {}
  meta.drums = { map = name, rows = copy_rows(rows) }
  part.meta = meta
  return meta.drums
end

--- Make a drum part an ordinary part again: its clips open in the piano roll.
function M.clear_map(which)
  local part = part_of(which)
  local meta = part.meta or {}
  if meta.drums == nil then return end
  meta.drums = nil
  -- An empty table would cross over as a list; one key keeps it a table.
  if next(meta) == nil then meta = { drums_was = true } end
  part.meta = meta
  if paw.api.part_get(part.id, "kind") == "drums" then paw.api.part_set(part.id, "kind", nil) end
end

--- The names of the maps there are, sorted.
function M.map_names()
  local out = {}
  for name, def in pairs(M.maps) do
    if type(def) == "table" and type(def.rows) == "table" then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

--- The rows a clip is shown with: the part's map, then a row for each
--- note the clip has that the map does not name, so that nothing is hidden.
--- Each row is `{ note, name }`; the extra ones have `extra = true`.
function M.rows(which, clip)
  local info = M.info(which)
  local out, named = {}, {}
  for i, row in ipairs(info and info.rows or {}) do
    out[i] = { note = row.note, name = row.name }
    named[row.note] = true
  end
  if clip then
    local extra = {}
    for _, n in ipairs(api.clip_notes(type(clip) == "table" and clip.id or clip)) do
      if not named[n.pitch] then
        named[n.pitch] = true
        extra[#extra + 1] = n.pitch
      end
    end
    table.sort(extra)
    for _, pitch in ipairs(extra) do
      out[#out + 1] = { note = pitch, name = M.maps.gm_names[pitch] or music.name(pitch), extra = true }
    end
  end
  return out
end

--- The name of the piece a note plays on a part.
function M.piece(which, note)
  for _, row in ipairs(M.rows(which)) do
    if row.note == note then return row.name end
  end
  return M.maps.gm_names[note] or music.name(note)
end

--- A new drum part, ready to program: the built-in kit (or `opts.kit`, a
--- folder of samples, see `drums.kit`), a map, a name and a colour.
--- `opts`: `name`, `index`, `map`, `kit`, `colour`.
function M.make_part(opts)
  opts = opts or {}
  return paw.part_kinds.add("drums", util.merge(opts, { name = opts.name or "Drums" }))
end

--- Make an ordinary part a drum part: its colour, the kit (`opts.kit`, a
--- folder of samples, or the built-in one) and the map (`opts.map`). What a
--- drum part is made with, as a kind of part.
function M.dress(part, opts)
  part.color = opts.colour or M.colour
  if opts.kit and opts.kit ~= "builtin" then
    require("drums.kit").build(part, opts.kit, { map = opts.map })
  else
    part:add_device("drums")
    M.set_map(part, opts.map)
  end
end

--- Sound one piece now, on the part's own instrument.
function M.hear(which, note, velocity)
  local part = part_of(which)
  part:play_note(note, velocity or paw.opt.drums_velocity, 150)
end

--- Clamp a velocity to MIDI's.
function M.clamp_velocity(v) return util.clamp(math.floor(v + 0.5), 1, 127) end

return M
