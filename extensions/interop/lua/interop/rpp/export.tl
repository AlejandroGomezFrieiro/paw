-- Writing paw's project as a REAPER project.
--
--   local result = require("interop.rpp.export").file("song.rpp")
--   print(result.report:text())     -- what could not be written, grouped
--
-- The file is laid out the way REAPER 7 writes its own: the same lines in the
-- same order, with REAPER's defaults for the settings paw does not have.
-- Beats become seconds by the project's tempo map, which is written as
-- REAPER's tempo envelope (TEMPOENVEX) when it has more than one point.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local fmt = require("interop.rpp.format")
local midi = require("interop.rpp.midi")
local fx = require("interop.rpp.fx")
local interop = require("interop")
local reports = require("interop.report")
local type rpp_import = require("interop.rpp.import")
local type types = require("paw.types")

local api = paw.api

local type Node = fmt.Node
local type Report = reports.Report

local record M
  PPQ: integer
end

M.PPQ = 960

--- What an export keeps while it runs.
local record Ctx
  --- Beats to seconds in the project.
  sec: function(beat: number): number
  --- The folder of the file: media under it are written relative to it.
  dir: string
  --- The last item id (`IID`) given.
  iid: integer
  --- A new GUID, from the seed of the export.
  guid: function(): string
  report: Report
end

local amp = interop.amp

-- GUIDs ------------------------------------------------------------------------------

--- GUIDs from a seed (a Park-Miller generator): the same seed gives the
--- same file.
local function guid_maker(seed: integer): function(): string
  local state = seed % 2147483647
  if state <= 0 then
    state = state + 2147483646
  end
  local function hex(n: integer): string
    local out: {string} = {}
    for i = 1, n do
      state = (state * 16807) % 2147483647
      out[i] = string.format("%X", state % 16)
    end
    return table.concat(out)
  end
  return function(): string
    return "{" .. hex(8) .. "-" .. hex(4) .. "-" .. hex(4) .. "-" .. hex(4) .. "-" .. hex(12) .. "}"
  end
end

--- A colour as #rrggbb to REAPER's native colour (red + green * 256 +
--- blue * 65536 on Linux, with 0x1000000 to say it is in use), or nil.
function M.native_colour(colour: string): integer
  local r, g, b = tostring(colour or ""):match("^#(%x%x)(%x%x)(%x%x)$")
  if not r then
    return nil
  end
  return math.tointeger(0x1000000 + tonumber(r, 16) + tonumber(g, 16) * 256 + tonumber(b, 16) * 65536)
end

-- Pieces -----------------------------------------------------------------------------

