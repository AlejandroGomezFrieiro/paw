-- MIDI in REAPER projects: the events of an inline `<SOURCE MIDI` block, and
-- Standard MIDI Files that a source refers to.
--
-- Both give notes in ticks from the start of the source, plus counts of what
-- is not a note, so an import can say what it left out.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local fmt = require("interop.rpp.format")
local smf = require("paw.midifile")
local type types = require("paw.types")

local record M
  --- A note in ticks from the start of a source.
  record Note
    tick: number
    length: number
    pitch: integer
    velocity: number
    --- The MIDI channel, from 0.
    channel: integer
    muted: boolean
  end

  --- A controller event as paw has it, in ticks: the value from 0 to 1
  --- (-1 to 1 for a bend).
  record Control
    tick: number
    type: types.ControlType
    value: number
    number: integer
    key: integer
    program: integer
    bank: integer
    channel: integer
  end

  --- The events of a source: notes and controller events in ticks of
  --- `ppq` to a quarter note, its length in ticks, and the counts of what
  --- was left out (`other` by what, `muted` notes). `file` is set instead
  --- when the source refers to a .mid file.
  record Source
    ppq: number
    qn: boolean
    notes: {Note}
    controls: {Control}
    length: number
    other: {string: integer}
    muted: integer
    file: string
    --- The tempo of a source that ignores the project's (IGNTEMPO).
    ignore_tempo: number
    --- The first tempo of a .mid file, in BPM.
    tempo: number
  end
end

local type Note = M.Note
local type Control = M.Control

--- A note-on or note-off of a source, as read.
local record Event
  tick: number
  status: integer
  data1: integer
  data2: integer
  muted: boolean
end

