-- Tests of the undo file: a project opened again undoes past its last save.
-- The suite runs with --clean, where the undo file is off: each test turns
-- it on, and it is in the suite's own state directory. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh, keys = T.test, T.eq, T.fresh, T.keys
local api = paw.api

--- A project folder of this name with one part, saved, with the undo file
--- on unless `off`. Returns the folder and the part.
local function project(name, off)
  local path = T.scratch .. "/undofile-" .. name
  local state = paw.loading.project_dir(path .. "/project.toml")
  paw.opt.undofile = not off
  T.after(function()
    paw.opt.undofile = false
    api.undo_file_wait()
    os.execute("rm -rf '" .. state .. "'")
  end)
  fresh()
  os.execute("rm -rf '" .. path .. "' '" .. state .. "'")
  local part = api.part_add({ name = "Bass" })
  api.undo_checkpoint()
  paw.project.save(path)
  paw.flush()
  return path, part
end

--- An edit of its own: the part's name.
local function rename(part, name)
  api.part_set(part, { name = name })
  paw.flush()
  api.undo_checkpoint()
end

--- Close the project, as quitting does, and open it again with the keys.
local function reopen(path)
  fresh()
  keys(":e " .. path .. "<CR>")
end

local function name_of(part) return api.part_get(part).name end

test("a project opened again undoes past its last save, and redoes", function()
  local path, part = project("three")
  for _, name in ipairs({ "A", "B", "C" }) do
    rename(part, name)
  end
  keys(":w<CR>")
  reopen(path)
  eq(name_of(part), "C", "opened as saved")
  local seen = {}
  for _ = 1, 3 do
    keys("u")
    seen[#seen + 1] = name_of(part)
  end
  eq(table.concat(seen, " "), "B A Bass", "u goes back through the three edits")
  keys("<C-r>")
  keys("<C-r>")
  eq(name_of(part), "B", "<C-r> forward")
end)

test("a branch made before the save is in the undo tree after the project opens again", function()
  local path, part = project("branch")
  rename(part, "A")
  rename(part, "B")
  local branch = api.undo_current()
  keys("u")
  rename(part, "X")
  keys(":w<CR>")
  reopen(path)
  local tree = api.undo_tree()
  local state
  for _, s in ipairs(tree.states) do
    if s.id == branch then state = s end
  end
  eq(state ~= nil and #tree.states, 5, "the branch's state is in the tree")
  eq(api.undo_goto(branch), true, "and can be gone to")
  eq(name_of(part), "B", "with its project")
end)

test("a project changed outside paw opens without its undo file, and says so once", function()
  local path, part = project("changed")
  rename(part, "A")
  keys(":w<CR>")
  fresh()
  T.write_file(path .. "/project.toml", T.read_file(path .. "/project.toml") .. "# changed\n")
  local before = #paw.ui.messages
  keys(":e " .. path .. "<CR>")
  local said = 0
  for i = before + 1, #paw.ui.messages do
    if paw.ui.messages[i].text:find("the undo file is for another version of the project", 1, true) then
      said = said + 1
    end
  end
  eq(said, 1, "the message comes once")
  eq(#api.undo_tree().states, 1, "the undo tree starts at the opened state")
end)

test("with undofile off, as under --clean, nothing is written or read", function()
  eq(paw.opt.undofile, false, "off under --clean")
  local path, part = project("off", true)
  local dir = paw.loading.project_dir(api.project_get("path")) .. "/undo"
  rename(part, "A")
  keys(":w<CR>")
  reopen(path)
  eq(io.open(dir .. "/tree.json") == nil, true, "nothing written")
  eq(#api.undo_tree().states, 1, "nothing read")
end)
