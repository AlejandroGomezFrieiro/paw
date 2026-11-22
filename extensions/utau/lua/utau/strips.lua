-- The vocal editor's pitch and curves in pixels, where the terminal shows
-- pictures (`buf:strip`): under the notes, the line each note is sung on
-- (its transition from the note before and its vibrato, as the window's
-- Pitch tool draws them, plus the pitch curve) and the pitch the engine
-- sang; under the curve rows, the chosen curve through `paw.plot`. The
-- notes, lyrics, cursor and playhead stay cells, drawn over the pictures.
-- Each drawing is cut at the bars, so that an edit sends again only the
-- bars it touched.
local api = paw.api
local notes = require("utau.notes")
local shapes = require("utau.shapes")
local proto = require("utau.proto")

local M = {}

local floor = math.floor

local function palette() return require("paw.theme").palette end

--- Where the drawing `w` pixels wide may be cut, from the project beat
--- `from` at `ppb` pixels a beat: 0, each bar on a cell's edge, and `w`.
local function edges(g, w, h, from, ppb, cw)
  local out = { 0 }
  for _, line in ipairs(paw.plot.lines(w, from, ppb, cw)) do
    if line.cut and line.cut > out[#out] and line.cut < w then
      out[#out + 1] = line.cut
      g:cut(line.cut, 0, h)
    end
  end
  out[#out + 1] = w
  return out
end

--- Draw `value(x)`, a height in pixels or nil for none, once a pixel
--- across, as lines broken where it has none and at the cuts.
local function trace(g, cuts, value, style)
  for i = 1, #cuts - 1 do
    local line = {}
    for x = cuts[i], cuts[i + 1] do
      local y = value(x)
      if y then
        line[#line + 1] = x
        line[#line + 1] = y
      else
        if #line >= 4 then g:poly(line, style) end
        line = {}
      end
    end
    if #line >= 4 then g:poly(line, style) end
  end
end

--- The pitch a clip's notes are sung on, in semitones, at a beat of the
--- clip: the note's own, its transition from the note before (which may
--- begin before the note does), its vibrato and the pitch curve. A
--- function of beats that only go up, nil where no note sounds.
function M.written(list, tempo, pitd)
  local cache = {}
  local function shape_of(k)
    if not cache[k] then
      local note = list[k]
      cache[k] = { pts = shapes.points(note, list[k - 1]), vb = shapes.vb(note), dur = shapes.ms(note.length, tempo) }
    end
    return cache[k]
  end
  local over = notes.walker(list)
  return function(beat)
    local note, k = over(beat)
    local next_k = (k or 0) + 1
    local after = list[next_k]
    -- The next note's transition, once it has begun, over a note still
    -- sounding: none starts in a rest, where no cells are.
    if after and note and beat < note.start + note.length then
      local s = shape_of(next_k)
      local ms = shapes.ms(beat - after.start, tempo)
      if s.pts[1] and ms >= s.pts[1][1] then
        note, k = after, next_k
      end
    end
    if not note or beat > note.start + note.length + 1e-9 then return nil end
    local s = shape_of(k)
    local ms = shapes.ms(beat - note.start, tempo)
    local semis = note.pitch + (shapes.transition_at(s.pts, ms) or 0)
    semis = semis + shapes.vibrato_at(s.vb, (beat - note.start) / note.length, s.dur) / 100
    return semis + (pitd and pitd(beat) or 0) / 100
  end
end

--- Where beats are across the roll, in pixels, so that the lines meet the
--- notes' edges: a note's cells start and end where its beats round to
--- (`floor(cells + 0.5)`), and the beats between are spread evenly over
--- them. Returns `x(beat)` and `beat(x)`.
function M.warp(list, scroll, zoom, cw)
  local knots = {}
  local function put(beat)
    local x = floor((beat - scroll) * zoom + 0.5) * cw
    local last = knots[#knots]
    if not last or (beat > last[2] + 1e-9 and x >= last[1]) then knots[#knots + 1] = { x, beat } end
  end
  for _, n in ipairs(list) do
    put(n.start)
    put(n.start + n.length)
  end
  local ppb = zoom * cw
  local function between(a, b, from, to, v)
    if not a then return nil end
    if not b or a[from] == b[from] then return a[to] + (v - a[from]) * (to == 1 and ppb or 1 / ppb) end
    return a[to] + (v - a[from]) * (b[to] - a[to]) / (b[from] - a[from])
  end
  -- Asked in order, mostly: the search starts where the last one ended.
  local hint = { 2, 2 }
  local function find(v, from, to)
    if #knots == 0 then return to == 1 and (v - scroll) * ppb or scroll + v / ppb end
    if v <= knots[1][from] then return between(knots[1], nil, from, to, v) end
    local i = hint[from]
    if i > #knots or v < knots[i - 1][from] then i = 2 end
    while i <= #knots and v > knots[i][from] do
      i = i + 1
    end
    hint[from] = math.max(2, math.min(i, #knots))
    if i > #knots then return between(knots[#knots], nil, from, to, v) end
    return between(knots[i - 1], knots[i], from, to, v)
  end
  return function(beat) return find(beat, 2, 1) end, function(x) return find(x, 1, 2) end
end

--- The roll's picture. `o`: `list` (the clip's notes), `clip`, `scroll`
--- (the beat of the clip at the left edge), `zoom` (cells a beat), `top`
--- (the pitch of the first row), `pitd` (the pitch curve's points, as
--- lanes give them, or nil), `sung` (the engine's pitch: `{ step, ticks }`).
function M.roll(g, px, o)
  local P = palette()
  local cw, ch = px.cell.w, px.cell.h
  local ppb = o.zoom * cw
  local function Y(semis) return (o.top - semis) * ch + ch / 2 end
  local cuts = edges(g, px.w, px.h, o.clip.start + o.scroll, ppb, cw)
  local pitd = o.pitd and #o.pitd > 0 and notes.sampler(o.pitd, 0) or nil
  local tempo = api.project_get("tempo")
  local written = M.written(o.list, tempo, pitd and function(beat) return pitd(o.clip.start + beat) end)
  local length = o.clip.length
  local x_at, beat_at = M.warp(o.list, o.scroll, o.zoom, cw)
  trace(g, cuts, function(x)
    local beat = beat_at(x)
    if beat > length then return nil end
    local semis = written(beat)
    return semis and Y(semis)
  end, { color = P.orange, width = 1.5 })
  local sung = o.sung
  if not sung then return end
  -- The engine's pitch: a point every `step` ticks, broken where it is not
  -- voiced and at the cuts.
  local step = sung.step or 5
  local first = math.max(0, floor(o.scroll * proto.TICKS / step) * step)
  local last = (o.scroll + px.w / ppb) * proto.TICKS + step
  local cut, line, prev = 2, {}, nil
  local style = { color = "#ffffff", width = 1.5 }
  for tick = first, last, step do
    local cents = sung.ticks[tick]
    local x = x_at(tick / proto.TICKS)
    while cuts[cut] and x > cuts[cut] do
      -- Across a cut: the line ends a point past it and starts again a
      -- point before it.
      if cents and prev then
        line[#line + 1], line[#line + 2] = x, Y(cents / 100)
        if #line >= 4 then g:poly(line, style) end
        line = { prev[1], prev[2] }
      end
      cut = cut + 1
    end
    if cents then
      line[#line + 1], line[#line + 2] = x, Y(cents / 100)
      prev = { x, Y(cents / 100) }
    else
      if #line >= 4 then g:poly(line, style) end
      line, prev = {}, nil
    end
  end
  if #line >= 4 then g:poly(line, style) end
end

--- The curve rows' picture: a curve of the vocal device. `o`: `info` (the
--- curve: `key`, `min`, `max`, `default`), `points` (its lane's, or none),
--- `constant` (the value with no points), `clip`, `scroll`, `zoom`.
function M.curve(g, px, o)
  local P = palette()
  local points = {}
  for i, p in ipairs(o.points or {}) do
    points[i] = { beat = p[1], value = p[2], shape = "linear", tension = 0 }
  end
  -- Up to the clip's end, as the notes go.
  local ppb = o.zoom * px.cell.w
  local w = math.min(px.w, floor((o.clip.length - o.scroll) * ppb + 0.5))
  if w <= 0 then return end
  local part = { w = w, h = px.h, cell = px.cell, fg = px.fg, bg = px.bg }
  g = g:sub(0, 0, w, px.h)
  local _, Y = paw.plot.curve(g, part, {
    points = points,
    from = o.clip.start + o.scroll,
    pixels_per_beat = ppb,
    lo = o.info.min,
    hi = o.info.max,
    flat = #points == 0 and o.constant or nil,
    color = P.green,
    guides = false,
    markers = false,
  })
  -- The default, as a line across.
  g:rect(0, floor(Y(o.info.default)), w, 1, { fill = paw.plot.alpha(P.dim, 0.6) })
end

return M
