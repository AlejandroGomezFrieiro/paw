-- MIDI in REAPER projects: the events of an inline `<SOURCE MIDI` block, and
-- Standard MIDI Files that a source refers to.
--
-- Both give notes in ticks from the start of the source, plus counts of what
-- is not a note, so an import can say what it left out.
local fmt = require("interop.rpp.format")
local smf = require("paw.midifile")
local M = {}

--- Pair note-ons with note-offs. `events` is a list of
--- { tick, status, data1, data2, muted }; returns notes as
--- { tick, length, pitch, velocity, channel, muted } in start order, and the
--- number of notes still held at the end (closed at `end_tick`).
local function pair(events, end_tick)
  local held, notes, open = {}, {}, 0
  for _, e in ipairs(events) do
    local kind, channel = math.floor(e[2] / 16), e[2] % 16
    local key = channel * 128 + e[3]
    if kind == 9 and e[4] > 0 then
      local list = held[key] or {}
      held[key] = list
      local note = { tick = e[1], pitch = e[3], velocity = e[4], channel = channel, muted = e[5] }
      list[#list + 1] = note
      notes[#notes + 1] = note
    elseif kind == 8 or kind == 9 then
      local list = held[key]
      local note = list and table.remove(list, 1)
      if note then note.length = e[1] - note.tick end
    end
  end
  for _, note in ipairs(notes) do
    if not note.length then
      note.length = math.max(0, end_tick - note.tick)
      open = open + 1
    end
  end
  table.sort(notes, function(a, b)
    if a.tick ~= b.tick then return a.tick < b.tick end
    return a.pitch < b.pitch
  end)
  return notes, open
end

local KIND_NAMES = {
  [10] = "aftertouch", [11] = "CC", [12] = "program change", [13] = "channel pressure", [14] = "pitch bend",
}

--- A raw controller event as paw has it: { tick, type, value (0 to 1, or
--- -1 to 1 for a bend), number, key, program, bank, channel }.
local function control_of(tick, status, d1, d2)
  local kind, channel = math.floor(status / 16), status % 16
  if kind == 11 then
    return { tick = tick, type = "cc", number = d1, value = d2 / 127, channel = channel }
  elseif kind == 14 then
    return { tick = tick, type = "bend", value = math.max(-1, math.min(1, (d1 + d2 * 128 - 8192) / 8192)), channel = channel }
  elseif kind == 13 then
    return { tick = tick, type = "pressure", value = d1 / 127, channel = channel }
  elseif kind == 10 then
    return { tick = tick, type = "pressure", key = d1, value = d2 / 127, channel = channel }
  elseif kind == 12 then
    return { tick = tick, type = "program", program = d1, value = 0, channel = channel }
  end
end
M.control_of = control_of

--- A bank select (CC 0 and CC 32) right before a program change at the
--- same tick becomes the bank of that program change, as paw keeps it.
local function join_banks(controls)
  local out = {}
  for _, c in ipairs(controls) do
    if c.type == "program" then
      local msb, lsb
      for i = #out, 1, -1 do
        local p = out[i]
        if p.tick ~= c.tick or p.type ~= "cc" or p.channel ~= c.channel or (p.number ~= 0 and p.number ~= 32) then break end
        if p.number == 0 then msb = math.floor(p.value * 127 + 0.5) else lsb = math.floor(p.value * 127 + 0.5) end
        table.remove(out, i)
      end
      if msb or lsb then c.bank = (msb or 0) * 128 + (lsb or 0) end
    end
    out[#out + 1] = c
  end
  return out
end
M.join_banks = join_banks

--- Read the events of a `<SOURCE MIDI` block. Returns
--- { ppq, qn, notes, controls, length (ticks), other = { [what] = count },
--- muted, file } where `file` is set instead when the source refers to a
--- .mid file. `controls` are as `control_of` makes them.
function M.read_source(source)
  local out = { ppq = 960, qn = true, notes = {}, controls = {}, length = 0, other = {}, muted = 0 }
  local file = source:child("FILE")
  if file then
    out.file = file:arg(1)
    return out
  end
  local hasdata = source:child("HASDATA")
  if hasdata then
    out.ppq = hasdata:argn(2) or 960
    out.qn = hasdata:arg(3) == "QN"
  end
  local ign = source:child("IGNTEMPO")
  if ign and ign:argn(1) == 1 then out.ignore_tempo = ign:argn(2) end
  local tick, events = 0, {}
  local function count(what) out.other[what] = (out.other[what] or 0) + 1 end
  for _, c in ipairs(source.children) do
    local name = c.tokens[1]
    if name == "E" or name == "e" or name == "Em" or name == "em" then
      tick = tick + (tonumber(c.tokens[2]) or 0)
      local status = tonumber(c.tokens[3] or "", 16)
      local d1, d2 = tonumber(c.tokens[4] or "0", 16) or 0, tonumber(c.tokens[5] or "0", 16) or 0
      if status then
        local kind = math.floor(status / 16)
        local muted = name:sub(2, 2) == "m"
        if kind == 8 or kind == 9 then
          events[#events + 1] = { tick, status, d1, d2, muted }
        elseif kind == 11 and d1 == 123 and d2 == 0 then
          -- "All notes off" is how REAPER marks the end of the source.
        elseif muted then
          count("muted " .. (KIND_NAMES[kind] or "other events"))
        else
          local c = control_of(tick, status, d1, d2)
          if c then out.controls[#out.controls + 1] = c else count("other events") end
        end
      end
    elseif name == "X" or name == "x" or name == "Xm" or name == "xm" then
      tick = tick + (tonumber(c.tokens[2]) or 0)
      count(c.children and #c.children > 0 and "sysex and text events" or "other events")
    end
  end
  out.length = tick
  out.controls = join_banks(out.controls)
  local notes, open = pair(events, tick)
  for _, n in ipairs(notes) do
    if n.muted then out.muted = out.muted + 1 else out.notes[#out.notes + 1] = n end
  end
  if open > 0 then out.other["notes without an end (held to the end)"] = open end
  return out
end

--- Lines for the events of a `<SOURCE MIDI` block from notes in ticks
--- ({ tick, length, pitch, velocity, channel }) and controller moves in
--- ticks (`controls`, as `control_of` makes them), ending with REAPER's
--- end-of-source marker at `length` ticks.
function M.event_lines(notes, length, controls)
  local events = {}
  -- Controller moves: { tick, kind, number, value, key, program, bank }
  -- as paw keeps them (values 0 to 1, a bend -1 to 1), before the notes at
  -- the same tick.
  local function b7(v) return math.max(0, math.min(127, math.floor(v * 127 + 0.5))) end
  for _, c in ipairs(controls or {}) do
    if c.type == "cc" then
      events[#events + 1] = { c.tick, 0, 0xb0, c.number, b7(c.value) }
    elseif c.type == "bend" then
      local v = math.max(0, math.min(16383, math.floor(c.value * 8192 + 8192 + 0.5)))
      events[#events + 1] = { c.tick, 0, 0xe0, v % 128, math.floor(v / 128) }
    elseif c.type == "pressure" and c.key then
      events[#events + 1] = { c.tick, 0, 0xa0, c.key, b7(c.value) }
    elseif c.type == "pressure" then
      events[#events + 1] = { c.tick, 0, 0xd0, b7(c.value), 0 }
    elseif c.type == "program" then
      if c.bank then
        events[#events + 1] = { c.tick, 0, 0xb0, 0, math.floor(c.bank / 128) % 128 }
        events[#events + 1] = { c.tick, 0, 0xb0, 32, c.bank % 128 }
      end
      events[#events + 1] = { c.tick, 0, 0xc0, c.program, 0 }
    end
  end
  for _, n in ipairs(notes) do
    local ch = n.channel or 0
    events[#events + 1] = { n.tick, 1, 0x90 + ch, n.pitch, n.velocity }
    events[#events + 1] = { n.tick + n.length, 0, 0x80 + ch, n.pitch, 0 }
  end
  -- Offs before ons at the same tick, so a repeated note is not cut short;
  -- controller moves before both, in their own order.
  for i, e in ipairs(events) do e[6] = i end
  table.sort(events, function(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    local ka = a[3] >= 0xa0 and -1 or a[2]
    local kb = b[3] >= 0xa0 and -1 or b[2]
    if ka ~= kb then return ka < kb end
    if ka == -1 then return a[6] < b[6] end
    if a[4] ~= b[4] then return a[4] < b[4] end
    return a[6] < b[6]
  end)
  local lines, tick = {}, 0
  for _, e in ipairs(events) do
    lines[#lines + 1] = fmt.line("E", e[1] - tick, string.format("%02x", e[3]), string.format("%02x", e[4]),
      string.format("%02x", e[5]))
    tick = e[1]
  end
  lines[#lines + 1] = fmt.line("E", math.max(0, length - tick), "b0", "7b", "00")
  return lines
end

-- Standard MIDI Files: read and written by the program's own reader
-- (runtime/lua/paw/midifile.lua), in the shape a source's events have here.

--- Read a Standard MIDI File. Returns { ppq, notes, length, other, tempo }
--- with every track's notes merged, ticks counted from the start, and the
--- first tempo found (bpm), or nil and a reason.
function M.read_smf(data)
  local file, why = smf.parse(data)
  if not file then return nil, why end
  local out = { ppq = file.ppq, notes = {}, controls = {}, length = file.length, other = {}, muted = 0 }
  local function count(what, n) out.other[what] = (out.other[what] or 0) + (n or 1) end
  for _, track in ipairs(file.tracks) do
    for _, n in ipairs(track.notes) do
      out.notes[#out.notes + 1] = { tick = n.tick, length = n.length, pitch = n.pitch, velocity = n.velocity, channel = n.channel }
    end
    for _, c in ipairs(track.controls) do
      local status = ({ cc = 0xb0, bend = 0xe0, program = 0xc0 })[c.type] or (c.key and 0xa0 or 0xd0)
      local d1, d2
      if c.type == "cc" then d1, d2 = c.number, c.value
      elseif c.type == "bend" then d1, d2 = c.value % 128, math.floor(c.value / 128)
      elseif c.type == "program" then d1, d2 = c.program, 0
      elseif c.key then d1, d2 = c.key, c.value
      else d1, d2 = c.value, 0 end
      out.controls[#out.controls + 1] = control_of(c.tick, status + (c.channel or 0), d1, d2)
    end
  end
  for what, n in pairs(file.skipped) do count(what, n) end
  if #file.markers > 0 then count("markers", #file.markers) end
  table.sort(out.notes, function(a, b)
    if a.tick ~= b.tick then return a.tick < b.tick end
    return a.pitch < b.pitch
  end)
  table.sort(out.controls, function(a, b) return a.tick < b.tick end)
  out.controls = join_banks(out.controls)
  out.tempo = file.tempos[1] and file.tempos[1].bpm
  return out
end

--- Write a Standard MIDI File (format 0) with these notes in ticks.
function M.write_smf(notes, ppq, bpm)
  return smf.encode({ format = 0, ppq = ppq, tempos = { { tick = 0, bpm = bpm or 120 } }, tracks = { { notes = notes } } })
end

return M