local function relative(path: string, dir: string): string
  if dir and path:sub(1, #dir + 1) == dir .. "/" then
    return path:sub(#dir + 2)
  end
  return path
end

local SOURCE_TYPES: {string: string} = {
  wav = "WAVE",
  wave = "WAVE",
  aif = "WAVE",
  aiff = "WAVE",
  flac = "FLAC",
  mp3 = "MP3",
  ogg = "VORBIS",
}

--- REAPER's point shape for each of paw's: hold is square (1), smooth is
--- slow start and end (2).
local SHAPES: {types.LaneShape: integer} = {hold = 1, smooth = 2}

--- The shape number of each point of a lane, by its beat.
local function shapes_of(lane: types.Lane, ctx: Ctx, label: string): {number: integer}
  local out: {number: integer} = {}
  for _, s in ipairs(api.lane_shapes(lane.id)) do
    out[s.beat] = SHAPES[s.shape] or 0
    local tension: number = math.abs(s.tension or 0)
    if s.shape == "smooth" and tension > 1e-9 then
      ctx.report:count("Tension of smooth automation curves (REAPER's slow start and end has none)", label)
    end
  end
  return out
end

--- How REAPER names a parameter of a CLAP or VST3 plugin after its place:
--- the plugin's own id for it, as a signed 32-bit number. Nil for others.
local function reaper_ident(info: types.ParamInfo, format: string): string
  local n = (format == "clap" or format == "vst3") and tonumber(info.id)
  if not n or n ~= math.floor(n) or n < 0 or n >= 2 ^ 32 then
    return nil
  end
  return string.format("%d", math.floor(n >= 2 ^ 31 and n - 2 ^ 32 or n))
end

--- The lines every envelope block starts with.
local function envelope_head(env: Node, ctx: Ctx, lane: types.Lane)
  env:add(fmt.line("EGUID", ctx.guid()))
  env:add(fmt.line("ACT", lane.enabled and 1 or 0, -1))
  env:add(fmt.line("VIS", 1, 1, 1))
  env:add(fmt.line("LANEHEIGHT", 0, 0))
  env:add(fmt.line("ARM", 0))
  env:add(fmt.line("DEFSHAPE", 0, -1, -1))
end

--- A plugin parameter's lane as `<PARMENV`: the parameter by its place
--- among the plugin's (from 0) and, as REAPER writes it, the plugin's own
--- id for it after a colon (`5:-1611133501`), the values as a share of
--- its range.
local function param_envelope(
  lane: types.Lane, index: integer, info: types.ParamInfo, format: string, ctx: Ctx, label: string
): Node
  local ident = reaper_ident(info, format)
  local env = fmt.block("PARMENV", ident and (index - 1) .. ":" .. ident or index - 1, 0, 1, 0)
  envelope_head(env, ctx, lane)
  local shapes = shapes_of(lane, ctx, label)
  local span = info.max - info.min
  for _, p in ipairs(api.lane_points(lane.id)) do
    local f = span ~= 0 and (p[2] - info.min) / span or 0
    env:add(fmt.line("PT", string.format("%.12f", ctx.sec(p[1])), math.max(0, math.min(1, f)), shapes[p[1]] or 0))
  end
  return env
end

local function envelope(name: string, lane: types.Lane, ctx: Ctx, label?: string): Node
  local env = fmt.block(name)
  envelope_head(env, ctx, lane)
  -- Points are amplitudes whatever the scaling; REAPER 7 marks volume
  -- envelopes with fader scaling, which only changes how they are drawn.
  if name:match("VOLENV") then
    env:add(fmt.line("VOLTYPE", 1))
  end
  local points = api.lane_points(lane.id)
  local shapes = shapes_of(lane, ctx, label or name)
  for _, p in ipairs(points) do
    local value: number
    if lane.target == "volume" then
      value = amp(p[2])
    else
      value = -p[2] -- REAPER's pan envelopes run from +1 (left) to -1 (right)
    end
    env:add(fmt.line("PT", string.format("%.12f", ctx.sec(p[1])), value, shapes[p[1]] or 0))
  end
  return env
end

--- An entry of an FX chain: a device of the part, or a plugin kept from
--- an imported REAPER project.
local record Entry
  device: integer
  holder: rpp_import.Placeholder
end

--- The devices of a part with the plugins kept from an imported REAPER
--- project at their places in the chain.
local function chain_entries(t: types.Part): {Entry}
  local entries: {Entry} = {}
  for _, device in ipairs(t.devices) do
    entries[#entries + 1] = {device = device}
  end
  local holders: {rpp_import.Placeholder} = {}
  local kept = (t.meta or {}).rpp_placeholders as {rpp_import.Placeholder}
  for _, holder in ipairs(kept or {}) do
    if holder.rpp then
      holders[#holders + 1] = holder
    end
  end
  table.sort(
    holders,
    function(x: rpp_import.Placeholder, y: rpp_import.Placeholder): boolean
      return (x.position or 0) < (y.position or 0)
    end
  )
  for _, holder in ipairs(holders) do
    table.insert(entries, math.max(1, math.min(holder.position or #entries + 1, #entries + 1)), {holder = holder})
  end
  return entries
end

--- The FX chain of a part as it is written: the chain block, the
--- parameter lanes of each device, and the kinds of device.
local record Chain
  block: Node
  lanes_of: {integer: {types.Lane}}
  types: {string: types.DeviceType}
  count: integer
  ctx: Ctx
  label: string
end

--- The parameter lanes of a device, written after its plugin (or counted
--- as left out when the device is not written).
local function param_lanes(chain: Chain, device: integer, written: boolean)
  local ctx, label = chain.ctx, chain.label
  for _, lane in ipairs(chain.lanes_of[device] or {}) do
    local index: integer
    local info: types.ParamInfo
    local d = api.device_get(device)
    for i, p in ipairs(d.param_info or {}) do
      if p.key == lane.param then
        index, info = i, p
      end
    end
    if written and index then
      chain.block:add(param_envelope(lane, index, info, d.format, ctx, label .. ": " .. lane.param))
    else
      ctx.report:add(
        "Plugin parameter automation",
        label .. ": " .. tostring(lane.param) .. (written and "" or " (its device is not written)")
      )
    end
  end
end

--- A plugin block in the chain, with REAPER's lines around it.
local function add_plugin(chain: Chain, block: Node, bypass: boolean)
  local c = chain.block
  c:add(fmt.line("BYPASS", bypass and 1 or 0, 0, 0))
  c:add(block)
  c:add(fmt.line("FLOATPOS", 0, 0, 0, 0))
  c:add(fmt.line("FXID", chain.ctx.guid()))
  c:add(fmt.line("WAK", 0, 0))
  chain.count = chain.count + 1
end

--- A device of paw in the chain, as its plugin block when REAPER has one.
local function add_device(chain: Chain, device: integer)
  local ctx, label = chain.ctx, chain.label
  local d = api.device_get(device)
  local info = chain.types[d.kind]
  if not info or info.format == "builtin" then
    ctx.report:add("Built-in devices (no REAPER equivalent)", label .. ": " .. d.kind)
    param_lanes(chain, device, false)
    return
  end
  local ok, block, why = pcall(fx.export, device, info) as (boolean, Node, string)
  if ok and block then
    add_plugin(chain, block, d.bypass)
    if why then
      ctx.report:count("Plugin settings", why)
    end
    param_lanes(chain, device, true)
  else
    -- A failed call gives its error in place of the block.
    local reason = ok and why or tostring(block)
    ctx.report:add("Plugins not written", label .. ": " .. d.kind .. " (" .. reason .. ")")
    param_lanes(chain, device, false)
  end
end

--- The FX chain of a part, or nil when it has no plugin.
local function fx_chain(name: string, part: integer, t: types.Part, ctx: Ctx, label: string): Node
  local chain: Chain = {
    block = fmt.block(name),
    lanes_of = {},
    -- The kinds of device, looked up as they are met.
    types = interop.device_types(),
    count = 0,
    ctx = ctx,
    label = label,
  }
  for _, lane in ipairs(api.lane_list(part)) do
    if lane.target == "param" then
      chain.lanes_of[lane.device] = chain.lanes_of[lane.device] or {}
      table.insert(chain.lanes_of[lane.device], lane)
    end
  end
  chain.block:add(fmt.line("SHOW", 0))
  chain.block:add(fmt.line("LASTSEL", 0))
  chain.block:add(fmt.line("DOCKED", 0))
  for _, entry in ipairs(chain_entries(t)) do
    if entry.holder then
      -- Plugins kept from an imported REAPER project go back as they were.
      local block = fmt.parse(entry.holder.rpp).children[1]
      if block and block.children then
        add_plugin(chain, block, entry.holder.bypass)
      end
    else
      add_device(chain, entry.device)
    end
  end
  return chain.count > 0 and chain.block or nil
end

local function item_common(item: Node, clip: types.Clip, ctx: Ctx, looped: boolean)
  local stop = clip.start + clip.length
  item:add(fmt.line("POSITION", ctx.sec(clip.start)))
  item:add(fmt.line("SNAPOFFS", 0))
  item:add(fmt.line("LENGTH", ctx.sec(stop) - ctx.sec(clip.start)))
  item:add(fmt.line("LOOP", looped and 1 or 0))
  item:add(fmt.line("ALLTAKES", 0))
  -- Fade lengths in seconds; shape 1 is REAPER's default.
  local fin = (clip.fade_in or 0) > 0 and ctx.sec(clip.start + clip.fade_in) - ctx.sec(clip.start) or 0
  local fout = (clip.fade_out or 0) > 0 and ctx.sec(stop) - ctx.sec(stop - clip.fade_out) or 0
  item:add(fmt.line("FADEIN", 1, fin, 0, 1, 0, 0, 0))
  item:add(fmt.line("FADEOUT", 1, fout, 0, 1, 0, 0, 0))
  item:add(fmt.line("MUTE", clip.muted and 1 or 0, 0))
  item:add(fmt.line("SEL", 0))
  item:add(fmt.line("IGUID", ctx.guid()))
  ctx.iid = ctx.iid + 1
  item:add(fmt.line("IID", ctx.iid))
  item:add(fmt.line("NAME", clip.name or "")):quoted(1)
end

--- The repeat of a looped clip: where it starts and how many beats it
--- lasts, from the clip's start; nil when the clip does not loop.
local function repeat_of(clip: types.Clip): number, number
  if clip.loop and (clip.loop_length or 0) > 0 then
    return clip.loop_start or 0, clip.loop_length
  end
end

local function audio_item(clip: types.Clip, ctx: Ctx, label: string): Node
  local item = fmt.block("ITEM")
  local stretch = clip.stretch or 1
  local from, beats = repeat_of(clip)
  if from and math.abs(stretch - 1) > 1e-9 then
    ctx.report:add("Loops of stretched audio clips (written without the loop)", label)
    from = nil
  end
  item_common(item, clip, ctx, from ~= nil)
  item:add(fmt.line("VOLPAN", 1, 0, amp(clip.gain or 0), -1))
  -- A looped clip repeats a stretch of its file that begins `lead`
  -- seconds before the clip's start (see paw's audio_regions). When that
  -- is not the start of the file, the item plays a section of it.
  local offset = clip.offset or 0
  local section_start, section_length: number, number
  if from then
    local period = ctx.sec(clip.start + beats) - ctx.sec(clip.start)
    section_start = offset + from * period / beats
    section_length = period
    offset = offset - section_start
  end
  item:add(fmt.line("SOFFS", offset))
  -- The rate keeps the pitch; paw's pitch is REAPER's pitch shift.
  item:add(fmt.line("PLAYRATE", 1 / stretch, 1, clip.pitch or 0, -1, 0, 0.0025))
  item:add(fmt.line("CHANMODE", 0))
  item:add(fmt.line("GUID", ctx.guid()))
  local ext = (clip.file:match("%.(%w+)$") or ""):lower()
  local source = item
  if section_start then
    source = item:add(fmt.block("SOURCE", "SECTION"))
    source:add(fmt.line("LENGTH", section_length))
    source:add(fmt.line("STARTPOS", section_start))
    source:add(fmt.line("OVERLAP", 0))
  end
  source = source:add(fmt.block("SOURCE", SOURCE_TYPES[ext] or "WAVE"))
  source:add(fmt.line("FILE", relative(clip.file, ctx.dir))):quoted(1)
  if not SOURCE_TYPES[ext] then
    ctx.report:add("Media REAPER may not read", clip.file)
  end
  if clip.stretch_mode and clip.stretch_mode ~= "auto" then
    ctx.report:add("Stretch modes (REAPER uses its own)", label .. ": " .. tostring(clip.stretch_mode))
  end
  if clip.warp and #clip.warp > 0 then
    ctx.report:add("Warp markers", label)
  end
  return item
end

--- Controller moves of a clip from `from` to `to` beats as ticks from
--- `shift`, for the events of a source.
local function control_ticks(controls: {types.Control}, from: number, to: number, shift: number): {midi.Control}
  local out: {midi.Control} = {}
  for _, c in ipairs(controls) do
    if c.start >= from - 1e-9 and c.start < to - 1e-9 then
      out[#out + 1] = {
        tick = math.floor((c.start - shift) * M.PPQ + 0.5),
        type = c.type,
        number = c.number,
        value = c.value,
        key = c.key,
        program = c.program,
        bank = c.bank,
      }
    end
  end
  return out
end

--- A note of a clip in ticks; `rounded` is true when its times are not on
--- a tick.
local function note_ticks(n: types.Note, shift: number): midi.Note, boolean
  local start = n.start - shift
  local tick = math.floor(start * M.PPQ + 0.5)
  local stop = math.floor((start + n.length) * M.PPQ + 0.5)
  local rounded = math.abs(tick - start * M.PPQ) > 1e-6 or math.abs(stop - (start + n.length) * M.PPQ) > 1e-6
  local channel = n.meta and tonumber(n.meta.channel)
  return {
    tick = tick,
    length = math.max(1, stop - tick),
    pitch = n.pitch,
    velocity = n.velocity,
    channel = channel and math.max(0, math.min(15, math.floor(channel) - 1)) or 0,
  }, rounded
end

--- The notes of a clip from `lo` to `hi` beats, in ticks from `shift`.
--- Notes before the clip's start are hidden by a trim, and not played; in
--- a looped clip, those outside the repeated stretch.
local function clip_note_ticks(
  clip: types.Clip, lo: number, hi: number, shift: number, ctx: Ctx, label: string
): {midi.Note}
  local notes: {midi.Note} = {}
  local rounded, attrs = 0, 0
  local all = api.clip_notes(clip.id)
  for _, n in ipairs(all) do
    if n.start >= lo - 1e-9 and n.start < hi - 1e-9 then
      local note, off_tick = note_ticks(n, shift)
      notes[#notes + 1] = note
      if off_tick then
        rounded = rounded + 1
      end
      if n.attr then
        attrs = attrs + 1
      end
    end
  end
  if rounded > 0 then
    ctx.report:count("Note times rounded to 1/960 beat", label, rounded)
  end
  -- A REAPER project keeps MIDI 1.0, where a note has no attribute.
  if attrs > 0 then
    ctx.report:count("Note attributes (MIDI 2.0 articulations)", label, attrs)
  end
  return notes
end

--- The controller moves MIDI 1.0 has an event for: the others are taken
--- out and counted.
local function midi1_controls(controls: {midi.Control}, ctx: Ctx, label: string)
  local other = 0
  for i = #controls, 1, -1 do
    local c = controls[i]
    local midi1 = c.type == "cc" or c.type == "bend" or c.type == "pressure" or c.type == "program"
    if not midi1 or (c.key and c.type ~= "pressure") then
      other = other + 1
      table.remove(controls, i)
    end
  end
  if other > 0 then
    ctx.report:count("Controllers MIDI 1.0 has no event for (registered, assignable, per note)", label, other)
  end
end

local function midi_item(clip: types.Clip, ctx: Ctx, label: string): Node
  local item = fmt.block("ITEM")
  -- A looped clip: its repeated stretch is the source, which the item
  -- starts into by the stretch's distance before the clip's start.
  local from, beats = repeat_of(clip)
  local lo, hi, shift = 0.0, clip.length, 0.0
  if from then
    lo, hi, shift = from, from + beats, from
  end
  item_common(item, clip, ctx, from ~= nil)
  item:add(fmt.line("VOLPAN", 1, 0, 1, -1))
  item:add(fmt.line("SOFFS", from and -from * 60 / api.tempo_at(clip.start) or 0))
  item:add(fmt.line("PLAYRATE", 1, 1, 0, -1, 0, 0.0025))
  item:add(fmt.line("CHANMODE", 0))
  item:add(fmt.line("GUID", ctx.guid()))
  local source = item:add(fmt.block("SOURCE", "MIDI"))
  source:add(fmt.line("HASDATA", 1, M.PPQ, "QN"))
  source:add(fmt.line("CCINTERP", 32))
  source:add(fmt.line("POOLEDEVTS", ctx.guid()))
  local notes = clip_note_ticks(clip, lo, hi, shift, ctx, label)
  local length = math.floor((hi - lo) * M.PPQ + 0.5)
  local controls = control_ticks(api.clip_controls(clip.id), lo, hi, shift)
  midi1_controls(controls, ctx, label)
  for _, line in ipairs(midi.event_lines(notes, length, controls)) do
    source:add(line)
  end
  source:add(fmt.line("CCINTERP", 32))
  source:add(fmt.line("GUID", ctx.guid()))
  source:add(fmt.line("IGNTEMPO", 0, 120, 4, 4))
  return item
end

-- Parts and folders -----------------------------------------------------------------

--- Folder depth changes for REAPER (`ISBUS`), and which parts' outputs a
--- folder cannot express (they become sends from a part whose parent send
--- is off). A part is in a folder when it follows its output part
--- directly, or follows a sibling in that folder.
local function layout(list: {types.Part}): {integer}, {integer: boolean}, {integer: integer}
  local index: {integer: integer} = {}
  for i, t in ipairs(list) do
    index[t.id] = i
  end
  local depth: {integer} = {}
  local stack: {integer} = {}
  local unfoldered: {integer: boolean} = {}
  for i, t in ipairs(list) do
    depth[i] = 0
    local parent = t.output
    local inside = false
    for _, open in ipairs(stack) do
      if open == parent then
        inside = true
      end
    end
    if parent and not inside then
      unfoldered[t.id] = true
    end
    -- Close folders until the innermost open one is the parent (or none is).
    local pops = 0
    while #stack > 0 and stack[#stack] ~= (inside and parent or nil) do
      stack[#stack] = nil
      pops = pops + 1
    end
    if pops > 0 then
      depth[i - 1] = depth[i - 1] - pops
    end
    local nxt = list[i + 1]
    if nxt and nxt.output == t.id then
      depth[i] = 1
      stack[#stack + 1] = t.id
    end
  end
  if #list > 0 then
    depth[#list] = depth[#list] - #stack
  end
  return depth, unfoldered, index
end

--- A send to write as a receive (`AUXRECV`) of the part it goes to.
local record Receive
  from: integer
  level: number
  pre: boolean
end

--- Where the parts are: their folder depths, the parts whose output is
--- not their folder, their places, and the receives of each.
local record Layout
  depth: {integer}
  unfoldered: {integer: boolean}
  index: {integer: integer}
  receives: {integer: {Receive}}
end

--- REAPER's record input of a part: an audio input (from 0) or a pair
--- (1024 and up), or none (-1).
local function rec_input(t: types.Part): integer
  if not t.input then
    return -1
  end
  local a = t.input:match("^(%d+)/(%d+)$")
  if a then
    return 1024 + math.floor(tonumber(a)) - 1
  end
  return math.floor(tonumber(t.input) or 1) - 1
end

local function part_block(t: types.Part, i: integer, ctx: Ctx, at: Layout): Node
  local guid = ctx.guid()
  local block = fmt.block("TRACK", guid)
  block:add(fmt.line("NAME", t.name or "")):quoted(1)
  block:add(fmt.line("PEAKCOL", M.native_colour(t.color) or 16576))
  block:add(fmt.line("BEAT", -1))
  block:add(fmt.line("AUTOMODE", 0))
  block:add(fmt.line("VOLPAN", amp(t.volume or 0), t.pan or 0, -1, -1, 1))
  block:add(fmt.line("MUTESOLO", t.mute and 1 or 0, t.solo and 2 or 0, 0))
  block:add(fmt.line("IPHASE", 0))
  block:add(fmt.line("PLAYOFFS", 0, 1))
  local d = at.depth[i] or 0
  block:add(fmt.line("ISBUS", d > 0 and 1 or (d < 0 and 2 or 0), d))
  block:add(fmt.line("BUSCOMP", 0, 0, 0, 0, 0))
  block:add(fmt.line("SHOWINMIX", 1, 0.6667, 0.5, 1, 0.5, 0, 0, 0, 0))
  block:add(fmt.line("SEL", 0))
  block:add(fmt.line("REC", t.armed and 1 or 0, rec_input(t), t.monitor and 1 or 0, 0, 0, 0, 0, 0))
  block:add(fmt.line("VU", 2))
  block:add(fmt.line("TRACKHEIGHT", 0, 0, 0, 0, 0, 0, 0))
  block:add(fmt.line("INQ", 0, 0, 0, 0.5, 100, 0, 0, 100))
  block:add(fmt.line("NCHAN", 2))
  block:add(fmt.line("FX", 1))
  block:add(fmt.line("TRACKID", guid))
  block:add(fmt.line("PERF", 0))
  block:add(fmt.line("MIDIOUT", -1))
  block:add(fmt.line("MAINSEND", at.unfoldered[t.id] and 0 or 1, 0))
  for _, r in ipairs(at.receives[t.id] or {}) do
    -- Mode 0 is after the fader, 3 before it (after the plugins).
    block:add(
      fmt.line("AUXRECV", at.index[r.from] - 1, r.pre and 3 or 0, amp(r.level), 0, 0, 0, 0, 0, 0, "-1:U", 0, -1, "")
    ):quoted(13)
  end
  return block
end

--- A point of REAPER's tempo envelope: a tempo, and a signature change.
local record TempoPoint
  beat: number
  bpm: number
  ramp: boolean
  --- The signature packed as num + den * 65536.
  sig: integer
end

--- The tempo and signature changes of the project as points at their
--- beats; a signature change and a tempo change at one beat share a point.
local function tempo_points(map: types.TempoPoints): {TempoPoint}
  local points: {TempoPoint} = {}
  local function at(beat: number): TempoPoint
    for _, p in ipairs(points) do
      if math.abs(p.beat - beat) < 1e-9 then
        return p
      end
    end
    local p: TempoPoint = {beat = beat}
    points[#points + 1] = p
    return p
  end
  for _, t in ipairs(map.tempos) do
    local p = at(t.beat)
    p.bpm, p.ramp = t.bpm, t.ramp
  end
  for _, s in ipairs(map.signatures) do
    local p = at(s.beat)
    p.sig = s.num + s.den * 65536
  end
  table.sort(points, function(a: TempoPoint, b: TempoPoint): boolean return a.beat < b.beat end)
  return points
end

--- REAPER's tempo envelope for a map with more than one point, or nil: a
--- point per tempo change (shape 0 ramps, 1 holds) and per signature
--- change, the signature packed as num + den * 65536.
function M.tempo_envelope(ctx: Ctx): Node
  local map = api.tempo_points()
  if #map.tempos == 1 and #map.signatures == 1 then
    return nil
  end
  local env = fmt.block("TEMPOENVEX")
  env:add(fmt.line("EGUID", ctx.guid()))
  env:add(fmt.line("ACT", 0, -1))
  env:add(fmt.line("VIS", 1, 0, 1))
  env:add(fmt.line("LANEHEIGHT", 0, 0))
  env:add(fmt.line("ARM", 0))
  env:add(fmt.line("DEFSHAPE", 1, -1, -1))
  local ramp = false
  for _, p in ipairs(tempo_points(map)) do
    -- A signature change inside a ramp keeps the ramp going through it.
    if p.bpm == nil then
      p.bpm, p.ramp = api.tempo_at(p.beat), ramp
    end
    ramp = p.ramp
    local t = string.format("%.12f", api.tempo_seconds(p.beat))
    if p.sig then
      env:add(fmt.line("PT", t, p.bpm, p.ramp and 0 or 1, p.sig, 0, 1))
    else
      env:add(fmt.line("PT", t, p.bpm, p.ramp and 0 or 1))
    end
  end
  return env
end

--- The lines of the project's settings before the master part, as
--- REAPER 7 writes them.
local function project_head(root: Node, p: types.Project, tr: types.Transport, ctx: Ctx)
  local function line(...: fmt.Token): Node
    return root:add(fmt.line(...))
  end
  line("RIPPLE", 0, 0)
  line("GROUPOVERRIDE", 0, 0, 0, 0)
  line("AUTOXFADE", 129)
  line("ENVATTACH", 3)
  line("POOLEDENVATTACH", 0)
  line("PANLAW", 1)
  line("PROJOFFS", 0, 0, 0)
  line("MAXPROJLEN", 0, 0)
  line("GRID", 3199, 8, 1, 8, 1, 0, 0, 0)
  line("TIMEMODE", 1, 5, -1, 30, 0, 0, -1, 0)
  line("PANMODE", 3)
  line("CURSOR", 0)
  line("ZOOM", 100, 0, 0)
  local looped = tr.loop_end and tr.loop_start and tr.loop_end > tr.loop_start
  line("LOOP", (tr.loop_enabled and looped) and 1 or 0)
  line("LOOPGRAN", 0, 4)
  line("RECORD_PATH", "Media", ""):quoted(1)
  line("TIMELOCKMODE", 1)
  line("TEMPOENVLOCKMODE", 1)
  line("ITEMMIX", 1)
  line("DEFPITCHMODE", 589824, 0)
  line("TAKELANE", 1)
  line("SAMPLERATE", 44100, 0, 0)
  line("LOCK", 1)
  line("GLOBAL_AUTO", -1)
  line("TEMPO", p.tempo, p.sig_num, p.sig_den, 0)
  line("PLAYRATE", 1, 0, 0.25, 4)
  local a, b = 0.0, 0.0
  if looped then
    a, b = ctx.sec(tr.loop_start), ctx.sec(tr.loop_end)
  end
  line("SELECTION", a, b)
  line("SELECTION2", a, b)
end

--- The master part: its settings, plugins and envelopes.
local function master_part(root: Node, ctx: Ctx)
  local function line(...: fmt.Token): Node
    return root:add(fmt.line(...))
  end
  line("MASTERAUTOMODE", 0)
  line("MASTERTRACKHEIGHT", 0, 0)
  line("MASTERPEAKCOL", 16576)
  local master = api.part_get(0)
  line("MASTERMUTESOLO", master.mute and 1 or 0)
  line("MASTERHWOUT", 0, 0, 1, 0, 0, 0, 0, -1)
  line("MASTER_NCH", 2, 2)
  line("MASTER_VOLUME", amp(master.volume or 0), master.pan or 0, -1, -1, 1)
  line("MASTER_PANMODE", 3)
  line("MASTER_FX", 1)
  line("MASTER_SEL", 0)
  local master_chain = fx_chain("MASTERFXLIST", 0, master, ctx, "Master")
  if master_chain then
    root:add(master_chain)
  end
  for _, lane in ipairs(api.lane_list(0)) do
    if lane.target == "volume" or lane.target == "pan" then
      root:add(
        envelope(lane.target == "volume" and "MASTERVOLENV2" or "MASTERPANENV2", lane, ctx, "Master " .. lane.target)
      )
    end
  end
end

--- A region as older versions of this extension kept them
--- (`project.meta.regions`), in beats.
local record OldRegion
  start: number
  length: number
  name: string
  color: string
end

--- Markers and regions (paw.markers: `project.meta.markers`, a region
--- with a length), in beats; `project.meta.regions` as older versions of
--- this extension kept them; and the song sections, as regions each up to
--- where the next starts.
local function markers(root: Node, p: types.Project, ctx: Ctx)
  local function line(...: fmt.Token): Node
    return root:add(fmt.line(...))
  end
  local meta = p.meta or {}
  local n = 0
  local function colour(c: string): integer
    return M.native_colour(c) or 0
  end
  for _, m in ipairs(interop.markers()) do
    n = n + 1
    if m.length then
      line("MARKER", n, ctx.sec(m.beat or 0), m.name or "", 1, colour(m.color), 1, "R", ctx.guid(), 0):quoted(3)
      line("MARKER", n, ctx.sec((m.beat or 0) + m.length), "", 1):quoted(3)
    else
      line("MARKER", n, ctx.sec(m.beat or 0), m.name or "", 0, colour(m.color), 1, "B", ctx.guid(), 0):quoted(3)
    end
  end
  local regions = type(meta.regions) == "table" and meta.regions as {OldRegion} or {}
  for _, r in ipairs(regions) do
    n = n + 1
    line("MARKER", n, ctx.sec(r.start or 0), r.name or "", 1, colour(r.color), 1, "R", ctx.guid(), 0):quoted(3)
    line("MARKER", n, ctx.sec((r.start or 0) + (r.length or 0)), "", 1):quoted(3)
  end
  local parts = interop.sections()
  for _, s in ipairs(parts) do
    n = n + 1
    line("MARKER", n, ctx.sec(s.start), s.name, 1, 0, 1, "B", ctx.guid(), 0):quoted(3)
    line("MARKER", n, ctx.sec(s.finish), "", 1):quoted(3)
  end
  if #parts > 0 then
    ctx.report:count("Sections written as regions (they come back as regions)", "sections", #parts)
  end
end

--- Where the parts go: folders, and the outputs and sends as receives.
local function part_layout(list: {types.Part}, ctx: Ctx): Layout
  local depth, unfoldered, index = layout(list)
  local at: Layout = {depth = depth, unfoldered = unfoldered, index = index, receives = {}}
  local receives = at.receives
  for _, t in ipairs(list) do
    if unfoldered[t.id] then
      receives[t.output] = receives[t.output] or {}
      table.insert(receives[t.output], {from = t.id, level = 0})
      ctx.report:add(
        "Routing written as a send (REAPER folders need the child right after its parent)",
        t.name .. " -> " .. api.part_get(t.output).name
      )
    end
    for _, s in ipairs(t.sends or {}) do
      receives[s.target] = receives[s.target] or {}
      table.insert(receives[s.target], {from = t.id, level = s.level, pre = s.pre})
    end
  end
  return at
end

--- The parts: each with its envelopes, plugins and items.
local function parts(root: Node, ctx: Ctx)
  local list: {types.Part} = {}
  for i, id in ipairs(api.part_list()) do
    list[i] = api.part_get(id)
  end
  local at = part_layout(list, ctx)
  for i, t in ipairs(list) do
    local block = root:add(part_block(t, i, ctx, at))
    for _, lane in ipairs(api.lane_list(t.id)) do
      if lane.target == "volume" or lane.target == "pan" then
        block:add(envelope(lane.target == "volume" and "VOLENV2" or "PANENV2", lane, ctx, t.name .. " " .. lane.target))
      end
    end
    local chain = fx_chain("FXCHAIN", t.id, t, ctx, t.name)
    if chain then
      block:add(chain)
    end
    for _, clip in ipairs(api.clip_list(t.id)) do
      local label = t.name .. ": " .. (clip.name or "clip")
      if clip.kind == "audio" then
        block:add(audio_item(clip, ctx, label))
      else
        block:add(midi_item(clip, ctx, label))
      end
    end
    local cues = #api.cue_list(t.id)
    if cues > 0 then
      ctx.report:count("Clips off the timeline (the clip launcher's slots)", t.name, cues)
    end
  end
end

--- Build the document for the current project. `opts.dir` is the folder
--- the file will be in (media under it are written relative to it).
function M.doc(opts?: interop.Options): Node, Report
  opts = opts or {}
  local p = api.project_get()
  local tr = api.transport_get()
  local ctx: Ctx = {
    sec = api.tempo_seconds,
    dir = opts.dir,
    iid = 0,
    guid = guid_maker(opts.seed or (os.time() + math.floor(api.now()))),
    report = reports.new("Not written to " .. (opts.name or "the REAPER project") .. ":"),
  }
  local doc = fmt.document("\r\n")
  local root = doc:add(fmt.block("REAPER_PROJECT", 0.1, "7.0/paw-rpp", opts.timestamp or os.time(), 0)):quoted(2)
  project_head(root, p, tr, ctx)
  master_part(root, ctx)
  markers(root, p, ctx)
  local tempo_env = M.tempo_envelope(ctx)
  if tempo_env then
    root:add(tempo_env)
  end
  root:add(fmt.block("PROJBAY"))
  parts(root, ctx)
  return doc, ctx.report
end

--- Write the current project to a file.
function M.file(path: string, opts?: interop.Options): interop.Result
  opts = opts or {}
  opts.dir = opts.dir or (path:match("^(.*)/[^/]*$") or ".")
  opts.name = path:match("([^/]+)$") or path
  if opts.dir:sub(1, 1) ~= "/" then
    local pwd = os.getenv("PWD")
    if pwd then
      opts.dir = pwd .. (opts.dir == "." and "" or "/" .. opts.dir)
    end
  end
  local doc, report = M.doc(opts)
  fmt.save(doc, path)
  return {report = report, doc = doc}
end

return M
