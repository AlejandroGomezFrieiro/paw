-- The motion layer: how each class of key moves a position in time. One
-- rule for each class, the same in each view and on each kind of row:
--
--   motion.grid(dir, count)          h l and the arrows: to the next lines (rule 1)
--   motion.object(list, dir, count)  w b e and jumps: to the exact edge of a thing (rule 2)
--   motion.relative(t, n)            a whole thing moves n lines and keeps its offset (rule 6)
--   motion.by(t, dbeat)              a drag of a whole thing: whole lines, with its offset
--   motion.edge(t, dir, count)       one edge goes to the lines (rule 7)
--   motion.nearest(t)                = puts a thing on its nearest line (rule 8)
--   motion.press(from, to)           a press of the pointer on a cell (rule 11)
--   motion.pointer_press/edge/by     the pointer in beats, with the option `snap`
--   motion.cell(t)                   the cell of the cursor: from it to the next line
--   motion.under(list, t)            the first thing with no length in that cell (rule 16)
--
-- Each position is a whole number of ticks (paw/timegrid.tl), and the
-- lines are those of the window's grid: its setting, meter, swing, folds
-- and scope. So `h` and `l` stop on the lines that the ruler draws, and an
-- offset from the grid never builds up: only an object motion (or a new
-- thing at the cursor) puts the cursor off the grid, and the next grid
-- motion puts it on a line again.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local options = require("paw.options")
local timegrid = require("paw.timegrid")
local cursor = require("paw.cursor")

local record M
end

--- The grid the keys move on: the window's, with its folds and scope.
local function grid(): timegrid.Grid
  return timegrid.window()
end

--- `count` lines after tick `from` (`dir` 1), or before it (`dir` -1).
--- From off the grid, the first step goes to the line next to it in that
--- direction. It stops at a bound (0, the scope).
local function lines(g: timegrid.Grid, from: integer, dir: integer, count: integer): integer
  local t = from
  for _ = 1, count do
    local to = dir > 0 and g:next(t) or g:prev(t)
    if to == t then
      break
    end
    t = to
  end
  return t
end

--- The tick of a grid motion (`h`, `l`): `count` lines after the cursor
--- (`dir` 1) or before it (`dir` -1), or after tick `from` when it's given.
function M.grid(dir: integer, count?: integer, from?: integer): integer
  return lines(grid(), from or cursor.tick, dir, count or 1)
end

--- The tick of an object motion (`w`, `b`): the `count`-th tick of `list`
--- after the cursor (`dir` 1) or before it (`dir` -1), exactly, so it can be
--- between two lines. It's nil when there is none. `list` holds ticks in
--- any order. With `from`, the motion starts there in place of the cursor.
function M.object(list: {integer}, dir: integer, count?: integer, from?: integer): integer
  local sorted: {integer} = {}
  for i, t in ipairs(list) do
    sorted[i] = t
  end
  table.sort(sorted)
  local at = from or cursor.tick
  local found: integer
  for _ = 1, count or 1 do
    local to: integer
    if dir > 0 then
      for _, t in ipairs(sorted) do
        if t > at then
          to = t
          break
        end
      end
    else
      for i = #sorted, 1, -1 do
        if sorted[i] < at then
          to = sorted[i]
          break
        end
      end
    end
    if not to then
      break
    end
    at, found = to, to
  end
  return found
end

--- Where a whole thing at tick `t` goes when it moves `n` lines (back when
--- `n` is negative). It keeps the same distance after its line.
function M.relative(t: integer, n: integer): integer
  return grid():steps(t, n)
end

--- The ticks that a whole thing at tick `t` moves when the pointer drags it
--- `dbeat` beats. The line of the thing goes to the line nearest to where
--- the drag puts it, and the thing keeps its distance after its line.
function M.by(t: integer, dbeat: number): integer
  local g = timegrid.window({bare = true})
  local line = g:floor(t)
  local to = g:nearest(math.max(0, line + timegrid.tick(dbeat)))
  return to - line
end

--- Where one edge at tick `t` goes: `count` lines on, as a grid motion.
function M.edge(t: integer, dir: integer, count?: integer): integer
  return lines(timegrid.window({bare = true}), t, dir, count or 1)
end

--- The line nearest to tick `t`, where `=` puts a thing.
function M.nearest(t: integer): integer
  return timegrid.window({bare = true}):nearest(t)
end

--- Where a press of the pointer goes in a cell that shows the beats from
--- `from` up to `to`. It's the first line in the cell, or the line before
--- the cell when no line starts in it, so a press goes to the line drawn
--- in that cell.
function M.press(from: number, to: number): integer
  local g = timegrid.window({bare = true})
  local a, b = timegrid.tick(from), timegrid.tick(to)
  local first = g:ceil(math.max(0, a))
  if first < b then
    return first
  end
  return g:floor(math.max(0, a))
end

-- The pointer, in beats: with `paw.opt.snap` on (the default) it follows
-- the rules of the keys; with it off, or with `free` (Shift turns the
-- option over for a drag), it is exact.

--- Whether the pointer goes exactly where it is: `snap` is off, or `free`.
local function exact(free?: boolean): boolean
  return free or not options.opt.snap
end

--- Where a press of the pointer at `beat` puts the cursor. It's the line
--- of the cell under the pointer, or `beat` itself when the option `snap`
--- is off or `free` is true.
function M.pointer_press(beat: number, free?: boolean): number
  local at = math.max(0, beat)
  if exact(free) then
    return at
  end
  return timegrid.beat(M.press(at, at))
end

--- Where an edge that the pointer drags to `beat` goes. It's the nearest
--- line, or `beat` itself when the option `snap` is off or `free` is true.
function M.pointer_edge(beat: number, free?: boolean): number
  local at = math.max(0, beat)
  if exact(free) then
    return at
  end
  return timegrid.beat(M.nearest(timegrid.tick(at)))
end

--- The beats that a whole thing at `beat` moves when the pointer drags it
--- `dbeat` beats. It moves by whole lines and keeps its distance from the
--- grid, or by `dbeat` itself when the option `snap` is off or `free` is
--- true.
function M.pointer_by(beat: number, dbeat: number, free?: boolean): number
  if exact(free) then
    return dbeat
  end
  return timegrid.beat(M.by(timegrid.tick(beat), dbeat))
end

--- The cell of the cursor, or of tick `t`, from it up to the next line.
--- On a line, it's a whole cell, and between two lines it's the rest of one.
function M.cell(t?: integer): integer, integer
  local from = t or cursor.tick
  return from, grid():next(from)
end

--- How many ticks tick `t` (the cursor when it's not given) is after the
--- line before it. It's 0 on a line.
function M.offset(t?: integer): integer
  return grid():off(t or cursor.tick)
end

--- True when tick `t` (the cursor when it's not given) is between two lines.
function M.off(t?: integer): boolean
  return M.offset(t) ~= 0
end

--- The index of the first tick of `list` from tick `t` (the cursor when
--- it's not given) up to the next line, or nil when there is none. It finds
--- the thing under the cursor among things with no length, e.g., the
--- points of a lane.
function M.under(list: {integer}, t?: integer): integer
  local from, to = M.cell(t)
  local best: integer
  for i, at in ipairs(list) do
    if at >= from and at < to and (not best or at < list[best]) then
      best = i
    end
  end
  return best
end

return M
