-- Saving and loading a large project.
--   paw --clean --no-plugins -l bench/saveload.lua <tracks> <clips per track> [json]
-- Each track has a synth and a delay and `clips` one-bar MIDI clips of 12
-- notes, as in the Tracktion driver's `saveload`. The project is saved as a
-- folder (`json` saves it in one file instead). `resave_ms` is a second
-- save with nothing changed, which writes no file.
local paw = require("paw")
local api = paw.api
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local tracks, clips, form = ...
tracks, clips = tonumber(tracks) or 100, tonumber(clips) or 8
local one_file = form == "json"

local function build()
  for i = 0, tracks - 1 do
    local id = api.track_add({ name = "T" .. i })
    api.device_add(id, "synth", { params = { wave = 1 } })
    api.device_add(id, "delay")
    for c = 0, clips - 1 do
      local notes = B.bar_notes(0, i)
      api.clip_add(id, { start = c * 4, length = 4, notes = notes })
    end
  end
  api.undo_checkpoint()
  paw.flush()
end

--- Bytes and files under a path.
local function size(path, dir)
  if not dir then
    local f = io.open(path, "rb")
    if not f then return 0, 0 end
    local bytes = f:seek("end")
    f:close()
    return bytes, 1
  end
  local bytes, files = 0, 0
  for _, e in ipairs(api.read_dir(path)) do
    local b, n = size(path .. "/" .. e.name, e.is_dir)
    bytes, files = bytes + b, files + n
  end
  return bytes, files
end

local build_ms = B.time(build)
local path = B.tmp .. (one_file and "/bench-project.json" or "/bench-project")
os.execute("rm -rf '" .. path .. "'")
local save_ms = B.time(api.project_save, path)
local resave_ms = B.time(api.project_save, path)
local bytes, files = size(path, not one_file)
api.project_new()
paw.flush()
local load_ms = B.time(function()
  api.project_load(path)
  paw.flush()
end)
local loaded = #api.track_list()
os.execute("rm -rf '" .. path .. "'")
B.emit({
  workload = "saveload",
  form = one_file and "json" or "folder",
  tracks = tracks,
  clips_per_track = clips,
  build_ms = build_ms,
  save_ms = save_ms,
  resave_ms = resave_ms,
  load_ms = load_ms,
  file_bytes = bytes,
  files = files,
  loaded_tracks = loaded,
  rss_kb = B.rss(),
})
api.quit(0)
