-- The reference model of the end-to-end tests: what a project SHOULD hold
-- after each action of a scenario. It is plain Lua, with no `paw`: it does
-- not share a line with the code that it checks. It reads the MIDI and WAV
-- files of the assets with its own small readers, for the same reason.
--
-- The state is plain data:
--
--   { tempo, markers = { { name, beat, length } },  -- a region has a length
--     parts = { { name, color, volume, pan, mute, solo,
--                  devices = { kind, ... }, sends = { { target = name, level } },
--                  clips = { { kind, start, length, notes = { ... }, file } } | ANY,
--                  notes = { { pitch, start, length, velocity } },
--                  lanes = { { target, points = { { beat, value } } } } } } }
--
-- `part.notes` is every note of the part at its time in the song (in
-- beats), sorted. `clips` is the layout of the clips, or `M.ANY` where the
-- scenario does not say it (the clips of an imported MIDI file). `ANY` in
-- any field means "not checked".
local M = {}

M.ANY = setmetatable({}, { __tostring = function() return "<any>" end })

function M.new() return { tempo = 120, markers = {}, parts = {} } end

local function copy(v)
  if type(v) ~= "table" or v == M.ANY then return v end
  local out = {}
  for k, x in pairs(v) do
    out[k] = copy(x)
  end
  return out
end
M.copy = copy

function M.part(state, name)
  for i, t in ipairs(state.parts) do
    if t.name == name then return t, i end
  end
  error("the model has no part " .. tostring(name), 2)
end

function M.new_part(name)
  return {
    name = name,
    color = nil,
    volume = 0,
    pan = 0,
    mute = false,
    solo = false,
    devices = {},
    sends = {},
    clips = {},
    notes = {},
    lanes = {},
  }
end

