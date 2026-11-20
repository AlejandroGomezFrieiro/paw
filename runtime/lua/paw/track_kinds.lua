-- `paw.track_kinds`: kinds of track that extensions define.
--
-- A track is a track: clips, devices, a fader. A kind says what a track is
-- for, and so how it is made and how its clips are edited: a vocal track is
-- made with a singing device and its clips open in the vocal editor, a drum
-- track's in the drum grid. An extension defines one:
--
--   paw.track_kinds.define("vocal", {
--     title = "Vocal track",            -- how it is offered and described
--     letter = "V",                     -- what the track header shows before the name
--     create = function(track, args) end, -- make an ordinary track this kind
--     editor = function(clip) return true end, -- open a clip (Enter, double click, clip.edit)
--     describe = function(track) return "Kitane" end, -- a few words for K and the header
--     is = function(track) end,         -- a track that is of the kind without saying so
--   })
--
-- and from then on `:track.add vocal` (or `kind=vocal`), `:track.new` (a
-- list of every kind), the window's buttons and menus that make a track,
-- the track header, `K` and `clip.edit` all know it. The kind is kept in the
-- track's `meta.kind`, saved with the project: opened without the
-- extension, the track is an ordinary one, and `K` says which kind it was.
local api = paw.api

local M = { kinds = {}, order = {} }

local function track_of(which)
  if type(which) == "table" then return which end
  return paw.track(which)
end

--- Define a kind of track (see above). `name` is a word: what is typed
--- after `:track.add` and kept in the track's `meta.kind`.
--- @type function(name: string, spec: contracts.TrackKind): contracts.TrackKind
function M.define(name, spec)
  if type(name) ~= "string" or not name:match("^[%w_]+$") then error("a kind of track is named by a word", 2) end
  if type(spec) ~= "table" then error("track_kinds.define takes a name and a table", 2) end
  spec.name = name
  spec.title = spec.title or (name:sub(1, 1):upper() .. name:sub(2) .. " track")
  spec.letter = spec.letter or name:sub(1, 1):upper()
  if not M.kinds[name] then M.order[#M.order + 1] = name end
  M.kinds[name] = spec
  local label = "New " .. spec.title:sub(1, 1):lower() .. spec.title:sub(2)
  local menu = paw.frontend.menus.timeline
  for i = #menu, 1, -1 do
    if menu[i].track_kind == name then table.remove(menu, i) end
  end
  table.insert(menu, { label = label, command = "track.add kind=" .. name, track_kind = name })
  return spec
end

--- Forget a kind: no longer offered, nor in the menus. Tracks that keep
--- it are ordinary tracks again until something defines it.
function M.remove(name)
  M.kinds[name] = nil
  for i = #M.order, 1, -1 do
    if M.order[i] == name then table.remove(M.order, i) end
  end
  local menu = paw.frontend.menus.timeline
  for i = #menu, 1, -1 do
    if menu[i].track_kind == name then table.remove(menu, i) end
  end
end

--- The defined kinds, in the order they were defined.
function M.list()
  local out = {}
  for i, name in ipairs(M.order) do out[i] = M.kinds[name] end
  return out
end

--- The name of the kind of a track: the kind that it keeps. If not, a kind
--- whose `is` claims it. Nil for a usual track.
function M.of(which)
  local ok, t = pcall(function() return track_of(which):get() end)
  if not ok or not t or t.master then return nil end
  local meta = type(t.meta) == "table" and t.meta or {}
  if type(meta.kind) == "string" then return meta.kind end
  for _, name in ipairs(M.order) do
    local spec = M.kinds[name]
    if spec.is and spec.is(t.id) then return name end
  end
end

--- A track's kind as defined, or nil (an ordinary track, or a kind that no
--- loaded extension defines).
function M.spec(which)
  local name = M.of(which)
  return name and M.kinds[name]
end

--- Make a track of `name`'s kind: keep the kind on it, then let the kind
--- make it what it is. `args` go to `create`.
function M.set(which, name, args)
  local spec = M.kinds[name]
  if not spec then error("no kind of track `" .. tostring(name) .. "`" .. M.known_words(), 2) end
  local track = track_of(which)
  local meta = track.meta or {}
  meta.kind = name
  track.meta = meta
  if spec.create then spec.create(track, args or {}) end
  return track
end

--- A new track of the kind `name`. `opts.name` is its name (if not given,
--- the title of the kind without "track"), and `opts.index` its place. The
--- other options go to `create`.
function M.add(name, opts)
  opts = opts or {}
  local spec = M.kinds[name]
  if not spec then error("no kind of track `" .. tostring(name) .. "`" .. M.known_words(), 2) end
  local track = paw.add_track({
    name = opts.name or spec.title:gsub("%s*[Tt]rack$", ""),
    index = opts.index,
  })
  local ok, err = pcall(M.set, track, name, opts)
  if not ok then
    -- Nothing half made is left behind.
    track:remove()
    error(err, 0)
  end
  return track
end

--- ": there are vocal, drums", for messages.
function M.known_words()
  if #M.order == 0 then return ": no extension has defined one" end
  return ": there are " .. table.concat(M.order, ", ")
end

--- A few words on a track's kind, for `K` and the track header:
--- "Vocal track · Kitane", "vocal (no extension here defines it)", or nil.
function M.describe(which)
  local name = M.of(which)
  if not name then return nil end
  local spec = M.kinds[name]
  if not spec then return name .. " (no extension here defines it)" end
  local words = spec.describe and spec.describe(track_of(which).id)
  if words and words ~= "" then return spec.title .. " · " .. words end
  return spec.title
end

--- Make a track an ordinary one again, as far as its kind goes: what the
--- kind made (its devices) stays, for the extension to take away.
function M.clear(which)
  local track = track_of(which)
  local meta = track.meta or {}
  if meta.kind == nil then return end
  meta.kind = nil
  -- An empty table would cross over as a list; one key keeps it a table.
  if next(meta) == nil then meta = { kind_was = true } end
  track.meta = meta
end

--- Open a clip in its track's kind's editor. True when it did.
function M.open(clip)
  local data = type(clip) == "table" and clip:get() or api.clip_get(clip)
  local spec = M.spec(data.track)
  if spec and spec.editor then return spec.editor(paw.clip(data.id)) == true end
  return false
end

-- Enter, a double click and `clip.edit` ask the track's kind first.
table.insert(paw.frontend.openers, 1, M.open)

-- The kind's letter in the track header, in the free column before the name.
paw.ui.layer("arrange", "header", "track_kinds", 20, function(c)
  local spec = M.spec(c.track)
  if spec then c.buf:text(c.x, c.y, spec.letter:sub(1, 1), "TrackIndex") end
end)

return M
