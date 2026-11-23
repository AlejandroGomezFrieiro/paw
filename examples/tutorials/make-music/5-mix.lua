-- The practice project of "Make music with paw", lesson 5: the song that
-- lesson 4 arranged (verse, chorus, verse, chorus at 104 BPM), which we
-- mix and render.
--
--   paw -e 'dofile(os.getenv("PAW_HOME") .. "/examples/tutorials/make-music/5-mix.lua")'
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
dofile(here .. "4-arrange.lua")

--- Put a copy of each clip of the part at `offset` beats later.
local function repeat_clips(part, offset)
  for _, clip in ipairs(part:clips()) do
    part:add_clip({ name = clip.name, start = clip.start + offset, length = clip.length, notes = clip:notes() })
  end
end

-- The verse is drums, bass and keys. The chorus adds the lead, and the
-- guitar answers it in the second half.
for _, name in ipairs({ "Drums", "Bass", "Keys" }) do
  repeat_clips(paw.part(name), 16)
end
for _, name in ipairs({ "Lead", "Guitar" }) do
  local clip = paw.part(name):clips()[1]
  clip.start = name == "Guitar" and 24 or 16
end
for _, part in ipairs(paw.parts()) do
  repeat_clips(part, 32)
end

for _, marker in ipairs({ { 0, "Verse" }, { 16, "Chorus" }, { 32, "Second verse" }, { 48, "Last chorus" } }) do
  paw.markers.add(marker[1], marker[2])
end
paw.project.tempo = 104
paw.transport.loop_enabled = false
paw.cursor.set_part(paw.part("Drums"))
