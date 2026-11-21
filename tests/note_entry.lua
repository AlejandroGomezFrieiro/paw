-- Entering notes on a new track the way the start screen says: `i`, then
-- `I` to type them; and letters typed while drawing are not lost in silence.
local T = ...
local test, eq = T.test, T.eq
local paw = require("paw")
local api = paw.api

local function roll_notes()
  local clip = paw.ui.views.pianoroll:clip()
  return clip and #clip:notes() or -1
end

test("note entry: the start screen's i Enter then I types notes on a new track, and letters while drawing say what to do", function()
  T.fresh()
  paw.ui.focus("arrange")
  paw.keymap.feed("<Esc><Esc>")
  local screen = table.concat(api.ui_snapshot(120, 30), "\n")
  eq(screen:find("then I", 1, true) ~= nil and screen:find("enter notes: a clip opens to draw them", 1, true) ~= nil, true,
    "the start screen says i, then I")
  paw.keymap.feed("o")
  paw.keymap.feed("i<CR>")
  eq(paw.ui.focused .. " " .. paw.keymap.mode, "pianoroll i", "i Enter opens a clip to enter notes in")
  paw.keymap.feed("a")
  eq(paw.ui.message.text:find("I types notes as a piano", 1, true) ~= nil, true, "a letter while drawing says what it is not")
  paw.keymap.feed("I")
  eq(paw.ui.message.text:find("typing notes as a piano", 1, true) ~= nil, true, "I turns the keys into a piano")
  paw.keymap.feed("asdf")
  eq(roll_notes(), 4, "the letters are notes")
  paw.keymap.feed("<Esc>")
  eq(paw.keymap.mode .. " " .. roll_notes() .. " " .. paw.ui.message.text, "n 4 wrote 4 notes", "Esc keeps them and says so")
  paw.keymap.feed("<Esc>")
  paw.ui.focus("arrange")
end)
