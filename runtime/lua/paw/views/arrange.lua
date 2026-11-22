-- The arrange view: track headers on the left, clips on a timeline on the right.
local api = paw.api
local util = paw.util

local view = {
  scroll = 0, -- beat at the left edge of the timeline
  top = 1, -- index of the first track shown
  flags = {}, -- header columns of the M, S, R and I chips, for the mouse
  -- What extensions draw on the timeline, by name, in name order, once the
  -- ruler and the tracks are drawn and before the playhead:
  --   paw.ui.views.arrange.layers.marks = function(view, layer) ... end
  -- `layer.ruler` is the timeline's part of the ruler row, `layer.ruler2`
  -- its second row when `view.ruler2` asks for one (else nil), and
  -- `layer.lanes` the timeline below, down to the master track;
  -- `layer.x(beat)` is the column of a beat in any of them. Also `scroll`, `zoom`, `span` (beats shown),
  -- `top`, `rows` and `th` (the first track shown, how many, rows per track).
  layers = {},
  -- Tracks need rows: two fifths of a column's height, and a third of the
  -- room where three or more windows share it (paw/ui.tl).
  share = { column = 2 / 5, least = 1 / 3 },
  -- Each window of the arrange view scrolls on its own. The edit cursor
  -- (paw/cursor.tl) is one for all of them.
  window_state = { "scroll", "top", "flags", "seen_index", "seen_fit", "seen_lane", "seen_beat", "geometry", "comp" },
  window_fresh = { "geometry", "flags" },
}
paw.seats.fields(
  "arrange",
  view,
  { "scroll", "top", "flags", "seen_index", "seen_fit", "seen_lane", "seen_beat", "geometry", "comp" },
  { scroll = 0, top = 1, flags = {} }
)

local draw = paw.draw
-- An empty list, to walk where there is none.
local NONE = {}

-- Another project is shown from its start, as the cursor is (paw/cursor.tl).
paw.on("project.loaded", function()
  view.scroll, view.top, view.seen_beat = 0, 1, nil
end)

-- Small piano rolls and waveforms drawn inside clips, and what a header says
-- about its track's devices. A waveform is kept until the project changes.
-- A piano roll is kept by what it is drawn from (the stamp of the clip's
-- notes, its length and its loop), and a header by its track's devices: an
-- edit elsewhere (a track deleted and put back, a fader) draws them again
-- from what is kept. They are forgotten when there are too many.
local previews, waves = {}, {}
local rolls, chains = { n = 0 }, { n = 0 }
local KEEP = 4096

--- What `kept` holds for `key`, or `make()` kept there.
local function keep(kept, key, make)
  local v = kept[key]
  if v == nil then
    v = make()
    if kept.n >= KEEP then
      for k in pairs(kept) do
        kept[k] = nil
      end
      kept.n = 0
    end
    kept[key], kept.n = v, kept.n + 1
  end
  return v
end

paw.on("changed", function()
  previews, waves = {}, {}
end)
-- A device's name can change without a change to the track's list of devices.
for _, event in ipairs({ "device.changed", "device.ready", "project.loaded" }) do
  paw.on(event, function() chains = { n = 0 } end)
end

--- An audio clip's waveform as `n` { min, max, rms } across it, kept: for
--- `paw.plot.wave` and its twin in cells. Nothing for a missing file.
local function wave_peaks(clip, n)
  local key = clip.id .. ":" .. n
  if not waves[key] then
    local ok, peaks = pcall(api.clip_peaks, clip.id, n)
    waves[key] = ok and peaks or {}
  end
  return waves[key]
end

