-- The grid of time: positions in ticks, and the lines that grid motions
-- stop on. One module owns the grid, so that each view, each lane and
-- each extension stops on the same lines.
--
--   local g = paw.timegrid.window()          the grid of the window with the keys
--   local t = paw.timegrid.tick(beat)        a beat as ticks, once, at the edge
--   g:next(t), g:prev(t)                     the line after, the line before
--   g:floor(t), g:nearest(t), g:cell(t)      the line at or before, the nearest, the cell
--   g:steps(t, n)                            n lines on, with the same offset
--   g:off(t)                                 how far after its line a position is
--   g:lines(from, to)                        the lines from one tick up to another
--   paw.timegrid.step()                      the step in beats, for code that needs one
--
-- A position is an integer count of ticks, TPQ (61440) to a beat: the
-- ticks of the clip files. Each note value from 1/1 to 1/4096, and each
-- triplet and quintuplet of them, is a whole number of ticks. So the
-- arithmetic is exact and needs no epsilon. A line that is not a whole
-- number of ticks (1/7, a frame, a second) is rounded to the nearest
-- tick, and each line is computed from the start of its bar (or from 0
-- seconds), never as a sum of steps, so that an error does not grow.
--
-- The grid setting (`paw.opt.grid` in the time views, `paw.opt.note_grid`
-- in the note editors) is a number of beats, or text:
--
--   1/4 1/8 1/16 ...   a note value: a line each step from the start of each bar
--   1/8t               a triplet: 2/3 of the note value
--   bar                the bar lines only
--   auto               the finest note value whose cell is 2 columns or more
--   frame              a line at each video frame
--   1s 500ms           a line at each multiple of a time, from 0 seconds
--
-- Lines start again at each bar line, and each bar line is a line: a 7/8
-- bar on a 1/4 grid has a short last cell. `paw.opt.swing` (50 to 75 %)
-- moves each second line of a bar later. A closed time fold is one cell:
-- its start and its end are lines, and the lines inside it are not. The
-- start and the end of the scope are lines, and no line is outside them.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local options = require("paw.options")
local objects = require("paw.objects")
local axis = require("paw.axis")

local TPQ = 61440

--- How a grid setting makes its lines.
local enum Kind
  "note" -- a step of `num / den` ticks from the start of each bar
  "bar" -- the bar lines
  "auto" -- a note value that the zoom chooses
  "frame" -- a frame of video, from 0 seconds
  "time" -- a period of seconds from 0 seconds
end

--- A grid setting, read: what `parse` gives.
local record Setting
  kind: Kind
  --- The step of a "note" grid: `num / den` ticks (`den` is 1 when the
  --- step is a whole number of ticks).
  num: integer
  den: integer
  --- The period of a "time" grid, in seconds.
  period: number
  --- The text or the number that was read.
  source: number | string
end

--- A meter change: from this tick, bars of `num`/`den`.
local record Meter
  tick: integer
  num: integer
  den: integer
end

--- A stretch of ticks: a closed fold, or the scope.
local record Span
  from: integer
  to: integer
end

--- What a grid is made from: the setting, and what moves its lines.
local record Spec
  --- The setting: a number of beats, or text (see the head of the file).
  setting: number | string
  --- The meter changes in order, the first at tick 0 (4/4 when empty).
  meter: {Meter}
  --- Swing in percent: 50 is none, 75 moves each second line by half a step.
  swing: number
  --- The closed time folds, in order. Each is one cell.
  folds: {Span}
  --- The scope: its start and its end are lines, and no line is outside.
  scope: Span
  --- Columns a beat, for the setting "auto".
  zoom: number
  --- Frames a second, for the setting "frame" (30 when not given; NTSC
  --- video is 30000 / 1001).
  frame_rate: number
  --- Seconds at a tick, and the tick (with a fraction) at a time in
  --- seconds: the tempo map, for a "time" grid.
  seconds: function(tick: integer): number
  tick_at: function(seconds: number): number
end

