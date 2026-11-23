-- What the arrange view (paw/views/arrange.tl) draws of one track: its
-- header (the name, the chips, the meter, the route, the sends and the
-- input), and the props of its clips with what is drawn in their bodies
-- (a small piano roll, a waveform, the notes of a subproject's block).
-- Nothing here knows where the view scrolls: the view places what this
-- module draws.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local kernel = require("paw.events.kernel")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type DrawModule = require("paw.draw")
local type roles = require("paw.roles.arrange")
local type Buf = contracts.Buf
local type Track = types.Track
local type Clip = types.Clip
local type Hue = DrawModule.Hue

local draw = paw.draw
local util = paw.util

--- The chip columns of a header, by the flag each switches (`mute`,
--- `solo`, `armed`, `monitor`), in the view's columns.
local type Flags = {string: integer}

local record M
  type Flags = Flags
  header: function(
    buf: Buf,
    y: integer,
    height: integer,
    t: Track,
    index: integer,
    selected: boolean,
    lanes: {types.Lane},
    hue: Hue,
    column_width: integer
  ): Flags
  level_glyph: function(level: number): string
  clip_props: function(
    clip: Clip,
    track: Track,
    hue: Hue,
    kind: string,
    zoom: number,
    chosen?: boolean,
    from?: number,
    to?: number,
    colour?: string
  ): roles.ClipProps
end

-- What is kept between frames -------------------------------------------------------

-- Small piano rolls and waveforms drawn inside clips, and what a header says
-- about its track's devices. A waveform is kept until the project changes.
-- A piano roll is kept by what it is drawn from (the stamp of the clip's
-- notes, its length and its loop), and a header by its track's devices: an
-- edit elsewhere (a track deleted and put back, a fader) draws them again
-- from what is kept. They are forgotten when there are too many.
local KEEP = 4096

--- A store of values made by a key, emptied when it holds KEEP: `n` is
--- how many it holds.
local record Kept<T>
  values: {string: T}
  n: integer
end

local function kept_store<T>(): Kept<T>
  return {values = {}, n = 0}
end

--- What `kept` holds for `key`, or `make()` kept there.
local function keep<T>(kept: Kept<T>, key: string, make: function(): T): T
  local v = kept.values[key]
  if v == nil then
    v = make()
    if kept.n >= KEEP then
      kept.values, kept.n = {}, 0
    end
    kept.values[key], kept.n = v, kept.n + 1
  end
  return v
end

--- What a clip's preview was drawn from, and what it drew: rows of text,
--- and the runs of a waveform's rows.
local record Preview
  width: integer
  rows: integer
  zoom: number
  scale: number | string
  ascii: boolean
  stamp: integer
  length: number
  loop: boolean
  loop_start: number
  loop_length: number
  out: {string}
  runs: {{DrawModule.WaveRun}}
end

local previews: {integer: Preview} = {}
local waves: {string: {types.Peak}} = {}
local rolls: Kept<{string}> = kept_store()
local chains: Kept<string> = kept_store()

paw.on(kernel.changed, function() previews, waves = {}, {} end)
-- A device's name can change without a change to the track's list of devices.
local function forget_chains()
  chains = kept_store()
end
paw.on(kernel.device_changed, forget_chains)
paw.on(kernel.device_ready, forget_chains)
paw.on(kernel.project_loaded, forget_chains)

-- The header ----------------------------------------------------------------------

--- What a track's sound goes through, in a few words: `synth › delay`.
local function chain(t: Track): string
  local key = t.id .. ":" .. table.concat(t.devices or {}, ",") .. (paw.opt.ascii and "a" or "")
  -- A row draws its chain each frame: the closure only when it is not kept.
  local kept = chains.values[key]
  if kept ~= nil then
    return kept
  end
  return keep(
    chains,
    key,
    function(): string
      local names: {string} = {}
      for _, id in ipairs(t.devices or {}) do
        local ok, device = pcall(api.device_get, id)
        if ok then
          names[#names + 1] = device.name
        end
      end
      return table.concat(names, " " .. draw.g.chain .. " ")
    end
  )
end

--- What a track sends, in a few words: `↗ Reverb -9  ↗ Delay -12`.
local function sends_text(t: Track): string
  local out: {string} = {}
  for _, send in ipairs(t.sends or {}) do
    local ok, to = pcall(api.track_get, send.target)
    if ok then
      out[#out + 1] = draw.g.send
        .. " "
        .. to.name
        .. " "
        .. string.format("%g", math.floor(send.level * 10 + 0.5) / 10)
    end
  end
  return table.concat(out, "  ")
end

--- A chip of a header: its letter, whether it is on, its style when on,
--- and the flag it switches.
local record Chip
  letter: string
  on: boolean
  style: string
  flag: string
end

--- The chips of a header, in order: mute, solo, arm, monitor.
local function chips(t: Track): {Chip}
  return {
    {letter = "M", on = t.mute, style = "Mute", flag = "mute"},
    {letter = "S", on = t.solo, style = "Solo", flag = "solo"},
    {letter = "R", on = t.armed, style = "Armed", flag = "armed"},
    {letter = "I", on = t.monitor, style = "Monitor", flag = "monitor"},
  }
end

--- The colours a window lights each chip in.
local chip_tones: {string: string} = {mute = "mute", solo = "solo", armed = "rec", monitor = "select"}

--- The letter of each automation mode before the chips.
local mode_letters: {string: string} = {read = "A", touch = "T", latch = "L", write = "W", off = "-"}

--- Where a fader of the volume stands, from 0 at -60 dB to 1 at +6 dB.
local function fader_at(volume: number): number
  return util.clamp(((volume or 0) + 60) / 66, 0, 1)
end

--- Words on a header in `style`, which a window writes in its font for
--- words, in the colour `tone` (a name of the palette).
local function words(buf: Buf, x: integer, y: integer, text: string, style: string, tone: string)
  local props: contracts.LabelMark = {text = text, style = style, font = "sans", tone = tone}
  buf:mark("label", x, y, math.max(1, api.str_width(text)), 1, props)
end

--- One character for a level, 0 to 1 linear, from -60 dB up: a dot for silence.
function M.level_glyph(level: number): string
  if level <= 0.001 then
    return draw.g.dot
  end
  local db = 20 * math.log10(level)
  return draw.g.eighths[math.floor(util.clamp(math.floor((db + 60) / 60 * 8) + 1, 1, 8))]
end

--- Where the parts of one header go: its width, whether it is narrow, the
--- column its lines under the name start at, the name's and the column
--- before the name, for what modules mark there. `right` is the last
--- column, and `before` the first column left of what is drawn on the
--- right of the name's row so far.
local record Place
  w: integer
  narrow: boolean
  body_at: integer
  name_at: integer
  mark_at: integer
  right: integer
  before: integer
end

--- The chips on the right of the first row: M S R I with room, MSRI in
--- less, only those that are on in less still. Each a switch, which a
--- window paints as a button. Gives the columns of the chips, by their
--- flag, in the view's columns (none when narrow).
local function draw_chips(buf: Buf, y: integer, t: Track, at: Place, column_width: integer): Flags
  local list = chips(t)
  if at.narrow then
    local lit: {Chip} = {}
    for _, chip in ipairs(list) do
      if chip.on then
        lit[#lit + 1] = chip
      end
    end
    list = lit
  end
  local gap = at.w >= 24 and 1 or 0
  local chips_w = #list > 0 and #list + gap * (#list - 1) or 0
  local chips_at = at.right - chips_w
  local flags: Flags = {}
  for i, chip in ipairs(list) do
    local x = chips_at + (i - 1) * (1 + gap)
    local props: contracts.SwitchMark = {
      letter = chip.letter,
      on = chip.on or false,
      style = chip.style,
      tone = chip_tones[chip.flag],
      icon = chip.flag == "monitor" and "speaker" or nil,
      label = chip.flag,
    }
    buf:mark("switch", x, y, 1, 1, props)
    if not at.narrow then
      flags[chip.flag] = x + column_width
    end
  end
  at.before = chips_w > 0 and chips_at - 1 or at.right
  return flags
end

--- In front of the chips: an `A` when the track has automation, and the
--- letter of its automation mode when that is not the usual one (Touch,
--- Latch, Write, or `-` for off); an `F` on a frozen track, an `f` on one
--- held inside a frozen group; with one row, the volume.
local function draw_states(buf: Buf, y: integer, height: integer, t: Track, lanes: {types.Lane}, at: Place)
  local mode = t.automation or "read"
  if #lanes > 0 or mode ~= "read" then
    local on = false
    for _, lane in ipairs(lanes) do
      on = on or lane.enabled and lane.point_count > 0
    end
    local writes = mode == "touch" or mode == "latch" or mode == "write"
    local style = writes and "Armed" or (on and mode ~= "off") and "Automation" or "TrackIndex"
    buf:text(at.before - 1, y, mode_letters[mode as string] or "A", style)
    at.before = at.before - 2
  end
  local frozen = not t.master and paw.freeze and paw.freeze.state(t.id) as string
  if frozen then
    buf:text(at.before - 1, y, frozen == "frozen" and "F" or "f", "TrackInfo")
    at.before = at.before - 2
  end
  if height == 1 and not at.narrow then
    local vol = draw.db_text(t.volume)
    if at.before - #vol - 1 > at.name_at + 4 then
      buf:text(at.before - #vol, y, vol, "TrackInfo")
      at.before = at.before - #vol - 1
    end
  end
end

--- The name a header shows. A folded group says how many tracks it holds.
--- The track column's `fold` shows the groups as a tree; without it, a
--- member stands a step in under its group, and a group has a mark that
--- says whether it is open.
local function name_text(t: Track): string
  local name = t.name
  if t.master then
    return name
  end
  local g, groups = draw.g, paw.groups
  -- The first row of a fold of tracks stands for all of it, by its name.
  local fold = paw.folds.row(t.id)
  if fold then
    name = paw.folds.name(fold) .. " +" .. paw.folds.count(fold)
  elseif groups.is_group(t.id) and groups.folded(t.id) then
    name = name .. " +" .. #groups.members(t.id)
  end
  if not paw.trackcolumn.shows("fold") then
    name = string.rep(" ", groups.depth(t.id)) .. name
    if fold then
      name = g.closed .. " " .. name
    elseif groups.is_group(t.id) then
      name = (groups.folded(t.id) and g.closed or g.open) .. " " .. name
    end
  end
  return name
end

--- The second row: the meter with the fader's place, which a window moves
--- with the live values, the volume on it, the clip light at its end
--- (both sides on the master's), and the input's button, which a click
--- chooses from: lit when the track has one.
local function draw_meter_row(buf: Buf, y: integer, t: Track, selected: boolean, at: Place)
  local left, right, hold, clipped = draw.track_peak(t.id)
  local vol = draw.db_text(t.volume)
  local vol_at = at.right - #vol
  if vol_at - 1 > at.body_at then
    local meter: roles.HmeterProps = {
      levels = {left, right},
      hold = hold,
      clipped = clipped,
      stereo = t.master or nil,
      at = fader_at(t.volume),
      bind = "meter:" .. t.id,
    }
    buf:mark("hmeter", at.body_at, y + 1, vol_at - 1 - at.body_at, 1, meter)
  end
  buf:text(vol_at, y + 1, vol, selected and "Bright" or "TrackInfo")
  if not at.narrow and not t.master then
    local input: contracts.ButtonMark = {
      text = "in",
      icon = "mic",
      on = t.input ~= nil,
      on_style = "Input",
      style = "TrackIndex",
      quiet = true,
      label = "input",
    }
    buf:mark("button", 1, y + 1, 2, 1, input)
  end
end

--- A row under the meter: the pan as a knob (a window turns it), the
--- devices the sound goes through, and the track it goes out to.
local function draw_route(buf: Buf, row: integer, t: Track, at: Place)
  local g, right = draw.g, at.right
  local x = at.body_at
  local pan = draw.pan_text(t.pan or 0)
  if not (at.narrow and pan == "C") then
    local knob: contracts.KnobMark = {
      value = t.pan or 0,
      text = pan,
      style = pan == "C" and "TrackIndex" or "TrackInfo",
      round = true,
      label = "pan",
    }
    buf:mark("knob", x, row, math.max(3, #pan), 1, knob)
    x = x + (at.narrow and #pan + 1 or math.max(4, #pan + 1))
  end
  local out = ""
  if t.output and t.output ~= 0 then
    local ok, to = pcall(api.track_get, t.output)
    if ok then
      out = g.out .. " " .. to.name
    end
  end
  local devices = chain(t)
  local room_left = right - x
  if out ~= "" then
    local out_w = api.str_width(out)
    if out_w > room_left - 2 then
      out = util.fit(out, math.max(1, room_left - 2))
      out_w = api.str_width(out)
    end
    words(buf, right - out_w, row, out, "TrackInfo", "text_3")
    room_left = room_left - out_w - 1
  end
  if devices ~= "" and room_left > 2 then
    if api.str_width(devices) > room_left then
      devices = util.fit(devices, room_left)
    end
    words(buf, x, row, devices, "TrackRoute", "text_2")
  end
end

--- A row of what the track takes in, with the level arriving there
--- whether or not it is heard, so that a guitar can be seen before
--- anything is armed.
local function draw_input(buf: Buf, row: integer, t: Track, at: Place)
  local label = paw.audio.label(t) as string
  if not label then
    return
  end
  local x = at.body_at
  local heard = t.input and (t.monitor or t.armed)
  if t.input then
    local level = paw.audio.level(t) as number
    buf:text(x, row, M.level_glyph(level), level > 0.001 and "Input" or "TrackIndex")
    x = x + 2
  end
  label = util.fit(label, math.max(1, at.right - x))
  words(buf, x, row, label, heard and "Input" or "TrackInfo", heard and "select" or "text_3")
end

--- The rows under the meter, in order, as many as the header has room
--- for: route, sends, input.
local function draw_lines(buf: Buf, y: integer, height: integer, t: Track, at: Place)
  local lines: {string} = {}
  if height >= 3 then
    lines[#lines + 1] = "route"
    if #(t.sends or {}) > 0 then
      lines[#lines + 1] = "sends"
    end
    if not t.master and (t.input or paw.audio.label(t) as string) and height >= 4 then
      lines[#lines + 1] = "input"
    end
  end
  for i, kind in ipairs(lines) do
    local row = y + 1 + i
    if row >= y + height then
      break
    end
    if kind == "route" then
      draw_route(buf, row, t, at)
    elseif kind == "sends" then
      local text = sends_text(t)
      local width = at.right - at.body_at
      if api.str_width(text) > width then
        text = util.fit(text, width)
      end
      words(buf, at.body_at, row, text, "TrackInfo", "text_3")
    else
      draw_input(buf, row, t, at)
    end
  end
end

--- A track's header from line `y`, `height` lines: its ground with a
--- stripe in the track's colour, the chips, the name, the meter and the
--- lines under it. `column_width` is the track column's left of `buf`.
--- Gives the chips' columns, for the pointer: nil for the master's, which
--- has none, so the tracks' stay where they are.
function M.header(
  buf: Buf,
  y: integer,
  height: integer,
  t: Track,
  index: integer,
  selected: boolean,
  lanes: {types.Lane},
  hue: Hue,
  column_width: integer
): Flags
  local g = draw.g
  local w = buf.width
  local trackhead: roles.TrackheadProps = {
    style = selected and "TrackHeaderSel" or "TrackHeader",
    stripe = selected and g.stripe_sel or g.stripe,
    stripe_style = hue.fg,
    color = draw.track_colour(t, index),
    selected = selected or nil,
  }
  buf:mark("trackhead", 0, y, w, height, trackhead)
  local narrow = w < 16
  -- The track's number is in the track column (paw/trackcolumn.tl), at
  -- the left of the header; the lines under the name start further in.
  -- A kind of track's letter stands clear of the stripe and of the name.
  local at: Place = {w = w, narrow = narrow, body_at = narrow and 2 or 4, name_at = 2, mark_at = 1, right = w - 1}
  if not narrow and not t.master and paw.track_kinds.spec(t.id) then
    at.mark_at, at.name_at = 2, 4
  end
  local flags: Flags
  if t.master then
    at.before = at.right
  else
    flags = draw_chips(buf, y, t, at, column_width)
  end
  draw_states(buf, y, height, t, lanes, at)
  local room = math.max(1, at.before - at.name_at)
  local name = name_text(t)
  if api.str_width(name) > room then
    name = util.fit(name, room)
  end
  -- In words, in a window.
  local label: contracts.LabelMark = {
    text = name,
    style = selected and "TrackNameSel" or "TrackName",
    font = "title",
    tone = "text",
  }
  buf:mark("label", at.name_at, y, room, 1, label)
  -- What modules mark on the header (`paw.ui.layer("arrange", "header", ...)`):
  -- `x` is the free column before the name.
  paw.ui.paint("arrange", "header", {buf = buf, x = at.mark_at, y = y, width = w, height = height, track = t.id})
  if height >= 2 then
    draw_meter_row(buf, y, t, selected, at)
  end
  draw_lines(buf, y, height, t, at)
  return flags
end

-- The clips -----------------------------------------------------------------------

--- An audio clip's waveform as `n` { min, max, rms } across it, kept: for
--- `paw.plot.wave` and its twin in cells. Nothing for a missing file.
local function wave_peaks(clip: Clip, n: integer): {types.Peak}
  local key = clip.id .. ":" .. n
  if not waves[key] then
    local ok, peaks = pcall(api.clip_peaks, clip.id, n)
    waves[key] = ok and peaks or {}
  end
  return waves[key]
end

--- Whether a clip's kept preview was drawn from what it would be drawn
--- from now.
local function still_fits(kept: Preview, clip: Clip, width: integer, rows: integer, zoom: number): boolean
  if not (kept.width == width and kept.rows == rows and kept.zoom == zoom) then
    return false
  end
  if not (kept.scale == paw.opt.wave_scale and kept.ascii == paw.opt.ascii) then
    return false
  end
  -- A waveform does not depend on the notes.
  if clip.kind ~= "midi" then
    return true
  end
  return kept.stamp == clip.stamp
    and kept.length == clip.length
    and kept.loop == clip.loop
    and kept.loop_start == clip.loop_start
    and kept.loop_length == clip.loop_length
end

--- The rows under a clip's name: its notes as a small piano roll, or its
--- waveform.
local function preview(clip: Clip, width: integer, rows: integer, zoom: number): {string}, {{DrawModule.WaveRun}}
  -- Kept by the clip, then compared field by field: a string key made on
  -- each frame for each clip cost more than the look-up saved.
  local scale, ascii = paw.opt.wave_scale, paw.opt.ascii
  local kept = previews[clip.id]
  if kept and still_fits(kept, clip, width, rows, zoom) then
    return kept.out, kept.runs
  end
  local key = clip.id .. ":" .. width .. ":" .. rows .. ":" .. zoom .. ":" .. tostring(scale) .. (ascii and "a" or "")
  local out: {string}
  local runs: {{DrawModule.WaveRun}}
  if clip.kind == "midi" then
    local roll = string.format(
      "%s:%s:%.17g:%s:%.17g:%s",
      key,
      tostring(clip.stamp),
      clip.length,
      tostring(clip.loop),
      clip.loop_start or 0,
      tostring(clip.loop_length)
    )
    out = rolls.values[roll]
    if out == nil then
      out = keep(
        rolls,
        roll,
        function(): {string}
          local notes = paw.stretch.sounding(clip, api.clip_notes(clip.id)) as {types.Note}
          return draw.miniroll(notes, width, rows, zoom)
        end
      )
    end
  else
    -- A file that has gone missing has been reported already; draw nothing.
    local ok, peaks = pcall(api.clip_peaks, clip.id, width)
    out, runs = draw.waveform(ok and peaks or {}, rows)
  end
  previews[clip.id] = {
    width = width,
    rows = rows,
    zoom = zoom,
    scale = scale,
    ascii = ascii,
    stamp = clip.stamp,
    length = clip.length,
    loop = clip.loop,
    loop_start = clip.loop_start,
    loop_length = clip.loop_length,
    out = out,
    runs = runs,
  }
  return out, runs
end

--- Style names for the runs of a waveform that `draw.waveform` marks.
local wave_style: {string: string} = {flip = "ClipWaveFlip", clip = "ClipWaveClip", clipflip = "ClipWaveClipFlip"}

--- What each clip's props (`clip_props`) draw in its body: the clip, its
--- track's colour, its kind and the zoom. Kept beside the props, not in
--- them, as they are not data for a frontend; and not in a closure made for
--- each clip on each frame, which LuaJIT does not compile.
local record Body
  clip: Clip
  colour: string
  kind: string
  zoom: number
end
local bodies: {roles.ClipProps: Body} = setmetatable({}, {__mode = "k"})

--- An audio clip's waveform: in pixels under the cells where the terminal
--- shows them, the whole clip's, so that scrolling moves pieces already
--- made; else in cells.
local function audio_body(box: Buf, of: Body)
  local clip = of.clip
  local cw, height = box.width, box.height
  local body = box:sub(0, 1, cw, height - 1)
  local function peaks(n: integer): {types.Peak}
    return wave_peaks(clip, n)
  end
  -- The colour the cells draw it in (`paw.draw.hue`'s body).
  local colour = draw.mix(require("paw.theme").palette.bg, of.colour, of.kind == "_off" and 0.30 or 0.75)
  local pictured = body:strip(
    0,
    0,
    cw,
    height - 1,
    {
      key = "arrange:wave:" .. clip.id,
      under = true,
      draw = function(g: contracts.Painter, px: contracts.StripPixels)
        paw.plot.wave(g, px, {peaks = peaks, color = colour})
      end,
    }
  )
  if not pictured then
    paw.plot.wave_cells(body, {peaks = peaks})
  end
end

--- A block of a subproject: what it plays, as a small piano roll of the
--- notes of its subproject's tracks.
local function nest_body(box: Buf, of: Body)
  local cw, height = box.width, box.height
  local key = paw.nest.content_key(of.clip) .. ":" .. cw .. ":" .. (height - 1) .. ":" .. of.zoom
  local rows = rolls.values[key]
  if rows == nil then
    rows = keep(
      rolls, key, function(): {string} return draw.miniroll(paw.nest.notes(of.clip), cw, height - 1, of.zoom) end
    )
  end
  for row, text in ipairs(rows) do
    box:text(0, row, text)
  end
end

--- What is drawn in a clip's body (the `clip` role's `body(buf, props)`):
--- its waveform, or its notes as a small piano roll.
local function clip_body(box: Buf, p: roles.ClipProps)
  local of = bodies[p]
  if not of then
    return
  end
  local clip = of.clip
  if clip.kind == "audio" then
    audio_body(box, of)
  elseif clip.kind == "nest" then
    nest_body(box, of)
  elseif clip.note_count > 0 then
    local rows, runs = preview(clip, box.width, box.height - 1, of.zoom)
    for row, text in ipairs(rows) do
      if runs then
        for _, run in ipairs(runs[row]) do
          box:text(run.column, row, run.text, wave_style[run.mark])
        end
      else
        box:text(0, row, text)
      end
    end
  end
end

--- The styles of a clip's title and body by its kind ("", "_cur", "_off").
local title_of: {string: string} = {[""] = "title", _cur = "title_cur", _off = "title_off"}
local body_of: {string: string} = {[""] = "body", _cur = "body_cur", _off = "body_off"}

--- Where the window's scope (`paw.scope`) cuts a clip that crosses one of
--- its edges, in beats from the clip's start: `cut_in` at its start,
--- `cut_out` at its end, each nil where it does not cut. Only the drawing
--- is cut: an edit of the clip is an edit of all of it.
local function cuts(clip: Clip, from: number, to: number): number, number
  if not from then
    return nil, nil
  end
  local finish = clip.start + clip.length
  local EPS = 1e-9
  local cut_in = (clip.start < from - EPS and finish > from + EPS) and from - clip.start or nil
  local cut_out = (clip.start < to - EPS and finish > to + EPS) and to - clip.start or nil
  return cut_in, cut_out
end

--- What a clip's title says: its name, and marks of what is done to it.
local function clip_label(clip: Clip): string
  local label = clip.offline and ("offline · " .. clip.name) or clip.name
  -- A muted clip: `⊘ riff`, beside its faint body, so it reads as off at a glance.
  if clip.muted then
    label = draw.g.muted .. label
  end
  -- A linked clip: `riff ≡`; with overrides, `riff ≡ +3 v-10`.
  if clip.link then
    label = label .. " " .. draw.g.link
  end
  if (clip.transpose or 0) ~= 0 then
    label = label .. string.format(" %+d", clip.transpose)
  end
  if (clip.velocity or 0) ~= 0 then
    label = label .. string.format(" v%+d", clip.velocity)
  end
  -- A block of a subproject: its name after `⧉`, in a frame; the letter
  -- of its kind after `⧉` for a kind of subproject (`⧉D Groove`).
  if clip.kind == "nest" then
    local letter = paw.nest.letter(clip.nest)
    label = (letter and (draw.g.nest:gsub("%s+$", "") .. letter .. " ") or draw.g.nest) .. label
  end
  -- Stretched, shifted, looped: `×1.5 ↻ drums`.
  local mark = paw.stretch.badge(clip) as string
  if mark then
    label = mark .. " " .. label
  end
  return label
end

--- A clip on the timeline's plane, as the `clip` role it is. `kind` is
--- "" or "_cur" (the cursor's) or "_off" (muted). `from`, `to`: the time
--- of the window's scope, which cuts it (`cut_in`, `cut_out`). `colour` is
--- its track's (`paw.draw.track_colour`), when the caller has it.
function M.clip_props(
  clip: Clip,
  track: Track,
  hue: Hue,
  kind: string,
  zoom: number,
  chosen?: boolean,
  from?: number,
  to?: number,
  colour?: string
): roles.ClipProps
  colour = colour or draw.track_colour(track)
  local cut_in, cut_out = cuts(clip, from, to)
  local block = clip.kind == "nest"
  local warps: {number}
  for i, m in ipairs(clip.warp or {}) do
    warps = warps or {}
    warps[i] = m.beat - clip.start
  end
  local hues = hue as {string: string}
  local props: roles.ClipProps = {
    key = "clip:" .. clip.id,
    name = clip.name,
    label = clip_label(clip),
    -- A clip with takes says which plays: `take 3 ‹2/4›` (the role puts
    -- the mark first where the label does not fit).
    mark = paw.takes.badge(clip),
    per = zoom,
    repeats = clip.loop and paw.stretch.repeats(clip) as {number} or nil,
    warps = warps,
    cut_in = cut_in,
    cut_out = cut_out,
    title_style = hues[title_of[kind]],
    body_style = hues[body_of[kind]],
    body = clip_body,
    nest = block or nil,
  }
  bodies[props] = {clip = clip, colour = colour, kind = kind, zoom = zoom}
  -- What only a frontend that gets scenes reads: the terminal draws the
  -- same cells without it.
  if paw.ui.scene_drawing then
    props.id = clip.id
    props.color = colour
    props.midi = clip.kind ~= "audio"
    props.muted = clip.muted or nil
    props.current = kind == "_cur" or nil
    props.chosen = chosen or nil
    props.offline = clip.offline or nil
    props.length = clip.length
    props.repeats = props.repeats or {}
    props.warps = warps or {}
    props.fade_in = clip.fade_in
    props.fade_out = clip.fade_out
    props.gain = clip.gain
    props.content = paw.frontend.content_key(clip)
  end
  return props
end

return M
