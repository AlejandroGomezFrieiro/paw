-- Tests of small things that read wrong or were left behind: what the views
-- draw over each other, and what is said. Loaded by tests/suite.lua with its
-- helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local function start()
  fresh()
  api.engine_restart({})
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
end

test("the playhead over a take lane keeps the letters of the take's name", function()
  start()
  local zoom = paw.opt.zoom
  T.after(function() paw.opt.zoom = zoom end)
  paw.opt.zoom = 16
  local t = paw.add_track({ name = "Lead" })
  local clip = t:add_clip({ start = 0, length = 4, name = "Riff", notes = { { pitch = 60, start = 0, length = 1 } } })
  paw.takes.new(clip.id)
  paw.takes.show_lanes(t.id, true)
  api.undo_checkpoint()
  paw.cursor.set_track(t)
  -- Two columns in: on the "i" of each take's name.
  for _, beat in ipairs({ 2 / 16, 3 / 16, 7 / 16 }) do
    paw.transport.seek(beat)
    paw.flush()
    local text = table.concat(api.ui_snapshot(120, 20), "\n")
    eq(text:find("Riff 1", 1, true) ~= nil, true, "the first take's name whole, the playhead at " .. beat)
    eq(text:find("Riff 2", 1, true) ~= nil, true, "the second's, the playhead at " .. beat)
  end
end)

test("a short clip with takes keeps room for its name, says which take plays, and ]t changes it", function()
  start()
  local t = paw.add_track({ name = "Lead" })
  local clip = t:add_clip({ start = 0, length = 4, name = "take 1", notes = { { pitch = 60, start = 0, length = 1 } } })
  paw.takes.new(clip.id)
  paw.takes.new(clip.id)
  paw.takes.select(clip.id, 1)
  api.undo_checkpoint()
  paw.cursor.set_track(t)
  paw.cursor.set_beat(1)
  local function line()
    paw.flush()
    for _, row in ipairs(api.ui_snapshot(120, 20)) do
      if row:find("‹", 1, true) then return row end
    end
    return ""
  end
  -- A bar at the default zoom has room for four letters and the take.
  eq(line():find("▏tak…‹1›", 1, true) ~= nil, true, "the name and the mark of a one-bar clip: " .. line())
  T.keys("]t")
  eq(line():find("▏tak…‹2›", 1, true) ~= nil, true, "]t shows on the clip: " .. line())
end)

test(":g/pat/p lists the matches in the quickfix list, as :g/pat/ does", function()
  start()
  local t = paw.add_track({ name = "Keys" })
  t:add_clip({
    start = 0,
    length = 4,
    notes = {
      { pitch = 60, start = 0, length = 1 },
      { pitch = 64, start = 1, length = 1 },
      { pitch = 60, start = 2, length = 1 },
    },
  })
  api.undo_checkpoint()
  for _, cmd in ipairs({ "p", "print", "#", "nu" }) do
    T.keys(":g/c4/" .. cmd .. "<CR>")
    eq(#paw.qf.current().entries, 2, ":g/c4/" .. cmd .. " lists the two C4s")
  end
end)

test(":w with a folder of other files says to name a project folder in it instead of taking it over", function()
  start()
  local folder = T.scratch .. "/a-folder"
  os.execute("mkdir -p '" .. folder .. "' && touch '" .. folder .. "/notes.txt'")
  T.keys(":w " .. folder .. "<CR>")
  eq(
    paw.ui.message.text,
    folder .. " has files and is not a project: `:w " .. folder .. "/song` makes a project folder in it",
    "the message"
  )
  eq(paw.ui.message.level, "warn", "a warning, not an error with a trace")
  -- An empty folder becomes the project's folder.
  local empty = T.scratch .. "/an-empty-folder"
  os.execute("mkdir -p '" .. empty .. "'")
  T.keys(":w " .. empty .. "<CR>")
  eq(paw.ui.message.text, "saved " .. empty .. "/project.toml", "saved into it")
end)

test("a time signature's lower number is a power of two", function()
  start()
  T.fails(function() paw.project.sig_den = 3 end, "1, 2, 4, 8, 16, 32 or 64, not 3", "3 is refused")
  paw.project.sig_den = 8
  eq(paw.project.sig_den, 8, "8 is taken")
  paw.project.sig_den = 4
end)

test("a script run with -l finds its arguments in arg, as Neovim's -l gives them", function()
  eq(type(arg), "table", "the suite has arg")
  eq(arg[0], "tests/suite.lua", "arg[0] is the script")
  local name = "a script run with -l finds its arguments in arg, as Neovim's -l gives them"
  eq(
    arg[1] == nil or name:find(arg[1], 1, true) ~= nil,
    true,
    "arg[1] its first argument: the words choosing tests, if any"
  )
end)
