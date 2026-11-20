-- The pitch a note sings by itself, as OpenUtau works it out: the transition
-- into the note (its pitch points, `note.meta.utau.pp`) and its vibrato
-- (`note.meta.utau.vb`). Pure functions on note tables, for the editor to
-- draw and edit them; the engine does the same sums when it sings.
--
--   pp = { snap = true, pts = { { x_ms, y_tenths, shape }, ... } }
--     x in milliseconds from the note's start, y in tenths of a semitone
--     from the note's pitch; `shape` says how the line goes on to the next
--     point: 0 ease in and out, 1 straight, 2 ease in, 3 ease out. With
--     `snap` the first point starts at the previous note's pitch when that
--     note ends where this one starts.
--   vb = { length, period, depth, in, out, shift, drift, vol_link }
--     length in % of the note (from its end), period in ms, depth in cents,
--     fade in and out in % of the vibrato, shift in % of a period, drift in
--     % of the depth, volume link in %.
local M = {}

M.SHAPES = { [0] = "ease in and out", "straight", "ease in", "ease out" }
M.SHAPE_SHORT = { [0] = "io", "l", "i", "o" }
--- OpenUtau's default transition: 80 ms around the note's start.
M.DEFAULT_PP = { snap = true, pts = { { -40, 0, 0 }, { 40, 0, 0 } } }
--- OpenUtau's vibrato when it is switched on.
M.DEFAULT_VB = { 75, 175, 25, 10, 10, 0, 0, 0 }
M.VB_FIELDS = {
  { i = 1, key = "length", name = "Length", unit = "%", min = 0, max = 100, step = 0.5 },
  { i = 2, key = "period", name = "Period", unit = "ms", min = 64, max = 512, step = 1 },
  { i = 3, key = "depth", name = "Depth", unit = "c", min = 5, max = 200, step = 1 },
  { i = 4, key = "in", name = "Fade in", unit = "%", min = 0, max = 100, step = 0.5 },
  { i = 5, key = "out", name = "Fade out", unit = "%", min = 0, max = 100, step = 0.5 },
  { i = 6, key = "shift", name = "Shift", unit = "%", min = 0, max = 100, step = 0.5 },
  { i = 7, key = "drift", name = "Drift", unit = "%", min = -100, max = 100, step = 0.5 },
  { i = 8, key = "vol_link", name = "Volume link", unit = "%", min = 0, max = 100, step = 0.5 },
}

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

M.copy = copy

local clamp = paw.util.clamp
M.clamp = clamp

--- Milliseconds as beats at a tempo, and back.
function M.beats(ms, tempo) return ms / 1000 * tempo / 60 end
function M.ms(beats, tempo) return beats * 60 / tempo * 1000 end

local function props(note) return note.meta and type(note.meta.utau) == "table" and note.meta.utau or {} end

--- A note's transition: its own, or the default. A copy, safe to change.
function M.pp(note)
  local pp = props(note).pp
  if type(pp) ~= "table" or type(pp.pts) ~= "table" or #pp.pts < 1 then return copy(M.DEFAULT_PP) end
  local out = { snap = pp.snap ~= false, pts = {} }
  for i, p in ipairs(pp.pts) do out.pts[i] = { p[1] or 0, p[2] or 0, p[3] or 0 } end
  table.sort(out.pts, function(a, b) return a[1] < b[1] end)
  return out
end

--- Whether the note has a transition of its own.
function M.has_pp(note)
  local pp = props(note).pp
  return type(pp) == "table" and type(pp.pts) == "table" and #pp.pts > 0
end

--- A note's vibrato, or nil when it has none.
function M.vb(note)
  local vb = props(note).vb
  if type(vb) ~= "table" or (vb[1] or 0) <= 0 then return nil end
  local out = {}
  for i = 1, 8 do out[i] = vb[i] or 0 end
  return out
end

--- The points of a transition as they are sung: the first one moved to the
--- previous note's pitch when it snaps. `prev` is the note before, or nil.
function M.points(note, prev, pp)
  pp = pp or M.pp(note)
  local pts = copy(pp.pts)
  if pp.snap and pts[1] then
    if prev and math.abs(prev.start + prev.length - note.start) < 1e-6 then
      pts[1][2] = (prev.pitch - note.pitch) * 10
    else
      pts[1][2] = 0
    end
  end
  return pts
end