--- Pair note-ons with note-offs. Returns the notes in start order, and the
--- number of notes still held at the end (closed at `end_tick`).
local function pair(events: {Event}, end_tick: number): {Note}, integer
  local held: {integer: {Note}} = {}
  local notes: {Note} = {}
  local open = 0
  for _, e in ipairs(events) do
    local kind, channel = e.status // 16, e.status % 16
    local key = channel * 128 + e.data1
    if kind == 9 and e.data2 > 0 then
      local list = held[key] or {}
      held[key] = list
      local note: Note = {tick = e.tick, pitch = e.data1, velocity = e.data2, channel = channel, muted = e.muted}
      list[#list + 1] = note
      notes[#notes + 1] = note
    elseif kind == 8 or kind == 9 then
      local list = held[key]
      local note = list and table.remove(list, 1)
      if note then
        note.length = e.tick - note.tick
      end
    end
  end
  for _, note in ipairs(notes) do
    if not note.length then
      note.length = math.max(0, end_tick - note.tick)
      open = open + 1
    end
  end
  table.sort(
    notes,
    function(a: Note, b: Note): boolean
      if a.tick ~= b.tick then
        return a.tick < b.tick
      end
      return a.pitch < b.pitch
    end
  )
  return notes, open
end

local KIND_NAMES: {integer: string} = {
  [10] = "aftertouch",
  [11] = "CC",
  [12] = "program change",
  [13] = "channel pressure",
  [14] = "pitch bend",
}

--- A raw controller event as paw has it, or nil for a status that is not
--- one.
function M.control_of(tick: number, status: integer, d1: integer, d2: integer): Control
  local kind, channel = status // 16, status % 16
  if kind == 11 then
    return {tick = tick, type = "cc", number = d1, value = d2 / 127, channel = channel}
  elseif kind == 14 then
    return {
      tick = tick,
      type = "bend",
      value = math.max(-1, math.min(1, (d1 + d2 * 128 - 8192) / 8192)),
      channel = channel,
    }
  elseif kind == 13 then
    return {tick = tick, type = "pressure", value = d1 / 127, channel = channel}
  elseif kind == 10 then
    return {tick = tick, type = "pressure", key = d1, value = d2 / 127, channel = channel}
  elseif kind == 12 then
    return {tick = tick, type = "program", program = d1, value = 0, channel = channel}
  end
end

--- A bank select (CC 0 and CC 32) right before a program change at the
--- same tick becomes the bank of that program change, as paw keeps it.
function M.join_banks(controls: {Control}): {Control}
  local out: {Control} = {}
  for _, c in ipairs(controls) do
    if c.type == "program" then
      local msb, lsb: integer, integer
      for i = #out, 1, -1 do
        local p = out[i]
        if p.tick ~= c.tick or p.type ~= "cc" or p.channel ~= c.channel or (p.number ~= 0 and p.number ~= 32) then
          break
        end
        if p.number == 0 then
          msb = math.floor(p.value * 127 + 0.5)
        else
          lsb = math.floor(p.value * 127 + 0.5)
        end
        table.remove(out, i)
      end
      if msb or lsb then
        c.bank = (msb or 0) * 128 + (lsb or 0)
      end
    end
    out[#out + 1] = c
  end
  return out
end

--- The tokens of an event line (`E delta status data1 data2`) as numbers.
local function event_bytes(c: fmt.Node): integer, integer, integer
  local function hex(i: integer, default: string): integer
    return math.tointeger(tonumber(c:arg(i) or default, 16))
  end
  return hex(2, ""), hex(3, "0") or 0, hex(4, "0") or 0
end

--- Read the events of a `<SOURCE MIDI` block. `controls` are as
--- `control_of` makes them.
function M.read_source(source: fmt.Node): M.Source
  local out: M.Source = {ppq = 960, qn = true, notes = {}, controls = {}, length = 0, other = {}, muted = 0}
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
  if ign and ign:argn(1) == 1 then
    out.ignore_tempo = ign:argn(2)
  end
  local tick: number = 0
  local events: {Event} = {}
  local function count(what: string)
    out.other[what] = (out.other[what] or 0) + 1
  end
  for _, c in ipairs(source.children) do
    local name = c:name()
    if name == "E" or name == "e" or name == "Em" or name == "em" then
      tick = tick + (c:argn(1) or 0)
      local status, d1, d2 = event_bytes(c)
      if status then
        local kind = status // 16
        local muted = name:sub(2, 2) == "m"
        if kind == 8 or kind == 9 then
          events[#events + 1] = {tick = tick, status = status, data1 = d1, data2 = d2, muted = muted}
        elseif kind == 11 and d1 == 123 and d2 == 0 then
          -- "All notes off" is how REAPER marks the end of the source.
        elseif muted then
          count("muted " .. (KIND_NAMES[kind] or "other events"))
        else
          local control = M.control_of(tick, status, d1, d2)
          if control then
            out.controls[#out.controls + 1] = control
          else
            count("other events")
          end
        end
      end
    elseif name == "X" or name == "x" or name == "Xm" or name == "xm" then
      tick = tick + (c:argn(1) or 0)
      count(c.children and #c.children > 0 and "sysex and text events" or "other events")
    end
  end
  out.length = tick
  out.controls = M.join_banks(out.controls)
  local notes, open = pair(events, tick)
  for _, n in ipairs(notes) do
    if n.muted then
      out.muted = out.muted + 1
    else
      out.notes[#out.notes + 1] = n
    end
  end
  if open > 0 then
    out.other["notes without an end (held to the end)"] = open
  end
  return out
end

--- An event of a source to write: `kind` sorts the note-offs (0) before
--- the note-ons (1) at a tick, and `order` keeps the order they came in.
local record Line
  tick: number
  kind: integer
  status: integer
  data1: integer
  data2: integer
  order: integer
end

--- A 0 to 1 value as 7 bits.
local function b7(v: number): integer
  return math.max(0, math.min(127, math.floor(v * 127 + 0.5)))
end

--- The events of controller moves, as paw keeps them (values 0 to 1, a
--- bend -1 to 1).
local function control_events(controls: {Control}, events: {Line})
  local function add(tick: number, status: integer, d1: integer, d2: integer)
    events[#events + 1] = {tick = tick, kind = 0, status = status, data1 = d1, data2 = d2}
  end
  for _, c in ipairs(controls or {}) do
    if c.type == "cc" then
      add(c.tick, 0xb0, c.number, b7(c.value))
    elseif c.type == "bend" then
      local v = math.max(0, math.min(16383, math.floor(c.value * 8192 + 8192 + 0.5)))
      add(c.tick, 0xe0, v % 128, v // 128)
    elseif c.type == "pressure" and c.key then
      add(c.tick, 0xa0, c.key, b7(c.value))
    elseif c.type == "pressure" then
      add(c.tick, 0xd0, b7(c.value), 0)
    elseif c.type == "program" then
      if c.bank then
        add(c.tick, 0xb0, 0, (c.bank // 128) % 128)
        add(c.tick, 0xb0, 32, c.bank % 128)
      end
      add(c.tick, 0xc0, c.program, 0)
    end
  end
end

--- Offs before ons at the same tick, so a repeated note is not cut short;
--- controller moves before both, in their own order.
local function before(a: Line, b: Line): boolean
  if a.tick ~= b.tick then
    return a.tick < b.tick
  end
  local ka = a.status >= 0xa0 and -1 or a.kind
  local kb = b.status >= 0xa0 and -1 or b.kind
  if ka ~= kb then
    return ka < kb
  end
  if ka == -1 then
    return a.order < b.order
  end
  if a.data1 ~= b.data1 then
    return a.data1 < b.data1
  end
  return a.order < b.order
end

--- Lines for the events of a `<SOURCE MIDI` block from notes in ticks
--- and controller moves in ticks (`controls`, as `control_of` makes
--- them), ending with REAPER's end-of-source marker at `length` ticks.
function M.event_lines(notes: {Note}, length: number, controls?: {Control}): {fmt.Node}
  local events: {Line} = {}
  control_events(controls, events)
  for _, n in ipairs(notes) do
    local ch = n.channel or 0
    local velocity = math.tointeger(n.velocity) or math.floor(n.velocity)
    events[#events + 1] = {tick = n.tick, kind = 1, status = 0x90 + ch, data1 = n.pitch, data2 = velocity}
    events[#events + 1] = {tick = n.tick + n.length, kind = 0, status = 0x80 + ch, data1 = n.pitch, data2 = 0}
  end
  for i, e in ipairs(events) do
    e.order = i
  end
  table.sort(events, before)
  local lines: {fmt.Node} = {}
  local tick: number = 0
  for _, e in ipairs(events) do
    lines[#lines + 1] = fmt.line(
      "E",
      e.tick - tick,
      string.format("%02x", e.status),
      string.format("%02x", e.data1),
      string.format("%02x", e.data2)
    )
    tick = e.tick
  end
  lines[#lines + 1] = fmt.line("E", math.max(0, length - tick), "b0", "7b", "00")
  return lines
end

-- Standard MIDI Files: read and written by the program's own reader
-- (runtime/lua/paw/midifile.tl), in the shape a source's events have here.

local STATUS: {string: integer} = {cc = 0xb0, bend = 0xe0, program = 0xc0}

--- A controller of a .mid file as the status and data bytes of its event.
local function event_of(c: smf.Control): integer, integer, integer
  local status = STATUS[c.type as string] or (c.key and 0xa0 or 0xd0)
  local value = math.tointeger(c.value) or math.floor(c.value)
  if c.type == "cc" then
    return status, c.number, value
  elseif c.type == "bend" then
    return status, value % 128, value // 128
  elseif c.type == "program" then
    return status, c.program, 0
  elseif c.key then
    return status, c.key, value
  end
  return status, value, 0
end

--- Read a Standard MIDI File, with every track's notes merged, ticks
--- counted from the start, and the first tempo found (bpm); or nil and a
--- reason.
function M.read_smf(data: string): M.Source, string
  local file, why = smf.parse(data)
  if not file then
    return nil, why
  end
  local out: M.Source = {ppq = file.ppq, notes = {}, controls = {}, length = file.length, other = {}, muted = 0}
  local function count(what: string, n?: integer)
    out.other[what] = (out.other[what] or 0) + (n or 1)
  end
  for _, file_track in ipairs(file.tracks) do
    for _, n in ipairs(file_track.notes) do
      out.notes[#out.notes + 1] = {
        tick = n.tick, length = n.length, pitch = n.pitch, velocity = n.velocity, channel = n.channel
      }
    end
    for _, c in ipairs(file_track.controls) do
      local status, d1, d2 = event_of(c)
      out.controls[#out.controls + 1] = M.control_of(c.tick, status + (c.channel or 0), d1, d2)
    end
  end
  for what, n in pairs(file.skipped) do
    count(what, n)
  end
  if #file.markers > 0 then
    count("markers", #file.markers)
  end
  table.sort(
    out.notes,
    function(a: Note, b: Note): boolean
      if a.tick ~= b.tick then
        return a.tick < b.tick
      end
      return a.pitch < b.pitch
    end
  )
  table.sort(out.controls, function(a: Control, b: Control): boolean return a.tick < b.tick end)
  out.controls = M.join_banks(out.controls)
  out.tempo = file.tempos[1] and file.tempos[1].bpm
  return out
end

--- Write a Standard MIDI File (format 0) with these notes in ticks.
function M.write_smf(notes: {smf.Note}, ppq: number, bpm?: number): string
  return smf.encode(
    {
      format = 0,
      ppq = ppq,
      tempos = {{tick = 0, bpm = bpm or 120}},
      tracks = {{notes = notes}},
    }
  )
end

return M
