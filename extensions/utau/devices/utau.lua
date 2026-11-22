-- The `utau` device: plays what the singing engine sang, where it belongs.
--
-- The engine renders a vocal track phrase by phrase; extensions/utau writes
-- each phrase to a file of 32-bit floats and tells every device of this kind
-- what each voice holds (`voice.<n>`, posted with `paw.api.device_post`, so
-- that devices made later, an offline render's among them, are told too). A
-- device plays the voice its `voice` parameter names, in real time and in
-- renders alike, and ignores the notes that reach it. The files are mapped,
-- not copied: every device playing a voice shares one copy of its sound.
--
-- The other parameters are the singing curves, in OpenUtau's units. The
-- device does nothing with them: they are there for automation lanes to
-- draw, and the extension reads the lanes and sends them to the engine.
local dsp = require("paw.dsp")
local ffi = require("ffi")
local floor = math.floor

local MAX_VOICES = 64

local params = { { key = "voice", name = "voice", min = 0, max = MAX_VOICES, default = 0 } }
for _, c in ipairs({
  { "pitd", "Pitch deviation", -1200, 1200, 0 },
  { "dyn", "Dynamics", -240, 120, 0 },
  { "tenc", "Tension", -100, 100, 0 },
  { "brec", "Breathiness", -100, 100, 0 },
  { "genc", "Gender", -100, 100, 0 },
  { "voic", "Voicing", 0, 100, 100 },
  { "shfc", "Tone shift", -1200, 1200, 0 },
  { "grwc", "Growl", 0, 100, 0 },
  { "xsy", "Cross synthesis", 0, 100, 0 },
}) do
  params[#params + 1] = { key = c[1], name = c[2], min = c[3], max = c[4], default = c[5] }
end
-- Slots for curves of the renderer's own (DiffSinger's energy, voice colour
-- blends, ...): the extension says which expression each one draws.
for i = 1, 8 do
  params[#params + 1] = { key = "x" .. i, name = "Renderer curve " .. i, min = -1200, max = 1200, default = 0 }
end

local dev = dsp.device {
  name = "UTAU voice",
  category = "instrument",
  vendor = "extensions/utau",
  params = params,
}

-- voices[n]: the phrases of voice n, sorted by start, each
-- { hash, start, rate, channels, quality, path, map, frames }.
local voices = {}
-- Every mapped file by path, with how many phrases use it.
local maps = {}
-- A short clip to play at once, transport or not: { map, rate, channels, at }.
local audition
-- What the device plays over a stretch of the song, kept to be asked for:
-- { from (a frame of the project), n, left, right }.
local capture
local sample_rate = 48000

local function map(path)
  local known = maps[path]
  if not known then
    known = { map = dsp.map(path), users = 0 }
    maps[path] = known
  end
  known.users = known.users + 1
  return known.map
end

local function unmap(path)
  local known = maps[path]
  if not known then return end
  known.users = known.users - 1
  if known.users <= 0 then
    known.map:close()
    maps[path] = nil
  end
end

--- A voice's phrases from what was posted: a line `hash start rate channels
--- quality path` each (start in project seconds; quality 0 for a draft).
local function set_voice(n, text)
  local list = {}
  for line in text:gmatch("[^\n]+") do
    local hash, start, rate, channels, quality, path = line:match("^(%S+) (%S+) (%S+) (%S+) (%S+) (.+)$")
    if not hash then error("a phrase is `hash start rate channels quality path`, not `" .. line .. "`", 0) end
    channels = tonumber(channels)
    if channels ~= 1 and channels ~= 2 then error("phrases are mono or stereo", 0) end
    list[#list + 1] = {
      hash = hash,
      start = tonumber(start),
      rate = tonumber(rate),
      channels = channels,
      quality = tonumber(quality),
      path = path,
    }
  end
  -- Map the new before letting go of the old: a file in both stays mapped.
  for _, p in ipairs(list) do
    p.map = map(p.path)
    p.frames = floor(p.map.n / p.channels)
  end
  for _, p in ipairs(voices[n] or {}) do
    unmap(p.path)
  end
  table.sort(list, function(a, b) return a.start < b.start end)
  voices[n] = list
end

function dev.init(rate) sample_rate = rate end

--- Calls: `voice.<n>` (posted to every device) gives voice n its phrases;
--- `audition` (`rate channels path`) plays a clip once, now; `list` (a
--- voice's number) answers a line `hash start seconds quality` per phrase;
--- `capture` (`from to`, in seconds of the song) keeps what the device plays
--- there while the song plays, and `captured` answers it: the left channel
--- and then the right, as 32-bit floats.
function dev.call(method, data)
  local n = method:match("^voice%.(%d+)$")
  if n then
    n = tonumber(n)
    if n < 1 or n > MAX_VOICES then error("voices are numbered from 1 to " .. MAX_VOICES, 0) end
    return set_voice(n, data)
  elseif method == "audition" then
    local rate, channels, path = data:match("^(%S+) (%S+) (.+)$")
    if not path then error("an audition is `rate channels path`", 0) end
    if audition then audition.map:close() end
    local clip = dsp.map(path)
    audition = { map = clip, rate = tonumber(rate), channels = tonumber(channels), at = 0 }
  elseif method == "list" then
    local out = {}
    for _, p in ipairs(voices[tonumber(data)] or {}) do
      out[#out + 1] = string.format("%s %.17g %.17g %d", p.hash, p.start, p.frames / p.rate, p.quality)
    end
    return table.concat(out, "\n")
  elseif method == "capture" then
    local from, to = data:match("^(%S+) (%S+)$")
    local a = floor(tonumber(from) * sample_rate + 0.5)
    local n = math.max(0, floor(tonumber(to) * sample_rate + 0.5) - a)
    capture = { from = a, n = n, left = dsp.buffer(n), right = dsp.buffer(n) }
  elseif method == "captured" then
    if not capture then return "" end
    return ffi.string(capture.left, capture.n * 4) .. ffi.string(capture.right, capture.n * 4)
  else
    error("the utau device has no method `" .. method .. "`", 0)
  end
end

--- The signal of channel `ch` at fractional frame `pos`, by cubic Hermite
--- interpolation; silence outside the data.
local function sample(d, frames, channels, ch, pos)
  local i = floor(pos)
  local t = pos - i
  local y0 = (i >= 1 and i - 1 < frames) and d[(i - 1) * channels + ch] or 0
  local y1 = (i >= 0 and i < frames) and d[i * channels + ch] or 0
  local y2 = (i + 1 >= 0 and i + 1 < frames) and d[(i + 1) * channels + ch] or 0
  local y3 = (i + 2 >= 0 and i + 2 < frames) and d[(i + 2) * channels + ch] or 0
  local c1 = 0.5 * (y2 - y0)
  local c2 = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
  local c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
  return ((c3 * t + c2) * t + c1) * t + y1
end

--- Add frames of a clip to the block, from `first` to `last` - 1, the
--- clip's frame for block frame i being `(origin + i) * step`.
local function mix(b, p, d, first, last, origin, step)
  local left, right, frames, channels = b.left, b.right, p.frames, p.channels
  local stereo = channels == 2 and 1 or 0
  for i = first, last - 1 do
    local pos = (origin + i) * step
    local l = sample(d, frames, channels, 0, pos)
    left[i] = left[i] + l
    right[i] = right[i] + (stereo == 1 and sample(d, frames, channels, 1, pos) or l)
  end
end

local function play_audition(b)
  local a = audition
  local frames = floor(a.map.n / a.channels)
  if a.at >= frames then return end
  local step = a.rate / b.sample_rate
  local clip = { frames = frames, channels = a.channels }
  local last = math.min(b.frames, math.ceil((frames - a.at) / step))
  mix(b, clip, a.map.data, 0, last, a.at / step, step)
  a.at = a.at + b.frames * step
end

function dev.process(b)
  local voice = floor(b.params.voice + 0.5)
  if voice == 0 then return end
  if audition and audition.map.n > 0 then play_audition(b) end
  if not b.playing or b.tempo <= 0 then return end
  local list = voices[voice]
  if not list then return end
  local sr, n = b.sample_rate, b.frames
  -- Where the block starts, counted in whole frames of the project, so that
  -- a phrase sounds the same however the song is cut into blocks.
  local f0 = floor(b.seconds * sr + 0.5)
  local t0, t1 = f0 / sr, (f0 + n) / sr
  for k = 1, #list do
    local p = list[k]
    if p.start >= t1 then break end
    if p.start + p.frames / p.rate > t0 and p.frames > 0 then
      local step = p.rate / sr
      local origin = f0 - p.start * sr
      -- Only the frames that land inside the phrase, with room for interpolation.
      local first = math.max(0, math.ceil(-2 / step - origin))
      local last = math.min(n, math.ceil((p.frames + 2) / step - origin))
      mix(b, p, p.map.data, first, last, origin, step)
    end
  end
  local c = capture
  if c then
    for i = math.max(0, c.from - f0), math.min(n, c.from + c.n - f0) - 1 do
      c.left[f0 + i - c.from], c.right[f0 + i - c.from] = b.left[i], b.right[i]
    end
  end
end

return dev
