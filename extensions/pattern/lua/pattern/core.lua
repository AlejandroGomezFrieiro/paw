-- Patterns as functions of time, in the manner of TidalCycles.
--
-- A pattern answers a query for a stretch of time, measured in cycles, with
-- the events that fall in it. An event has a `whole` (wb..we, when it starts
-- and ends) and a `part` (pb..pe, the piece of it inside the query), and a
-- value `v`. An event whose part starts where its whole starts is an onset;
-- turning a pattern into notes keeps only onsets, so an event that a query
-- cuts in two is not played twice.
local M = {}

local EPS = 1e-9
M.EPS = EPS

local Pattern = {}
Pattern.__index = Pattern
M.Pattern = Pattern

local function new(query) return setmetatable({ query = query }, Pattern) end
M.new = new

--- The cycle a time is in, forgiving the rounding of float arithmetic.
local function sam(t) return math.floor(t + EPS) end
M.sam = sam

--- Split a span at cycle boundaries.
local function cycles(b, e)
  local out = {}
  if e - b < EPS then return out end
  local c = sam(b)
  while b < e - EPS do
    local stop = math.min(e, c + 1)
    out[#out + 1] = { b, stop }
    b, c = stop, c + 1
  end
  return out
end
M.cycles = cycles

M.silence = new(function() return {} end)

--- One event per cycle, the whole cycle long.
function M.pure(value)
  return new(function(b, e)
    local out = {}
    for _, s in ipairs(cycles(b, e)) do
      local c = sam(s[1])
      out[#out + 1] = { wb = c, we = c + 1, pb = s[1], pe = s[2], v = value }
    end
    return out
  end)
end

--- Change query times with `fq` and event times with `fe`.
function Pattern:with_time(fq, fe)
  local inner = self
  return new(function(b, e)
    local out = {}
    for _, ev in ipairs(inner.query(fq(b), fq(e))) do
      out[#out + 1] = { wb = fe(ev.wb), we = fe(ev.we), pb = fe(ev.pb), pe = fe(ev.pe), v = ev.v }
    end
    return out
  end)
end

function Pattern:fmap(fn)
  local inner = self
  return new(function(b, e)
    local out = {}
    for _, ev in ipairs(inner.query(b, e)) do
      out[#out + 1] = { wb = ev.wb, we = ev.we, pb = ev.pb, pe = ev.pe, v = fn(ev.v) }
    end
    return out
  end)
end

--- Keep the events for which `keep(event)` is true.
function Pattern:filter(keep)
  local inner = self
  return new(function(b, e)
    local out = {}
    for _, ev in ipairs(inner.query(b, e)) do
      if keep(ev) then out[#out + 1] = ev end
    end
    return out
  end)
end

--- Play `factor` times as fast.
function Pattern:fast(factor)
  if factor <= 0 then return M.silence end
  if factor == 1 then return self end
  return self:with_time(function(t) return t * factor end, function(t) return t / factor end)
end

--- Shift earlier in time by `t` cycles.
function Pattern:early(t)
  if t == 0 then return self end
  return self:with_time(function(x) return x + t end, function(x) return x - t end)
end

--- Squeeze each cycle into the stretch b0..e0 of the cycle (0 <= b0 < e0 <= 1),
--- leaving the rest silent.
function Pattern:compress(b0, e0)
  if e0 - b0 < EPS then return M.silence end
  local inner, width = self, e0 - b0
  return new(function(b, e)
    local out = {}
    for _, s in ipairs(cycles(b, e)) do
      local c = sam(s[1])
      local qb, qe = math.max(s[1], c + b0), math.min(s[2], c + e0)
      if qe - qb > EPS then
        local function to_inner(t) return c + (t - c - b0) / width end
        local function to_outer(t) return c + b0 + (t - c) * width end
        for _, ev in ipairs(inner.query(to_inner(qb), to_inner(qe))) do
          out[#out + 1] =
            { wb = to_outer(ev.wb), we = to_outer(ev.we), pb = to_outer(ev.pb), pe = to_outer(ev.pe), v = ev.v }
        end
      end
    end
    return out
  end)
end

--- Patterns played together.
function M.stack(list)
  if #list == 1 then return list[1] end
  return new(function(b, e)
    local out = {}
    for _, pat in ipairs(list) do
      for _, ev in ipairs(pat.query(b, e)) do
        out[#out + 1] = ev
      end
    end
    return out
  end)
end

--- Patterns one after another within each cycle, each taking a share of the
--- cycle in proportion to its weight: `steps` is a list of { weight, pattern }.
function M.timecat(steps)
  local total = 0
  for _, s in ipairs(steps) do
    total = total + s[1]
  end
  if total <= 0 then return M.silence, 0 end
  local parts, at = {}, 0
  for _, s in ipairs(steps) do
    parts[#parts + 1] = s[2]:compress(at / total, (at + s[1]) / total)
    at = at + s[1]
  end
  return M.stack(parts), total
end

--- Build a pattern from argument patterns, sampling them as they change: the
--- result takes its structure from `build(values)` within each event of the
--- arguments (Tidal's inner join). Constant arguments cost nothing.
function M.with_args(args, build)
  return new(function(b, e)
    local out = {}
    local values = {}
    local function go(i, qb, qe)
      if i > #args then
        local copy = {}
        for k = 1, #args do
          copy[k] = values[k]
        end
        for _, ev in ipairs(build(copy).query(qb, qe)) do
          out[#out + 1] = ev
        end
        return
      end
      for _, a in ipairs(args[i].query(qb, qe)) do
        values[i] = a.v
        go(i + 1, a.pb, a.pe)
      end
    end
    go(1, b, e)
    return out
  end)
end

-- Randomness -------------------------------------------------------------------
-- A number in 0..1 from a time and a seed, the same every time it is asked.

local bit = require("bit")

-- 32-bit multiplication without losing bits to the double's mantissa.
local function mul32(a, b)
  a = a % 4294967296
  local lo, hi = a % 65536, math.floor(a / 65536)
  return bit.tobit(((hi * b) % 65536 * 65536 + lo * b) % 4294967296)
end

local function mix(h)
  h = bit.bxor(h, bit.rshift(h, 16))
  h = mul32(h, 0x45d9f3b)
  h = bit.bxor(h, bit.rshift(h, 16))
  h = mul32(h, 0x45d9f3b)
  h = bit.bxor(h, bit.rshift(h, 16))
  return h
end

function M.rand(t, seed)
  local ticks = math.floor(t * 65536 + 0.5)
  local h = mix(bit.bxor(bit.tobit(ticks % 4294967296), mix(bit.tobit(((seed or 0) * 7919 + 17) % 4294967296))))
  return (h % 4294967296) / 4294967296
end

--- Drop each event with probability `prob`, decided by its onset.
function Pattern:degrade(prob, seed)
  return self:filter(function(ev) return M.rand(ev.wb, seed) >= prob end)
end

--- One of the patterns each cycle, chosen at random.
function M.choose(list, seed)
  return new(function(b, e)
    local out = {}
    for _, s in ipairs(cycles(b, e)) do
      local c = sam(s[1])
      local pick = list[math.floor(M.rand(c, seed) * #list) + 1] or list[#list]
      for _, ev in ipairs(pick.query(s[1], s[2])) do
        out[#out + 1] = ev
      end
    end
    return out
  end)
end

-- Euclidean rhythms ------------------------------------------------------------

--- Bjorklund's algorithm, as TidalCycles has it: `hits` onsets spread over
--- `steps`, as a list of booleans. Negative hits give the complement.
function M.bjorklund(hits, steps)
  local invert = hits < 0
  hits = math.min(math.abs(hits), steps)
  local xs, ys = {}, {}
  for i = 1, hits do
    xs[i] = { true }
  end
  for i = 1, steps - hits do
    ys[i] = { false }
  end
  local i, j = hits, steps - hits
  local function join(a, b)
    local out = {}
    for _, v in ipairs(a) do
      out[#out + 1] = v
    end
    for _, v in ipairs(b) do
      out[#out + 1] = v
    end
    return out
  end
  while math.min(i, j) > 1 do
    if i > j then
      -- left: the first j of xs take a ys each; the rest of xs become ys.
      local nx, ny = {}, {}
      for k = 1, j do
        nx[k] = join(xs[k], ys[k])
      end
      for k = j + 1, #xs do
        ny[#ny + 1] = xs[k]
      end
      xs, ys, i, j = nx, ny, j, i - j
    else
      -- right: every xs takes one of the first i ys; the rest stay ys.
      local nx, ny = {}, {}
      for k = 1, #xs do
        nx[k] = join(xs[k], ys[k])
      end
      for k = i + 1, #ys do
        ny[#ny + 1] = ys[k]
      end
      xs, ys, i, j = nx, ny, i, j - i
    end
  end
  local out = {}
  for _, group in ipairs(xs) do
    for _, v in ipairs(group) do
      out[#out + 1] = v
    end
  end
  for _, group in ipairs(ys) do
    for _, v in ipairs(group) do
      out[#out + 1] = v
    end
  end
  if invert then
    for k, v in ipairs(out) do
      out[k] = not v
    end
  end
  return out
end

--- The pattern on the hits of a Euclidean rhythm, rotated left by `rotate` steps.
function Pattern:euclid(hits, steps, rotate)
  hits, steps, rotate = math.floor(hits + 0.5), math.floor(steps + 0.5), math.floor((rotate or 0) + 0.5)
  if steps <= 0 then return M.silence end
  local list = {}
  for k, hit in ipairs(M.bjorklund(hits, steps)) do
    list[k] = { 1, hit and self or M.silence }
  end
  local pat = M.timecat(list)
  return pat:early((rotate % steps) / steps)
end

return M
