-- Singing synthesis: vocal tracks sung by paw-utau-engine.
--
-- A vocal track is a track with a `utau` device. Its MIDI clips are the
-- engine's parts, their notes carry lyrics and note properties in
-- `note.meta` (see utau.payload), the device's automation lanes are the
-- singing curves, and the device's `meta.utau` holds the singer and the rest
-- of the track's voice. All of it is ordinary project data: saved, loaded and
-- undone like any edit. This module mirrors it to the engine, and gives the
-- device the audio that comes back.
local api = paw.api
local proto = require("utau.proto")
local payload = require("utau.payload")
local engine = require("utau.engine")
local voices = require("utau.voices")

local M = {
  engine = engine,
  voices = voices,
  -- The kind of the device that sings (devices/utau.lua).
  DEVICE = voices.DEVICE,
  singers = {}, -- SingerList from the engine
  renderers = {}, -- RendererList: { renderers, resamplers, wavtools }
  phonemizers = {},
  layouts = {}, -- track id -> { seq, phrases = { { hash, start, stop, state } } }
  received = {}, -- track id -> hash -> quality of the audio the device has
  phonemes = {}, -- clip id -> { seq, notes = { [note index] = { phonemes } } }
  pitch = {}, -- clip id -> { step, ticks = { [tick] = cents } }
  progress = nil, -- the engine's last Progress
  log = {}, -- the engine's log lines, newest last
}

M.CURVES = { "pitd", "dyn", "tenc", "brec", "genc", "voic", "shfc", "grwc", "xsy" }
-- Parameters of the device for curves of the renderer's own; which
-- expression each draws is `device.meta.utau.curves[slot]` (see utau.renderer).
M.EXTRA = { "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8" }
local TICKS = proto.TICKS

local seq = 0
local sent = nil -- the snapshot the engine last received
local expected = {} -- track id -> seq of the last change sent for it
-- The engine answers a change with a layout at once, before it has worked
-- out the new phonemes: that layout still lists the old phrases, all sung.
-- So notes sent are remembered until their phonemes come back, and the
-- track's layout is only believed when it arrived after them.
local resent = {} -- clip id -> { seq, at, track }: notes the engine has yet to phonemize
local fresh_after = {} -- track id -> the arrival a layout must come after
local arrivals = 0 -- layouts and phonemes from the engine, counted in order
-- How long to wait for phonemes that never come (ms), should the engine
-- find nothing to do for notes that were sent again.
local PHONEMIZE_GRACE = 5000
local dirty = false

-- Reading the project ----------------------------------------------------------

local round = paw.util.round

--- The `utau` device of a track, as a device id, or nil.
function M.device_of(track_id)
  for _, id in ipairs(api.track_get(track_id).devices) do
    local kind = api.device_get(id).kind
    if kind == voices.DEVICE or kind == voices.OLD_DEVICE then return id end
  end
end