--- The rows under a clip's name: its notes as a small piano roll, or its
--- waveform.
local function preview(clip, width, rows, zoom)
  -- Kept by the clip, then compared field by field: a string key made on
  -- each frame for each clip cost more than the look-up saved.
  local scale, ascii = paw.opt.wave_scale, paw.opt.ascii
  local kept = previews[clip.id]
  if
    kept
    and kept.width == width
    and kept.rows == rows
    and kept.zoom == zoom
    and kept.scale == scale
    and kept.ascii == ascii
    and (
      clip.kind ~= "midi"
      or kept.stamp == clip.stamp
        and kept.length == clip.length
        and kept.loop == clip.loop
        and kept.loop_start == clip.loop_start
        and kept.loop_length == clip.loop_length
    )
  then
    return kept.out, kept.runs
  end
  local key = clip.id .. ":" .. width .. ":" .. rows .. ":" .. zoom .. ":" .. tostring(scale) .. (ascii and "a" or "")
  local out, runs
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
    out = rolls[roll]
    if out == nil then
      out = keep(
        rolls,
        roll,
        function() return draw.miniroll(paw.stretch.sounding(clip, api.clip_notes(clip.id)), width, rows, zoom) end
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
local wave_style = { flip = "ClipWaveFlip", clip = "ClipWaveClip", clipflip = "ClipWaveClipFlip" }

--- What a track's sound goes through, in a few words: `synth › delay`.
local function chain(t)
  local key = t.id .. ":" .. table.concat(t.devices or NONE, ",") .. (paw.opt.ascii and "a" or "")
  -- A row draws its chain each frame: the closure only when it is not kept.
  local kept = chains[key]
  if kept ~= nil then return kept end
  return keep(chains, key, function()
    local names = {}
    for _, id in ipairs(t.devices or {}) do
      local ok, device = pcall(api.device_get, id)
      if ok then names[#names + 1] = device.name end
    end
    return table.concat(names, " " .. draw.g.chain .. " ")
  end)
end

view.meter = draw.meter

--- Columns for the track headers on a screen `w` wide, the rule on their
--- right included: `paw.opt.header_width`, or by the width with "auto".
function view.header_width(w)
  local want = tonumber(paw.opt.header_width)
  if not want then want = w >= 120 and 26 or w >= 100 and 22 or w >= 80 and 18 or 12 end
  return math.max(4, math.min(want, w - 4))
end

--- Rows a track takes when `count` tracks share `room` rows:
--- `paw.opt.track_height`, or with "auto" as many as fit, from 3 to 4.
function view.track_height(count, room)
  local want = tonumber(paw.opt.track_height)
  if want then return math.max(1, math.floor(want)) end
  if count < 1 then return 3 end
  return util.clamp(math.floor(room / count), 3, 4)
end

--- Whether the ruler has a second row: when something registered in
--- `view.ruler2` (by name, a function of the view) has something to show.
--- The lanes of `paw.ruler` (the regions' rows) add rows of their own, and
--- a layer draws on the first of them.
---   paw.ui.views.arrange.ruler2.marks = function(view) return #my_marks > 0 end
view.ruler2 = {}

local function wants_ruler2(self)
  for _, wants in pairs(self.ruler2) do
    local ok, yes = pcall(wants, self)
    if ok and yes then return true end
  end
  return false
end

--- Where everything goes on a `w` by `h` view: the header width, the ruler's
--- rows, and the rows of the timeline, each `{ kind = "track", id, index, y,
--- h }` from the first track shown, then the master's. All placement is
--- here, so that rows of other kinds can be added in one place.
function view:layout(w, h)
  local tracks = paw.groups.rows()
  local hw = view.header_width(w)
  -- The track column (paw/trackcolumn.tl) at the left of the headers takes
  -- its columns from the timeline, as Neovim's number column takes them
  -- from the text: the headers keep their width. `count` is how far the
  -- counts of `j` and `k` go: over lane rows too, in normal mode, when
  -- lanes are open.
  local count = #tracks
  if paw.lanes.any_open() and paw.keymap.mode == "n" then count = #paw.lanes.lines() end
  local column = paw.trackcolumn.layout({ rows = tracks, count = count }, math.max(0, w - hw - 8))
  hw = hw + column.width
  -- The ruler, its second row if something asks for one, a row for each
  -- band of an extension's (`paw.frontend.bands`) that has entries, and
  -- the tempo lane's two rows when it is shown.
  local tempo_rows = paw.tempolane.shown() and 2 or 0
  local bands = paw.frontend.band_state()
  local band_y = 1 + math.max(paw.ruler.lane_rows(), wants_ruler2(self) and 1 or 0)
  local ruler_rows = band_y + bands.rows + tempo_rows
  local master_rows = 2
  local room = math.max(1, h - ruler_rows - master_rows)
  -- Take lanes (a line each) and automation lanes shown as rows (two
  -- lines each) take their lines first.
  local lane_lines, own = 0, false
  for _, id in ipairs(tracks) do
    lane_lines = lane_lines + paw.takes.lane_count(id) + 2 * #paw.lanes.shown(id)
    own = own or (api.track_get(id, "height") or 1) ~= 1
  end
  local th = view.track_height(#tracks, math.max(1, room - lane_lines))
  -- Squeezed by panels below, a track takes what there is rather than vanish.
  if not tonumber(paw.opt.track_height) and room < th then th = math.max(1, room) end
  local fit = math.max(1, math.floor(room / th))
  local cursor_index = paw.cursor.row() or 1
  -- Tracks of heights of their own are placed one by one, as lanes are.
  if lane_lines > 0 or own then
    local rows, y = self:rows_with_lanes(tracks, th, ruler_rows, room, cursor_index)
    return {
      hw = hw,
      tw = w - hw,
      column = column,
      th = th,
      ruler_rows = ruler_rows,
      tempo_rows = tempo_rows,
      rows = rows,
      tracks = tracks,
      used = y,
      master = { kind = "master", id = 0, y = h - master_rows, h = master_rows },
      bands = bands,
      band_y = band_y,
    }
  end
  if cursor_index ~= self.seen_index or fit ~= self.seen_fit then
    if cursor_index < self.top then self.top = cursor_index end
    if cursor_index >= self.top + fit then self.top = cursor_index - fit + 1 end
  end
  self.seen_index, self.seen_fit = cursor_index, fit
  self.top = util.clamp(self.top, 1, math.max(1, #tracks - fit + 1))
  local rows, y = {}, ruler_rows
  for index = self.top, #tracks do
    if y + th > ruler_rows + room then break end
    rows[#rows + 1] = { kind = "track", id = tracks[index], index = index, y = y, h = th }
    y = y + th
  end
  return {
    hw = hw,
    tw = w - hw,
    column = column,
    th = th,
    ruler_rows = ruler_rows,
    tempo_rows = tempo_rows,
    rows = rows,
    tracks = tracks,
    used = y,
    master = { kind = "master", id = 0, y = h - master_rows, h = master_rows },
    bands = bands,
    band_y = band_y,
  }
end

--- The bands of extensions under the ruler (`paw.frontend.bands`), a row
--- each from line `y`: an entry with a length over its stretch, one
--- without a flag where it is, each in its colour with its name.
local function draw_bands(buf, y, state, col)
  local w = buf.width
  for row = 0, state.rows - 1 do
    buf:fill(0, y + row, w, 1, " ", "Ruler")
  end
  for _, e in ipairs(state.entries) do
    local x0 = col(e.beat)
    local span = e.length > 0 and math.max(1, col(e.beat + e.length) - x0) or api.str_width(e.name) + 2
    if x0 < w and x0 + span > 0 then
      local box = buf:sub(x0, y + e.row, span, 1)
      box:fill(0, 0, span, 1, " ", e.color ~= "" and draw.hue(e.color).pill or "RulerBar")
      box:text(0, 0, (e.length > 0 and draw.g.clip_start or "▾") .. e.name)
    end
  end
end

--- The chips of a header, in order: mute, solo, arm, monitor.
local function chips(t)
  return {
    { "M", t.mute, "Mute", "mute" },
    { "S", t.solo, "Solo", "solo" },
    { "R", t.armed, "Armed", "armed" },
    { "I", t.monitor, "Monitor", "monitor" },
  }
end

--- The colours a window lights each chip in.
local chip_tones = { mute = "mute", solo = "solo", armed = "rec", monitor = "select" }

--- Where a fader of the volume stands, from 0 at -60 dB to 1 at +6 dB.
local function fader_at(volume) return util.clamp(((volume or 0) + 60) / 66, 0, 1) end

--- Words on a header in `style`, which a window writes in its font for
--- words, in the colour `tone` (a name of the palette).
local function words(buf, x, y, text, style, tone)
  buf:mark(
    "label",
    x,
    y,
    math.max(1, api.str_width(text)),
    1,
    { text = text, style = style, font = "sans", tone = tone }
  )
end

--- What a track sends, in a few words: `↗ Reverb -9  ↗ Delay -12`.
local function sends_text(t)
  local out = {}
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

local function header(self, buf, y, height, t, index, selected, lanes, hue)
  local g = draw.g
  local w = buf.width
  local style = selected and "TrackHeaderSel" or "TrackHeader"
  -- Its ground, with a stripe in the track's colour down its whole height.
  buf:mark("trackhead", 0, y, w, height, {
    style = style,
    stripe = selected and g.stripe_sel or g.stripe,
    stripe_style = hue.fg,
    color = draw.track_colour(t, index),
    selected = selected or nil,
  })
  local narrow = w < 16
  -- The track's number is in the track column (paw/trackcolumn.tl), at
  -- the left of the header; the lines under the name start further in.
  local body_at = narrow and 2 or 4
  local name_at = 2
  -- The free column before the name, for what modules mark there. A kind
  -- of track's letter stands clear of the stripe and of the name.
  local mark_at = 1
  if not narrow and not t.master and paw.track_kinds.spec(t.id) then
    mark_at, name_at = 2, 4
  end

  -- The chips on the right: M S R I with room, MSRI in less, only those
  -- that are on in less still.
  local right = w - 1
  local list = not t.master and chips(t) or {}
  if narrow then
    local lit = {}
    for _, chip in ipairs(list) do
      if chip[2] then lit[#lit + 1] = chip end
    end
    list = lit
  end
  local gap = w >= 24 and 1 or 0
  local chips_w = #list > 0 and #list + gap * (#list - 1) or 0
  local chips_at = right - chips_w
  -- The master, drawn last, has none: the tracks' stay where they are.
  if not t.master then self.flags = {} end
  if chips_w > 0 then
    -- Each a switch, which a window paints as a button.
    for i, chip in ipairs(list) do
      local x = chips_at + (i - 1) * (1 + gap)
      buf:mark("switch", x, y, 1, 1, {
        letter = chip[1],
        on = chip[2] or false,
        style = chip[3],
        tone = chip_tones[chip[4]],
        icon = chip[4] == "monitor" and "speaker" or nil,
        label = chip[4],
      })
      if not narrow then self.flags[chip[4]] = x + (self.column_width or 0) end
    end
  end
  local before = chips_w > 0 and chips_at - 1 or right
  -- In front of the chips: an `A` when the track has automation, and
  -- the letter of its automation mode when that is not the usual one
  -- (Touch, Latch, Write, or `-` for off).
  local mode = t.automation or "read"
  if #lanes > 0 or mode ~= "read" then
    local on = false
    for _, lane in ipairs(lanes) do
      on = on or lane.enabled and lane.point_count > 0
    end
    local letter = ({ read = "A", touch = "T", latch = "L", write = "W", off = "-" })[mode] or "A"
    local writes = mode == "touch" or mode == "latch" or mode == "write"
    buf:text(before - 1, y, letter, writes and "Armed" or (on and mode ~= "off") and "Automation" or "TrackIndex")
    before = before - 2
  end
  -- An `F` on a frozen track, an `f` on one held inside a frozen group.
  local frozen = not t.master and paw.freeze and paw.freeze.state(t.id)
  if frozen then
    buf:text(before - 1, y, frozen == "frozen" and "F" or "f", "TrackInfo")
    before = before - 2
  end
  -- With one row, the volume goes there too.
  if height == 1 and not narrow then
    local vol = draw.db_text(t.volume)
    if before - #vol - 1 > name_at + 4 then
      buf:text(before - #vol, y, vol, "TrackInfo")
      before = before - #vol - 1
    end
  end
  -- A folded group says how many tracks it holds. The track column's
  -- `fold` shows the groups as a tree; without it, a member stands a step
  -- in under its group, and a group has a mark that says whether it is open.
  local name = t.name
  if not t.master then
    local groups = paw.groups
    if groups.is_group(t.id) and groups.folded(t.id) then name = name .. " +" .. #groups.members(t.id) end
    if not paw.trackcolumn.shows("fold") then
      name = string.rep(" ", groups.depth(t.id)) .. name
      if groups.is_group(t.id) then name = (groups.folded(t.id) and g.closed or g.open) .. " " .. name end
    end
  end
  local room = math.max(1, before - name_at)
  if api.str_width(name) > room then name = util.fit(name, room) end
  -- In words, in a window.
  buf:mark(
    "label",
    name_at,
    y,
    room,
    1,
    { text = name, style = selected and "TrackNameSel" or "TrackName", font = "title", tone = "text" }
  )
  -- What modules mark on the header (`paw.ui.layer("arrange", "header", ...)`):
  -- `x` is the free column before the name.
  paw.ui.paint("arrange", "header", { buf = buf, x = mark_at, y = y, width = w, height = height, track = t.id })

  if height >= 2 then
    local left, r, hold, clipped = draw.track_peak(t.id)
    local vol = draw.db_text(t.volume)
    local vol_at = right - #vol
    if vol_at - 1 > body_at then
      -- A window moves it with the live values, and shows the volume on it
      -- and the clip light at its end. The master's has both sides.
      buf:mark("hmeter", body_at, y + 1, vol_at - 1 - body_at, 1, {
        levels = { left, r },
        hold = hold,
        clipped = clipped,
        stereo = t.master or nil,
        at = fader_at(t.volume),
        bind = "meter:" .. t.id,
      })
    end
    buf:text(vol_at, y + 1, vol, selected and "Bright" or "TrackInfo")
    -- The input, which a click chooses: lit when the track has one.
    if not narrow and not t.master then
      buf:mark("button", 1, y + 1, 2, 1, {
        text = "in",
        icon = "mic",
        on = t.input ~= nil,
        on_style = "Input",
        style = "TrackIndex",
        quiet = true,
        label = "input",
      })
    end
  end

  -- The rows under: pan, devices and output; sends; the input.
  local lines = {}
  if height >= 3 then
    lines[#lines + 1] = "route"
    if #(t.sends or {}) > 0 then lines[#lines + 1] = "sends" end
    if not t.master and (t.input or paw.audio.label(t)) and height >= 4 then lines[#lines + 1] = "input" end
  end
  for i, kind in ipairs(lines) do
    local row = y + 1 + i
    if row >= y + height then break end
    local x = body_at
    local width = right - x
    if kind == "route" then
      local pan = draw.pan_text(t.pan or 0)
      if not (narrow and pan == "C") then
        -- A knob in a window.
        buf:mark("knob", x, row, math.max(3, #pan), 1, {
          value = t.pan or 0,
          text = pan,
          style = pan == "C" and "TrackIndex" or "TrackInfo",
          round = true,
          label = "pan",
        })
        x = x + (narrow and #pan + 1 or math.max(4, #pan + 1))
      end
      local out = ""
      if t.output and t.output ~= 0 then
        local ok, to = pcall(api.track_get, t.output)
        if ok then out = g.out .. " " .. to.name end
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
        if api.str_width(devices) > room_left then devices = util.fit(devices, room_left) end
        words(buf, x, row, devices, "TrackRoute", "text_2")
      end
    elseif kind == "sends" then
      local text = sends_text(t)
      if api.str_width(text) > width then text = util.fit(text, width) end
      words(buf, x, row, text, "TrackInfo", "text_3")
    elseif kind == "input" then
      -- What the track takes in, with the level arriving there whether or
      -- not it is heard, so that a guitar can be seen before anything is armed.
      local label = paw.audio.label(t)
      if label then
        local heard = t.input and (t.monitor or t.armed)
        if t.input then
          local level = paw.audio.level(t)
          buf:text(x, row, view.level_glyph(level), level > 0.001 and "Input" or "TrackIndex")
          x = x + 2
        end
        label = util.fit(label, math.max(1, right - x))
        words(buf, x, row, label, heard and "Input" or "TrackInfo", heard and "select" or "text_3")
      end
    end
  end
end

--- One character for a level, 0 to 1 linear, from -60 dB up: a dot for silence.
function view.level_glyph(level)
  if level <= 0.001 then return draw.g.dot end
  local db = 20 * math.log10(level)
  return draw.g.eighths[util.clamp(math.floor((db + 60) / 60 * 8) + 1, 1, 8)]
end

--- The columns of the bar and beat lines on a timeline `width` wide.
local function grid_lines(scroll, zoom, width)
  local out = {}
  for _, line in ipairs(draw.bar_lines(scroll, width / zoom)) do
    out[#out + 1] = { x = math.floor((line.beat - scroll) * zoom + 0.5), bar = line.bar, beat = line.beat }
  end
  return out
end

--- What each clip's props (`view.clip_props`) draw in its body: the clip,
--- its track's colour, its kind and the zoom. Kept beside the props, not in
--- them, as they are not data for a frontend; and not in a closure made for
--- each clip on each frame, which LuaJIT does not compile.
local bodies = setmetatable({}, { __mode = "k" })

--- What is drawn in a clip's body (the `clip` role's `body(buf, props)`):
--- its waveform, or its notes as a small piano roll.
local function clip_body(box, p)
  local of = bodies[p]
  if not of then return end
  local clip, colour, kind, zoom = of.clip, of.colour, of.kind, of.zoom
  do
    local cw, height = box.width, box.height
    if clip.kind == "audio" then
      -- In pixels under the cells where the terminal shows them, the
      -- whole clip's, so that scrolling moves pieces already made.
      local body = box:sub(0, 1, cw, height - 1)
      -- The colour the cells draw it in (`paw.draw.hue`'s body).
      local colour = draw.mix(require("paw.theme").palette.bg, colour, kind == "_off" and 0.30 or 0.75)
      local pictured = body:strip(0, 0, cw, height - 1, {
        key = "arrange:wave:" .. clip.id,
        under = true,
        draw = function(g, px)
          paw.plot.wave(g, px, { peaks = function(n) return wave_peaks(clip, n) end, color = colour })
        end,
      })
      if not pictured then paw.plot.wave_cells(body, { peaks = function(n) return wave_peaks(clip, n) end }) end
    elseif clip.note_count > 0 then
      local rows, runs = preview(clip, cw, height - 1, zoom)
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
end

--- The styles of a clip's title and body by its kind ("", "_cur", "_off").
local title_of = { [""] = "title", _cur = "title_cur", _off = "title_off" }
local body_of = { [""] = "body", _cur = "body_cur", _off = "body_off" }

--- Where the window's scope (`paw.scope`) cuts a clip that crosses one of
--- its edges, in beats from the clip's start: `cut_in` at its start,
--- `cut_out` at its end, each nil where it does not cut. Only the drawing
--- is cut: an edit of the clip is an edit of all of it.
local function cuts(clip, from, to)
  if not from then return nil, nil end
  local finish = clip.start + clip.length
  local EPS = 1e-9
  local cut_in = (clip.start < from - EPS and finish > from + EPS) and from - clip.start or nil
  local cut_out = (clip.start < to - EPS and finish > to + EPS) and to - clip.start or nil
  return cut_in, cut_out
end

--- A clip on the timeline's plane, as the `clip` role it is. `from`, `to`:
--- the time of the window's scope, which cuts it (`cut_in`, `cut_out`).
--- `colour` is its track's (`paw.draw.track_colour`), when the caller has it.
function view.clip_props(clip, track, hue, kind, zoom, chosen, from, to, colour)
  colour = colour or draw.track_colour(track)
  local cut_in, cut_out = cuts(clip, from, to)
  -- A clip with takes says which plays: `take 3 ‹2/4›`.
  local badge = paw.takes.badge(clip)
  local label = clip.offline and ("offline · " .. clip.name) or clip.name
  -- Stretched, shifted, looped: `×1.5 ↻ drums`.
  local mark = paw.stretch.badge(clip)
  if mark then label = mark .. " " .. label end
  local warps
  for i, m in ipairs(clip.warp or {}) do
    warps = warps or {}
    warps[i] = m.beat - clip.start
  end
  local props = {
    key = "clip:" .. clip.id,
    name = clip.name,
    label = badge and (label .. " ‹" .. badge .. "›") or label,
    per = zoom,
    repeats = clip.loop and paw.stretch.repeats(clip) or nil,
    warps = warps,
    cut_in = cut_in,
    cut_out = cut_out,
    title_style = hue[title_of[kind]],
    body_style = hue[body_of[kind]],
    body = clip_body,
  }
  bodies[props] = { clip = clip, colour = colour, kind = kind, zoom = zoom }
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

--- True if the column `x` is in `span` (`{ from, to }`), when there is one.
local function within(span, x) return span and x >= span[1] and x < span[2] end

-- What `lane_sample` reads: the lane `lane` from the beat `scroll` at
-- `zoom` columns a beat, in half columns, nothing over the columns of
-- `skip` (spans), and the level of a value by `lo` and `hi` (a volume in
-- dB when they are nil). Set before each curve that it samples: a frame
-- draws a curve for each lane with no new function for it.
local sampled = { lane = 0, scroll = 0, zoom = 1 }

local function lane_sample(i)
  local skip = sampled.skip
  if skip then
    local col = math.floor(i / 2)
    for _, span in ipairs(skip) do
      if col >= span[1] and col < span[2] then return nil end
    end
  end
  local v = api.lane_value_at(sampled.lane, sampled.scroll + (i + 0.5) / (sampled.zoom * 2))
  local lo, hi = sampled.lo, sampled.hi
  if lo == nil then return (v + 60) / 66 end
  return hi ~= lo and util.clamp((v - lo) / (hi - lo), 0, 1) or 0.5
end

-- Set what `lane_sample` reads, and give it.
local function lane_sampler(lane, scroll, zoom, skip, lo, hi)
  sampled.lane, sampled.scroll, sampled.zoom, sampled.skip, sampled.lo, sampled.hi = lane, scroll, zoom, skip, lo, hi
  return lane_sample
end

--- A curve over `w` columns and `h` rows of `buf` from `x`, `y`, as the
--- `curve` role: `value(i)` is its height at half column `i` (nil for
--- none); `o.points` the points marked on it, `{ beat, height, glyph }`
--- each, which a terminal draws on its top row or its bottom by the
--- height; `o.style` the style of its cells; `o.from`, `o.per` where the
--- beats are; `o.color` and `o.enabled` how a window draws it.
local function curve(buf, x, y, w, h, value, o)
  local values, marks = {}, {}
  for i = 0, 2 * w - 1 do
    values[i + 1] = value and value(i) or false
  end
  for i, p in ipairs(o.points or {}) do
    marks[i] = { p[1], p[2] }
  end
  buf:mark("curve", x, y, w, h, {
    values = values,
    points = marks,
    from = o.from,
    per = o.per,
    color = o.color,
    enabled = o.enabled ~= false,
    draw = function(b)
      if value then draw.curve(b, 0, h, function(i) return values[i + 1] or nil end, o.style) end
      for _, p in ipairs(o.points or {}) do
        local px = math.floor((p[1] - o.from) * o.per + 0.5)
        if px >= 0 and px < w then b:text(px, p[2] >= 0.5 and 0 or h - 1, p[3] or "◆", o.style) end
      end
    end,
  })
end

--- The lines of the bars among `lines` (`grid_lines`), as the `beats`
--- role takes them.
local function bar_marks(lines)
  local out = {}
  for _, line in ipairs(lines) do
    if line.bar then out[#out + 1] = { line.beat, true } end
  end
  return out
end

--- Whether two values of plain data (numbers, text, flags, tables of
--- them) are the same.
local function same(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

-- The rows of the timeline that the terminal drew last, by their track and
-- place: what each was drawn from, and the columns its clips take. A row
-- drawn from the same things again puts back the cells it drew
-- (`buf:put_kept`) instead of drawing its clips again. Only the rows that
-- are all MIDI clips, not the cursor's, with nothing live, are kept.
local kept_rows = {}

--- What a row of the timeline is drawn from, besides its clips.
local function row_ground(self, buf, row, hue, marks, loop, colour, scope_from, scope_to)
  return {
    buf.x,
    buf.y,
    buf.width,
    buf.cx,
    buf.cy,
    buf.cw,
    buf.ch,
    row.y,
    row.h,
    self.scroll,
    self.geometry.zoom,
    colour,
    hue.title,
    hue.body,
    hue.title_off,
    hue.body_off,
    draw.g,
    paw.opt.ascii,
    paw.roles.registry.clip,
    paw.roles.registry.beats,
    loop and loop[1] or false,
    loop and loop[2] or false,
    scope_from or false,
    scope_to or false,
    marks = marks,
  }
end

local function lane(self, buf, row, track, selected, cursor_clip, lanes, hue, marks, loop, chosen)
  local y, height = row.y, row.h
  local scroll, zoom = self.scroll, self.geometry.zoom
  local plane = self.plane
  local w = buf.width
  local colour = draw.track_colour(track)
  local scope_from, scope_to = paw.scope.span()
  local layers = paw.ui.layers.arrange
  local painted = layers and layers.clip
  -- The clips the timeline shows, and a column more each side: the test
  -- below keeps the ones whose cells are in view.
  local clips = api.clip_list(track.id, scroll - 1 / zoom, scroll + (w + 1) / zoom)
  -- The clips in view, and the columns each takes.
  local spans, shown = {}, {}
  for _, clip in ipairs(clips) do
    local x0 = math.floor((clip.start - scroll) * zoom + 0.5)
    local x1 = math.floor((clip.start + clip.length - scroll) * zoom + 0.5)
    local cw = math.max(1, x1 - x0)
    if x0 < w and x0 + cw > 0 then
      spans[#spans + 1] = { x0, x0 + cw }
      shown[#shown + 1] = { clip = clip, cw = cw }
    end
  end
  --- What other modules mark on each clip (`paw.ui.layer("arrange",
  --- "clip", ...)`), in its cells.
  local function paint_layers()
    for _, s in ipairs(shown) do
      local clip = s.clip
      local box = plane.buf:sub(plane:cells(clip.start, y, clip.length, height))
      paw.ui.paint("arrange", "clip", { buf = box, width = s.cw, height = height, clip = clip })
    end
  end
  local keep_key, ground
  if not (paw.ui.scene_drawing or selected or (self.rec and track.armed)) then
    keep_key = "arrange:row:" .. track.id .. ":" .. buf.x .. ":" .. buf.y
    -- The layers are painted after the row is kept, each in its clip's
    -- cells: so the clips may not share a column.
    for _, clip in ipairs(clips) do
      if clip.kind ~= "midi" or clip.id == cursor_clip then keep_key = nil end
    end
    local right = -math.huge
    for _, span in ipairs(spans) do
      if span[1] < right then keep_key = nil end
      right = math.max(right, span[2])
    end
  end
  if keep_key then
    ground = row_ground(self, buf, row, hue, marks, loop, colour, scope_from, scope_to)
    local was = kept_rows[keep_key]
    if was and same(was.ground, ground) and same(was.clips, clips) and buf:put_kept(keep_key, 0, y, w, height) then
      if painted then paint_layers() end
      return spans
    end
  end
  plane:mark("beats", scroll, y, w / zoom, height, {
    from = scroll,
    per = zoom,
    style = selected and hue.lane_sel or "Lane",
    tone = "lane",
    selected = selected or nil,
    color = colour,
    index = row.index,
    loop = loop,
    lines = marks,
    beats = zoom >= 4 or nil,
  })
  for _, s in ipairs(shown) do
    local clip = s.clip
    local kind = clip.muted and "_off" or clip.id == cursor_clip and "_cur" or ""
    local box = plane:mark(
      "clip",
      clip.start,
      y,
      clip.length,
      height,
      view.clip_props(clip, track, hue, kind, zoom, chosen[clip.id], scope_from, scope_to, colour)
    )
    if painted and not keep_key then
      paw.ui.paint("arrange", "clip", { buf = box, width = s.cw, height = height, clip = clip })
    end
  end
  -- The take being made on an armed track, which a window makes grow with
  -- the playhead.
  local rec = self.rec
  if rec and track.armed then
    plane:mark("recording", rec.start, y, math.max((rec.to or (scroll + w / zoom)) - rec.start, 1 / zoom), height, {
      start = rec.start,
      at = rec.at,
      to = rec.to,
      per = zoom,
      color = colour,
      bind = "position",
    })
  end
  -- The volume curve runs over the empty lane, never over clips, and only
  -- on the track the cursor is on: drawn on every track it ran along the
  -- clips' edges and made the notes harder to read, and the curve of a
  -- track is a thing to look at while working on that track (the others
  -- show an `A` in their header; `<leader>a` opens their lanes as rows).
  for _, l in ipairs(lanes) do
    if selected and height >= 2 and l.target == "volume" and l.point_count > 0 then
      curve(buf, 0, y + 1, w, height - 1, lane_sampler(l.id, scroll, zoom, spans), {
        style = l.enabled and "Automation" or "Faint",
        color = colour,
        enabled = l.enabled,
        from = scroll,
        per = zoom,
      })
    end
  end
  if keep_key then
    buf:keep(keep_key, 0, y, w, height)
    kept_rows[keep_key] = { ground = ground, clips = clips }
    if painted then paint_layers() end
  end
  return spans
end

--- What a new project shows in place of tracks: how to begin.
local function welcome(buf)
  local lines = {
    { "o", "add a track" },
    { "a", "put an instrument on it" },
    { "i Enter", "enter notes: a clip opens to draw them (i alone: insert mode)" },
    { "then I", "play them on a MIDI keyboard (step input)" },
    { paw.keymap.human("<leader><Space>"), "play, and stop" },
    { paw.keymap.human("<leader>f:"), "find any command" },
    { "?", "every key that works where you are" },
    { ":", "run a command by name" },
    { ":help", "the manual, inside the program" },
  }
  if paw.commands.get("tutor") then lines[#lines + 1] = { ":tutor", "take the course, ten minutes a lesson" } end
  local x, y = math.max(2, math.floor((buf.width - 52) / 2)), math.max(1, math.floor((buf.height - #lines - 3) / 2))
  buf:text(x, y, "A new project", "WelcomeTitle")
  buf:text(x, y + 1, "Everything is driven from the keyboard. To begin:", "Dim")
  for i, line in ipairs(lines) do
    buf:text(x + 2, y + 2 + i, line[1], "HintKey")
    buf:text(x + 13, y + 2 + i, line[2], "Welcome")
  end
end

--- The lines a track's row takes, `th` the tracks' height: its own share
--- of it (`height`, which a drag of its header's bottom edge sets), at
--- least one.
function view.row_height(id, th) return math.max(1, math.floor(th * (api.track_get(id, "height") or 1) + 0.5)) end

--- The rows from `self.top` when some tracks show their take lanes or their
--- automation lanes: each track, then a row `{ kind = "take", id, take,
--- index, y, h = 1 }` for each of its take lanes, then a row `{ kind =
--- "lane", id, lane, index, y, h = 2 }` for each of its automation lanes.
--- Scrolls so that the cursor's row is in view. Returns the rows and the
--- line after the last.
function view:rows_with_lanes(tracks, th, ruler_rows, room, cursor_index)
  local bottom = ruler_rows + room
  local function place(top)
    local out, y = {}, ruler_rows
    for index = top, #tracks do
      local id = tracks[index]
      local h = view.row_height(id, th)
      if #out > 0 and y + h > bottom then break end
      out[#out + 1] = { kind = "track", id = id, index = index, y = y, h = h }
      y = y + h
      for k = 1, paw.takes.lane_count(id) do
        if y + 1 > bottom then return out, y, false end
        out[#out + 1] = { kind = "take", id = id, take = k, index = index, y = y, h = 1 }
        y = y + 1
      end
      for _, l in ipairs(paw.lanes.shown(id)) do
        if y + 2 > bottom then return out, y, false end
        out[#out + 1] = { kind = "lane", id = id, lane = l, index = index, y = y, h = 2 }
        y = y + 2
      end
    end
    return out, y, true
  end
  local function shows_cursor(rows)
    local lane = paw.cursor.lane_id()
    for _, row in ipairs(rows) do
      if row.index == cursor_index and ((row.kind == "track" and not lane) or (row.lane and row.lane.id == lane)) then
        return true
      end
    end
    return false
  end
  local lane = paw.cursor.lane_id()
  if cursor_index ~= self.seen_index or lane ~= self.seen_lane then
    if cursor_index < self.top then self.top = cursor_index end
    while self.top < cursor_index and not shows_cursor((place(self.top))) do
      self.top = self.top + 1
    end
  end
  self.seen_index, self.seen_lane, self.seen_fit = cursor_index, lane, nil
  self.top = util.clamp(self.top, 1, math.max(1, #tracks))
  -- No room left empty below while tracks above are scrolled away.
  while self.top > 1 do
    local rows, _, whole = place(self.top - 1)
    if not whole or rows[#rows].index < #tracks or not shows_cursor(rows) then break end
    self.top = self.top - 1
  end
  return place(self.top)
end

--- One automation lane row: the header names what the lane moves, its value
--- at the cursor and whether it is read or bypassed; the timeline has its
--- curve and points.
function view:draw_lane_row(headers, timeline, row, lines)
  local l, y = row.lane, row.y
  local zoom, scroll = self.geometry.zoom, self.scroll
  local beat = paw.cursor.beat
  local hw, tw = headers.width, timeline.width
  local on = paw.cursor.lane_id() == l.id
  local hue = draw.track_hue(api.track_get(row.id), row.index)
  local style = on and "TrackHeaderSel" or "TrackHeader"
  headers:fill(0, y, hw, 2, " ", style)
  for r = 0, 1 do
    headers:text(0, y + r, "▏", hue.fg)
  end
  headers:text(2, y, util.fit("↳ " .. paw.lanes.name(l), math.max(1, hw - 3)), style)
  local state = l.enabled and "read" or "bypass"
  headers:text(math.max(2, hw - #state - 1), y + 1, state, l.enabled and "Automation" or "FlagOff")
  headers:text(
    4,
    y + 1,
    util.fit(paw.lanes.format(l, paw.lanes.value_at(l, beat)), math.max(1, hw - #state - 5)),
    "TrackInfo"
  )
  self.plane:mark("beats", scroll, y, tw / zoom, 2, {
    from = scroll,
    per = zoom,
    style = on and hue.lane_sel or "Lane",
    tone = "auto",
    lines = bar_marks(lines),
  })
  -- Volume on the fader's useful stretch, -60 to +6 dB; the rest across their range.
  local lo, hi = l.min or 0, l.max or 1
  if l.target == "volume" then
    lo, hi = -60, 6
  end
  local function level(v) return hi ~= lo and util.clamp((v - lo) / (hi - lo), 0, 1) or 0.5 end
  local points = {}
  if l.target == "state" then
    -- No curve: each point's state, by name, up to the next point.
    local list = api.lane_points(l.id)
    for i, p in ipairs(list) do
      points[i] = { p[1], 1 }
    end
    curve(timeline, 0, y, tw, 2, nil, {
      points = points,
      style = l.enabled and "Automation" or "Faint",
      from = scroll,
      per = zoom,
      color = draw.track_colour(api.track_get(row.id), row.index),
      enabled = l.enabled,
    })
    for i, p in ipairs(list) do
      local x0 = math.max(0, math.floor((p[1] - scroll) * zoom + 0.5))
      local x1 = list[i + 1] and math.floor((list[i + 1][1] - scroll) * zoom + 0.5) or tw
      x1 = math.min(tw, x1)
      if x1 - x0 >= 2 then
        timeline:text(
          x0,
          y + 1,
          util.fit(paw.lanes.format(l, p[2]), x1 - x0 - 1),
          l.enabled and "Automation" or "Faint"
        )
      end
    end
  else
    for i, p in ipairs(api.lane_points(l.id)) do
      points[i] = { p[1], level(p[2]) }
    end
    curve(timeline, 0, y, tw, 2, l.point_count > 0 and lane_sampler(l.id, scroll, zoom, nil, lo, hi) or nil, {
      points = points,
      style = l.enabled and "Automation" or "Faint",
      from = scroll,
      per = zoom,
      color = draw.track_colour(api.track_get(row.id), row.index),
      enabled = l.enabled,
    })
  end
  if not on then return end
  -- A selection on this lane: the stretch of time chosen.
  local selection = paw.keymap.selection()
  if selection then
    local x0 = math.max(0, math.floor((selection.c0 - scroll) * zoom + 0.5))
    local x1 = math.min(tw, math.floor((selection.c1 - scroll) * zoom + 0.5))
    if x1 > x0 then timeline:fill(x0, y, x1 - x0, 2, nil, "Visual") end
  end
  local x = math.floor((beat - scroll) * zoom + 0.5)
  local cw = math.max(1, math.floor(paw.opt.grid * zoom))
  timeline:fill(x, y, cw, 1, nil, paw.keymap.mode == "x" and "CursorVisual" or "Cursor")
  timeline:fill(x, y + 1, cw, 1, nil, "CursorTail")
end

--- Where each row is among the lines that the counts of `j` and `k` go
--- over, and the cursor's: rows of tracks, and the lane rows too in normal
--- mode while lanes are open (paw/cursor.tl `move_track`). A take lane and,
--- in other modes, a lane row is on no line.
local function counted_lines(L, cursor_track, cursor_lane)
  local line_of, at = {}
  if paw.lanes.any_open() and paw.keymap.mode == "n" then
    local lines = paw.lanes.lines()
    local index = {}
    for i, l in ipairs(lines) do
      index[l.track .. ":" .. (l.lane or "")] = i
    end
    for _, row in ipairs(L.rows) do
      if row.kind ~= "take" then line_of[row] = index[row.id .. ":" .. (row.lane and row.lane.id or "")] end
    end
    at = cursor_track == 0 and #lines + 1 or index[tostring(cursor_track) .. ":" .. (cursor_lane or "")]
  else
    for _, row in ipairs(L.rows) do
      if row.kind == "track" then line_of[row] = row.index end
    end
    at = paw.cursor.row()
  end
  return line_of, at
end

--- The track column (paw/trackcolumn.tl) on each line of each row shown.
function view:draw_column(column, L, cursor_track, cursor_lane)
  local line_of, at = counted_lines(L, cursor_track, cursor_lane)
  for _, row in ipairs(L.rows) do
    local line = line_of[row]
    local on = row.id == cursor_track
      and (row.kind == "track" and not cursor_lane or row.kind == "lane" and row.lane.id == cursor_lane)
    for k = 0, row.h - 1 do
      paw.trackcolumn.draw(column, L.column, row.y + k, row.id, {
        row = row.index,
        line = k,
        kind = row.kind,
        lane = row.lane and row.lane.id or nil,
        relative = line and at and math.abs(line - at) or nil,
        cursor = on or nil,
      })
    end
  end
end

--- The tempo lane: the header says what the tempo is at the cursor, the
--- timeline draws the map as a curve, a step where a change holds and a slope
--- where it ramps, a mark on each change. `:tempo.lane` or `zT` hides it.
function view:draw_tempo_row(headers, timeline, y, lines)
  local zoom, scroll = self.geometry.zoom, self.scroll
  local hw, tw = headers.width, timeline.width
  local beat = paw.cursor.beat
  headers:fill(0, y, hw, 2, " ", "TrackHeader")
  headers:text(2, y, util.fit("tempo", math.max(1, hw - 3)), "TrackHeader")
  headers:text(2, y + 1, util.fit(string.format("%g bpm", paw.tempo.at(beat)), math.max(1, hw - 3)), "TrackInfo")
  timeline:fill(0, y, tw, 2, " ", "Lane")
  for _, line in ipairs(lines) do
    if line.bar then timeline:fill(line.x, y, 1, 2, draw.g.bar, "LaneBar") end
  end
  local lo, hi = paw.tempolane.range()
  local function level(bpm) return util.clamp((bpm - lo) / (hi - lo), 0, 1) end
  local points = {}
  for i, p in ipairs(paw.tempo.points()) do
    points[i] = { p.beat, level(p.bpm), paw.opt.ascii and (p.ramp and ">" or "*") or (p.ramp and "↗" or "◆") }
  end
  curve(
    timeline,
    0,
    y,
    tw,
    2,
    function(i) return level(paw.tempo.at(scroll + (i + 0.5) / (zoom * 2))) end,
    { points = points, style = "Automation", from = scroll, per = zoom, color = require("paw.theme").palette.accent }
  )
  local x = math.floor((beat - scroll) * zoom + 0.5)
  timeline:fill(x, y, math.max(1, math.floor(paw.opt.grid * zoom)), 1, nil, "Cursor")
end

--- One take lane: take `row.take` of every clip of the track that has that
--- many, over the clip's own stretch of time, lit where it is the one that
--- plays and faint where it is not, with its name. To look at: comping here
--- is `:take 2` over a selection, or a drag across the lane, with the
--- mouse in the terminal or the window. Returns the columns its names take,
--- for the playhead to keep their letters.
function view:draw_take_row(headers, timeline, row, lines)
  local y, k = row.y, row.take
  local zoom, scroll = self.geometry.zoom, self.scroll
  local hw, tw = headers.width, timeline.width
  local hue = draw.track_hue(api.track_get(row.id), row.index)
  local names = {}
  headers:fill(0, y, hw, 1, " ", "TrackHeader")
  headers:text(0, y, "▏", hue.fg)
  headers:text(2, y, util.fit("↳ take " .. k, math.max(1, hw - 3)), "TrackInfo")
  self.plane:mark("beats", scroll, y, tw / zoom, 1, {
    from = scroll,
    per = zoom,
    style = "TakeLane",
    tone = "take",
    lines = bar_marks(lines),
  })
  for _, clip in ipairs(api.clip_list(row.id)) do
    local takes = paw.takes.of(clip)
    local entry = takes and takes.list[k]
    if entry then
      local x0 = math.floor((clip.start - scroll) * zoom + 0.5)
      local x1 = math.floor((clip.start + clip.length - scroll) * zoom + 0.5)
      local cw = math.max(1, x1 - x0)
      if x0 < tw and x0 + cw > 0 then
        local on = takes.active == k
        local label = (on and (draw.g.play .. " ") or "") .. (entry.name or ("take " .. k))
        -- A clip of its own, which a window paints with the take's notes
        -- or waveform.
        local row_of = paw.frontend.take_rows(clip)
        self.plane:mark("clip", clip.start, y, clip.length, 1, {
          key = "take:" .. clip.id .. ":" .. k,
          id = clip.id,
          take = k,
          active = on or nil,
          name = entry.name,
          label = label,
          color = draw.track_colour(api.track_get(row.id), row.index),
          midi = clip.kind ~= "audio",
          length = clip.length,
          per = zoom,
          content = row_of and row_of[k] and row_of[k].key,
          title_style = on and hue.title or "TakeLaneName",
        })
        local at = cw > 2 and 1 or 0
        names[#names + 1] = { x0 + at, x0 + at + math.min(api.str_width(label), cw - at) }
      end
    end
  end
  -- The stretch being dragged over.
  local comp = self.comp
  if comp and comp.id == row.id and comp.take == k then
    local x0, x1 = math.floor(math.min(comp.x0, comp.x1)) - hw, math.floor(math.max(comp.x0, comp.x1)) - hw
    timeline:fill(math.max(0, x0), y, math.max(0, x1 - math.max(0, x0) + 1), 1, nil, "Visual")
  end
  return names
end

--- The time this view shows, for windows bound in time (`timebind`): the
--- beat at the left edge, columns per beat, and beats shown.
function view:time_axis() return self.scroll, paw.opt.zoom, self.geometry and self.geometry.span end

function view:set_time_axis(left, zoom)
  self.scroll = math.max(0, left)
  if zoom and paw.opt.zoom ~= zoom then paw.opt.zoom = zoom end
end

--- On an automation lane row the lane's own keys come first.
function view:subscope() return paw.cursor.lane_id() and "arrange.lane" or nil end

function view:render(buf, ctx)
  local g = draw.g
  local w, h = buf.width, buf.height
  local opt = paw.opt
  local zoom = opt.zoom
  local t = paw.ui.transport()
  local cursor = paw.cursor
  local cursor_track = cursor.track_id()
  local bar = paw.time.bar()

  local L = self:layout(w, h)
  local hw, tw = L.hw, L.tw
  local span = tw / zoom
  local tracks = L.tracks

  -- Keep the playhead in view while playing, and the cursor whenever it
  -- moves; unless another window leads this one's time (`timebind`).
  local led = ctx.follower
  -- In a subproject, the playhead's beat of the song is `origin` later
  -- than the window's beat (paw.time).
  local origin = paw.time.origin()
  if t.playing and opt.follow and not led then
    local position = t.position - origin
    if position < self.scroll or position >= self.scroll + span then self.scroll = paw.time.bar_floor(position) end
  elseif cursor.beat ~= self.seen_beat and not led then
    if cursor.beat < self.scroll then
      self.scroll = paw.time.bar_floor(cursor.beat)
    elseif cursor.beat >= self.scroll + span - 1 / zoom then
      self.scroll = math.max(0, math.ceil((cursor.beat - span) / bar + 1) * bar)
    end
  end
  self.seen_beat = cursor.beat
  -- In a scope with time, the view starts no earlier than the bar it starts in.
  local scope_from, scope_to = paw.scope.span()
  self.scroll = math.max(scope_from and paw.time.bar_floor(scope_from) or 0, self.scroll)
  local th = L.th
  self.geometry = { hw = hw, th = th, rows = #L.rows, zoom = zoom, span = span, layout = L }
  local function col(beat) return math.floor((beat - self.scroll) * zoom + 0.5) end

  -- All of it takes the pointer, in both frontends (paw/views/arrange_mouse.lua).
  buf:hit(0, 0, w, h, { kind = "arrange" })
  -- The rule between the headers and the timeline, from top to bottom.
  buf:fill(hw - 1, 0, 1, h, g.rule, "Rule")
  -- The track column at the left, then the headers.
  local cw = L.column.width
  -- Where the chips are, for the pointer, in the view's columns.
  self.column_width = cw
  local column = cw > 0 and buf:sub(0, 0, cw, h) or nil
  local headers, lanes = buf:sub(cw, 0, hw - 1 - cw, h), buf:sub(hw, 0, tw, h)
  buf:fill(0, 0, hw - 1, h, " ", "TrackHeader")

  -- Ruler: where the cursor is in the corner; bars, beat ticks and the loop.
  buf:fill(0, 0, hw - 1, L.ruler_rows, " ", "Ruler")
  local ruler = buf:sub(hw, 0, tw, 1)
  ruler:fill(0, 0, tw, 1, " ", "Ruler")
  if hw >= 12 then
    local pos = paw.scope.format(cursor.beat)
    if hw - 2 >= #pos + 5 then
      buf:mark("label", 1, 0, 3, 1, { text = "cur", style = "RulerCornerLabel", font = "sans", tone = "text_3" })
      buf:text(5, 0, pos, "RulerCorner")
    else
      buf:text(1, 0, util.fit(pos, hw - 2), "RulerCorner")
    end
  end
  local loop
  if t.loop_enabled and t.loop_end > t.loop_start then
    local x0, x1 = math.max(0, col(t.loop_start - origin)), math.min(tw, col(t.loop_end - origin))
    if x1 > x0 then
      loop = { x0, x1 }
      ruler:fill(x0, 0, x1 - x0, 1, nil, "RulerLoop")
    end
  end
  -- The punch range, in red over the loop's amber where they meet.
  local punch
  if t.punch_enabled and t.punch_end > t.punch_start then
    local x0, x1 = math.max(0, col(t.punch_start)), math.min(tw, col(t.punch_end))
    if x1 > x0 then
      punch = { x0, x1 }
      ruler:fill(x0, 0, x1 - x0, 1, nil, "RulerPunch")
    end
  end
  local lines = grid_lines(self.scroll, zoom, tw)

  -- Skip bar numbers that would run into each other when zoomed out.
  local every = math.max(1, math.ceil(5 / (paw.time.bar(self.scroll) * zoom)))
  local free = 0 -- the first column a label has not taken
  local label_end = {} -- where each bar's label ends, by its column
  for _, line in ipairs(lines) do
    if line.bar then
      if (line.bar - 1) % every == 0 and line.x >= free then
        local style = within(punch, line.x) and "RulerPunch" or within(loop, line.x) and "RulerLoop" or "RulerBar"
        -- Its label: the parts of `paw.opt.barlabel` (paw/ruler.tl).
        local x = line.x
        -- Its room: up to a column before the next bar whose label shows.
        local room = math.max(1, math.floor(paw.time.bar(line.beat) * zoom * every) - 1)
        for _, piece in ipairs(paw.ruler.label(line.bar, line.beat, style, cursor.beat, room)) do
          x = x + ruler:text(x, 0, piece[1], piece[2])
        end
        free, label_end[line.x] = x + 1, x
      end
    elseif zoom >= 2 and line.x >= free then
      ruler:text(
        line.x,
        0,
        g.tick,
        within(punch, line.x) and "RulerPunchTick" or within(loop, line.x) and "RulerLoopTick" or "RulerTick"
      )
    end
  end
  if loop then
    if col(t.loop_start - origin) >= 1 then
      ruler:text(col(t.loop_start - origin) - 1, 0, g.loop_in, "RulerLoopEdge")
    end
    -- The end's mark sits in the band's last cell, clear of the next bar's number.
    if col(t.loop_end - origin) >= 1 and col(t.loop_end - origin) <= tw then
      ruler:text(col(t.loop_end - origin) - 1, 0, g.loop_out, "RulerLoopEdgeIn")
    end
  end
  if punch then
    if col(t.punch_start) >= 1 then ruler:text(col(t.punch_start) - 1, 0, g.punch_in, "RulerPunchEdge") end
    if col(t.punch_end) >= 1 and col(t.punch_end) <= tw then
      ruler:text(col(t.punch_end) - 1, 0, g.punch_out, "RulerPunchEdge")
    end
  end
  -- Tempo and signature changes: a mark and the value, after the bar number.
  local mark_end = -1
  for _, mark in ipairs(paw.tempo.marks(self.scroll, self.scroll + span)) do
    local x = col(mark.beat)
    if paw.tempo.is_bar_line(mark.beat) then x = label_end[x] or (x + #tostring(paw.time.bar_of(mark.beat))) end
    x = math.max(x, mark_end)
    mark_end = x + ruler:text(x, 0, (mark.kind == "tempo" and "▾" or "‖") .. mark.text, "RulerTempo") + 1
  end
  local ruler2
  if L.band_y > 1 then
    ruler2 = buf:sub(hw, 1, tw, L.band_y - 1)
    ruler2:fill(0, 0, tw, L.band_y - 1, " ", "Ruler")
    paw.ruler.draw_lanes(ruler2, col, self.scroll, span)
  end
  if L.bands.rows > 0 then draw_bands(lanes, L.band_y, L.bands, col) end
  if L.tempo_rows > 0 then self:draw_tempo_row(headers, lanes, L.ruler_rows - L.tempo_rows, lines) end

  -- Tracks. The timeline under the ruler is a plane, beats along and the
  -- view's lines down: a window paints the clips and the lines on it where
  -- they are between cells. Lines, not tracks, go down, because rows of
  -- other kinds (take lanes, automation lanes) have heights of their own,
  -- and a drag goes across all of them in one domain.
  local mst = L.master
  self.plane = buf:plane(hw, L.ruler_rows, tw, math.max(1, mst.y - L.ruler_rows), {
    key = "timeline",
    x = { domain = "beat", from = self.scroll, per = zoom },
    y = { domain = "line", from = L.ruler_rows, per = 1 },
  })
  local marks = {}
  for i, line in ipairs(lines) do
    marks[i] = { line.beat, line.bar and true or false }
  end
  local loop_beats = loop and { t.loop_start - origin, t.loop_end - origin } or nil
  -- A take being made: from where the playhead was when it began, or from
  -- the punch-in.
  if t.take then
    self.rec_start = self.rec_start or t.position
  else
    self.rec_start = nil
  end
  self.rec = self.rec_start
      and {
        start = t.punch_enabled and math.max(self.rec_start, t.punch_start) or self.rec_start,
        at = t.position,
        to = t.punch_enabled and t.punch_end or nil,
      }
    or nil
  local cursor_clip = cursor.clip()
  cursor_clip = cursor_clip and cursor_clip.id
  local covered, names_of = {}, {}
  local cursor_lane = cursor.lane_id()
  local chosen = {}
  for _, id in ipairs(paw.frontend.chosen_clips()) do
    chosen[id] = true
  end
  for _, row in ipairs(L.rows) do
    if row.kind == "lane" then self:draw_lane_row(headers, lanes, row, lines) end
    if row.kind == "take" then names_of[row] = self:draw_take_row(headers, lanes, row, lines) end
  end
  for _, row in ipairs(L.rows) do
    if row.kind == "track" then
      local track, y = api.track_get(row.id), row.y
      local selected = row.id == cursor_track
      local automation = api.lane_list(row.id)
      local hue = draw.track_hue(track, row.index)
      header(self, headers, y, row.h, track, row.index, selected and not cursor_lane, automation, hue)
      -- With its lanes open as rows, a track's curve is drawn there, not here.
      covered[row] = lane(
        self,
        lanes,
        row,
        track,
        selected,
        cursor_clip,
        paw.lanes.is_open(row.id) and {} or automation,
        hue,
        marks,
        loop_beats,
        chosen
      )
      if selected and not cursor_lane then
        local x = col(cursor.beat)
        -- In the mode's colour where the clips' names are, a shadow below.
        local cw = math.max(1, math.floor(opt.grid * zoom))
        local mode = paw.keymap.mode
        lanes:fill(x, y, cw, 1, nil, mode == "x" and "CursorVisual" or mode == "i" and "InsertCursor" or "Cursor")
        if row.h > 1 then lanes:fill(x, y + 1, cw, row.h - 1, nil, "CursorTail") end
      end
    end
  end
  if column then self:draw_column(column, L, cursor_track, cursor_lane) end
  -- The selection of visual mode: whole tracks, or a stretch of time on some.
  local selection = paw.keymap.selection()
  if selection then
    for _, row in ipairs(cursor_lane and {} or L.rows) do
      if row.kind == "track" and row.index >= selection.r0 and row.index <= selection.r1 then
        if selection.kind == "line" then
          buf:fill(0, row.y, hw - 1, row.h, nil, "Visual")
          lanes:fill(0, row.y, tw, row.h, nil, "Visual")
        else
          local x0 = math.max(0, col(selection.c0))
          local x1 = math.min(tw, col(selection.c1))
          if x1 > x0 then lanes:fill(x0, row.y, x1 - x0, row.h, nil, "Visual") end
        end
      end
    end
  end

  -- The time outside a scope, dimmed: it is not part of what the tab shows.
  if scope_from then
    local a, b = math.max(0, col(scope_from)), math.min(tw, col(scope_to))
    if a > 0 then lanes:fill(0, L.ruler_rows, a, L.master.y - L.ruler_rows, nil, "ScopeOutside") end
    if b < tw then
      lanes:fill(math.max(0, b), L.ruler_rows, tw - math.max(0, b), L.master.y - L.ruler_rows, nil, "ScopeOutside")
    end
  end

  -- The master track is pinned to the bottom, with its level on both sides.
  if #tracks == 0 then
    welcome(buf:sub(0, L.ruler_rows, w, mst.y - L.ruler_rows))
  elseif mst.y - L.used >= 2 then
    -- Room left under the last track says how to fill it.
    -- A button in a window, which a click opens the kinds of track from.
    headers:text((headers.width + 1) >= 16 and 4 or 2, L.used, "o", "EmptyKey")
    local at = (headers.width + 1) >= 16 and 6 or 4
    headers:mark("button", at, L.used, math.max(9, math.min(13, (headers.width + 1) - 1 - at)), 1, {
      text = "new track",
      words = "New track",
      icon = "plus",
      style = "Empty",
      quiet = true,
      label = "new track",
    })
  end
  local master = api.track_get(0)
  -- The cursor reaches it with `j` from the last track, and `/master`.
  local on_master = cursor_track == 0
  header(self, headers, mst.y, mst.h, master, nil, on_master, api.lane_list(0), draw.track_hue(master))
  if on_master then
    local cw = math.max(1, math.floor(opt.grid * zoom))
    lanes:fill(col(cursor.beat), mst.y, cw, 1, nil, paw.keymap.mode == "x" and "CursorVisual" or "Cursor")
  end
  -- Beside the master, its automation when it has some; else nothing.
  for _, l in ipairs(api.lane_list(0)) do
    if l.target == "volume" and l.point_count > 0 then
      curve(lanes, 0, mst.y, tw, mst.h, lane_sampler(l.id, self.scroll, zoom), {
        style = l.enabled and "Automation" or "Faint",
        color = draw.track_colour(master),
        enabled = l.enabled,
        from = self.scroll,
        per = zoom,
      })
    end
  end

  local names = {}
  for name in pairs(self.layers) do
    names[#names + 1] = name
  end
  if #names > 0 then
    table.sort(names)
    local scroll = self.scroll
    local layer = {
      ruler = ruler,
      ruler2 = ruler2,
      lanes = buf:sub(hw, L.ruler_rows, tw, mst.y - L.ruler_rows),
      x = function(beat) return math.floor((beat - scroll) * zoom + 0.5) end,
      scroll = scroll,
      zoom = zoom,
      span = span,
      top = self.top,
      rows = #L.rows,
      th = th,
    }
    for _, name in ipairs(names) do
      local ok, err = pcall(self.layers[name], self, layer)
      if not ok then ruler:text(0, 0, util.fit(name .. ": " .. tostring(err), tw), "Error") end
    end
  end

  -- The playhead: a mark on the ruler and a thin line on the beat's left
  -- edge, which is where a clip that starts there begins to be drawn. Over a
  -- clip the line keeps the clip's colour behind it, so the clip is seen to
  -- start where it does. A window moves it as the song plays, and so does
  -- a terminal, which asks for the spans at the column it moves it to.
  local rows = L.rows
  -- The spans of the column the playhead was at last: a live frame asks
  -- again for the same column until the playhead moves on.
  local last_px, last_spans
  local function spans_at(px)
    if px == last_px then return last_spans end
    local spans = {}
    for _, row in ipairs(rows) do
      local on_clip, on_name = false, false
      for _, s in ipairs(covered[row] or NONE) do
        if px >= s[1] and px < s[2] then on_clip = true end
      end
      for _, s in ipairs(names_of[row] or NONE) do
        if px >= s[1] and px < s[2] then on_name = true end
      end
      if on_name then
        -- A take's name keeps its letter, in the playhead's colour.
        spans[#spans + 1] = { row.y, 1, "PlayheadClip", false }
      elseif on_clip then
        -- Under the clip's name only, so the name row reads unbroken.
        local skip = row.h > 1 and 1 or 0
        spans[#spans + 1] = { row.y + skip, row.h - skip, "PlayheadClip" }
      else
        spans[#spans + 1] = { row.y, row.h, "Playhead" }
      end
    end
    last_px, last_spans = px, spans
    return spans
  end
  buf:mark("playhead", hw, 0, tw, mst.y, {
    at = t.position,
    from = self.scroll + origin,
    per = zoom,
    lo = 0,
    hi = 1e12,
    spans = spans_at(col(t.position - origin)),
    spans_at = spans_at,
    bind = "position",
  })
end

--- Scroll so that the cursor is in the middle of the timeline.
function view:center()
  local g = self.geometry
  if not g then return end
  self.scroll = math.max(0, paw.time.bar_floor(math.max(0, paw.cursor.beat - g.span / 2)))
  api.ui_redraw()
end

--- Scroll by bars without moving the cursor.
function view:scroll_by(bars)
  self.scroll = math.max(0, self.scroll + bars * paw.time.bar(self.scroll))
  api.ui_redraw()
end

-- What modal editing works on: rows are positions in the track list.
view.grid = {
  get = function() return paw.cursor.row() or 1, paw.cursor.beat end,
  set = function(row, col)
    local list = paw.groups.rows()
    local id = list[util.clamp(row, 1, #list)]
    -- The row after the last track is the master's.
    if row > #list and paw.cursor.master_reachable() then id = 0 end
    -- Staying on the same track keeps the cursor on the lane row it is on.
    if #list > 0 and id ~= paw.cursor.track_id() then paw.cursor.set_track(id) end
    paw.cursor.set_beat(col)
  end,
  step = function() return paw.opt.grid end,
  -- A mark stays with its track when tracks are moved around.
  mark = function() return { track = paw.cursor.track_id(), beat = paw.cursor.beat } end,
  jump = function(pos)
    if pos.track and pcall(api.track_get, pos.track) then paw.cursor.set_track(pos.track) end
    paw.cursor.set_beat(pos.beat)
  end,
  -- Clips by name where they start, and tracks by name at the cursor's beat.
  search = function(text)
    local wanted, hits = text:lower(), {}
    for row, id in ipairs(paw.groups.rows()) do
      if api.track_get(id, "name"):lower():find(wanted, 1, true) then
        hits[#hits + 1] = { row = row, col = paw.cursor.beat }
      end
      for _, clip in ipairs(api.clip_list(id)) do
        if clip.name:lower():find(wanted, 1, true) then hits[#hits + 1] = { row = row, col = clip.start } end
      end
    end
    if api.track_get(0, "name"):lower():find(wanted, 1, true) then
      hits[#hits + 1] = { row = #paw.groups.rows() + 1, col = paw.cursor.beat }
    end
    return hits
  end,
}

-- Its ruler is its first row: a graphical frontend shows it with no title
-- of its own over it (paw/panes.tl).
view.titled = true
-- What moves on its own as the song plays: the playhead and the meters. A
-- frontend that paints them with the live values needs no new scene for
-- them, but for when the view must scroll to follow the playhead.
view.live_roles = { "playhead", "hmeter", "recording" }

--- Whether the view must be drawn again although its live roles move on
--- their own: the playhead it follows has left the time it shows.
function view:moving()
  local g = self.geometry
  if not (g and g.span and paw.opt.follow) then return false end
  local t = paw.ui.transport()
  local position = t.position - paw.time.origin()
  return t.playing and (position < self.scroll or position >= self.scroll + g.span)
end

paw.ui.view("arrange", view)
return view
