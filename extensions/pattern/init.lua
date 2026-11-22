-- Patterns: a line of text in the manner of TidalCycles' mini-notation that
-- becomes the notes of a clip, and can be changed while the song plays.
-- See README.md beside this file.
paw.option.define("pattern_names", true) -- name pattern clips after their text
paw.option.define("pattern_cycles", 4) -- cycles in a clip made by `pattern.set`

local pattern = require("pattern")

-- A clip follows its text through every change, however it was made: a
-- longer clip plays more cycles, undo brings back text and notes together,
-- and notes edited by other means detach it.
for _, name in ipairs({ "clip.changed", "clip.added" }) do
  paw.on(name, function(event) pattern.refresh(event.id) end)
end
-- A new time signature changes how long a cycle of one bar is.
paw.on("project.changed", function() pattern.refresh_all() end)

require("pattern.commands")