--- Every vocal track as `{ track = id, device = id }`, in track order.
function M.vocal_tracks()
  local out = {}
  for _, id in ipairs(api.track_list()) do
    local device = M.device_of(id)
    if device then out[#out + 1] = { track = id, device = device } end
  end
  return out
end

--- A vocal track's voice settings: `singer`, `phonemizer`, `renderer`,
--- `resampler`, `wavtool`, `options`.
function M.config(track_id)
  local device = M.device_of(track_id)
  local meta = device and api.device_get(device).meta or {}
  return type(meta.utau) == "table" and meta.utau or {}
end

--- Whether a vocal track is frozen: sung to audio on a track of its own
--- (see utau.freeze), and no longer sung by the engine.
function M.frozen(track_id) return M.config(track_id).frozen ~= nil end

--- Change a vocal track's voice settings; `nil` values are left alone, and
--- `false` clears one. A new singer resets the others to its defaults.
function M.configure(track_id, changes)
  local device = M.device_of(track_id)
  if not device then error("track " .. tostring(track_id) .. " is not a vocal track", 2) end
  local meta = api.device_get(device).meta or {}
  local config = type(meta.utau) == "table" and meta.utau or {}
  if changes.singer and changes.singer ~= config.singer then
    -- A new singer starts from its own defaults, as in OpenUtau.
    config.phonemizer, config.renderer, config.resampler, config.wavtool, config.voice_color = nil, nil, nil, nil, nil
  end
  for key, value in pairs(changes) do
    if value == false then
      config[key] = nil
    else
      config[key] = value
    end
  end
  meta.utau = config
  api.device_set(device, "meta", meta)
end

local function value_at(points, beat)
  if #points == 0 then return nil end
  if beat <= points[1][1] then return points[1][2] end
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    if beat < b[1] then
      if b[1] <= a[1] then return b[2] end
      return a[2] + (b[2] - a[2]) * (beat - a[1]) / (b[1] - a[1])
    end
  end
  return points[#points][2]
end

--- The curves a device's lanes and parameters give one clip, as knots in
--- the clip's ticks: abbr -> { { tick, value }, ... }.
local function curves_for(clip, sources, extra)
  local out = {}
  local length = clip.length
  local list = {}
  for i, abbr in ipairs(M.CURVES) do
    list[i] = { abbr = abbr, key = abbr }
  end
  for _, x in ipairs(extra or {}) do
    list[#list + 1] = x
  end
  for _, item in ipairs(list) do
    local abbr = item.abbr
    local source = sources[item.key]
    if
      item.default
      and source
      and source.value
      and not source.points
      and math.abs(source.value - item.default) < 1e-9
    then
      source = nil
    end
    local knots = {}
    if source and source.points then
      local points = source.points
      knots[1] = { 0, value_at(points, clip.start), 1, 0 }
      for _, p in ipairs(points) do
        local beat = p[1] - clip.start
        if beat > 0 and beat < length then knots[#knots + 1] = { beat * TICKS, p[2], 1, 0 } end
      end
      knots[#knots + 1] = { length * TICKS, value_at(points, clip.start + length), 1, 0 }
    elseif source and source.value then
      knots[1] = { 0, source.value, 1, 0 }
    end
    out[abbr] = knots
  end
  return out, list
end

--- Where each curve of a vocal track comes from: an enabled lane on the
--- device's parameter, or the parameter's own value when that is not the default.
local function curve_sources(track_id, device_id, extra)
  local sources = {}
  local device = api.device_get(device_id)
  local mapped = {}
  for _, x in ipairs(extra or {}) do
    mapped[x.key] = true
  end
  for _, info in ipairs(device.param_info) do
    local value = device.params[info.key]
    if value and (mapped[info.key] or math.abs(value - info.default) > 1e-9) then
      sources[info.key] = { value = value }
    end
  end
  for _, lane in ipairs(api.lane_list(track_id)) do
    if lane.target == "param" and lane.device == device_id and lane.enabled and lane.point_count > 0 then
      sources[lane.param] = { points = api.lane_points(lane.id) }
    end
  end
  return sources
end

--- The renderer's own curves a vocal track draws, as
--- `{ { key = slot, abbr, default }, ... }`, in slot order.
function M.extra_curves(track_id)
  local out = {}
  local map = M.config(track_id).curves
  if type(map) ~= "table" then return out end
  for _, slot in ipairs(M.EXTRA) do
    local c = map[slot]
    if type(c) == "table" and type(c.abbr) == "string" then
      out[#out + 1] = { key = slot, abbr = c.abbr, default = tonumber(c.default) or 0 }
    end
  end
  return out
end

--- The project's tempo map as the engine takes it: steps of tempo, with a
--- ramp as steps of a quarter beat that each last exactly as long as the
--- ramp's stretch does. And its signatures, and a key that changes with
--- either.
function M.tempo_map()
  local tempos, sigs, key = {}, {}, {}
  local points = paw.tempo.points()
  local function add(beat, bpm)
    local tick = math.floor(beat * proto.TICKS + 0.5)
    tempos[#tempos + 1] = { tick = tick, bpm = bpm, sec = paw.tempo.beats_to_seconds(beat) }
    key[#key + 1] = tick .. ":" .. bpm
  end
  for i, p in ipairs(points) do
    local next_point = points[i + 1]
    if p.ramp and next_point then
      local beat, step = p.beat, 0.25
      while beat < next_point.beat - 1e-9 and #tempos < 20000 do
        local to = math.min(beat + step, next_point.beat)
        add(beat, (to - beat) * 60 / paw.tempo.seconds_between(beat, to))
        beat = to
      end
    else
      add(p.beat, p.bpm)
    end
  end
  for _, s in ipairs(paw.tempo.signatures()) do
    sigs[#sigs + 1] = { tick = math.floor(s.beat * proto.TICKS + 0.5), num = s.num, den = s.den, bar = s.bar - 1 }
    key[#key + 1] = s.beat .. "@" .. s.num .. "/" .. s.den
  end
  return tempos, sigs, table.concat(key, " ")
end

--- The whole project as the engine sees it.
function M.snapshot()
  local tempos, sigs, key = M.tempo_map()
  local snap = {
    tempos = tempos,
    sigs = sigs,
    tracks = {},
    parts = {},
    tempo = key,
  }
  local default_lyric = paw.opt.utau_default_lyric
  for _, vocal in ipairs(M.vocal_tracks()) do
    if M.frozen(vocal.track) then goto next_track end
    local t = api.track_get(vocal.track)
    local id = tostring(vocal.track)
    local config = M.config(vocal.track)
    local options = {}
    for key, value in pairs(type(config.options) == "table" and config.options or {}) do
      options[key] = value
    end
    if config.voice_color then options.subbank = config.voice_color end
    snap.tracks[#snap.tracks + 1] = {
      id = id,
      name = t.name,
      muted = t.mute,
      config = {
        singer = config.singer,
        phonemizer = config.phonemizer,
        renderer = config.renderer,
        resampler = config.resampler,
        wavtool = config.wavtool,
        options = options,
      },
    }
    local extra = M.extra_curves(vocal.track)
    local sources = curve_sources(vocal.track, vocal.device, extra)
    for _, clip in ipairs(api.clip_list(vocal.track)) do
      if clip.kind == "midi" then
        local part = {
          id = tostring(clip.id),
          clip = clip.id,
          track = id,
          name = clip.name,
          muted = clip.muted,
          pos = round(clip.start * TICKS),
          dur = math.max(1, round(clip.length * TICKS)),
          notes = {},
          curves = {},
        }
        for index, note in ipairs(api.clip_notes(clip.id)) do
          local lyric = payload.lyric(note, default_lyric)
          if note.start >= 0 and note.start < clip.length and lyric ~= "R" and lyric ~= "r" then
            local pos = round(note.start * TICKS)
            local stop = math.min(round((note.start + note.length) * TICKS), part.dur)
            part.notes[#part.notes + 1] = {
              id = index,
              pos = pos,
              dur = math.max(1, stop - pos),
              tone = note.pitch,
              payload = payload.encode(index, lyric, payload.props(note)),
            }
          end
        end
        local curves, list = curves_for(clip, sources, extra)
        for _, item in ipairs(list) do
          part.curves[#part.curves + 1] = { id = item.abbr, abbr = item.abbr, knots = curves[item.abbr] }
        end
        snap.parts[#snap.parts + 1] = part
      end
    end
    ::next_track::
  end
  return snap
end

-- Sending it -------------------------------------------------------------------

local function key_of(list, fn)
  local parts = {}
  for i, item in ipairs(list) do
    parts[i] = fn(item)
  end
  return table.concat(parts, "\0")
end

local function note_key(n) return n.id .. ":" .. n.pos .. ":" .. n.dur .. ":" .. n.tone .. ":" .. n.payload end

local function curve_key(c)
  return key_of(c.knots, function(k) return string.format("%.6f/%.6f", k[1], k[2]) end)
end

local function config_key(c)
  local options = {}
  for k, v in pairs(c.options) do
    options[#options + 1] = k .. "=" .. tostring(v)
  end
  table.sort(options)
  return table.concat({
    c.singer or "",
    c.phonemizer or "",
    c.renderer or "",
    c.resampler or "",
    c.wavtool or "",
    table.concat(options, ","),
  }, "\0")
end

local function track_key(t) return table.concat({ t.name, tostring(t.muted), config_key(t.config) }, "\0") end

local function part_key(p) return table.concat({ p.track, p.pos, p.dur, p.name, tostring(p.muted) }, "\0") end

local function index(list)
  local out = {}
  for _, item in ipairs(list) do
    out[item.id] = item
  end
  return out
end

local function touch(track) expected[track] = seq end

local function await_phonemes(part)
  resent[part.clip] = #part.notes > 0 and { seq = seq, at = api.now(), track = part.track } or nil
end

--- Send the whole project.
local function send_full(snap)
  seq = seq + 1
  for _, t in ipairs(snap.tracks) do
    touch(t.id)
  end
  resent, fresh_after = {}, {}
  for _, p in ipairs(snap.parts) do
    await_phonemes(p)
  end
  engine.send(proto.encode.sync_project({
    seq = seq,
    tempos = snap.tempos,
    sigs = snap.sigs,
    tracks = snap.tracks,
    parts = snap.parts,
  }))
  sent = snap
end

--- Send what changed since the engine last heard. Nothing when nothing did.
local function send_delta(snap)
  local d = {
    remove_tracks = {},
    upsert_tracks = {},
    remove_parts = {},
    upsert_parts = {},
    remove_notes = {},
    upsert_notes = {},
    curves = {},
  }
  local any = false
  local old_tracks, new_tracks = index(sent.tracks), index(snap.tracks)
  local old_parts, new_parts = index(sent.parts), index(snap.parts)
  seq = seq + 1
  if snap.tempo ~= sent.tempo then
    d.tempos, d.sigs, any = snap.tempos, snap.sigs, true
    for _, t in ipairs(snap.tracks) do
      touch(t.id)
    end
  end
  for id in pairs(old_tracks) do
    if not new_tracks[id] then
      d.remove_tracks[#d.remove_tracks + 1] = id
      any = true
    end
  end
  local voices = {}
  for _, t in ipairs(snap.tracks) do
    local old = old_tracks[t.id]
    if not old or track_key(old) ~= track_key(t) then
      d.upsert_tracks[#d.upsert_tracks + 1] = t
      touch(t.id)
      any = true
    end
    if old and config_key(old.config) ~= config_key(t.config) then voices[t.id] = true end
  end
  for id, p in pairs(old_parts) do
    if not new_parts[id] then resent[p.clip] = nil end
    if not new_parts[id] and new_tracks[p.track] then
      d.remove_parts[#d.remove_parts + 1] = id
      touch(p.track)
      any = true
    end
  end
  for _, p in ipairs(snap.parts) do
    local old = old_parts[p.id]
    if not old or part_key(old) ~= part_key(p) then
      d.upsert_parts[#d.upsert_parts + 1] = p
      touch(p.track)
      any = true
    end
    -- The engine only phonemizes notes again for a new voice when they
    -- change, so the notes of a track with a new voice are sent again.
    if not old or voices[p.track] or key_of(old.notes, note_key) ~= key_of(p.notes, note_key) then
      -- Note ids are positions in the clip, so a changed part is sent whole.
      if old and #old.notes > 0 then
        local ids = {}
        for i, n in ipairs(old.notes) do
          ids[i] = n.id
        end
        d.remove_notes[#d.remove_notes + 1] = { part = p.id, ids = ids }
      end
      d.upsert_notes[#d.upsert_notes + 1] = { part = p.id, notes = p.notes }
      await_phonemes(p)
      touch(p.track)
      any = true
    end
    local changed = {}
    local old_curves = old and index(old.curves) or {}
    for _, c in ipairs(p.curves) do
      local before = old_curves[c.abbr]
      if (before and curve_key(before) or "") ~= curve_key(c) then changed[#changed + 1] = c end
    end
    -- A curve no longer drawn (a renderer curve taken off) is cleared.
    local now_curves = index(p.curves)
    for abbr, c in pairs(old_curves) do
      if not now_curves[abbr] and #c.knots > 0 then changed[#changed + 1] = { id = abbr, abbr = abbr, knots = {} } end
    end
    if #changed > 0 then
      d.curves[#d.curves + 1] = { part = p.id, curves = changed }
      touch(p.track)
      any = true
    end
  end
  if not any then
    seq = seq - 1
    return false
  end
  d.seq = seq
  engine.send(proto.encode.apply_delta(d))
  sent = snap
  return true
end

--- Give every vocal device a voice of its own. Voices outlive tracks and
--- projects, so one that is handed out again starts empty.
function M.assign_voices()
  local used = {}
  for _, vocal in ipairs(M.vocal_tracks()) do
    local voice = math.floor(api.device_get(vocal.device).params.voice or 0)
    if voice < 1 or used[voice] then
      voice = 1
      while used[voice] do
        voice = voice + 1
      end
      api.device_set_param(vocal.device, "voice", voice)
      voices.clear(vocal.device)
      M.received[tostring(vocal.track)] = nil
    end
    used[voice] = vocal
  end
end

--- Empty the voices of every vocal track, for a project that was just loaded.
function M.clear_voices()
  M.layouts, M.received, M.phonemes, M.pitch = {}, {}, {}, {}
  M.assign_voices()
  for _, vocal in ipairs(M.vocal_tracks()) do
    voices.clear(vocal.device)
  end
end

--- Bring the engine up to date with the project now. Starts the engine when
--- there is a vocal track to sing.
function M.sync()
  dirty = false
  M.assign_voices()
  if #M.vocal_tracks() == 0 and engine.state == "off" then return end
  if engine.state == "off" then engine.start() end
  if not engine.connected() or engine.state == "failed" then return end
  local snap = M.snapshot()
  if not sent then
    send_full(snap)
  else
    send_delta(snap)
  end
end

--- Sync at the end of this turn, once, however many edits it made.
function M.schedule()
  if dirty then return end
  dirty = true
  paw.defer(function()
    if dirty then M.sync() end
  end, 0)
end

function M.send_transport()
  local t = api.transport_get()
  local sec = paw.tempo.beats_to_seconds(t.position)
  engine.send(proto.encode.transport(t.playing, sec, paw.tempo.beats_to_seconds(paw.cursor.beat)))
end

engine.on_connect = function()
  sent = nil
  engine.send(proto.encode.render_policy({
    draft = paw.opt.utau_drafts,
    final_delay_ms = paw.opt.utau_final_delay,
  }))
  engine.send(proto.encode.request_singers(false))
  M.sync()
  M.send_transport()
end

-- What comes back ----------------------------------------------------------------

local function vocal_device(track_key_str)
  local id = tonumber(track_key_str)
  return id and pcall(api.track_get, id) and M.device_of(id)
end

local function put(device, message, raw)
  voices.put(device, message.hash, message.start, message.rate, message.channels, message.quality, raw)
end

--- Which clips a layout keeps: those still in it, and
--- old ones under a phrase that is being rendered, until it arrives.
local function retained(layout, have)
  local keep, current = {}, {}
  for _, p in ipairs(layout.phrases) do
    current[p.hash] = p
    if have[p.hash] and p.state ~= proto.state.error then keep[#keep + 1] = p.hash end
  end
  for hash, clip in pairs(have) do
    if not current[hash] and clip.start then
      for _, p in ipairs(layout.phrases) do
        local busy = p.state == proto.state.pending or p.state == proto.state.rendering
        if busy and p.start < clip.stop and p.stop > clip.start then
          keep[#keep + 1] = hash
          break
        end
      end
    end
  end
  return keep
end

engine.handlers.PhraseLayout = function(m)
  arrivals = arrivals + 1
  m.arrival = arrivals
  M.layouts[m.track] = m
  local device = vocal_device(m.track)
  local have = M.received[m.track] or {}
  local keep = retained(m, have)
  local kept = {}
  for _, hash in ipairs(keep) do
    kept[hash] = have[hash]
  end
  M.received[m.track] = kept
  if device then voices.keep(device, keep) end
  api.ui_redraw()
end

engine.handlers.PhraseAudio = function(m, frame)
  if m.purpose == 1 and M.on_audition then return M.on_audition(m, frame.raw) end
  if m.purpose ~= 0 then return end
  local device = vocal_device(m.track)
  if not device then return end
  local have = M.received[m.track] or {}
  M.received[m.track] = have
  local old = have[m.hash]
  if old and old.quality > m.quality then return end
  put(device, m, frame.raw)
  have[m.hash] = { quality = m.quality, start = m.start, stop = m.start + m.frames / m.rate }
  api.ui_redraw()
end

engine.handlers.Phonemes = function(m)
  local clip = tonumber(m.part)
  if not clip then return end
  local notes = {}
  for _, n in ipairs(m.notes) do
    notes[n.id] = n.phonemes
  end
  M.phonemes[clip] = { seq = m.seq, notes = notes }
  local waiting = resent[clip]
  if waiting and m.seq >= waiting.seq then
    -- The phrases made from these come in a layout after this.
    arrivals = arrivals + 1
    fresh_after[waiting.track] = arrivals
    resent[clip] = nil
  end
  api.ui_redraw()
end

engine.handlers.RenderedPitch = function(m)
  local clip = tonumber(m.part)
  if not clip then return end
  local entry = M.pitch[clip]
  if not entry or entry.step ~= m.step then
    entry = { step = m.step, ticks = {} }
    M.pitch[clip] = entry
  end
  for i, cents in ipairs(m.cents) do
    local tick = m.start + (i - 1) * m.step
    entry.ticks[tick] = cents >= 0 and cents or nil
  end
  api.ui_redraw()
end

--- The singer a name or part of one means: an exact id or name first.
function M.find_singer(query)
  query = tostring(query):lower()
  for _, s in ipairs(M.singers) do
    if s.id:lower() == query or s.name:lower() == query then return s end
  end
  for _, s in ipairs(M.singers) do
    if (s.name .. " " .. s.id):lower():find(query, 1, true) then return s end
  end
end

--- Give a vocal track the singer a name means, now or, before the engine
--- has listed its singers, as soon as it has.
function M.choose_singer(track_id, query)
  if #M.singers == 0 then
    M.pending_singers[track_id] = query
    if engine.state == "off" then M.sync() end
    return nil
  end
  local s = M.find_singer(query)
  if s then M.configure(track_id, { singer = s.id }) end
  return s
end
M.pending_singers = {}

engine.handlers.SingerList = function(m)
  M.singers = m
  for track, query in pairs(M.pending_singers) do
    M.pending_singers[track] = nil
    if pcall(api.track_get, track) and M.device_of(track) then
      local s = M.choose_singer(track, query)
      if not s then paw.notify("utau: no singer matches `" .. query .. "`", "warn") end
    end
  end
end
engine.handlers.RendererList = function(m) M.renderers = m end
engine.handlers.PhonemizerList = function(m) M.phonemizers = m end
engine.handlers.Progress = function(m) M.progress = m end

engine.handlers.Log = function(m)
  M.log[#M.log + 1] = m
  if #M.log > 500 then table.remove(M.log, 1) end
end

engine.handlers.Error = function(m)
  local level = m.fatal and "error" or "warn"
  if m.code ~= 8 then paw.notify("utau: " .. tostring(m.message), level) end
  -- The engine lost track of something: start over from the whole project.
  if m.code == 4 and not m.fatal then
    sent = nil
    M.schedule()
  end
end

-- Waiting ------------------------------------------------------------------------

--- Pump the engine until `fn()` is true or `seconds` pass. Returns whether
--- it became true. For scripts and offline renders; the UI pumps on a timer.
function M.wait(fn, seconds)
  local deadline = api.real_ms() + (seconds or 60) * 1000
  while true do
    if dirty then M.sync() end
    engine.pump()
    if fn() then return true end
    if engine.state == "failed" or engine.state == "missing" then return false end
    if api.real_ms() > deadline then return false end
    api.sleep(10)
  end
end

--- Whether a track has notes and the engine found nothing it can sing in
--- them: every note's phonemes are missing from the voicebank. Until the
--- phonemes are in, a layout without phrases only means it is not done.
function M.unsingable(track_key_str)
  for _, part in ipairs(sent and sent.parts or {}) do
    if part.track == track_key_str and #part.notes > 0 then
      local got = M.phonemes[part.clip]
      if not got then return false end
      for _, n in ipairs(part.notes) do
        local list = got.notes[n.id]
        if not list or #list == 0 then return false end
        for _, p in ipairs(list) do
          if p.flags % 2 == 0 then return false end
        end
      end
    end
  end
  return true
end

--- Whether a vocal track's final audio is all with its device.
function M.rendered(track_id)
  local key = tostring(track_id)
  local wanted = expected[key]
  -- Without a singer a track is silent, and that is final too; a frozen
  -- one plays its audio.
  if M.frozen(track_id) or not wanted or not M.config(track_id).singer then return true end
  local layout = M.layouts[key]
  if not layout or layout.seq < wanted then return false end
  if layout.arrival <= (fresh_after[key] or 0) then return false end
  for _, waiting in pairs(resent) do
    if waiting.track == key and api.now() - waiting.at < PHONEMIZE_GRACE then return false end
  end
  if #layout.phrases == 0 and not M.unsingable(key) then return false end
  local have = M.received[key] or {}
  for _, p in ipairs(layout.phrases) do
    if p.state ~= proto.state.error then
      if p.state ~= proto.state.final then return false end
      if not have[p.hash] or have[p.hash].quality < 1 then return false end
    end
  end
  return true
end

local function has_notes(track_id)
  for _, clip in ipairs(api.clip_list(track_id)) do
    if clip.kind == "midi" and (clip.note_count or 0) > 0 then return true end
  end
  return false
end

--- Wait until every vocal track is sung at final quality. Returns whether
--- that happened, and why not.
function M.finish(seconds)
  local tracks = {}
  for _, vocal in ipairs(M.vocal_tracks()) do
    if has_notes(vocal.track) and not M.frozen(vocal.track) then tracks[#tracks + 1] = vocal.track end
  end
  if #tracks == 0 then return true end
  M.sync()
  if engine.state == "missing" or engine.state == "failed" then return false, engine.reason end
  local done = M.wait(function()
    if not engine.connected() or engine.state ~= "ready" then return false end
    if dirty or not sent then M.sync() end
    for _, track in ipairs(tracks) do
      if not M.rendered(track) then return false end
    end
    return true
  end, seconds)
  if done then return true end
  return false, engine.reason or "timed out waiting for the engine"
end

--- The render state of a vocal track: "off", "missing", "starting",
--- "rendering", "ready" or "failed", and a count of phrases by state.
function M.status(track_id)
  if M.frozen(track_id) then return "frozen", {} end
  if engine.state ~= "ready" then return engine.state, {} end
  local counts = {}
  local layout = M.layouts[tostring(track_id)]
  for _, p in ipairs(layout and layout.phrases or {}) do
    local name = proto.state_name[p.state] or "?"
    counts[name] = (counts[name] or 0) + 1
  end
  if M.rendered(track_id) then return "ready", counts end
  return "rendering", counts
end

return M
