-- The staff in the terminal, for terminals that cannot show the engraved
-- page: lines that run unbroken from the clef to the system's end, joined by
-- the barlines; heads filled or open, stems, flags and beams, rests that
-- look like rests, ties and slurs as arcs; measures packed into as many
-- systems as the panel has room for, from the first measure scrolled to.
-- At the usual zoom the staff is dense, a row for each line and the spaces
-- between rows (`notation.cells`); zoomed in (`zi`) every line and space has
-- a row of its own.
local api = paw.api
local util = paw.util
local model = require("notation.model")
local cells = require("notation.cells")
local breaks = require("notation.breaks")
local engrave = require("notation.engrave")
local view = require("notation")

local floor = math.floor
local EPS = 1e-6

view.zoom = 1 -- how wide the terminal spaces notes: 1 gives a sixteenth three columns; above 1 the staff is open too

-- Where a key signature's sharps and flats go, on each clef.
local function key_positions(fifths, clef) return model.key_positions(fifths, clef) end
view.key_positions = key_positions

local room_for_changes, draw_directions

--- Whether the staff is drawn dense: lines on rows, spaces between them.
--- ASCII has no half blocks to put a head between two rows.
function view.dense() return view.zoom <= 1 and not paw.opt.ascii end

local function unit(d)
  -- A head is two cells wide: at least one clear after it.
  return 1 + math.max(2, floor(2 * view.zoom * math.sqrt(d / 0.25) + 0.5))
end

--- How the panel is divided: rows above and below each staff (`lines` rows
--- for its own lines), the rows of a system, and how many systems fit.
local function rows_for(height, staves, extra, lines, most)
  local best
  extra = extra or 0
  for margin = most, 1, -1 do
    local per = staves * (lines + 2 * margin) + (type(extra) == "function" and extra(margin) or extra)
    -- The last system may lose a little of the room under it.
    local systems = floor((height + margin - 1) / per)
    -- More systems win; between as many, more room above and below.
    if systems >= 1 and (not best or systems > best[3]) and (margin >= 3 or not best) then
      best = { margin, per, systems }
    end
  end
  if best then return best[1], best[2], best[3] end
  return 1, staves * (lines + 2) + (type(extra) == "function" and extra(1) or extra), 1
end

