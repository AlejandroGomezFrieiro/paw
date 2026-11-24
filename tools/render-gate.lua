-- Renders the songs of the render gate (tools/render-gate.sh) into the
-- folder OUT, one WAV file for each song. The shell script hashes the files.
--
--   paw --clean --no-plugins --audio null --no-listen -l tools/render-gate.lua OUT
--
-- A song is a Lua file that builds a project, or a saved project. Every
-- render has the same options, so that a hash changes only when the sound
-- changes: 24 bits, no tail, one thread.
local paw = require("paw")
local out = ...

--- The songs: the file name in OUT, and the source.
local songs = {
  { name = "demo-song", lua = "examples/demo-song.lua" },
  { name = "render-song", lua = "tests/fixtures/render-song.lua" },
  { name = "demo-song-saved", load = "tests/fixtures/demo-song.json" },
  { name = "tutorial-1-first-song", lua = "examples/tutorials/make-music/1-first-song.lua" },
  { name = "tutorial-3-guitar", lua = "examples/tutorials/make-music/3-guitar.lua" },
  { name = "tutorial-4-arrange", lua = "examples/tutorials/make-music/4-arrange.lua" },
  { name = "tutorial-5-mix", lua = "examples/tutorials/make-music/5-mix.lua" },
}

for _, song in ipairs(songs) do
  paw.project.new()
  if song.lua then
    dofile(song.lua)
  else
    paw.project.load(song.load)
  end
  local path = out .. "/" .. song.name .. ".wav"
  local info = paw.render(path, { tail = 0, bits = 24, threads = 1, quiet = true })
  print(string.format("render-gate: %s: %d frames", song.name, info.frames))
end
paw.api.quit(0)
