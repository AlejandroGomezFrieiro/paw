-- What each built-in effect costs: N parts of audio rendered on one thread,
-- with and without one instance of the effect on every part (at its
-- defaults, or with `busy` settings below that make it work), and the
-- difference per instance as a share of one core in real time.
--   paw --clean --no-plugins -l bench/devices.lua [parts] [seconds] [kind...]
local paw = require("paw")
local api = paw.api
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local args = { ... }
local parts = tonumber(args[1]) or 16
local seconds = tonumber(args[2]) or 20
local only = {}
for i = 3, #args do
  only[args[i]] = true
end

-- Settings that keep each effect busy, where its defaults would let it idle.
local busy = {
  eq = { b1_on = 1, b2_gain = 2, b3_gain = -3, b4_gain = 2, b5_gain = 3, b6_gain = -2, b7_gain = 2, b8_on = 1 },
  compressor = { threshold = -30, lookahead = 2 },
  gate = { threshold = -20 },
}

local function build(kind)
  api.project_new()
  local wav = B.wav()
  local bars = math.ceil(seconds / 2)
  for i = 0, parts - 1 do
    local id = api.part_add({ name = "T" .. i })
    for bar = 0, bars - 1 do
      api.clip_add(id, { start = bar * 4, length = 4, file = wav })
    end
    if kind then api.device_add(id, kind, { params = busy[kind] or {} }) end
  end
  paw.flush()
  return bars
end

local function render(kind)
  local bars = build(kind)
  local out = B.tmp .. "/devices.wav"
  local best
  for _ = 1, 3 do
    local info = paw.render(out, { start = 0, ["end"] = bars * 4, tail = 0, threads = 1 })
    best = math.min(best or math.huge, info.processing)
  end
  os.remove(out)
  return best, bars * 2
end

local base, audio = render(nil)
B.emit({ workload = "devices", kind = "none", parts = parts, audio_seconds = audio, processing_ms = base })
for _, d in ipairs(api.device_types()) do
  if d.format == "builtin" and d.category == "effect" and (next(only) == nil or only[d.kind]) then
    local ms = render(d.kind)
    local per = (ms - base) / parts
    B.emit({
      workload = "devices",
      kind = d.kind,
      parts = parts,
      audio_seconds = audio,
      processing_ms = ms,
      -- One instance's share of one core, in per cent, in real time.
      core_percent = per / (audio * 1000) * 100,
    })
  end
end
paw.api.quit(0)