--- Systems `width` wide from the one that holds measure `first`: broken
--- as the engraved page is (`notation.breaks`), balanced over the whole
--- clip, where the score asks for breaks too. Returns them and the last
--- measure they show.
local function pack(layout, first, width, systems, prefix)
  local widths = {}
  for i, m in ipairs(layout.measures) do
    widths[i] = m.width + 1
  end
  local starts = breaks.lines(widths, prefix, width, engrave.asked(layout))
  local k = 1
  while starts[k + 1] and starts[k + 1] <= first do
    k = k + 1
  end
  local out, last = {}, starts[k] - 1
  for s = k, math.min(#starts, k + systems - 1) do
    local row = { measures = {}, prefix = prefix(starts[s]) }
    local x = row.prefix
    last = (starts[s + 1] or #layout.measures + 1) - 1
    for j = starts[s], last do
      row.measures[#row.measures + 1] = { m = layout.measures[j], x = x }
      x = x + layout.measures[j].width + 1
    end
    row.width = x
    out[#out + 1] = row
  end
  return out, last
end

--- The column of a beat of measure `index` in a system, if the system has it.
local function x_in(sys, index, beat)
  for _, placed in ipairs(sys.measures) do
    if placed.m.index == index then return placed.x + floor(model.x_of(placed.m, beat) + 0.5) end
  end
end

--- Text with its spaces left out, so that what is under them shows.
local function ink(buf, x, y, text, style)
  local col = x
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if ch ~= " " then buf:text(col, y, ch, style) end
    col = col + 1
  end
end

--- A head at step `pos`: in one cell on a row, across two rows in a space
--- of the dense staff.
local function head(buf, G, R, x, pos, hollow, style)
  if R.step == 1 or pos % 2 == 0 then
    buf:text(x, R.above(pos), hollow and G.hollow or G.filled, style)
  else
    local pair = hollow and G.hollow_space or G.filled_space
    buf:text(x, R.above(pos), pair[1], style)
    buf:text(x, R.below(pos), pair[2], style)
  end
end

--- Ledger lines from the staff out to step `pos`, centred on column `x`.
local function ledgers(buf, G, R, x, pos, style)
  for p = -2, pos, -2 do
    buf:text(x - 1, R.above(p), G.ledger, style)
  end
  for p = 10, pos, 2 do
    buf:text(x - 1, R.above(p), G.ledger, style)
  end
end

--- An arc from column `x0` to `x1` on row `y` (ties and slurs); `open`
--- when it goes on into the next system.
local function arc(buf, set, x0, x1, y, style, open)
  if x1 < x0 then return end
  if x1 == x0 then return buf:text(x0, y, set[2], style) end
  buf:text(x0, y, set[1], style)
  for x = x0 + 1, x1 - 1 do
    buf:text(x, y, set[2], style)
  end
  buf:text(x1, y, open and set[2] or set[3], style)
end

--- Room at the start of a measure for a clef or key that changes there.
room_for_changes = function(layout)
  for i, m in ipairs(layout.measures) do
    local extra = 0
    if m.clef_change then extra = extra + 3 + (m.repeat_start and 2 or 0) end
    if m.key_change and i > 1 then
      extra = extra + math.max(1, math.abs(m.fifths or 0), m.fifths == 0 and math.abs(m.key_from or 0) or 0) + 1
    end
    if extra > 0 then
      for _, slot in ipairs(m.slots) do
        slot.x = slot.x + extra
      end
      m.width = m.width + extra
    end
  end
end

local ORN = { trill = "tr", mordent = "∿", prall = "∿", turn = "∾", turn_inverted = "∾", tremolo = "≡" }
local ORN_ASCII = { trill = "tr", mordent = "~", prall = "~", turn = "S", turn_inverted = "S", tremolo = "///" }

--- What a measure says besides its notes, in cells: clef and key changes
--- at its start, double and final barlines and endings, rehearsal marks,
--- tempo, chord symbols and techniques over the staff, ornaments and
--- fermatas over chords, the lyrics of later verses. `inside`: not the
--- system's first measure (whose clef and key the system's start says).
draw_directions = function(buf, layout, m, inside, o)
  local G, ink = o.G, o.note_style
  local ascii = paw.opt.ascii
  -- Over the first staff: the bar number's row for endings, rehearsal
  -- marks and tempo; the row under it for chord symbols and techniques.
  local top_row = o.top + math.max(0, o.margin - 2)
  local text_row = top_row + (o.margin > 1 and 1 or 0)
  -- After a start repeat's barline and dots.
  local x = o.mx + (m.repeat_start and 2 or 0)
  local before = layout.measures[m.index - 1]
  for s, clef in ipairs(layout.staves) do
    local R = o.rows[s]
    clef = m.clefs and m.clefs[s] or clef
    if m.clef_change and m.clef_change[s] and inside then
      for _, r in ipairs(cells.small_clef(clef)) do
        buf:text(x, R.above(r[1]), r[2], ink)
      end
    end
    if m.key_change and m.index > 1 and inside then
      local kx = x + (m.clef_change and 3 or 0)
      local from, fifths = m.key_from or 0, m.fifths or 0
      if fifths == 0 or (from ~= 0 and (from > 0) ~= (fifths > 0)) then
        for i, pos in ipairs(key_positions(from, clef)) do
          buf:text(kx + i - 1, R.above(pos), G.acc[0], ink)
        end
        kx = kx + math.abs(from)
      end
      for i, pos in ipairs(key_positions(fifths, clef)) do
        buf:text(kx + i - 1, R.above(pos), G.acc[fifths > 0 and 1 or -1], ink)
      end
    end
    if m.barline == "||" or m.barline == "|." then
      for y = R.above(8), R.above(0) do
        buf:text(
          o.bx,
          y,
          m.barline == "||" and G.repeat_bar or (ascii and "#" or "┃"),
          m.ghost and ink or o.bar_style
        )
      end
    end
  end
  local used = x + #tostring(m.number) + 1
  if m.rehearsal then
    used = used
      + buf:text(used, top_row, "[" .. m.rehearsal .. "]", m.ghost and ink or { fg = o.colour, bold = true })
      + 1
  end
  if m.volta then
    -- The ending's number where it starts; its line over every bar of it.
    local label = (before and before.volta == m.volta and inside) and "" or (m.volta .. ".")
    local corner = label ~= "" and G.bracket_over[1] or G.bracket_over[2]
    buf:text(used, top_row, corner .. label, ink)
    for vx = used + 1 + #label, o.bx - 1 do
      buf:text(vx, top_row, G.bracket_over[2], ink)
    end
  end
  for _, mk in ipairs(m.marks or {}) do
    local mx = o.xt(mk.at)
    local style = (m.ghost or mk.ghost) and "ExGhost"
    if mk.kind == "tempo" then
      local label = mk.value:gsub("q(%.?)%s*=%s*", (ascii and "q" or "♩") .. "%1=")
      if not mk.change and mk.bpm and not label:find("=") then
        label = label .. (ascii and " q=" or " ♩=") .. math.floor(mk.bpm + 0.5)
      end
      buf:text(math.max(mx, used), top_row, label, style or { fg = o.colour, bold = true })
    elseif mk.kind == "chord" then
      buf:text(mx, text_row, mk.value, style or { fg = o.colour, bold = true })
    elseif mk.kind == "technique" then
      buf:text(mx, text_row, mk.value, style or { fg = o.colour, italic = true })
    elseif mk.kind == "dyn" and mk.subito then
      buf:text(
        mx + #mk.value + 1,
        math.min(o.band(1) + o.staff_rows - 1, o.bottom),
        "sub.",
        style or { fg = o.colour, italic = true }
      )
    elseif (mk.kind == "cresc" or mk.kind == "dim") and mk.niente then
      local at = mk.kind == "cresc" and mx or (mk.to >= m.start + m.length - EPS and o.bx - 1 or o.xt(mk.to))
      buf:text(at, math.min(o.band(1) + o.staff_rows - 1, o.bottom), "o", style or ink)
    end
  end
  for s in ipairs(layout.staves) do
    local R = o.rows[s]
    for _, ev in ipairs(m.staves[s] or {}) do
      local src = ev.source
      if ev.kind == "note" and src then
        local art = src.art or {}
        local top = ev.notes[#ev.notes].pos
        local above = math.max(top + 2 * R.step, (ev.stem or 0) > 0 and top + 6 * R.step or 10)
        local fermata = art.fermata or art.fermata_long or art.fermata_short
        if src.orn then
          buf:text(o.xt(ev.start), R.above(above), (ascii and ORN_ASCII or ORN)[src.orn] or src.orn, ink)
          above = above + 2
        end
        if fermata then buf:text(o.xt(ev.start), R.above(above), ascii and "U" or "⌒", ink) end
        if s == 1 then
          for verse, text in ipairs(src.lyrics or {}) do
            local y = o.band(1) + o.staff_rows - (#layout.staves == 2 and 1 or 2) + verse
            if text ~= "" and y <= o.bottom then buf:text(o.xt(ev.start), y, text, "Normal") end
          end
        end
      end
    end
  end
end

function view:render(buf, ctx)
  local w, h = buf.width, buf.height
  local clip = self:clip()
  buf:fill(0, 0, w, h, " ", "Normal")
  if not clip then
    paw.ui.titlebar(buf, { name = "Notation", focused = ctx.focused })
    if self.gone then
      buf:text(2, 2, "The clip shown here is gone: undone or deleted. Ctrl-r brings it back.", "Empty")
      return
    end
    local x = 2 + buf:text(2, 2, "No clip open. Put the cursor on a MIDI clip in the arrange view and press", "Empty")
    x = x + 1 + buf:text(x + 1, 2, paw.ui.keybar.show("<localleader>n"), "EmptyKey")
    buf:text(x + 1, 2, "or :notation.", "Empty")
    return
  end
  local c = clip:get()
  local part = api.part_get(c.part)
  local hue = paw.draw.part_hue(part)
  local colour = paw.draw.part_colour(part)
  -- The clip's own staff, or the score it is a staff of: the cursor's
  -- staff is the active one, drawn in full ink with a mark at its start.
  local F = self:frame()
  local layout = F.layout
  model.space(layout, { lead = 2, acc = 1, grace = 2, tail = 1, unit = unit })
  room_for_changes(layout)
  self.caret_cell = nil
  local fifths, stored = view.key()
  local inserting = ctx.focused and paw.keymap.mode == "i"
  local G = cells.glyphs()
  local dense = view.dense()
  local step = dense and 2 or 1 -- staff steps a row
  local lines = dense and 5 or 9 -- rows from the top line to the bottom one
  -- A grand staff in a panel too low for both staves: the cursor's staff alone.
  local only
  if #layout.staves == 2 and h - 1 < 2 * (lines + 2 * (dense and 2 or 1)) then
    only = F.base + self:cursor_staff()
    local full = layout
    local measures = {}
    for i, m in ipairs(full.measures) do
      measures[i] = setmetatable({ staves = { m.staves[only] } }, { __index = m })
    end
    layout = setmetatable({ staves = { full.staves[only] }, measures = measures }, { __index = full })
  end
  -- Nothing drawn over the title row or below the panel.
  local real = buf
  buf = setmetatable({
    text = function(_, bx, by, ...)
      if by < 1 or by >= h then return 0 end
      return real:text(bx, by, ...)
    end,
    fill = function(_, bx, by, bw, bh, ...)
      local y0, y1 = math.max(by, 1), math.min(by + bh, h)
      if y1 > y0 then return real:fill(bx, y0, bw, y1 - y0, ...) end
    end,
  }, {
    __index = function(_, k)
      local v = real[k]
      if type(v) == "function" then
        return function(_, ...) return v(real, ...) end
      end
      return v
    end,
  })

  -- Title: the clip, its part, where the cursor is, what will be entered.
  local under = self:note()
  local _, _, written = self:note()
  -- The note under the piano roll's cursor, when the two are bound in time.
  local partner = require("notation.roll").partner_place()
  -- In a transposed part, the name as written.
  local wf = fifths + F.dfifths
  local here = written and model.name(written) or model.name(model.spell(model.key_pitch(self.step + F.dstep, wf), wf))
  local value = (model.NAMES[self.value] or "?") .. (self.dot and " dotted" or "")
  local clip = self:clip()
  local keyname = view.key_name(fifths, stored, clip and clip.start)
  local extra = (
    layout.labels and ("  " .. view.score_name() .. ", staff " .. (F.base + 1) .. " of " .. #layout.staves) or ""
  )
    .. (layout.part_name and ("  part: " .. layout.part_name) or "")
    .. (self.parts and self.parts.check and ", to check" or "")
    .. (view.raw_view() and "  raw" or "")
    .. ((self.voice or 1) > 1 and ("  voice " .. self.voice) or "")
    .. (only and ("  " .. (only == 1 and "right hand" or "left hand") .. " (low panel)") or "")
  -- How letters write: overwriting (as entered), pushing later music
  -- along, re-pitching what is there; and a tuplet or grace note to come.
  -- The title's right side stands clear of it.
  local badge
  if inserting then
    local tp = self:entry_tuplet()
    local how = self.repitch and " REPITCH " or self.push and " PUSH " or " INS "
    badge = how
      .. value
      .. (tp and (" " .. tp[1] .. ":" .. tp[2]) or "")
      .. (self.grace and (" " .. self.grace) or "")
      .. " "
  end
  local right = (badge and "" or value .. "  ")
    .. keyname
    .. "  "
    .. layout.meter.num
    .. "/"
    .. layout.meter.den
    .. extra
  paw.ui.titlebar(real, {
    pill = { c.name, hue.pill },
    name = part.name,
    focused = ctx.focused,
    context = string.format("%s  %s", here, paw.time.format(c.start + self.beat)),
    right = right .. (badge and string.rep(" ", api.str_width(badge) + 1) or ""),
  })
  if badge then real:text(math.max(0, w - api.str_width(badge) - 1), 0, badge, "RulerInsert") end
  -- Where the terminal shows images, the engraved page (gui.lua) below the title.
  if real:surface(0, 1, w, h - 1) then return end

  -- Room: systems of staves down the panel.
  local staves = #layout.staves
  local tab = layout.tab
  -- Tablature goes below the lowest note and stem of the last staff, in rows.
  local tab_room = 0
  if tab then
    for _, m in ipairs(layout.measures) do
      for _, ev in ipairs(m.staves[staves] or {}) do
        for _, n in ipairs(ev.notes or {}) do
          tab_room = math.max(tab_room, math.ceil(-(n.pos - ((ev.stem or 0) < 0 and 4 or 0)) / step))
        end
      end
    end
  end
  local stem_len = dense and 6 or 5
  -- Notes low under the last staff, their stems down, take rows of their
  -- own under it, so that they do not run into the next system.
  local below = 0
  if not tab then
    for _, m in ipairs(layout.measures) do
      for _, ev in ipairs(m.staves[staves] or {}) do
        if ev.kind == "note" then
          local low = math.huge
          for _, n in ipairs(ev.notes or {}) do
            low = math.min(low, n.pos)
          end
          if (ev.stem or 0) < 0 and (ev.base or 1) < 4 then low = math.min(low - stem_len, 4) end
          below = math.max(below, math.ceil(-low / step))
        end
      end
    end
  end
  local extra = tab and (tab.strings + 1 + math.max(0, tab_room - 1))
    or function(margin) return math.max(0, below - margin) end
  local margin, per, systems = rows_for(h - 1, staves, extra, lines, dense and (staves == 2 and 2 or 3) or 4)
  if tab then tab_room = math.max(0, tab_room - margin) end
  local staff_rows = lines + 2 * margin
  -- Columns: a brace before a grand staff, the system's left edge, the
  -- clef, the key, the time.
  local edge = staves == 2 and 1 or 0
  local clef_w = 0
  for _, clef in ipairs(layout.staves) do
    clef_w = math.max(clef_w, cells.clef_width(clef))
  end
  local key_x = edge + 2 + clef_w
  local function meter_changes(i)
    local m, before = layout.measures[i], layout.measures[i - 1]
    return i == 1 or (before and before.meter ~= m.meter)
  end
  local function prefix(i)
    local p = key_x + math.abs(layout.measures[i].fifths or fifths) + 1
    if meter_changes(i) then
      local meter = layout.measures[i].meter
      p = p + math.max(#tostring(meter.num), #tostring(meter.den)) + 1
    end
    return p
  end
  -- Scroll by whole measures to keep the cursor's measure on screen.
  local _, cursor_measure = self:measure_at(self:follow_beat() + F.off, layout)
  if cursor_measure < self.first then self.first = cursor_measure end
  self.first = util.clamp(self.first, 1, #layout.measures)
  local rows_out, last = pack(layout, self.first, w, systems, prefix)
  while cursor_measure > last and self.first < cursor_measure do
    self.first = self.first + 1
    rows_out, last = pack(layout, self.first, w, systems, prefix)
  end

  local note_style = { fg = colour }
  -- In a score, the other staves dimmed or in their parts' colours
  -- (`score_dim`, `score_colors`), the active one in full ink.
  local function active(s) return only ~= nil or (s > F.base and s <= F.base + F.count) end
  local staff_styles = {}
  for s in ipairs(layout.staves) do
    local id = F.multi and not active(s) and layout.parts and layout.parts[s]
    if id then
      local tint = paw.opt.score_colors and paw.draw.part_colour(api.part_get(id)) or colour
      if paw.opt.score_dim then
        staff_styles[s] = { fg = paw.draw.mix(tint, "#101216", 0.55) }
      elseif paw.opt.score_colors then
        staff_styles[s] = { fg = tint }
      end
    end
  end
  local faint = { fg = paw.draw.mix(colour, "#101216", 0.55) }
  local faint_ink = { fg = paw.draw.mix(colour, "#101216", 0.3) }
  local clef_style = { fg = colour, bold = true }
  local staff_style, bar_style = "Faint", "Dim"
  local geometry = { systems = {}, margin = margin, staff_rows = staff_rows, staves = layout.staves, dense = dense }
  self.geometry = geometry
  local t = api.transport_get()
  local selection = ctx.focused and paw.keymap.selection()

  for si, sys in ipairs(rows_out) do
    local top = 1 + (si - 1) * per
    -- Each staff's rows: its band from `band(s)` for `staff_rows`, its
    -- bottom line `margin + lines - 1` rows into the band.
    local function band(s) return top + (s - 1) * staff_rows end
    local rows = {}
    for s in ipairs(layout.staves) do
      rows[s] = cells.rows(band(s) + margin + lines - 1, dense)
    end
    local function row_of(s, pos) return rows[s].above(pos) end
    geometry.systems[si] = { top = top, measures = sys.measures, row_of = row_of, rows = rows, width = sys.width }
    local y0, y1 = row_of(1, 8), row_of(staves, 0)
    -- Rows a line runs along, for the barlines to join.
    local line_row = {}
    for s in ipairs(layout.staves) do
      for pos = 0, 8, 2 do
        line_row[row_of(s, pos)] = true
      end
    end
    --- A barline from the top line to the bottom one, joining the lines with `set`.
    local function barline(x, set)
      for y = y0, y1 do
        local ch = G.bar
        if line_row[y] then ch = y == y0 and set[1] or y == y1 and set[3] or set[2] end
        buf:text(x, y, ch, bar_style)
      end
    end
    -- Staff lines from the system's edge to its last barline; clef, key, time.
    for s, clef in ipairs(layout.staves) do
      local R = rows[s]
      -- The clef and key in force where the system starts.
      local first = sys.measures[1].m
      clef = first.clefs and first.clefs[s] or clef
      local fifths = first.fifths or fifths
      for pos = 0, 8, 2 do
        buf:fill(edge, R.above(pos), sys.width - edge, 1, G.line, staff_style)
      end
      for _, r in ipairs(cells.clef(clef, dense)) do
        ink(buf, edge + 1, R.above(r[1]), r[2], staff_styles[s] or clef_style)
      end
      if clef == "treble8" or clef == "bass8" then buf:text(edge + 1, R.above(-4), "8", clef_style) end
      if layout.names and layout.names[s] ~= "" then buf:text(edge + 1, band(s), layout.names[s], "Dim") end
      -- A score's instrument names: in full on the first system, short after.
      for _, l in ipairs(layout.labels or {}) do
        if l.first == s then
          buf:text(edge + 1, band(s), (sys.measures[1].m.index == 1 and l.full or l.short) or "", "Dim")
        end
      end
      for i, pos in ipairs(key_positions(fifths, clef)) do
        buf:text(key_x + i - 1, R.above(pos), fifths > 0 and G.acc[1] or G.acc[-1], note_style)
      end
      if meter_changes(first.index) then
        local tx = key_x + math.abs(fifths) + (fifths ~= 0 and 1 or 0)
        buf:text(tx, R.above(6), tostring(first.meter.num), "Bright")
        buf:text(tx, R.above(2), tostring(first.meter.den), "Bright")
      end
    end
    barline(edge, G.first)
    -- A grand staff's brace.
    if staves == 2 then
      local b0, b1 = row_of(1, 8), row_of(2, 0)
      local mid = floor((b0 + b1) / 2)
      for y = b0, b1 do
        buf:text(
          0,
          y,
          y == b0 and G.brace[1] or y == b1 and G.brace[4] or y == mid and G.brace[3] or G.brace[2],
          clef_style
        )
      end
    end
    -- Where keys go: a mark at the active staff's start, over the brace.
    if F.multi then
      for s in ipairs(layout.staves) do
        if active(s) then buf:text(0, rows[s].above(4), paw.opt.ascii and ">" or "▶", "RollCursor") end
      end
    end
    -- Tablature under the staves: a row for each string, the highest first.
    local tab_top = top + staves * staff_rows + tab_room
    if tab then
      for i = 1, tab.strings do
        buf:fill(2, tab_top + i - 1, sys.width - 2, 1, G.line, staff_style)
        buf:text(
          0,
          tab_top + i - 1,
          (paw.music.name(tab.tuning[tab.strings - i + 1]):gsub("%-?%d+$", "")):sub(1, 2),
          "Dim"
        )
      end
    end

    for pi, placed in ipairs(sys.measures) do
      local m, mx = placed.m, placed.x
      -- What a popover would write is drawn as a ghost until Enter.
      local note_style = m.ghost and "ExGhost" or note_style
      local function xt(beat) return mx + floor(model.x_of(m, beat) + 0.5) end
      -- Barline after, the bar's number over the measure.
      local bx = mx + m.width
      barline(bx, pi == #sys.measures and G.last or G.join)
      buf:text(mx, top + math.max(0, margin - 2), tostring(m.number), "Faint")
      if placed ~= sys.measures[1] and meter_changes(m.index) then
        buf:text(
          mx + 1 + #tostring(m.number),
          top + math.max(0, margin - 2),
          m.meter.num .. "/" .. m.meter.den,
          "Bright"
        )
      end

      -- The selection of visual mode.
      if selection then
        local x0 = xt(math.max(selection.c0, m.start))
        local x1 = selection.c1 >= m.start + m.length - EPS and bx or xt(math.min(selection.c1, m.start + m.length))
        if selection.c1 > m.start and selection.c0 < m.start + m.length and x1 > x0 then
          for s, clef in ipairs(layout.staves) do
            local ya, yb = band(s), band(s) + staff_rows - 1
            local pitches = self:selected_staff(selection, F, only and F.base + 1 or s)
            if pitches and (pitches[1] > 0 or pitches[2] < 127) then
              local bottom = model.CLEF_BOTTOM[m.clefs and m.clefs[s] or clef]
              ya = math.max(ya, rows[s].above(model.spell(pitches[2], fifths).step - bottom))
              yb = math.min(yb, rows[s].below(model.spell(pitches[1], fifths).step - bottom))
            end
            if not pitches then yb = ya - 1 end
            if selection.kind == "line" then
              x0, x1 = mx, bx
            end
            if yb >= ya then buf:fill(x0, ya, x1 - x0, yb - ya + 1, nil, "Visual") end
          end
        end
      end

      for s in ipairs(layout.staves) do
        local evs = m.staves[s]
        local R = rows[s]
        local note_style = not m.ghost and staff_styles[s] or note_style
        local mine = active(s)
        local function row(pos) return R.above(pos) end
        -- The row of a stem's end, its flags and beams: inside the system,
        -- a stem shortened rather than run into the next system.
        local function tip_row(pos) return util.clamp(R.above(pos), top, top + per - 1) end
        -- Where a chord's stem is: at its heads' right going up, their left going down.
        local function stem_x(ev) return xt(ev.start) + ((ev.stem or 1) > 0 and 1 or 0) end
        -- Beam groups: where the beam runs.
        local beams = {}
        for _, ev in ipairs(evs) do
          if ev.beam then
            local b = beams[ev.beam] or { dir = ev.stem, events = {} }
            b.events[#b.events + 1] = ev
            beams[ev.beam] = b
          end
        end
        for _, b in pairs(beams) do
          local tip = b.dir > 0 and -math.huge or math.huge
          for _, ev in ipairs(b.events) do
            local top_pos, low_pos = ev.notes[#ev.notes].pos, ev.notes[1].pos
            if b.dir > 0 then
              tip = math.max(tip, top_pos + stem_len, 4)
            else
              tip = math.min(tip, low_pos - stem_len, 4)
            end
          end
          -- On the dense staff a beam runs along a row.
          if dense then tip = b.dir > 0 and tip + tip % 2 or tip - tip % 2 end
          b.tip = tip
        end

        for ei, ev in ipairs(evs) do
          local ex = xt(ev.start)
          if ev.kind == "rest" and ev.multirest then
            -- A multi-measure rest: a bar on the middle line, the count in it.
            local label = "━━ " .. ev.multirest .. " ━━"
            buf:text(mx + math.max(1, floor((m.width - (6 + #tostring(ev.multirest))) / 2)), row(4), label, note_style)
          elseif ev.kind == "rest" then
            local sh = ev.shift or 0
            local rx = ev.whole and mx + floor(m.width / 2) or ex
            local value = ev.whole and 4 or ev.base
            if value >= 4 or value >= 2 then
              -- The whole rest hangs from the fourth line, the half sits on the third.
              local whole = value >= 4
              if dense then
                buf:text(rx, row((whole and 6 or 4) + sh), whole and G.whole or G.half, note_style)
              else
                local pair = whole and G.whole_open or G.half_open
                buf:text(rx, row((whole and 6 or 4) + sh), pair[1], note_style)
                buf:text(rx, row(5 + sh), pair[2], note_style)
              end
            elseif value >= 1 then
              if dense then
                for i, ch in ipairs(G.quarter) do
                  buf:text(rx, row(6 + sh) + i - 1, ch, note_style)
                end
              else
                for i, part in ipairs(G.quarter_open) do
                  buf:text(rx + part[1], row(7 + sh) + i - 1, part[2], note_style)
                end
              end
            else
              -- A flag for each beam the value would have, down a slanted stroke.
              local flags = math.max(1, model.flags(value))
              for f = 1, flags do
                buf:text(rx + flags - f, row(4 + sh + (flags > 1 and 2 or 0) - (f - 1) * 2), G.flag_rest, note_style)
              end
            end
            if ev.dots > 0 and not ev.whole then
              buf:text(
                rx + (value >= 2 and 2 or value < 1 and math.max(1, model.flags(value)) or 1),
                row(5 + sh),
                dense and G.space_dot or G.dot,
                note_style
              )
            end
          else
            local hollow = (ev.base or 1) >= 2
            -- Heads, ledger lines and accidentals; a second's upper head beside the stem.
            local shifted = {}
            for i, n in ipairs(ev.notes) do
              local prev = ev.notes[i - 1]
              shifted[i] = prev and n.step - prev.step == 1 and not shifted[i - 1] or false
            end
            for i, n in ipairs(ev.notes) do
              ledgers(buf, G, R, ex + (shifted[i] and 2 or 0), n.pos, faint)
            end
            -- Cells the heads take, by column and row, for the stem to pass by.
            local taken = { [ex] = {}, [ex + 1] = {}, [ex + 2] = {}, [ex + 3] = {} }
            local boxed = dense and hollow
            for i, n in ipairs(ev.notes) do
              local hx = ex + (shifted[i] and 2 or 0)
              local is_cursor = under
                and ctx.focused
                and mine
                and (ev.player or 1) == F.player
                and (ev.clip or c.id) == c.id
                and n.index == written.index
                and ev.start <= self.beat + F.off + EPS
                and self.beat + F.off < ev.start + ev.length - EPS
              -- The note under the piano roll's cursor stands out.
              head(
                buf,
                G,
                R,
                hx,
                n.pos,
                hollow,
                is_cursor and "NoteCursor" or mine and partner == n.index and "Bright" or note_style
              )
              for _, y in ipairs({ R.above(n.pos), R.below(n.pos) }) do
                taken[hx][y], taken[hx + 1][y] = true, true
              end
              -- Open heads in spaces a third apart share a row.
              local prev = ev.notes[i - 1]
              if
                boxed
                and prev
                and n.pos % 2 ~= 0
                and n.pos - prev.pos == 2
                and not shifted[i]
                and not shifted[i - 1]
              then
                buf:text(hx, R.below(n.pos), G.hollow_join, note_style)
              end
              if n.acc then buf:text(hx - 1, row(n.pos), G.acc[n.acc], n.courtesy and "Dim" or note_style) end
              if ev.dots > 0 then
                local dot_x = ex + 2 + (shifted[i] or shifted[i + 1] and 2 or 0)
                -- In the space: a line's note has its dot in the space above.
                if dense then
                  buf:text(dot_x, row(n.pos % 2 == 0 and n.pos + 1 or n.pos), G.space_dot, note_style)
                else
                  buf:text(dot_x, row(n.pos % 2 == 0 and n.pos + 1 or n.pos), G.dot, note_style)
                end
              end
              -- A tie to the next event: under the head when the stem is up.
              if n.tie then
                local nxt = ev.next
                local tx1 = nxt and x_in(sys, nxt.measure, nxt.start)
                local stem_up = (ev.stem or 1) > 0
                local ty = stem_up and R.below(n.pos - 1) or R.above(n.pos + 1)
                local tx0 = hx + 2 + (ev.dots > 0 and 1 or 0)
                arc(buf, stem_up and G.tie_under or G.tie_over, tx0, (tx1 or sys.width) - 1, ty, note_style, not tx1)
              end
            end
            -- Grace notes before the chord, an arpeggio's wave, a staccato dot.
            local left = ex - 1
            for _, n in ipairs(ev.notes) do
              if n.acc then left = ex - 2 end
            end
            if ev.arpeggio then
              for p = ev.notes[1].pos, ev.notes[#ev.notes].pos do
                buf:text(left, row(p), G.arpeggio, note_style)
              end
              buf:text(
                left,
                row(ev.arpeggio > 0 and ev.notes[#ev.notes].pos + step or ev.notes[1].pos - step),
                ev.arpeggio > 0 and "^" or "v",
                note_style
              )
              left = left - 1
            end
            if ev.grace then
              for gi = #ev.grace, 1, -1 do
                local gn = ev.grace[gi]
                buf:text(left, row(gn.pos), G.grace, faint_ink)
                if gn.acc then buf:text(left - 1, row(gn.pos), G.acc[gn.acc], faint_ink) end
                left = left - 2
              end
            end
            -- Articulations on the side away from the stem, nearest first.
            do
              local up = (ev.stem or 1) > 0
              local p = up and ev.notes[1].pos - 2 or ev.notes[#ev.notes].pos + 2
              local art = ev.art or {}
              for _, mark in ipairs({
                { ev.staccato or art.staccato, G.staccato },
                { art.tenuto, G.tenuto },
                { art.accent, ">" },
                { art.marcato, "^" },
              }) do
                if mark[1] then
                  buf:text(ex, up and R.below(p) or R.above(p), mark[2], note_style)
                  p = p + (up and -step or step)
                end
              end
            end
            if ev.lyric and s == 1 then
              buf:text(ex, band(1) + staff_rows - (staves == 2 and 1 or 2), ev.lyric, "Normal")
            end
            -- The stem, at the heads' right side going up and their left
            -- going down, from the head furthest along it to its tip.
            if ev.stem then
              local top_pos, low_pos = ev.notes[#ev.notes].pos, ev.notes[1].pos
              local b = ev.beam and beams[ev.beam]
              local up = ev.stem > 0
              local tip = b and b.tip
              if not tip then
                tip = up and math.max(top_pos + stem_len, 4) or math.min(low_pos - stem_len, 4)
                if dense then tip = up and tip + tip % 2 or tip - tip % 2 end
              end
              local sx = stem_x(ev)
              if boxed and up and top_pos % 2 ~= 0 then
                buf:text(ex, R.above(top_pos), G.hollow_up, note_style)
              elseif boxed and not up and low_pos % 2 ~= 0 then
                buf:text(ex, R.below(low_pos), G.hollow_down, note_style)
              end
              local ya, yb
              if up then
                ya, yb = tip_row(tip), R.above(low_pos) - 1
              else
                ya, yb = R.below(top_pos) + 1, tip_row(tip)
              end
              for y = ya, yb do
                if not taken[sx][y] then buf:text(sx, y, G.stem, note_style) end
              end
              if not b then
                for f = 1, ev.flags or 0 do
                  buf:text(sx + 1, tip_row(tip - (f - 1) * step * ev.stem), up and G.flag_up or G.flag_down, note_style)
                end
              end
            end
          end
        end
        -- Beams over the stems' ends: one for eighths, more for shorter values.
        for _, b in pairs(beams) do
          local list = b.events
          for level = 1, 3 do
            local y = tip_row(b.tip - (level - 1) * b.dir * step)
            for i, ev in ipairs(list) do
              if (ev.flags or 0) >= level then
                local x0 = stem_x(ev)
                local nxt = list[i + 1]
                if nxt and (nxt.flags or 0) >= level then
                  for bx2 = x0, stem_x(nxt) do
                    buf:text(bx2, y, G.beam, note_style)
                  end
                elseif level > 1 and not (list[i - 1] and (list[i - 1].flags or 0) >= level) then
                  -- A part beam toward the neighbour.
                  if nxt then
                    buf:text(x0, y, G.stub_right, note_style)
                  else
                    buf:text(x0 - 1, y, G.stub_left, note_style)
                  end
                elseif level == 1 then
                  buf:text(x0, y, G.beam, note_style)
                end
              end
            end
          end
          for _, ev in ipairs(list) do
            buf:text(stem_x(ev), tip_row(b.tip), b.dir > 0 and G.beam_up or G.beam_down, note_style)
          end
        end
        -- Slurs: an arc over the notes, to where the slur ends in this system.
        for _, ev in ipairs(evs) do
          if ev.slur_to then
            local last_ev = ev.slur_to
            local x0 = xt(ev.start)
            local x1 = x_in(sys, last_ev.measure, last_ev.start)
            local top_pos = math.max(ev.notes[#ev.notes].pos, last_ev.notes and last_ev.notes[#last_ev.notes].pos or 0)
            local over = (ev.stem or 1) < 0
            local y = over and R.above(top_pos + 2)
              or R.below(math.min(ev.notes[1].pos, last_ev.notes and last_ev.notes[1].pos or 0) - 2)
            if (x1 or sys.width) > x0 + 1 then
              arc(buf, over and G.tie_over or G.tie_under, x0, (x1 or sys.width), y, faint, not x1)
            end
          end
        end
        -- Tuplets: the number over (or under) its notes.
        local tuplets = {}
        for _, ev in ipairs(evs) do
          if ev.tuplet then
            local tp = tuplets[ev.tuplet] or { events = {}, up = 0 }
            tp.events[#tp.events + 1] = ev
            if ev.kind == "note" then tp.up = tp.up + ((ev.stem or 1) > 0 and 1 or -1) end
            tuplets[ev.tuplet] = tp
          end
        end
        for span, tp in pairs(tuplets) do
          local x0, x1 = xt(tp.events[1].start), xt(tp.events[#tp.events].start)
          local up = tp.up >= 0
          local edge_pos = up and 10 or -2
          for _, ev in ipairs(tp.events) do
            for _, n in ipairs(ev.notes or {}) do
              if up then
                edge_pos = math.max(edge_pos, n.pos + stem_len + 1)
              else
                edge_pos = math.min(edge_pos, n.pos - stem_len - 1)
              end
            end
          end
          local y = up and R.above(edge_pos) or R.below(edge_pos)
          if x1 > x0 + 1 then arc(buf, up and G.bracket_over or G.bracket_under, x0, x1, y, faint) end
          buf:text(floor((x0 + x1) / 2), y, tostring(span.n), note_style)
        end
      end

      if tab then
        for i = 1, tab.strings do
          buf:text(bx, tab_top + i - 1, G.bar, bar_style)
        end
        -- Frets, at the notes' places; a tied note's continuation is not played again.
        for st = 1, staves do
          for _, ev in ipairs(m.staves[st]) do
            if ev.kind == "note" then
              for _, n in ipairs(ev.notes) do
                if n.string and not n.tied then
                  buf:text(xt(ev.start), tab_top + n.string - 1, tostring(n.fret), note_style)
                end
              end
            end
          end
        end
      end
      -- Dynamics, hairpins and text; repeat signs at the barlines.
      -- Under the first staff (between a grand staff's two); in a low
      -- panel, on the last row there is. In a score, under the staff the
      -- mark is on.
      local function band_of(mk) return band(F.multi and not only and util.clamp(mk.staff or 1, 1, staves) or 1) end
      local function dyn_row_of(mk) return math.min(band_of(mk) + staff_rows - 1, h - 1) end
      -- A hairpin from an earlier bar runs on through this one.
      for k = m.index - 1, 1, -1 do
        for _, mk in ipairs(layout.measures[k].marks or {}) do
          if (mk.kind == "cresc" or mk.kind == "dim") and mk.to > m.start + EPS then
            local dyn_row = dyn_row_of(mk)
            local x1 = mk.to >= m.start + m.length - EPS and bx - 1 or xt(mk.to)
            local style = mk.ghost and "ExGhost" or note_style
            for hx = mx - 1, x1 do
              buf:text(hx, dyn_row, G.hairpin, style)
            end
            if mk.kind == "dim" and mk.to <= m.start + m.length + EPS then buf:text(x1, dyn_row, ">", style) end
          end
        end
      end
      for _, mk in ipairs(m.marks or {}) do
        local mxp = xt(mk.at)
        local note_style = mk.ghost and "ExGhost" or note_style
        local dyn_row = dyn_row_of(mk)
        if mk.kind == "dyn" then
          buf:text(mxp, dyn_row, mk.value, mk.ghost and note_style or { fg = colour, bold = true, italic = true })
        elseif mk.kind == "cresc" or mk.kind == "dim" then
          local x1 = mk.to >= m.start + m.length - EPS and bx - 1 or xt(mk.to)
          for _, other in ipairs(m.marks) do
            if other.kind == "dyn" and math.abs(other.at - mk.at) < EPS then mxp = mxp + #other.value + 1 end
          end
          for hx = mxp, x1 do
            buf:text(hx, dyn_row, G.hairpin, note_style)
          end
          if mk.kind == "cresc" then
            buf:text(mxp, dyn_row, "<", note_style)
          elseif mk.to <= m.start + m.length + EPS then
            buf:text(x1, dyn_row, ">", note_style)
          end
        elseif mk.kind == "text" then
          buf:text(
            mxp,
            band_of(mk) + math.max(0, margin - 2) + (margin > 1 and 1 or 0),
            tostring(mk.value),
            mk.ghost and note_style or { fg = colour, italic = true }
          )
        end
      end
      for st in ipairs(layout.staves) do
        local R = rows[st]
        for _, at in ipairs({ m.repeat_start and { mx, 1 } or nil, m.repeat_end and { bx, -1 } or nil }) do
          for y = R.above(8), R.above(0) do
            buf:text(at[1], y, G.repeat_bar, bar_style)
          end
          if dense then
            buf:text(at[1] + at[2], R.above(4), ":", note_style)
          else
            buf:text(at[1] + at[2], R.above(3), G.dot, note_style)
            buf:text(at[1] + at[2], R.above(5), G.dot, note_style)
          end
        end
      end

      draw_directions(buf, layout, m, pi > 1, {
        mx = mx,
        bx = bx,
        xt = xt,
        rows = rows,
        band = band,
        staff_rows = staff_rows,
        margin = margin,
        G = G,
        note_style = note_style,
        colour = colour,
        bar_style = bar_style,
        bottom = h - 1,
        top = top,
      })

      if t.position >= F.start + m.start - EPS and t.position < F.start + m.start + m.length - EPS then
        local px = xt(t.position - F.start)
        buf:fill(px, y0, 1, y1 - y0 + 1, nil, "Playhead")
      end
    end
  end

  -- The cursor: on its line or space, at its time. Off a note it is the
  -- note `Enter` or a letter would put there (the shadow note); in insert
  -- mode that follows the pointer while it is over the staff.
  if ctx.focused then
    local beat, cstep, s = self.beat + F.off, self.step + F.dstep, nil
    local hover = view.cell_hover
    if inserting and hover and hover.from_beat == self.beat and hover.from_step == self.step then
      beat, cstep, s, under =
        hover.beat + F.off, hover.step + F.dstep, only and 1 or F.base + self:staff_of_step(hover.step), nil
    end
    for _, sys in ipairs(geometry.systems) do
      for _, placed in ipairs(sys.measures) do
        local m = placed.m
        if
          beat >= m.start - EPS
          and (beat < m.start + m.length - EPS or (m.index == #layout.measures and beat <= m.start + m.length + EPS))
        then
          s = s or (only and 1 or F.base + self:cursor_staff())

          local R = sys.rows[s]
          local pos = cstep - model.CLEF_BOTTOM[m.clefs and m.clefs[s] or layout.staves[s]]
          local cx = placed.x + floor(model.x_of(m, beat) + 0.5)
          -- A popover opens under the system, at the caret's column, so that
          -- the staff and what it previews stay in sight; at the foot of the
          -- panel when the system fills it. Under the row of dynamics too,
          -- which is what a dynamic's popover previews.
          local last = sys.rows[#sys.rows]
          local under_marks = math.max(last.above(0) + 3, sys.top + geometry.staff_rows)
          self.caret_cell = { x = (ctx.x or 0) + cx, y = (ctx.y or 0) + math.min(h - 1, math.max(1, under_marks)) }
          local style = inserting and "InsertCursor" or "RollCursor"
          if selection then
            buf:fill(cx, R.above(pos), 2, 1, nil, style)
          elseif not under then
            ledgers(buf, G, R, cx, pos, faint)
            head(buf, G, R, cx, pos, (model.value_of(self:entry_length()) or 1) >= 2, style)
          elseif inserting then
            buf:fill(cx, R.above(pos), 2, 1, nil, style)
          end
          return
        end
      end
    end
  end
end

-- The pointer, as on the engraved page (`notation.gui`), in cells: in
-- normal mode a click puts the cursor on a note (and sounds it) or on a line
-- or space and time, Shift-click stretches a selection from the cursor, a
-- drag of a note moves it, a drag on the paper selects a block, a double
-- click enters notes there; in insert mode a click enters a note of the
-- chosen value and the shadow note follows the pointer; a right click opens
-- the menu of what can be done there; the wheel scrolls by measures.

--- Where the pointer puts the cursor or a note `rel` beats into measure
--- `m`: on a multiple of the chosen value within the beat, as one counts
--- the bar (an eighth on an eighth, a triplet on a third of a beat), so that
--- what is typed after a click lands where it was meant; with `fine` (Alt
--- held, or a drag) on the grid. The window's pointer (`notation.gui`)
--- snaps the same.
function view:snap(m, rel, fine)
  local grid = self:layout().grid
  if fine then return util.clamp(floor(rel / grid + 0.5) * grid, 0, m.length - grid) end
  return model.snap(
    m.meter,
    rel,
    self.value * (self:entry_tuplet() and self:entry_tuplet()[2] / self:entry_tuplet()[1] or 1)
  )
end

--- What is at a cell of the view: the line or space, the beat there
--- (`view:snap`, `fine` on the grid), its staff, and `note` when the cell is
--- a note's head; in the clip's beats and staves. In a score, a cell on
--- another staff makes that staff the active one with `activate`, and is
--- nothing without it.
function view:cell_at(x, y, fine, activate)
  local g = self.geometry
  local F = self:frame()
  local layout = F and F.layout
  if not (g and layout) then return nil end
  for _, sys in ipairs(g.systems) do
    for _, placed in ipairs(sys.measures) do
      local m = placed.m
      if x >= placed.x and x <= placed.x + m.width then
        for s, clef in ipairs(g.staves or layout.staves) do
          local R = sys.rows[s]
          local pos = R.pos_of(y)
          local reach = g.margin * R.step
          if pos >= -reach - 1 and pos <= 8 + reach + 1 then
            local step = model.CLEF_BOTTOM[m.clefs and m.clefs[s] or clef] + pos
            local at = { step = step, beat = m.start + self:snap(m, model.t_of(m, x - placed.x) - m.start, fine) }
            local staff = g.staves and #g.staves == 1 and F.base + 1 or s
            -- A head is drawn at its chord's start, two cells wide, or two
            -- columns right beside a second; on the dense staff a head in a
            -- space is on the rows either side of it.
            local player, owner
            for _, near in ipairs(R.step == 2 and { step, step + 1, step - 1 } or { step }) do
              for _, ev in ipairs(m.staves[s] or {}) do
                local hx = placed.x + floor(model.x_of(m, ev.start) + 0.5)
                for _, n in ipairs(ev.notes or {}) do
                  if
                    not at.note
                    and n.step == near
                    and at.beat >= ev.start - EPS
                    and at.beat < ev.start + ev.length - EPS
                    and x >= hx
                    and x <= hx + 3
                  then
                    at.note, at.beat, at.step, player, owner = n.index, ev.start, near, ev.player, ev.clip
                  end
                end
              end
            end
            if not self:onto_staff(F, staff, player, activate, at.beat, owner) then return nil end
            F = self:frame()
            at.beat = at.beat - F.off
            at.staff = staff - F.base
            at.step = at.step - F.dstep
            return at
          end
        end
      end
    end
  end
end

--- Say on the status line what the pointer is over.
local function hint(self, at)
  if not at then return paw.mouse.hint(nil) end
  local fifths = view.key()
  local note = at.note and self:clip() and self:clip():notes()[at.note]
  local name = note and paw.music.name(note.pitch) or model.name(model.spell(model.key_pitch(at.step, fifths), fifths))
  paw.mouse.hint(string.format("%s  %s", name, paw.time.format(self:clip():get().start + at.beat)))
end

function view:on_mouse(e)
  local F = self:frame()
  local layout = F and F.layout
  if not (self.geometry and layout) then return end
  local wheel = paw.mouse.wheel(e)
  if wheel then
    self.first = util.clamp(self.first + wheel, 1, #layout.measures)
    return api.ui_redraw()
  end
  local inserting = paw.keymap.mode == "i"
  -- A press on another staff of a score makes it the active one.
  local at = self:cell_at(e.x, e.y, paw.mouse.has(e, "A"), e.kind == "down")
  if e.kind == "move" then
    view.cell_hover = inserting
        and at
        and { beat = at.beat, step = at.step, from_beat = self.beat, from_step = self.step }
      or nil
    hint(self, at)
    return api.ui_redraw()
  end
  if e.kind ~= "down" or not at then return end
  view.cell_hover = nil
  if e.button == "right" then
    self:set(at.step, at.beat)
    return paw.ui.menu(self:menu_items(at.note ~= nil, at), { x = e.x + (e.view_x or 0), y = e.y + (e.view_y or 0) })
  end
  if e.button ~= "left" then return end
  if inserting then
    -- The second press of a double click enters nothing more.
    if not e.double then self:enter_at(at) end
    return
  end
  if e.double then
    self:set(at.step, at.beat)
    self.last, self.chord = nil, nil
    return paw.keymap.set_mode("i")
  end
  if paw.mouse.has(e, "S") then
    if paw.keymap.mode ~= "x" then paw.keymap.visual_start("v") end
    return self:set(at.step, at.beat)
  end
  if paw.keymap.mode == "x" then paw.keymap.set_mode("n") end
  self:set(at.step, at.beat)
  local clip = self:clip()
  local note = at.note and clip:notes()[at.note]
  if note then
    self:audition(note.pitch)
    -- A drag of the note moves it: the cursor, off the note, shows where.
    local to
    return paw.mouse.grab(e, {
      drag = function(d)
        local there = self:cell_at(d.x, d.y, true)
        if not (d.moved and there) then return end
        to = { step = there.step, beat = there.beat }
        self:set(to.step, to.beat)
        hint(self, there)
      end,
      up = function()
        if to and (to.step ~= at.step or math.abs(to.beat - at.beat) > EPS) then
          self:move_note(at.note, note, to.step, to.beat)
        end
      end,
      cancel = function() self:set(at.step, at.beat) end,
    })
  end
  -- A drag on the paper selects a block.
  paw.mouse.grab(e, {
    drag = function(d)
      local there = self:cell_at(d.x, d.y, true)
      if not (d.moved and there) then return end
      if paw.keymap.mode ~= "x" then paw.keymap.visual_start("b") end
      self:set(there.step, there.beat)
    end,
  })
end

return view