--- A grid: the lines of a spec, and the motions over them.
local record Grid
  setting: Setting
  meter: {Meter}
  swing: integer
  folds: {Span}
  lo: integer
  hi: integer
  seconds: function(tick: integer): number
  tick_at: function(seconds: number): number
end

--- What `window` takes.
local record WindowOptions
  --- The grid of the note editors (`paw.opt.note_grid`), not of the time views.
  note: boolean
  --- A setting in place of the option's.
  setting: number | string
  --- No folds and no scope: only the setting, the meter and the swing.
  bare: boolean
end

local record M
  type Kind = Kind
  type Setting = Setting
  type Meter = Meter
  type Span = Span
  type Spec = Spec
  type Grid = Grid
  type WindowOptions = WindowOptions
  --- Ticks in a beat (a quarter note).
  TPQ: integer
  --- Frames a second of the setting "frame" in a window: 30, until a
  --- project has a frame rate of its own.
  FRAME_RATE: number
  --- What a grid setting can be, in words.
  TAKES: string
  --- True in the tests: a tick with a fraction is an error, not rounded.
  strict: boolean
  --- A function that gives the closed time folds of the window, in beats
  --- and in order, or nil: paw/folds.tl sets it.
  spans: function(): {axis.Folded}
  --- A function that gives the time of the scope, `from, to` in beats, or
  --- nil for all of it: paw/scope.tl sets it.
  bounds: function(): number, number
end

M.TPQ = TPQ
M.FRAME_RATE = 30
M.strict = false

local GridMeta = Grid as metatable<Grid>
GridMeta.__index = Grid

-- Ticks and beats ------------------------------------------------------------

--- A beat as ticks: the nearest tick. The one place where a beat from the
--- API, the kernel or the pointer becomes a tick.
function M.tick(beat: number): integer
  return math.floor(beat * TPQ + 0.5)
end

--- Ticks as a beat, for the API and the kernel.
function M.beat(tick: integer): number
  return tick / TPQ
end

--- True if a value is a whole number of ticks.
function M.is_tick(value: number): boolean
  return value == math.floor(value) and value > -math.huge and value < math.huge
end

--- A value checked as a tick: with a fraction, an error when `strict`
--- (the tests), else rounded. `what` names the value in the error.
function M.checked(value: number, what: string): integer
  if M.is_tick(value) then
    return value as integer
  end
  if M.strict then
    error(string.format("%s: %s ticks is not a whole number of ticks", what, tostring(value)), 3)
  end
  return math.floor(value + 0.5)
end

-- The setting ---------------------------------------------------------------

--- A ratio of two whole numbers that is `x`, with the least `den` up to
--- 1000; nil when none is. A grid of 1/3 beat typed as a number is so a
--- step of 20480 ticks, not of 20480.000000000004.
local function ratio(x: number): integer, integer
  for den = 1, 1000 do
    local num = x * den
    local whole = math.floor(num + 0.5)
    if math.abs(num - whole) < 1e-6 * den then
      return whole, den
    end
  end
end

--- A note grid of `beats` beats.
local function note(beats: number, source: number | string): Setting
  local num, den = ratio(beats * TPQ)
  if not num then
    num, den = math.floor(beats * TPQ + 0.5), 1
  end
  if num < 1 then
    return nil
  end
  return {kind = "note", num = num, den = den, source = source}
end

--- What a grid setting can be, in words.
M.TAKES = "a number of beats, a note value (1/8, 1/8t), bar, auto, frame, or a time (1s, 500ms)"

--- What a grid setting stands for, or nil and what a setting can be.
function M.parse(value: number | string): Setting, string
  local why = "a grid is " .. M.TAKES
  if value is number then
    if value > 0 and value < math.huge then
      return note(value, value)
    end
    return nil, why
  end
  local text = value:lower()
  if text == "bar" then
    return {kind = "bar", source = value}
  elseif text == "auto" then
    return {kind = "auto", source = value}
  elseif text == "frame" then
    return {kind = "frame", source = value}
  end
  local d, t = text:match("^1/(%d+)(t?)$")
  local den = tonumber(d)
  if den and den >= 1 and den <= 4096 then
    -- A note value 1/d is 4/d beats; a triplet is 2/3 of it.
    return note(4 / den * (t == "t" and 2 / 3 or 1), value)
  end
  local amount, unit = text:match("^(%d*%.?%d+)(m?s)$")
  local n = tonumber(amount)
  if n and n > 0 then
    return {kind = "time", period = unit == "ms" and n / 1000 or n, source = value}
  end
  return nil, why
