-- Tests of the list of recent projects, opening the last one at the start,
-- and the window's remembered layout. Loaded by tests/suite.lua with its
-- helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local dir = T.scratch .. "/recent"
os.execute("mkdir -p '" .. dir .. "'")
local counter = 0

--- Point the list at a file of this test's own, as the program does when it
--- is not run with --clean; `done()` puts things back.
local function keeping(fn)
  counter = counter + 1
  local file = string.format("%s/list-%d.json", dir, counter)
  paw.recent.use(file)
  local ok, err = xpcall(fn, debug.traceback)
  paw.recent.use()
  paw.opt.reopen_last = false
  if not ok then error(err, 0) end
end

--- A project file of this name, saved (and so remembered).
local function save(name)
  fresh()
  local path = string.format("%s/%s.json", dir, name)
  paw.project.save(path)
  paw.flush()
  return path
end

local function paths()
  local out = {}
  for i, entry in ipairs(paw.recent.list()) do
    out[i] = entry.path
  end
  return table.concat(out, " ")
end

test("recent: the newest project is first, and one that is opened again moves up", function()
  keeping(function()
    local a, b, c = save("a"), save("b"), save("c")
    eq(paths(), table.concat({ c, b, a }, " "), "newest first")
    paw.project.load(a)
    paw.flush()
    eq(paths(), table.concat({ a, c, b }, " "), "opening one puts it first, once")
    local entry = paw.recent.list()[1]
    eq(entry.name, "a", "the name is the file's")
    eq(entry.time > 0, true, "and when it was")
  end)
end)

test("recent: only twenty are kept", function()
  keeping(function()
    for i = 1, 22 do
      save("many" .. i)
    end
    local list = paw.recent.list()
    eq(#list, 20, "twenty")
    eq(list[1].path, dir .. "/many22.json", "the newest is first")
    eq(list[20].path, dir .. "/many3.json", "the two oldest are gone")
  end)
end)

test("recent: a project whose file is gone is left out", function()
  keeping(function()
    local a, b = save("gone-a"), save("gone-b")
    os.remove(a)
    eq(paths(), b, "the list is read without it")
    paw.recent.clear()
    eq(paths(), "", "clear forgets them all")
  end)
end)

test("recent: nothing is kept when the program runs with --clean", function()
  eq(api.env().clean, true, "the suite runs clean")
  paw.recent.use()
  local before = paths()
  save("not-remembered")
  eq(paths(), before, "a save adds nothing")
end)

test(":recent 2 opens the second without a list", function()
  keeping(function()
    local a = save("pick-a")
    save("pick-b")
    fresh()
    paw.commands.exec("recent 2")
    paw.flush()
    eq(api.project_get().path, a, "the second is open")
    eq(paw.recent.list()[1].path, a, "and is the newest now")
  end)
end)

test(":recent chooses from a list with the name, the place and the time", function()
  keeping(function()
    local a = save("list-a")
    save("list-b")
    fresh()
    paw.commands.exec("recent")
    local state = paw.pick.state()
    eq(state ~= nil, true, "a picker opened")
    paw.keymap.feed("list-a<CR>")
    paw.flush()
    eq(paw.pick.state(), nil, "Enter closed it")
    eq(api.project_get().path, a, "and opened the one chosen")
  end)
end)

test("recent: the window's Open recent asks about unsaved changes like Open does", function()
  keeping(function()
    local a = save("leave-a")
    save("leave-b")
    paw.add_part({ name = "unsaved" })
    paw.flush()
    eq(paw.frontend.closing().modified, true, "there are changes to save")
    paw.frontend.act.leave("discard", "open:" .. a)
    paw.flush()
    eq(api.project_get().path, a, "the one named is open")
    eq(paw.frontend.recent_menu()[1].path, a, "the menu lists it first")
  end)
end)

test("reopen_last opens the newest project, and a failure is a message", function()
  keeping(function()
    local a = save("last-a")
    fresh()
    eq(paw.recent.reopen_last(), false, "the option is off")
    eq(api.project_get().path, nil, "nothing opened")
    paw.opt.reopen_last = true
    eq(paw.recent.reopen_last(), true, "it opens one")
    paw.flush()
    eq(api.project_get().path, a, "the newest")
    local b = save("last-b")
    paw.project.new()
    local handle = assert(io.open(b, "wb"))
    handle:write("this is not a project")
    handle:close()
    eq(paw.recent.reopen_last(), false, "a project that will not open is not an error")
  end)
end)

test("the window's layout is kept and comes back", function()
  local was = paw.frontend.layout_path
  paw.frontend.layout_path = dir .. "/window.json"
  os.remove(paw.frontend.layout_path)
  eq(next(paw.frontend.layout_get()), nil, "nothing kept yet")
  paw.frontend.layout_set({ width = 1200, height = 700, zoom = 31.5, row_height = 80, roll_height = 300, mixer = true })
  local got = paw.frontend.layout_get()
  paw.frontend.layout_path = was
  eq(got.width, 1200, "width")
  eq(got.zoom, 31.5, "zoom")
  eq(got.row_height, 80, "row height")
  eq(got.roll_height, 300, "roll height")
  eq(got.mixer, true, "mixer")
end)
