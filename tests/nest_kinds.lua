-- Tests of the kinds of subproject that extensions define
-- (`paw.nest.define_kind`, paw/nest.tl), and of the events `nest.enter`,
-- `nest.leave` and `nest.changed`. Loaded by tests/suite.lua with its
-- helpers.
local T = ...
local test, eq, fresh, keys = T.test, T.eq, T.fresh, T.keys
local api = paw.api
local L = paw.layout

local initial = L.capture()

local function reset()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  L.restore(initial)
  paw.ui.focus("arrange")
end

local function start()
  fresh()
  api.engine_restart({})
  reset()
  T.after(reset)
end

local function names(ids)
  local out = {}
  for i, id in ipairs(ids) do
    out[i] = api.track_get(id, "name")
  end
  return table.concat(out, " ")
end

--- What `K` says of the block at the cursor.
local function described()
  keys("K")
  local said = T.hover_text()
  paw.ui.close()
  return said
end

-- A fixture extension: the kind `beats.pattern` makes a track Kit with a
-- synth and a note, keeps 16 steps as its data, and opens its view
-- `beatgrid` when a window goes inside. The kind `beats.broken` adds a
-- track, then fails.
local EXTENSION = [[
paw.ui.view("beatgrid", {
  title = "Beat grid",
  render = function(_, buf) buf:text(0, 0, "beat grid") end,
})
paw.nest.define_kind("beats.pattern", {
  title = "Beat pattern",
  letter = "B",
  create = function(region)
    local kit = paw.api.track_add({ nest = region.nest, name = "Kit" })
    paw.api.clip_add(kit, { start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
    paw.track(kit):add_device("synth", { attack = 0.001, release = 0.01 })
    return { steps = 16 }
  end,
  enter = function() paw.ui.focus("beatgrid") end,
  describe = function(nest) return paw.nest.data(nest).steps .. " steps" end,
})
paw.nest.define_kind("beats.broken", {
  title = "Broken pattern",
  create = function(region)
    paw.api.track_add({ nest = region.nest, name = "Half" })
    return nil, "no kit here"
  end,
})
]]

--- Load the fixture extension until the test ends (or until `unload`).
local function load_kind()
  local dir = T.scratch .. "/beats"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(dir .. "/init.lua", EXTENSION)
  eq(paw.ext.load(dir).ok, true, "the fixture extension loads")
  T.after(function()
    if paw.ext.loaded.beats then paw.ext.unload("beats") end
  end)
end

--- A song with a Drums track, and `:nest.new Groove 2 kind=beats.pattern`
--- typed on it at bar 3: the window is inside the new subproject.
local function groove()
  local drums = paw.add_track({ name = "Drums" })
  paw.cursor.set_track(drums.id)
  paw.flush()
  api.undo_checkpoint()
  keys("3|")
  keys(":nest.new Groove 2 kind=beats.pattern<CR>")
  local nest = paw.scope.nest().id
  local row = api.track_list()[2]
  return { nest = nest, row = row, block = api.clip_list(row)[1].id }
end

test("a kind of subproject: :nest.new kind= runs its create, and znn on its block opens its view", function()
  start()
  load_kind()
  local g = groove()
  eq(paw.scope.breadcrumb(), "Song › ⧉Groove", "the window is inside the new subproject")
  eq(names(api.track_list({ nest = g.nest })), "Kit", "the tracks of create, and no empty track")
  eq(paw.nest.data(g.nest).steps, 16, "the data of create")
  eq(paw.ui.focused, "beatgrid", ":nest.new opened the kind's view")
  eq(paw.ui.message.text:find("Groove (Beat pattern) over bars 3-4", 1, true) ~= nil, true, paw.ui.message.text)

  paw.ui.focus("arrange")
  keys("zw")
  paw.cursor.set_track(g.row)
  paw.cursor.set_beat(9)
  eq(T.screen(120, 30):find("⧉B Groove", 1, true) ~= nil, true, "the block shows the kind's letter")
  eq(described():find("subproject Groove (Beat pattern: 16 steps)", 1, true) ~= nil, true, "K names the kind")
  keys("znn")
  eq(paw.ui.focused, "beatgrid", "znn opened the kind's view")

  T.expect_error("no kind of subproject `drums.loop` here: the kinds are beats.broken, beats.pattern")
  T.expect_error("Broken pattern: no kit here")
  paw.ui.focus("arrange")
  keys("zw")
  local nests, tracks = #api.nest_list(), #api.track_list({ all = true })
  keys(":nest.new kind=drums.loop<CR>")
  keys(":nest.new kind=beats.broken<CR>")
  eq(
    { #api.nest_list(), #api.track_list({ all = true }) },
    { nests, tracks },
    "an unknown kind and a create that fails leave the project as it was"
  )
end)

test("without the extension, a kind's subproject opens, plays, and the arrange view edits it", function()
  start()
  load_kind()
  groove()
  paw.ui.focus("arrange")
  keys("zw")
  local dir = T.scratch .. "/groove-song"
  keys(":w " .. dir .. "<CR>")
  paw.ext.unload("beats")
  api.project_load(dir)
  paw.flush()

  local nest = api.nest_list()[1]
  eq(api.nest_get(nest).kind, "beats.pattern", "the subproject keeps its kind")
  eq(paw.nest.data(nest).steps, 16, "and its data")
  local info = T.render({ tail = 0, bits = 16, ["end"] = 16 })
  eq(T.channel_peaks(info, 0, 3.9) < 1e-3, true, "nothing before bar 3")
  eq(T.channel_peaks(info, 4, 4.5) > 0.01, true, "its Kit plays at bar 3")

  local row = api.track_list()[2]
  paw.cursor.set_track(row)
  paw.cursor.set_beat(9)
  eq(T.screen(120, 30):find("⧉ Groove", 1, true) ~= nil, true, "the block has no letter")
  eq(
    described():find("subproject Groove (beats.pattern, which no extension here defines)", 1, true) ~= nil,
    true,
    "K names the kind that is not here"
  )
  keys("znn")
  eq(paw.scope.breadcrumb(), "Song › ⧉Groove", "znn enters it")
  eq(paw.ui.focused, "arrange", "in the arrange view")
  keys("o")
  eq(names(api.track_list({ nest = nest })), "Kit Track 2", "o adds a track in it")
end)

test("nest.enter and nest.leave come once for each enter and leave; nest.changed once for each edit inside", function()
  start()
  local row = paw.add_track({ name = "Ballad" })
  local nest = api.nest_add({ name = "Ballad", length = 16 })
  local piano = api.track_add({ name = "Piano", nest = nest })
  api.clip_add(piano, { start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  api.clip_add(row.id, { nest = nest, start = 16 })
  paw.flush()
  api.undo_checkpoint()

  -- What the events say, and how many edits ended. An edit ends at the end
  -- of its turn, which `T.until_` lets come: `T.keys` would close its undo
  -- step at once, so the keys of an edit go through `paw.keymap.feed`.
  local seen, edits = {}, 0
  for _, name in ipairs({ "nest.enter", "nest.leave", "nest.changed" }) do
    local id = paw.on(name, function(e) seen[#seen + 1] = name .. " " .. api.nest_get(e.nest).name end)
    T.after(function() paw.off(id) end)
  end
  local id = paw.on("edit.after", function() edits = edits + 1 end)
  T.after(function() paw.off(id) end)
  local function edit(key)
    local was = edits
    paw.keymap.feed(key)
    T.until_(function() return edits > was end, "the edit of " .. key .. " ends")
  end

  paw.cursor.set_track(row.id)
  paw.cursor.set_beat(17)
  keys("znn")
  paw.cursor.set_track(piano)
  paw.cursor.set_beat(0)
  edit("x")
  edit("o")
  edit(":track.remove<CR>")
  keys("zw")
  edit("o")
  keys("<C-o>")
  eq(
    table.concat(seen, ", "),
    "nest.enter Ballad, nest.changed Ballad, nest.changed Ballad, nest.changed Ballad, nest.leave Ballad, nest.enter Ballad",
    "znn, x, o and :track.remove inside, zw, o in the song, <C-o>"
  )
end)
