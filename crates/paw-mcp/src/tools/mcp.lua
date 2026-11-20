-- The kernel side of paw-mcp. The server sends this chunk with every tool
-- call (`eval`, with the tool's name, its arguments and the undo label as
-- `...`), so it needs nothing installed in the kernel and survives `:reload`.
--
-- Arguments arrive normalized by the server: positions and lengths in beats,
-- pitches as MIDI numbers, paths absolute and checked. Tracks may still be
-- named. Everything is done through `paw.api`, so every change is undoable,
-- and each tool call that writes is exactly one undo step, named `mcp: ...`:
-- a failed call is rolled back.
local api = paw.api
local T = {}

local function clean(e)
  local text = tostring(e)
  text = text:match("^(.-)\nstack traceback") or text
  text = text:gsub("^runtime error: ", ""):gsub("^%[string [^%]]*%]:%d+: ", ""):gsub("^rpc:%d+: ", "")
  return text
end

local function fail(msg) error(msg, 0) end

local function exists(get, id) return id ~= nil and (pcall(get, id)) end

-- Tracks, by id, by name, or "master" ------------------------------------------

local function track_id(ref)
  if ref == nil then fail("which track? give its id or its name") end
  if type(ref) == "number" then
    if not exists(api.track_get, ref) then fail("no track " .. ref .. " (get_project lists the tracks)") end
    return ref
  end
  local text = tostring(ref)
  if text:lower() == "master" then return 0 end
  if tonumber(text) then return track_id(tonumber(text)) end
  local wanted, partial = text:lower(), {}
  for _, id in ipairs(api.track_list()) do
    local name = api.track_get(id).name
    if name:lower() == wanted then return id end
    if name:lower():find(wanted, 1, true) then partial[#partial + 1] = { id = id, name = name } end
  end
  if #partial == 1 then return partial[1].id end
  if #partial > 1 then
    local names = {}
    for i, t in ipairs(partial) do names[i] = string.format("%q (id %d)", t.name, t.id) end
    fail("`" .. text .. "` matches several tracks: " .. table.concat(names, ", ") .. "; use an id")
  end
  fail("no track named `" .. text .. "` (get_project lists the tracks)")
end

local function need(get, id, what)
  if type(id) ~= "number" then fail(what .. " must be given by its numeric id") end
  if not exists(get, id) then fail("no " .. what .. " " .. id) end
  return id
end

-- Markers and regions, by id or by name ----------------------------------------

local function marker_view(m)
  return { id = m.id, name = m.name, beat = m.beat, length = m.length, color = m.color, region = m.length ~= nil }
end

local function markers_view()
  local out = {}
  for i, m in ipairs(paw.markers.list()) do out[i] = marker_view(m) end
  return out
end

local function marker_ref(ref, regions_only)
  if ref == nil then fail("which marker? give its id or its name") end
  local found
  if type(ref) == "number" then
    for _, m in ipairs(paw.markers.list()) do
      if m.id == ref then found = m end
    end
  else
    found = regions_only and paw.markers.region(ref) or paw.markers.find(ref)
  end
  if found and regions_only and not found.length then found = nil end
  if not found then
    fail(string.format("no %s %s (get_project lists them)", regions_only and "region" or "marker",
      type(ref) == "number" and ref or "named `" .. tostring(ref) .. "`"))
  end
  return found
end

--- The stretch a marker or region means: a region's own, or a marker up to
--- the next marker (or the end of the song).
local function marker_range(m)
  if m.length then return m.beat, m.beat + m.length end
  local after = paw.markers.next(m.beat)
  return m.beat, after and after.beat or math.max(api.project_get().length, m.beat + 1)
end

-- Device kinds -----------------------------------------------------------------

local function matches(info, words)
  local hay = (info.kind .. " " .. info.name .. " " .. (info.vendor or "") .. " " .. (info.category or "") .. " " .. info.format):lower()
  for _, word in ipairs(words) do
    if not hay:find(word, 1, true) then return false end
  end
  return true
end

local function search(query, format)
  local words = {}
  for word in tostring(query or ""):lower():gmatch("%S+") do words[#words + 1] = word end
  local out = {}
  for _, info in ipairs(api.device_types()) do
    if (not format or info.format == format) and matches(info, words) then out[#out + 1] = info end
  end
  table.sort(out, function(a, b)
    if (a.format == "builtin") ~= (b.format == "builtin") then return a.format == "builtin" end
    return a.kind < b.kind
  end)
  return out
end

local function find_kind(text)
  for _, info in ipairs(api.device_types()) do
    if info.kind == text then return info.kind end
  end
  for _, info in ipairs(api.device_types()) do
    if info.name:lower() == text:lower() then return info.kind end
  end
  local found = search(text)
  if #found == 0 then fail("no device matches `" .. text .. "`; find_devices searches what can be added") end
  return found[1].kind
end

-- Views: plain data for the server to format ----------------------------------

local function param_list(d)
  local out = {}
  for i, p in ipairs(d.param_info) do
    out[i] = {
      key = p.key, name = p.name, value = d.params[p.key], min = p.min, max = p.max,
      default = p.default, unit = p.unit, choices = p.choices,
    }
  end
  return out
end

local function device_view(id, full)
  local d = api.device_get(id)
  local v = {
    id = d.id, kind = d.kind, name = d.name, format = d.format, bypass = d.bypass, index = d.index,
    track = d.track, missing = d.missing, param_count = #d.param_info,
  }
  if full then v.params = param_list(d) end
  return v
end

--- What `filter` ({ from, to, pitches }) keeps of a clip's notes.
local function note_keeper(filter)
  if not filter then return function() return true end end
  local pitches
  if filter.pitches then
    pitches = {}
    for _, p in ipairs(filter.pitches) do pitches[p] = true end
  end
  return function(n)
    return (not pitches or pitches[n.pitch])
      and (not filter.from or n.start >= filter.from - 1e-9)
      and (not filter.to or n.start < filter.to - 1e-9)
  end
end

local function note_view(n)
  return { id = n.id, pitch = n.pitch, start = n.start, length = n.length, velocity = n.velocity, lyric = n.meta and n.meta.lyric }
end

local function clip_view(c, notes, filter)
  local v = {
    id = c.id, name = c.name, track = c.track, start = c.start, length = c.length, kind = c.kind,
    muted = c.muted, file = c.file, gain = c.gain, offset = c.offset, note_count = c.note_count,
  }
  if c.kind == "midi" then
    local list = api.clip_notes(c.id)
    for _, n in ipairs(list) do
      v.low = math.min(v.low or 127, n.pitch)
      v.high = math.max(v.high or 0, n.pitch)
    end
    if notes then
      local keep = note_keeper(filter)
      v.notes = {}
      for _, n in ipairs(list) do
        if keep(n) then v.notes[#v.notes + 1] = note_view(n) end
      end
      if filter then v.filtered = true end
    end
  end
  return v
end

local function lane_view(lane, points)
  local v = {
    id = lane.id, target = lane.target, device = lane.device, param = lane.param, enabled = lane.enabled,
    min = lane.min, max = lane.max, point_count = lane.point_count,
  }
  if points then v.points = api.lane_points(lane.id) end
  return v
end

local function db(linear)
  if not linear or linear <= 1e-6 then return -120 end
  return 20 * math.log10(linear)
end

local function track_view(id, detail)
  local t = api.track_get(id)
  local v = {
    id = id, index = t.index, name = t.name, volume = t.volume, pan = t.pan, mute = t.mute, solo = t.solo,
    armed = t.armed, master = t.master, input = t.input, monitor = t.monitor, color = t.color,
    output = t.output, sends = {}, devices = {}, clips = {}, lanes = {},
  }
  if t.output then v.output_name = api.track_get(t.output).name end
  for i, s in ipairs(t.sends or {}) do
    v.sends[i] = { target = s.target, level = s.level, name = exists(api.track_get, s.target) and api.track_get(s.target).name or "?" }
  end
  for i, d in ipairs(t.devices) do v.devices[i] = device_view(d, detail) end
  for i, c in ipairs(api.clip_list(id)) do v.clips[i] = clip_view(c, false) end
  for i, l in ipairs(api.lane_list(id)) do v.lanes[i] = lane_view(l, detail) end
  if detail then
    -- What the engine's meter holds now: the level while playing, and the
    -- last peak it kept otherwise; a render measures every track's peak.
    local left, right = api.track_meter(id)
    v.meter = { left = db(left), right = db(right) }
  end
  return v
end

-- Whether there are edits since the project was last saved or opened. The
-- kernel's `modified` only says the project has history, so remember the
-- edit count at each save (ours, and others' once this has run).
local SAVED = "paw-mcp.saved_edits"
if not rawget(_G, "__paw_mcp_hooked") then
  rawset(_G, "__paw_mcp_hooked", true)
  paw.on("project.saved", function() paw.state[SAVED] = api.project_get().edits end)
  paw.on("project.loaded", function() paw.state[SAVED] = api.project_get().edits end)
end
local function unsaved(p)
  return p.modified and paw.state[SAVED] ~= p.edits
end

local function project_key()
  local key = paw.harmony.project_key()
  return key and paw.harmony.key_name(key) or nil
end

local function project_view()
  local p, t = api.project_get(), api.transport_get()
  local v = {
    name = p.name, path = p.path, modified = unsaved(p), tempo = p.tempo, sig_num = p.sig_num,
    sig_den = p.sig_den, length = p.length, transport = t, tracks = {}, key = project_key(),
    tempo_ramp = p.tempo_ramp, tempo_changes = p.tempo_changes, sig_changes = p.sig_changes,
    markers = markers_view(),
  }
  for i, id in ipairs(api.track_list()) do v.tracks[i] = track_view(id, false) end
  v.master = track_view(0, false)
  return v
end

-- Writes -----------------------------------------------------------------------

local function set_params(id, params)
  if not params then return end
  local d = api.device_get(id)
  for key, value in pairs(params) do
    local info
    for _, p in ipairs(d.param_info) do
      if p.key == key or p.name:lower() == tostring(key):lower() then info = p end
    end
    if not info then
      local keys = {}
      for i, p in ipairs(d.param_info) do if i <= 40 then keys[i] = p.key end end
      fail(string.format("%s has no parameter `%s`; it has: %s%s", d.name, key, table.concat(keys, ", "), #d.param_info > 40 and ", ..." or ""))
    end
    if type(value) == "string" then
      local index
      for i, choice in ipairs(info.choices or {}) do
        if choice:lower() == value:lower() then index = i - 1 end
      end
      value = index or tonumber(value) or fail(string.format("`%s` is not a value of %s (%s)", value, info.key,
        #(info.choices or {}) > 0 and "one of: " .. table.concat(info.choices, ", ") or "a number"))
    end
    if type(value) ~= "number" then fail("parameter values are numbers (or a choice's name)") end
    api.device_set_param(id, info.key, value)
  end
end

local function add_device(track, spec)
  if type(spec) == "string" then spec = { kind = spec } end
  local kind = find_kind(spec.kind or fail("a device needs a `kind`"))
  local id = api.device_add(track, kind, { index = spec.index })
  set_params(id, spec.params)
  if spec.bypass ~= nil then api.device_set(id, "bypass", spec.bypass) end
  return id
end

local function add_clip(track, spec)
  local opts = { name = spec.name, start = spec.start or 0, length = spec.length, notes = spec.notes }
  if spec.file then
    opts.kind, opts.file, opts.offset, opts.gain, opts.notes = "audio", spec.file, spec.offset or 0, spec.gain or 0, nil
  end
  local id = api.clip_add(track, opts)
  if spec.muted then api.clip_set(id, "muted", true) end
  return id
end

local function set_sends(id, sends)
  local list = {}
  for i, s in ipairs(sends) do list[i] = { target = track_id(s.target), level = s.level or 0 } end
  api.track_set(id, "sends", list)
end

function T.add_track(a)
  local output = a.output ~= nil and track_id(a.output) or nil
  local id = api.track_add({ name = a.name, index = a.index, volume = a.volume, pan = a.pan, output = output, color = a.color })
  for _, d in ipairs(a.devices or {}) do add_device(id, d) end
  for _, c in ipairs(a.clips or {}) do add_clip(id, c) end
  if a.sends then set_sends(id, a.sends) end
  return { track = track_view(id, false) }
end

function T.set_track(a)
  local id = track_id(a.track)
  for _, key in ipairs({ "name", "volume", "pan", "mute", "solo", "color" }) do
    if a[key] ~= nil then api.track_set(id, key, a[key]) end
  end
  if a.output ~= nil then
    local out = a.output
    if out == false or out == "" then out = 0 end
    api.track_set(id, "output", track_id(out))
  end
  if a.sends then set_sends(id, a.sends) end
  if a.index then api.track_move(id, a.index) end
  return { track = track_view(id, false) }
end

function T.remove(a)
  local removed = {}
  for _, id in ipairs(a.automation or {}) do
    local lane = api.lane_get(need(api.lane_get, id, "automation lane"))
    api.lane_remove(id)
    removed[#removed + 1] = string.format("automation lane %d (%s%s)", id, lane.target, lane.param and " " .. lane.param or "")
  end
  for _, id in ipairs(a.clips or {}) do
    local c = api.clip_get(need(api.clip_get, id, "clip"))
    api.clip_remove(id)
    removed[#removed + 1] = string.format("clip %d %q", id, c.name)
  end
  for _, id in ipairs(a.devices or {}) do
    local d = api.device_get(need(api.device_get, id, "device"))
    api.device_remove(id)
    removed[#removed + 1] = string.format("device %d %s", id, d.name)
  end
  for _, ref in ipairs(a.tracks or {}) do
    local id = track_id(ref)
    local name = api.track_get(id).name
    api.track_remove(id)
    removed[#removed + 1] = string.format("track %d %q", id, name)
  end
  for _, ref in ipairs(a.markers or {}) do
    local m = marker_ref(ref)
    paw.markers.remove(m.id)
    removed[#removed + 1] = string.format("%s %d %q", m.length and "region" or "marker", m.id, m.name)
  end
  return { removed = removed }
end

function T.add_clip(a)
  local track = track_id(a.track)
  local id = add_clip(track, a)
  return { clip = clip_view(api.clip_get(id), #(a.notes or {}) <= 64) }
end

-- Notes ------------------------------------------------------------------------

--- What `r` ({ all, ids, pitches, from, to }) picks out of a clip's notes:
--- everything with `all`, else the notes that fit everything that is given.
local function note_picker(r)
  if not r then return function() return false end end
  if r.all then return function() return true end end
  if not (r.ids or r.pitches or r.from or r.to) then return function() return false end end
  local ids
  if r.ids then
    ids = {}
    for _, id in ipairs(r.ids) do ids[id] = true end
  end
  local keep = note_keeper(r)
  return function(n) return (not ids or ids[n.id]) and keep(n) end
end

--- Move a pitch by scale degrees in the key sounding where the note is.
local function degrees_up(c, n, spec)
  local key = spec.key and paw.harmony.parse_key(spec.key) or paw.harmony.key(c.start + n.start)
  return paw.harmony.step(key, n.pitch, spec.degrees), key
end

--- Edit a clip's notes in one go, by the notes' own ids where they are
--- named: remove, change one by one, transpose, scale or set velocities.
local function edit_notes(id, c, a)
  local list = api.clip_notes(id)
  local place = {}
  for i, n in ipairs(list) do place[n.id or -i] = i end
  local changes = {}
  for _, e in ipairs(a.edit_notes or {}) do
    local i = place[e.id]
    if not i then fail(string.format("clip %d has no note %s (get_clip lists the notes and their ids)", id, tostring(e.id))) end
    local into = changes[i] or {}
    for _, key in ipairs({ "pitch", "start", "length", "velocity" }) do
      if e[key] ~= nil then into[key] = e[key] end
    end
    changes[i] = into
  end
  local pick = note_picker(a.remove_notes)
  local velocities = a.set_velocity and note_picker({
    pitches = a.set_velocity.pitches, from = a.set_velocity.from, to = a.set_velocity.to,
    all = not (a.set_velocity.pitches or a.set_velocity.from or a.set_velocity.to),
  })
  local semitones, spec = 0, nil
  if type(a.transpose) == "number" then
    semitones = a.transpose
  elseif type(a.transpose) == "table" then
    semitones, spec = a.transpose.semitones or 0, a.transpose.degrees and a.transpose
  end
  local edit, removed, keys = { set = {}, remove = {} }, 0, {}
  for i, n in ipairs(list) do
    if pick(n) then
      edit.remove[#edit.remove + 1] = i
      removed = removed + 1
    else
      local now = { pitch = n.pitch, start = n.start, length = n.length, velocity = n.velocity }
      for key, value in pairs(changes[i] or {}) do now[key] = value end
      if spec then
        local pitch, key = degrees_up(c, n, spec)
        now.pitch = pitch
        keys[key.name or paw.harmony.key_name(key)] = true
      end
      now.pitch = now.pitch + semitones
      if now.pitch < 0 or now.pitch > 127 then
        fail("transposing takes a note outside MIDI's range (note " .. tostring(n.id) .. ")")
      end
      if a.velocity then now.velocity = math.floor(now.velocity * a.velocity + 0.5) end
      if velocities and velocities(n) then now.velocity = a.set_velocity.value end
      now.velocity = math.max(1, math.min(127, now.velocity))
      if now.pitch ~= n.pitch or now.start ~= n.start or now.length ~= n.length or now.velocity ~= n.velocity then
        edit.set[#edit.set + 1] = { index = i, pitch = now.pitch, start = now.start, length = now.length, velocity = now.velocity }
      end
    end
  end
  if #edit.set > 0 or #edit.remove > 0 then api.clip_notes_edit(id, edit) end
  local used = {}
  for name in pairs(keys) do used[#used + 1] = name end
  table.sort(used)
  return removed, #edit.set, used
end

function T.edit_clip(a)
  local id = need(api.clip_get, a.clip, "clip")
  local c = api.clip_get(id)
  for _, key in ipairs({ "name", "start", "length", "muted", "gain", "offset" }) do
    if a[key] ~= nil then api.clip_set(id, key, a[key]) end
  end
  if a.track ~= nil then api.clip_set(id, "track", track_id(a.track)) end
  local touches_notes = a.remove_notes or a.edit_notes or a.transpose or a.notes or a.add_notes or a.velocity or a.set_velocity
  if touches_notes and c.kind ~= "midi" then fail("clip " .. id .. " is an audio clip; only MIDI clips have notes") end
  local removed, changed, keys = 0, 0, {}
  if a.remove_notes or a.edit_notes or a.transpose or a.velocity or a.set_velocity then
    removed, changed, keys = edit_notes(id, api.clip_get(id), a)
  end
  if a.notes then api.clip_set_notes(id, a.notes) end
  if a.add_notes then api.clip_add_notes(id, a.add_notes) end
  local v = clip_view(api.clip_get(id), true)
  if #v.notes > 64 then v.notes = nil end
  v.removed_notes, v.changed_notes, v.keys_used = removed, changed, keys
  return { clip = v }
end

local function copy_of(clip, opts)
  local copy = paw.clip(clip.id):duplicate(opts)
  return copy.id
end

function T.duplicate_clip(a)
  local id = need(api.clip_get, a.clip, "clip")
  local c = api.clip_get(id)
  local track = a.track ~= nil and track_id(a.track) or c.track
  local at = a.at or c.start + c.length
  local made = {}
  for i = 1, a.times or 1 do
    made[i] = copy_of(c, { start = at + (i - 1) * (a.gap and c.length + a.gap or c.length), track = track })
  end
  local clips = {}
  for i, copy in ipairs(made) do clips[i] = clip_view(api.clip_get(copy), false) end
  return { clips = clips }
end

function T.repeat_bars(a)
  local from, to = a.from, a.to
  if not (to > from) then fail("`to` must be after `from`") end
  local length = to - from
  local tracks
  if a.tracks then
    tracks = {}
    for _, ref in ipairs(a.tracks) do tracks[track_id(ref)] = true end
  end
  local source, skipped = {}, {}
  for _, id in ipairs(api.track_list()) do
    if not tracks or tracks[id] then
      for _, c in ipairs(api.clip_list(id)) do
        if c.start + 1e-9 >= from and c.start + c.length <= to + 1e-9 then
          source[#source + 1] = c
        elseif c.start < to and c.start + c.length > from then
          skipped[#skipped + 1] = c.id
        end
      end
    end
  end
  if #source == 0 then fail("no clip lies wholly between those beats") end
  local at = a.at or to
  local made = {}
  for n = 1, a.times or 1 do
    for _, c in ipairs(source) do
      made[#made + 1] = copy_of(c, { start = c.start + at - from + (n - 1) * length })
    end
  end
  local clips = {}
  for i, id in ipairs(made) do clips[i] = clip_view(api.clip_get(id), false) end
  return { clips = clips, source = #source, skipped = skipped }
end

function T.add_device(a)
  local id = add_device(track_id(a.track), a)
  return { device = device_view(id, true) }
end

function T.set_device(a)
  local id = need(api.device_get, a.device, "device")
  set_params(id, a.params)
  if a.bypass ~= nil then api.device_set(id, "bypass", a.bypass) end
  if a.track ~= nil or a.index ~= nil then
    local d = api.device_get(id)
    local track = a.track ~= nil and track_id(a.track) or d.track
    api.device_move(id, track, a.index or #api.track_get(track).devices + (track == d.track and 0 or 1))
  end
  local v = device_view(id, true)
  if a.params and #v.params > 24 then
    -- Only what was asked about, for a plugin with hundreds of parameters.
    local wanted, keep = {}, {}
    for key in pairs(a.params) do wanted[tostring(key):lower()] = true end
    for _, p in ipairs(v.params) do
      if wanted[p.key:lower()] or wanted[p.name:lower()] then keep[#keep + 1] = p end
    end
    v.params, v.only_changed = keep, true
  end
  return { device = v }
end

function T.automate(a)
  local track, target, device = a.track, a.target or "volume", a.device
  if device then
    local d = api.device_get(need(api.device_get, device, "device"))
    track = track ~= nil and track_id(track) or d.track
    target = "param"
    if not a.param then fail("automating a device needs `param`, the parameter's key or name") end
  else
    track = track_id(track)
    if target ~= "volume" and target ~= "pan" then fail("target is `volume` or `pan`; for a device parameter give `device` and `param`") end
  end
  local lane
  for _, l in ipairs(api.lane_list(track)) do
    if l.target == target and (target ~= "param" or (l.device == device and (l.param == a.param))) then lane = l end
  end
  if not lane and target == "param" then
    -- The parameter may have been named by its display name.
    for _, p in ipairs(api.device_get(device).param_info) do
      if p.name:lower() == a.param:lower() then
        for _, l in ipairs(api.lane_list(track)) do
          if l.target == "param" and l.device == device and l.param == p.key then lane = l end
        end
      end
    end
  end
  if a.remove then
    if not lane then fail("there is no such automation lane to remove") end
    api.lane_remove(lane.id)
    return { removed = { "automation lane " .. lane.id } }
  end
  local created = false
  if not lane then
    local id = api.lane_add(track, { target = target, device = device, param = a.param, points = {} })
    lane, created = api.lane_get(id), true
  end
  if a.clear then api.lane_set_points(lane.id, {}) end
  if a.points then
    if a.mode == "add" then
      for _, p in ipairs(a.points) do api.lane_add_point(lane.id, p[1], p[2]) end
    else
      api.lane_set_points(lane.id, a.points)
    end
  end
  if a.enabled ~= nil then api.lane_set(lane.id, "enabled", a.enabled) end
  local v = lane_view(api.lane_get(lane.id), true)
  v.created, v.track = created, track
  v.track_name = api.track_get(track).name
  if target == "param" then v.device_name = api.device_get(device).name end
  return { lane = v }
end

function T.set_project(a)
  if a.tempo then api.project_set("tempo", a.tempo) end
  if a.sig_num then api.project_set("sig_num", a.sig_num) end
  if a.sig_den then api.project_set("sig_den", a.sig_den) end
  if a.name then api.project_set("name", a.name) end
  if a.key ~= nil then
    -- An empty text takes the key away: the harmony reading is used again.
    paw.harmony.set_key(a.key ~= "" and a.key or nil)
  end
  if a.tempo_changes or a.signature_changes then
    local map = api.tempo_points()
    local tempos, sigs = { map.tempos[1] }, { map.signatures[1] }
    for i, c in ipairs(a.tempo_changes or {}) do tempos[i + 1] = c end
    for i, c in ipairs(a.signature_changes or {}) do sigs[i + 1] = c end
    if not a.tempo_changes then tempos = map.tempos end
    if not a.signature_changes then sigs = map.signatures end
    api.tempo_set_points(tempos, sigs)
  end
  return { project = project_view() }
end

function T.marker(a)
  local action = a.action
  if action == "add" then
    if a.at == nil then fail("add needs `at`, where the marker goes") end
    local m = paw.markers.add(a.at, a.name, { length = a.length, color = a.color })
    return { marker = marker_view(m), markers = markers_view() }
  elseif action == "list" then
    return { markers = markers_view() }
  end
  local m = marker_ref(a.marker)
  if action == "remove" then
    paw.markers.remove(m.id)
    return { removed = { string.format("%s %d %q", m.length and "region" or "marker", m.id, m.name) }, markers = markers_view() }
  elseif action == "rename" then
    if not a.name then fail("rename needs the new `name`") end
    paw.markers.set(m.id, { name = a.name })
  elseif action == "move" then
    if a.at == nil and a.length == nil then fail("move needs `at` (and `length` to resize a region)") end
    paw.markers.set(m.id, { beat = a.at, length = a.length })
  end
  return { marker = marker_view(marker_ref(m.id)), markers = markers_view() }
end

-- Not undoable: the transport is not part of the project's history.
function T.transport(a)
  for _, key in ipairs({ "loop_start", "loop_end", "metronome" }) do
    if a[key] ~= nil then api.transport_set(key, a[key]) end
  end
  if a.loop_marker ~= nil then
    local from, to = marker_range(marker_ref(a.loop_marker))
    api.transport_set("loop_start", from)
    api.transport_set("loop_end", to)
    api.transport_set("loop_enabled", true)
  end
  if a.loop ~= nil then api.transport_set("loop_enabled", a.loop) end
  if a.action == "stop" or a.action == "pause" then api.transport_stop() end
  if a.position then api.transport_seek(a.position) end
  if a.action == "play" then api.transport_play() end
  return { transport = api.transport_get() }
end

-- History ----------------------------------------------------------------------

local function history()
  local tree = api.undo_tree()
  local by_id = {}
  for _, s in ipairs(tree.states) do by_id[s.id] = s end
  return tree, by_id
end

local function step_label(state)
  return state and state.label and state.label ~= "" and state.label or "an edit made outside this server"
end

function T.undo(a)
  local tree, by_id = history()
  if a.list then
    local out, state = {}, by_id[tree.current]
    while state and #out < (a.limit or 20) do
      -- The first state is the project as it was opened, with nothing to undo.
      if state.parent then
        out[#out + 1] = { id = state.id, label = step_label(state), time = state.time, current = state.id == tree.current }
      end
      state = state.parent and by_id[state.parent] or nil
    end
    local redo, next_state = {}, by_id[tree.current] and by_id[by_id[tree.current].redo or -1]
    while next_state and #redo < (a.limit or 20) do
      redo[#redo + 1] = { id = next_state.id, label = step_label(next_state), time = next_state.time }
      next_state = by_id[next_state.redo or -1]
    end
    return { history = out, redoable = redo }
  end
  local names, fn = {}, a.redo and api.redo or api.undo
  for _ = 1, a.steps or 1 do
    local from = by_id[api.undo_current()]
    if not fn() then break end
    names[#names + 1] = step_label(a.redo and by_id[api.undo_current()] or from)
  end
  paw.flush()
  return { done = #names, steps = names }
end

function T.file(a)
  local p = api.project_get()
  if a.action == "save" then
    local path = api.project_save(a.path)
    paw.state[SAVED] = api.project_get().edits
    return { saved = path, project = { name = p.name, tempo = p.tempo } }
  end
  if unsaved(p) and not a.discard then
    fail("the project has unsaved changes, which " .. a.action .. " would lose for good (it also clears undo): save first, or pass discard=true")
  end
  if a.action == "load" then api.project_load(a.path) else api.project_new() end
  paw.state[SAVED] = api.project_get().edits
  paw.flush()
  return { project = project_view() }
end

local LOUDNESS = { "integrated", "short_term_max", "momentary_max", "lra", "true_peak", "sample_peak", "clipped_samples" }

--- LUFS and peaks of a rendered file, as the kernel measures them.
local function loudness_of(path)
  local ok, m = pcall(api.measure, { file = path })
  if not ok then return nil end
  local out = {}
  for _, key in ipairs(LOUDNESS) do out[key] = m[key] end
  return out
end

function T.render(a)
  local p = api.project_get()
  local opts = {
    start = a.start, ["end"] = a["end"], tail = a.tail, bits = a.bits, sample_rate = a.sample_rate,
    loudness = a.loudness, normalize = a.normalize, quality = a.quality, dither = a.dither,
  }
  if a.region then
    local from, to = marker_range(marker_ref(a.region, true))
    opts.start, opts["end"] = from, to
  end
  local ids
  if a.tracks then
    ids = {}
    for i, ref in ipairs(a.tracks) do ids[i] = track_id(ref) end
  end
  local start, finish = opts.start or 0, opts["end"] or p.length
  if a.stems then
    opts.tracks = ids
    local files = require("paw.render").stems(a.path, paw.util.merge(opts, { format = a.format }))
    return { render = { stems = files, start = start, ["end"] = finish, tempo = p.tempo, sig_num = p.sig_num, sig_den = p.sig_den } }
  end
  opts.tracks = ids
  local info = paw.render(a.path, opts)
  info.start, info["end"] = start, finish
  info.tempo, info.sig_num, info.sig_den = p.tempo, p.sig_num, p.sig_den
  info.project_length = p.length
  return { render = info, loudness = loudness_of(info.path or a.path) }
end

function T.analyze(a)
  return { loudness = loudness_of(a.path) }
end

-- Reads ------------------------------------------------------------------------

function T.project() return { project = project_view() } end

function T.track(a) return { track = track_view(track_id(a.track), true) } end

function T.clip(a)
  local v = clip_view(api.clip_get(need(api.clip_get, a.clip, "clip")), true, a.filter)
  v.track_name = api.track_get(v.track).name
  return { clip = v }
end

function T.device(a)
  local v = device_view(need(api.device_get, a.device, "device"), true)
  if a.filter then
    local keep, words = {}, a.filter:lower()
    for _, p in ipairs(v.params) do
      if p.key:lower():find(words, 1, true) or p.name:lower():find(words, 1, true) then keep[#keep + 1] = p end
    end
    v.params, v.filtered = keep, true
  end
  v.track_name = api.track_get(v.track).name
  return { device = v }
end

function T.find_devices(a)
  local found = search(a.query, a.format)
  local out, limit = {}, a.limit or 25
  for i = 1, math.min(limit, #found) do
    local info = found[i]
    out[i] = { kind = info.kind, name = info.name, format = info.format, vendor = info.vendor, category = info.category, params = #info.params }
    if a.params then out[i].param_info = info.params end
  end
  return { total = #found, devices = out, all = #api.device_types() }
end

function T.status(a)
  local p, e = api.project_get(), api.engine_get()
  local out = { transport = api.transport_get(), engine = e, project = {
    name = p.name, path = p.path, modified = unsaved(p), tempo = p.tempo, sig_num = p.sig_num, sig_den = p.sig_den, length = p.length,
  }, messages = {} }
  local msgs = paw.ui.messages
  for i = math.max(1, #msgs - (a.messages or 10) + 1), #msgs do
    out.messages[#out.messages + 1] = { text = msgs[i].text, level = msgs[i].level }
  end
  return out
end

-- Finding and diagnosing -------------------------------------------------------

function T.find(a)
  local ok, nodes = pcall(paw.query, a.query)
  if not ok then fail("the query `" .. a.query .. "` does not parse: " .. clean(nodes) .. " (see the `query` help page)") end
  local out, limit = {}, a.limit or 50
  for i = 1, math.min(limit, #nodes) do
    local n = nodes[i]
    local d = n.data or {}
    out[i] = {
      kind = n.kind, id = n.id or d.id, clip = n.clip, text = paw.query.describe(n),
      track = n.kind == "clip" and d.track or (n.track and (type(n.track) == "table" and n.track.id or n.track)) or nil,
      beat = n.kind == "note" and d.start or d.start or d.beat,
    }
  end
  return { total = #nodes, found = out }
end

local function instrument_kinds()
  local out = {}
  for _, info in ipairs(api.device_types()) do
    local category = (info.category or ""):lower()
    -- A plugin that does not say what it is may well be an instrument.
    out[info.kind] = category:find("instrument", 1, true) ~= nil or category:find("synth", 1, true) ~= nil
      or (info.format ~= "builtin" and category == "")
  end
  return out
end

function T.diagnose(a)
  local findings, counts = {}, { error = 0, warning = 0, info = 0 }
  local function add(severity, rule, message, where)
    counts[severity] = counts[severity] + 1
    local f = { severity = severity, rule = rule, message = message }
    for k, v in pairs(where or {}) do f[k] = v end
    findings[#findings + 1] = f
  end
  local ids = api.track_list()
  if a.track ~= nil then ids = { track_id(a.track) } end
  local length = api.project_get().length
  local instruments = instrument_kinds()
  local fed = {}
  for _, id in ipairs(api.track_list()) do
    local t = api.track_get(id)
    if t.output and t.output ~= 0 then fed[t.output] = true end
    for _, s in ipairs(t.sends or {}) do fed[s.target] = true end
  end
  local soloed
  for _, id in ipairs(api.track_list()) do
    if api.track_get(id).solo then soloed = true end
  end
  if soloed then add("info", "solo", "some track is soloed: every other track is silent until it is not") end
  local function check_track(id)
    local t = api.track_get(id)
    local where = { track = id }
    local clips = api.clip_list(id)
    local label = string.format("track %q [id %d]", t.name, id)
    if #clips == 0 and #t.devices == 0 and not fed[id] then
      add("warning", "empty_track", label .. " is empty: no clips and no devices", where)
    elseif #clips == 0 and #t.devices > 0 and not fed[id] then
      local instrument
      for _, d in ipairs(t.devices) do
        if instruments[api.device_get(d).kind] then instrument = true end
      end
      if instrument then add("info", "no_clips", label .. " has an instrument but no clips", where) end
    end
    local sounding, has_instrument, bypassed = 0, false, false
    for _, c in ipairs(clips) do
      if c.kind == "midi" and not c.muted then
        if c.note_count == 0 then
          add("info", "empty_clip", string.format("clip %d %q on %s has no notes", c.id, c.name, label), { track = id, clip = c.id })
        else
          sounding = sounding + c.note_count
          local beyond = 0
          for _, n in ipairs(api.clip_notes(c.id)) do
            if n.start >= c.length - 1e-9 then beyond = beyond + 1 end
          end
          if beyond > 0 then
            add("warning", "notes_beyond_clip", string.format("clip %d %q has %d note%s starting after its end, which never sound", c.id, c.name, beyond, beyond == 1 and "" or "s"), { track = id, clip = c.id })
          end
        end
      end
    end
    for _, d in ipairs(t.devices) do
      local dev = api.device_get(d)
      if dev.missing then
        add("error", "missing_device", string.format("device %d %s on %s is not loaded (plugin not found)", d, dev.name, label), { track = id, device = d })
      end
      if instruments[dev.kind] then
        if dev.bypass then bypassed = true else has_instrument = true end
      end
    end
    if sounding > 0 and not has_instrument and id ~= 0 then
      add("error", "silent_midi_track", label .. " has MIDI notes but "
        .. (bypassed and "its instrument is bypassed" or "no instrument device") .. ": it makes no sound (add_device `synth` or `drums`)", where)
    end
    if id == 0 and #clips > 0 then
      add("warning", "clip_on_master", "the master track holds clips, which nothing plays", where)
    end
    local out = t.output
    if out and out ~= 0 and exists(api.track_get, out) and api.track_get(out).mute then
      add("warning", "muted_destination", label .. " plays into the muted track " .. string.format("%q", api.track_get(out).name), where)
    end
    for _, s in ipairs(t.sends or {}) do
      if not exists(api.track_get, s.target) then
        add("error", "orphan_send", label .. " has a send to a track that no longer exists (id " .. s.target .. ")", where)
      elseif api.track_get(s.target).mute then
        add("warning", "muted_destination", label .. " sends to the muted track " .. string.format("%q", api.track_get(s.target).name), where)
      end
    end
    for _, l in ipairs(api.lane_list(id)) do
      local outside = 0
      for _, p in ipairs(api.lane_points(l.id)) do
        if p[2] < l.min - 1e-9 or p[2] > l.max + 1e-9 then outside = outside + 1 end
      end
      if outside > 0 then
        add("warning", "automation_out_of_range", string.format("automation lane %d on %s has %d point%s outside its range %g to %g", l.id, label, outside, outside == 1 and "" or "s", l.min, l.max), { track = id })
      end
    end
  end
  for _, id in ipairs(ids) do check_track(id) end
  if a.track == nil then check_track(0) end

  local summary
  if a.measure then
    if length <= 0 then
      add("warning", "no_music", "the project has no clips, so there is nothing to measure")
    else
      local range = { start = 0, ["end"] = length }
      paw.emit("render.before", { path = nil, opts = range, measure = true })
      paw.flush()
      local m = api.measure({ start = 0, ["end"] = length, tail = 1 })
      summary = { integrated = m.integrated, true_peak = m.true_peak, sample_peak = m.sample_peak, clipped_samples = m.clipped_samples, lra = m.lra }
      if not m.sound_start then
        add("error", "silent_mix", "the mix is silent: nothing rises above -60 dBFS")
      end
      if (m.over_samples or 0) > 0 or (m.clipped_samples or 0) > 0 then
        add("error", "clipping", string.format("the mix clips: %d sample%s at or over full scale (sample peak %.1f dBFS)", m.clipped_samples, m.clipped_samples == 1 and "" or "s", m.sample_peak))
      elseif m.true_peak and m.true_peak > -1 then
        add("warning", "true_peak", string.format("the true peak is %.1f dBTP, over the -1 dBTP streaming services ask for", m.true_peak))
      end
      for _, tp in ipairs(m.tracks or {}) do
        if tp.over_at and exists(api.track_get, tp.id) then
          add("warning", "track_clipping", string.format("track %q goes over full scale at %.1f s", api.track_get(tp.id).name, tp.over_at), { track = tp.id })
        end
      end
    end
  end

  -- What language servers and lints in paw have said about the project.
  local published = {}
  local ok, list = pcall(paw.diagnostic.get)
  if ok then
    for i, d in ipairs(list) do
      if i > 50 then break end
      local sev = ({ "error", "warning", "info", "info" })[d.severity] or "info"
      published[#published + 1] = { severity = sev, source = d.source, message = tostring(d.message), where = paw.diagnostic.where(d) }
    end
  end
  return { findings = findings, counts = counts, measure = summary, published = published }
end

-- Escape hatches ---------------------------------------------------------------

function T.command(a)
  local result = paw.commands.exec(a.line)
  return { result = result ~= nil and paw.inspect(result) or nil }
end

function T.keys(a)
  paw.keymap.feed(a.keys)
  local km = paw.keymap
  return { mode = km.mode, pending = km.pending(), focused = paw.ui.focused }
end

function T.lua(a)
  local chunk = loadstring("return " .. a.code, "=lua") or assert(loadstring(a.code, "=lua"))
  local results = { chunk() }
  local shown = {}
  for i = 1, table.maxn(results) do shown[i] = paw.inspect(results[i]) end
  return { result = table.concat(shown, "\n") }
end

-- Resources: the manual's pages ------------------------------------------------

function T.help_pages()
  local out = {}
  for _, s in ipairs(paw.help.sources()) do
    if s.path then out[#out + 1] = { name = s.name, aliases = s.aliases, group = s.group, ext = s.ext } end
  end
  return { pages = out }
end

function T.help_page(a)
  for _, s in ipairs(paw.help.sources()) do
    if s.path and s.name == a.name then
      local f, err = io.open(s.path, "rb")
      if not f then fail("reading " .. s.path .. ": " .. tostring(err)) end
      local text = f:read("*a")
      f:close()
      return { text = text }
    end
  end
  fail("no help page `" .. tostring(a.name) .. "`")
end

-- Batches ----------------------------------------------------------------------

--- Steps in one undo step: any that fails undoes them all.
function T.batch(a)
  local results = {}
  for i, op in ipairs(a.ops) do
    local ok, res = pcall(T[op.tool], op.args)
    if not ok then fail(string.format("step %d (%s): %s", i, op.tool, clean(res))) end
    results[i] = res
  end
  return { results = results }
end

-- Entry ------------------------------------------------------------------------

local writes = {
  add_track = true, set_track = true, remove = true, add_clip = true, edit_clip = true, add_device = true,
  set_device = true, automate = true, set_project = true, marker = true, duplicate_clip = true,
  repeat_bars = true, batch = true, command = true, keys = true, lua = true,
}
local rollback = { command = false, keys = false, lua = false }

local name, args, label = ...
local fn = T[name] or fail("no tool `" .. tostring(name) .. "` in the kernel side")
args = args or {}

local messages = paw.ui.messages
local last = messages[#messages]
local function new_messages()
  local out = {}
  for i = #messages, math.max(1, #messages - 20), -1 do
    if messages[i] == last then break end
    table.insert(out, 1, { text = messages[i].text, level = messages[i].level })
  end
  return out
end

local result
if writes[name] then
  api.undo_checkpoint()
  api.undo_label(label or ("mcp: " .. name))
  local before = api.project_get().edits
  local ok, res = xpcall(fn, function(e) return e end, args)
  if not ok then
    local undone = false
    if rollback[name] ~= false and api.project_get().edits ~= before then
      api.undo()
      undone = true
    end
    paw.flush()
    fail(clean(res) .. (undone and " (nothing was changed: the call was rolled back)" or ""))
  end
  paw.flush()
  api.undo_checkpoint()
  result = res
  result.edited = api.project_get().edits ~= before
else
  local ok, res = xpcall(fn, function(e) return e end, args)
  if not ok then fail(clean(res)) end
  paw.flush()
  result = res
end
result.messages = new_messages()
return result
