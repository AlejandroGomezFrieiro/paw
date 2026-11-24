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

--- Load the code `code` as the extension `name`, and unload it when the
--- test ends.
local function load_ext(name, code)
  local dir = T.scratch .. "/heads/" .. name
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(dir .. "/manifest.lua", 'return { version = "1.0.0" }')
  T.write_file(dir .. "/init.lua", code)
  local entry = paw.ext.load(dir)
  eq(entry.ok, true, "the extension loads: " .. tostring(entry.error))
  T.after(function()
    if paw.ext.loaded[name] then paw.ext.unload(name) end
  end)
end

-- A kind of part whose head wishes for the rows of the test's state, has
-- a key `\x` that writes in the state, and a line of text. The test gives
-- the state in `package.loaded.heads_test`.
local KIND_HEAD = [[
local heads_test = package.loaded.heads_test
paw.heads.define("testhead", {
  title = "Test head",
  rows = function() return heads_test.rows end,
  stamp = function() return tostring(heads_test.rows) end,
  render = function(ctx)
    ctx:line(0, { "badge", "name" }, { "chips" })
    ctx:text(1, 1, ctx.width - 2, "a test head", "PartInfo")
  end,
  keys = {
    { lhs = "x", run = function(s) heads_test.said[#heads_test.said + 1] = paw.api.part_get(s.part).name end, desc = "Name the part" },
  },
  describe = function() return { "a test head" } end,
})
paw.part_kinds.define("testkind", { title = "Test part", letter = "T", head = "testhead" })
]]

--- The state of the extension of KIND_HEAD, given to it.
local function head_state(rows)
  local state = { rows = rows, said = {} }
  package.loaded.heads_test = state
  T.after(function() package.loaded.heads_test = nil end)
  return state
end

--- Parts `Plain`, `Tested` (of the kind of KIND_HEAD) and `Last`, with
--- the arrange view alone and the cursor on `Plain`. Gives them and the
--- state of the extension.
local function kind_song()
  fresh()
  paw.cmd("view.only")
  paw.ui.views:get("arrange").scroll = 0
  paw.opt.head_limit = 0
  local state = head_state(3)
  load_ext("headtest", KIND_HEAD)
  local plain = paw.add_part({ name = "Plain" })
  local tested = paw.part_kinds.add("testkind", { name = "Tested" })
  local last = paw.add_part({ name = "Last" })
  paw.cursor.set_part(plain)
  paw.flush()
  T.until_meters_at_rest()
  return plain, tested, last, state
end

test("a head of a kind draws its row, and without its extension the row has the default head", function()
  kind_song()
  paw.opt.part_height = 3
  expect_screen("kind_head", 100, 20, { rows = { 2, 10 }, cols = { 1, 25 } })
  T.keys("<Esc>")
  paw.ext.unload("headtest")
  paw.flush()
  eq(#paw.api.part_list(), 3, "the part stays")
  expect_screen("kind_head_unloaded", 100, 20, { rows = { 2, 10 }, cols = { 1, 25 } })
end)

test("a head that fails gives one message, and the row shows the default head", function()
  fresh()
  paw.cmd("view.only")
  paw.opt.head_limit = 0
  load_ext(
    "headbroken",
    [[
paw.heads.define("broken", { render = function() error("boom") end })
paw.part_kinds.define("brokenkind", { title = "Broken part", head = "broken" })
]]
  )
  local first = paw.add_part({ name = "First" })
  paw.part_kinds.add("brokenkind", { name = "Broken" })
  T.keys("<Esc><Esc>")
  paw.cursor.set_part(first)
  T.keys("j")
  T.screen(100, 20)
  T.screen(100, 20)
  local said = 0
  for _, m in ipairs(paw.ui.messages) do
    if m.text:find("the head broken failed", 1, true) then
      said = said + 1
      eq(m.text:find("boom; paw shows the default head", 1, true) ~= nil, true, "the error in one line: " .. m.text)
      eq(m.text:find("traceback", 1, true), nil, "no stack trace")
    end
  end
  eq(said, 1, "one message")
  eq(T.screen(100, 20):find("Broken", 1, true) ~= nil, true, "the default head names the part")
  T.keys("K")
  eq(T.hover_text():find("head    broken (out: ", 1, true) ~= nil, true, "K says the head is out: " .. T.hover_text())
end)

test("a switch that is on and that the head does not show is lit by paw, and K says it", function()
  fresh()
  paw.cmd("view.only")
  paw.opt.head_limit = 0
  paw.opt.part_height = 2
  load_ext(
    "headplain",
    [[
paw.heads.define("plain", { render = function(ctx) ctx:line(0, { "name" }, {}) end })
paw.part_kinds.define("plainkind", { title = "Plain part", head = "plain" })
]]
  )
  local part = paw.part_kinds.add("plainkind", { name = "Quiet" })
  T.keys("<Esc><Esc>")
  paw.cursor.set_part(part)
  T.until_meters_at_rest()
  T.keys("M")
  eq(part:get().mute, true, "M mutes the part")
  expect_screen("lit_flag", 100, 20, { rows = { 2, 2 }, cols = { 1, 25 } })
  T.keys("K")
  eq(T.hover_text():find("muted", 1, true) ~= nil, true, "K says muted: " .. T.hover_text())
end)

test("a key of a head works on its rows only, and a head cannot take a key of the arrange view", function()
  local plain, _, last, state = kind_song()
  T.keys("<Esc><Esc>")
  paw.cursor.set_part(plain)
  T.keys("j\\x")
  eq(table.concat(state.said, ","), "Tested", "\\x on the head's row")
  T.keys("<Esc>j\\x<Esc>")
  eq(paw.cursor.part_id(), last.id, "the cursor went on")
  eq(table.concat(state.said, ","), "Tested", "and \\x does nothing on a row of the default head")
  T.fails(
    function()
      paw.heads.define("clash", { render = function() end, keys = { { lhs = "fi", run = "messages" } } })
    end,
    "the head clash cannot take .*fi: the arrange view uses it %(fades%)",
    "the clash is refused with who uses the key"
  )
  eq(paw.heads.heads:get("clash"), nil, "and the head is not defined")
end)

--- The first line and the height of each part's row, by the part's id.
local function rows_of()
  local out = {}
  for _, row in ipairs(paw.ui.views:get("arrange").geometry.layout.rows) do
    if row.kind == "part" then out[row.id] = { row.y, row.h } end
  end
  return out
end

test("a head that wishes for 3 rows is one step of j, and a wish below the cursor does not move it", function()
  fresh()
  paw.cmd("view.only")
  paw.ui.views:get("arrange").scroll = 0
  paw.opt.head_limit = 0
  local state = head_state(3)
  load_ext("headtest", KIND_HEAD)
  local parts = {}
  for i = 1, 10 do
    parts[i] = i == 5 and paw.part_kinds.add("testkind", { name = "P5" }) or paw.add_part({ name = "P" .. i })
  end
  T.keys("<Esc><Esc>")
  paw.cursor.set_part(parts[4])
  T.screen(100, 30)
  local rows = rows_of()
  eq(rows[parts[4].id][2], 2, "the parts are two rows each")
  eq(rows[parts[5].id][2], 3, "the head's wish gives its row three")
  T.keys("j")
  eq(paw.cursor.part_id(), parts[5].id, "j goes onto the tall row")
  T.keys("j")
  eq(paw.cursor.part_id(), parts[6].id, "and one more j goes past it")
  T.keys("kk")
  eq(paw.cursor.part_id(), parts[4].id, "k comes back in two steps")
  T.screen(100, 30)
  local line = rows_of()[parts[4].id][1]
  state.rows = 5
  T.screen(100, 30)
  rows = rows_of()
  eq(rows[parts[5].id][2], 5, "the new wish gives five rows")
  eq(rows[parts[4].id][1], line, "the cursor's row stays on its line")
end)

test("after j only the two heads that the cursor left and reached draw again", function()
  three_parts()
  T.keys("<Esc><Esc>")
  paw.cursor.set_part(paw.api.part_list()[1])
  T.screen(100, 20)
  T.screen(100, 20)
  local before = paw.heads.draws
  T.keys("j")
  T.screen(100, 20)
  eq(paw.heads.draws - before, 2, "two heads drew again")
end)

test("a head shows a picture in half blocks where the terminal shows no images", function()
  fresh()
  paw.cmd("view.only")
  paw.opt.head_limit = 0
  paw.opt.graphics = false
  paw.opt.part_height = 3
  -- A picture of 4 by 6 pixels: red on top, blue under it.
  local red, blue = string.char(220, 40, 40, 255), string.char(40, 40, 220, 255)
  package.loaded.heads_picture = paw.canvas.image(red:rep(12) .. blue:rep(12), 4, 6, "rgba")
  T.after(function() package.loaded.heads_picture = nil end)
  load_ext(
    "headpicture",
    [[
paw.heads.define("picture", {
  render = function(ctx)
    ctx:picture(0, 0, 4, ctx.height, package.loaded.heads_picture)
    local body = ctx:sub(5, 0, ctx.width - 5, ctx.height)
    body:line(0, { "name" }, {})
  end,
})
paw.part_kinds.define("picturekind", { title = "Picture part", head = "picture" })
]]
  )
  paw.part_kinds.add("picturekind", { name = "Face" })
  paw.flush()
  T.until_meters_at_rest()
  expect_screen("picture", 100, 20, { rows = { 2, 4 }, cols = { 1, 25 } })
end)
