-- What depends on the renderer: AI pitch and its takes, timbre takes, the
-- renderer's own curves (energy, voice colour blends, ...), unison, and the
-- engine's track options. These are DiffSinger's (and similar engines');
-- a classic UTAU voicebank sings the same without them.
--
-- Takes are kept by the engine (engine/PawUtau.Engine/AiPitch.cs, in its cache folder,
-- across sessions); this side asks for them with the `retake` batch edit
-- and keeps what the engine answers about each note. Timing takes are
-- stored in the project instead: a seeded offset of each note's first
-- phoneme.
local api = paw.api
local utau = require("utau")
local proto = require("utau.proto")
local json = require("utau.json")
local engine = utau.engine

local M = {
  pending = {}, -- request id -> { action, kind, clip, sent }
  info = {}, -- clip id -> note id -> { current, count, vcurrent, vcount, phrase }
  last = nil, -- the last answer: { ok, message, error, changed }
}

local request = 0

-- Track options ------------------------------------------------------------------

--- Set one engine option of a vocal track (`nil` or "" clears it).
function M.set_option(track_id, key, value)
  local options = {}
  for k, v in pairs(type(utau.config(track_id).options) == "table" and utau.config(track_id).options or {}) do
    options[k] = v
  end
  if value == nil or value == "" then
    options[key] = nil
  else
    options[key] = tostring(value)
  end
  utau.configure(track_id, { options = next(options) and options or false })
end

function M.option(track_id, key)
  local options = utau.config(track_id).options
  return type(options) == "table" and options[key] or nil
end

--- AI pitch on or off for a track: on, the renderer's pitch model sings and
--- the drawn pitch is added on top; off, the notes and drawn pitch alone.
function M.ai_pitch(track_id, on) M.set_option(track_id, "pitchmode", (not on) and "manual" or nil) end

--- Unison: `voices` voices (1 is off), with `opts` spacing (stereo %),
--- pitch (detune cents), timing (ms), level (dB of the doubles).
function M.unison(track_id, voices, opts)
  opts = opts or {}
  voices = math.floor(tonumber(voices) or 1)
  M.set_option(track_id, "unison", voices >= 2 and math.min(voices, 16) or nil)
  for _, k in ipairs({ "spacing", "pitch", "timing", "level" }) do
    if opts[k] ~= nil then M.set_option(track_id, "unison_" .. k, opts[k]) end
  end
end

--- Sing a track higher or lower without moving its notes: semitones, cents.
function M.shift(track_id, semitones, cents)
  M.set_option(track_id, "keyshift", semitones and semitones ~= 0 and math.floor(semitones) or nil)
  M.set_option(track_id, "pitchshift", cents and cents ~= 0 and cents or nil)
end

-- Takes ------------------------------------------------------------------------------

--- The note ids the engine knows a clip's notes by: their places in the clip.
local function note_ids(clip_id, which)
  local ids = {}
  for index in ipairs(api.clip_notes(clip_id)) do
    if not which or which[index] then ids[#ids + 1] = index end
  end
  return ids
end

--- Ask the engine for a take: `action` "new", "prev", "next", "select"
--- (with `opts.index`) or "info"; `opts.kind` "pitch" (default) or
--- "timbre"; `opts.notes` a set of note places (all notes when absent);
--- `opts.whole` retakes the whole phrases. Returns the request id, or nil
--- when the engine is not connected.
function M.retake(clip_id, action, opts)
  opts = opts or {}
  local args = { action = action, kind = opts.kind or "pitch" }
  if opts.index then args.index = opts.index end
  if opts.whole then args.whole = true end
  local ids = opts.notes and note_ids(clip_id, opts.notes) or {}
  args.notes = json.array(ids)
  request = request + 1
  local ok = engine.send(proto.encode.run_batch_edit({
    request = request,
    name = "retake",
    vparts = { tostring(clip_id) },
    notes = ids,
    args = json.encode(args),
  }))
  if not ok then return nil end
  M.pending[request] = { action = action, kind = args.kind, clip = clip_id, sent = api.now() }
  return request
end

engine.handlers.BatchEditResult = function(m)
  local p = M.pending[m.request]
  if not p then return end
  M.pending[m.request] = nil
  local ok, v = pcall(json.decode, m.message or "")
  if not ok then v = nil end
  local answer = {
    ok = m.ok,
    message = m.message,
    error = type(v) == "table" and v.error or nil,
    changed = type(v) == "table" and v.changed or 0,
    action = p.action,
    kind = p.kind,
    clip = p.clip,
  }
  if type(v) == "table" and type(v.phrases) == "table" then
    local notes = M.info[p.clip] or {}
    M.info[p.clip] = notes
    for _, ph in ipairs(v.phrases) do
      for _, id in ipairs(ph.notes or {}) do
        notes[id] = {
          current = ph.current,
          count = ph.count,
          vcurrent = ph.vcurrent or 0,
          vcount = ph.vcount or 1,
          phrase = ph.hash,
        }
      end
    end
  end
  M.last = answer
  if p.action ~= "info" then
    if not m.ok or answer.error then
      paw.notify("utau: " .. tostring(answer.error or m.message), "warn")
    elseif answer.changed > 0 then
      paw.notify(
        string.format(
          "utau: %s take for %d phrase%s, singing it",
          p.kind,
          answer.changed,
          answer.changed == 1 and "" or "s"
        )
      )
    else
      paw.notify("utau: no other " .. p.kind .. " take there")
    end
  end
  api.ui_redraw()
end

--- What the engine said about a note's takes, or nil.
function M.take_info(clip_id, index) return M.info[clip_id] and M.info[clip_id][index] end

M.TIMING_RANGE = 18 -- ticks either way

--- The onset offset, in ticks, a timing take gives a note: repeatable for
--- the same note and take, within ±range, small more often than large.
function M.timing_offset(id, take, range)
  local s = ((id or 0) * 2654435761 + take * 40503) % 4294967296
  s = (s * 1103515245 + 12345) % 2147483648
  local u = s / 2147483648 * 2 - 1
  return math.floor(u * math.abs(u) * (range or M.TIMING_RANGE) + 0.5)
end

--- A timing take for notes of a clip: each sung note's first phoneme moves
--- by a seeded offset; take 0 takes the offsets away. One edit. Returns how
--- many notes changed.
function M.timing(clip_id, take, which, range)
  local notes = require("utau.notes")
  return notes.change_props(clip_id, function(props, note, index)
    local lyric = note.meta.lyric
    if lyric == "R" or lyric == "r" or lyric == "+" or lyric == "-" then return false end
    local offset = take and take > 0 and M.timing_offset(index, take, range) or nil
    if offset == 0 then offset = nil end
    local ph, found, changed = {}, false, false
    for _, p in ipairs(props.ph or {}) do
      if p.index == 0 then
        found = true
        local q = notes.copy(p)
        if q.offset ~= offset then changed = true end
        q.offset = offset
        if next(q, nil) and (q.phoneme or q.offset or q.pre or q.ovl or q.atk or q.rel) then ph[#ph + 1] = q end
      else
        ph[#ph + 1] = p
      end
    end
    if not found and offset then
      table.insert(ph, 1, { index = 0, offset = offset })
      changed = true
    end
    props.ph = #ph > 0 and ph or nil
    return changed
  end, which)
end

-- The renderer's own curves ----------------------------------------------------------

--- The renderer a vocal track sings with: its own setting, else the one
--- the engine lists for its singer's type.
function M.renderer_of(track_id)
  local config = utau.config(track_id)
  local list = utau.renderers.renderers or {}
  if config.renderer then
    for _, r in ipairs(list) do
      if r.id == config.renderer or r.name == config.renderer then return r end
    end
  end
  local singer = config.singer and utau.find_singer(config.singer)
  for _, r in ipairs(list) do
    for _, t in ipairs(r.singer_types or {}) do
      if singer and t:lower() == tostring(singer.type):lower() then return r end
    end
  end
end

local STANDARD = {}
for _, abbr in ipairs(utau.CURVES) do
  STANDARD[abbr] = true
end

--- The curves the renderer offers beyond the standard ones.
function M.extra_expressions(track_id)
  local out = {}
  local r = M.renderer_of(track_id)
  for _, e in ipairs(r and r.expressions or {}) do
    if e.kind == 1 and not STANDARD[e.abbr] then out[#out + 1] = e end
  end
  return out
end

--- Draw one of the renderer's curves on a free slot of the track's device
--- (`x1` .. `x8`). `desc` is `{ abbr, min, max, default }`, as the engine
--- describes it. Returns the slot. An abbreviation already drawn keeps its slot.
function M.add_curve(track_id, desc)
  local device = utau.device_of(track_id)
  if not device then error("not a vocal track", 0) end
  local config = utau.config(track_id)
  local map = {}
  for k, v in pairs(type(config.curves) == "table" and config.curves or {}) do
    map[k] = v
  end
  for slot, c in pairs(map) do
    if c.abbr == desc.abbr then return slot end
  end
  for _, slot in ipairs(utau.EXTRA) do
    if not map[slot] then
      map[slot] = { abbr = desc.abbr, name = desc.name, min = desc.min, max = desc.max, default = desc.default or 0 }
      utau.configure(track_id, { curves = map })
      api.device_set_param(device, slot, desc.default or 0)
      return slot
    end
  end
  error("all " .. #utau.EXTRA .. " renderer curve slots are in use", 0)
end

--- Stop drawing a renderer curve: its lane goes, and the engine is told to
--- forget it.
function M.remove_curve(track_id, abbr)
  local device = utau.device_of(track_id)
  local config = utau.config(track_id)
  local map = {}
  for k, v in pairs(type(config.curves) == "table" and config.curves or {}) do
    map[k] = v
  end
  for slot, c in pairs(map) do
    if c.abbr == abbr then
      local lane = require("utau.notes").lane(track_id, device, slot)
      if lane then api.lane_remove(lane) end
      api.device_set_param(device, slot, 0)
      map[slot] = nil
      utau.configure(track_id, { curves = next(map) and map or false })
      return slot
    end
  end
end

--- The slot a renderer curve is drawn on, or nil.
function M.slot_of(track_id, abbr)
  for _, x in ipairs(utau.extra_curves(track_id)) do
    if x.abbr == abbr then return x.key end
  end
end

return M
