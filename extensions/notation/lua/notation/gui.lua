-- The staff in pixels: the measures engraved by `notation.engrave`, in a
-- window of the graphical frontend or on a terminal's pixel surface.
--
--   toolbar   (a window only) the clip; the value to enter, dot, rest, the
--             accidental to enter with; marks; zoom
--   page      wrapped systems scrolling down, or one endless system
--             scrolling sideways (the galley, `zg`), drawn as layers: the
--             page's ink, then the selection, suggestions, diagnostics,
--             the caret and the playhead over it
--   info      (a window only) what is under the cursor, or what the pointer does
--
-- The pointer, in the spirit of the keys: in normal mode a click puts the
-- cursor on a note or a place (and sounds it), Shift extends a selection
-- from the cursor, a drag on the paper selects a box, a drag of a note
-- moves it up or down the staff and in time, a double click enters notes
-- there; in insert mode a click enters a note of the chosen value where the
-- pointer is, and the note to be entered follows the pointer. A click lands
-- on the chosen value within the beat, Alt-click on the grid. A right
-- click opens a menu of what can be done there.
local api = paw.api
local util = paw.util
local model = require("notation.model")
local engrave = require("notation.engrave")
local page = require("notation.page")
local view = require("notation")

local c = require("paw.canvas").palette
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local EPS = 1e-6
local INFO = 26

-- bar_h is the toolbar's height: it grows a row for every row the buttons wrap to.
local gui = {
  bar_h = 44,
  scroll = 0,
  hscroll = 0,
  drag = nil,
  hits = paw.canvas.hit_list(),
  buttons = {},
  heads = {},
  accidental = nil,
  rest = false,
  measures = {},
}
view.gui = gui
view.space = nil -- the staff space chosen by zooming, in px; nil: by the size of a cell
view.galley = false -- one endless system, scrolled sideways
view.page = false -- the systems on pages of paper (`zp`)
view.spread = 1 -- how widely notes are spaced

local function round(v) return floor(v + 0.5) end
local function alpha(colour, a) return colour .. string.format("%02x", floor(a * 255 + 0.5)) end

--- The staff space for a paint: the zoom's, or about a third of a cell's
--- height on a terminal's surface (a staff in a cell and a half), 12 px in
--- a window; in the page view, the largest whose page fits the width.
local function space_for(ctx)
  if view.space then return view.space end
  if view.page then return page.space_for(ctx.width or 800) end
  if not ctx.surface then return 12 end
  local want, best = (ctx.cell and ctx.cell.h or 27) / 3, engrave.STEPS[1]
  for _, s in ipairs(engrave.STEPS) do
    if s <= want + EPS then best = s end
  end
  return best
end

