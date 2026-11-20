-- The page in pixels: a layout's measures engraved with a SMuFL font,
-- snapped to the pixel grid, as `paw.canvas` drawing operations.
--
--   style    the staff space in whole pixels (one of STEPS), the font's
--            engraving defaults turned into whole-pixel thicknesses, and
--            the colours: ink (the terminal's foreground, or the window's
--            text), staff lines part of the way to the paper, accents
--   systems  measures broken into systems across the width, balanced
--            (`notation.breaks`), or all of them in one endless system
--            ("galley"), or systems on pages; what stands outside the staff
--            placed against each staff's skyline (`notation.skyline`), and
--            the staves as far apart as their skylines need; measure widths
--            in whole cell columns and system heights in whole cell rows,
--            so a frontend can cut the page at barlines into images that
--            sit on cells
--   ink      what is written, staff by staff and measure by measure, kept
--            by what it holds: an edit engraves again only the measures it
--            changed, and a cursor move none
--
-- Staff lines, stems, barlines and ledger lines are rectangles on whole
-- pixels; note heads, clefs, accidentals, flags, rests, dots, numbers and
-- dynamics are the font's glyphs; beams, ties and slurs are paths.
local model = require("notation.model")
local smufl = require("notation.smufl")
local skyline = require("notation.skyline")
local breaks = require("notation.breaks")

local floor, ceil, abs, max, min, sqrt = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt
local EPS = 1e-6

local E = {}

--- The staff spaces the page is drawn at, in pixels: zoom steps through these.
E.STEPS = { 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 24 }
--- How large a cue is drawn, of a note's size.
E.CUE = 0.7

local function round(v) return floor(v + 0.5) end

-- Colours ------------------------------------------------------------------------------------

local function rgb(hex)
  hex = tostring(hex or ""):gsub("^#", "")
  return tonumber(hex:sub(1, 2), 16) or 0, tonumber(hex:sub(3, 4), 16) or 0, tonumber(hex:sub(5, 6), 16) or 0
end

local function lightness(hex)
  local r, g, b = rgb(hex)
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

--- `a` taken `t` of the way to `b`.
local function mix(a, b, t)
  local r1, g1, b1 = rgb(a)
  local r2, g2, b2 = rgb(b)
  return string.format("#%02x%02x%02x", round(r1 + (r2 - r1) * t), round(g1 + (g2 - g1) * t), round(b1 + (b2 - b1) * t))
end
E.mix = mix

-- Style --------------------------------------------------------------------------------------

--- What the page is drawn with. `o`: `space` (staff space in px), `cell`
--- (`{ w, h }`), `ink`, `paper`, `accent`, `font`, `whole_cells` (measure
--- widths and system heights in whole cells).
function E.style(o)
  local sp = o.space
  local font = smufl.font(o.font)
  local d = font.defaults
  -- Light ink on a dark page looks heavier than dark on light: thinner.
  local thin = lightness(o.ink) > lightness(o.paper) and 0.9 or 1
  local function px(v) return max(1, round(v * sp * thin)) end
  local st = {
    sp = sp, em = 4 * sp, font = font, cell = o.cell, whole = o.whole_cells,
    line = px(d.staffLineThickness), stem = px(d.stemThickness), ledger = px(d.legerLineThickness),
    ledger_ext = d.legerLineExtension * sp, beam = max(2, round(d.beamThickness * sp * thin)),
    beam_gap = max(1, round(d.beamSpacing * sp)), bar = px(d.thinBarlineThickness), thick = px(d.thickBarlineThickness),
    bar_gap = round(d.barlineSeparation * sp), dot_gap = d.repeatBarlineDotSeparation * sp,
    tie_end = d.tieEndpointThickness * sp, tie_mid = d.tieMidpointThickness * sp * thin,
    slur_end = d.slurEndpointThickness * sp, slur_mid = d.slurMidpointThickness * sp * thin,
    hairpin = max(1, d.hairpinThickness * sp * thin), bracket = px(d.tupletBracketThickness),
    ink = o.ink, paper = o.paper, accent = o.accent,
    staff = mix(o.ink, o.paper, 0.55), faint = mix(o.ink, o.paper, 0.45), muted = mix(o.ink, o.paper, 0.3),
  }
  st.key = table.concat({ sp, o.cell.w, o.cell.h, o.ink, o.paper, font.name, tostring(o.whole_cells) }, ":")
  return st
end

local function glyph(st, name) return st.font.glyphs[name] end
local function gwidth(st, name, scale)
  local g = glyph(st, name)
  return (g.bbox[3] - g.bbox[1]) * st.sp * (scale or 1)
end

-- Ink: drawing kept in coordinates of its own ------------------------------------------------

-- Ink keeps, beside its operations, its shape: a box for each rectangle,
-- glyph and text, and the segments of each path, which is what a skyline
-- (`notation.skyline`) is made of.
local Ink = {}
Ink.__index = Ink
local function ink() return setmetatable({ ops = {}, heads = {}, shape = {} }, Ink) end
E.ink = ink

