-- The heads of the arrange view's rows (paw/heads.tl): the default head
-- made of pieces, the choice of a head by name, the lit flags, the keys of
-- a head, the height that a head wishes for, and the hits of the pointer.
local T = ...
local test, eq, fresh, expect_screen = T.test, T.eq, T.fresh, T.expect_screen
local paw = require("paw")

--- A song of three parts with the arrange view alone: an audio part with
--- an input and a pan, a MIDI part with a synth, and a part of a kind
--- that an extension defines, with a send.
local function three_parts()
  fresh()
  paw.cmd("view.only")
  paw.ui.views:get("arrange").scroll = 0
  paw.part_kinds.define("testvocal", { title = "Test vocal part", letter = "V" })
  T.after(function() paw.part_kinds.remove("testvocal") end)
  local guitar = paw.add_part({ name = "Guitar" })
  local piano = paw.add_part({ name = "Piano" })
  local vocal = paw.add_part({ name = "Vocal" })
  local reverb = paw.add_part({ name = "Reverb" })
  guitar.input = "1"
  guitar.volume = -3.5
  guitar.pan = -0.3
  vocal.sends = { { target = reverb.id, level = -9 } }
  piano:add_device("synth")
  piano.solo = true
  guitar.mute = true
  paw.part_kinds.set(vocal, "testvocal")
  paw.cursor.set_part(guitar)
  paw.flush()
  -- The meters are on the screen: the sound of an earlier test falls first.
  T.until_meters_at_rest()
  return guitar, piano, vocal
end

-- The header columns at each width: the part column, the head and the rule.
local widths = { { 60, 3, 15 }, { 100, 3, 25 }, { 140, 4, 29 } }

test("the default head draws the same cells at 60, 100 and 140 columns", function()
  three_parts()
  for _, w in ipairs(widths) do
    paw.opt.part_height = w[2]
    paw.flush()
    expect_screen("default_" .. w[1], w[1], 20, { rows = { 2, 1 + 3 * w[2] }, cols = { 1, w[3] } })
  end
end)
