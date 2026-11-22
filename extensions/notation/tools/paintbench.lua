-- How long the notation view's paint takes in the kernel, and how big its
-- drawing is: the first paint, a paint with nothing changed, a cursor move,
-- an edit (one note moved, then undone), and the layout thrown away.
--
--   paw --clean --no-plugins --no-listen --audio null -l extensions/notation/tools/paintbench.lua [bars] [window] [notation]
--
-- With `window` it paints as the window is asked (glyphs as paths, with the
-- toolbar); else as a terminal's pixel surface is (glyph ops, 13 x 27 px cells).
-- With `notation` the edit is made in notation, and its time is the edit
-- itself (the score changed and written back as MIDI) and the paint.
local paw = require("paw")
local args = { ... }
local bars = tonumber(args[1]) or 16
local window = args[2] == "window" or args[3] == "window"
local in_notation = args[2] == "notation" or args[3] == "notation"
paw.ext.load("extensions/notation")
local bench = require("notation.bench")
local result = bench.run(
  bars,
  window and { cell = { w = 7.8, h = 17 } } or { glyphs = true, surface = true, cell = { w = 13, h = 27 } },
  nil,
  { notation = in_notation }
)
print(bench.format(result))
