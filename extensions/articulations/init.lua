-- Articulations for paw: which way each note is played, kept on the note as
-- its MIDI 2.0 attribute, named per instrument by `.art.toml` maps, and
-- told to MIDI 1.0 instruments by keyswitches, controllers or programs.
-- See README.md beside this file.
paw.option.define("art_from_notation", true) -- a mark or technique written in the score sets the notes' articulation

local art = require("articulations")
package.loaded["paw.articulations"] = art

require("articulations.roll")
require("articulations.commands")
require("articulations.diagnostics").schedule()
require("articulations.measure")
require("articulations.linked")

-- With the notation extension, the score shows the articulations and sets them.
local function with_notation()
  if package.loaded["articulations.notation"] then return true end
  if not package.loaded["notation.marks"] then return false end
  require("articulations.notation")
  return true
end
if not with_notation() then
  paw.on("project.loaded", with_notation)
  paw.defer(with_notation, 0)
end
