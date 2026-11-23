-- Kits of samples: one audio file per note, played by the built-in `sampler`
-- device. The kit is the device's state (see crates/paw-engine/src/devices/
-- sampler.rs), so it is saved with the project, undone like any edit, and
-- heard in renders; this module reads and writes it as a list of pads:
--
--   { note = 36, file = "/samples/kick.wav", level = 0, pan = 0, tune = 0, group = 0 }
--
-- `level` is in dB, `pan` from -1 to 1, `tune` in semitones; pads of the same
-- `group` above 0 cut each other off, as hats do.
--
--   local kit = require("drums.kit")
--   kit.build(part, "~/samples/808")       -- a pad for every sound file, by its name
--   kit.set_pad(device, 42, { level = -4 })
local api = paw.api
local drums = require("drums")

local M = {}

--- A kit's pads as the device's state, and back.
function M.encode(pads)
  local lines = { "sampler 1" }
  for _, p in ipairs(pads) do
    lines[#lines + 1] = string.format(
      "%d %s %s %s %d %s",
      p.note,
      tostring(p.level or 0),
      tostring(p.pan or 0),
      tostring(p.tune or 0),
      p.group or 0,
      p.file
    )
  end
  return table.concat(lines, "\n") .. "\n"
end

function M.decode(text)
  local pads = {}
  for line in (text or ""):gmatch("[^\n]+") do
    local note, level, pan, tune, group, file = line:match("^(%d+) (%S+) (%S+) (%S+) (%d+) (.+)$")
    if note then
      pads[#pads + 1] = {
        note = tonumber(note),
        level = tonumber(level),
        pan = tonumber(pan),
        tune = tonumber(tune),
        group = tonumber(group),
        file = file,
      }
    end
  end
  return pads
end

local function device_of(which)
  if type(which) == "number" then return paw.device(which) end
  return which
end

--- The sampler on a part, if it has one.
function M.device(part)
  if type(part) == "number" then part = paw.part(part) end
  return part:device("sampler")
end

--- A sampler's pads, sorted by note.
function M.pads(device)
  device = device_of(device)
  local state = api.device_state(device.id)
  local pads = M.decode(state and paw.bytes.unbase64(state) or "")
  table.sort(pads, function(a, b) return a.note < b.note end)
  return pads
end

--- Give a sampler its pads: one edit, undone like any other.
function M.set_pads(device, pads)
  device = device_of(device)
  table.sort(pads, function(a, b) return a.note < b.note end)
  api.device_set(device.id, "state", paw.bytes.base64(M.encode(pads)))
end

--- Change one pad: `fields` of `level`, `pan`, `tune`, `group`, `file`.
--- A note with no pad gets one when `fields.file` is given.
function M.set_pad(device, note, fields)
  local pads, found = M.pads(device), nil
  for _, p in ipairs(pads) do
    if p.note == note then found = p end
  end
  if not found then
    if not fields.file then error("note " .. note .. " has no sample: give it a file", 0) end
    found = { note = note, level = 0, pan = 0, tune = 0, group = 0 }
    pads[#pads + 1] = found
  end
  for _, key in ipairs({ "level", "pan", "tune", "group", "file" }) do
    if fields[key] ~= nil then found[key] = fields[key] end
  end
  found.pan = math.max(-1, math.min(1, found.pan))
  M.set_pads(device, pads)
  return found
end

-- Naming the files ----------------------------------------------------------------

-- What a file's name says it is, tried in order: words in the name (split at
-- anything that is not a letter or a digit), and the notes to give it, the
-- first that is still free. Hats are one group, so that a closed or pedal hat
-- cuts off an open one.
M.names = {
  {
    words = { "open", "oh", "ohh", "ohat" },
    also = { "hat", "hh", "hihat", "oh", "ohh", "ohat" },
    notes = { 46 },
    group = 1,
    name = "Open hat",
  },
  {
    words = { "pedal", "foot", "ph", "phh" },
    also = { "hat", "hh", "hihat", "ph", "phh" },
    notes = { 44 },
    group = 1,
    name = "Pedal hat",
  },
  { words = { "hat", "hh", "hihat", "hats", "ch", "chh", "closed" }, notes = { 42 }, group = 1, name = "Closed hat" },
  { words = { "kick", "bd", "bassdrum", "kik", "kck" }, notes = { 36, 35 }, name = "Kick" },
  { words = { "rim", "rimshot", "stick", "sidestick", "rs" }, notes = { 37 }, name = "Rim" },
  { words = { "snare", "sd", "snr", "sn" }, notes = { 38, 40 }, name = "Snare" },
  { words = { "clap", "cp", "handclap", "clp" }, notes = { 39 }, name = "Clap" },
  { words = { "floor" }, also = { "tom", "tm" }, notes = { 41, 43 }, name = "Floor tom" },
  { words = { "low", "lo", "lt" }, also = { "tom", "tm", "lt" }, notes = { 45, 41 }, name = "Low tom" },
  { words = { "mid", "mt" }, also = { "tom", "tm", "mt" }, notes = { 47, 48 }, name = "Mid tom" },
  { words = { "high", "hi", "ht" }, also = { "tom", "tm", "ht" }, notes = { 50, 48 }, name = "High tom" },
  { words = { "tom", "tm", "toms" }, notes = { 50, 47, 45, 48, 43, 41 }, name = "Tom" },
  { words = { "bell" }, also = { "ride", "rd" }, notes = { 53 }, name = "Ride bell" },
  { words = { "ride", "rd" }, notes = { 51, 59 }, name = "Ride" },
  { words = { "crash", "cr", "cym", "cymbal" }, notes = { 49, 57 }, name = "Crash" },
  { words = { "splash" }, notes = { 55 }, name = "Splash" },
  { words = { "china" }, notes = { 52 }, name = "China" },
  { words = { "cowbell", "cb", "bell", "cow" }, notes = { 56 }, name = "Cowbell" },
  { words = { "tamb", "tambourine", "tamborine", "tam" }, notes = { 54 }, name = "Tambourine" },
  { words = { "shaker", "shake", "maraca", "maracas", "sh" }, notes = { 70 }, name = "Shaker" },
  { words = { "conga" }, notes = { 63, 64, 62 }, name = "Conga" },
  { words = { "bongo" }, notes = { 60, 61 }, name = "Bongo" },
  { words = { "clave", "claves" }, notes = { 75 }, name = "Claves" },
  { words = { "block", "woodblock", "wood" }, notes = { 76, 77 }, name = "Wood block" },
  { words = { "triangle", "tri" }, notes = { 81, 80 }, name = "Triangle" },
}

