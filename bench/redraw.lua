-- Drawing the terminal UI: how long one frame takes.
--   paw --clean --no-plugins -l bench/redraw.lua [parts] [frames]
-- A project of N parts (a synth each, eight one-bar MIDI clips of 12 notes,
-- a volume lane on every third), then `frames` full redraws of the screen
-- through `ui_snapshot` in a few layouts and sizes. Prints one JSON line per
-- layout with the median and worst frame in milliseconds.
local paw = require("paw")
local api = paw.api
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local parts, frames = ...
parts, frames = tonumber(parts) or 16, tonumber(frames) or 200

for i = 0, parts - 1 do
  local id = api.part_add({ name = "Part " .. i })
  api.device_add(id, "synth", { params = { wave = 1 } })
  for c = 0, 7 do
    api.clip_add(id, { start = c * 4, length = 4, notes = B.bar_notes(0, i) })
  end
  if i % 3 == 0 then paw.part(id):automate("volume"):set_points({ { 0, -12 }, { 16, -3 }, { 32, -9 } }) end
end
api.undo_checkpoint()
paw.flush()
paw.cursor.set_part(api.part_list()[2])

local function measure(name, w, h, setup)
  setup()
  api.ui_snapshot(w, h) -- the first frame fills the caches
  local times = {}
  for i = 1, frames do
    times[i] = B.time(api.ui_snapshot, w, h)
  end
  table.sort(times)
  B.emit({
    bench = "redraw",
    layout = name,
    width = w,
    height = h,
    parts = parts,
    frames = frames,
    p50_ms = times[math.ceil(#times / 2)],
    max_ms = times[#times],
  })
end

local ui = paw.ui
local function arrange_only()
  for _, v in ipairs({ "mixer", "pianoroll", "devices" }) do
    ui.hide(v)
  end
  ui.focus("arrange")
end
local function everything()
  ui.show("mixer")
  ui.show("devices")
  local clip = api.clip_list(api.part_list()[2])[1]
  ui.views:get("pianoroll"):edit(paw.clip(clip.id))
end

measure("arrange", 150, 45, arrange_only)
measure("arrange", 80, 24, arrange_only)
measure("all panels", 150, 45, everything)
measure("all panels", 100, 30, everything)
os.exit(0)
