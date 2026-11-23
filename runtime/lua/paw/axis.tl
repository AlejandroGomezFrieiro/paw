-- The time axis of a view: where each beat is drawn, in cells, and which
-- beat a cell shows. Every row of a time view (the ruler, the markers,
-- the clips, the take lanes, the curves, the playhead, the cursor, the
-- selection, the loop and the grid lines) and the pointer go through one
-- axis, so that a beat is in the same column on each row.
--
--   local ax = paw.axis.new(scroll, zoom, spans)  -- spans: the time folds, or nil
--   ax:x_of(beat)          the cell that contains the beat
--   ax:range(a, b)         the cells of a stretch: the first, and the one after the last
--   ax:beat_of(x)          the beat at a column (fractions of a cell)
--   ax:cell_span(x)        the beats that a cell shows
--
-- The one rule of rounding: a beat goes to the cell that contains it.
-- Cell `c` shows the beats from `beat_of(c)` up to `beat_of(c + 1)`. A
-- stretch from `a` to `b` takes the cells from the one of `a` up to the
-- one of `b`, that cell not included, and one cell at least. Two stretches
-- side by side so do not take the same cell.
--
-- A thing drawn inside a box of cells (the notes or the sound in a clip)
-- places its own beats by the box's `phase`: how far into its first cell
-- the box begins. Then its cells agree with the axis.
--
-- Time folds: a folded stretch is one narrow column of `cells` cells. The
-- axis counts in the beats of the view (`view`): a folded stretch is
-- `cells` cells of them wide, and the beats after it move left.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.

-- A beat on the edge of a cell is in the cell after it. Sums of beats in
-- floating point can come a little short of the edge: this much of a cell
-- is still the edge.
local EDGE = 1e-6

local record M
  --- A folded stretch of time (paw/folds.tl): its beats and its columns.
  interface Folded
    from: number
    to: number
    cells: integer
  end

  --- The axis of a view. `scroll` is the beat at its left edge, `zoom`
  --- the cells a beat, `spans` the time folds in order (none when empty),
  --- `left` the place of `scroll` in the beats of the view.
  record Axis
    scroll: number
    zoom: number
    spans: {Folded}
    left: number
  end
end

local type Axis = M.Axis
local type Folded = M.Folded
local AxisMeta = Axis as metatable<Axis>
AxisMeta.__index = Axis

--- The cell that a place `x` (in fractions of a cell) is in: the rule of
--- rounding of each axis. Roles that place beats in cells use it too.
function M.cell(x: number): integer
  return math.floor(x + EDGE)
end

--- The place of a beat in the beats of the view: the beats of a folded
--- stretch are at its column's start, and the beats after it move left.
function Axis:view(beat: number): number
  local cut = 0.0
  for _, s in ipairs(self.spans) do
    if beat <= s.from then
      break
    end
    if beat < s.to then
      return s.from - cut
    end
    cut = cut + (s.to - s.from) - s.cells / self.zoom
  end
  return beat - cut
end

--- The beat at a place in the beats of the view: on a folded column, the
--- start of what it folds.
function Axis:unview(v: number): number
  local cut = 0.0
  for _, s in ipairs(self.spans) do
    local at = s.from - cut
    if v < at then
      break
    end
    local width = s.cells / self.zoom
    if v < at + width then
      return s.from
    end
    cut = cut + (s.to - s.from) - width
  end
  return v + cut
end

--- A new axis: `scroll` the beat at the left edge, `zoom` the cells a
--- beat, `spans` the time folds in order of their beats (optional).
function M.new(scroll: number, zoom: number, spans?: {Folded}): Axis
  local ax = setmetatable({scroll = scroll, zoom = zoom, spans = spans or {}, left = scroll} as Axis, AxisMeta)
  ax.left = ax:view(scroll)
  return ax
end

--- A length of `beats` of the view in cells, not rounded: for a room or a
--- width that is measured, not drawn.
function Axis:cells(beats: number): number
  return beats * self.zoom
end

--- A length of `cells` in beats of the view.
function Axis:beats(cells: number): number
  return cells / self.zoom
end

--- Where a beat is, in cells from the left edge, with the fraction.
function Axis:exact(beat: number): number
  return (self:view(beat) - self.left) * self.zoom
end

--- The cell that contains a beat, from the left edge.
function Axis:x_of(beat: number): integer
  return M.cell(self:exact(beat))
end

--- How far into its first cell a box begins that is marked at place `v`
--- of the plane (beats of the view, as `view` gives them), from 0 up to 1:
--- what a box adds to the places of the beats inside it, so that each
--- goes to the cell the axis gives it.
function Axis:phase_at(v: number): number
  local x = (v - self.left) * self.zoom
  return x - M.cell(x)
end

--- The cells of the stretch from beat `a` to beat `b`: the first, and
--- the one after the last. One cell at least.
function Axis:range(a: number, b: number): integer, integer
  local x0 = self:x_of(a)
  return x0, math.max(x0 + 1, self:x_of(b))
end

--- The beat at a column `x` (in fractions of a cell): on a folded column,
--- the start of what it folds.
function Axis:beat_of(x: number): number
  return self:unview(self.left + x / self.zoom)
end

--- The beats that cell `x` shows: from its left edge up to the next cell's.
function Axis:cell_span(x: integer): number, number
  return self:beat_of(x), self:beat_of(x + 1)
end

--- The beat in the middle of half cell `i` (two a cell): where a curve or a
--- waveform drawn in half cells reads its value.
function Axis:half_beat(i: integer): number
  return self:beat_of((i + 0.5) / 2)
end

--- The step of a grid of `grid` beats that cell `x` shows: the first step
--- that starts in it, or, when none does, the step that it is in. A press
--- on a cell so goes to the step drawn there.
function Axis:step_at(x: integer, grid: number): number
  local from = self:beat_of(x)
  local first = math.ceil(from / grid - EDGE) * grid
  if self:x_of(first) == x then
    return first
  end
  return math.floor(from / grid + EDGE) * grid
end

--- The folded stretch drawn at column `x`, or nil: its cells start in
--- the cell of its first beat, as each box does.
function Axis:fold_at(x: number): Folded
  for _, s in ipairs(self.spans) do
    local x0 = self:x_of(s.from)
    if x >= x0 and x < x0 + s.cells then
      return s
    end
  end
end

--- The stretches of `a` to `b` that are not folded away, as `{ from, to }`.
function Axis:unfolded(a: number, b: number): {{number, number}}
  local out: {{number, number}} = {}
  local at = a
  for _, s in ipairs(self.spans) do
    if s.to > at and s.from < b then
      if s.from > at then
        out[#out + 1] = {at, s.from}
      end
      at = math.max(at, s.to)
    end
  end
  if at < b then
    out[#out + 1] = {at, b}
  end
  return out
end

--- Whether a beat is inside a folded stretch, after its start.
function Axis:folded(beat: number): boolean
  for _, s in ipairs(self.spans) do
    if beat > s.from + 1e-9 and beat < s.to - 1e-9 then
      return true
    end
  end
  return false
end

return M
