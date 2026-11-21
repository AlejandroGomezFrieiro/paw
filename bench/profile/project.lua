-- The large project the profile opens: 64 tracks with a synth each, 2 000
-- MIDI clips (about 31 a track, one bar each) and 50 000 notes (25 a clip),
-- a volume lane on every fourth track, saved as a project folder.
--   paw --clean --no-plugins -l bench/profile/project.lua <dir> [tracks] [clips] [notes]
local paw = require("paw")
local api = paw.api

local dir, tracks, clips, notes = ...
assert(dir, "usage: project.lua <dir> [tracks] [clips] [notes]")
tracks, clips, notes = tonumber(tracks) or 64, tonumber(clips) or 2000, tonumber(notes) or 50000
local per_track = math.ceil(clips / tracks)
local per_clip = math.floor(notes / clips)

local made = 0
for t = 0, tracks - 1 do
  local id = api.track_add({ name = string.format("Track %02d", t + 1) })
  api.device_add(id, "synth", { params = { wave = 1 + t % 3 } })
  for c = 0, per_track - 1 do
    if made >= clips then break end
    local list = {}
    for n = 0, per_clip - 1 do
      -- A fixed spread of pitches and starts inside the bar.
      list[#list + 1] = { pitch = 36 + (t * 7 + c * 5 + n * 3) % 48, start = (n % 16) * 0.25,
        length = 0.25 + (n % 3) * 0.25, velocity = 60 + (n * 13) % 60 }
    end
    api.clip_add(id, { start = c * 4, length = 4, notes = list, name = "c" .. c })
    made = made + 1
  end
  if t % 4 == 0 then
    local points = {}
    for bar = 0, per_track, 4 do points[#points + 1] = { bar * 4, bar % 8 == 0 and -12 or -3 } end
    api.lane_add(id, { target = "volume", points = points })
  end
end
api.undo_checkpoint()
paw.flush()
os.execute("rm -rf '" .. dir .. "'")
api.project_save(dir)
print(string.format('{"tracks":%d,"clips":%d,"notes":%d}', tracks, made, made * per_clip))
api.quit(0)
