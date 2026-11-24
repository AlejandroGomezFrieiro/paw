-- The clip launcher: every part has slots, a column of clips kept off the
-- timeline, and a row of slots across the parts is a scene. Launching a
-- slot cues its clip on its part at the next boundary of its quantize (a
-- bar by default), to the frame (`paw.api.cue`); while a part plays a
-- slot, or has been stopped, its clips on the timeline are silent until it
-- goes back to the timeline. Stopping the song sends every part back. A
-- render plays the timeline: `capture` writes a performance into it.
--
-- The clips are the core's clips off the timeline (`paw.api.clip_add(part,
-- { cue = true })`), saved with the project and undone like any edit. What
-- is the launcher's own is kept in `meta.launcher`: on each clip its `row`
-- (from 0), `quantize`, `mode` and `legato`; on the project the `quantize`
-- of launches and the names of the `scenes`. Without the extension the
-- project opens and plays its timeline, and keeps all of it.
--
-- Rows count from 0 here and in `paw.api`, from 1 in commands and on screen.
local api = paw.api
local M = {
  -- The slot the session view's cursor is on, as a row from 0; the part
  -- is the cursor's.
  row = 0,
  quantizes = { "off", "1/16", "1/8", "1/4", "beat", "bar", "2bars", "4bars" },
  modes = { "trigger", "gate", "toggle" },
  -- A performance is being written into the timeline.
  capturing = false,
}

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

M.contains = contains

-- The model ------------------------------------------------------------------------

--- The launcher's part of a clip's meta, or nil for a clip that is not in a slot.
local function slot_meta(clip)
  local m = type(clip.meta) == "table" and clip.meta.launcher
  return type(m) == "table" and type(m.row) == "number" and m or nil
end

--- A clip view as the launcher shows it: `slot` (its row), `mode`,
--- `quantize` (nil for the project's) and `legato`.
local function as_slot(clip, m)
  clip.slot, clip.mode, clip.quantize, clip.legato = m.row, m.mode or "trigger", m.quantize, m.legato == true
  return clip
end

--- The clips in a part's slots, by row: `{ [row] = clip view }`.
function M.slots(part)
  local out = {}
  for _, clip in ipairs(api.cue_list(part)) do
    local m = slot_meta(clip)
    if m and not out[m.row] then out[m.row] = as_slot(clip, m) end
  end
  return out
end

--- The clip in a slot, or nil.
function M.clip(part, row) return M.slots(part)[row] end

--- A clip's view as a slot's, by its id, or nil if it is in no slot.
function M.slot_of(id)
  local ok, clip = pcall(api.clip_get, id)
  local m = ok and clip.cue and slot_meta(clip)
  return m and as_slot(clip, m) or nil
end

--- Change the launcher's part of a clip's meta: `fields` are set, a false
--- one is taken away. One edit.
local function set_meta(id, fields)
  local meta = api.clip_get(id).meta
  meta = type(meta) == "table" and meta or {}
  local m = type(meta.launcher) == "table" and meta.launcher or {}
  for k, v in pairs(fields) do
    if v == false then
      m[k] = nil
    else
      m[k] = v
    end
  end
  meta.launcher = m
  api.clip_set(id, "meta", meta)
end

--- The project's part: `{ quantize, scenes }`.
local function project_meta()
  local m = api.project_get().meta.launcher
  return type(m) == "table" and m or {}
end

local function set_project_meta(key, value)
  local meta = api.project_get().meta
  local m = type(meta.launcher) == "table" and meta.launcher or {}
  m[key] = value
  meta.launcher = next(m) and m or nil
  api.project_set("meta", meta)
end

--- Where launches land unless a slot says otherwise: "bar" by default.
function M.quantize()
  local q = project_meta().quantize
  return contains(M.quantizes, q) and q or "bar"
end

--- Set where launches land.
function M.set_quantize(q)
  if not contains(M.quantizes, q) then error("a quantize is one of " .. table.concat(M.quantizes, ", "), 2) end
  set_project_meta("quantize", q ~= "bar" and q or nil)
end

--- Change how a slot's clip launches: `mode` (trigger, gate, toggle),
--- `quantize` (one of `M.quantizes`, or "project" for the project's) or
--- `legato` (true or false).
function M.set(id, key, value)
  if not M.slot_of(id) then error("clip " .. tostring(id) .. " is in no slot", 2) end
  if key == "mode" then
    if not contains(M.modes, value) then error("a mode is trigger, gate or toggle", 2) end
    set_meta(id, { mode = value ~= "trigger" and value or false })
  elseif key == "quantize" then
    if value ~= nil and value ~= "project" and not contains(M.quantizes, value) then
      error("a quantize is project or one of " .. table.concat(M.quantizes, ", "), 2)
    end
    set_meta(id, { quantize = (value and value ~= "project") and value or false })
  elseif key == "legato" then
    set_meta(id, { legato = value and true or false })
  else
    error("a slot has no setting `" .. tostring(key) .. "`: mode, quantize or legato", 2)
  end
end

--- Put a slot's clip in another slot: `row` on `part` (its own when nil),
--- in place of what was there.
function M.move(id, part, row)
  local c = M.slot_of(id)
  if not c then error("clip " .. tostring(id) .. " is in no slot", 2) end
  part = part or c.part
  local there = M.clip(part, row)
  if there and there.id ~= id then api.clip_remove(there.id) end
  if c.part ~= part then api.clip_set(id, "part", part) end
  set_meta(id, { row = row })
end

--- The names of the scenes, by row from 1. Rows without a name are "" or nil.
function M.scenes()
  local scenes = project_meta().scenes
  return type(scenes) == "table" and scenes or {}
end

--- A scene's name (rows from 0): its own, or "Scene N".
function M.scene_name(row)
  local name = M.scenes()[row + 1]
  return (type(name) == "string" and name ~= "") and name or ("Scene " .. (row + 1))
end

--- Name a scene (rows from 0), kept with the project.
function M.set_scene_name(row, name)
  local scenes = M.scenes()
  for i = 1, row do
    scenes[i] = scenes[i] or ""
  end
  scenes[row + 1] = name
  while #scenes > 0 and scenes[#scenes] == "" do
    scenes[#scenes] = nil
  end
  set_project_meta("scenes", #scenes > 0 and scenes or nil)
end

--- How many rows there are: those with clips or names, one empty row more,
--- and at least `paw.opt.launch_rows`.
function M.rows()
  local last = #M.scenes()
  for _, id in ipairs(api.part_list()) do
    for row in pairs(M.slots(id)) do
      last = math.max(last, row + 1)
    end
  end
  return math.max(paw.opt.launch_rows, last + 1)
end

-- What plays --------------------------------------------------------------------------

--- What each part plays and has in its queue, by part id, from
--- `paw.api.cue_state`: `slot` (a row) or `stopped`, `phase`, `length`,
--- `since`, and `queued` (a row, "stop" or "arrangement") with `at`. A
--- part that plays its timeline with nothing queued is not in the table.
function M.state()
  local out = {}
  for _, s in ipairs(api.cue_state()) do
    if s.clip or s.stopped or s.queued then
      local function row_of(id)
        local c = M.slot_of(id)
        return c and c.slot
      end
      local q = s.queued
      out[s.part] = {
        part = s.part,
        since = s.since,
        phase = s.phase,
        length = s.length,
        at = s.at,
        stopped = s.stopped or (s.clip and not row_of(s.clip)) or nil,
        slot = s.clip and row_of(s.clip) or nil,
        clip = s.clip,
        queued = q == "timeline" and "arrangement" or q == "stop" and "stop" or (q and (row_of(q) or "stop")) or nil,
      }
    end
  end
  return out
end

--- What one part plays: "arrangement", "stopped" or a row. The second
--- value is what it has in its queue, if anything.
function M.playing(part)
  local s = M.state()[part]
  if not s then return "arrangement" end
  return s.slot or (s.stopped and "stopped" or "arrangement"), s.queued
end

-- Launching ------------------------------------------------------------------

--- Send cues, and start the song if it is stopped: cued while stopped,
--- clips start at once.
local function send(list, start)
  if #list == 0 then return end
  api.cue(list)
  if start and not paw.transport.playing then paw.transport.play() end
  api.ui_redraw()
end

--- The cue of a part's slot: its clip, or a stop for an empty slot.
local function cue_of(part, row, opts)
  opts = opts or {}
  local clip = M.clip(part, row)
  if not clip then return { part = part, stop = true, quantize = opts.quantize or M.quantize() } end
  local legato = opts.legato
  if legato == nil then legato = clip.legato end
  return { part = part, clip = clip.id, quantize = opts.quantize or clip.quantize or M.quantize(), legato = legato }
end

--- Launch the clip in a slot on its next boundary. An empty slot stops the
--- part. `opts.quantize` and `opts.legato` replace the values of the slot.
function M.launch(part, row, opts) send({ cue_of(part, row, opts) }, true) end

--- A slot's button pressed, from a key, the mouse or a controller: what that
--- does is the clip's mode. A toggle stops a clip that plays or is queued.
function M.press(part, row)
  local clip = M.clip(part, row)
  local now, queued = M.playing(part)
  if clip and clip.mode == "toggle" and (now == row or queued == row) then return M.stop(part) end
  M.launch(part, row)
end

--- A slot's button let go: a gate clip stops.
function M.release(part, row)
  local clip = M.clip(part, row)
  local now, queued = M.playing(part)
  if clip and clip.mode == "gate" and (now == row or queued == row) then M.stop(part) end
end

--- Stop the clip of a part on the next boundary. With no part, stop the
--- clips of all parts. A stopped part makes no sound until you launch it
--- again or send it back to its timeline.
function M.stop(part)
  local list, q = {}, M.quantize()
  if part then
    list[1] = { part = part, stop = true, quantize = q }
  else
    for id, s in pairs(M.state()) do
      if s.slot or (s.queued and s.queued ~= "stop") then list[#list + 1] = { part = id, stop = true, quantize = q } end
    end
  end
  send(list)
end

--- Send a part back to its timeline. With no part, send back each part
--- that left its timeline.
function M.back(part)
  local list, q = {}, M.quantize()
  if part then
    list[1] = { part = part, timeline = true, quantize = q }
  else
    for id in pairs(M.state()) do
      list[#list + 1] = { part = id, timeline = true, quantize = q }
    end
  end
  send(list)
end

--- Launch a scene: the clip in that row on every part that has one, all
--- on the same boundary. Parts without one stop what they play from a slot.
function M.scene(row)
  local list, state = {}, M.state()
  for _, id in ipairs(api.part_list()) do
    if M.clip(id, row) then
      list[#list + 1] = cue_of(id, row)
    elseif state[id] and state[id].slot then
      list[#list + 1] = { part = id, stop = true, quantize = M.quantize() }
    end
  end
  send(list, true)
end

-- Making clips in slots --------------------------------------------------------

--- Add a clip off the timeline in a slot, from `opts` as `paw.api.clip_add`
--- takes them, in place of what was there. Returns its id.
function M.add(part, row, opts)
  local there = M.clip(part, row)
  if there then api.clip_remove(there.id) end
  opts = paw.util.merge(opts, { cue = true })
  local meta = type(opts.meta) == "table" and paw.util.merge(opts.meta, {}) or {}
  local m = type(meta.launcher) == "table" and paw.util.merge(meta.launcher, {}) or {}
  m.row = row
  meta.launcher = m
  opts.meta = meta
  return api.clip_add(part, opts)
end

--- An empty MIDI clip of `bars` bars (1) in a slot. Returns its id.
function M.new_clip(part, row, bars)
  local length = paw.time.bar(0) * (bars or 1)
  return M.add(part, row, { length = length, name = "clip " .. (row + 1) })
end

--- Copy a clip from the timeline (or another slot) into a slot. Returns the copy's id.
function M.copy(clip, part, row)
  local there = M.clip(part, row)
  if there and there.id ~= clip then api.clip_remove(there.id) end
  local id = api.clip_to_cues(clip, part)
  set_meta(id, { row = row })
  return id
end

--- Put a clip from a snapshot (`paw.restore_clip`) in a slot.
function M.paste(snap, part, row)
  local there = M.clip(part, row)
  if there then api.clip_remove(there.id) end
  local meta = type(snap.meta) == "table" and paw.util.merge(snap.meta, {}) or {}
  meta.launcher = paw.util.merge(type(meta.launcher) == "table" and meta.launcher or {}, { row = row })
  return paw.restore_clip(paw.util.merge(snap, { cue = true, start = 0, meta = meta }), part)
end

-- Recording into a slot ----------------------------------------------------------
--
-- An empty slot of a part records `bars` bars from the next boundary. The
-- take is made by the transport's recording, as any take is; when the bars
-- are done the take ends. When it is clips (`transport.recorded`), the part
-- of it between the two boundaries becomes the slot's clip, the take leaves
-- the timeline, and the clip plays on in step, as if it had been playing
-- since the first boundary.

-- The slot being recorded: { part, row, from, to, before = clip ids on the
-- part before, take = the number of the take }, or nil.
M.recording = nil
local rec_timer

local grids = { ["1/16"] = 0.25, ["1/8"] = 0.5, ["1/4"] = 1 }
local bar_counts = { bar = 1, ["2bars"] = 2, ["4bars"] = 4 }

--- The first boundary of a quantize (the project's by default) at or after
--- `beat`, as the engine finds it.
function M.boundary(beat, q)
  q = q or M.quantize()
  if q == "off" then return beat end
  local bar = api.tempo_bar_of(beat)
  local start = api.tempo_bar_start(bar)
  local every = bar_counts[q]
  if every then
    if start < beat - 1e-9 then bar = bar + 1 end
    return api.tempo_bar_start(math.ceil(bar / every) * every)
  end
  local unit = grids[q] or 4 / select(2, paw.tempo.signature_at(beat))
  local steps = math.max(0, math.ceil((beat - start) / unit - 1e-9))
  return math.min(start + steps * unit, api.tempo_bar_start(bar + 1))
end

--- The part of a recorded clip from `from` to `to`, as options for a clip
--- in a slot.
local function piece(c, from, to)
  local opts = { name = "rec " .. c.name, length = to - from }
  if c.kind == "midi" then
    opts.notes, opts.controls = {}, {}
    for _, n in ipairs(api.clip_notes(c.id)) do
      local at = c.start + n.start
      if at >= from - 1e-9 and at < to - 1e-9 then
        opts.notes[#opts.notes + 1] = {
          pitch = n.pitch,
          velocity = n.velocity,
          start = at - from,
          length = math.min(n.length, to - at),
          lyric = n.lyric,
          meta = n.meta,
        }
      end
    end
    for _, m in ipairs(c.control_count > 0 and api.clip_controls(c.id) or {}) do
      local at = c.start + m.start
      if at >= from - 1e-9 and at < to - 1e-9 then
        opts.controls[#opts.controls + 1] = paw.util.merge(m, { start = at - from })
      end
    end
  else
    opts.file, opts.gain = c.file, c.gain
    opts.offset = c.offset + paw.time.seconds(from - c.start, c.start)
  end
  return opts
end

--- End the take that records into a slot. Its part in the slot's bars
--- becomes the slot's clip when the take is clips (`take_into_slot`).
local function finish_recording()
  local r = M.recording
  if not r then return end
  M.recording = nil
  if rec_timer then paw.cancel(rec_timer) end
  rec_timer = nil
  r.stopped_at = paw.transport.position
  -- Ending the take puts it on the timeline, as any take.
  paw.transport.recording = false
  if r.punch then api.transport_set("punch_enabled", true) end
end

--- Make the slot's clip from the take that recorded into it, now that the
--- take is clips on the timeline.
local function take_into_slot(r)
  -- The song stopped before the timer saw it: end the recording here.
  if M.recording == r then finish_recording() end
  local stopped_at = r.stopped_at
  local made
  for _, c in ipairs(api.clip_list(r.part)) do
    if not r.before[c.id] then
      if not made and c.start <= r.from + 1e-9 and c.start + c.length > r.from then
        made = M.add(r.part, r.row, piece(c, r.from, r.to))
      end
      api.clip_remove(c.id)
    end
  end
  api.undo_checkpoint()
  api.ui_redraw()
  if not made then
    return paw.notify("nothing was recorded into the slot: the song stopped before its first boundary", "warn")
  end
  paw.notify("recorded into slot " .. (r.row + 1))
  -- Going on in step: the loop counts from where the recording began.
  if paw.transport.playing and stopped_at >= r.to - 1e-9 then
    api.cue({ { part = r.part, clip = made, quantize = "off", from = r.from } })
  end
end

--- Record `bars` bars (1) into an empty slot of a part, from the next
--- boundary of the quantize of the project. paw arms the part if it is not
--- armed. The part stops what it plays at that boundary. If the song is
--- stopped, it starts. If you stop the song early, paw keeps the recording.
function M.record(part, row, bars)
  if M.clip(part, row) then error("the slot holds a clip already", 2) end
  if M.recording then error("a slot is being recorded already", 2) end
  if not api.part_get(part, "armed") then api.part_set(part, "armed", true) end
  local before = {}
  for _, c in ipairs(api.clip_list(part)) do
    before[c.id] = true
  end
  -- The slot's bars are the take: punching (and with it the pre-roll) is
  -- set aside until they are done. A count-in still leads in when stopped.
  local punch = api.transport_get().punch_enabled
  if punch then api.transport_set("punch_enabled", false) end
  if paw.transport.playing then
    paw.transport.recording = true
  else
    paw.transport.record()
  end
  local from = M.boundary(paw.transport.position)
  M.recording = {
    part = part,
    row = row,
    from = from,
    to = from + (bars or 1) * paw.time.bar(from),
    before = before,
    punch = punch,
    take = api.transport_get().take,
  }
  local r = M.recording
  local listener
  listener = paw.on("transport.recorded", function(e)
    if e.take ~= r.take then return end
    paw.off(listener)
    take_into_slot(r)
  end)
  api.cue({ { part = part, stop = true, quantize = M.quantize() } })
  rec_timer = paw.every(10, function()
    local current = M.recording
    if current and (not paw.transport.playing or paw.transport.position >= current.to) then finish_recording() end
  end)
  paw.notify("recording into slot " .. (row + 1) .. " from beat " .. paw.time.format(from))
  api.ui_redraw()
end

--- Stop recording into a slot now, keeping what was recorded.
M.finish_recording = finish_recording

-- Capturing a performance ------------------------------------------------------
--
-- While capturing and playing, what each part plays is read from the engine
-- every few milliseconds; the engine says on which beat each cue began, so
-- the timeline gets them exactly. When the song stops, every stretch a
-- part played a clip becomes a looped copy of the clip there, and every
-- stretch it was stopped is cleared, in one undo step.

local log, last, timer = {}, {}, nil

--- Begin or end a stretch for a part, from what the engine says of it.
local function note(s, position)
  local was = last[s.part]
  local key = string.format("%s|%.9f", tostring(s.clip or s.stopped or "timeline"), s.since)
  if was and was.key == key then return end
  if was and was.kind then was.to = s.since end
  if s.clip or s.stopped then
    -- How far into its loop the clip was where it began (a legato launch).
    local phase = s.clip and s.length and ((s.phase or 0) - (position - s.since)) % s.length or 0
    local entry = { kind = s.clip and "clip" or "stop", clip = s.clip, from = s.since, phase = phase, key = key }
    log[#log + 1] = { part = s.part, entry = entry }
    last[s.part] = entry
  else
    last[s.part] = { key = key }
  end
end

local function poll()
  if not paw.transport.playing then return end
  local position = paw.transport.position
  for _, s in ipairs(api.cue_state()) do
    note(s, position)
  end
end

--- Write what was captured into the timeline.
local function write(position)
  for part, entry in pairs(last) do
    if entry.kind and not entry.to then entry.to = position end
    last[part] = nil
  end
  local wrote = 0
  for _, item in ipairs(log) do
    local e, part = item.entry, item.part
    if e.to and e.to - e.from > 1e-9 and pcall(api.part_get, part) then
      paw.edit.arrange.clear(part, e.from, e.to)
      local ok, clip = pcall(api.clip_get, e.clip)
      if e.kind == "clip" and ok then
        local snap = paw.clip(clip.id):snapshot()
        snap.cue = nil
        if type(snap.meta) == "table" then
          snap.meta.launcher = nil
          if next(snap.meta) == nil then snap.meta = nil end
        end
        snap.start, snap.length = e.from, e.to - e.from
        snap.loop, snap.loop_length, snap.loop_start = true, clip.length, 0
        if clip.kind == "midi" and e.phase > 1e-9 then
          -- Begun partway through its loop: the loop starts that much before the clip.
          snap.loop_start = -e.phase
          for _, n in ipairs(snap.notes or {}) do
            n.start = n.start - e.phase
          end
          for _, c in ipairs(snap.controls or {}) do
            c.start = c.start - e.phase
          end
        end
        paw.restore_clip(snap, part)
      end
      wrote = wrote + 1
    end
  end
  log = {}
  return wrote
end

--- Start or stop the capture. If you stop it while the song plays, paw
--- writes the captured notes.
function M.capture(on)
  if on == nil then on = not M.capturing end
  if on == M.capturing then return end
  M.capturing = on
  if on then
    log, last = {}, {}
    timer = paw.every(10, poll)
    poll()
    paw.notify("capturing: what is launched is written into the timeline when the song stops")
  else
    if timer then paw.cancel(timer) end
    timer = nil
    poll()
    M.write_captured(paw.transport.position)
    paw.notify("capture stopped")
  end
  api.ui_redraw()
end

--- Write the captured notes that paw did not write yet, as one undo step,
--- up to `position` where the capture continues.
function M.write_captured(position)
  if #log == 0 then return end
  local wrote = write(position)
  api.undo_checkpoint()
  if wrote > 0 then paw.notify("captured " .. wrote .. (wrote == 1 and " clip" or " clips") .. " into the timeline") end
end

-- The song stopped where it says: so did what was launched.
paw.on("transport.stop", function(e)
  if M.capturing then M.write_captured(e.position or paw.transport.position) end
end)

paw.on("project.loaded", function()
  M.row = 0
  if M.capturing then M.capture(false) end
end)

return M