--- A rectangle; `bare` leaves it out of the shape (a staff line, which the
--- skyline has already).
function Ink:rect(x, y, w, h, colour, bare)
  if w <= 0 or h <= 0 then return end
  self.ops[#self.ops + 1] = { "r", x, y, w, h, colour, "", 1, 0 }
  if not bare then self.shape[#self.shape + 1] = { 1, x, y, x + w, y + h } end
end

function Ink:glyph(st, x, y, name, colour, scale)
  local g = glyph(st, name)
  if not g then return end
  self.ops[#self.ops + 1] = { "g", x, y, st.em * (scale or 1), g.cp, colour, st.font.name }
  local bb = g.bbox
  if bb then
    local k = st.sp * (scale or 1)
    self.shape[#self.shape + 1] = { 1, x + bb[1] * k, y - bb[4] * k, x + bb[3] * k, y - bb[2] * k }
  end
end

--- About how wide a line of text is, a little over.
local function text_width(text, size, bold)
  return select(2, tostring(text):gsub("[^\128-\191]", "")) * size * (bold and 0.62 or 0.56)
end
E.text_width = text_width

--- The size lyrics are set in.
local function lyric_size(st) return max(10, round(1.3 * st.sp)) end

--- Text with its top at `y`. Its shape is a box from the top of its
--- capitals to the foot of its descenders, a little over its width.
function Ink:text(x, y, text, colour, size, bold, align, width)
  text = tostring(text)
  self.ops[#self.ops + 1] = { "t", x, y, text, colour, size, bold and 1 or 0, align or "left", width or 400 }
  local w = min(width or 400, text_width(text, size, bold))
  local l = align == "center" and x - w / 2 or align == "right" and x - w or x
  self.shape[#self.shape + 1] = { 1, l, y + 0.2 * size, l + w, y + 1.2 * size }
end

--- A path: `{ "M", x, y, "C", ..., "Z" }` kept as numbers until placed.
--- Its shape is its outline, curves as straight segments.
function Ink:path(cmds, stroke, width, fill)
  self.ops[#self.ops + 1] = { "P", cmds, stroke or "", width or 1, fill or "" }
  local shape, w = self.shape, stroke and stroke ~= "" and width or 1
  local x, y, sx, sy = 0, 0, 0, 0
  local i = 1
  while i <= #cmds do
    local c = cmds[i]
    if c == "M" then
      x, y = cmds[i + 1], cmds[i + 2]
      sx, sy = x, y
      i = i + 3
    elseif c == "L" then
      shape[#shape + 1] = { 2, x, y, cmds[i + 1], cmds[i + 2], w }
      x, y = cmds[i + 1], cmds[i + 2]
      i = i + 3
    elseif c == "C" then
      local ax, ay, bx, by, ex, ey = cmds[i + 1], cmds[i + 2], cmds[i + 3], cmds[i + 4], cmds[i + 5], cmds[i + 6]
      local px, py = x, y
      -- A segment every 16 px or so, at least six.
      local steps = max(6, ceil(abs(ex - x) / 16))
      for k = 1, steps do
        local t = k / steps
        local u = 1 - t
        local qx = u * u * u * x + 3 * u * u * t * ax + 3 * u * t * t * bx + t * t * t * ex
        local qy = u * u * u * y + 3 * u * u * t * ay + 3 * u * t * t * by + t * t * t * ey
        shape[#shape + 1] = { 2, px, py, qx, qy, w }
        px, py = qx, qy
      end
      x, y = ex, ey
      i = i + 7
    elseif c == "Z" then
      shape[#shape + 1] = { 2, x, y, sx, sy, w }
      x, y = sx, sy
      i = i + 1
    else
      i = i + 1
    end
  end
end

--- Ink's operations, heads and shape added to another's, moved down by `dy`.
local function offset(src, dst, dy)
  local ops = dst.ops
  for _, op in ipairs(src.ops) do
    if op[1] == "P" then
      local cmds, moved, axis = op[2], {}, 0
      for i, v in ipairs(cmds) do
        if type(v) == "string" then
          moved[i] = v
          axis = 0
        else
          moved[i] = axis == 1 and v + dy or v
          axis = 1 - axis
        end
      end
      ops[#ops + 1] = { "P", moved, op[3], op[4], op[5] }
    else
      local o = { op[1], op[2], op[3] + dy }
      for i = 4, #op do o[i] = op[i] end
      ops[#ops + 1] = o
    end
  end
  for _, h in ipairs(src.heads) do
    local moved = {}
    for k, v in pairs(h) do moved[k] = v end
    moved.y = h.y + dy
    dst.heads[#dst.heads + 1] = moved
  end
  if dst.shape then
    for _, s in ipairs(src.shape) do
      dst.shape[#dst.shape + 1] = { s[1], s[2], s[3] + dy, s[4], s[5] + dy, s[6] }
    end
  end
end
E.offset = offset

local function fmt(v) return string.format("%.1f", v) end

--- Put ink into a drawing at `dx, dy`.
local function place(src, out, dx, dy)
  for _, op in ipairs(src) do
    local kind = op[1]
    if kind == "P" then
      local cmds, parts, axis = op[2], {}, 0
      for i, v in ipairs(cmds) do
        if type(v) == "string" then
          parts[i] = v
          axis = 0
        else
          parts[i] = fmt(v + (axis == 0 and dx or dy))
          axis = 1 - axis
        end
      end
      out[#out + 1] = { "p", table.concat(parts, " "), op[3], op[4], op[5] }
    else
      local o = { kind, op[2] + dx, op[3] + dy }
      for i = 4, #op do o[i] = op[i] end
      out[#out + 1] = o
    end
  end
end
E.place = place

-- Shapes ------------------------------------------------------------------------------------

--- A tie or slur from `x0, y0` to `x1, y1` bowing `bow` px towards `dir`
--- (1 down, -1 up), thicker in the middle. `inset` is how far in from the
--- ends the curve's control points are, as a part of its length: small for
--- a flat curve, a quarter for a round one.
local function arc(dst, x0, y0, x1, y1, bow, dir, thick_end, thick_mid, colour, inset)
  local dx, dy = x1 - x0, y1 - y0
  inset = inset or 0.25
  -- A cubic's middle is three quarters of the way to its control points.
  local outer, inner = (bow + thick_mid / 2) / 0.75, (bow - thick_mid / 2) / 0.75
  local e = thick_end / 2
  local ax, ay = x0 + dx * inset, y0 + dy * inset
  local bx, by = x0 + dx * (1 - inset), y0 + dy * (1 - inset)
  dst:path({ "M", x0, y0 + dir * e,
    "C", ax, ay + dir * outer, bx, by + dir * outer, x1, y1 + dir * e,
    "L", x1, y1 - dir * e,
    "C", bx, by + dir * inner, ax, ay + dir * inner, x0, y0 - dir * e, "Z" }, "", 1, colour)
end
E.arc = arc

--- The most a tie rises, in staff spaces.
E.TIE_HEIGHT = 0.6

--- A tie from `x0` to `x1` at `y`, towards `dir` (1 down): flat, close to
--- the heads, rising a little more the longer it is (Gould).
local function tie(dst, st, x0, x1, y, dir, colour)
  local s = st.sp
  local bow = min(E.TIE_HEIGHT, 0.3 + 0.02 * (x1 - x0) / s) * s
  arc(dst, x0, y, x1, y, bow, dir, st.tie_end, st.tie_mid, colour, 0.12)
end

--- Where the tie of a chord's `i`th note (from the lowest) goes: `dir` (1
--- below the heads, -1 above) and whether it lies outside the chord, over
--- or under the heads, or between them. A single note's tie and a chord's
--- outer ones are outside, on the side away from the stem (a stemless note
--- by where it sits on the staff); a chord's upper notes tie up, its lower
--- ones down.
local function tie_side(ev, i)
  local notes = ev.notes
  local away = ev.stem and (ev.stem > 0 and 1 or -1) or (notes[#notes].pos >= 4 and -1 or 1)
  local count = #notes
  if count == 1 then return away, true end
  if i == count then return -1, true end
  if i == 1 then return 1, true end
  if 2 * i - 1 == count then return away, false end
  return 2 * i > count and -1 or 1, false
end

--- A tie's ends for a head whose left edge is at `hx` (`hw` wide) and the
--- next head's left edge at `nx`, and its height: outside a chord over the
--- heads, inside it between them.
local function tie_ends(st, hw, hx, nx, y, dir, outside, dotted)
  local s = st.sp
  if outside then
    return dotted and hx + hw + 0.85 * s or hx + 0.7 * hw, nx and nx + 0.3 * hw, y + dir * 0.7 * s
  end
  return hx + hw + 0.15 * s + (dotted and 0.5 * s or 0), nx and nx - 0.15 * s, y + dir * 0.25 * s
end

-- Heads, accidentals and what else stands beside a head --------------------------------

--- Accidentals of a chord in columns: the highest nearest the notes, each
--- next one in the first column where it clears those above it by six
--- staff positions. Returns the column of each note (0 nearest).
local function accidental_columns(notes)
  local cols, placed = {}, {}
  for i = #notes, 1, -1 do
    local n = notes[i]
    if n.acc then
      local c = 0
      while true do
        local clash = false
        for _, q in ipairs(placed) do
          if q.col == c and abs(q.pos - n.pos) < 6 then clash = true end
        end
        if not clash then break end
        c = c + 1
      end
      cols[i] = c
      placed[#placed + 1] = { col = c, pos = n.pos }
    end
  end
  return cols
end

local ACC_GLYPH = { [1] = "accidentalSharp", [-1] = "accidentalFlat", [0] = "accidentalNatural", [2] = "accidentalDoubleSharp", [-2] = "accidentalDoubleFlat" }
local HEAD_GLYPH = function(base)
  if not base or base < 2 then return "noteheadBlack" end
  if base < 4 then return "noteheadHalf" end
  if base < 8 then return "noteheadWhole" end
  return "noteheadDoubleWhole"
end
local REST_GLYPH = { [4] = "restWhole", [2] = "restHalf", [1] = "restQuarter", [0.5] = "rest8th", [0.25] = "rest16th", [0.125] = "rest32nd" }
local FLAG_GLYPH = { "flag8th", "flag16th", "flag32nd", "flag64th" }
E.ACC_GLYPH, E.HEAD_GLYPH = ACC_GLYPH, HEAD_GLYPH
local DYN_GLYPH = { p = "dynamicPiano", mp = "dynamicMP", mf = "dynamicMF", f = "dynamicForte",
  pp = "dynamicPP", ff = "dynamicFF", ppp = "dynamicPPP", fff = "dynamicFFF", pppp = "dynamicPPPP", ffff = "dynamicFFFF",
  sf = "dynamicSforzando1", sfz = "dynamicSforzato", sffz = "dynamicSforzatoFF", fz = "dynamicForzando", rfz = "dynamicRinforzando2",
  fp = "dynamicFortePiano", sfp = "dynamicSforzandoPiano", niente = "dynamicNiente" }
local CLEF_GLYPH = { treble = { "gClef", 2 }, treble8 = { "gClef8vb", 2 }, bass = { "fClef", 6 }, bass8 = { "fClef8vb", 6 },
  alto = { "cClef", 4 }, tenor = { "cClef", 6 } }
E.CLEF_GLYPH = CLEF_GLYPH

--- Between a head and its accidental, and between columns of accidentals,
--- in staff spaces.
local ACC_GAP, ACC_COLUMN_GAP = 0.2, 0.15

--- An accidental's width, its parentheses included.
local function acc_width(st, n)
  local w = gwidth(st, ACC_GLYPH[n.acc])
  if n.courtesy then w = w + gwidth(st, "accidentalParensLeft") + gwidth(st, "accidentalParensRight") end
  return w
end

--- A chord's accidentals placed left of its heads: for each note with one,
--- how far left of the heads' left edge its sign (parentheses included)
--- begins, each right-aligned in a column as wide as the column's widest;
--- and the room they all take, from the heads' edge (0 with none).
local function accidentals(st, notes)
  local cols = accidental_columns(notes)
  local widths = {}
  for i, n in ipairs(notes) do
    if n.acc then widths[cols[i] + 1] = max(widths[cols[i] + 1] or 0, acc_width(st, n)) end
  end
  if #widths == 0 then return {}, 0 end
  local edge, from = ACC_GAP * st.sp, {}
  for c, w in ipairs(widths) do
    from[c] = edge
    edge = edge + w + ACC_COLUMN_GAP * st.sp
  end
  local at = {}
  for i, n in ipairs(notes) do
    if n.acc then at[i] = from[cols[i] + 1] + acc_width(st, n) end
  end
  return at, edge - ACC_COLUMN_GAP * st.sp
end

--- Which of a chord's heads go on the other side of the stem (a second up
--- from its neighbour does), and whether any does.
local function seconds(ev)
  local shifted, any = {}, false
  for i, n in ipairs(ev.notes) do
    local prev = ev.notes[i - 1]
    shifted[i] = prev and n.step - prev.step == 1 and not shifted[i - 1] or false
    any = any or shifted[i]
  end
  return shifted, any
end

--- How far an event's writing reaches left and right of its time (the
--- middle of its heads), in px: accidentals, grace notes and the arpeggio
--- on the left; heads on the other side of the stem, dots and a flag on
--- the right. As `measure_ink` draws them.
local function room(st, ev)
  local s = st.sp
  if ev.kind == "rest" then
    if ev.whole then return 0, 0 end
    local rw = gwidth(st, REST_GLYPH[ev.base] or "rest16th")
    return rw / 2, rw / 2 + (ev.dots > 0 and 0.3 * s + gwidth(st, "augmentationDot") or 0)
  end
  local hw = gwidth(st, HEAD_GLYPH(ev.base))
  local dir = ev.stem or 1
  -- Most chords have no second and no accidental: nothing to place for those.
  local any, signs = false, false
  for i, n in ipairs(ev.notes) do
    if n.acc then signs = true end
    if i > 1 and n.step - ev.notes[i - 1].step == 1 then any = true end
  end
  local side = any and hw - st.stem or 0
  local acc = 0
  if signs then _, acc = accidentals(st, ev.notes) end
  local left = hw / 2 + (dir < 0 and side or 0) + acc
  local right = hw / 2 + (dir > 0 and side or 0)
  if ev.arpeggio or ev.grace then left = left + 0.4 * s end
  if ev.arpeggio then left = left + 1.1 * s end
  for _, gn in ipairs(ev.grace or {}) do
    left = left + 0.66 * gwidth(st, "noteheadBlack") + 0.5 * s
    if gn.acc then left = left + gwidth(st, ACC_GLYPH[gn.acc], 0.66) + 0.15 * s end
  end
  if ev.dots > 0 then right = right + (0.35 + 0.5 * (ev.dots - 1)) * s + gwidth(st, "augmentationDot") end
  if ev.stem and dir > 0 and not ev.beam and (ev.flags or 0) > 0 then
    right = max(right, hw / 2 - st.stem + gwidth(st, FLAG_GLYPH[min(4, ev.flags)] .. "Up"))
  end
  -- A lyric is centred under its note, and its syllables do not touch.
  if ev.lyric and ev.lyric ~= "" then
    local half = text_width(ev.lyric, lyric_size(st)) / 2 + 0.25 * s
    left, right = max(left, half), max(right, half)
  end
  return left, right
end
E.room = room

-- Spacing ------------------------------------------------------------------------------------

--- A measure's spacing without touching the layout's measure: a proxy
--- carries `slots` and `width` (in px). What stands beside the heads gets
--- room only where the spacing of the values leaves too little, half a
--- space clear of the note before.
local function spaced(m, st, spread)
  local p = setmetatable({}, { __index = m })
  local s = st.sp
  model.space({ measures = { p } }, {
    lead = 1.5 * s + E.change_room(st, m), gap = 0.5 * s, tail = 0.9 * s,
    unit = function(d) return s * spread * (1.15 + 1.6 * sqrt(d / 0.25)) end,
    room = function(ev) return room(st, ev) end,
  })
  -- A multi-measure rest is as wide as a bar of a few notes, whatever it counts.
  if m.multirest then p.width = max(p.width, 9 * s) end
  return p
end

--- Stretch a spaced measure to `width` px, keeping its own width as `natural`.
local function stretch(p, width)
  local f = width / max(1, p.width)
  local slots = {}
  for i, slot in ipairs(p.slots) do slots[i] = { t = slot.t, x = slot.x * f } end
  p.slots, p.width, p.natural = slots, width, p.natural or p.width
end

-- Systems ------------------------------------------------------------------------------------

local SHARP_POS = { 8, 5, 9, 6, 3, 7, 4 }
local FLAT_POS = { 4, 7, 3, 6, 2, 5, 1 }
E.SHARP_POS, E.FLAT_POS = SHARP_POS, FLAT_POS

local function meter_changes(layout, i)
  local before = layout.measures[i - 1]
  return i == 1 or (before and before.meter ~= layout.measures[i].meter)
end
E.meter_changes = meter_changes

local function time_width(st, meter)
  local w = 0
  for _, digits in ipairs({ tostring(meter.num), tostring(meter.den) }) do
    local dw = 0
    for ch in digits:gmatch("%d") do dw = dw + gwidth(st, "timeSig" .. ch) end
    w = max(w, dw)
  end
  return w
end

--- What starts a system at measure `i` (clef, key signature, and the time
--- signature where it is written): where its measures begin, and where
--- the signs end.
local function prefix(st, layout, i, left)
  local s = st.sp
  local x = left + 0.6 * s + gwidth(st, "gClef") + 0.8 * s
  local signs = x - 0.8 * s
  local fifths = layout.measures[i].fifths or layout.fifths
  if fifths ~= 0 then
    x = x + abs(fifths) * (gwidth(st, fifths > 0 and "accidentalSharp" or "accidentalFlat") + 0.12 * s) + 0.6 * s
    signs = x - 0.6 * s
  end
  if meter_changes(layout, i) then
    local tw = time_width(st, layout.measures[i].meter)
    signs = x + tw
    x = x + tw + 0.8 * s
  end
  return x, signs
end

--- The y of a staff position in a staff's own frame, whose y 0 is the top
--- of its top line.
local function staff_y(st, pos) return (8 - pos) * st.sp / 2 + st.line / 2 end

--- The y of a staff position (0 the bottom line, 8 the top) on a staff,
--- at the middle of its line.
function E.y_of(st, sys, staff, pos)
  return sys.staff_top[staff] + staff_y(st, pos)
end

-- A staff's ink in a measure -----------------------------------------------------------------

--- What a staff's ink in a measure depends on, as text: two that say the
--- same draw the same.
local function staff_signature(m, p, k)
  local parts = { k, floor(p.width + 0.5), tostring(m.repeat_start), tostring(m.repeat_end), m.start, tostring(m.ghost) }
  for _, ev in ipairs(m.staves[k] or {}) do
    parts[#parts + 1] = table.concat({ ev.kind, ev.start, ev.length, tostring(ev.base), ev.dots, tostring(ev.stem),
      tostring(ev.flags), tostring(ev.beam and true), tostring(ev.whole), tostring(ev.shift), ev.voice,
      tostring(ev.arpeggio), tostring(ev.staccato), tostring(ev.tuplet and ev.tuplet.n), tostring(ev.tuplet and ev.tuplet.s),
      tostring(ev.cue), tostring(ev.multirest) }, ",")
    if ev.art then
      for _, a in ipairs({ "staccato", "accent", "tenuto", "marcato" }) do
        if ev.art[a] then parts[#parts + 1] = a end
      end
    end
    for _, n in ipairs(ev.notes or {}) do
      parts[#parts + 1] = table.concat({ n.pos, n.id or n.index, tostring(n.acc), tostring(n.courtesy), tostring(n.tie),
        tostring(n.tied), tostring(ev.next and ev.next.measure == ev.measure and ev.next.start) }, ".")
    end
    for _, n in ipairs(ev.grace or {}) do parts[#parts + 1] = "g" .. n.pos .. tostring(n.acc) end
  end
  return table.concat(parts, ";")
end

--- Where a beam group's beams run: `y0` at `x0`, slope per px, direction.
--- The slope is at most a staff space over the group and comes in quarter
--- spaces; inside the staff the beam's middle sits on a line, or a
--- quarter space above or below one, never in the middle of a space.
local function beam_line(st, evs, stem_x, Y, dir)
  local s = st.sp
  local first, last = evs[1], evs[#evs]
  local function far(ev) return dir > 0 and ev.notes[#ev.notes].pos or ev.notes[1].pos end
  local x0, x1 = stem_x(first), stem_x(last)
  local span = max(1, x1 - x0)
  local rise = (Y(far(last)) - Y(far(first)))
  rise = max(-s, min(s, rise / 2))
  rise = round(rise / (s / 4)) * (s / 4)
  -- A group whose inner notes reach further than its ends lies flat.
  for k = 2, #evs - 1 do
    local p = far(evs[k])
    if (dir > 0 and p > max(far(first), far(last))) or (dir < 0 and p < min(far(first), far(last))) then rise = 0 end
  end
  local slope = rise / span
  -- Every stem at least three spaces (shorter with more beams), and the
  -- beam reaching the middle line.
  local levels = 1
  for _, ev in ipairs(evs) do levels = max(levels, ev.flags or 1) end
  local need = (3.0 + max(0, levels - 2) * 0.5) * s
  local y0 = dir > 0 and math.huge or -math.huge
  for _, ev in ipairs(evs) do
    local at = Y(far(ev)) - dir * need - slope * (stem_x(ev) - x0)
    if dir > 0 then y0 = min(y0, at) else y0 = max(y0, at) end
  end
  local mid = Y(4)
  for _, ev in ipairs(evs) do
    local yb = y0 + slope * (stem_x(ev) - x0)
    if dir > 0 and yb > mid then y0 = y0 - (yb - mid) end
    if dir < 0 and yb < mid then y0 = y0 + (mid - yb) end
  end
  -- The primary beam's middle on the quarter-space grid, avoiding mid-space.
  local centre = y0 + dir * st.beam / 2
  local top = Y(8) - st.line / 2
  local rel = (centre - top) / (s / 4)
  local q = round(rel)
  if q >= -1 and q <= 17 and q % 4 == 2 then q = q + (dir > 0 and -1 or 1) end
  local snapped = top + q * s / 4
  -- On a whole pixel, so that a flat beam's edges are sharp.
  y0 = round(y0 + (snapped - centre))
  return { x0 = x0, y0 = y0, slope = slope, dir = dir, at = function(x) return y0 + slope * (x - x0) end }
end

--- Engrave a staff's music in a measure, in coordinates from the
--- measure's left edge and the staff's own frame: its stretch of the staff
--- lines, heads, stems, beams, accidentals, dots, ledger lines,
--- articulations, ties within the measure, tuplets and repeat signs. What
--- crosses barlines or stands outside the staff is the system's.
local function staff_ink(st, m, p, staff)
  local s, out = st.sp, ink()
  -- What a popover would write is drawn in the accent until Enter.
  local colour = m.ghost and st.accent or st.ink
  local function xt(beat) return model.x_of(p, beat) end
  local w = p.width
  local function Y(pos) return staff_y(st, pos) end
  for pos = 0, 8, 2 do out:rect(0, round(Y(pos) - st.line / 2), round(w), st.line, st.staff, true) end
  local head_w = gwidth(st, "noteheadBlack")
  local stem_up_x = round(glyph(st, "noteheadBlack").anchors.stemUpSE[1] * s)
  local evs = m.staves[staff] or {}
  -- Heads are placed with their left edge on a whole pixel, centred on
  -- the event's time; stems hang from the font's anchors.
  local function head_x(ev) return round(xt(ev.start) - head_w / 2) end
  local function stem_x(ev, dir)
    local hx = head_x(ev)
    if dir > 0 then return hx + stem_up_x - st.stem end
    return hx
  end
  local beams = {}
  for _, ev in ipairs(evs) do
    if ev.beam then
      local b = beams[ev.beam] or { dir = ev.stem, events = {} }
      b.events[#b.events + 1] = ev
      beams[ev.beam] = b
    end
  end
  for _, b in pairs(beams) do
    b.line = beam_line(st, b.events, function(ev) return stem_x(ev, b.dir) + st.stem / 2 end, Y, b.dir)
  end

  for _, ev in ipairs(evs) do
    local ex = xt(ev.start)
    -- A cue (another part's notes, to come in by) is drawn small.
    local k = ev.cue and E.CUE or 1
    if ev.kind == "rest" and ev.multirest then
      -- A multi-measure rest: a thick bar on the middle line between two
      -- serifs, how many bars it counts over the staff.
      local x0, x1 = round(1.2 * s), round(w - 1.6 * s)
      local h = round(0.6 * s)
      out:rect(x0, round(Y(4) - h / 2), x1 - x0, h, colour)
      out:rect(x0, round(Y(6)), st.thick, round(2 * s), colour)
      out:rect(x1 - st.thick, round(Y(6)), st.thick, round(2 * s), colour)
      local digits = tostring(ev.multirest)
      local dw = 0
      for ch in digits:gmatch("%d") do dw = dw + gwidth(st, "timeSig" .. ch) end
      local dx = (x0 + x1 - dw) / 2
      for ch in digits:gmatch("%d") do
        out:glyph(st, round(dx), round(Y(11)), "timeSig" .. ch, colour)
        dx = dx + gwidth(st, "timeSig" .. ch)
      end
    elseif ev.kind == "rest" then
      local rx = ev.whole and (w / 2) or ex
      local sh = ev.shift or 0
      local base = ev.whole and 4 or ev.base
      local name = REST_GLYPH[base] or "rest16th"
      local rw = gwidth(st, name, k)
      local pos = (base >= 4) and 6 or 4
      out:glyph(st, round(rx - rw / 2), round(Y(pos + sh)), name, colour, k)
      if ev.dots > 0 and not ev.whole then
        out:glyph(st, round(rx + rw / 2 + 0.3 * s), round(Y(5 + sh)), "augmentationDot", colour, k)
      end
    else
      local dir = ev.stem or 1
      local hname = HEAD_GLYPH(ev.base)
      local hw = gwidth(st, hname, k)
      local hx = round(ex - hw / 2)
      -- A second up from its neighbour goes on the other side of the stem.
      local shifted, any_shift = seconds(ev)
      local side = round(hw - st.stem)
      local low, high = ev.notes[1].pos, ev.notes[#ev.notes].pos
      local ext = st.ledger_ext
      local lx0 = round(hx - ext - ((any_shift and dir < 0) and side or 0))
      local lx1 = round(hx + hw + ext + ((any_shift and dir > 0) and side or 0))
      for pos = -2, low, -2 do out:rect(lx0, round(Y(pos) - st.ledger / 2), lx1 - lx0, st.ledger, colour) end
      for pos = 10, high, 2 do out:rect(lx0, round(Y(pos) - st.ledger / 2), lx1 - lx0, st.ledger, colour) end
      local acc_at, acc_room = accidentals(st, ev.notes)
      local acc_left = hx - ((any_shift and dir < 0) and side or 0)
      for i, n in ipairs(ev.notes) do
        local nx = hx + (shifted[i] and (dir > 0 and side or -side) or 0)
        local ny = Y(n.pos)
        out:glyph(st, nx, ny, hname, colour, k)
        out.heads[#out.heads + 1] = { x = nx + hw / 2, y = ny, index = n.index, id = n.id, step = n.step, start = ev.start, staff = staff,
          base = ev.base, glyph = hname, gx = nx, player = ev.player, clip = ev.clip }
        if n.acc then
          local name = ACC_GLYPH[n.acc]
          local ax = acc_left - acc_at[i]
          if n.courtesy then
            local lw = gwidth(st, "accidentalParensLeft")
            out:glyph(st, round(ax), round(ny), "accidentalParensLeft", st.faint)
            out:glyph(st, round(ax + lw), round(ny), name, st.faint)
            out:glyph(st, round(ax + lw + gwidth(st, name)), round(ny), "accidentalParensRight", st.faint)
          else
            out:glyph(st, round(ax), round(ny), name, colour, k)
          end
        end
        for d = 1, ev.dots do
          local dy = n.pos % 2 == 0 and Y(n.pos + 1) or ny
          local dx = hx + hw + ((any_shift and dir > 0) and side or 0) + (0.35 + 0.5 * (d - 1)) * s
          out:glyph(st, round(dx), round(dy), "augmentationDot", colour, k)
        end
        if n.tie and ev.next and ev.next.measure == ev.measure then
          local tdir, outside = tie_side(ev, i)
          local x0, x1, y = tie_ends(st, hw, nx, round(xt(ev.next.start) - hw / 2), ny, tdir, outside, ev.dots > 0)
          tie(out, st, x0, x1, y, tdir, colour)
        end
      end
      -- Grace notes, the arpeggio and articulations.
      local left = acc_left - acc_room - 0.4 * s
      if ev.arpeggio then
        local y0, y1 = Y(high) - 0.6 * s, Y(low) + 0.6 * s
        local ax = left - 0.3 * s
        local pts = { "M", ax, y1 }
        local k, yy = 0, y1
        while yy > y0 do
          yy = yy - 0.5 * s
          k = k + 1
          pts[#pts + 1] = "L"
          pts[#pts + 1] = ax + (k % 2 == 1 and 0.3 or -0.3) * s
          pts[#pts + 1] = yy
        end
        out:path(pts, colour, max(1, 0.13 * s))
        local tipy = ev.arpeggio > 0 and yy or y1
        local d = ev.arpeggio > 0 and 1 or -1
        out:path({ "M", ax - 0.45 * s, tipy + d * 0.6 * s, "L", ax, tipy, "L", ax + 0.45 * s, tipy + d * 0.6 * s }, colour, max(1, 0.13 * s))
        left = left - 1.1 * s
      end
      if ev.grace then
        local scale = 0.66
        local gw = head_w * scale
        for gi = #ev.grace, 1, -1 do
          local gn = ev.grace[gi]
          local gx, gy = round(left - gw), Y(gn.pos)
          for pos = -2, gn.pos, -2 do out:rect(round(gx - 0.25 * s), round(Y(pos) - st.ledger / 2), round(gw + 0.5 * s), st.ledger, colour) end
          for pos = 10, gn.pos, 2 do out:rect(round(gx - 0.25 * s), round(Y(pos) - st.ledger / 2), round(gw + 0.5 * s), st.ledger, colour) end
          out:glyph(st, gx, gy, "noteheadBlack", colour, scale)
          local sx = gx + round(stem_up_x * scale) - st.stem
          local tip = round(gy - 2.5 * s)
          out:rect(sx, tip, st.stem, round(gy) - tip, colour)
          out:glyph(st, sx, tip, "flag8thUp", colour, scale)
          out:path({ "M", sx - 0.5 * s, gy - 0.9 * s, "L", sx + 0.8 * s, gy - 2.0 * s }, colour, max(1, 0.1 * s))
          left = gx - 0.5 * s
          if gn.acc then
            local name = ACC_GLYPH[gn.acc]
            local aw = gwidth(st, name, scale)
            out:glyph(st, round(gx - aw - 0.15 * s), round(gy), name, colour, scale)
            left = left - aw - 0.15 * s
          end
        end
      end
      do
        -- Articulations on the side away from the stem, nearest first,
        -- in the spaces.
        local up = dir > 0
        local d = up and 1 or -1
        local pos = up and low - 2 or high + 2
        if pos % 2 == 0 and pos >= 0 and pos <= 8 then pos = pos - d end
        local cx = hx + hw / 2
        local art = ev.art or {}
        local function mark(name)
          local gn = name .. (up and "Below" or "Above")
          local gw2 = gwidth(st, gn)
          out:glyph(st, round(cx - gw2 / 2), round(Y(pos)), gn, colour)
          pos = pos - d * 2
          if pos >= 0 and pos <= 8 and pos % 2 == 0 then pos = pos - d end
        end
        if ev.staccato or art.staccato then mark("articStaccato") end
        if art.tenuto then mark("articTenuto") end
        if art.accent then mark("articAccent") end
        if art.marcato then mark("articMarcato") end
      end
      -- Stem, then flags when nothing beams it.
      if ev.stem then
        local sx = stem_x(ev, dir)
        if ev.cue then sx = dir > 0 and hx + round(stem_up_x * k) - st.stem or hx end
        local anchor = dir > 0 and glyph(st, hname).anchors and glyph(st, hname).anchors.stemUpSE
        local base_y = dir > 0 and Y(low) - (anchor and anchor[2] or 0.16) * s * k or Y(high) + 0.17 * s * k
        local tip
        local b = ev.beam and beams[ev.beam]
        if b then
          tip = b.line.at(sx + st.stem / 2)
        else
          local len = (3.5 * s + ((ev.flags or 0) >= 2 and (ev.flags - 1) * 0.5 * s or 0)) * k
          -- A stem reaches the middle line at least; a cue's keeps its own length.
          local mid = not ev.cue and Y(4) or nil
          tip = dir > 0 and min(Y(high) - len, mid or math.huge) or max(Y(low) + len, mid or -math.huge)
        end
        local y0, y1 = round(min(base_y, tip)), round(max(base_y, tip))
        out:rect(sx, y0, st.stem, y1 - y0, colour)
        if not b and (ev.flags or 0) > 0 then
          local name = FLAG_GLYPH[min(4, ev.flags)] .. (dir > 0 and "Up" or "Down")
          out:glyph(st, sx, round(tip), name, colour, k)
        end
      end
    end
  end

  -- Beams: the first joins every note of the group, the others the
  -- notes short enough for them, with a stub where one stands alone.
  for _, b in pairs(beams) do
    local list, line = b.events, b.line
    local th = st.beam
    for level = 1, 4 do
      -- Beams a whole number of pixels apart, the font's gap between them.
      local off = (level - 1) * (th + st.beam_gap) * b.dir
      for i, ev in ipairs(list) do
        if (ev.flags or 0) >= level then
          local xa = stem_x(ev, b.dir)
          local nxt, prev = list[i + 1], list[i - 1]
          local function draw(x0, x1)
            local y0, y1 = line.at(x0) + off, line.at(x1) + off
            if b.dir < 0 then y0, y1 = y0 - th, y1 - th end
            out:path({ "M", x0, y0, "L", x1, y1, "L", x1, y1 + th, "L", x0, y0 + th, "Z" }, "", 1, colour)
          end
          if nxt and (nxt.flags or 0) >= level then
            draw(xa, stem_x(nxt, b.dir) + st.stem)
          elseif not (prev and (prev.flags or 0) >= level) and level > 1 then
            if nxt then draw(xa, xa + 1.1 * s) else draw(xa + st.stem - 1.1 * s, xa + st.stem) end
          end
        end
      end
    end
  end

  -- Tuplets, clear of what is drawn so far. A group under one beam of its
  -- own has only its number, on the beam's side, past the beam's middle;
  -- any other has a bracket from its first head's left edge to its last
  -- head's right edge on the stems' side, clear of them, with the number
  -- in a gap in the middle.
  local tuplets, order = {}, {}
  for _, ev in ipairs(evs) do
    if ev.tuplet then
      local tp = tuplets[ev.tuplet]
      if not tp then
        tp = { span = ev.tuplet, events = {}, up = 0 }
        tuplets[ev.tuplet] = tp
        order[#order + 1] = tp
      end
      tp.events[#tp.events + 1] = ev
      if ev.kind == "note" then tp.up = tp.up + ((ev.stem or 1) > 0 and 1 or -1) end
    end
  end
  local sky = #order > 0 and skyline.new(w + 1, 0, 4 * s + st.line)
  if sky then sky:shape(out.shape) end
  for _, tp in ipairs(order) do
    local first, last = tp.events[1], tp.events[#tp.events]
    local name = "tuplet" .. tostring(tp.span.n)
    local nw = gwidth(st, name)
    local nh = glyph(st, name).bbox[4] * s
    local b = first.beam and beams[first.beam]
    local drawn = #out.shape
    if b and #b.events == #tp.events and last.beam == first.beam then
      local mid = (stem_x(first, b.dir) + stem_x(last, b.dir) + st.stem) / 2
      local edge = b.line.at(mid)
      local base = b.dir > 0 and edge - 0.4 * s or edge + 0.4 * s + nh
      local top, bottom = sky:over(mid - nw / 2, mid + nw / 2)
      if b.dir > 0 then base = min(base, top - 0.25 * s) else base = max(base, bottom + 0.25 * s + nh) end
      out:glyph(st, round(mid - nw / 2), round(base), name, colour)
    else
      local up = tp.up >= 0
      local x0, x1 = head_x(first), head_x(last) + round(head_w)
      local top, bottom = sky:over(x0, x1)
      local clear = max(0.75 * s, nh / 2 + 0.3 * s)
      local edge = round(up and min(top - clear, Y(10)) or max(bottom + clear, Y(-2)))
      local hook = round(up and 0.5 * s or -0.5 * s)
      local mid = (x0 + x1) / 2
      local th = st.bracket
      out:rect(x0, min(edge, edge + hook), th, abs(hook), st.faint)
      out:rect(x0, edge, round(mid - nw / 2 - 0.3 * s) - x0, th, st.faint)
      out:rect(round(mid + nw / 2 + 0.3 * s), edge, x1 - round(mid + nw / 2 + 0.3 * s), th, st.faint)
      out:rect(x1 - th, min(edge, edge + hook), th, abs(hook), st.faint)
      out:glyph(st, round(mid - nw / 2), round(edge + nh / 2), name, colour)
    end
    for i = drawn + 1, #out.shape do sky:shape({ out.shape[i] }) end
  end

  if m.repeat_start or m.repeat_end then
    local t0, t1 = round(Y(8) - st.line / 2), round(Y(0) + st.line / 2)
    local dot_w = gwidth(st, "repeatDot")
    if m.repeat_start then
      out:rect(0, t0, st.thick, t1 - t0, colour)
      out:rect(st.thick + st.bar_gap, t0, st.bar, t1 - t0, colour)
      local dx = round(st.thick + st.bar_gap + st.bar + st.dot_gap)
      out:glyph(st, dx, round(Y(5)), "repeatDot", colour)
      out:glyph(st, dx, round(Y(3)), "repeatDot", colour)
    end
    if m.repeat_end then
      local x = round(w) - st.thick
      out:rect(x, t0, st.thick, t1 - t0, colour)
      out:rect(x - st.bar_gap - st.bar, t0, st.bar, t1 - t0, colour)
      local dx = round(x - st.bar_gap - st.bar - st.dot_gap - dot_w)
      out:glyph(st, dx, round(Y(5)), "repeatDot", colour)
      out:glyph(st, dx, round(Y(3)), "repeatDot", colour)
    end
  end
  return out
end

--- The runs of staves a barline joins, `{ first, last }`: a score's
--- `layout.spans` (its barlines stop between the families of
--- instruments), else every staff.
function E.bar_spans(layout)
  return layout.spans or { { 1, #layout.staves } }
end

--- A measure's barline, and its stretch of the tablature, in coordinates
--- from its left edge and the system's top.
local function frame_ink(st, layout, sys, placed)
  local m, p = placed.m, placed.p
  local s, out = st.sp, ink()
  local colour = st.ink
  local w = p.width
  local nstaves = #layout.staves
  local bx = round(w) - st.bar
  for _, span in ipairs(E.bar_spans(layout)) do
    local top_y = sys.staff_top[span[1]] - sys.y
    local bottom_y = sys.staff_top[span[2]] - sys.y + 4 * s + st.line
    out:rect(bx, round(top_y), st.bar, round(bottom_y - top_y), colour)
  end
  local tab = layout.tab
  if tab and sys.tab_top then
    local function ty(i) return sys.tab_top - sys.y + (i - 1) * sys.tab_line end
    for i = 1, tab.strings do out:rect(0, ty(i), round(w), st.line, st.staff) end
    out:rect(bx, ty(1), st.bar, (tab.strings - 1) * sys.tab_line + st.line, colour)
    -- Fret numbers on a patch that breaks the string line.
    for k = 1, nstaves do
      for _, ev in ipairs(m.staves[k] or {}) do
        if ev.kind == "note" then
          for _, n in ipairs(ev.notes) do
            if n.string and not n.tied then
              local label = tostring(n.fret)
              local size = max(9, round(1.25 * s))
              local fw = round((#label * 0.62 + 0.25) * size)
              local fx, fy = model.x_of(p, ev.start), ty(n.string)
              out:rect(round(fx - fw / 2), round(fy - size * 0.45), fw, round(size * 0.9), st.paper)
              out:text(round(fx), round(fy - size * 0.62), label, colour, size, false, "center", fw + 4)
            end
          end
        end
      end
    end
  end
  return out
end

--- A staff's skyline in a measure, from its ink, kept with it.
local function staff_sky(st, si, width)
  local sky = si.sky
  if not sky then
    sky = skyline.new(width + 1, 0, 4 * st.sp + st.line)
    sky:shape(si.shape)
    si.sky = sky
  end
  return sky
end

--- A staff's ink in a measure (`staff_ink`), kept by its signature while
--- the style holds.
function E.staff(cache, st, m, p, k)
  -- A score's layout keeps the events of a measure it did not lay out
  -- again: their signature is known while the measure's place and width
  -- are the same.
  local evs = m.staves[k]
  local known = cache.known
  if not known then
    known = setmetatable({}, { __mode = "k" })
    cache.known = known
  end
  local width = floor(p.width + 0.5)
  local seen = evs and known[evs]
  local sig
  if seen and seen.width == width and seen.start == m.start and seen.k == k and seen.rs == m.repeat_start and seen.re == m.repeat_end
    and seen.ghost == m.ghost then
    sig = seen.sig
  else
    sig = staff_signature(m, p, k)
    if evs then known[evs] = { width = width, start = m.start, k = k, rs = m.repeat_start, re = m.repeat_end, ghost = m.ghost, sig = sig } end
  end
  local hit = cache[sig]
  if hit then
    hit.used = cache.generation
    return hit
  end
  local made = staff_ink(st, m, p, k)
  made.used = cache.generation
  cache[sig] = made
  cache.count = (cache.count or 0) + 1
  return made
end

--- A measure's ink in coordinates from its left edge and the system's
--- top: its staves' ink where the system puts them, the barline, and the
--- tablature.
function E.measure(cache, st, layout, sys, placed)
  local out = { ops = {}, heads = {} }
  for k = 1, #layout.staves do
    offset(E.staff(cache, st, placed.m, placed.p, k), out, sys.staff_top[k] - sys.y)
  end
  for _, op in ipairs(frame_ink(st, layout, sys, placed).ops) do out.ops[#out.ops + 1] = op end
  for _, op in ipairs(E.change_ink(st, layout, sys, placed).ops) do out.ops[#out.ops + 1] = op end
  return out
end

--- Forget measures not used for a while.
function E.sweep(cache)
  if (cache.count or 0) < 400 then return end
  local keep = 0
  for k, v in pairs(cache) do
    if type(v) == "table" and v.used then
      if v.used < cache.generation - 2 then cache[k] = nil else keep = keep + 1 end
    end
  end
  cache.count = keep
end

-- Marks the engraver places ------------------------------------------------------------------

local function dynamics_side(item)
  return item.system.lyrics[item.staff] and "above" or "below"
end

skyline.kind("number", { side = "above", pad = 0.3, ink = function(out, st, item)
  local size = max(9, round(1.0 * st.sp))
  out:text(round(item.x), -2 * size, tostring(item.value), st.muted, size)
end })

skyline.kind("lyric", { side = "below", pad = 0.6, row = "lyrics",
  collect = function(m, add)
    for k, evs in ipairs(m.staves) do
      for _, ev in ipairs(evs) do
        if ev.lyric and ev.lyric ~= "" then add({ at = ev.start, staff = k, value = ev.lyric }) end
      end
    end
  end,
  ink = function(out, st, item)
    out:text(round(item.x), 0, item.value, st.ink, lyric_size(st), false, "center")
  end })

-- Dynamics and hairpins are one row along the system: a dynamic's glyph
-- sits on the line, a hairpin's middle at the height of its letters.
skyline.kind("dyn", { order = skyline.ORDER.dynamics, side = dynamics_side, pad = 0.7, row = "dynamics", ink = function(out, st, item)
  local s = st.sp
  local name = DYN_GLYPH[item.value]
  local colour = item.ghost and st.accent or st.ink
  local x = round(item.x - gwidth(st, "noteheadBlack") / 2)
  if name then
    out:glyph(st, x, 0, name, colour)
    x = x + round(gwidth(st, name))
  else
    out:text(round(item.x), round(-1.3 * s), item.value, colour, round(1.6 * s), true)
    x = x + round(text_width(item.value, round(1.6 * s), true))
  end
  if item.subito then out:text(x + round(0.4 * s), round(-1.2 * s), "subito", colour, round(1.2 * s), false) end
end })

local function hairpin(out, st, item)
  local s = st.sp
  local x0, x1 = item.x, max(item.x + s, item.x1 or item.x + 4 * s)
  local mid = -0.5 * s
  local open, shut = x0, x1
  if item.kind == "cresc" then open, shut = x1, x0 end
  local colour = item.ghost and st.accent or st.ink
  out:path({ "M", open, mid - 0.55 * s, "L", shut, mid, "L", open, mid + 0.55 * s }, colour, st.hairpin)
  -- Niente: a small circle at the point, from or to nothing.
  if item.niente then out:glyph(st, round(shut - 0.9 * s), round(mid + 0.4 * s), "dynamicNiente", colour, 0.6) end
end
skyline.kind("cresc", { order = skyline.ORDER.dynamics, side = dynamics_side, pad = 0.7, row = "dynamics", ink = hairpin })
skyline.kind("dim", { order = skyline.ORDER.dynamics, side = dynamics_side, pad = 0.7, row = "dynamics", ink = hairpin })

skyline.kind("text", { side = "above", pad = 0.6, ink = function(out, st, item)
  out:text(round(item.x), 0, tostring(item.value), item.ghost and st.accent or st.ink, round(1.4 * st.sp), true)
end })

--- The x of a beat on a system, or nil off it. `ending`: the beat ends
--- something (a hairpin), so a barline's beat is just before the barline.
local function x_on(st, sys, beat, ending)
  local list = sys.measures
  for i, placed in ipairs(list) do
    local m = placed.m
    if ending and i > 1 and abs(beat - m.start) < EPS then return placed.x - 0.6 * st.sp end
    if beat >= m.start - EPS and beat < m.start + m.length - EPS then return placed.x + model.x_of(placed.p, beat) end
  end
  local last = list[#list]
  if ending and abs(beat - (last.m.start + last.m.length)) < EPS then return last.x + last.p.width - 0.6 * st.sp end
end
E.x_on = x_on

-- What the popovers write (`notation.popover`) -------------------------------------------------

local ORN_GLYPH = { trill = "ornamentTrill", mordent = "ornamentMordent", prall = "ornamentShortTrill", turn = "ornamentTurn",
  turn_inverted = "ornamentTurnInverted", tremolo = "tremolo3", fermata = "fermataAbove", fermata_short = "fermataShortAbove",
  fermata_long = "fermataLongAbove" }
local METRONOME = { q = "metNoteQuarterUp", h = "metNoteHalfUp", e = "metNote8thUp" }
local CHANGE_SCALE = 0.75   -- a clef changed inside a system is drawn smaller

local function mark_colour(st, item) return item.ghost and st.accent or st.ink end

skyline.kind("chord", { side = "above", pad = 0.6, row = "chords", ink = function(out, st, item)
  out:text(round(item.x - gwidth(st, "noteheadBlack") / 2), -round(1.5 * st.sp), item.value, mark_colour(st, item), round(1.5 * st.sp), true)
end })

skyline.kind("technique", { order = 45, side = "above", pad = 0.5, ink = function(out, st, item)
  out:text(round(item.x), -round(1.3 * st.sp), item.value, mark_colour(st, item), round(1.3 * st.sp), false)
end })

-- Words, then the metronome mark: the note's glyph and its number.
skyline.kind("tempo", { side = "above", pad = 0.6, ink = function(out, st, item)
  local s, colour = st.sp, mark_colour(st, item)
  local size = round(1.4 * s)
  local words, unit, per = item.value:match("^(.-)%s*([qhe]%.?)%s*=%s*(%d+%.?%d*)$")
  if not unit and item.bpm and not item.change then words, unit, per = item.value, "q", tostring(floor(item.bpm + 0.5)) end
  words = words or item.value
  local x = round(item.x)
  if words ~= "" then
    out:text(x, -size, words, colour, size, not item.change)
    x = x + round(text_width(words, size, not item.change) + 0.6 * s)
  end
  if unit then
    local name = METRONOME[unit:sub(1, 1)]
    out:glyph(st, x, round(-0.2 * s), name, colour, 0.8)
    x = x + round(gwidth(st, name, 0.8))
    if unit:find("%.") then
      out:glyph(st, x + round(0.2 * s), round(-0.2 * s), "metAugmentationDot", colour, 0.8)
      x = x + round(0.6 * s)
    end
    out:text(x + round(0.3 * s), -size, "= " .. per, colour, size, false)
  end
end })

-- A rehearsal mark in its box over the bar's start.
skyline.kind("rehearsal", { side = "above", pad = 0.8,
  collect = function(m, add)
    if m.rehearsal then add({ at = m.start, staff = 1, value = m.rehearsal, ghost = m.ghost }) end
  end,
  ink = function(out, st, item)
    local s, colour = st.sp, mark_colour(st, item)
    local size = round(1.4 * s)
    local w = round(text_width(item.value, size, true) + 0.8 * s)
    local h = round(1.9 * s)
    local x = round(item.x - 0.5 * s)
    out:rect(x, -h, w, st.line, colour)
    out:rect(x, 0, w + st.line, st.line, colour)
    out:rect(x, -h, st.line, h, colour)
    out:rect(x + w, -h, st.line, h, colour)
    out:text(x + round(w / 2), -h + round(0.25 * s), item.value, colour, size, true, "center", w)
  end })

-- An ending's bracket over its bars, its number where it starts.
skyline.kind("volta", { order = 65, side = "above", pad = 0.8, row = "voltas",
  collect = function(m, add)
    if m.volta then add({ at = m.start, to = m.start + m.length, staff = 1, value = m.volta, index = m.index, ghost = m.ghost }) end
  end,
  ink = function(out, st, item)
    local s, colour = st.sp, mark_colour(st, item)
    local sys = item.system
    local x1 = E.x_on(st, sys, item.to, true) or sys.width
    local x0 = round(item.x - 1.2 * s)
    local h = round(2 * s)
    out:rect(x0, -h, round(x1 - x0), st.line, colour)
    local before = sys.layout_measures and sys.layout_measures[item.index - 1]
    if not (before and before.volta == item.value and sys.measures[1].m.index ~= item.index) then
      out:rect(x0, -h, st.line, h, colour)
      out:text(x0 + round(0.4 * s), -h + round(0.2 * s), item.value .. ".", colour, round(1.2 * s), false)
    end
  end })

-- Ornaments and fermatas over their chords.
skyline.kind("orn", { order = 15, side = "above", pad = 0.5,
  collect = function(m, add)
    for k, evs in ipairs(m.staves) do
      for _, ev in ipairs(evs) do
        local src = ev.kind == "note" and ev.source
        if src and src.orn and ORN_GLYPH[src.orn] then add({ at = ev.start, staff = k, value = src.orn, ghost = m.ghost }) end
        for _, kind in ipairs({ "fermata", "fermata_short", "fermata_long" }) do
          if src and src.art and src.art[kind] then add({ at = ev.start, staff = k, value = kind, ghost = m.ghost }) end
        end
      end
    end
  end,
  ink = function(out, st, item)
    out:glyph(st, round(item.x - gwidth(st, ORN_GLYPH[item.value]) / 2), 0, ORN_GLYPH[item.value], mark_colour(st, item))
  end })

-- The verses after the first, each a line under the one before.
for verse = 2, 4 do
  skyline.kind("verse" .. verse, { order = 20 + verse / 10, side = "below", pad = 0.3, row = "verse" .. verse,
    collect = function(m, add)
      for k, evs in ipairs(m.staves) do
        for _, ev in ipairs(evs) do
          local text = ev.source and ev.source.lyrics and ev.source.lyrics[verse - 1]
          if text and text ~= "" then add({ at = ev.start, staff = k, value = text }) end
        end
      end
    end,
    ink = function(out, st, item)
      out:text(round(item.x), 0, item.value, st.ink, lyric_size(st), false, "center")
    end })
end

--- Room at a measure's start for the clef and key that change there.
function E.change_room(st, m)
  local w = 0
  if m.clef_change then w = w + gwidth(st, "gClef") * CHANGE_SCALE + 0.5 * st.sp end
  if m.key_change and m.index > 1 then
    local n = max(1, abs(m.fifths or 0), m.key_from and abs(m.key_from) or 0)
    w = w + n * (gwidth(st, "accidentalSharp") + 0.12 * st.sp) + 0.6 * st.sp
  end
  return w
end

--- What a measure changes where it starts, inside a system (at a system's
--- start its clef and key say it): a smaller clef, the key's signs (the
--- old ones cancelled where they must be); and its barline when it is a
--- double or the final one. In coordinates from its left edge and the
--- system's top.
function E.change_ink(st, layout, sys, placed)
  local m, p = placed.m, placed.p
  local s, out = st.sp, ink()
  local colour = m.ghost and st.accent or st.ink
  local nstaves = #layout.staves
  local function Y(staff, pos) return sys.staff_top[staff] - sys.y + staff_y(st, pos) end
  local inside = sys.measures[1] ~= placed
  local x = 0.4 * s
  if m.clef_change and inside then
    for staff, clef in pairs(m.clef_change) do
      local cg = CLEF_GLYPH[clef] or CLEF_GLYPH.treble
      out:glyph(st, round(x), round(Y(staff, cg[2])), cg[1], colour, CHANGE_SCALE)
    end
    x = x + gwidth(st, "gClef") * CHANGE_SCALE + 0.5 * s
  end
  if m.key_change and m.index > 1 and inside then
    local before = m.key_from or 0
    local fifths = m.fifths or 0
    for staff = 1, nstaves do
      local clef = m.clefs and m.clefs[staff] or layout.staves[staff]
      local kx = x
      if fifths == 0 or (before ~= 0 and (before > 0) ~= (fifths > 0)) then
        for _, pos in ipairs(model.key_positions(before, clef)) do
          out:glyph(st, round(kx), round(Y(staff, pos)), "accidentalNatural", colour)
          kx = kx + gwidth(st, "accidentalNatural") + 0.12 * s
        end
      end
      local name = fifths > 0 and "accidentalSharp" or "accidentalFlat"
      for _, pos in ipairs(model.key_positions(fifths, clef)) do
        out:glyph(st, round(kx), round(Y(staff, pos)), name, colour)
        kx = kx + gwidth(st, name) + 0.12 * s
      end
    end
  end
  if m.barline == "||" or m.barline == "|." then
    local t0 = round(sys.staff_top[1] - sys.y)
    local t1 = round(sys.staff_top[nstaves] - sys.y + 4 * s + st.line)
    local w = round(p.width)
    if m.barline == "||" then
      out:rect(w - st.bar - st.bar_gap - st.bar, t0, st.bar, t1 - t0, colour)
    else
      out:rect(w - st.thick, t0, st.thick, t1 - t0, colour)
      out:rect(w - st.thick - st.bar_gap - st.bar, t0, st.bar, t1 - t0, colour)
    end
  end
  return out
end

--- Slurs and hairpins of a layout, which may run over systems. A hairpin
--- ends at the first dynamic after its start, if that comes before its end.
local function spanners(layout)
  local slurs, hairpins, dynamics = {}, {}, {}
  for _, m in ipairs(layout.measures) do
    for k, evs in ipairs(m.staves) do
      for _, ev in ipairs(evs) do
        if ev.slur_to then slurs[#slurs + 1] = { a = ev, b = ev.slur_to, staff = k } end
      end
    end
    for _, mk in ipairs(m.marks or {}) do
      if (mk.kind == "cresc" or mk.kind == "dim") and skyline.kinds[mk.kind] then hairpins[#hairpins + 1] = mk end
      if mk.kind == "dyn" then dynamics[#dynamics + 1] = mk.at end
    end
  end
  for i, hp in ipairs(hairpins) do
    local to = hp.to or hp.at
    for _, at in ipairs(dynamics) do
      if at > hp.at + EPS and at < to then to = at end
    end
    hairpins[i] = { kind = hp.kind, at = hp.at, to = to, staff = hp.staff, niente = hp.niente, ghost = hp.ghost }
  end
  return slurs, hairpins
end

--- Which side a slur goes: under the heads when every stem under it
--- points up, else over them; a lower voice's below, an upper voice's
--- above where there are two (Gould).
local function slur_side(layout, sl)
  local up, down, voices = false, false, false
  for mi = sl.a.measure, sl.b.measure do
    for _, ev in ipairs(layout.measures[mi] and layout.measures[mi].staves[sl.staff] or {}) do
      if ev.voice ~= sl.a.voice and ev.kind == "note" then voices = true end
      if ev.kind == "note" and ev.voice == sl.a.voice and ev.start >= sl.a.start - EPS and ev.start <= sl.b.start + EPS and ev.stem then
        if ev.stem > 0 then up = true else down = true end
      end
    end
  end
  if voices then return sl.a.voice >= 2 and 1 or -1 end
  return (up and not down) and 1 or -1
end

--- Bow a slur from `x0, y0` to `x1, y1` (its middle line) over a skyline
--- towards `d` (-1 up): as round as its length asks, rounder where what is
--- under it needs, and where a bow cannot clear it (it would be too round),
--- both ends rise. Returns the ends' heights and the bow.
local function fit_slur(st, sky, x0, y0, x1, y1, d)
  local s = st.sp
  local len = max(1, x1 - x0)
  local clear = 0.3 * s
  local half = st.slur_mid / 2
  local bow = min(2.0 * s, 0.6 * s + len * 0.08)
  local most = max(bow, min(3.0 * s, len / 4))
  local function want(x)
    local t = (x - x0) / len
    local base = y0 + (y1 - y0) * t
    local obstacle = d < 0 and sky.top[x] or sky.bottom[x]
    return (d < 0 and base - obstacle or obstacle - base) + clear, t
  end
  local need = bow
  for x = max(0, ceil(x0)), min(sky.n, floor(x1)) do
    local w, t = want(x)
    if w > 0 and t > 0.15 and t < 0.85 then need = max(need, w / (4 * t * (1 - t)) + half) end
  end
  bow = min(need, most)
  -- What the bow leaves uncleared: each end rises for what is nearer it,
  -- and both together for what is still left.
  local short = {}
  local lift0, lift1 = 0, 0
  for x = max(0, ceil(x0)), min(sky.n, floor(x1)) do
    local w, t = want(x)
    local left = w - (bow - half) * 4 * t * (1 - t)
    if left > 0 then
      short[#short + 1] = { t, left }
      if t < 0.5 then lift0 = max(lift0, left) else lift1 = max(lift1, left) end
    end
  end
  local more = 0
  for _, sh in ipairs(short) do
    local t = sh[1]
    more = max(more, sh[2] - (lift0 * (1 - t) + lift1 * t))
  end
  return y0 + d * (lift0 + more), y1 + d * (lift1 + more), bow
end

--- Place a slur's part on a system, against the skyline of its staff,
--- and add it there. A slur that starts on a system before begins after
--- the clef and key; one that ends on a system after runs to the end.
local function place_slur(st, layout, sys, sl, where)
  local s = st.sp
  local sky = sys.skies[sl.staff]
  local d = slur_side(layout, sl)
  local function end_of(ev)
    local placed = where[ev.measure]
    if not placed then return nil end
    local hw = gwidth(st, HEAD_GLYPH(ev.base))
    local cx = round(placed.x + model.x_of(placed.p, ev.start) - hw / 2) + hw / 2
    local top, bottom = sky:over(cx - hw / 2, cx + hw / 2, true)
    return cx, d < 0 and top - 0.35 * s or bottom + 0.35 * s
  end
  local x0, y0 = end_of(sl.a)
  local x1, y1 = end_of(sl.b)
  if not x0 and not x1 then
    x0, x1 = sys.signs + 0.5 * s, sys.width - 0.3 * s
    y0 = d < 0 and -0.5 * s or 4.5 * s
    y1 = y0
  elseif not x0 then
    x0, y0 = sys.signs + 0.5 * s, y1
  elseif not x1 then
    x1, y1 = sys.width - 0.3 * s, y0
  end
  if x1 - x0 < s then return end
  local bow
  y0, y1, bow = fit_slur(st, sky, x0, y0, x1, y1, d)
  local out = ink()
  arc(out, x0, y0, x1, y1, bow, d, st.slur_end, st.slur_mid, st.ink, 1 / 3)
  sky:shape(out.shape)
  sys.marks[#sys.marks + 1] = { kind = "slur", ink = out, staff = sl.staff, dy = 0,
    slur = { x0 = x0, y0 = y0, x1 = x1, y1 = y1, bow = bow, d = d } }
end

--- Place a system's marks: slurs first, then each kind of mark in its
--- order (`notation.skyline`), each clear of what is placed before.
local function place_marks(st, layout, sys, left, slurs, hairpins)
  local s = st.sp
  local where = {}
  for _, placed in ipairs(sys.measures) do where[placed.m.index] = placed end
  local first, last = sys.measures[1], sys.measures[#sys.measures]
  local from, to = first.m.start, last.m.start + last.m.length
  sys.marks, sys.lyrics = {}, {}
  -- The shorter slurs first, so that one inside another is inside it.
  local here = {}
  for _, sl in ipairs(slurs) do
    if sl.b.start >= from - EPS and sl.a.start < to - EPS then here[#here + 1] = sl end
  end
  table.sort(here, function(a, b)
    local la, lb = a.b.start - a.a.start, b.b.start - b.a.start
    if la ~= lb then return la < lb end
    return a.a.start < b.a.start
  end)
  for _, sl in ipairs(here) do place_slur(st, layout, sys, sl, where) end
  local items = {}
  local staves = #layout.staves
  local function add(item)
    local spec = skyline.kinds[item.kind]
    if not spec then return end
    item.staff = item.staff or (spec.staff == "last" and staves) or spec.staff or 1
    item.x = item.x or (item.at and x_on(st, sys, item.at))
    if not item.x or not sys.skies[item.staff] then return end
    item.system = sys
    if item.kind == "lyric" then sys.lyrics[item.staff] = true end
    items[#items + 1] = item
  end
  add({ kind = "number", x = left, value = first.m.number, staff = 1 })
  local dynamics = {}
  for _, placed in ipairs(sys.measures) do
    for _, mk in ipairs(placed.m.marks or {}) do
      if mk.kind ~= "cresc" and mk.kind ~= "dim" then
        local item = setmetatable({}, { __index = mk })
        item.kind, item.at, item.staff = mk.kind, mk.at, mk.staff
        add(item)
        if mk.kind == "dyn" and item.x then dynamics[#dynamics + 1] = item end
      end
    end
  end
  for name, spec in pairs(skyline.kinds) do
    if spec.collect then
      for _, placed in ipairs(sys.measures) do
        spec.collect(placed.m, function(item)
          item.kind = item.kind or name
          add(item)
        end)
      end
    end
  end
  -- Hairpins over the system, those begun on a system before too; clear
  -- of a dynamic at either end.
  local dyn_w = gwidth(st, "dynamicForte")
  for _, hp in ipairs(hairpins) do
    if hp.to and hp.to > from + EPS and hp.at < to - EPS then
      local x = hp.at >= from - EPS and x_on(st, sys, hp.at) or (sys.signs + 0.5 * s)
      local x1 = hp.to <= to + EPS and x_on(st, sys, hp.to, true) or (sys.width - 0.6 * s)
      for _, dyn in ipairs(dynamics) do
        local dl = dyn.x - gwidth(st, "noteheadBlack") / 2
        local name = DYN_GLYPH[dyn.value]
        local dr = dl + (name and gwidth(st, name) or dyn_w)
        if abs(dyn.at - hp.at) < EPS then x = max(x, dr + 0.4 * s) end
        if abs(dyn.at - hp.to) < EPS then x1 = min(x1, dl - 0.4 * s) end
      end
      if x and x1 then add({ kind = hp.kind, at = hp.at, to = hp.to, x = x, x1 = x1, staff = hp.staff, niente = hp.niente, ghost = hp.ghost }) end
    end
  end
  for _, item in ipairs(skyline.place(items, sys.skies, st, ink)) do
    if item.dy then sys.marks[#sys.marks + 1] = item end
  end
end

-- Systems ------------------------------------------------------------------------------------

--- The breaks a layout's score asks for, by measure (`notation.breaks`'
--- `breaks`, `joins` and `per`); a layout made of parts says its own
--- (`layout.asked`).
local function asked(layout)
  if layout.asked then return layout.asked end
  local own = layout.doc and layout.doc.layout
  if not own then return {} end
  local index = {}
  for i, m in ipairs(layout.measures) do
    if m.id then index[m.id] = i end
  end
  local out = { breaks = {}, joins = {}, per = own.per_system }
  for _, b in ipairs(own.breaks or {}) do
    local i = index[b.measure]
    if i then
      if b.kind == "join" then out.joins[i] = true else out.breaks[i] = true end
    end
  end
  return out
end
E.asked = asked

--- Systems down pages: each page `pg.height` tall, `pg.gap` between, its
--- systems from `pg.margin` (the first page's below `pg.header` more), a
--- system that does not fit starting the next. A full page's systems are
--- spread over it, by at most a sixteenth of the page between two, so
--- that a page of a few tall systems (a full score) does not open wide
--- gaps. Returns the pages (`{ y, systems }`) and their end.
local function paginate(systems, pg, y0, set_y, row)
  local pages, page = {}, nil
  local function new_page()
    local top = y0 + #pages * (pg.height + pg.gap)
    page = { y = top, systems = {}, at = top + pg.margin + (#pages == 0 and pg.header or 0) }
    pages[#pages + 1] = page
  end
  new_page()
  local limit = function() return page.y + pg.height - pg.margin end
  local function put(sys)
    page.systems[#page.systems + 1] = sys
    sys.page = #pages
    set_y(sys, page.at)
    page.at = page.at + sys.height
  end
  -- A part's page is turned after each odd page: there the page had
  -- better end with a system that ends in rests (`pg.turn(sys)`), when
  -- one does in its second half; the systems after it go over.
  local function turn_over()
    local list = page.systems
    if not pg.turn or #pages % 2 == 0 or pg.turn(list[#list]) then return {} end
    for k = #list - 1, math.max(1, math.ceil(#list / 2)), -1 do
      if pg.turn(list[k]) then
        local moved = {}
        for j = k + 1, #list do
          moved[#moved + 1] = list[j]
          list[j] = nil
        end
        page.at = list[k].y + list[k].height
        return moved
      end
    end
    return {}
  end
  for _, sys in ipairs(systems) do
    if #page.systems > 0 and page.at + sys.height > limit() then
      local moved = turn_over()
      new_page()
      for _, m in ipairs(moved) do put(m) end
    end
    put(sys)
  end
  for i, p in ipairs(pages) do
    local free = p.y + pg.height - pg.margin - p.at
    local count = #p.systems
    if i < #pages and count > 1 and free > 0 and free < pg.height / 3 then
      local each = floor(min(free / (count - 1), pg.height / 16) / row) * row
      for k, sys in ipairs(p.systems) do set_y(sys, sys.y + (k - 1) * each) end
    end
  end
  return pages, y0 + #pages * (pg.height + pg.gap) - pg.gap
end
E.paginate = paginate

--- Measures broken into systems (`notation.breaks`), each system spread
--- to the width, its marks placed against its staves' skylines and its
--- staves as far apart as those need. `o`: `width` (where systems end),
--- `x` (where they start, 0), `top`, `galley`, `spread`, `cache` (where
--- staves' ink is kept, `gui.measures`), `page` (`{ height, margin,
--- header, gap }` to lay the systems on pages). Returns `{ systems, total,
--- left, s, style, pages, cache }`; each system has `y`, `height`, `x0` (where
--- its measures start), `signs` (where its clef, key and time end),
--- `width`, `staff_top[st]`, the tab staff's `tab_top`, `skies[st]`,
--- `marks` (what is placed: `{ kind, ink, staff, dy }`) and `measures`
--- (`{ m, p, x }`: the measure, its spacing, where it starts).
function E.systems(layout, st, o)
  local s = st.sp
  local cw = st.whole and st.cell.w or 1
  local ch = st.whole and st.cell.h or 1
  local function cols(v) return ceil(v / cw - EPS) * cw end
  local function rows(v) return ceil(v / ch - EPS) * ch end
  local cache = o.cache or { generation = 0 }
  local staves = #layout.staves
  -- Room at the left for a grand staff's brace, and a score's names and
  -- brackets: the full names on the first system, the short ones after.
  local left = (o.x or 0) + cols(max(cw, (staves >= 2 and not layout.names and 1.8 or 0.8) * s))
  local full, short = E.label_room(st, layout)
  local function left_of(i) return left + cols(i == 1 and full or short) end
  local width = o.width
  local spaced_of = {}
  for i, m in ipairs(layout.measures) do spaced_of[i] = spaced(m, st, o.spread or 1) end
  local n = #layout.measures
  local function begins(i) return cols((prefix(st, layout, i, left_of(i)))) end
  local starts = { 1 }
  if not o.galley then
    local widths = {}
    for i = 1, n do widths[i] = spaced_of[i].width end
    starts = breaks.lines(widths, begins, width - cw, asked(layout))
  end
  local slurs, hairpins = spanners(layout)
  local systems = {}
  local staff_h = 4 * s
  local tab = layout.tab
  for k, first in ipairs(starts) do
    local x0 = begins(first)
    local sys_left = left_of(first)
    local _, signs = prefix(st, layout, first, sys_left)
    local sys = { measures = {}, x0 = x0, signs = signs, first = first, layout_measures = layout.measures, left = sys_left }
    local x = x0
    for j = first, (starts[k + 1] or n + 1) - 1 do
      local p = spaced_of[j]
      sys.measures[#sys.measures + 1] = { m = layout.measures[j], p = p, x = x }
      x = x + p.width
    end
    -- Every system is spread to the full width, as on a page, but a last
    -- one under three quarters full; each barline on a whole cell column.
    local target = x
    if not o.galley and (starts[k + 1] or x - x0 >= 0.75 * (width - cw - x0)) then target = width - cw end
    local factor = (target - x0) / max(1, x - x0)
    local at, natural = x0, x0
    for _, placed in ipairs(sys.measures) do
      natural = natural + placed.p.width * factor
      local right = max(at + cw, floor(natural / cw + 0.5) * cw)
      stretch(placed.p, right - at)
      placed.x = at
      at = right
    end
    sys.width = at
    -- Each staff's skyline: the staff, its clef, its measures.
    local reach = at + 4 * s
    sys.skies = {}
    for k2 = 1, staves do
      local sky = skyline.new(reach, 0, staff_h + st.line)
      local fm = layout.measures[first]
      local cg = CLEF_GLYPH[fm.clefs and fm.clefs[k2] or layout.staves[k2]] or CLEF_GLYPH.treble
      local bb = glyph(st, cg[1]).bbox
      local cy = staff_y(st, cg[2])
      sky:box(sys_left, cy - bb[4] * s, signs, cy - bb[2] * s)
      local name = layout.names and layout.names[k2]
      if name and name ~= "" then
        local size = max(10, round(1.1 * s))
        sky:box(sys_left, -2.4 * s + 0.2 * size, sys_left + #name * 0.56 * size, -2.4 * s + 1.2 * size)
      end
      for _, placed in ipairs(sys.measures) do
        sky:merge(staff_sky(st, E.staff(cache, st, placed.m, placed.p, k2), placed.p.width), placed.x)
      end
      sys.skies[k2] = sky
    end
    place_marks(st, layout, sys, sys_left, slurs, hairpins)
    -- The staves as far apart as their skylines need.
    local rel = {}
    local top1 = sys.skies[1]:over(0, reach)
    rel[1] = round(max(2.5 * s, -top1 + 0.6 * s))
    for k2 = 2, staves do
      rel[k2] = round(rel[k2 - 1] + max(staff_h + 3.5 * s, skyline.distance(sys.skies[k2 - 1], sys.skies[k2], 1.0 * s)))
    end
    local _, low = sys.skies[staves]:over(0, reach)
    local bottom = rel[staves] + max(staff_h + 2 * s, low + 1.0 * s)
    if tab then
      sys.tab_line = round(1.5 * s)
      sys.tab_rel = round(rel[staves] + max(staff_h + 3 * s, low + 1.5 * s))
      bottom = sys.tab_rel + (tab.strings - 1) * sys.tab_line + s
    end
    sys.rel = rel
    sys.height = rows(bottom)
    systems[#systems + 1] = sys
  end
  local function set_y(sys, y)
    sys.y = y
    sys.staff_top = {}
    for k = 1, staves do sys.staff_top[k] = y + sys.rel[k] end
    if sys.tab_rel then sys.tab_top = y + sys.tab_rel end
  end
  local y = o.top or 0
  local pages
  if o.page and not o.galley then
    o.page.turn = o.page.turn or (layout.turns and function(sys)
      local last = sys.measures[#sys.measures]
      return layout.turns[last.m.index] == true
    end)
    pages, y = paginate(systems, o.page, y, set_y, ch)
  else
    for _, sys in ipairs(systems) do
      set_y(sys, y)
      y = y + sys.height
    end
  end
  return { systems = systems, total = y, left = left, s = s, style = st, pages = pages, cache = cache }
end


-- What starts and spans a system -------------------------------------------------------------

--- The size of a score's instrument names.
local function label_size(st) return max(10, round(1.2 * st.sp)) end

--- How much room a score's names and brackets take at the left of its
--- first system and of the others: `layout.labels` (`{ first, last, full,
--- short }`, a name for staves `first` to `last`) and `layout.brackets`.
function E.label_room(st, layout)
  if not layout.labels then return 0, 0 end
  local size = label_size(st)
  local full, short = 0, 0
  for _, l in ipairs(layout.labels) do
    full = max(full, text_width(l.full or "", size))
    short = max(short, text_width(l.short or "", size))
  end
  local bracket = (layout.brackets and #layout.brackets > 0) and 1.2 * st.sp or 0
  return (full > 0 and full + 0.8 * st.sp or 0) + bracket, (short > 0 and short + 0.8 * st.sp or 0) + bracket
end

--- A score's names, brackets (each family of instruments) and braces (an
--- instrument of two staves) at the start of a system.
local function label_ink(out, st, layout, sys, Y, left)
  local s = st.sp
  local brackets = layout.brackets or {}
  local brace_room = (#layout.staves >= 2 and not layout.names and 1.8 or 0.8) * s
  local bx = round(left - brace_room - (#brackets > 0 and 0.5 * s or 0))
  for _, b in ipairs(brackets) do
    local top, bottom = round(Y(b[1], 8) - 0.6 * s), round(Y(b[2], 0) + 0.6 * s)
    local th = round(0.5 * s)
    out:rect(bx, top, th, bottom - top, st.ink)
    -- The hooks at either end, curving out to the right.
    out:path({ "M", bx, top + th, "L", bx, top, "C", bx + 0.8 * s, top, bx + 1.4 * s, top - 0.2 * s, bx + 1.8 * s, top - 0.7 * s,
      "C", bx + 1.4 * s, top + 0.1 * s, bx + 0.8 * s, top + th, bx, top + th, "Z" }, "", 1, st.ink)
    out:path({ "M", bx, bottom - th, "L", bx, bottom, "C", bx + 0.8 * s, bottom, bx + 1.4 * s, bottom + 0.2 * s, bx + 1.8 * s, bottom + 0.7 * s,
      "C", bx + 1.4 * s, bottom - 0.1 * s, bx + 0.8 * s, bottom - th, bx, bottom - th, "Z" }, "", 1, st.ink)
  end
  for _, b in ipairs(layout.braces or {}) do
    local top, bottom = round(Y(b[1], 8) - st.line / 2), round(Y(b[2], 0) + st.line / 2)
    local h = bottom - top
    out:glyph(st, round(left - 0.4 * s - gwidth(st, "brace") * h / (4 * s)), bottom, "brace", st.ink, h / (4 * s))
  end
  local size = label_size(st)
  local right = bx - (#brackets > 0 and 0.4 * s or 0)
  for _, l in ipairs(layout.labels or {}) do
    local text = sys.first == 1 and l.full or l.short
    if text and text ~= "" then
      local mid = (Y(l.first, 4) + Y(l.last, 4)) / 2
      out:text(round(right), round(mid - 0.7 * size), text, st.ink, size, false, "right", right)
    end
  end
end

--- The system's own ink, in coordinates from the page's left edge and the
--- system's top, as two parts: what starts it (staff lines up to the
--- first measure, the left barline and brace, clefs, key and time
--- signatures, names, the first measure's number), which the galley keeps
--- at the left; and what spans its measures (time signatures that change
--- inside it, ties across barlines, and what is placed against the
--- skylines: slurs, dynamics, hairpins, text, lyrics and the rest).
function E.system_ink(st, layout, sys, eng)
  local s, out, spans = st.sp, ink(), ink()
  local colour = st.ink
  local nstaves = #layout.staves
  local sy = sys.y
  local function Y(staff, pos) return E.y_of(st, sys, staff, pos) - sy end
  local left = sys.left or eng.left
  local right = sys.measures[1].x
  local top_y, bottom_y = round(Y(1, 8) - st.line / 2), round(Y(nstaves, 0) + st.line / 2)
  local first_m = sys.measures[1].m
  for staff, clef in ipairs(layout.staves) do
    clef = first_m.clefs and first_m.clefs[staff] or clef
    for pos = 0, 8, 2 do
      out:rect(left, round(Y(staff, pos) - st.line / 2), right - left, st.line, st.staff)
    end
    if layout.names and layout.names[staff] and layout.names[staff] ~= "" then
      out:text(left, round(Y(staff, 8) - 2.4 * s), layout.names[staff], st.faint, max(10, round(1.1 * s)))
    end
    local cx = round(left + 0.6 * s)
    local cg = CLEF_GLYPH[clef] or CLEF_GLYPH.treble
    out:glyph(st, cx, round(Y(staff, cg[2])), cg[1], colour)
    local x = cx + gwidth(st, "gClef") + 0.8 * s
    local fifths = first_m.fifths or layout.fifths
    if fifths ~= 0 then
      local name = fifths > 0 and "accidentalSharp" or "accidentalFlat"
      for _, pos in ipairs(model.key_positions(fifths, clef)) do
        out:glyph(st, round(x), round(Y(staff, pos)), name, colour)
        x = x + gwidth(st, name) + 0.12 * s
      end
      x = x + 0.6 * s
    end
    local first = sys.measures[1].m
    if meter_changes(layout, first.index) then
      local tw = time_width(st, first.meter)
      for k, digits in ipairs({ tostring(first.meter.num), tostring(first.meter.den) }) do
        local dw = 0
        for ch in digits:gmatch("%d") do dw = dw + gwidth(st, "timeSig" .. ch) end
        local dx = x + (tw - dw) / 2
        for ch in digits:gmatch("%d") do
          out:glyph(st, round(dx), round(Y(staff, k == 1 and 6 or 2)), "timeSig" .. ch, colour)
          dx = dx + gwidth(st, "timeSig" .. ch)
        end
      end
    end
  end
  for _, span in ipairs(E.bar_spans(layout)) do
    local y0, y1 = round(Y(span[1], 8) - st.line / 2), round(Y(span[2], 0) + st.line / 2)
    out:rect(left, y0, st.bar, y1 - y0, colour)
  end
  if layout.labels then
    label_ink(out, st, layout, sys, Y, left)
  elseif nstaves >= 2 and not layout.names then
    -- A grand staff's brace.
    local h = bottom_y - top_y
    out:glyph(st, round(left - 0.4 * s - gwidth(st, "brace") * h / (4 * s)), bottom_y, "brace", colour, h / (4 * s))
  end
  local tab = layout.tab
  if tab and sys.tab_top then
    local t0 = sys.tab_top - sy
    for i = 1, tab.strings do out:rect(left, t0 + (i - 1) * sys.tab_line, right - left, st.line, st.staff) end
    out:rect(left, t0, st.bar, (tab.strings - 1) * sys.tab_line + st.line, colour)
    local mid = t0 + (tab.strings - 1) * sys.tab_line / 2
    for k, letter in ipairs({ "T", "A", "B" }) do
      out:text(round(left + 0.9 * s), round(mid + (k - 2.5) * 1.4 * s), letter, colour, round(1.3 * s), true)
    end
  end
  -- Time signatures that change inside the system.
  for k = 2, #sys.measures do
    local placed = sys.measures[k]
    if meter_changes(layout, placed.m.index) then
      for staff = 1, nstaves do
        local dx = placed.x + 0.5 * s
        for row, digits in ipairs({ tostring(placed.m.meter.num), tostring(placed.m.meter.den) }) do
          local x = dx
          for ch in digits:gmatch("%d") do
            spans:glyph(st, round(x), round(Y(staff, row == 1 and 6 or 2)), "timeSig" .. ch, colour)
            x = x + gwidth(st, "timeSig" .. ch)
          end
        end
      end
    end
  end

  -- Ties that cross a barline: they belong to two measures. A tie from
  -- the system before begins after the clef and key, as long as a tie.
  local where = {}
  for _, placed in ipairs(sys.measures) do where[placed.m.index] = placed end
  for k, placed in ipairs(sys.measures) do
    local m = placed.m
    local function xt(beat) return placed.x + model.x_of(placed.p, beat) end
    for staff = 1, nstaves do
      for ei, ev in ipairs(m.staves[staff] or {}) do
        if ev.notes then
          local hw = gwidth(st, HEAD_GLYPH(ev.base))
          for i, n in ipairs(ev.notes) do
            local dir, outside = tie_side(ev, i)
            local hx = round(xt(ev.start) - hw / 2)
            if n.tie and ev.next and ev.next.measure ~= ev.measure then
              local target = where[ev.next.measure]
              local nx = target and round(target.x + model.x_of(target.p, ev.next.start) - hw / 2)
              local x0, x1, y = tie_ends(st, hw, hx, nx, Y(staff, n.pos), dir, outside, ev.dots > 0)
              tie(spans, st, x0, x1 or (sys.width + 0.3 * s), y, dir, colour)
            end
            if n.tied and k == 1 and ei == 1 then
              local _, x1, y = tie_ends(st, hw, hx, hx, Y(staff, n.pos), dir, outside, false)
              local x0 = min(sys.signs + 0.4 * s, x1 - s)
              tie(spans, st, x0, x1, y, dir, colour)
            end
          end
        end
      end
    end
  end
  -- What was placed against the skylines, each where its staff is.
  for _, item in ipairs(sys.marks or {}) do
    offset(item.ink, item.kind == "number" and out or spans, sys.staff_top[item.staff] - sy + item.dy)
  end
  return out, spans
end

return E