end

-- The setting checks the options grid and note_grid: text that is no
-- setting is refused with what a setting can be.
for _, name in ipairs({"grid", "note_grid"}) do
  options.checks[name] = function(value: options.Value): string
    if value is string and not M.parse(value) then
      return M.TAKES
    end
  end
end

-- The bars ------------------------------------------------------------------

local FOUR: {Meter} = {{tick = 0, num = 4, den = 4}}

--- The ticks of a bar of a meter.
local function bar_ticks(m: Meter): integer
  return math.floor(m.num * 4 * TPQ / m.den + 0.5)
end

--- The bar that holds tick `t`: its start, and the start of the next bar.
function Grid:bar(t: integer): integer, integer
  local meter = self.meter
  -- The last change at or before `t`.
  local lo, hi = 1, #meter
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if meter[mid].tick <= t then
      lo = mid
    else
      hi = mid - 1
    end
  end
  local m = meter[lo]
  local length = bar_ticks(m)
  local start = m.tick + ((t - m.tick) // length) * length
  local after = start + length
  local change = meter[lo + 1]
  if change and change.tick < after then
    after = change.tick
  end
  return start, after
end

-- The lines of the setting, before folds and the scope ------------------

--- Line `j` of a note grid in the bar from `start` up to `after`, or nil
--- when that bar has no such line. Each line is computed from the bar's
--- start; the second line of each pair moves later by the swing.
function Grid:note_line(start: integer, after: integer, j: integer): integer
  local s = self.setting
  local at = start + (2 * j * s.num + s.den) // (2 * s.den)
  if j % 2 == 1 then
    at = at + self.swing
  end
  if at < after then
    return at
  end
end

--- Line `k` of a time grid: `k` periods from 0 seconds, as a tick.
function Grid:time_line(k: integer): integer
  return math.floor(self.tick_at(k * self.setting.period) + 0.5)
end

--- The index of the time line at or before tick `t`, near enough: the
--- callers look at the lines around it.
function Grid:time_index(t: integer): integer
  return math.max(0, math.floor(self.seconds(t) / self.setting.period))
end

--- The last line of the setting at or before tick `t` (t >= 0).
function Grid:raw_floor(t: integer): integer
  local kind = self.setting.kind
  if kind == "time" then
    local best = 0
    local k = self:time_index(t)
    for i = math.max(0, k - 2), k + 1 do
      local at = self:time_line(i)
      if at <= t and at > best then
        best = at
      end
    end
    return best
  end
  local start, after = self:bar(t)
  if kind == "bar" then
    return start
  end
  local s = self.setting
  local j = ((t - start) * s.den) // s.num
  for i = j + 1, math.max(0, j - 1), -1 do
    local at = self:note_line(start, after, i)
    if at and at <= t then
      return at
    end
  end
  return start
end

--- The first line of the setting at or after tick `t` (t >= 0).
function Grid:raw_ceil(t: integer): integer
  local kind = self.setting.kind
  if kind == "time" then
    local k = self:time_index(t)
    for i = math.max(0, k - 1), k + 3 do
      local at = self:time_line(i)
      if at >= t then
        return at
      end
    end
    return self:time_line(k + 4)
  end
  local start, after = self:bar(t)
  if t == start or kind == "bar" then
    return t == start and start or after
  end
  local s = self.setting
  local j = ((t - start) * s.den) // s.num
  for i = j, j + 2 do
    local at = self:note_line(start, after, i)
    if at and at >= t then
      return at
    end
  end
  return after
end

-- The lines: the setting's, with the folds and the scope ------------------

--- The closed fold that has `t` inside it (after its start, before its end).
function Grid:fold_at(t: integer): Span
  for _, f in ipairs(self.folds) do
    if t > f.from and t < f.to then
      return f
    end
  end
end

--- The last line at or before tick `t`: the line of the cell that holds it.
function Grid:floor(t: integer): integer
  if t <= self.lo then
    return self.lo
  elseif t >= self.hi then
    return self.hi
  end
  local fold = self:fold_at(t)
  if fold then
    return fold.from
  end
  local best = math.max(self.lo, self:raw_floor(t))
  for _, f in ipairs(self.folds) do
    for _, edge in ipairs({f.from, f.to}) do
      if edge <= t and edge > best then
        best = edge
      end
    end
  end
  return best
end

--- The first line at or after tick `t`.
function Grid:ceil(t: integer): integer
  if t <= self.lo then
    return self.lo
  elseif t >= self.hi then
    return self.hi
  end
  local fold = self:fold_at(t)
  if fold then
    return fold.to
  end
  local best = math.min(self.hi, self:raw_ceil(t))
  for _, f in ipairs(self.folds) do
    for _, edge in ipairs({f.from, f.to}) do
      if edge >= t and edge < best then
        best = edge
      end
    end
  end
  return best
end

--- The line after tick `t`, or the end of the scope.
function Grid:next(t: integer): integer
  return self:ceil(math.min(t, self.hi - 1) + 1)
end

--- The line before tick `t`, or the start of the scope (or 0).
function Grid:prev(t: integer): integer
  return self:floor(math.max(t, self.lo + 1) - 1)
end

--- The nearest line to tick `t`; halfway, the later one.
function Grid:nearest(t: integer): integer
  local before = self:floor(t)
  if before == t then
    return t
  end
  local after = self:ceil(t)
  return t - before < after - t and before or after
end

--- The cell that holds tick `t`: its line, and the next line.
function Grid:cell(t: integer): integer, integer
  local from = self:floor(t)
  return from, self:next(from)
end

--- How far tick `t` is after its line: 0 on the grid.
function Grid:off(t: integer): integer
  return t - self:floor(t)
end

--- `t` moved by `n` lines (back when `n` is negative), with the same
--- offset after its line: the move of a whole thing. A thing on the grid
--- stays on it, and one that is off the grid keeps its feel. It stays in
--- the scope.
function Grid:steps(t: integer, n: integer): integer
  local line = self:floor(t)
  local offset = t - line
  for _ = 1, math.abs(n) do
    local to = n > 0 and self:next(line) or self:prev(line)
    if to == line then
      break
    end
    line = to
  end
  return math.min(math.max(line + offset, self.lo), self.hi)
end

--- The lines from tick `from` up to `to` (not included), at most `limit`
--- (10000 when not given): integers, sorted and unique.
function Grid:lines(from: integer, to: integer, limit?: integer): {integer}
  local out: {integer} = {}
  limit = limit or 10000
  local t = self:ceil(from)
  while t < to and #out < limit do
    out[#out + 1] = t
    local after = self:next(t)
    if after <= t then
      break
    end
    t = after
  end
  return out
end

--- The ticks of the cell that holds tick `t`.
function Grid:width(t: integer): integer
  local from, to = self:cell(t)
  return to - from
end

-- Making a grid ---------------------------------------------------------------

--- The note value of the setting "auto" at a zoom: the finest power of
--- two of a beat, from 1/64 note to a whole note, whose cell is two
--- columns wide or more.
local function auto(zoom: number): Setting
  local columns = axis.new(0, zoom)
  local beats = 1 / 16
  while beats < 4 and columns:cells(beats) < 2 do
    beats = beats * 2
  end
  return note(beats, "auto")
end

--- A grid from a spec. A setting that is no setting is an error.
function M.new(spec: Spec): Grid
  local setting, why = M.parse(spec.setting)
  if not setting then
    error(why, 2)
  end
  if setting.kind == "auto" then
    setting = auto(spec.zoom or 2)
  elseif setting.kind == "frame" then
    setting = {kind = "time", period = 1 / (spec.frame_rate or M.FRAME_RATE), source = setting.source}
  end
  local swing = 0
  if setting.kind == "note" and spec.swing and spec.swing > 50 then
    -- Later by (swing - 50%) x 2 steps: half a step at 75 %.
    local percent = math.min(spec.swing, 75)
    swing = math.floor(setting.num * (percent - 50) / (50 * setting.den) + 0.5)
  end
  local meter = spec.meter and #spec.meter > 0 and spec.meter or FOUR
  local scope = spec.scope
  local g: Grid = {
    setting = setting,
    meter = meter,
    swing = swing,
    folds = spec.folds or {},
    lo = scope and scope.from or 0,
    hi = scope and scope.to or math.huge as integer,
    seconds = spec.seconds or function(t: integer): number return t / TPQ / 2 end,
    tick_at = spec.tick_at or function(s: number): number return s * 2 * TPQ end,
  }
  return setmetatable(g, GridMeta)
end

--- The meter of the window's time, in ticks.
local function window_meter(): {Meter}
  local out: {Meter} = {}
  for _, s in ipairs(objects.time.signature_points()) do
    out[#out + 1] = {tick = M.tick(s.beat), num = s.num, den = s.den}
  end
  return out
end

--- The closed folds of the window, in ticks.
local function window_folds(): {Span}
  local out: {Span} = {}
  for _, s in ipairs(M.spans and M.spans() or {}) do
    out[#out + 1] = {from = M.tick(s.from), to = M.tick(s.to)}
  end
  return out
end

--- The scope of the window in ticks, or nil for all of its time.
local function window_scope(): Span
  local from, to: number, number
  if M.bounds then
    from, to = M.bounds()
  end
  if from then
    return {from = M.tick(from), to = M.tick(to)}
  end
end

--- The grid of the window with the keys: its setting (`paw.opt.grid`, or
--- `paw.opt.note_grid` with `opts.note`), the meter of its time, the swing
--- (`paw.opt.swing`), its closed folds and its scope (not with
--- `opts.bare`), and the tempo map for a grid of frames or seconds.
function M.window(opts?: WindowOptions): Grid
  opts = opts or {}
  local opt = options.opt
  local time = objects.time
  local bare = opts.bare
  return M.new(
    {
      setting = opts.setting or (opts.note and opt.note_grid or opt.grid),
      meter = window_meter(),
      swing = opt.swing,
      folds = not bare and window_folds() or nil,
      scope = not bare and window_scope() or nil,
      zoom = opts.note and opt.note_zoom or opt.zoom,
      frame_rate = M.FRAME_RATE,
      seconds = function(t: integer): number return time.to_seconds(t / TPQ) end,
      tick_at = function(s: number): number return time.to_beat(s) * TPQ end,
    }
  )
end

--- The step of the window's grid in beats, for code that needs a number:
--- a number setting as it is, a note value's step, else the width of the
--- cell at beat `at` (the start when not given). `which` is "note" for the
--- note editors' grid.
function M.step(which?: string, at?: number): number
  local note_grid = which == "note"
  local value = note_grid and options.opt.note_grid or options.opt.grid
  if value is number then
    return value
  end
  local g = M.window({note = note_grid, bare = true})
  if g.setting.kind == "note" then
    return g.setting.num / g.setting.den / TPQ
  end
  return g:width(M.tick(at or 0)) / TPQ
end

--- A number of beats as a note value: 1 is `1/4`, 0.25 is `1/16`, and
--- one that is no note value is `0.3 beats`.
function M.note_text(beats: number): string
  local n = 4 / beats
  if math.abs(n - math.floor(n + 0.5)) < 1e-6 and n >= 1 then
    return "1/" .. math.floor(n + 0.5)
  end
  return string.format("%g beats", beats)
end

--- The window's grid setting as text, for the status line and the
--- messages: `1/8t`, `bar`, or a number of beats as a note value. `which`
--- is "note" for the note editors' grid.
function M.label(which?: string): string
  local value = which == "note" and options.opt.note_grid or options.opt.grid
  if value is number then
    return M.note_text(value)
  end
  return value
end

return M