--- Zoom by whole pixels of staff space: `dir` 1 in, -1 out.
function gui.zoom(dir)
  local now = view.space or gui.last_space or 12
  local steps, at = engrave.STEPS, 1
  for i, s in ipairs(steps) do
    if s <= now then at = i end
  end
  view.space = steps[util.clamp(at + dir, 1, #steps)]
  api.ui_redraw()
end

local styles = {}
local function style_for(ctx)
  local cell = ctx.cell or { w = 8, h = 17 }
  local o = {
    space = space_for(ctx),
    cell = cell,
    ink = ctx.fg or c.text,
    paper = ctx.bg or c.surface,
    accent = c.select,
    whole_cells = ctx.surface and true or false,
  }
  if view.page and paw.opt.notation_paper == "white" then
    o.ink, o.paper = "#000000", "#ffffff"
  end
  local key = table.concat({ o.space, cell.w, cell.h, o.ink, o.paper, tostring(o.whole_cells) }, ":")
  styles[key] = styles[key] or engrave.style(o)
  gui.last_space = o.space
  return styles[key]
end

--- The systems of a layout for a style and width, kept until either
--- changes: wrapped, in the galley, or on pages.
function view:engrave(layout, width, st, top)
  local geo = view.page and page.geometry(st.sp, st.whole and st.cell)
  local key = table.concat(
    { tostring(layout), st.key, width, tostring(view.galley), view.spread, top or 0, geo and geo.key or "" },
    ":"
  )
  if gui.eng and gui.eng_key == key then return gui.eng end
  -- The staves' ink is kept across layouts while the style holds.
  if gui.measures.style ~= st.key then gui.measures = { style = st.key, generation = 0 } end
  gui.measures.generation = gui.measures.generation + 1
  engrave.sweep(gui.measures)
  local eng
  if geo then
    eng = page.systems(layout, st, geo, width, gui.measures)
  else
    eng = engrave.systems(
      layout,
      st,
      { width = width, galley = view.galley, spread = view.spread, top = top or 0, cache = gui.measures }
    )
  end
  gui.eng, gui.eng_key, gui.page = eng, key, nil
  return eng
end

--- Where a beat of the clip is on the page: the system and x, or nil.
local function at_beat(eng, beat)
  for _, sys in ipairs(eng.systems) do
    for k, placed in ipairs(sys.measures) do
      local m = placed.m
      local last = k == #sys.measures and sys == eng.systems[#eng.systems]
      if beat >= m.start - EPS and (beat < m.start + m.length - EPS or (last and beat <= m.start + m.length + EPS)) then
        return sys, placed.x + model.x_of(placed.p, beat), placed
      end
    end
  end
end
gui.at_beat = at_beat

-- The page's ink --------------------------------------------------------------------------------

--- A system's ink in the page's coordinates, kept on the system: its own
--- and its measures', with the note heads for the pointer.
local function system_ops(eng, sys, layout)
  if sys.heads then return sys end
  local st = eng.style
  local heads = {}
  local prefix, spans = engrave.system_ink(st, layout, sys, eng)
  for _, placed in ipairs(sys.measures) do
    local mi = engrave.measure(gui.measures, st, layout, sys, placed)
    placed.ops = mi.ops
    for _, h in ipairs(mi.heads) do
      -- A written note's ink is kept by its id; the note that plays it may
      -- have another place among the clip's notes since.
      local index = h.id and layout.places and layout.places[h.id] or h.index
      heads[#heads + 1] =
        util.merge(h, { x = h.x + placed.x, gx = h.gx + placed.x, y = h.y + sys.y, sys = sys, index = index })
    end
  end
  sys.prefix, sys.spans, sys.heads = prefix.ops, spans.ops, heads
  return sys
end

--- Put the page's ink for what shows into the drawing: in a window from
--- `top` down, scrolled; in the galley the system's start stays at the
--- left and the measures pass under it.
local function page_ink(g, eng, layout, area)
  local st = eng.style
  local out = g.ops
  gui.heads = {}
  local dy = area.top - gui.scroll
  if eng.pages then
    local clip = view:clip()
    local title, composer = page.heading(clip and clip:get().name)
    page.paper(out, eng, 0, dy, { shadow = true, title = title, composer = composer, part = layout.part_name })
  end
  for _, sys in ipairs(eng.systems) do
    if sys.y + sys.height + dy > area.top and sys.y + dy < area.bottom then
      system_ops(eng, sys, layout)
      local dx = view.galley and -gui.hscroll or 0
      for _, placed in ipairs(sys.measures) do
        local x = placed.x + dx
        if x + placed.p.width > (view.galley and sys.x0 or 0) and x < area.width then
          engrave.place(placed.ops, out, x, sys.y + dy)
          g:cut(x + placed.p.width, sys.y + dy, sys.y + dy + sys.height)
        end
      end
      engrave.place(sys.spans, out, dx, sys.y + dy)
      if view.galley then
        -- What starts the system stays, over the paper.
        out[#out + 1] = { "r", 0, sys.y + dy, sys.x0, sys.height, st.paper, "", 1, 0 }
        g:cut(sys.x0, sys.y + dy, sys.y + dy + sys.height)
      end
      engrave.place(sys.prefix, out, 0, sys.y + dy)
      for _, h in ipairs(sys.heads) do
        local hx = h.x + dx
        if not view.galley or hx > sys.x0 then
          gui.heads[#gui.heads + 1] = util.merge(h, { x = hx, gx = h.gx + dx, y = h.y + dy })
        end
      end
    end
  end
end

-- What moves over the page -----------------------------------------------------------------------

--- A note head drawn over the page, at a staff step and beat, with its
--- ledger lines: the caret's note to enter, a suggestion, a dragged note.
--- `beat` is the page's; the staff is the open clip's at `step`, in the
--- score where the clip is a staff of it (`F`, `view:frame`).
local function lone_head(g, eng, layout, beat, step, colour, base, area, accidental, F)
  local st = eng.style
  local sys, x = at_beat(eng, beat)
  if not sys then return end
  local staff = (F and F.base or 0) + view:staff_of_step(step)
  local pos = step + (F and F.dstep or 0) - model.CLEF_BOTTOM[layout.staves[staff]]
  local dx = view.galley and -gui.hscroll or 0
  local dy = area.top - gui.scroll
  local y = engrave.y_of(st, sys, staff, pos) + dy
  local name = engrave.HEAD_GLYPH(base)
  local gl = st.font.glyphs[name]
  local hw = (gl.bbox[3] - gl.bbox[1]) * st.sp
  local hx = round(x + dx - hw / 2)
  local ext = st.ledger_ext
  for p = -2, pos, -2 do
    g.ops[#g.ops + 1] = {
      "r",
      round(hx - ext),
      round(engrave.y_of(st, sys, staff, p) + dy - st.ledger / 2),
      round(hw + 2 * ext),
      st.ledger,
      colour,
      "",
      1,
      0,
    }
  end
  for p = 10, pos, 2 do
    g.ops[#g.ops + 1] = {
      "r",
      round(hx - ext),
      round(engrave.y_of(st, sys, staff, p) + dy - st.ledger / 2),
      round(hw + 2 * ext),
      st.ledger,
      colour,
      "",
      1,
      0,
    }
  end
  g:glyph(hx, round(y), st.em, gl.cp, colour, st.font.name)
  if base and base < 4 then
    -- A stem up, as the note would get on its own.
    local up = pos < 4
    local anchor = gl.anchors and gl.anchors[up and "stemUpSE" or "stemDownNW"]
    local sx = up and hx + round((anchor and anchor[1] or 1.18) * st.sp) - st.stem or hx
    local y0 = up and round(y - 3.5 * st.sp) or round(y)
    g.ops[#g.ops + 1] = { "r", sx, y0, st.stem, round(3.5 * st.sp), colour, "", 1, 0 }
  end
  if accidental then
    local an = engrave.ACC_GLYPH[accidental]
    local ag = st.font.glyphs[an]
    local aw = (ag.bbox[3] - ag.bbox[1]) * st.sp
    g:glyph(round(hx - 0.2 * st.sp - aw), round(y), st.em, ag.cp, colour, st.font.name)
  end
  return hx, y
end

--- The head of a note on the page again, in another colour.
local function tint(g, eng, h, colour)
  local st = eng.style
  local gl = st.font.glyphs[h.glyph]
  g:glyph(h.gx, round(h.y), st.em, gl.cp, colour, st.font.name)
end

--- The heads of notes by their places among a clip's notes: on the staves
--- `first` to `last` of the page (all of them without), of `clip` (in a
--- score, where a staff shows several).
local function heads_of(places, first, last, clip)
  local set, out = {}, {}
  for _, p in ipairs(places) do
    set[p] = true
  end
  for _, h in ipairs(gui.heads) do
    if
      set[h.index]
      and (not first or (h.staff >= first and h.staff <= last))
      and (not clip or not h.clip or h.clip == clip)
    then
      out[#out + 1] = h
    end
  end
  return out
end

--- The active staves of a frame: the first and the last.
local function mine(F) return F.base + 1, F.base + F.count end

--- The selection: a faint band over its stretch, and its notes in the
--- accent; in a score, over each staff it takes.
local function draw_selection(g, eng, layout, F, selection, area)
  if not selection then return end
  local st = eng.style
  local dy = area.top - gui.scroll
  local dx = view.galley and -gui.hscroll or 0
  local S = view.staves
  local parts = S.split(F, selection)
  for _, sys in ipairs(eng.systems) do
    for _, placed in ipairs(sys.measures) do
      local m = placed.m
      if selection.c1 > m.start and selection.c0 < m.start + m.length then
        local x0 = selection.kind == "line" and placed.x or placed.x + model.x_of(placed.p, max(selection.c0, m.start))
        local x1 = (selection.kind == "line" or selection.c1 >= m.start + m.length - EPS) and placed.x + placed.p.width
          or placed.x + model.x_of(placed.p, selection.c1)
        for _, part in ipairs(parts) do
          local u = F.multi and layout.units[part.unit]
          local y0 = engrave.y_of(st, sys, u and u.first or 1, 8) - 2 * st.sp
          local y1 = engrave.y_of(st, sys, u and u.last or #layout.staves, 0) + 2 * st.sp
          g.ops[#g.ops + 1] =
            { "r", round(x0 + dx), round(y0 + dy), round(x1 - x0), round(y1 - y0), alpha(st.accent, 0.15), "", 1, 0 }
        end
      end
    end
  end
  for _, part in ipairs(parts) do
    local u = F.multi and layout.units[part.unit]
    for _, id in ipairs(part.clips) do
      local c = api.clip_get(id)
      local shift = c.start - F.start
      local region = util.merge(part.region, { c0 = part.region.c0 - shift, c1 = part.region.c1 - shift })
      local _, places = paw.edit.roll.notes(paw.clip(id), region)
      for _, h in ipairs(heads_of(places, u and u.first, u and u.last, id)) do
        tint(g, eng, h, st.accent)
      end
    end
  end
end

--- In a score, the staves not under the cursor dimmed (`score_dim`) or
--- tinted in their parts' colours (`score_colors`), and a mark at the
--- active staff's start on every system.
local function draw_staves(g, eng, layout, F, area)
  local st = eng.style
  local dy = area.top - gui.scroll
  local first, last = mine(F)
  for _, sys in ipairs(eng.systems) do
    -- Each staff's band: halfway to the staves either side.
    local function edge(s)
      if s < 1 then return engrave.y_of(st, sys, 1, 8) - 3 * st.sp end
      if s >= #layout.staves then return engrave.y_of(st, sys, #layout.staves, 0) + 3 * st.sp end
      return (engrave.y_of(st, sys, s, 0) + engrave.y_of(st, sys, s + 1, 8)) / 2
    end
    for s = 1, #layout.staves do
      if s < first or s > last then
        local id = layout.parts and layout.parts[s]
        local colour = paw.opt.score_dim and alpha(st.paper, 0.55)
          or paw.opt.score_colors and id and alpha(paw.draw.part_colour(api.part_get(id)), 0.16)
        if colour then
          local y0, y1 = edge(s - 1), edge(s)
          g.ops[#g.ops + 1] = { "r", 0, round(y0 + dy), round(area.width), round(y1 - y0), colour, "", 1, 0 }
        end
      end
    end
    local y0 = engrave.y_of(st, sys, first, 8)
    local y1 = engrave.y_of(st, sys, last, 0)
    g.ops[#g.ops + 1] = { "r", 3, round(y0 + dy), max(2, round(st.sp / 3)), round(y1 - y0), st.accent, "", 1, 0 }
  end
end

--- Suggestions from `paw.complete`, laid out as real notes would be (the
--- clip's notes with the suggestion's, written together), faint, in a
--- second accent.
local function draw_ghosts(g, eng, layout, clip, area, F)
  local complete = paw.complete
  local cur = complete and complete.current and complete.current()
  if not (cur and cur.clip == clip.id and cur.item and #cur.item.notes > 0) then return end
  local key = tostring(cur.item) .. ":" .. tostring(clip:get().stamp)
  if gui.ghost_key ~= key then
    local notes = clip:notes()
    for _, n in ipairs(cur.item.notes) do
      notes[#notes + 1] = { pitch = n.pitch, start = n.start, length = n.length, velocity = n.velocity or 80 }
    end
    table.sort(notes, function(a, b) return a.start < b.start end)
    local opts = view.layout_opts(clip:get())
    local ok, combined = pcall(model.layout, notes, opts)
    local ghosts = {}
    if ok then
      local mine = {}
      for _, n in ipairs(cur.item.notes) do
        mine[n.pitch .. "@" .. string.format("%.4f", n.start)] = true
      end
      for _, ev in ipairs(model.events(combined)) do
        for _, n in ipairs(ev.notes or {}) do
          local played = notes[n.index]
          if played and mine[played.pitch .. "@" .. string.format("%.4f", played.start)] and not n.tied then
            ghosts[#ghosts + 1] = { beat = ev.start, step = n.step, base = ev.base, acc = n.acc }
          end
        end
      end
    end
    gui.ghost_key, gui.ghosts = key, ghosts
  end
  local colour = alpha(c.play_on, 0.45)
  for _, gh in ipairs(gui.ghosts or {}) do
    lone_head(g, eng, layout, gh.beat + F.off, gh.step, colour, gh.base, area, gh.acc, F)
  end
end

local SEVERITY_COLOUR = { c.error, c.warn, c.select, c.text_3 }

local function fmt_n(v) return string.format("%.1f", v) end

--- Diagnostics of the clip: a wavy line under the staff across each one's
--- stretch, its notes tinted, and a mark in the system's left margin.
local function draw_diagnostics(g, eng, layout, clip, area, F)
  local diag = paw.diagnostic
  if not (diag and diag.get) then return end
  local list = diag.get(clip.id)
  if #list == 0 then return end
  local st = eng.style
  local dy = area.top - gui.scroll
  local dx = view.galley and -gui.hscroll or 0
  local marked = {}
  for _, d in ipairs(list) do
    local colour = SEVERITY_COLOUR[d.severity] or c.warn
    local from, to = d.at + F.off, d.at + F.off + max(d.length, layout.grid or 0.25)
    for _, sys in ipairs(eng.systems) do
      for _, placed in ipairs(sys.measures) do
        local m = placed.m
        if to > m.start + EPS and from < m.start + m.length - EPS then
          local x0 = placed.x + model.x_of(placed.p, max(from, m.start)) - st.sp * 0.6
          local x1 = placed.x + model.x_of(placed.p, min(to, m.start + m.length)) + st.sp * 0.6
          local y = engrave.y_of(st, sys, F.base + F.count, 0) + 1.6 * st.sp + dy
          local pts, x, k = { "M", fmt_n(x0 + dx), fmt_n(y) }, x0, 0
          while x < x1 do
            x = min(x1, x + st.sp * 0.4)
            k = k + 1
            pts[#pts + 1] = "L"
            pts[#pts + 1] = fmt_n(x + dx)
            pts[#pts + 1] = fmt_n(y + (k % 2 == 1 and -1 or 1) * st.sp * 0.2)
          end
          g.ops[#g.ops + 1] = { "p", table.concat(pts, " "), colour, max(1, st.stem), "" }
          if not marked[sys] or d.severity < marked[sys] then marked[sys] = d.severity end
        end
      end
    end
    local first, last = mine(F)
    for _, h in ipairs(heads_of(diag.places(d), first, last, clip.id)) do
      tint(g, eng, h, colour)
    end
  end
  for sys, severity in pairs(marked) do
    local y = engrave.y_of(st, sys, F.base + 1, 4) + dy
    g.ops[#g.ops + 1] = {
      "r",
      1,
      round(y - st.sp),
      max(2, round(st.sp / 3)),
      round(2 * st.sp),
      SEVERITY_COLOUR[severity] or c.warn,
      "",
      1,
      0,
    }
  end
end

--- The cursor: a hairline across the staff at its beat, and the note that
--- would be entered there (half transparent), or its note tinted.
local function draw_caret(g, eng, layout, area, under_index, inserting, F)
  local st = eng.style
  local beat, step = view.beat, view.step
  if gui.hover and inserting then
    beat, step = gui.hover.beat, gui.hover.step
  end
  local sys, x = at_beat(eng, beat + F.off)
  if not sys then return end
  local dy = area.top - gui.scroll
  local dx = view.galley and -gui.hscroll or 0
  -- Across the active staves (in a score, the cursor's instrument).
  local top = engrave.y_of(st, sys, F.base + 1, 8) - 1.5 * st.sp
  local bottom = engrave.y_of(st, sys, F.base + F.count, 0) + 1.5 * st.sp
  g.ops[#g.ops + 1] = { "r", round(x + dx), round(top + dy), 1, round(bottom - top), alpha(st.accent, 0.7), "", 1, 0 }
  if under_index and not (gui.hover and inserting) then
    local here = view.beat + F.off
    local first, last = mine(F)
    for _, h in ipairs(heads_of({ under_index }, first, last, view.clip_id)) do
      if (h.player or 1) == F.player and (abs(h.start - here) < EPS or (h.start <= here + EPS)) then
        tint(g, eng, h, st.accent)
      end
    end
  else
    local value = view:entry_length()
    local base = model.value_of(value) or 1
    lone_head(
      g,
      eng,
      layout,
      beat + F.off,
      step,
      alpha(inserting and c.play_on or st.accent, 0.5),
      base,
      area,
      gui.accidental,
      F
    )
  end
end

local function draw_playhead(g, eng, layout, F, area)
  local t = api.transport_get()
  local at = t.position - F.start
  local sys, x = at_beat(eng, at)
  if not sys or at < 0 then return end
  local st = eng.style
  local dy = area.top - gui.scroll
  local dx = view.galley and -gui.hscroll or 0
  local top = engrave.y_of(st, sys, 1, 8) - 2 * st.sp
  local bottom = engrave.y_of(st, sys, #layout.staves, 0) + 2 * st.sp
  g.ops[#g.ops + 1] = { "r", round(x + dx - 1), round(top + dy), 2, round(bottom - top), c.play, "", 1, 0 }
end

--- The playhead as a mark that a window paints and moves by the live
--- values, with no new scene (`ctx.marks`): over the whole paint, in
--- `segments` (`{ from, to, x0, x1, top, bottom }`, the song's beats and
--- pixels), one for each stretch between two slots of a measure that
--- shows, so that it goes as `draw_playhead` puts it.
local function playhead_mark(eng, layout, F, area, w, h)
  local st = eng.style
  local dy = area.top - gui.scroll
  local dx = view.galley and -gui.hscroll or 0
  local segments = {}
  for _, sys in ipairs(eng.systems) do
    local top = max(area.top, engrave.y_of(st, sys, 1, 8) - 2 * st.sp + dy)
    local bottom = min(area.bottom, engrave.y_of(st, sys, #layout.staves, 0) + 2 * st.sp + dy)
    if bottom > top then
      for _, placed in ipairs(sys.measures) do
        local m = placed.m
        local points = { { m.start, placed.x + model.x_of(placed.p, m.start) } }
        for _, slot in ipairs(placed.p.slots) do
          if slot.t > m.start + EPS and slot.t < m.start + m.length - EPS then
            points[#points + 1] = { slot.t, placed.x + slot.x }
          end
        end
        points[#points + 1] = { m.start + m.length, placed.x + model.x_of(placed.p, m.start + m.length) }
        for i = 1, #points - 1 do
          local a, b = points[i], points[i + 1]
          if b[1] > a[1] + EPS then
            segments[#segments + 1] = { F.start + a[1], F.start + b[1], a[2] + dx, b[2] + dx, top, bottom }
          end
        end
      end
    end
  end
  return { role = "playhead", x = 0, y = 0, w = w, h = h, props = { segments = segments, bind = "position" } }
end

--- What the drawing in a window shows but the playhead, as a key: while
--- the song plays, the system that the playhead is in (the page follows
--- it), and in the galley where it is (the galley scrolls with it). Other
--- changes draw the view again by themselves.
function view:scene_key()
  local eng = gui.engraved
  if not eng then return nil end
  local t = api.transport_get()
  local sys = at_beat(eng, self:follow_beat())
  return table.concat(
    { tostring(t.playing), sys and sys.y or -1, view.galley and t.playing and t.position or 0, gui.scroll, gui.hscroll },
    ":"
  )
end
view.scene_roles = { "playhead" }

-- Painting ---------------------------------------------------------------------------------------

local VALUE_BUTTONS = { 4, 2, 1, 0.5, 0.25, 0.125 }

-- The toolbar is groups of buttons, every button BTN high, BAR_GAP between
-- groups; a group that does not fit on its row goes to the next row. The
-- zoom buttons keep the right end of the first row.
local BTN, BAR_ROW, BAR_GAP, ZOOM_W = 28, 36, 16, 70

local function bar_height(rows) return #rows * BAR_ROW + 8 end

--- Where each group goes in a toolbar `width` wide: rows of { group, x }.
local function bar_rows(groups, width)
  local rows, x = { {} }, 10
  for _, grp in ipairs(groups) do
    local gw = -5
    for _, b in ipairs(grp) do
      gw = gw + b.w + 5
    end
    if x > 10 and x + gw > width - 10 - (#rows == 1 and ZOOM_W or 0) then
      rows[#rows + 1] = {}
      x = 10
    end
    local row = rows[#rows]
    row[#row + 1] = { group = grp, x = x }
    x = x + gw + BAR_GAP
  end
  return rows
end

--- One button at `x, y`. Its label, or what `b.draw` paints around the
--- button's centre, sits in the middle of the box.
local function button(g, x, y, b)
  g:rect(x, y, b.w, BTN, { fill = b.fill or (b.on and c.select or c.control), radius = 5 })
  local ink2 = (b.fill or b.on) and c.surface or c.text
  if b.draw then
    b.draw(x + b.w / 2, y + BTN / 2, ink2)
  else
    -- Centred text is centred on the `x` it is given, not started there.
    g:text(
      x + b.w / 2,
      y + (BTN - 12) / 2 - 1,
      b.label,
      { color = ink2, bold = b.on or b.fill ~= nil, align = "center", width = b.w }
    )
  end
  if b.action then gui.hits:add(g, x, y, b.w, BTN, b.action).label = b.label end
end

--- A glyph of the music font for the toolbar, at a staff space of 5 px.
local function icon(g, name, x, y, colour)
  local font = require("notation.smufl").font()
  local gl = font.glyphs[name]
  if gl then g:glyph(x, y, 20, gl.cp, colour, font.name) end
end

--- The toolbar's buttons, in groups: the clip's name, the note value, the
--- accidentals, the marks, the dynamics. `colour` is the part's.
local function bar_groups(g, name, colour)
  local marks = view.marks
  local values, accidentals, shapes, dynamics = {}, {}, {}, {}
  for _, v in ipairs(VALUE_BUTTONS) do
    values[#values + 1] = {
      w = 30,
      label = model.NAMES[v],
      on = view.value == v and not gui.rest,
      action = function()
        view:choose(v)
        gui.rest = false
      end,
      draw = function(cx, cy, ink2)
        local hx, hy = floor(cx - 4), floor(cy + 6)
        icon(g, engrave.HEAD_GLYPH(v), hx, hy, ink2)
        if v < 4 then
          g:rect(hx + 6, hy - 16, 1, 16, { fill = ink2 })
          local flags = model.flags(v)
          if flags > 0 then icon(g, ({ "flag8thUp", "flag16thUp", "flag32ndUp" })[flags], hx + 6, hy - 16, ink2) end
        end
      end,
    }
  end
  values[#values + 1] = {
    w = 30,
    label = "dot",
    on = view.dot,
    action = function() view.dot = not view.dot end,
    draw = function(cx, cy, ink2) icon(g, "augmentationDot", floor(cx - 2), floor(cy), ink2) end,
  }
  values[#values + 1] = { w = 44, label = "rest", on = gui.rest, action = function() gui.rest = not gui.rest end }
  for _, a in ipairs({ { -1, "flat" }, { 0, "natural" }, { 1, "sharp" } }) do
    accidentals[#accidentals + 1] = {
      w = 30,
      label = a[2],
      on = gui.accidental == a[1],
      action = function() gui.accidental = (gui.accidental ~= a[1]) and a[1] or nil end,
      draw = function(cx, cy, ink2) icon(g, engrave.ACC_GLYPH[a[1]], floor(cx - 3), floor(cy + 1), ink2) end,
    }
  end
  local function art(kind, glyph_name)
    shapes[#shapes + 1] = {
      w = 28,
      label = kind,
      action = function() marks.toggle_art(kind, view:chord_indices()) end,
      draw = function(cx, cy, ink2) icon(g, glyph_name, floor(cx - 4), floor(cy + 2), ink2) end,
    }
  end
  art("staccato", "articStaccatoAbove")
  art("accent", "articAccentAbove")
  art("tenuto", "articTenutoAbove")
  shapes[#shapes + 1] = {
    w = 28,
    label = "slur",
    action = function() paw.cmd("notation.slur") end,
    draw = function(cx, cy, ink2)
      g:poly({ cx - 8, cy + 3, cx - 4, cy - 2, cx + 4, cy - 2, cx + 8, cy + 3 }, { color = ink2, width = 1.6 })
    end,
  }
  shapes[#shapes + 1] = {
    w = 28,
    label = "triplet",
    action = function() view:toggle_tuplet() end,
    draw = function(cx, cy, ink2) icon(g, "tuplet3", floor(cx - 3), floor(cy + 5), ink2) end,
  }
  shapes[#shapes + 1] = {
    w = 32,
    label = "voice",
    action = function() view:toggle_voice() end,
    draw = function(cx, cy, ink2) g:text(cx, cy - 7.5, "v2", { color = ink2, size = 12, align = "center" }) end,
  }
  for _, d in ipairs({ "p", "mf", "f" }) do
    dynamics[#dynamics + 1] = { w = 32, label = d, action = function() paw.cmd("notation.dyn", { d }) end }
  end
  dynamics[#dynamics + 1] = {
    w = 28,
    label = "cresc",
    action = function() paw.cmd("notation.cresc") end,
    draw = function(cx, cy, ink2) g:poly({ cx + 8, cy - 4, cx - 8, cy, cx + 8, cy + 4 }, { color = ink2, width = 1.4 }) end,
  }
  dynamics[#dynamics + 1] = {
    w = 28,
    label = "dim",
    action = function() paw.cmd("notation.dim") end,
    draw = function(cx, cy, ink2) g:poly({ cx - 8, cy - 4, cx + 8, cy, cx - 8, cy + 4 }, { color = ink2, width = 1.4 }) end,
  }
  return { { { w = #name * 7 + 22, label = name, fill = colour } }, values, accidentals, shapes, dynamics }
end

local function toolbar(g, w, rows)
  g:rect(0, 0, w, gui.bar_h, { fill = c.panel })
  for r, row in ipairs(rows) do
    local y = 6 + (r - 1) * BAR_ROW
    for gi, placed in ipairs(row) do
      local x = placed.x
      for _, b in ipairs(placed.group) do
        button(g, x, y, b)
        x = x + b.w + 5
      end
      if gi > 1 then g:rect(placed.x - BAR_GAP / 2 - 0.5, y + 3, 1, BTN - 6, { fill = c.text_3 }) end
    end
  end
  button(g, w - 40, 6, { w = 30, label = "+", action = function() gui.zoom(1) end })
  button(g, w - 75, 6, { w = 30, label = "−", action = function() gui.zoom(-1) end })
end

--- What the info line says: the note under the cursor, a diagnostic
--- there, or what the pointer does.
function view:status_text()
  local clip = self:clip()
  if not clip then return "" end
  local note, index, written = self:note()
  local diag = paw.diagnostic
  if diag and diag.get then
    for _, d in ipairs(diag.get(clip.id)) do
      local inside = self.beat >= d.at - EPS and self.beat < d.at + max(d.length, EPS) + EPS
      local about = false
      for _, place in ipairs(index and diag.places(d) or {}) do
        about = about or place == index
      end
      if about or (inside and not index) then return d.message end
    end
  end
  if note then
    return string.format(
      "%s  played at %s, %.2f beats long, velocity %d",
      model.name(written),
      paw.time.format(clip.start + note.start),
      note.length,
      note.velocity
    )
  end
  self:layout()
  if paw.keymap.mode == "i" then
    return "click the staff to enter a "
      .. (self.dot and "dotted " or "")
      .. model.NAMES[self.value]
      .. " there · letters enter notes · Esc ends"
  end
  if gui.rest then
    return "rest: click the staff to clear a " .. model.NAMES[self.value] .. (self.dot and " dotted" or "") .. " there"
  end
  return "click a note to choose it, drag it to move it · double click enters notes there · right click for more · Ctrl+wheel zooms"
end

--- Keep the cursor (or, while playing, the playhead) in view: its system
--- in the wrapped page, a third of the way across in the galley.
local function follow(eng, area, layout)
  local playing = api.transport_get().playing
  local beat = view:follow_beat()
  local sys, x = at_beat(eng, beat)
  if playing then gui.follow = true end
  if sys and gui.follow ~= false then
    local view_h = area.bottom - area.top
    if sys.y - gui.scroll < 0 then gui.scroll = sys.y end
    if sys.y + sys.height - gui.scroll > view_h then gui.scroll = sys.y + sys.height - view_h end
    if view.galley then
      local span = area.width - sys.x0
      if playing then
        gui.hscroll = x - sys.x0 - span / 3
      elseif x - gui.hscroll < sys.x0 + eng.style.sp * 2 or x - gui.hscroll > area.width - eng.style.sp * 2 then
        gui.hscroll = x - sys.x0 - span / 3
      end
    end
  end
  gui.scroll = util.clamp(gui.scroll, 0, max(0, eng.total - (area.bottom - area.top)))
  local last = eng.systems[#eng.systems]
  gui.hscroll = view.galley
      and util.clamp(gui.hscroll, 0, max(0, (last and last.width or 0) - area.width + eng.style.sp * 2))
    or 0
  gui.follow = true
end

function view:paint(g, ctx)
  local w, h = ctx.width, ctx.height
  local chrome = not ctx.surface
  gui.hits:clear()
  gui.buttons = gui.hits.list
  gui.heads = {}
  gui.size = { w = w, h = h, chrome = chrome }
  if chrome then g:rect(0, 0, w, h, { fill = ctx.bg or c.surface }) end
  local clip = self:clip()
  if not clip then
    g:text(24, 24, "No clip is open as notation.", { color = ctx.fg or c.text, size = 16, bold = true })
    g:text(
      24,
      50,
      "Right click a MIDI clip and choose Open as notation, or put the cursor on one and type "
        .. paw.keymap.human("<localleader>n")
        .. ".",
      { color = c.text_2 }
    )
    return
  end
  local data = clip:get()
  local part = api.part_get(data.part)
  local colour = paw.draw.part_colour(part)
  -- The clip's staff, or the score it is a staff of (`view:frame`).
  local F = self:frame()
  local layout = F.layout
  local st = style_for(ctx)
  local rows
  if chrome then
    rows = bar_rows(bar_groups(g, data.name, colour), w)
    gui.bar_h = bar_height(rows)
  end
  local area = { top = chrome and gui.bar_h or 0, bottom = h - (chrome and INFO or 0), width = w }
  local eng = self:engrave(layout, w, st, 0)
  gui.engraved, gui.area = eng, area
  follow(eng, area, layout)

  g:layer("ink")
  page_ink(g, eng, layout, area)

  local _, under_index = self:note()
  local selection = ctx.focused and paw.keymap.selection()
  if F.multi then
    g:layer("staves")
    draw_staves(g, eng, layout, F, area)
  end
  g:layer("selection")
  if selection and selection.view == "notation" then draw_selection(g, eng, layout, F, selection, area) end
  g:layer("ghost")
  draw_ghosts(g, eng, layout, clip, area, F)
  g:layer("diagnostic")
  draw_diagnostics(g, eng, layout, clip, area, F)
  g:layer("caret")
  if ctx.focused then draw_caret(g, eng, layout, area, under_index, paw.keymap.mode == "i", F) end
  local drag = gui.drag
  if drag and drag.moved and drag.to_beat then
    lone_head(g, eng, layout, drag.to_beat + F.off, drag.to_step, alpha(st.accent, 0.8), 1, area, nil, F)
  end
  if gui.box then
    local b = gui.box
    local x0, y0 = min(b.x0, b.x1), min(b.y0, b.y1)
    g:rect(x0, y0, abs(b.x1 - b.x0), abs(b.y1 - b.y0), { fill = alpha(st.accent, 0.12), stroke = st.accent, width = 1 })
  end
  g:layer("playhead")
  if ctx.marks then
    ctx.marks[#ctx.marks + 1] = playhead_mark(eng, layout, F, area, w, h)
  else
    draw_playhead(g, eng, layout, F, area)
  end
  -- A popover is drawn under the caret's system, so that the staff and what
  -- it previews stay in sight (at the foot of the page when the system
  -- reaches it); `paint` takes the line its box ends on.
  local popover = view.popover
  if popover and popover.active() then
    local sys, x = at_beat(eng, view.beat + F.off)
    if sys then
      local foot = engrave.y_of(st, sys, F.base + F.count, 0) + 3 * st.sp + area.top - gui.scroll
      g:layer("popover")
      popover.paint(
        g,
        x + (view.galley and -gui.hscroll or 0),
        math.min(math.max(area.top + 26, foot + 24), h - INFO - 2),
        w,
        c
      )
    end
  end

  if chrome then
    toolbar(g, w, rows)
    local fifths = layout.fifths
    local key_text = view.key_name(fifths, select(2, view.key()), clip and clip.start)
    gui.key_text = key_text
      .. "  ·  "
      .. layout.meter.num
      .. "/"
      .. layout.meter.den
      .. "  ·  "
      .. part.name
      .. (F.multi and ("  ·  staff " .. (F.base + 1) .. " of " .. #layout.staves) or "")
      .. (view.raw_view() and "  ·  raw" or "")
      .. (view.galley and "  ·  galley" or "")
      .. (view.page and (view.parts and view.parts.check and "  ·  pages, to check" or "  ·  pages") or "")
    local iy = h - INFO
    g:rect(0, iy, w, INFO, { fill = c.control })
    g:text(12, iy + 6, self:status_text(), { color = c.text_2, width = w - 260 })
    g:text(w - 12, iy + 6, gui.key_text, { color = c.text_2, align = "right", width = 240 })
  end
end

-- The pointer ----------------------------------------------------------------------------------

--- What is at a point of the paint: the system, staff, measure, the beat
--- and the staff step there, in the clip's beats and staves. The beat is
--- on the chosen value within the beat (`view:snap`, in `notation.tui`),
--- or with `fine` on the grid. In a score, a point on another staff makes
--- that staff the active one with `activate`, and is nothing without it.
function view:locate(x, y, fine, activate)
  local eng, area = gui.engraved, gui.area
  local F = self:frame()
  local layout = F and F.layout
  if not (eng and layout and area) then return nil end
  local st = eng.style
  local py = y - area.top + gui.scroll
  local px = x + (view.galley and gui.hscroll or 0)
  for _, sys in ipairs(eng.systems) do
    if py >= sys.y and py < sys.y + sys.height then
      -- The nearer staff.
      local staff, best = 1, math.huge
      for k = 1, #layout.staves do
        local mid = engrave.y_of(st, sys, k, 4)
        if abs(py - mid) < best then
          staff, best = k, abs(py - mid)
        end
      end
      local pos = floor((engrave.y_of(st, sys, staff, 0) - py) / (st.sp / 2) + 0.5)
      local step = model.CLEF_BOTTOM[layout.staves[staff]] + pos
      local beat, measure
      for _, placed in ipairs(sys.measures) do
        local m = placed.m
        if px >= placed.x and px < placed.x + placed.p.width then
          beat, measure = self:snap(m, model.t_of(placed.p, px - placed.x) - m.start, fine) + m.start, m
        end
      end
      if not self:onto_staff(F, staff, nil, activate, beat) then return nil end
      F = self:frame()
      return {
        sys = sys,
        staff = staff - F.base,
        step = step - F.dstep,
        beat = beat and beat - F.off,
        measure = measure,
      }
    end
  end
end

local function head_at(x, y)
  local eng = gui.engraved
  local s = eng and eng.style.sp or 10
  local best, dist
  for _, hd in ipairs(gui.heads) do
    local d = abs(hd.x - x) / (0.9 * s) + abs(hd.y - y) / (0.5 * s)
    if abs(hd.x - x) <= 0.9 * s and abs(hd.y - y) <= 0.5 * s and (not dist or d < dist) then
      best, dist = hd, d
    end
  end
  return best
end

-- What a gesture does is the same on the paper and in the terminal's cells
-- (`notation.tui`): these take a place (`at`: its `beat`, `step`, `staff`).

--- Enter a note of the chosen value at a place, as a click in insert mode does.
function view:enter_at(at)
  local length = self:entry_length()
  self.beat, self.step = max(0, at.beat), at.step
  if gui.rest then return self:rest(max(0, at.beat), length, at.staff) end
  local fifths = view.key()
  local pitch, spell
  if gui.accidental then
    pitch = model.pitch_of(at.step, gui.accidental)
    spell = model.spelled(at.step % 7, gui.accidental, pitch)
  else
    pitch = model.key_pitch(at.step, fifths)
  end
  self:place(pitch, at.beat, length, nil, spell)
  self:audition(pitch)
  self.last = { step = at.step, pitch = pitch, beat = at.beat }
end

--- The menu a right click opens: for the note under the pointer
--- (`on_note`), else for the place `at`.
function view:menu_items(on_note, at)
  local items = {}
  local function add(label, keys, run) items[#items + 1] = { label = label, keys = keys, run = run } end
  if on_note then
    add("Delete the note", "x", function() self:delete() end)
    add("Delete the chord", "X", function() self:delete_chord() end)
    add("Sharpen", "Ctrl-a", function() self:inflect(1) end)
    add("Flatten", "Ctrl-x", function() self:inflect(-1) end)
    add("Respell", "g~", function() self:respell() end)
    items[#items + 1] = "-"
    for _, kind in ipairs({ "staccato", "accent", "tenuto", "marcato" }) do
      add(kind:sub(1, 1):upper() .. kind:sub(2), nil, function() view.marks.toggle_art(kind, self:chord_indices()) end)
    end
    add("Into the other voice", "gV", function() self:toggle_voice() end)
    add("Triplets on this beat", paw.keymap.human("<localleader>3"), function() self:toggle_tuplet() end)
  else
    add("Enter a " .. model.NAMES[self.value] .. " here", "Enter", function()
      if at and at.beat then self:enter_at(at) end
    end)
    add("Rest here", "r", function()
      if at and at.beat then self:rest(at.beat, self:entry_length(), at.staff) end
    end)
    add("Paste here", "P", function() paw.keymap.normal("P") end)
  end
  items[#items + 1] = "-"
  add(view.galley and "Wrapped systems" or "One long system (galley)", "zg", function()
    view.galley, view.page = not view.galley, false
  end)
  add(view.page and "Systems without pages" or "Pages (page view)", "zp", function()
    view.page, view.galley = not view.page, false
  end)
  return items
end

--- Move a written note (the one the clip's note at `index` plays) to a
--- line or space and a beat, as a drag of it does: up or down the staff it
--- keeps its distance from the key (a sharp stays a sharp); in time it is
--- written there in its voice, as long as it was, over what that voice has
--- there (a note of a chord leaves the chord, and goes where a voice is free).
function view:move_note(index, note, step, beat)
  local clip = self:editable()
  if not clip then return end
  local D = require("notation.doc")
  local played = clip:notes()[index] or note
  if not (played and played.id) then return end
  local id = "n" .. played.id
  local fifths = view.key()
  local pitch
  self:write(function(sc)
    local n, ev, _, entry = D.find_note(sc, id)
    if not n then return false end
    local bend = n.alter - model.key_alter(n.step, fifths)
    local alter = model.key_alter(step % 7, fifths) + bend
    pitch = util.clamp(model.pitch_of(step, alter), 0, 127)
    local sp = model.spelled(step % 7, alter, pitch)
    local moved = { id = id, step = sp.letter, alter = sp.alter, octave = sp.octave }
    local alone = #ev.notes == 1
    local was = alone and view.lift(sc, ev.id)
    local links = not alone and view.chain(sc, ev.id)
    local f = D.frame(sc)
    local len = was and was.len
    if not alone then
      local last = links[#links]
      len = f.starts[last.mi] + last.at + D.length(last.ev) - (f.starts[links[1].mi] + links[1].at)
      for _, c in ipairs(D.tied_on(sc, entry.staff, entry.voice, id)) do
        D.remove_note(sc, c.note.id)
      end
      D.remove_note(sc, id)
    end
    local t = math.max(0, D.from_beats(beat) - D.origin(sc))
    local staff = #sc.staves == 2 and sc.staves[self:staff_of_step(step)].id or entry.staff
    if was then
      was.notes = { moved }
      view.drop(sc, was, t, len, staff, entry.voice)
    elseif not view.add_sounding(sc, moved, t, len, staff) then
      paw.notify("no voice free there: the note is not written", "warn")
      return false
    end
  end)
  self:set(step, beat)
  if pitch and pitch ~= note.pitch then self:audition(pitch) end
end

local function context_menu(self, hd, at, e)
  if paw.ui.menu then
    local cell = paw.canvas.cell
    paw.ui.menu(
      self:menu_items(hd ~= nil, at),
      { x = e.col or floor((e.x or 0) / cell.w), y = e.row or floor((e.y or 0) / cell.h) }
    )
  end
end

function view:pointer(e)
  local clip = self:clip()
  if not clip or not gui.size then return end
  local chrome = gui.size.chrome
  if e.kind == "wheel" then
    if e.ctrl then
      gui.zoom((e.dy or 0) > 0 and 1 or -1)
    elseif view.galley then
      gui.hscroll = max(0, gui.hscroll - (e.dy or 0) - (e.dx or 0))
      gui.follow = false
    else
      gui.scroll = max(0, gui.scroll - (e.dy or 0))
      gui.follow = false
    end
    return
  end
  if chrome and e.kind == "down" and e.y < gui.bar_h then
    local b = gui.hits:under(e.x, e.y)
    if b then return b.down() end
    return
  end
  local inserting = paw.keymap.mode == "i"
  if e.kind == "hover" then
    gui.gesture = nil
    local at = self:locate(e.x, e.y, e.alt)
    gui.hover = inserting and at and at.beat and { beat = at.beat, step = at.step } or nil
    return
  end
  local in_page = not chrome or e.y < gui.size.h - INFO
  if (e.kind == "down" or e.kind == "double") and in_page then
    -- A click on another staff of a score makes it the active one first:
    -- its note's (a condensed staff's player too), else the staff's.
    local hd = head_at(e.x, e.y)
    if hd then
      local F = self:frame()
      self:onto_staff(F, hd.staff, hd.player, true, nil, hd.clip)
      F = self:frame()
      hd = util.merge(hd, { start = hd.start - F.off, step = hd.step - F.dstep })
    end
    local at = self:locate(e.x, e.y, e.alt, true)
    if self:readonly() then return end
    if e.button == "right" then
      if hd then
        self:set(hd.step, max(0, hd.start))
      elseif at and at.beat then
        self:set(at.step, at.beat)
      end
      return context_menu(self, hd, at, e)
    end
    if e.kind == "double" then
      -- Enter notes from here. A frontend may say so before the second
      -- click's own `down`, which is not a click in insert mode.
      if at and at.beat then self:set(at.step, at.beat) end
      self.last, self.chord = nil, nil
      gui.gesture = { x = e.x, y = e.y }
      paw.keymap.set_mode("i")
      return
    end
    local second = gui.gesture and abs(gui.gesture.x - e.x) < 4 and abs(gui.gesture.y - e.y) < 4
    gui.gesture = nil
    if second then return end
    if inserting or gui.rest then
      if at and at.beat and at.beat >= 0 then self:enter_at(at) end
      return
    end
    if e.shift then
      -- Stretch a selection from the cursor to here.
      if paw.keymap.mode ~= "x" then paw.keymap.visual_start("v") end
      if hd then
        self:set(hd.step, max(0, hd.start))
      elseif at and at.beat then
        self:set(at.step, at.beat)
      end
      return
    end
    if paw.keymap.mode == "x" then paw.keymap.set_mode("n") end
    if hd then
      self:set(hd.step, max(0, hd.start))
      local note = self:clip():notes()[hd.index]
      if note then self:audition(note.pitch) end
      -- A drag moves it on the grid, from where it was taken.
      local from = self:locate(e.x, e.y, true)
      gui.drag = {
        index = hd.index,
        from_step = hd.step,
        from_beat = from and from.beat or hd.start,
        start = hd.start,
        note = note,
        moved = false,
      }
    elseif at and at.beat then
      self:set(at.step, at.beat)
      gui.box = { x0 = e.x, y0 = e.y, x1 = e.x, y1 = e.y, at = at }
    end
    return
  end
  if gui.box then
    local b = gui.box
    if e.kind == "move" then
      b.x1, b.y1 = e.x, e.y
      if not b.started and (abs(b.x1 - b.x0) > 4 or abs(b.y1 - b.y0) > 4) then
        b.started = true
        paw.keymap.visual_start("b")
      end
      local at = self:locate(e.x, e.y, true)
      if b.started and at and at.beat then self:set(at.step, at.beat) end
    elseif e.kind == "up" then
      gui.box = nil
    end
    return
  end
  local drag = gui.drag
  if not drag then return end
  if e.kind == "move" then
    local at = self:locate(e.x, e.y, true)
    if at and at.beat then
      drag.to_beat = max(0, drag.start + at.beat - drag.from_beat)
      drag.to_step = at.step
      drag.moved = drag.moved or at.step ~= drag.from_step or abs(at.beat - drag.from_beat) > EPS
    end
  elseif e.kind == "up" then
    gui.drag = nil
    if not (drag.moved and drag.to_beat and drag.note) then return end
    self:move_note(drag.index, drag.note, drag.to_step, drag.to_beat)
  end
end

--- Closing the window gives the keyboard back to the window before, and
--- leaving the view from the keyboard closes the window.
function view:on_close()
  gui.drag, gui.box, gui.hover = nil, nil, nil
  paw.ui.hide("notation")
end

function view:on_hide()
  if paw.canvas and paw.canvas.open_views.notation then paw.canvas.close("notation") end
end

return gui