--- How a shape goes from 0 to 1 as `t` goes from 0 to 1.
function M.ease(shape, t)
  if shape == 1 then return t end
  if shape == 2 then return 1 - math.cos(math.pi / 2 * t) end
  if shape == 3 then return math.sin(math.pi / 2 * t) end
  return (1 - math.cos(math.pi * t)) / 2
end

--- The transition's offset from the note's pitch, in semitones, at `ms`
--- from the note's start; nil outside it.
function M.transition_at(pts, ms)
  if #pts == 0 or ms < pts[1][1] or ms > pts[#pts][1] then return nil end
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    if ms <= b[1] then
      if b[1] - a[1] < 1e-9 then return b[2] / 10 end
      return (a[2] + (b[2] - a[2]) * M.ease(a[3], (ms - a[1]) / (b[1] - a[1]))) / 10
    end
  end
  return pts[#pts][2] / 10
end

--- The vibrato's offset in cents at `pos` (0 at the note's start, 1 at its
--- end), for a note `dur_ms` long; 0 outside the vibrato.
function M.vibrato_at(vb, pos, dur_ms)
  if not vb or vb[1] <= 0 or dur_ms <= 0 then return 0 end
  local length = vb[1] / 100
  local start = 1 - length
  if pos < start or pos > 1 then return 0 end
  local fade_in, fade_out = length * vb[4] / 100, length * vb[5] / 100
  local period = vb[2] / dur_ms
  local t = (pos - start) / period + vb[6] / 100
  local y = math.sin(2 * math.pi * t) * vb[3] + vb[3] * vb[7] / 100
  if fade_in > 0 and pos < start + fade_in then
    y = y * (pos - start) / fade_in
  elseif fade_out > 0 and pos > 1 - fade_out then
    y = y * (1 - pos) / fade_out
  end
  return y
end

--- Where the vibrato's handles are, as `{ beat, cents }` from the note's
--- start and its pitch: where it starts (length), its fades, its depth, a
--- period, a trough (shift) and its drift.
function M.vibrato_handles(note, vb, tempo)
  local len = note.length
  local vlen = len * vb[1] / 100
  local v0, v1 = len - vlen, len
  local period = M.beats(vb[2], tempo)
  local trough = ((0.75 - vb[6] / 100) % 1) * period
  return {
    length = { v0, 0 },
    ["in"] = { v0 + vlen * vb[4] / 100, vb[3] },
    out = { v1 - vlen * vb[5] / 100, vb[3] },
    depth = { (v0 + vlen * vb[4] / 100 + v1 - vlen * vb[5] / 100) / 2, vb[3] },
    period = { math.min(v1, v0 + period), 0 },
    shift = { math.min(v1, v0 + trough), -vb[3] },
    drift = { v1, vb[3] * vb[7] / 100 },
  }
end

--- Change a vibrato by dragging one of its handles `dbeat` beats sideways
--- and `dcents` up, from the values `vb0` it had when the drag began.
function M.drag_vibrato(vb0, which, note, dbeat, dcents, tempo)
  local vb = copy(vb0)
  local len = note.length
  local vlen = len * vb0[1] / 100
  if which == "length" then
    vb[1] = clamp(vb0[1] - dbeat / len * 100, 1, 100)
  elseif which == "in" and vlen > 0 then
    vb[4] = clamp(vb0[4] + dbeat / vlen * 100, 0, 100 - vb0[5])
  elseif which == "out" and vlen > 0 then
    vb[5] = clamp(vb0[5] - dbeat / vlen * 100, 0, 100 - vb0[4])
  elseif which == "depth" then
    vb[3] = clamp(vb0[3] + dcents, 5, 200)
  elseif which == "period" then
    vb[2] = clamp(vb0[2] + M.ms(dbeat, tempo), 64, 512)
  elseif which == "shift" then
    vb[6] = (vb0[6] - M.ms(dbeat, tempo) / vb0[2] * 100) % 100
  elseif which == "drift" then
    vb[7] = clamp(vb0[7] + dcents / math.max(1, vb0[3]) * 100, -100, 100)
  end
  for i = 1, 8 do vb[i] = math.floor(vb[i] * 10 + 0.5) / 10 end
  return vb
end

--- Set (or with `nil` take away) a whole-note expression (`ex`) in a note's
--- properties.
function M.set_expression(p, abbr, value)
  local list = type(p.ex) == "table" and p.ex or {}
  for i = #list, 1, -1 do
    if list[i][1] == abbr and (list[i][3] or -1) == -1 then table.remove(list, i) end
  end
  if value ~= nil then list[#list + 1] = { abbr, value, -1 } end
  p.ex = #list > 0 and list or nil
end

return M
