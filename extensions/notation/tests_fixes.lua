-- Tests of what the extensions' review turned up in notation: a clip undone
-- out of existence under the view, entry at the top of the MIDI range.
-- Loaded by tests/suite.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation"), require("notation.model")
end

local function N(pitch, start, length, velocity)
  return { pitch = pitch, start = start, length = length, velocity = velocity or 80 }
end

--- A track with a clip open as notation.
local function song(notes, length)
  fresh()
  local view = load()
  local track = paw.add_track({ name = "Lead" })
  local clip = track:add_clip({ start = 0, length = length or 8, name = "tune", notes = notes or {} })
  paw.flush()
  paw.keymap.set_mode("n")
  view:edit(clip)
  view.value, view.dot, view.voice, view.triplets, view.tuplet = 1, false, 1, false, nil
  api.undo_checkpoint()
  return view, clip, track
end

--- The messages shown since `mark` (the last one when it was taken): the
--- list keeps the last 500, so it is followed by the message, not counted.
local function since(mark)
  local out, after = {}, mark == nil
  for _, m in ipairs(paw.ui.messages) do
    if after then out[#out + 1] = m end
    if m == mark then after = true end
  end
  return out
end
local function mark() return paw.ui.messages[#paw.ui.messages] end

--- The errors shown since `from` (a `mark()`).
local function errors(from)
  local out = {}
  for _, m in ipairs(since(from)) do
    if m.level == "error" then out[#out + 1] = m.text:match("[^\n]*") end
  end
  return out
end

local LEAVE = { ZZ = true, ["<localleader>n"] = true, zS = true }

test("notation: every key of the view says the clip is gone when an undo took it, and a redo brings it back", function()
  fresh()
  local view = load()
  api.undo_checkpoint()
  local track = paw.add_track({ name = "Lead" })
  local clip = track:add_clip({ start = 0, length = 4, notes = { N(60, 0, 1), N(64, 1, 1) } })
  paw.flush()
  api.undo_checkpoint()
  paw.ui.focus("notation")
  paw.keymap.set_mode("n")
  view:edit(clip)
  paw.undo()
  eq(view:clip(), nil, "the clip is gone")
  local screen = table.concat(api.ui_snapshot(120, 30), "\n")
  eq(screen:find("gone: undone or deleted", 1, true) ~= nil, true, "the view says so")
  local from, tried = mark(), 0
  for _, m in ipairs(paw.keymap.list("n", "notation")) do
    if m.scope == "notation" and not LEAVE[m.lhs] then
      paw.ui.focus("notation")
      paw.keymap.set_mode("n")
      paw.keymap.feed(m.lhs .. "<Esc>")
      tried = tried + 1
    end
  end
  eq(tried > 100, true, "every key of the view was tried: " .. tried)
  eq(table.concat(errors(from), "; "), "", "no key raised an error")
  T.keys("G")
  eq(paw.ui.message.text:find("gone (undone or deleted)", 1, true) ~= nil, true, "G says the clip is gone")
  paw.redo()
  eq(view:clip() and view:clip().id, clip.id, "a redo shows it again")
  paw.ui.focus("arrange")
end)

test(
  "notation: on a long song the title does not read the song's key on every key, but once the edits pause",
  function()
    local notes = {}
    for i = 1, 3000 do
      notes[i] = N(57 + i % 12, (i - 1) * 0.25, 0.25)
    end
    local view, clip = song(notes, 750)
    paw.ui.focus("notation")
    api.ui_snapshot(120, 30)
    clip:add_note(N(60, 0.125, 0.125))
    api.undo_checkpoint()
    api.ui_snapshot(120, 30)
    eq(paw.harmony.fresh(), false, "a draw after an edit leaves the reading for later")
    T.advance_until(function() return paw.harmony.fresh() end, "the key to be read once the edits pause", 5000)
    eq(view:clip().id, clip.id, "")
    paw.ui.focus("arrange")
  end
)

test("notation: a page of a few tall systems keeps them close, not spread over the page", function()
  load()
  local E = require("notation.engrave")
  local systems = {}
  for i = 1, 3 do
    systems[i] = { height = 400 }
  end
  local pg = { height = 1200, gap = 20, margin = 50, header = 0 }
  local pages = E.paginate(systems, pg, 0, function(sys, y) sys.y = y end, 1)
  eq(#pages, 2, "two systems on the first page, the third on the next")
  local gap = systems[2].y - (systems[1].y + systems[1].height)
  eq(gap > 0 and gap <= pg.height / 16, true, "a little room between them, not a quarter of the page: " .. gap)
end)

test("notation: the key bar names + and - for sharp and flat, as the manual does", function()
  song({ N(60, 0, 1) }, 4)
  paw.ui.focus("notation")
  paw.keymap.set_mode("n")
  local words = {}
  for _, e in ipairs(paw.ui.keybar.entries()) do
    words[#words + 1] = e[1] .. " " .. e[2]
  end
  local line = table.concat(words, " · ")
  eq(line:find("+ sharp", 1, true) ~= nil and line:find("- flat", 1, true) ~= nil, true, "the key bar: " .. line)
  paw.keymap.feed("+")
  eq(paw.ui.views:get("notation"):clip():notes()[1].pitch, 61, "and + sharpens")
  paw.ui.focus("arrange")
end)

test("notation: entering and moving notes at the top of the MIDI range stops at G9 and raises no error", function()
  local view, clip = song({}, 4)
  paw.ui.focus("notation")
  local from = mark()
  view:set(72, 0)
  T.keys("ieabgab<Esc>")
  T.keys("0kkkkk<C-a><C-a>")
  T.keys("0vwKK<Esc>")
  T.keys("0i3456<Esc>")
  T.keys("0>>")
  eq(table.concat(errors(from), "; "), "", "no error")
  for _, n in ipairs(clip:notes()) do
    eq(n.pitch <= 127, true, "every pitch within MIDI: " .. n.pitch)
  end
  eq(#clip:notes() > 0, true, "the notes that fit were entered")
  paw.ui.focus("arrange")
end)