--- Add an automation point `{ beat, value }` to the lane of `target` of a
--- part ("volume", "pan"). A point at the beat of another replaces it, as
--- docs/reference/automation.md says ("over what the lane had there").
function M.automate(part, target, beat, value)
  local lane
  for _, l in ipairs(part.lanes) do
    if l.target == target then lane = l end
  end
  if not lane then
    lane = { target = target, points = {} }
    part.lanes[#part.lanes + 1] = lane
    table.sort(part.lanes, function(a, b) return a.target < b.target end)
  end
  for i = #lane.points, 1, -1 do
    if math.abs(lane.points[i][1] - beat) < 1e-9 then table.remove(lane.points, i) end
  end
  lane.points[#lane.points + 1] = { beat, value }
  table.sort(lane.points, function(a, b) return a[1] < b[1] end)
end

local function note_order(a, b)
  if a.start ~= b.start then return a.start < b.start end
  if a.pitch ~= b.pitch then return a.pitch < b.pitch end
  return a.length < b.length
end

--- Make `part.notes` again from its clips (where the clips are known).
function M.renote(part)
  if part.clips == M.ANY then return end
  local out = {}
  for _, c in ipairs(part.clips) do
    for _, n in ipairs(c.notes or {}) do
      out[#out + 1] = { pitch = n.pitch, start = c.start + n.start, length = n.length, velocity = n.velocity }
    end
  end
  table.sort(out, note_order)
  part.notes = out
end

--- Markers and regions in the order of time; at one beat, by name.
function M.marker_order(a, b)
  if a.beat ~= b.beat then return a.beat < b.beat end
  return a.name < b.name
end

function M.sort_notes(list)
  table.sort(list, note_order)
  return list
end

-- Comparison ----------------------------------------------------------------

local EPS = 1e-6

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  if v == M.ANY then return "<any>" end
  local parts = {}
  for k, x in pairs(v) do
    if type(x) ~= "table" then parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
  end
  table.sort(parts)
  return "{" .. table.concat(parts, " ") .. "}"
end
M.show = show

--- The differences between `want` (the model) and `got` (what paw holds),
--- as lines "path: want X, got Y". Only the fields that the model has are
--- compared; a field `ANY` is not.
function M.diff(want, got, path, out)
  out = out or {}
  path = path or "project"
  if want == M.ANY then return out end
  if type(want) == "number" and type(got) == "number" then
    if math.abs(want - got) > EPS * math.max(1, math.abs(want)) then
      out[#out + 1] = string.format("%s: want %.9g, got %.9g", path, want, got)
    end
  elseif type(want) ~= "table" then
    if want ~= got then out[#out + 1] = string.format("%s: want %s, got %s", path, show(want), show(got)) end
  elseif type(got) ~= "table" then
    out[#out + 1] = string.format("%s: want %s, got %s", path, show(want), show(got))
  elseif #want > 0 or #got > 0 then
    if #want ~= #got then out[#out + 1] = string.format("%s: want %d items, got %d", path, #want, #got) end
    for i = 1, math.min(#want, #got) do
      local label = type(want[i]) == "table" and want[i].name and (path .. "[" .. want[i].name .. "]")
        or (path .. "[" .. i .. "]")
      M.diff(want[i], got[i], label, out)
    end
  else
    local keys = {}
    for k in pairs(want) do
      keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      M.diff(want[k], got[k], path .. "." .. tostring(k), out)
    end
  end
  return out
end

-- Files of the assets, read without paw ---------------------------------------

local function read(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("*a")
  f:close()
  return data
end

local function u16(s, i) return s:byte(i) * 256 + s:byte(i + 1) end
local function u32(s, i) return ((s:byte(i) * 256 + s:byte(i + 1)) * 256 + s:byte(i + 2)) * 256 + s:byte(i + 3) end
local function le16(s, i) return s:byte(i) + s:byte(i + 1) * 256 end
local function le32(s, i) return le16(s, i) + le16(s, i + 2) * 65536 end

--- The tracks of a Standard MIDI File that have notes: `{ { name, notes } }`,
--- notes in beats from the start of the file, sorted.
function M.read_midi(path)
  local s = read(path)
  assert(s:sub(1, 4) == "MThd", path .. " is not a MIDI file")
  local ntracks, ppq = u16(s, 11), u16(s, 13)
  local at = 9 + u32(s, 5)
  local parts = {}
  for _ = 1, ntracks do
    assert(s:sub(at, at + 3) == "MTrk", "a track chunk")
    local stop = at + 8 + u32(s, at + 4)
    local i, tick, status, name = at + 8, 0, 0, nil
    local open, notes = {}, {}
    local function varlen()
      local v = 0
      repeat
        local b = s:byte(i)
        i = i + 1
        v = v * 128 + b % 128
      until b < 128
      return v
    end
    while i < stop do
      tick = tick + varlen()
      local b = s:byte(i)
      if b >= 0x80 then
        status = b
        i = i + 1
      end
      if status == 0xFF then
        local kind = s:byte(i)
        i = i + 1
        local len = varlen()
        if kind == 0x03 and not name then name = s:sub(i, i + len - 1) end
        i = i + len
      elseif status == 0xF0 or status == 0xF7 then
        i = i + varlen()
      else
        local hi, ch = math.floor(status / 16), status % 16
        local d1, d2 = s:byte(i), s:byte(i + 1)
        if hi == 0xC or hi == 0xD then
          i = i + 1
        else
          i = i + 2
        end
        local key = ch * 128 + (d1 or 0)
        if hi == 0x9 and d2 > 0 then
          open[key] = { tick = tick, velocity = d2 }
        elseif hi == 0x8 or (hi == 0x9 and d2 == 0) then
          local on = open[key]
          if on then
            notes[#notes + 1] =
              { pitch = d1, start = on.tick / ppq, length = (tick - on.tick) / ppq, velocity = on.velocity }
            open[key] = nil
          end
        end
      end
    end
    if #notes > 0 then parts[#parts + 1] = { name = name, notes = M.sort_notes(notes) } end
    at = stop
  end
  return parts
end

--- The length of a PCM WAV file in seconds.
function M.wav_seconds(path)
  local s = read(path)
  assert(s:sub(1, 4) == "RIFF" and s:sub(9, 12) == "WAVE", path .. " is not a WAV file")
  local i, rate, align = 13, nil, nil
  while i < #s do
    local id, size = s:sub(i, i + 3), le32(s, i + 4)
    if id == "fmt " then
      rate, align = le32(s, i + 12), le16(s, i + 20)
    elseif id == "data" then
      return size / align / rate
    end
    i = i + 8 + size + size % 2
  end
  error(path .. " has no data")
end

return M
