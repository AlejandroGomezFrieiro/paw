-- The grammar of the devices view (paw/views/devices_keys.tl): operators,
-- text objects, insert mode at a caret, visual mode, the Ex commands and
-- the states that change what you hear, each with the real keys. Golden
-- screens show the title and the status line of each mode. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, keys = T.test, T.eq, T.keys
local api = paw.api

--- The chain of the part `t` as text: the kinds of its devices in series,
--- a split as `kind(branch | branch)`, and `~` after a bypassed device.
local function shape(t)
  local chain = paw.chain.get({ part = t.id })
  local function dev(id)
    local d = api.device_get(id)
    return d.kind .. (d.bypass and "~" or "")
  end
  local split
  local function nodes(list)
    local out = {}
    for _, n in ipairs(list) do
      out[#out + 1] = n.split and split(n.split) or dev(n.device)
    end
    return table.concat(out, " ")
  end
  split = function(s)
    local bs = {}
    for _, b in ipairs(s.branches) do
      bs[#bs + 1] = nodes(b.nodes)
    end
    return s.kind .. "(" .. table.concat(bs, " | ") .. ")"
  end
  if not chain then
    local out = {}
    for _, id in ipairs(api.part_get(t.id).devices) do
      out[#out + 1] = dev(id)
    end
    return table.concat(out, " ")
  end
  return nodes(chain.root.branches[1].nodes)
end

--- A part named `name` with devices of the kinds `kinds` in series.
local function part_with(name, kinds)
  local t = paw.add_part({ name = name })
  for _, kind in ipairs(kinds) do
    t:add_device(kind)
  end
  return t
end

--- A part with an EQ, a layer of a dry branch and a branch with a
--- saturation and a compressor, and a limiter.
local function with_layer()
  local t = part_with("Bus", { "eq", "saturation", "compressor", "limiter" })
  local h = paw.chain.of({ part = t.id })
  local ids = api.part_get(t.id).devices
  local id = paw.chain.wrap(h, { ids[2], ids[3] }, "layer", { branches = 2 }).id
  local split = paw.chain.find(paw.chain.get(h), id).split
  paw.chain.move(h, ids[2], { branch = split.branches[2].id, index = 1 })
  paw.chain.move(h, ids[3], { branch = split.branches[2].id, index = 2 })
  return t
end

--- The devices view alone on the screen, on the part `t`, with the keys.
local function open(t)
  paw.cursor.set_part(t)
  keys(":only<CR>")
  keys(":e devices<CR>")
  paw.ui.focus("devices")
  paw.ui.message = nil
  api.ui_snapshot(100, 24)
end

local function message() return tostring(paw.ui.message and paw.ui.message.text) end

local function cursor_name() return paw.ui.views:get("devices"):node().node.name end

test("dd cuts a node and p pastes it after the cursor, each one undo step", function()
  T.start()
  local t = part_with("Lead", { "eq", "compressor", "saturation", "limiter" })
  open(t)
  keys("ldd")
  eq(shape(t), "eq saturation limiter", "dd cuts the compressor")
  eq(message(), "cut Compressor", "and says what it cut")
  keys("p")
  eq(shape(t), "eq saturation compressor limiter", "p pastes it after the cursor")
  keys("u")
  eq(shape(t), "eq saturation limiter", "one u takes back the paste")
  keys("u")
  eq(shape(t), "eq compressor saturation limiter", "one u takes back the cut")
  keys("gg2dd")
  eq(shape(t), "saturation limiter", "2dd cuts two nodes in series")
  keys("P")
  eq(shape(t), "eq compressor saturation limiter", "P pastes both before the cursor")
end)

test(">> and << move a node in the order of the signal, and out of a split at its end", function()
  T.start()
  local t = with_layer()
  open(t)
  keys(">>")
  eq(shape(t), "layer( | saturation compressor) eq limiter", ">> moves the EQ after the layer")
  keys("u")
  keys("ggzRlllll")
  eq(cursor_name(), "Compressor", "the cursor is on the last node of the branch")
  keys(">>")
  eq(shape(t), "eq layer( | saturation) compressor limiter", "at the end of a branch, >> goes out of the split")
  keys("2<lt><lt>")
  eq(shape(t), "compressor eq layer( | saturation) limiter", "2<< moves it two places earlier")
end)

test("the text objects of the graph take a branch, its nodes, a split and the chain", function()
  T.start()
  local t = with_layer()
  open(t)
  keys("zRllll")
  keys("dib")
  eq(shape(t), "eq layer( | ) limiter", "dib empties the branch")
  keys("u")
  keys("zRllll")
  keys("dab")
  eq(shape(t), "eq layer() limiter", "dab removes the branch")
  keys("u")
  keys("zRllll")
  keys("yasG")
  keys("p")
  eq(
    shape(t),
    "eq layer( | saturation compressor) limiter layer( | saturation compressor)",
    "yas then p copies the split"
  )
  keys("u")
  keys("ggdie")
  eq(shape(t), "", "die cuts the entire chain")
end)

test("gs wraps in a split of a kind letter, cs changes the kind and ds unwraps", function()
  T.start()
  local t = part_with("Gtr", { "eq", "compressor", "limiter" })
  open(t)
  keys("lgsinl")
  eq(shape(t), "eq layer(compressor | ) limiter", "gsinl wraps the node in a layer")
  keys("csb")
  eq(shape(t), "eq band(compressor | ) limiter", "csb makes it a band split")
  keys("zoll")
  eq(cursor_name(), "Compressor", "on the device in the first band")
  keys("ds")
  eq(shape(t), "eq compressor limiter", "ds keeps the branch of the cursor")
  keys("ggvlgs3b")
  eq(
    shape(t),
    "band(eq compressor |  | ) limiter",
    "in visual mode gs takes the kind, and a count before it the branches"
  )
end)

test("gc bypasses devices and mutes branches; ~ bypasses the node", function()
  T.start()
  local t = with_layer()
  open(t)
  keys("gcc")
  eq(shape(t), "eq~ layer( | saturation compressor) limiter", "gcc bypasses the node")
  keys("~")
  eq(shape(t), "eq layer( | saturation compressor) limiter", "~ lets it play again")
  keys("zRlll")
  keys("gcab")
  local branch = paw.chain.get({ part = t.id }).root.branches[1].nodes[2].split.branches[2]
  eq(branch.mute, true, "gcab mutes the branch")
end)

test("i inserts at a caret, each key one node, and all of one insert is one undo step", function()
  T.start()
  local t = part_with("Vox", { "eq", "limiter" })
  open(t)
  keys("li")
  eq(paw.keymap.mode, "i", "insert mode")
  keys("ces")
  eq(shape(t), "eq compressor eq saturation limiter", "c e s insert three devices before the limiter")
  keys("<BS>")
  eq(shape(t), "eq compressor eq limiter", "<BS> takes back the last one")
  keys("<Esc>")
  eq(message(), "inserted 2 devices", "Esc says what it inserted")
  keys("u")
  eq(shape(t), "eq limiter", "one u takes back the whole insert")
  keys("ggi3B")
  eq(shape(t), "band( |  | ) eq limiter", "3B inserts a band split with three bands")
  keys("c<Esc>")
  eq(shape(t), "band(compressor |  | ) eq limiter", "the caret went into its first band")
end)

test("o adds a branch below and starts insert mode in it; out of a split it makes a layer", function()
  T.start()
  local t = part_with("Keys", { "eq", "compressor" })
  open(t)
  keys("lo")
  eq(paw.keymap.mode, "i", "insert mode in the new branch")
  keys("r<Esc>")
  eq(shape(t), "eq layer(compressor | reverb)", "the compressor went into a layer, the reverb into branch 2")
  keys("u")
  eq(shape(t), "eq compressor", "one u")
end)

test("paw.insert.add with view = devices adds a key to the insert mode of the graph", function()
  T.start()
  local t = part_with("Pad", { "eq" })
  T.after(function()
    paw.insert.remove("C", "devices")
    paw.opt.graph_insertkeys = { "c", "e", "s", "g", "l", "d", "r", "u", "m", "R", "L", "B", "M", "S" }
  end)
  paw.insert.add("C", { view = "devices", device = "chorus", desc = "A chorus" })
  paw.opt.graph_insertkeys = { "c", "C" }
  open(t)
  keys("iCe<Esc>")
  eq(shape(t), "chorus eq", "C inserts a chorus, and e is no insert key any more")
end)

test("v, V and Ctrl-v select nodes, branches and a block; an operator acts on all of it", function()
  T.start()
  local t = part_with("Drums", { "eq", "compressor", "saturation", "limiter" })
  open(t)
  keys("vld")
  eq(shape(t), "saturation limiter", "vld cuts two nodes")
  keys("u")
  local h = paw.chain.of({ part = t.id })
  local ids = api.part_get(t.id).devices
  paw.chain.wrap(h, { ids[2], ids[3] }, "layer", { branches = 2 })
  paw.chain.move(h, ids[3], { branch = paw.chain.get(h).root.branches[1].nodes[2].split.branches[2].id, index = 1 })
  keys("zRggllljk")
  eq(cursor_name(), "Compressor", "on the device of the first band")
  keys("<C-v>jj")
  keys("gc")
  eq(shape(t), "eq layer(compressor~ | saturation~) limiter", "a block bypasses the device of each branch")
  keys("jVd")
  eq(shape(t), "eq layer(compressor~) limiter", "V takes the whole branch")
end)

test("the value keys change the wet mix of a device and the gain of a branch", function()
  T.start()
  local t = with_layer()
  open(t)
  keys("3-")
  eq(api.device_get(api.part_get(t.id).devices[1]).params.fx_wet, 85, "3- lowers the wet mix 15 %")
  keys("]")
  eq(api.device_get(api.part_get(t.id).devices[1]).params.fx_gain, 1, "] raises the output gain 1 dB")
  keys("zRllj+")
  local branch = paw.chain.get({ part = t.id }).root.branches[1].nodes[2].split.branches[2]
  eq(branch.gain, 1, "+ on a branch raises its gain 1 dB")
end)

test("\\s solos a branch alone, \\b bypasses the chain and brings each device back, \\a flips variants", function()
  T.start()
  local t = with_layer()
  open(t)
  keys("zRlll")
  keys("\\s")
  local split = paw.chain.get({ part = t.id }).root.branches[1].nodes[2].split
  eq({ split.branches[1].solo or false, split.branches[2].solo }, { false, true }, "the branch plays alone")
  keys("\\s")
  split = paw.chain.get({ part = t.id }).root.branches[1].nodes[2].split
  eq(split.branches[2].solo or false, false, "again: no solo")
  keys("gggcc")
  keys("\\b")
  eq(shape(t), "eq~ layer( | saturation~ compressor~) limiter~", "\\b bypasses every device")
  keys("\\b")
  eq(shape(t), "eq~ layer( | saturation compressor) limiter", "again: each device as it was")
  keys(":ab.store<CR>")
  keys("~")
  keys("\\a")
  eq(shape(t), "eq~ layer( | saturation compressor) limiter", "\\a plays the stored variant")
  T.expect_screen("variant_b", 100, 24, { rows = { 1, 2 } })
  keys("\\a")
  eq(shape(t), "eq layer( | saturation compressor) limiter", "\\a again: the first")
end)

test("the Ex commands of the graph wrap, unwrap and add branches", function()
  T.start()
  local t = part_with("Bass", { "eq", "compressor" })
  open(t)
  keys(":wrap band 120 2k<CR>")
  eq(shape(t), "band(eq |  | ) compressor", ":wrap band with two crossovers makes three bands")
  local split = paw.chain.get({ part = t.id }).root.branches[1].nodes[1].split
  eq(split.values.xover, { 120, 2000 }, "at 120 Hz and 2 kHz")
  keys(":xover 100 3k<CR>")
  split = paw.chain.get({ part = t.id }).root.branches[1].nodes[1].split
  eq(split.values.xover, { 100, 3000 }, ":xover sets them")
  keys(":branch add Air<CR>")
  eq(shape(t), "band(eq |  |  | ) compressor", ":branch add adds a branch")
  keys(":unwrap all<CR>")
  eq(shape(t), "eq compressor", ":unwrap all puts the branches in series")
end)

-- The title and the status line show each mode.
test("each mode shows in the title and the status line of the devices view", function()
  T.start()
  local t = with_layer()
  open(t)
  T.expect_screen("mode_normal", 100, 24)
  keys("li")
  T.expect_screen("mode_insert", 100, 24)
  keys("<Esc>vl")
  T.expect_screen("mode_visual", 100, 24)
  keys("<Esc>zRllV")
  T.expect_screen("mode_visual_line", 100, 24)
  keys("<Esc>d")
  T.expect_screen("mode_pending", 100, 24, { rows = { 1, 2 } })
  keys("<Esc>")
end)
