-- Tests of what stands between a project with unsaved work and every way of
-- replacing it. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local function said()
  return paw.ui.messages[#paw.ui.messages].text
end

--- A project that came from a MIDI file: it has notes, no file, and nothing
--- in its undo history, so it is not "modified".
local function imported()
  fresh()
  local t = paw.add_track({ name = "Keys" })
  t:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1, velocity = 90 } } })
  local path = T.scratch .. "/unsaved.mid"
  paw.midifile.export(path)
  fresh()
  T.keys(":open " .. path .. "<CR>")
  eq(#paw.tracks(), 1, "the file is open")
  eq(api.project_get().path, nil, "it has no file of its own")
  eq(api.project_get().modified, false, "and nothing to undo")
  return path
end

local function kept(why)
  eq(#paw.tracks(), 1, why)
end

test("a project opened from a MIDI file counts as unsaved work, and the window asks about it", function()
  imported()
  eq(paw.project.unsaved(), true, "no file, and something in it")
  eq(paw.frontend.closing().modified, true, "the window's question is asked")
  fresh()
  eq(paw.project.unsaved(), false, "an empty untitled project has nothing to lose")
end)

test(":open, :edit, :new and :recent leave an imported project in place and say why", function()
  local path = imported()
  for _, line in ipairs({ ":open " .. path, ":edit " .. T.scratch .. "/other.json", ":new", ":recent" }) do
    -- The last message, not how many: the list keeps the latest 500 only.
    local before = paw.ui.messages[#paw.ui.messages]
    T.keys(line .. "<CR>")
    kept(line .. " left it")
    eq(paw.ui.messages[#paw.ui.messages] ~= before and said():find("unsaved work", 1, true) ~= nil, true, line .. " says why: " .. said())
  end
  T.keys(":q<CR>")
  eq(said():find("unsaved work", 1, true) ~= nil, true, ":q is refused too")
end)

test("the ! form of each goes on and throws the work away", function()
  local path = imported()
  T.keys(":new!<CR>")
  eq(#paw.tracks(), 0, ":new! starts an empty project")
  imported()
  T.keys(":open! " .. path .. "<CR>")
  eq(#paw.tracks(), 1, ":open! opens the file again")
  T.keys(":new<CR>")
  kept(":new is refused again at once")
  T.keys(":edit! " .. path .. "<CR>")
  eq(#paw.tracks(), 1, ":edit! opens it")
  eq(paw.project.discarding(), false, "and the ! is over when it is done")
end)

test(":recover and picking a project from the file list are guarded", function()
  imported()
  local file = T.scratch .. "/guard-copy.json"
  api.project_backup(file, {})
  paw.autosave.recover(file)
  kept(":recover left it")
  eq(said():find("unsaved work", 1, true) ~= nil, true, "and said why")
  paw.autosave.recover(file, { force = true })
  eq(#paw.tracks(), 1, "with force it opens the copy")
  os.remove(file)
  imported()
  paw.pick.sources.files.on_choose({ kind = "project", path = file })
  kept("the file picker left it")
end)

test("a saved project, or one with changes saved, is replaced without asking", function()
  imported()
  local file = T.scratch .. "/guard-saved.json"
  paw.project.save(file)
  eq(paw.project.unsaved(), false, "saved")
  T.keys(":new<CR>")
  eq(#paw.tracks(), 0, ":new goes ahead")
end)

test("a new project with a track in it is unsaved work until it has a file", function()
  fresh()
  paw.add_track({ name = "Idea" })
  api.undo_checkpoint()
  eq(paw.project.unsaved(), true, "changed")
  T.keys(":new<CR>")
  eq(#paw.tracks(), 1, "refused")
  T.keys(":new!<CR>")
  eq(#paw.tracks(), 0, "forced")
end)
