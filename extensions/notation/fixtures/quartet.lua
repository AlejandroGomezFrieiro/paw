-- A quartet of sixteen bars for the score and the parts: two flutes (in
-- unison, the first alone, in thirds, resting), a clarinet in B flat, a
-- cello. The tracks come in an order a score would not keep, and the
-- clarinet's part has a cue from the first flute. Used for the pictures
-- of `:help notation-parts`:
--   paw --clean --no-plugins --audio null -e "dofile('extensions/notation/fixtures/quartet.lua')"
local api = paw.api
if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end

local PC = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

--- Notes from text: `C5:1 D5:.5 r:2 | ...`, a name (or `r`) and a length in beats.
local function line(text)
  local notes, at = {}, 0
  for word in text:gmatch("%S+") do
    if word ~= "|" then
      local name, len = word:match("^(.-):([%d.]+)$")
      len = tonumber(len)
      if name ~= "r" then
        local letter, acc, octave = name:match("^(%u)([#b]?)(%-?%d)$")
        local pitch = (tonumber(octave) + 1) * 12 + PC[letter] + (acc == "#" and 1 or acc == "b" and -1 or 0)
        notes[#notes + 1] = { pitch = pitch, start = at, length = len * 0.95, velocity = 80 }
      end
      at = at + len
    end
  end
  return notes
end

local tune = "E5:1 F5:.5 G5:.5 A5:1 G5:1 | F5:1 E5:1 D5:2 | E5:.5 F5:.5 G5:1 C6:1.5 B5:.5 | A5:2 G5:2 | "
local flute1 = line(
  tune
    .. "C5:1 D5:1 E5:1 F5:1 | G5:3 r:1 | E5:1 G5:1 C6:1 B5:1 | A5:4 | "
    .. "r:4 | r:4 | r:4 | r:4 | "
    .. "G5:1 A5:1 B5:1 C6:1 | D6:2 B5:2 | C6:1 G5:1 E5:1 G5:1 | C6:4"
)
local flute2 = line(
  tune
    .. "r:4 | r:4 | C5:1 E5:1 A5:1 G5:1 | F5:4 | "
    .. "r:4 | r:4 | r:4 | r:4 | "
    .. "E5:1 F5:1 G5:1 A5:1 | B5:2 G5:2 | E5:1 E5:1 C5:1 E5:1 | E5:4"
)
local clarinet = line(
  "r:4 | r:4 | r:4 | r:4 | "
    .. "E4:2 F4:2 | G4:4 | C4:2 E4:2 | F4:4 | "
    .. "G4:1 A4:1 Bb4:1 A4:1 | G4:2 F4:2 | E4:1 F4:1 G4:1 E4:1 | D4:4 | "
    .. "D4:2 F4:2 | G4:4 | G4:2 E4:2 | E4:4"
)
local cello = line(
  "C3:4 | G2:4 | A2:2 E2:2 | F2:2 G2:2 | "
    .. "C3:2 B2:2 | E2:4 | A2:4 | D3:2 G2:2 | "
    .. "r:4 | r:4 | C3:2 A2:2 | G2:4 | "
    .. "G2:4 | G2:4 | C3:2 G2:2 | C2:4"
)

local tracks = {}
for _, spec in ipairs({
  { "Violoncello", cello },
  { "Clarinet in Bb", clarinet },
  { "Flute 1", flute1 },
  { "Flute 2", flute2 },
}) do
  local track = paw.add_track({ name = spec[1] })
  track:add_clip({ start = 0, length = 64, name = spec[1], notes = spec[2] })
  tracks[spec[1]] = track
end
local meta = api.project_get().meta or {}
meta.title, meta.composer = "Quartet", "paw"
api.project_set("meta", meta)
api.project_set("tempo", 96)
paw.flush()

-- Marks written in notation: a tempo, dynamics, a rehearsal mark.
local view = require("notation")
view:edit(tracks["Flute 1"]:clips()[1])
paw.commands.exec("1notation.tempo Andante q=96")
paw.commands.exec("1notation.dyn mf")
paw.commands.exec("9notation.rehearsal B")
view:edit(tracks["Violoncello"]:clips()[1])
paw.commands.exec("1notation.dyn p")
-- The clarinet comes in at bar 5: the flute's bars 3 and 4 as a cue.
paw.commands.exec("part Clarinet")
paw.commands.exec("3,4part.cue Flute 1")
paw.commands.exec("part.score")
api.undo_checkpoint()
