-- Notation for paw: a MIDI clip shown as staff notation, to read and to
-- edit, in the terminal and in a window of the graphical frontend.
-- See README.md beside this file.
local view = require("notation")
require("notation.marks")
require("notation.tab")
require("notation.tui")
require("notation.gui")
require("notation.keys")
require("notation.roll")
require("notation.write")
require("notation.popover")
require("notation.files")
require("notation.search")
require("notation.part_keys")
-- Last: it takes in every key of the view for the score's staves.
require("notation.staves")

-- Where three or more windows share the room, the staves take half of it at most.
view.share = { most = 1 / 2 }
-- Each window of the notation has its own clip or score, cursor, zoom and
-- scroll: one score twice, or the notation beside the roll of its clip.
view.window_state = {
  "clip_id",
  "gone",
  "cache",
  "parts",
  "beat",
  "step",
  "first",
  "zoom",
  "galley",
  "page",
  "space",
  "geometry",
  "caret_cell",
  "cell_hover",
  "chord",
  "last",
}
view.window_fresh = { "cache", "geometry", "caret_cell", "cell_hover", "chord", "last" }
-- And the scroll and the hit places of its painted drawing (notation.gui).
local gui = view.gui
paw.layout.window_keep(
  "notation",
  function() return { gui.scroll, gui.hscroll, gui.heads, gui.measures, gui.buttons } end,
  function(v)
    gui.scroll, gui.hscroll, gui.heads, gui.measures, gui.buttons =
      v[1] or 0, v[2] or 0, v[3] or {}, v[4] or {}, v[5] or {}
  end,
  function(v) return { v[1], v[2], {}, {}, {} } end,
  "notation.gui"
)
paw.ui.view("notation", view)
paw.ui.dock("notation", { side = "bottom", hidden = true })
-- Staves need rows: the panel takes twice the share of the arrange view.
local function weigh(node)
  for _, child in ipairs(node) do
    if child.view == "notation" then child.weight = 2 end
    weigh(child)
  end
end
weigh(paw.ui.layout)
