-- Helpers shared by the bench scripts: timing, JSON output, memory, and the
-- workloads, built the same way the Tracktion driver builds them.
local paw = require("paw")
local api = paw.api

local M = {}

M.dir = debug.getinfo(1, "S").source:sub(2):match("(.*)/") or "."
M.tmp = os.getenv("BENCH_TMP") or "/tmp/paw-bench"
os.execute("mkdir -p '" .. M.tmp .. "'")

M.now = api.now

--- Milliseconds of processor time that this thread has used. A bench of
--- the kernel's own work reads this and not the clock: on a loaded machine
--- the clock runs on while other programs have the processor.
local ffi = require("ffi")
pcall(ffi.cdef, "struct paw_timespec { long tv_sec; long tv_nsec; }; int clock_gettime(int, struct paw_timespec *);")
local cpu_now = ffi.new("struct paw_timespec")
function M.cpu_ms()
  ffi.C.clock_gettime(3, cpu_now) -- CLOCK_THREAD_CPUTIME_ID
  return tonumber(cpu_now.tv_sec) * 1000 + tonumber(cpu_now.tv_nsec) / 1e6
end

--- The load average of the machine (the text of /proc/loadavg up to the
--- count of tasks), for the result lines: a number measured under load
--- says so.
function M.load()
  local f = io.open("/proc/loadavg")
  if not f then return nil end
  local text = f:read("*l")
  f:close()
  return text:match("^(%S+ %S+ %S+)")
end

--- Milliseconds `fn` takes, and what it returns.
function M.time(fn, ...)
  local t = api.now()
  local r = fn(...)
  return api.now() - t, r
end

local function encode(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if math.floor(v) == v and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.6g", v)
  end
  if t == "string" then return string.format("%q", v):gsub("\\\n", "\\n") end
  local keys = {}
  for k in pairs(v) do
    keys[#keys + 1] = k
  end
  if #keys == #v then
    local out = {}
    for i = 1, #v do
      out[i] = encode(v[i])
    end
    return "[" .. table.concat(out, ",") .. "]"
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do
    out[#out + 1] = string.format("%q", tostring(k)) .. ":" .. encode(v[k])
  end
  return "{" .. table.concat(out, ",") .. "}"
end
M.json = encode

--- Print one result line, tagged with the engine.
function M.emit(record)
  record.engine = record.engine or "paw"
  print(encode(record))
  io.stdout:flush()
end

--- Resident and peak resident memory of this process, in kB.
function M.rss()
  local f = io.open("/proc/self/status")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return tonumber(text:match("VmRSS:%s+(%d+)")), tonumber(text:match("VmHWM:%s+(%d+)"))
end

--- Sorted copy, and quantiles of a list of numbers.
function M.stats(list)
  local s = {}
  for i, v in ipairs(list) do
    s[i] = v
  end
  table.sort(s)
  local function q(p) return s[math.max(1, math.min(#s, math.ceil(p * #s)))] or 0 end
  local sum = 0
  for _, v in ipairs(s) do
    sum = sum + v
  end
  return { n = #s, mean = #s > 0 and sum / #s or 0, p50 = q(0.5), p99 = q(0.99), max = s[#s] or 0 }
end

--- The audio file both engines play: 2 s of 48 kHz 16-bit stereo, a chord of
--- sines with a little deterministic noise, so that it is not trivially silent.
function M.wav()
  local path = M.tmp .. "/bench-2s.wav"
  local f = io.open(path, "rb")
  if f then
    f:close()
    return path
  end
  local rate, frames = 48000, 96000
  local parts = {}
  local seed = 1
  for i = 0, frames - 1 do
    seed = (seed * 1103515245 + 12345) % 2147483648
    local noise = (seed / 2147483648 - 0.5) * 0.02
    local t = i / rate
    local l = 0.3 * math.sin(2 * math.pi * 220 * t) + 0.2 * math.sin(2 * math.pi * 331 * t) + noise
    local r = 0.3 * math.sin(2 * math.pi * 277 * t) + 0.2 * math.sin(2 * math.pi * 440 * t) - noise
    for _, v in ipairs({ l, r }) do
      local s = math.floor(math.max(-1, math.min(1, v)) * 32767)
      if s < 0 then s = s + 65536 end
      parts[#parts + 1] = string.char(s % 256, math.floor(s / 256))
    end
  end
  local data = table.concat(parts)
  local function u32(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
  end
  local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
  f = assert(io.open(path, "wb"))
  f:write(
    "RIFF",
    u32(36 + #data),
    "WAVE",
    "fmt ",
    u32(16),
    u16(1),
    u16(2),
    u32(rate),
    u32(rate * 4),
    u16(4),
    u16(16),
    "data",
    u32(#data),
    data
  )
  f:close()
  return path
end

--- The MIDI workload per bar, as in the Tracktion driver: a four-note chord on
--- the first beat, two beats long, and eight eighth notes of a bass line.
function M.bar_notes(bar, index)
  local notes = {}
  local b = bar * 4
  for i = 0, 3 do
    notes[#notes + 1] = { pitch = 48 + index % 12 + i * 4, start = b, length = 2, velocity = 100 }
  end
  for i = 0, 7 do
    notes[#notes + 1] = { pitch = 36 + index % 12 + (i % 3) * 7, start = b + i * 0.5, length = 0.5, velocity = 90 }
  end
  return notes
end

--- Build `tracks` tracks of `bars` bars: audio clips (one per bar) or one MIDI
--- clip through the built-in synth, optionally with a delay and with volume
--- automation. Goes through `paw.api` directly, as one undo step.
function M.build(opts)
  local tracks, bars = opts.tracks, opts.bars
  local wav = opts.kind == "audio" and M.wav() or nil
  local ids = {}
  for i = 0, tracks - 1 do
    local id = api.track_add({ name = "T" .. i })
    ids[#ids + 1] = id
    if opts.kind == "midi" then
      api.device_add(id, "synth", { params = { wave = 1, cutoff = 4000 } })
      local notes = {}
      for bar = 0, bars - 1 do
        for _, n in ipairs(M.bar_notes(bar, i)) do
          notes[#notes + 1] = n
        end
      end
      api.clip_add(id, { start = 0, length = bars * 4, notes = notes })
    else
      for bar = 0, bars - 1 do
        api.clip_add(id, { start = bar * 4, length = 4, file = wav })
      end
    end
    if opts.fx then api.device_add(id, "delay") end
    if opts.automation then
      local points = {}
      for bar = 0, bars do
        points[#points + 1] = { bar * 4, bar % 2 == 1 and -6 or -1 }
      end
      api.lane_add(id, { target = "volume", points = points })
    end
  end
  api.undo_checkpoint()
  paw.flush()
  return ids
end

return M
