-- "Take the song to another DAW and back" (the interop extension): the
-- person sketches a song as in the song scenario, then writes it as a
-- REAPER project and as a DAWproject file. Each file, opened again in paw,
-- holds what the model holds, but for what the format cannot carry.
-- short: 3
local song = dofile("tests/e2e/scenarios/song.lua")
local paw = require("paw")
local api = paw.api
local days = {}

--- What a format cannot carry, field by field: the model's copy without
--- these fields is compared with the file opened again.
local LOSSES = {
  -- paw's own devices stay in paw: the page lists them (`instrument=synth` gives a synth back).
  rpp = { devices = true },
  dawproject = {},
}

--- The model as a file of `format` should give it back.
local function carried(E, format)
  local want = E.Model.copy(E.model)
  for _, t in ipairs(want.parts) do
    for field in pairs(LOSSES[format]) do
      t[field] = E.ANY
    end
  end
  return want
end

--- Open `file` aside (the person's project stays as it is, with its undo
--- history), compare it with the model, and come back.
local function reopen(E, file, format)
  api.project_shelve()
  local ok, err = pcall(function()
    paw.open(file)
    local got = E.snapshot()
    E:compare("open " .. file .. " again", carried(E, format), got)
  end)
  -- The page of what was not brought across.
  while paw.ui.float do
    paw.ui.close()
  end
  api.project_unshelve()
  if not ok then error(err, 0) end
end

-- Days 1 and 2 are those of the song: a sketch; a chorale, a drum sample,
-- colors and levels.
days[1] = function(E) song.days[1](E) end
days[2] = function(E) song.days[2](E) end

-- Day 3: the song goes out as a REAPER project and as a DAWproject file.
days[3] = function(E)
  E:act({ name = "load the interop extension", keys = { ":ext.load interop<CR>" } })
  for _, format in ipairs({ "rpp", "dawproject" }) do
    local file = E.workdir .. "/song." .. format
    E:act({
      name = "write the song as ." .. format,
      keys = { "<Esc>", ":w " .. file .. "<CR>" },
      slow = true,
      check = function(self) reopen(self, file, format) end,
    })
    E:act({ name = "close the page of what was not written", keys = { "<Esc>" } })
  end
end

return { days = days }
