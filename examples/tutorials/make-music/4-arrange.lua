-- The practice project of "Make music with paw", lesson 4: the four bars
-- of lessons 1 to 3, which we arrange into a song.
--
--   paw -e 'dofile(os.getenv("PAW_HOME") .. "/examples/tutorials/make-music/4-arrange.lua")'
--
-- The guitar of lesson 3 is a recording. Here a synth plays it, through the
-- same amp chain, so that the project plays without a recording.
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
dofile(here .. "3-guitar.lua")

local guitar = paw.add_part({ name = "Guitar" })
guitar:add_device("synth")
paw.params.apply(guitar:devices()[1], "Pluck")
guitar:add_device("saturation", { drive = 10, curve = 1 })
local eq = guitar:add_device("eq")
paw.params.apply(eq, "Electric guitar: tame the fizz")
local riff = {}
for bar, chord in ipairs({ { "A3", "E4", "A4" }, { "F3", "C4", "F4" } }) do
  for _, at in ipairs({ 0, 1.5, 2.5, 3 }) do
    for _, pitch in ipairs(chord) do
      riff[#riff + 1] = { pitch = pitch, start = (bar - 1) * 4 + at, length = 0.5, velocity = 90 }
    end
  end
end
guitar:add_clip({ name = "riff", start = 0, length = 8, notes = riff })
paw.cursor.set_part(paw.part("Drums"))
