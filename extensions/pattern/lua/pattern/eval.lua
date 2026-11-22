-- The evaluator: a parsed pattern to a pattern of events, and events to notes.
local core = require("pattern.core")
local names = require("pattern.names")

local M = {}
local EPS = core.EPS

local function constant(node) return node.t == "atom" and type(node.v) == "number" end

local function seed_of(node, seed) return node.seed + 7919 * (seed or 0) end

local build

--- A pattern with the shape of `node` and, for each step of its steps, the
--- total weight (its number of steps, for `{ }` and `< >`).
local function steps_of(node, seed, raw)
  if node.t == "seq" then
    local list = {}
    for i, s in ipairs(node.steps) do
      list[i] = { s.weight, build(s.node, seed, raw) }
    end
    return core.timecat(list)
  end
  return build(node, seed, raw), 1
end

-- Apply a numeric argument that may itself be a pattern: `a*2`, `a*<2 3>`.
local function by_arg(pat, arg, seed, fn)
  if constant(arg) then return fn(pat, arg.v) end
  return core.with_args({ build(arg, seed, true) }, function(v) return fn(pat, v[1]) end)
end

--- `raw`: atoms are their values (numbers, names), as for arguments and
--- parameters; otherwise an atom's event carries the atom itself.
function build(node, seed, raw)
  local t = node.t
  if t == "atom" then
    return core.pure(raw and node.v or node)
  elseif t == "rest" then
    return core.silence
  elseif t == "seq" then
    return (steps_of(node, seed, raw))
  elseif t == "stack" then
    local list = {}
    for i, item in ipairs(node.items) do
      list[i] = build(item, seed, raw)
    end
    return core.stack(list)
  elseif t == "choose" then
    local list = {}
    for i, item in ipairs(node.items) do
      list[i] = build(item, seed, raw)
    end
    return core.choose(list, seed_of(node, seed))
  elseif t == "poly" then
    -- Each layer goes at `steps` of its steps per cycle; `< >` is one per cycle.
    local layers, base = {}, nil
    for i, layer in ipairs(node.layers) do
      local pat, count = steps_of(layer, seed, raw)
      layers[i] = { pat, count }
      base = base or count
    end
    local list = {}
    for i, layer in ipairs(layers) do
      local pat, count = layer[1], layer[2]
      if not node.steps then
        list[i] = pat:fast(base / count)
      else
        list[i] = by_arg(pat, node.steps, seed, function(p, v) return p:fast(v / count) end)
      end
    end
    return core.stack(list)
  elseif t == "fast" then
    return by_arg(build(node.node, seed, raw), node.by, seed, function(p, v) return p:fast(v) end)
  elseif t == "slow" then
    return by_arg(build(node.node, seed, raw), node.by, seed, function(p, v)
      if v == 0 then return core.silence end
      return p:fast(1 / v)
    end)
  elseif t == "euclid" then
    local pat = build(node.node, seed, raw)
    local all = true
    for _, arg in ipairs(node.args) do
      all = all and constant(arg)
    end
    if all then return pat:euclid(node.args[1].v, node.args[2].v, node.args[3] and node.args[3].v or 0) end
    local args = {}
    for i, arg in ipairs(node.args) do
      args[i] = build(arg, seed, true)
    end
    return core.with_args(args, function(v) return pat:euclid(v[1], v[2], v[3] or 0) end)
  elseif t == "degrade" then
    return build(node.node, seed, raw):degrade(node.prob, seed_of(node, seed))
  end
  error("unknown node " .. tostring(t))
end

--- Turn a parsed pattern into patterns of events: { main, params }.
function M.compile(tree, seed)
  local out = { main = build(tree.main, seed, false), params = {}, text = tree.text, seed = seed or 0 }
  for name, node in pairs(tree.params) do
    out.params[name] = build(node, seed, true)
  end
  return out
end

-- Pitches ------------------------------------------------------------------------

local function scale_steps(params) return names.scales[params.scale or "major"] or names.scales.major end