local audio = { wav = true, wave = true, aif = true, aiff = true, flac = true, mp3 = true, ogg = true }

local function words_of(name)
  local set = {}
  -- `ClosedHat` and `closed_hat` alike.
  local spaced = name:gsub("(%l)(%u)", "%1 %2"):lower()
  for word in spaced:gmatch("[%a]+") do
    set[word] = true
  end
  for word in spaced:gmatch("[%w]+") do
    set[word] = true
  end
  return set
end

--- What a file name says the sound is: the entry of `M.names`, or nil.
function M.classify(name)
  local words = words_of(name)
  for _, entry in ipairs(M.names) do
    local hit = false
    for _, w in ipairs(entry.words) do
      hit = hit or words[w]
    end
    if hit and entry.also then
      local also = false
      for _, w in ipairs(entry.also) do
        also = also or words[w]
      end
      hit = also
    end
    if hit then return entry end
  end
end

local function expand(dir)
  dir = dir:gsub("^~", os.getenv("HOME") or "~")
  if not dir:match("^/") then dir = (os.getenv("PWD") or ".") .. "/" .. dir end
  return (dir:gsub("/+$", ""))
end

--- A kit from the sound files in a folder, by their names: pads, and rows
--- for the grid named after the files, in the order of the General MIDI
--- map, then the sounds it does not know on notes from 60 up.
function M.from_folder(dir)
  dir = expand(dir)
  local ok, entries = pcall(api.read_dir, dir)
  if not ok then error("cannot read the folder " .. dir, 0) end
  local files = {}
  for _, e in ipairs(entries) do
    local ext = e.name:match("%.(%w+)$")
    if not e.is_dir and ext and audio[ext:lower()] then files[#files + 1] = e.name end
  end
  table.sort(files)
  if #files == 0 then error("no sound files (WAV, AIFF, FLAC, MP3, Ogg) in " .. dir, 0) end
  local taken, pads, rows, unknown = {}, {}, {}, {}
  for _, file in ipairs(files) do
    local stem = file:gsub("%.%w+$", "")
    local entry = M.classify(stem)
    local note
    for _, n in ipairs(entry and entry.notes or {}) do
      if not taken[n] then
        note = n
        break
      end
    end
    if note then
      taken[note] = true
      pads[#pads + 1] =
        { note = note, file = dir .. "/" .. file, level = 0, pan = 0, tune = 0, group = entry.group or 0 }
      rows[#rows + 1] = { note = note, name = stem }
    else
      unknown[#unknown + 1] = { file = file, stem = stem }
    end
  end
  local next_note = 60
  for _, u in ipairs(unknown) do
    while taken[next_note] and next_note < 127 do
      next_note = next_note + 1
    end
    taken[next_note] = true
    pads[#pads + 1] = { note = next_note, file = dir .. "/" .. u.file, level = 0, pan = 0, tune = 0, group = 0 }
    rows[#rows + 1] = { note = next_note, name = u.stem }
  end
  -- Rows in the order of the General MIDI map, as a beat reads.
  local order = {}
  for i, row in ipairs(drums.maps.gm.rows) do
    order[row.note] = i
  end
  table.sort(rows, function(a, b)
    local oa, ob = order[a.note] or 100 + a.note, order[b.note] or 100 + b.note
    return oa < ob
  end)
  return pads, rows, dir
end

--- Give a part a kit from a folder: a sampler with a pad per file (in
--- place of the built-in kit if it has one) and a drum map whose rows are
--- named after the files. Returns the sampler.
function M.build(part, dir, opts)
  if type(part) == "number" then part = paw.part(part) end
  local pads, rows, path = M.from_folder(dir)
  local device = M.device(part)
  if not device then
    local builtin = part:device("drums")
    local index = builtin and builtin.index or 1
    device = part:add_device("sampler", nil, { index = index })
    if builtin then builtin:remove() end
  end
  M.set_pads(device, pads)
  drums.set_map(part, rows, "kit: " .. path:match("[^/]+$"))
  local _ = opts
  return device
end

return M
