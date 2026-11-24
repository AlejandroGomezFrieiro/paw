-- The devices view (paw/views/devices.tl): the chain of a part as a graph,
-- with the inspector under it. Golden screens of three chains of a metal
-- mix, folded and open, at 120 and 80 columns, and as an outline at 40; the
-- keys that move the cursor and fold; and the warning on a split whose kind
-- no loaded extension defines. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, keys = T.test, T.eq, T.keys
local api = paw.api

local H = 44

--- A scratch extension that defines the split kind `drums.transient`, so
--- that a split of it can be made; `gone()` unloads it, and the split stays
--- with a kind that no loaded extension defines.
local function transient_kind()
  local dir = T.scratch .. "/device-graph/drums"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(dir .. "/init.lua", 'paw.chain.define_kind("drums.transient", { min = 2, max = 2, first = 2 })')
  T.after(function()
    if paw.ext.loaded.drums then paw.ext.unload("drums") end
  end)
  eq(paw.ext.load(dir).ok, true, "the extension of the kind loads")
  return function() paw.ext.unload("drums") end
end

--- A builder of a chain on a new part named `name`.
local function builder(name)
  local t = paw.add_part({ name = name })
  local h = paw.chain.of({ part = t.id })
  local b = {}
  --- Add a device of `kind`, with `label` as the name of its preset.
  function b.dev(kind, label)
    local d = t:add_device(kind)
    api.device_set(d.id, { meta = { preset = label } })
    return d.id
  end
  --- Put the devices of each list of `lists` in a branch of a new split of
  --- `kind`: `opts.name`, `opts.values`, `opts.names` and `opts.gains` of
  --- the branches. An empty list is an empty branch (the dry signal).
  function b.split(kind, lists, opts)
    opts = opts or {}
    local all = {}
    for _, list in ipairs(lists) do
      for _, id in ipairs(list) do
        all[#all + 1] = id
      end
    end
    local id = paw.chain.wrap(h, all, kind, { branches = #lists, name = opts.name, values = opts.values }).id
    local split = paw.chain.find(paw.chain.get(h), id).split
    for i, list in ipairs(lists) do
      local branch = split.branches[i].id
      for at, device in ipairs(list) do
        if i > 1 then paw.chain.move(h, device, { branch = branch, index = at }) end
      end
      if opts.names and opts.names[i] then paw.chain.set(h, branch, { name = opts.names[i] }) end
      if opts.gains and opts.gains[i] then paw.chain.set(h, branch, { gain = opts.gains[i] }) end
    end
    return id
  end
  --- Put the devices `ids` in a rack named `label`.
  function b.rack(label, ids) return paw.chain.wrap(h, ids, "chain", { name = label }).id end
  return t, b, h
end

--- A. The rhythm guitar bus: an EQ, a dynamic EQ, a band split, a layer, a
--- mid/side split and a rack.
local function guitar_bus()
  local t, b = builder("Guitars")
  b.dev("eq", "HP 90 · LP 9k")
  b.dev("eq", "Thump 131")
  local low, mud, fizz = b.dev("compressor", "Low comp"), b.dev("eq", "Mud 400"), b.dev("compressor", "De-ess")
  b.split("band", { { low }, { mud }, { fizz } }, {
    name = "Tame",
    values = { xover = { 150, 2500 } },
    names = { "Low", "Mid", "Fizz" },
  })
  local comp, eq, sat = b.dev("compressor", "Crush 20:1"), b.dev("eq", "Crush EQ"), b.dev("saturation", "Crush sat")
  b.split("layer", { {}, { comp, eq, sat } }, { name = "Crush", names = { "Dry", "Crush" }, gains = { 0, -12 } })
  local side_eq, side_sat = b.dev("eq", "Side HP"), b.dev("saturation", "Side sat")
  b.split("ms", { {}, { side_eq, side_sat } }, { name = "Width", names = { "Mid", "Side" } })
  b.rack("Glue", {
    b.dev("saturation", "Glue sat"),
    b.dev("compressor", "Glue comp"),
    b.dev("eq", "Vocal room"),
    b.dev("utility", "Utility"),
    b.dev("meter", "Meter"),
  })
  return t
end

--- B. The drum bus: a transient split whose kind an extension defined and
--- that has unloaded, a layer, a band split and a meter.
local function drum_bus()
  local gone = transient_kind()
  local t, b = builder("Drums")
  b.dev("eq", "Bus EQ")
  local attack, sat, body = b.dev("eq", "Attack EQ"), b.dev("saturation", "Attack sat"), b.dev("compressor", "Slow")
  b.split("drums.transient", { { attack, sat }, { body } }, { name = "Punch", names = { "Attack", "Body" } })
  local comp, eq, crush = b.dev("compressor", "Crush 20:1"), b.dev("eq", "Crush EQ"), b.dev("saturation", "Crush sat")
  b.split("layer", { {}, { comp, eq, crush } }, { name = "Crush", names = { "Dry", "Crush" }, gains = { 0, -9 } })
  b.dev("compressor", "Glue")
  local lo, hi = b.dev("limiter", "Low limit"), b.dev("limiter", "High limit")
  b.split("band", { { lo }, { hi } }, { name = "Limit", values = { xover = { 150 } }, names = { "Low", "High" } })
  b.dev("eq", "Tilt")
  b.dev("meter", "Meter")
  gone()
  return t
end

--- C. The lead vocal: a rack, three layers, a split in a layer, and sends.
local function vocal()
  local t, b = builder("Vocal")
  b.dev("eq", "HP 100")
  b.dev("compressor", "De-ess")
  b.rack("Level", { b.dev("compressor", "Peaks 8:1"), b.dev("compressor", "Level 3:1") })
  b.dev("eq", "Air +3")
  local clip, band, comp = b.dev("saturation", "Clip"), b.dev("eq", "Band-pass"), b.dev("compressor", "Scream comp")
  b.split("layer", { {}, { clip, band, comp } }, { name = "Scream", names = { "Dry", "Scream" }, gains = { 0, -14 } })
  local left, right = b.dev("delay", "12 ms"), b.dev("delay", "18 ms")
  b.split("layer", { {}, { left, right } }, { name = "Double", names = { "Dry", "Double" }, gains = { 0, -15 } })
  b.split("lr", { { left }, { right } }, { name = "Spread", names = { "L", "R" } })
  b.dev("compressor", "De-ess 2")
  local throw, duck, plate, verb_eq =
    b.dev("delay", "Dotted 8th"), b.dev("compressor", "Duck"), b.dev("reverb", "Plate"), b.dev("eq", "Verb EQ")
  b.split("layer", { {}, { throw, duck }, { plate, verb_eq } }, {
    name = "Sends",
    names = { "Dry", "Throw", "Verb" },
    gains = { 0, -6, -18 },
  })
  b.dev("limiter", "Limiter")
  b.dev("meter", "Meter")
  return t
end

--- The devices view alone on the screen, with the inspector under it, on
--- the part `t`, with the keyboard.
local function open(t)
  paw.cursor.set_part(t)
  keys(":only<CR>")
  keys(":e devices<CR>")
  paw.ui.focus("devices")
  paw.ui.message = nil
end

for _, chain in ipairs({ { "guitar", guitar_bus }, { "drums", drum_bus }, { "vocal", vocal } }) do
  local name, make = chain[1], chain[2]
  test("the devices view draws the " .. name .. " chain folded and open, at 120 and 80 columns", function()
    T.start()
    local t = make()
    open(t)
    T.expect_screen(name .. "_folded_120", 120, H)
    T.expect_screen(name .. "_folded_80", 80, H)
    keys("zR")
    T.expect_screen(name .. "_open_120", 120, H)
    T.expect_screen(name .. "_open_80", 80, H)
  end)
end

test("in a narrow window the devices view is an outline, one row for each node", function()
  T.start()
  paw.cursor.set_part(vocal())
  paw.ui.show("devices")
  paw.ui.focus("devices")
  paw.ui.message = nil
  keys("zR")
  T.expect_screen("vocal_outline", 110, H, { cols = { 71, 110 } })
end)

test("l and h go along the signal, j and k across the branches, and the path to the cursor opens", function()
  T.start()
  local t = guitar_bus()
  open(t)
  local view = paw.ui.views:get("devices")
  local function at()
    local node = view:node().node
    return node.kind == "device" and node.summary or node.name
  end
  eq(at(), "HP 90 · LP 9k", "the cursor starts on the first device")
  keys("2l")
  eq(at(), "Tame", "2l: the band split, folded")
  keys("zo")
  keys("l")
  eq(at(), "1 Low", "in an open split, l goes to its first branch")
  keys("l")
  eq(at(), "Low comp", "and then to its device")
  keys("j")
  eq(at(), "Mud 400", "j: the same place in the branch below")
  keys("k")
  eq(at(), "Low comp", "k: back up")
  keys("zc")
  eq(at(), "Tame", "zc folds the split around the cursor, and the cursor goes to it")
  keys("G")
  eq(at(), "Glue", "G: the last node, the rack, folded")
  keys("gg")
  eq(at(), "HP 90 · LP 9k", "gg: the first")
  keys("zR")
  keys("G")
  eq(at(), "Meter", "with all open, G goes into the rack")
  eq(view:path()[1].node.name, "Glue", "and the path starts at the rack")
end)

test("Enter goes to the inspector, which shows the node under the cursor", function()
  T.start()
  local t = guitar_bus()
  open(t)
  local inspector = paw.ui.views:get("inspector")
  keys("l")
  keys("<CR>")
  eq(paw.ui.focused, "inspector", "the inspector has the keys")
  local device, row = inspector:selected()
  eq(device and device:get().meta.preset, "Thump 131", "on the device under the cursor")
  eq(row.param, nil, "on its heading")
  keys("<C-w>k")
  eq(paw.ui.focused, "devices", "Ctrl-w k goes back to the graph above it")
  keys("l")
  local place = inspector:node()
  eq(place.chain_split.name, "Tame", "on a split, the inspector shows it")
end)

test("K on a split of a kind that no loaded extension defines says that it plays its first branch, and why", function()
  T.start()
  local t = drum_bus()
  open(t)
  keys("zR")
  keys("l")
  keys("K")
  local hover = T.hover_text()
  eq(
    hover:find("its first branch: no loaded extension defines the kind drums.transient", 1, true) ~= nil,
    true,
    "K says that it plays its first branch, and why: " .. hover
  )
  keys("<Esc>")
end)
