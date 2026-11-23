-- The vocal editor in a graphical frontend: the same view as the terminal's,
-- painted in pixels and worked with the pointer. It is also the example of
-- how an extension gives itself a window: a view with `paint(g, ctx)` and
-- `pointer(event)`, opened with `paw.canvas.open` (see runtime/lua/paw/canvas.tl).
--
--   toolbar    the clip, the singer (click to choose), what the engine is
--              doing, the tool, the panels, the grid, zoom
--   ruler      bars and beats; under them, how far each phrase is rendered;
--              a click moves the playhead
--   roll       notes with their lyrics, the pitch that was drawn and the pitch
--              that is sung; with the Pitch tool, each note's transition
--              points and the handles of its vibrato
--   phonemes   what the engine made of the lyrics; their starts are dragged
--   curves     one expression curve at a time, drawn in time with the notes
--   inspector  the properties of the selected notes
--
-- The panels are in gui_pitch.lua, gui_curves.lua and gui_inspector.lua.
-- Every key of the terminal editor works in the window too.
local api = paw.api
local util = paw.util
local music = paw.music
local utau = require("utau")
local notes = require("utau.notes")
local proto = require("utau.proto")
local audition = require("utau.audition")
local view = require("utau.editor").editor

local c = require("paw.canvas").palette
local TOOLBAR, RULER, KEYS, PHONEMES, INFO = 38, 24, 64, 30, 26
local TABS, GRAPH, INSPECTOR = 22, 92, 252
local STATE_COLOUR = {
  [proto.state.pending] = c.control_hover,
  [proto.state.rendering] = c.warn,
  [proto.state.draft] = c.select,
  [proto.state.final] = c.play_on,
  [proto.state.error] = c.error,
}

-- What only the graphical editor keeps: how far it is zoomed and scrolled,
-- the tool, which panels show, what is being dragged, and where the
-- buttons and fields are.
local gui = {
  zoom = 96,
  row = 22,
  top = 76,
  scroll = 0,
  tool = "notes",
  drag = nil,
  hits = paw.canvas.hit_list(),
  buttons = {},
  singers = false,
  curves = true,
  inspector = true,
  popup = nil,
  fields = {},
  KEYS = KEYS,
  TOOLBAR = TOOLBAR,
  RULER = RULER,
}
view.gui = gui
gui.view = view

local function is_black(pitch)
  local step = pitch % 12
  return step == 1 or step == 3 or step == 6 or step == 8 or step == 10
end

--- Where a beat of the clip and a pitch are in the roll, and back.
local function x_of(beat) return (beat - gui.scroll) * gui.zoom end
local function y_of(pitch) return (gui.top - pitch) * gui.row end
local function beat_at(x) return gui.scroll + x / gui.zoom end
local function pitch_at(y) return gui.top - y / gui.row end
gui.x_of, gui.y_of, gui.beat_at, gui.pitch_at = x_of, y_of, beat_at, pitch_at

local function snap(beat)
  local grid = paw.timegrid.step("note")
  return math.max(0, math.floor(beat / grid + 0.5) * grid)
end
gui.snap = snap

local pitch_panel = require("utau.gui_pitch")(gui)
local curve_panel = require("utau.gui_curves")(gui)
local inspector = require("utau.gui_inspector")(gui)

