-- A MIDI clip as a language server is sent it: the document of MIDI LSP's
-- protocol (`midi/didOpen`, `midi/didChange`), as its REAPER client builds
-- it from a take (client/lib/snapshot.lua there). Times are ticks from the
-- clip's start at `PPQ` to the beat; a note's id is its own (the model's,
-- `paw://clip/7/note/41`), so `notes = { 41 }` in an answer is that note
-- wherever it has gone since.
--
-- What sounds with the clip goes along as `context`: the notes of other
-- tracks' MIDI clips that overlap it, in this clip's ticks, with their
-- track's name and devices; and the tempo map, signatures and key over it.
local api = paw.api

local M = { PPQ = 960, MAX_CONTEXT_NOTES = 4000 }

--- The URI that names a clip: `paw://clip/12`.
function M.uri(id) return "paw://clip/" .. id end

--- The clip a URI names, or nil.
function M.clip_of(uri) return tonumber(tostring(uri):match("^paw://clip/(%d+)$")) end

--- Beats as ticks of `M.PPQ` a beat, the language server's unit.
local function tick(beats) return math.floor(beats * M.PPQ + 0.5) end


local function track_info(track)
  local fx = {}
  for _, id in ipairs(track.devices or {}) do
    local ok, d = pcall(api.device_get, id)
    if ok then fx[#fx + 1] = d.name end
  end
  return { name = track.name, fx = fx, tag = paw.harmony.is_drums(track) and "drums" or nil }
end

--- The project's key at a beat as `{ root = 0..11, scale = "major" }`, as
--- `paw.harmony.key` gives it.
function M.key(beat)
  local key = paw.harmony.key(beat)
  return { root = key.tonic % 12, scale = (tostring(key.mode or "major"):gsub("_", " ")) }
end

-- The notes of a clip as the protocol has them, those in `[from, to)` beats
-- of `into` (a clip's start) only, shifted into its ticks.
local function notes_of(c, into, from, to, limit)
  local out = {}
  for place, n in ipairs(api.clip_notes(c.id)) do
    -- A note trimmed off by the clip's edges is not heard, so not sent.
    if n.start >= 0 and n.start < c.length then
      local s, e = c.start + n.start, c.start + math.min(n.start + n.length, c.length)
      if (not from or e > from) and (not to or s < to) then
        out[#out + 1] = { id = n.id or place - 1, pitch = n.pitch, vel = n.velocity, start = tick(s - into), ["end"] = tick(e - into), chan = 0 }
        if limit and #out >= limit then break end
      end
    end
  end
  return out
end

-- The other tracks' MIDI clips that sound during `c`.
local function overlapping(c)
  local out = {}
  for _, track_id in ipairs(api.track_list()) do
    if track_id ~= c.track then
      for _, other in ipairs(api.clip_list(track_id)) do
        if other.kind == "midi" and not other.muted and other.start < c.start + c.length and other.start + other.length > c.start then
          out[#out + 1] = other
        end
      end
    end
  end
  return out
end

-- Signature and tempo changes over the clip, in its ticks: the first meter
-- at the bar line at or before its start, the first tempo at its start, and
-- the change after its end too (where a ramp running into it ends).
local function tempo_map(c)
  local first_bar = paw.time.bar_start(paw.time.bar_of(c.start))
  local num, den = paw.tempo.signature_at(c.start)
  local meters = { { tick = tick(first_bar - c.start), num = num, denom = den } }
  for _, s in ipairs(paw.tempo.signatures()) do
    if s.beat > c.start and s.beat < c.start + c.length then
      meters[#meters + 1] = { tick = tick(s.beat - c.start), num = s.num, denom = s.den }
    end
  end
  local in_force
  for _, t in ipairs(paw.tempo.points()) do
    if t.beat <= c.start then in_force = t end
  end
  local tempi = { { tick = 0, bpm = paw.tempo.at(c.start), ramp = in_force and in_force.ramp or nil } }
  for _, t in ipairs(paw.tempo.points()) do
    if t.beat > c.start then
      tempi[#tempi + 1] = { tick = tick(t.beat - c.start), bpm = t.bpm, ramp = t.ramp or nil }
      if t.beat >= c.start + c.length then break end
    end
  end
  return meters, tempi, tick(first_bar - c.start), num, den
end

-- The clip's controller moves, by number, as 0..127.
local function cc_lanes(c)
  local by, order = {}, {}
  for _, move in ipairs(api.clip_controls(c.id)) do
    if move.type == "cc" and not move.key and move.start >= 0 and move.start < c.length then
      if not by[move.number] then
        by[move.number] = {}
        order[#order + 1] = move.number
      end
      local list = by[move.number]
      list[#list + 1] = { tick = tick(move.start), value = math.floor(move.value * 127 + 0.5) }
    end
  end
  table.sort(order)
  local out = {}
  for _, number in ipairs(order) do out[#out + 1] = { cc = number, events = by[number] } end
  return out
end

--- A value that changes each time the data that paw would send about a clip
--- changes, and that is fast to make. It contains the notes of the clip,
--- its position, the tracks around it, the tempo map and the key. Nil when
--- the clip does not exist.
function M.key_of(id)
  local ok, c = pcall(api.clip_get, id)
  if not ok or c.kind ~= "midi" then return nil end
  local track = api.track_get(c.track)
  local parts = { tostring(c.stamp), c.start, c.length, track.name, #(track.devices or {}), c.control_count or 0 }
  for _, other in ipairs(overlapping(c)) do
    parts[#parts + 1] = string.format("%d:%s:%.9g:%.9g", other.id, tostring(other.stamp), other.start, other.length)
  end
  for _, t in ipairs(paw.tempo.points()) do parts[#parts + 1] = string.format("t%.9g,%.9g,%s", t.beat, t.bpm, tostring(t.ramp)) end
  for _, s in ipairs(paw.tempo.signatures()) do parts[#parts + 1] = string.format("s%.9g,%d/%d", s.beat, s.num, s.den) end
  local key = M.key(c.start)
  if key then parts[#parts + 1] = key.root .. key.scale end
  local text = table.concat(parts, "|")
  -- 32 bits of it: short enough to go back and forth with every request.
  local h = 5381
  for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
  return string.format("%08x", h)
end

--- The document for a clip, as `midi/didOpen` and `midi/didChange` send it,
--- under `hash` (from `key_of`). Nil when the clip is gone.
function M.build(id, hash)
  local ok, c = pcall(api.clip_get, id)
  if not ok or c.kind ~= "midi" then return nil end
  local track = api.track_get(c.track)
  local meters, tempi, bar_start, num, den = tempo_map(c)
  local context, budget = {}, M.MAX_CONTEXT_NOTES
  for _, other in ipairs(overlapping(c)) do
    if budget <= 0 then break end
    local notes = notes_of(other, c.start, c.start, c.start + c.length, budget)
    budget = budget - #notes
    if #notes > 0 then context[#context + 1] = { track = track_info(api.track_get(other.track)), notes = notes } end
  end
  return {
    uri = M.uri(id),
    hash = hash or M.key_of(id),
    ppq = M.PPQ,
    notes = notes_of(c, c.start),
    track = track_info(track),
    timesig = { num = num, denom = den },
    key = M.key(c.start),
    context = context,
    barStart = bar_start,
    cc = cc_lanes(c),
    meters = meters,
    tempi = tempi,
  }
end

--- Beats from the clip's start for a tick of its document.
function M.beats(ticks) return (tonumber(ticks) or 0) / M.PPQ end
M.tick = tick

return M
