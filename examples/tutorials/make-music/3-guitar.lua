-- The practice project of "Make music with paw", lesson 3: the song of
-- lesson 2 with its lead, where we record a guitar.
--
--   paw -e 'dofile(os.getenv("PAW_HOME") .. "/examples/tutorials/make-music/3-guitar.lua")'
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
dofile(here .. "2-midi-keyboard.lua")

-- The lead of lesson 2, as a person played it and `=ie` put it on the grid.
local lead = paw.add_part({ name = "Lead" })
lead:add_device("synth")
local melody = {}
for _, n in ipairs({
  { "E5", 0, 1 },
  { "C5", 1, 1 },
  { "A4", 2, 2 },
  { "F4", 4, 1 },
  { "A4", 5, 1 },
  { "C5", 6, 2 },
  { "E5", 8, 1 },
  { "G5", 9, 1 },
  { "E5", 10, 2 },
  { "D5", 12, 2 },
  { "B4", 14, 2 },
}) do
  melody[#melody + 1] = { pitch = n[1], start = n[2], length = n[3], velocity = 96 }
end
lead:add_clip({ name = "lead", start = 0, length = 16, notes = melody })
paw.cursor.set_part(paw.part("Drums"))
