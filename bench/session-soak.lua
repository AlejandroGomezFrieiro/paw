-- A long session on the null backend: play, edit, undo, record from the test
-- input, open and close projects, over and over. Prints resident memory.
--   paw --clean --no-plugins -l bench/session-soak.lua <minutes> <dir>
local paw = require("paw")
local api = paw.api
local minutes, dir = tonumber((...)) or 20, select(2, ...)
local function rss()
  local f = io.open("/proc/self/status")
  local text = f:read("*a")
  f:close()
  return tonumber(text:match("VmRSS:%s+(%d+)"))
end
os.execute("mkdir -p '" .. dir .. "'")
api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })

-- A sound file of 10 s for clips.
local function wav(path, seconds)
  local n = 48000 * seconds
  local parts = {}
  for i = 1, n do
    local v = math.floor(math.sin(i * 0.05) * 8000)
    if v < 0 then v = v + 65536 end
    parts[i] = string.char(v % 256, math.floor(v / 256), v % 256, math.floor(v / 256))
  end
  local data = table.concat(parts)
  local function u32(x)
    return string.char(x % 256, math.floor(x / 256) % 256, math.floor(x / 65536) % 256, math.floor(x / 16777216))
  end
  local f = io.open(path, "wb")
  f:write(
    "RIFF"
      .. u32(36 + #data)
      .. "WAVEfmt "
      .. u32(16)
      .. string.char(1, 0, 2, 0)
      .. u32(48000)
      .. u32(192000)
      .. string.char(4, 0, 16, 0)
      .. "data"
      .. u32(#data)
      .. data
  )
  f:close()
end

local start = api.now()
local round = 0
local first = rss()
print(string.format("start rss %d kB", first))
while api.now() - start < minutes * 60000 do
  round = round + 1
  -- A new file each round, as importing new material would.
  local file = string.format("%s/sound-%d.wav", dir, round % 50)
  wav(file, 10)
  paw.project.new()
  local tracks = {}
  for i = 1, 6 do
    local t = paw.add_track({ name = "t" .. i })
    t:add_device(i % 2 == 0 and "synth" or "gain")
    if i % 2 == 0 then
      t:add_clip({
        start = 0,
        length = 8,
        notes = { { pitch = 60, start = 0, length = 4 }, { pitch = 64, start = 4, length = 4 } },
      })
    else
      t:add_clip({ start = 0, file = file })
    end
    tracks[i] = t
  end
  api.undo_checkpoint()
  local mic = tracks[1]
  mic.input, mic.armed = "1", true
  paw.project.save(string.format("%s/song-%d.json", dir, round % 5))
  paw.transport.record()
  paw.wait(1500)
  paw.transport.stop()
  for i = 1, 20 do
    tracks[i % 6 + 1].volume = -(i % 12)
    api.undo_checkpoint()
  end
  for _ = 1, 10 do
    paw.undo()
  end
  paw.transport.play()
  paw.wait(1000)
  paw.transport.stop()
  paw.project.save()
  paw.project.load(string.format("%s/song-%d.json", dir, round % 5))
  if round % 10 == 0 then
    local e = api.engine_get()
    print(
      string.format(
        "round %d  %.1f min  rss %d kB  audio files %d  xruns %d",
        round,
        (api.now() - start) / 60000,
        rss(),
        e.audio_files or -1,
        e.xruns
      )
    )
    io.stdout:flush()
  end
end
print(string.format("end rss %d kB after %d rounds (start %d kB)", rss(), round, first))
api.quit(0)