--- Pitch of a scale degree: 1 is the root, 8 the octave above in a
--- seven-note scale, 0 the step below the root.
local function degree(root, steps, n)
  local index = n - 1
  return root + steps[index % #steps + 1] + 12 * math.floor(index / #steps)
end

local function apply_mods(pitches, mods)
  for _, mod in ipairs(mods) do
    local kind, n = mod[1], mod[2]
    if kind == "range" then
      local base, out = pitches, {}
      for i = 1, n do
        out[i] = base[(i - 1) % #base + 1] + 12 * math.floor((i - 1) / #base)
      end
      pitches = out
    elseif kind == "invert" then
      for _ = 1, n do
        local low = table.remove(pitches, 1)
        pitches[#pitches + 1] = low + 12
      end
    elseif kind == "open" then
      if #pitches > 2 then
        local out = { pitches[1] - 12, pitches[3] - 12 }
        for i, p in ipairs(pitches) do
          if i ~= 1 and i ~= 3 then out[#out + 1] = p end
        end
        pitches = out
      end
    elseif kind == "drop" then
      local at = #pitches - n + 1
      if at >= 1 then
        local p = table.remove(pitches, at)
        table.insert(pitches, 1, p - 12)
      end
    end
    table.sort(pitches)
  end
  return pitches
end

--- The MIDI pitches an atom plays with the given parameters.
function M.pitches(value, params)
  local scaled = params.key ~= nil or params.scale ~= nil
  local root = params.key and params.key.pitch or 60
  local add = math.floor((params.add or 0) + 0.5)
  local octave = 12 * math.floor((params.oct or 0) + 0.5)
  local function single(v)
    if v.kind == "number" then
      if scaled then return degree(root, scale_steps(params), v.n + add) + octave end
      return v.n + add + octave
    end
    return v.pitch + add + octave
  end
  if value.kind == "drum" then return { value.pitch } end
  if value.kind == "chord" then
    local root_pitch = single(value.root)
    local out = {}
    for i, interval in ipairs(value.shape) do
      out[i] = root_pitch + interval
    end
    return apply_mods(out, value.mods)
  end
  return { single(value) }
end

-- Events -------------------------------------------------------------------------

local function round(x) return math.floor(x * 1e9 + 0.5) / 1e9 end
M.round = round

--- The value of each parameter at time `t`.
local function sample(params, t)
  local out = {}
  for name, pat in pairs(params) do
    for _, ev in ipairs(pat.query(t, t + 1e-6)) do
      if ev.wb <= t + EPS and t < ev.we - EPS then out[name] = ev.v end
    end
  end
  return out
end

--- Events starting from cycle `from` up to `to`, in order: { start, stop (in
--- cycles), text (the word as written), value, params, pitches }.
--- The most events a pattern may make over the stretch asked for: past
--- them it is an error, not a clip of hundreds of thousands of notes.
M.MAX_EVENTS = 20000

function M.events(compiled, from, to)
  local out = {}
  -- A cycle at a time, so that a pattern that makes too many stops early.
  local c0 = from
  while c0 < to - EPS do
    local c1 = math.min(to, math.floor(c0 + EPS) + 1)
    for _, ev in ipairs(compiled.main.query(c0, c1)) do
      if math.abs(ev.pb - ev.wb) < EPS and ev.wb >= c0 - EPS and ev.wb < c1 - EPS then
        local params = sample(compiled.params, ev.wb)
        out[#out + 1] = {
          start = round(ev.wb),
          stop = round(ev.we),
          text = ev.v.text,
          value = ev.v.v,
          pos = ev.v.pos,
          params = params,
          pitches = M.pitches(ev.v.v, params),
        }
      end
    end
    if #out > M.MAX_EVENTS then
      error("more than " .. M.MAX_EVENTS .. " notes: make the clip shorter or the pattern sparser", 0)
    end
    c0 = c1
  end
  table.sort(out, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.pos < b.pos
  end)
  return out
end

--- Notes for `length` beats with `beats` to a cycle, as a clip holds them.
function M.notes(compiled, opts)
  local beats, length = opts.beats, opts.length
  local velocity = opts.velocity or 100
  local notes, seen = {}, {}
  for _, ev in ipairs(M.events(compiled, 0, length / beats)) do
    local p = ev.params
    local vel = velocity
    if p.vel then vel = p.vel <= 1 and math.floor(p.vel * 127 + 0.5) or math.floor(p.vel + 0.5) end
    local legato = p.legato or 1
    if vel > 0 and legato > 0 then
      vel = math.min(127, vel)
      local start = round(ev.start * beats)
      local dur = round(math.min((ev.stop - ev.start) * beats * legato, length - start))
      for _, pitch in ipairs(ev.pitches) do
        local key = pitch .. "@" .. start
        if pitch >= 0 and pitch <= 127 and dur > 0 and not seen[key] then
          seen[key] = true
          notes[#notes + 1] = {
            pitch = pitch,
            start = start,
            length = dur,
            velocity = vel,
            meta = p.ch and { channel = p.ch } or nil,
          }
        end
      end
    end
  end
  table.sort(notes, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.pitch < b.pitch
  end)
  return notes
end

return M
