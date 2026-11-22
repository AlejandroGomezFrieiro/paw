-- The time of a full frame of the arrange view after a key: the key, then
-- the whole screen drawn, as the terminal draws it after a move.
--   paw --clean --no-plugins -l bench/profile/frame.lua <project dir> [rounds] [keys] [size]
-- `keys` is comma-separated (default `j,k`), each fed in turn before a
-- frame; `size` is COLSxROWS (default 187x56). Prints one JSON line: the
-- time of each frame (median, min and max, in ms). Run it under `perf
-- stat -e instructions:u` twice, with 0 rounds and with N, for the
-- instructions of a frame.
local paw = require("paw")
local api = paw.api
local dir, rounds, keys, size = ...
assert(dir, "usage: frame.lua <project dir> [rounds] [keys] [size]")
rounds = tonumber(rounds) or 200
local list = {}
for k in (keys or "j,k"):gmatch("[^,]+") do
  list[#list + 1] = k
end
local W, H = (size or "187x56"):match("(%d+)x(%d+)")
W, H = tonumber(W), tonumber(H)
paw.open(dir)
paw.flush()
-- The chord reading of the song is done before the frames are timed.
paw.harmony.builtin(0, math.huge)
api.ui_snapshot(W, H)
-- With PAW_FRAME_PROF set to a file, LuaJIT's profiler samples the frames
-- (not the keys) and writes folded stacks there, for top.py.
local out = os.getenv("PAW_FRAME_PROF")
local prof = out and require("jit.profile")
local folded = {}
local function sample(th, samples, vmstate)
  local stack = prof.dumpstack(th, "pF;", -48):gsub(";$", "")
  local key = stack .. ";[" .. vmstate .. "]"
  folded[key] = (folded[key] or 0) + samples
end
local times = {}
for i = 1, rounds do
  paw.keymap.feed(list[(i - 1) % #list + 1])
  if prof then prof.start("fi1", sample) end
  local t = api.now()
  api.ui_snapshot(W, H)
  times[i] = api.now() - t
  if prof then prof.stop() end
end
if out then
  local f = assert(io.open(out, "w"))
  for k, v in pairs(folded) do
    f:write(k, " ", v, "\n")
  end
  f:close()
end
table.sort(times)
if rounds > 0 then
  print(
    string.format(
      '{"rounds":%d,"keys":"%s","p50_ms":%.2f,"min_ms":%.2f,"max_ms":%.2f}',
      rounds,
      table.concat(list, ","),
      times[math.ceil(#times / 2)],
      times[1],
      times[#times]
    )
  )
end
api.quit(0)