--- A button: drawn, and remembered for the pointer.
local function button(g, x, y, label, on, action, opts)
  opts = opts or {}
  local next_x = paw.canvas.button(g, gui.hits, x, y, label, action, {
    on = on,
    color = opts.color,
    size = opts.size,
    width = opts.width or (#label * 7 + 18),
    height = opts.height or 22,
  })
  return next_x - 2
end
gui.button = button

--- The note under the editor's cursor, from a list in hand.
local function cursor_note(list)
  for index, note in ipairs(list) do
    if note.pitch == view.pitch and view.beat >= note.start - 1e-9 and view.beat < note.start + note.length - 1e-9 then
      return note, index
    end
  end
end
gui.cursor_note = cursor_note

--- The sung pitch of the clip as points along the roll, from the engine's
--- curve (cents every few ticks), split where it is not voiced.
local function sung_lines(clip, width)
  local sung = utau.pitch[clip.id]
  if not sung then return {} end
  local first = math.floor(beat_at(-40) * proto.TICKS / sung.step) * sung.step
  local last = beat_at(width + 40) * proto.TICKS
  local lines, line = {}, {}
  for tick = math.max(0, first), last, sung.step do
    local cents = sung.ticks[tick]
    if cents then
      line[#line + 1] = x_of(tick / proto.TICKS)
      line[#line + 1] = y_of(cents / 100) + gui.row / 2
    elseif #line > 0 then
      lines[#lines + 1], line = line, {}
    end
  end
  lines[#lines + 1] = line
  return lines
end

function view:paint(g, ctx)
  local w, h = ctx.width, ctx.height
  gui.hits:clear()
  gui.buttons, gui.fields = gui.hits.list, {}
  g:rect(0, 0, w, h, { fill = c.surface })
  local clip = self:clip()
  if not clip then
    g:text(24, 24, "No vocal clip is open.", { color = c.text, size = 16, bold = true })
    g:text(
      24,
      50,
      "Double click a clip of a vocal track, or put the cursor on one and run :utau.edit.",
      { color = c.text_2 }
    )
    return
  end
  local track = api.track_get(clip.track)
  local device = utau.device_of(clip.track)
  local hue = paw.draw.track_colour(track)
  local config = utau.config(clip.track)
  local list = notes.list(clip.id)
  local grid = paw.timegrid.step("note")
  -- Vibratos and pitch points are in milliseconds: at the tempo where the clip is.
  local tempo = paw.tempo.at(clip.start)
  local transport = api.transport_get()
  local side = gui.inspector and INSPECTOR or 0
  local curve_h = (gui.curves and device) and (TABS + GRAPH) or 0
  local roll_h = h - TOOLBAR - RULER - PHONEMES - curve_h - INFO
  local roll_w = w - KEYS - side
  local top = TOOLBAR
  gui.size = { w = roll_w, h = roll_h }
  gui.geo = {
    w = w,
    h = h,
    roll_y = TOOLBAR + RULER,
    roll_w = roll_w,
    roll_h = roll_h,
    ph_y = TOOLBAR + RULER + roll_h,
    curve_y = TOOLBAR + RULER + roll_h + PHONEMES,
    curve_h = curve_h,
    info_y = h - INFO,
    side_x = w - side,
    side_w = side,
  }
  -- Keep what is scrolled to within reach, and the playhead in sight.
  gui.top = util.clamp(gui.top, roll_h / gui.row - 1, 127)
  gui.scroll = math.max(0, view.follow(gui.scroll, roll_w / gui.zoom, clip))
  -- One look at the notes for everything below.
  local S = {
    clip = clip,
    track = track,
    device = device,
    list = list,
    tempo = tempo,
    hue = hue,
    selected = {},
    targets = {},
    roll_w = roll_w,
    roll_h = roll_h,
  }
  local _, under = cursor_note(list)
  S.under = under
  local region = self:visual_region()
  for i, n in ipairs(list) do
    if (region and paw.edit.roll.inside(n, region)) or (not region and self.sel[view.key_of(n)]) then
      S.selected[i] = true
    end
  end
  for i in pairs(S.selected) do
    S.targets[#S.targets + 1] = i
  end
  table.sort(S.targets)
  if #S.targets == 0 and under then S.targets[1] = under end
  gui.S = S

  g:rect(0, 0, w, TOOLBAR, { fill = c.panel })
  g:rect(10, 8, #clip.name * 7 + 22, 22, { fill = hue, radius = 5 })
  g:text(21, 12, clip.name, { color = c.surface, bold = true })
  local x = 10 + #clip.name * 7 + 22 + 10
  g:text(x, 12, track.name, { color = c.text_2 })
  x = x + #track.name * 7 + 14
  gui.singer_x = x
  local singer = "choose a singer"
  for _, s in ipairs(utau.singers) do
    if s.id == config.singer then singer = s.name end
  end
  x = button(
    g,
    x,
    8,
    singer .. "  ▾",
    gui.singers,
    function() gui.singers = not gui.singers end,
    { color = c.text_2 }
  )
  local state, counts = utau.status(clip.track)
  local parts = {}
  for _, name in ipairs({ "final", "draft", "rendering", "pending", "error" }) do
    if counts[name] then parts[#parts + 1] = counts[name] .. " " .. name end
  end
  g:text(
    x + 4,
    12,
    state .. (#parts > 0 and ("  ·  " .. table.concat(parts, ", ")) or ""),
    { color = state == "ready" and c.play_on or c.warn, width = 200 }
  )
  -- From the right: zoom, grid, panels, tools.
  local right = w - 10
  local function from_right(label, on, action)
    right = right - (#label * 7 + 18)
    button(g, right, 8, label, on, action)
    right = right - 6
  end
  from_right("+", false, function() gui.zoom = math.min(480, gui.zoom * 1.3) end)
  from_right("−", false, function() gui.zoom = math.max(16, gui.zoom / 1.3) end)
  right = right - 8
  for _, step in ipairs({ { "1/32", 0.125 }, { "1/16", 0.25 }, { "1/8", 0.5 }, { "1/4", 1 } }) do
    from_right(step[1], grid == step[2], function() paw.opt.note_grid = step[2] end)
  end
  right = right - 8
  from_right("Inspector", gui.inspector, function() gui.inspector = not gui.inspector end)
  from_right("Curves", gui.curves, function() gui.curves = not gui.curves end)
  right = right - 8
  from_right("Pitch", gui.tool == "pitch", function() gui.tool = "pitch" end)
  from_right("Select", gui.tool == "select", function() gui.tool = "select" end)
  from_right("Notes", gui.tool == "notes", function() gui.tool = "notes" end)

  -- Ruler: bars and beats, and under them how far each phrase is rendered.
  g:rect(0, top, w - side, RULER, { fill = c.panel })
  local ruler = g:sub(KEYS, top, roll_w, RULER)
  local layout = utau.layouts[tostring(clip.track)]
  for _, p in ipairs(layout and layout.phrases or {}) do
    local x0 = x_of(paw.tempo.seconds_to_beats(p.start) - clip.start)
    local x1 = x_of(paw.tempo.seconds_to_beats(p.stop) - clip.start)
    ruler:rect(x0, RULER - 5, math.max(2, x1 - x0), 4, { fill = STATE_COLOUR[p.state] or c.control_hover, radius = 2 })
  end
  local bar = paw.time.bar()
  local roll = g:sub(KEYS, top + RULER, roll_w, roll_h)
  S.roll = roll
  -- Rows: black keys' rows darker, a line under each C.
  for pitch = math.floor(pitch_at(roll_h)), math.ceil(gui.top) do
    local y = y_of(pitch)
    roll:rect(0, y, roll_w, gui.row, { fill = is_black(pitch) and c.well or c.surface })
    if pitch % 12 == 0 then roll:line(0, y + gui.row, roll_w, y + gui.row, { color = c.line_beat }) end
  end
  S.beat_lines = {}
  for beat = math.floor(gui.scroll), math.ceil(gui.scroll + roll_w / gui.zoom) do
    local bx = x_of(beat)
    local pos = clip.start + beat
    local on_bar = math.abs(pos / bar - math.floor(pos / bar + 0.5)) < 1e-9
    S.beat_lines[#S.beat_lines + 1] = { x = bx, bar = on_bar }
    roll:line(bx, 0, bx, roll_h, { color = on_bar and c.text_3 or c.line_bar })
    if grid * gui.zoom >= 12 then
      for step = grid, 1 - 1e-9, grid do
        roll:line(bx + step * gui.zoom, 0, bx + step * gui.zoom, roll_h, { color = c.line_beat })
      end
    end
    if on_bar then
      ruler:text(bx + 4, 3, tostring(math.floor(pos / bar + 0.5) + 1), { color = c.text, bold = true })
    elseif gui.zoom >= 40 then
      ruler:text(bx + 4, 3, "·" .. (math.floor(pos % bar) + 1), { color = c.text_3, size = 11 })
    end
  end
  -- Past the end of the clip.
  local end_x = x_of(clip.length)
  if end_x < roll_w then roll:rect(end_x, 0, roll_w - end_x, roll_h, { fill = "#000000aa" }) end

  -- Notes, each with what it sings. Dragged ones are drawn where they go.
  local phonemes = utau.phonemes[clip.id]
  local drag = gui.drag
  local entry = self.entry
  local view_left, view_right = beat_at(-20), beat_at(roll_w + 20)
  local low, high = pitch_at(roll_h) - 1, gui.top + 1
  local labels = {}
  for index, note in ipairs(list) do
    local start, length, pitch = note.start, note.length, note.pitch
    if drag and drag.moving and drag.moving[index] then
      if drag.mode == "move" then
        start, pitch = math.max(0, start + drag.dbeat), util.clamp(pitch + drag.dpitch, 0, 127)
      end
      if drag.mode == "stretch" then length = math.max(grid, length + drag.dlen) end
    end
    if start + length >= view_left and start <= view_right and pitch >= low and pitch <= high then
      local lyric = notes.lyric(note) or paw.opt.utau_default_lyric
      local bad = false
      for _, p in ipairs(phonemes and phonemes.notes[index] or {}) do
        bad = bad or p.flags % 2 == 1
      end
      local fill = notes.is_rest(lyric) and c.control_hover or bad and c.error or hue
      local nx, ny, nw = x_of(start), y_of(pitch), math.max(4, length * gui.zoom - 1)
      local typing = entry and entry.kind == "lyric" and entry.index == index
      local chosen = S.selected[index]
      roll:rect(nx, ny + 1, nw, gui.row - 2, {
        fill = typing and c.warn or fill,
        radius = 3,
        stroke = chosen and c.warn or index == under and c.text or nil,
        width = 2,
      })
      if typing then lyric = self:entry_text() .. "▏" end
      local props = note.meta and note.meta.utau
      labels[#labels + 1] = { nx, ny, nw, lyric, notes.is_rest(lyric), props and props.vb }
    end
  end
  -- A note being drawn.
  if drag and drag.mode == "new" then
    roll:rect(
      x_of(drag.start),
      y_of(drag.pitch) + 1,
      math.max(4, drag.length * gui.zoom - 1),
      gui.row - 2,
      { fill = hue .. "99", stroke = c.text, radius = 3 }
    )
  end

  -- The pitch that was drawn, as it bends away from the notes; then the
  -- pitch that is sung.
  if device then
    local lane = notes.lane(clip.track, device, "pitd")
    local points = lane and api.lane_points(lane) or {}
    if #points > 0 then
      local over, value = notes.walker(list), notes.sampler(points, 0)
      local line = {}
      for px = 0, roll_w, 3 do
        local beat = beat_at(px)
        local note = beat < clip.length and over(beat)
        local cents = value(clip.start + beat)
        if note and beat >= note.start and beat < note.start + note.length then
          line[#line + 1] = px
          line[#line + 1] = y_of(note.pitch + cents / 100) + gui.row / 2
        elseif #line >= 4 then
          roll:poly(line, { color = c.mute, width = 2 })
          line = {}
        else
          line = {}
        end
      end
      if #line >= 4 then roll:poly(line, { color = c.mute, width = 2 }) end
    end
  end
  for _, line in ipairs(sung_lines(clip, roll_w)) do
    if #line >= 4 then roll:poly(line, { color = c.text, width = 1.5 }) end
  end
  -- What the pitch pencil is drawing.
  if drag and drag.mode == "pitch" and #drag.line >= 4 then roll:poly(drag.line, { color = c.select, width = 2 }) end
  -- Transition points and vibrato handles, with the Pitch tool.
  if gui.tool == "pitch" then pitch_panel.paint(self, roll, S) end
  -- Lyrics over the lines, clear of the transition points at the notes' starts.
  local inset = gui.tool == "pitch" and 11 or 5
  for _, l in ipairs(labels) do
    local nx, ny, nw = l[1], l[2], l[3]
    roll:text(
      nx + inset,
      ny + (gui.row - 15) / 2,
      l[4],
      { color = l[5] and c.text_2 or c.surface, width = nw - inset - 1 }
    )
    if l[6] and nw > 30 then
      roll:text(nx + nw - 14, ny + (gui.row - 15) / 2, "~", { color = c.surface, bold = true })
    end
  end
  -- The box being dragged out, and the selection of visual mode.
  if drag and drag.mode == "box" then
    local x0, y0 = math.min(drag.x0, drag.x1), math.min(drag.y0, drag.y1)
    roll:rect(
      x0,
      y0,
      math.abs(drag.x1 - drag.x0),
      math.abs(drag.y1 - drag.y0),
      { fill = c.select .. "33", stroke = c.select }
    )
  end
  if region then
    local x0, x1 = x_of(region.c0), x_of(region.c1)
    local y0, y1 = y_of(region.r1), y_of(region.r0) + gui.row
    if region.kind == "line" then
      x0, x1 = 0, roll_w
    end
    if region.kind == "char" then
      y0, y1 = 0, roll_h
    end
    roll:rect(x0, y0, x1 - x0, y1 - y0, { fill = c.select .. "26", stroke = c.select .. "88" })
  end
  -- The editor's cursor, where there is no note under it.
  if not under then
    roll:rect(
      x_of(self.beat),
      y_of(self.pitch),
      math.max(2, grid * gui.zoom),
      gui.row,
      { stroke = c.select .. "aa", radius = 2 }
    )
  end

  local playhead = transport.position >= clip.start and transport.position <= clip.start + clip.length
  if playhead then
    local px = x_of(transport.position - clip.start)
    roll:line(px, 0, px, roll_h, { color = c.play, width = 1 })
    ruler:poly({ px - 4.5, RULER - 6, px + 4.5, RULER - 6, px, RULER }, { fill = c.play })
  end

  local keys = g:sub(0, top + RULER, KEYS, roll_h)
  keys:rect(0, 0, KEYS, roll_h, { fill = c.key_white })
  for pitch = math.floor(pitch_at(roll_h)), math.ceil(gui.top) do
    local y = y_of(pitch)
    if is_black(pitch) then
      keys:rect(0, y, KEYS * 0.62, gui.row, { fill = c.key_black, radius = 2 })
    elseif pitch % 12 == 0 or pitch % 12 == 5 then
      keys:line(0, y + gui.row, KEYS, y + gui.row, { color = c.key_line })
    end
    if pitch == self.pitch then keys:rect(0, y, KEYS, gui.row, { fill = c.select .. "bb" }) end
    if pitch % 12 == 0 then
      keys:text(KEYS - 26, y + 3, music.name(pitch), { color = c.text_off, size = 10, bold = true })
    end
  end

  -- Phonemes, under the notes they belong to: a box from each one's start
  -- to its end, its start a line that can be dragged.
  local py = gui.geo.ph_y
  g:rect(0, py, w - side, PHONEMES, { fill = c.panel })
  g:text(8, py + 4, "phonemes", { color = c.text_3, size = 10 })
  g:text(8, py + 16, "drag · type", { color = c.text_3, size = 9 })
  local strip = g:sub(KEYS, py, roll_w, PHONEMES)
  local _, ph_note, ph_k = self:phoneme()
  S.phoneme_boxes = {}
  for note_index, of_note in pairs(phonemes and phonemes.notes or {}) do
    for k, p in ipairs(of_note) do
      local x0, x1 = x_of(p.start / proto.TICKS), x_of(p.stop / proto.TICKS)
      if drag and drag.mode == "phoneme" and drag.note == note_index and drag.k == k then
        x0 = x_of((p.start + drag.dticks) / proto.TICKS)
      end
      if x1 >= -40 and x0 <= roll_w + 40 then
        S.phoneme_boxes[#S.phoneme_boxes + 1] = { note = note_index, k = k, x0 = x0, x1 = x1, p = p }
        local missing, changed = p.flags % 2 == 1, math.floor(p.flags / 2) % 2 == 1
        local colour = missing and c.error or changed and c.mute or c.select
        local marked = self.ph and note_index == ph_note and k == ph_k
        strip:rect(
          x0,
          4,
          math.max(2, x1 - x0 - 1),
          PHONEMES - 8,
          { fill = colour .. (marked and "66" or "22"), radius = 2 }
        )
        strip:line(x0, 2, x0, PHONEMES - 2, { color = colour, width = 2 })
        local name = p.phoneme ~= "" and p.phoneme or p.alias
        if entry and entry.kind == "phoneme" and entry.note == note_index and entry.k == k then
          strip:rect(x0, 4, math.max(60, x1 - x0), PHONEMES - 8, { fill = c.warn, radius = 2 })
          strip:text(x0 + 4, 8, self:entry_text() .. "▏", { color = c.surface, bold = true, size = 11 })
        else
          strip:text(x0 + 4, 8, name, { color = colour, size = 11, bold = marked, width = math.max(8, x1 - x0 - 6) })
        end
      end
    end
  end

  if curve_h > 0 then curve_panel.paint(self, g, S) end

  if side > 0 then inspector.paint(self, g:sub(w - side, TOOLBAR, side, h - TOOLBAR - INFO), S) end

  -- What is under the cursor, or what the pointer does.
  local iy = h - INFO
  g:rect(0, iy, w, INFO, { fill = c.control })
  -- Every phoneme missing from the voicebank most often means lyrics in
  -- another script than its aliases (romaji for a kana voicebank).
  local total, missing = 0, 0
  for _, of_note in pairs(phonemes and phonemes.notes or {}) do
    for _, p in ipairs(of_note) do
      total = total + 1
      if p.flags % 2 == 1 then missing = missing + 1 end
    end
  end
  local info
  if drag and drag.label then
    info = drag.label
  elseif entry then
    info = entry.kind == "lyric" and "typing a lyric: Tab goes on to the next note, Enter keeps it, Esc drops it"
      or "typing " .. (entry.label or entry.kind or "") .. ": Enter keeps it, Esc drops it"
  elseif total > 0 and missing == total then
    info =
      "the voicebank has none of these phonemes (red): its aliases may be in kana, try :utau.batch romaji_to_hiragana"
  elseif gui.tool == "pitch" then
    info =
      "pitch: draw over the notes to bend them · drag a point, double click adds one, right click removes it, Ctrl+click its shape · Ctrl+click a note: vibrato"
  elseif gui.tool == "select" then
    info =
      "select: drag a box around notes, Shift adds · drag them to move · Ctrl+C copies, Ctrl+V pastes at the cursor, Del removes"
  else
    local note = under and list[under]
    if note and #S.targets <= 1 then
      info = string.format(
        "%s  %s  length %g  “%s”",
        music.name(note.pitch),
        paw.time.format(clip.start + note.start),
        note.length,
        notes.lyric(note) or paw.opt.utau_default_lyric
      )
    elseif #S.targets > 1 then
      info = #S.targets
        .. " notes selected: drag one to move them all, its right edge to stretch them · Del removes · Ctrl+C copies"
    else
      info =
        "notes: drag on empty space draws one, Ctrl+drag selects · click selects, Shift+click adds · double click types the lyric · right click removes"
    end
  end
  g:text(12, iy + 6, info, { color = c.text_2, width = w - 24 })

  -- The list of singers, over everything else, while it is open.
  if gui.singers then
    local rows = math.max(1, #utau.singers)
    local lx, ly, lw = gui.singer_x, TOOLBAR - 2, 360
    g:rect(lx, ly, lw, rows * 24 + 8, { fill = c.panel, stroke = c.select, radius = 6 })
    gui.singer_list = { x = lx, y = ly + 4, w = lw, row = 24 }
    if #utau.singers == 0 then g:text(lx + 12, ly + 9, "no singers: the engine is " .. state, { color = c.text_2 }) end
    for i, s in ipairs(utau.singers) do
      g:text(
        lx + 12,
        ly + 9 + (i - 1) * 24,
        (s.id == config.singer and "● " or "   ") .. s.name,
        { color = s.id == config.singer and c.select or c.text, width = lw - 90 }
      )
      g:text(lx + lw - 12, ly + 9 + (i - 1) * 24, s.type or "", { color = c.text_3, align = "right", width = 80 })
    end
  end
  -- A list to choose from, opened by a field of the inspector.
  if gui.popup then inspector.paint_popup(self, g, gui.popup) end
end

--- The note at a place in the roll, its index, and whether the place is on
--- the note's right edge.
local function note_at(list, x, y)
  local beat, pitch = beat_at(x), math.floor(pitch_at(y) + 1)
  for index = #list, 1, -1 do
    local note = list[index]
    if note.pitch == pitch and beat >= note.start and beat < note.start + note.length then
      return note, index, x >= x_of(note.start + note.length) - 6 and note.length * gui.zoom > 14
    end
  end
end
gui.note_at = note_at

--- The places of the notes whose boxes meet a rectangle of the roll.
local function notes_in_box(list, x0, y0, x1, y1)
  x0, x1 = math.min(x0, x1), math.max(x0, x1)
  y0, y1 = math.min(y0, y1), math.max(y0, y1)
  local out = {}
  for i, n in ipairs(list) do
    local nx0, nx1 = x_of(n.start), x_of(n.start + n.length)
    local ny0 = y_of(n.pitch)
    if nx1 > x0 and nx0 < x1 and ny0 + gui.row > y0 and ny0 < y1 then out[#out + 1] = i end
  end
  return out
end

--- Hear the note at a place of the clip.
local function hear(clip, index) audition.note(clip.id, index) end
gui.hear = hear

--- Move or stretch the selection by what a drag did.
local function finish_drag(self, clip, drag)
  if drag.mode == "move" and (math.abs(drag.dbeat) > 1e-9 or drag.dpitch ~= 0) then
    self:change_targets(function(n)
      n.start = math.max(0, n.start + drag.dbeat)
      n.pitch = util.clamp(n.pitch + drag.dpitch, 0, 127)
    end)
    if drag.dpitch ~= 0 and drag.index then
      local list = notes.list(clip.id)
      local _, index = cursor_note(list)
      if index then hear(clip, index) end
    end
  elseif drag.mode == "stretch" and math.abs(drag.dlen) > 1e-9 then
    local grid = paw.timegrid.step("note")
    self:change_targets(function(n) n.length = math.max(grid, n.length + drag.dlen) end)
  end
end

function view:pointer(e)
  local clip = self:clip()
  if not clip or not gui.size or not gui.geo then return end
  local geo = gui.geo
  local device = utau.device_of(clip.track)
  local in_roll = e.x >= KEYS and e.x < KEYS + geo.roll_w and e.y >= geo.roll_y and e.y < geo.roll_y + geo.roll_h
  local x, y = e.x - KEYS, e.y - geo.roll_y

  if e.kind == "wheel" then
    if gui.popup then return inspector.popup_wheel(e) end
    if e.ctrl and e.shift then
      -- Taller or shorter rows, keeping the pitch under the pointer where it is.
      local pitch = pitch_at(y)
      gui.row = util.clamp(gui.row * (e.dy > 0 and 1.15 or 1 / 1.15), 10, 60)
      gui.top = pitch + y / gui.row
    elseif e.ctrl then
      -- Keep the beat under the pointer where it is.
      local beat = beat_at(x)
      gui.zoom = util.clamp(gui.zoom * (e.dy > 0 and 1.2 or 1 / 1.2), 16, 480)
      gui.scroll = math.max(0, beat - x / gui.zoom)
    elseif e.shift then
      gui.scroll = math.max(0, gui.scroll - e.dy / gui.zoom)
    else
      gui.top = gui.top + e.dy / gui.row
      gui.scroll = math.max(0, gui.scroll - (e.dx or 0) / gui.zoom)
    end
    return
  end

  -- A press while typing keeps what was typed first.
  if (e.kind == "down" or e.kind == "double") and self.entry then
    self:commit_entry()
    if self.entry then self:close_entry() end
  end

  if e.kind == "down" and gui.popup then return inspector.popup_pointer(self, e) end
  if e.kind == "down" and gui.singers then
    -- A click in the list chooses; anywhere else only closes it.
    local l = gui.singer_list
    local row = l and math.floor((e.y - l.y) / l.row) + 1
    local singer = l and e.x >= l.x and e.x < l.x + l.w and utau.singers[row]
    gui.singers = false
    if singer then utau.configure(clip.track, { singer = singer.id }) end
    return
  end
  if e.kind == "down" or e.kind == "double" then
    local b = gui.hits:under(e.x, e.y)
    if b then
      if e.kind == "down" then b.down(e) end
      return
    end
  end
  if (e.kind == "down" or e.kind == "double") and e.x >= geo.side_x and geo.side_w > 0 then
    return inspector.pointer(self, e)
  end
  if e.kind == "down" and e.y < TOOLBAR then return end
  if e.kind == "down" and e.y < TOOLBAR + RULER and e.x >= KEYS then
    return paw.transport.seek(math.max(0, clip.start + snap(beat_at(x))))
  end
  if (e.kind == "down" or e.kind == "double") and e.y >= geo.ph_y and e.y < geo.ph_y + PHONEMES and e.x >= KEYS then
    return pitch_panel.phoneme_pointer(self, e, clip)
  end
  if
    (e.kind == "down" or e.kind == "double")
    and geo.curve_h > 0
    and e.y >= geo.curve_y
    and e.y < geo.curve_y + geo.curve_h
  then
    return curve_panel.pointer(self, e, clip)
  end

  local list = notes.list(clip.id)
  if e.kind == "double" and in_roll then
    if gui.tool == "pitch" then return pitch_panel.pointer(self, e, clip, list, x, y) end
    local note = note_at(list, x, y)
    if note then
      self.pitch, self.beat = note.pitch, note.start
      self:edit_lyric()
    else
      -- On empty space: the phrase there.
      local phrase = self:phrase_at(beat_at(x), list)
      if phrase then
        local indices = {}
        for i = phrase.first, phrase.last do
          indices[#indices + 1] = i
        end
        self:select(indices, e.shift)
      end
    end
    gui.drag = nil
    return
  end

  if e.kind == "down" and in_roll then
    if gui.tool == "pitch" and pitch_panel.pointer(self, e, clip, list, x, y) then return end
    local note, index, edge = note_at(list, x, y)
    self.pitch = util.clamp(math.floor(pitch_at(y) + 1), 0, 127)
    self.beat = util.clamp(note and note.start or snap(beat_at(x) - paw.timegrid.step("note") / 2), 0, clip.length)
    if e.button == "right" then
      if not note then return end
      if gui.tool == "pitch" and device then
        notes.reset(clip.track, device, "pitd", clip.start + note.start, clip.start + note.start + note.length)
      elseif self.sel[view.key_of(note)] then
        local remove = self:selected(list)
        self:clear_selection()
        paw.clip(clip.id):edit_notes({ remove = remove })
      else
        paw.clip(clip.id):remove_note(index)
      end
    elseif gui.tool == "pitch" then
      gui.drag = { mode = "pitch", samples = {}, line = {} }
      self:pointer(util.merge(e, { kind = "move" }))
    elseif note and e.shift then
      self:select({ index }, true, true)
    elseif note then
      if not self.sel[view.key_of(note)] then self:select({ index }) end
      local moving = {}
      for _, i in ipairs(self:selected(list)) do
        moving[i] = true
      end
      gui.drag = {
        mode = edge and "stretch" or "move",
        index = index,
        moving = moving,
        dbeat = 0,
        dpitch = 0,
        dlen = 0,
        from = { beat = beat_at(x), pitch = pitch_at(y), start = note.start, note = note.pitch, length = note.length },
        min_start = math.huge,
      }
      for i in pairs(moving) do
        gui.drag.min_start = math.min(gui.drag.min_start, list[i].start)
      end
      hear(clip, index)
    elseif e.ctrl or gui.tool == "select" then
      if not e.shift then self:clear_selection() end
      gui.drag = { mode = "box", x0 = x, y0 = y, x1 = x, y1 = y, add = e.shift }
    else
      self:clear_selection()
      gui.drag = { mode = "new", pitch = self.pitch, start = self.beat, length = paw.timegrid.step("note") * 2 }
    end
    return
  end

  local drag = gui.drag
  if not drag then return end
  if drag.panel then return drag.panel(self, e, clip, x, y) end
  if e.kind == "move" then
    local grid = paw.timegrid.step("note")
    if drag.mode == "move" then
      local start = snap(drag.from.start + beat_at(x) - drag.from.beat)
      drag.dbeat = math.max(-drag.min_start, start - drag.from.start)
      drag.dpitch = math.floor(pitch_at(y) - drag.from.pitch + 0.5)
      drag.label = string.format("move %+g beats, %+d semitones", drag.dbeat, drag.dpitch)
    elseif drag.mode == "stretch" then
      local length = math.max(grid, snap(drag.from.length + beat_at(x) - drag.from.beat))
      drag.dlen = length - drag.from.length
      drag.label = string.format("length %g (%+g)", length, drag.dlen)
    elseif drag.mode == "new" then
      drag.length = math.max(grid, snap(beat_at(x) - drag.start + grid / 2))
    elseif drag.mode == "box" then
      drag.x1, drag.y1 = x, y
    elseif drag.mode == "pitch" then
      -- How far the pointer is from the note it is over, in cents.
      local beat = beat_at(x)
      local note = notes.near(clip.id, beat)
      if note and beat >= note.start and beat < note.start + note.length then
        local cents = (pitch_at(y) + 0.5 - note.pitch) * 100
        drag.samples[#drag.samples + 1] = { clip.start + beat, util.clamp(cents, -1200, 1200) }
        drag.line[#drag.line + 1] = x
        drag.line[#drag.line + 1] = y
      end
    end
  elseif e.kind == "up" then
    gui.drag = nil
    if drag.mode == "move" or drag.mode == "stretch" then
      finish_drag(self, clip, drag)
    elseif drag.mode == "box" then
      self:select(notes_in_box(list, drag.x0, drag.y0, drag.x1, drag.y1), drag.add)
    elseif drag.mode == "new" and drag.start < clip.length then
      local c_obj = paw.clip(clip.id)
      local index = c_obj:add_note({
        pitch = drag.pitch,
        start = drag.start,
        length = math.min(drag.length, clip.length - drag.start),
        velocity = paw.opt.velocity,
      })
      if index then
        self:select({ index })
        hear(clip, index)
      end
    elseif drag.mode == "pitch" and device and #drag.samples > 1 then
      table.sort(drag.samples, function(a, b) return a[1] < b[1] end)
      notes.stroke(clip.track, device, "pitd", drag.samples)
    end
  end
end

--- Closing the window puts the keyboard back in the arrange view, and
--- leaving the editor from the keyboard closes the window.
function view:on_close()
  if self.entry then self:close_entry() end
  gui.singers, gui.drag, gui.popup = false, nil, nil
  paw.ui.hide("utau")
end

function view:on_hide() paw.canvas.close("utau") end

-- Opening a vocal clip (the vocal track kind's editor) opens this editor, in
-- the terminal and in a window.
local edit = view.edit
function view:edit(clip_id)
  edit(self, clip_id)
  if self.clip_id ~= clip_id then return end
  local list = notes.list(clip_id)
  local high = 60
  for _, n in ipairs(list) do
    high = math.max(high, n.pitch)
  end
  gui.top, gui.scroll, gui.drag, gui.singers, gui.popup = high + 5, 0, nil, false, nil
  paw.canvas.open("utau", { title = "Vocal editor", width = 1180, height = 620 })
end

-- In the window's track menu: singing for a track that is there already.
-- A new vocal track is offered wherever a track is made, as a kind of
-- track (see utau.commands).
table.insert(paw.frontend.menus.track, { label = "Make this a vocal track", command = "utau.voice" })

return gui
