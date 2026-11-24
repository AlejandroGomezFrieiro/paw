-- The extension API: manifests and versions, what an extension owns and
-- taking it away again. Loaded by tests/suite.lua with its helpers.
local T = ...
local advance = T.advance
local test, eq = T.test, T.eq
local api = paw.api

local function write(path, text)
  os.execute("mkdir -p '" .. path:match("^(.*)/") .. "'")
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local function dir(name) return T.scratch .. "/extapi/" .. name end

local function names(list)
  local out = {}
  for _, item in ipairs(list) do
    out[#out + 1] = item
  end
  return table.concat(out, " ")
end

local function provided(name, kind)
  for _, group in ipairs(paw.ext.provides(name)) do
    if group.kind == kind then return names(group.items) end
  end
  return ""
end

-- The errors a test means to cause are read, as `:messages` reads them,
-- so that the key line of the tests after it does not point at them.
local function read_errors()
  paw.commands.exec("messages")
  paw.ui.close()
end

test("the API has a version, and requirements are checked against it", function()
  T.after(read_errors)
  eq(api.version, "1.0.0", "the version")
  eq(paw.ext.satisfies("1.2.3", ">=1.2"), true, ">=")
  eq(paw.ext.satisfies("1.2.3", "^1.0"), true, "^ keeps the first number")
  eq(paw.ext.satisfies("2.0.0", "^1.0"), false, "and refuses another")
  eq(paw.ext.satisfies("1.3.0", "~1.2"), false, "~ keeps the first two")
  eq(paw.ext.satisfies("1.2.9", "~1.2"), true, "~ within")
  eq(paw.ext.satisfies("1.2.3", ">=1.0, <1.2"), false, "a range")
  eq(paw.ext.satisfies("0.9", "*"), true, "any")
  eq(paw.ext.satisfies("1.0.0", "1.0"), true, "a bare version is ^")
  write(dir("future") .. "/manifest.lua", 'return { version = "1.0.0", requires = { paw = ">=9.0" } }')
  write(dir("future") .. "/init.lua", "paw.command('future.hi', function() end)")
  local entry = paw.ext.load(dir("future"))
  eq(entry.ok, false, "an extension for a later API does not load")
  eq(
    entry.error:find("needs the paw API >=9.0, and this is 1.0.0", 1, true) ~= nil,
    true,
    "and says why: " .. tostring(entry.error)
  )
  eq(paw.commands.get("future.hi"), nil, "nothing of it ran")
  paw.ext.unload("future")
end)

test("an extension that needs what the build lacks does not load, and :extensions says why", function()
  T.start()
  local build = api.build()
  eq(build.vm, "luajit", "this build runs LuaJIT")
  eq(names(build.features), "ffi processes network native", "and has every feature")
  -- A build of the web, as the pod has it: no ffi and no native parts.
  local real = api.build
  api.build = function() return { vm = "lua52", features = { "processes", "network" } } end
  T.after(function()
    api.build = real
    paw.ext.unload("wanting")
    paw.ext.unload("modest")
    paw.ext.unload("loose")
    read_errors()
  end)
  write(dir("wanting") .. "/manifest.lua", 'return { needs = { "ffi", "processes", "native" } }')
  write(dir("wanting") .. "/init.lua", "paw.command('wanting.hi', function() end)")
  write(dir("modest") .. "/manifest.lua", 'return { needs = { "processes" } }')
  write(dir("modest") .. "/init.lua", "")
  local wanting = paw.ext.load(dir("wanting"))
  eq(wanting.ok, false, "it does not load")
  eq(wanting.error, "needs ffi and native, which this build of paw does not have", "and says what is missing")
  eq(paw.commands.get("wanting.hi"), nil, "nothing of it ran")
  eq(paw.ext.load(dir("modest")).ok, true, "an extension whose needs the build has loads")
  write(dir("loose") .. "/manifest.lua", 'return { needs = "ffi" }')
  write(dir("loose") .. "/init.lua", "")
  eq(
    paw.ext.load(dir("loose")).error,
    'manifest.lua: needs is a list of names, such as { "processes" }',
    "a needs that is no list is said"
  )
  T.keys(":extensions<CR>")
  eq(T.screen():find("wanting%s+FAILED: needs ffi and native") ~= nil, true, ":extensions says why")
  paw.ui.close()
  local said
  for _, item in ipairs(paw.health.run("extensions").items) do
    if item.text:find("wanting: needs ffi and native", 1, true) then said = item end
  end
  eq(said and said.advice[1], "a build of paw with these features loads it (`paw.api.build()`)", "so does checkhealth")
end)

test("an extension's requirements are loaded before it, and their versions checked", function()
  T.after(read_errors)
  write(
    dir("reqs/base") .. "/manifest.lua",
    'return { version = "1.4.0", description = "the base", provides = { "basics" } }'
  )
  write(dir("reqs/base") .. "/init.lua", "paw.command('base.hi', function() return 'base' end)")
  write(dir("reqs/top") .. "/manifest.lua", 'return { version = "0.2.0", requires = { paw = "^1", base = ">=1.2" } }')
  write(
    dir("reqs/top") .. "/init.lua",
    "assert(paw.ext.loaded.base, 'base first') paw.command('top.hi', function() return paw.cmd('base.hi') end)"
  )
  write(dir("reqs/old") .. "/manifest.lua", 'return { requires = { base = ">=2" } }')
  write(dir("reqs/old") .. "/init.lua", "")
  write(dir("reqs/needy") .. "/manifest.lua", 'return { requires = { basics = "*", nowhere = "*" } }')
  write(dir("reqs/needy") .. "/init.lua", "")
  local top = paw.ext.load(dir("reqs/top"))
  eq(top.ok, true, "loads: " .. tostring(top.error))
  eq(paw.ext.loaded.base.version, "1.4.0", "with what it requires, loaded from beside it")
  eq(paw.cmd("top.hi"), "base", "which it can use")
  local old = paw.ext.load(dir("reqs/old"))
  eq(old.ok, false, "a version too old is refused")
  eq(old.error, "needs base >=2, and this is 1.4.0", "and says so")
  local needy = paw.ext.load(dir("reqs/needy"))
  eq(
    needy.error,
    "needs the extension nowhere, which is not to be found: put it beside needy, or in "
      .. api.env().config_dir
      .. "/extensions",
    "a name provided counts; a missing one does not"
  )
  local ok, why = paw.ext.unload("base")
  eq(ok, nil, "an extension another requires stays")
  eq(why, "top requires base: unload it first", "and says which")
  for _, name in ipairs({ "needy", "old", "top", "base" }) do
    eq(paw.ext.unload(name), true, "unload " .. name)
  end
  eq(paw.commands.get("base.hi"), nil, "gone with it")
end)

test("an optional extension of the same folder loads first, and one that is not there is no error", function()
  local root = dir("optional")
  -- `aa` comes first in the folder, and wants `zz` first.
  write(root .. "/aa/manifest.lua", 'return { optional = { zz = "*", gone = "*" } }')
  write(root .. "/aa/init.lua", "_G.optional_order = (_G.optional_order or '') .. 'aa'")
  write(root .. "/zz/manifest.lua", "return {}")
  write(root .. "/zz/init.lua", "_G.optional_order = (_G.optional_order or '') .. 'zz'")
  T.after(function()
    _G.optional_order = nil
    paw.ext.unload("aa")
    paw.ext.unload("zz")
  end)
  paw.ext.load_dir(root)
  eq(_G.optional_order, "zzaa", "zz first")
  eq(paw.ext.loaded.aa.ok, true, "and aa loads without gone")
  eq(paw.ext.unload("zz"), true, "an optional one unloads while the other stays")
end)

test("what an extension registers is its own, and unloading it takes all of it away", function()
  T.fresh()
  local root = dir("owner")
  write(root .. "/manifest.lua", 'return { version = "0.3.0", description = "owns things" }')
  write(root .. "/lua/owner/lib.lua", "return { word = 'lib' }")
  write(
    root .. "/init.lua",
    [[
    local lib = require("owner.lib")
    paw.command("owner.go", function() return lib.word end, { desc = "Go" })
    -- One of the core's own, replaced: unloading puts the core's back.
    paw.command("info", function() return "owner's info" end, { desc = "Taken over" })
    paw.keymap.set("<leader>Zo", "owner.go", { desc = "Owner" })
    paw.keymap.group("<leader>Z", "owner things")
    paw.ui.view("ownerview", { render = function(_, buf) buf:text(0, 0, "owned") end })
    paw.buftype("ownerbuf", { create = function() return {} end, render = function() end })
    paw.textbuf.kind("owned", { pattern = "^paw://owned$", read = function() return {} end, format = function() return {} end })
    paw.track_kinds.define("ownedkind", { title = "Owned track" })
    paw.pick.sources:put("owned", { items = function() return {} end })
    paw.query.field("track", "ownedness", function() return 1 end)
    paw.statusline.component("owned", function() return "O" end)
    paw.grep.source("owned", function(add) end)
    paw.ex.field("owned", { level = "note", type = "number", get = function() return 1 end })
    paw.commands.completers:put("owned", function() return {} end)
    paw.curves.provide("owned", function() end)
    paw.ui.layer("arrange", "header", "owned", 99, function() end)
    paw.frontend.bands:put("owned", function() return {} end)
    paw.ui.views:get("pianoroll").layer("owned", 99, function() end)
    paw.on("track.added", function() _G.owner_heard = (_G.owner_heard or 0) + 1 end)
    paw.option.define("owned_option", 7)
  ]]
  )
  local core_info = paw.commands.get("info")
  local entry = paw.ext.load(root)
  eq(entry.ok, true, "loads: " .. tostring(entry.error))
  eq(entry.version, "0.3.0", "the manifest's version")
  eq(provided("owner", "commands"), ":info :owner.go", "its commands")
  eq(provided("owner", "keys"), "<leader>Zo (n)", "its keys")
  eq(provided("owner", "views"), "ownerview", "its view")
  eq(provided("owner", "buftypes"), "ownerbuf", "its buffer type")
  eq(provided("owner", "track_kinds"), "ownedkind", "its kind of track")
  eq(provided("owner", "hooks"), "track.added", "its hook")
  eq(provided("owner", "options"), "owned_option", "its option")
  for _, kind in ipairs({
    "key_groups",
    "textbuf_kinds",
    "pickers",
    "query_fields",
    "statusline",
    "grep",
    "ex_fields",
    "completers",
    "curves",
    "layers",
    "bands",
    "roll",
  }) do
    eq(provided("owner", kind) ~= "", true, "it owns its " .. kind)
  end
  eq(paw.commands.get("owner.go").ext, "owner", "a command says whose it is")
  paw.cmd("extensions")
  local shown = {}
  for _, line in ipairs(paw.ui.views:get("pager").lines) do
    shown[#shown + 1] = line.text
  end
  paw.ui.close()
  shown = table.concat(shown, "\n")
  eq(shown:find("owner 0.3.0", 1, true) ~= nil, true, ":extensions shows the name and version")
  eq(shown:find("owns things", 1, true) ~= nil, true, "the description")
  eq(shown:find(":owner.go", 1, true) ~= nil, true, "and what it registered")

  paw.add_track({ name = "heard" })
  paw.flush()
  eq(_G.owner_heard, 1, "its hook runs while it is loaded")

  eq(paw.ext.unload("owner"), true, "unloads")
  eq(paw.ext.loaded.owner, nil, "is no longer loaded")
  eq(paw.commands.get("owner.go"), nil, "its command is gone")
  eq(paw.commands.get("info"), core_info, "the core's command it replaced is back")
  eq(
    paw.keymap.groups().global and paw.keymap.groups().global[table.concat(paw.keymap.parse("<leader>Z"))],
    nil,
    "its key group is gone"
  )
  for _, map in ipairs(paw.keymap.every()) do
    if map.lhs == "<leader>Zo" then error("its key is still mapped") end
  end
  eq(paw.ui.views:get("ownerview"), nil, "its view")
  eq(paw.ui.views:get("ownerbuf"), nil, "its buffer type's view")
  eq(paw.layout.types:get("ownerbuf"), nil, "its buffer type")
  eq(paw.textbuf.kinds:get("owned"), nil, "its text buffer kind")
  eq(paw.track_kinds.kinds:get("ownedkind"), nil, "its kind of track")
  for _, item in ipairs(paw.frontend.menus.timeline) do
    if item.track_kind == "ownedkind" then error("its kind is still in the menu") end
  end
  eq(paw.pick.sources:get("owned"), nil, "its picker source")
  eq(paw.query.fields:get("track ownedness"), nil, "its query field")
  eq(paw.statusline.components:get("owned"), nil, "its status line component")
  eq(paw.grep.sources:get("owned"), nil, "its grep source")
  for _, name in ipairs(paw.grep.order) do
    eq(name ~= "owned", true, "and its place in the order")
  end
  eq(paw.ex.fields:get("owned"), nil, "its field")
  eq(paw.commands.completers:get("owned"), nil, "its completer")
  eq(paw.curves.providers:get("owned"), nil, "its curve provider")
  for _, layer in ipairs(paw.ui.layers.arrange.header or {}) do
    eq(layer.name ~= "owned", true, "its layer")
  end
  eq(paw.frontend.bands:get("owned"), nil, "its band under the ruler")
  for _, layer in ipairs(paw.ui.views:get("pianoroll").layers) do
    eq(layer.name ~= "owned", true, "its layer of the piano roll")
  end
  eq(package.loaded["owner.lib"], nil, "its modules are forgotten")
  paw.add_track({ name = "unheard" })
  paw.flush()
  eq(_G.owner_heard, 1, "its hook no longer runs")

  -- And it can be loaded again, afresh.
  eq(paw.ext.load(root).ok, true, "loads again")
  eq(paw.cmd("owner.go"), "lib", "with its modules")
  paw.ext.unload("owner")
  _G.owner_heard = nil
end)

test(":bnext goes past the view of an extension that was unloaded", function()
  T.start()
  local root = dir("shown")
  write(root .. "/init.lua", 'paw.ui.view("shownview", { render = function(_, buf) buf:text(0, 0, "shown") end })')
  eq(paw.ext.load(root).ok, true, "loads")
  paw.cmd("buffer", { "shownview" })
  eq(paw.ui.focused, "shownview", "its view is shown")
  paw.cmd("buffer", { "arrange" })
  paw.ext.unload("shown")
  for _ = 1, #paw.layout.buffers_list() + 1 do
    paw.keymap.feed(":bnext<CR>")
    local view = paw.layout.current().view
    eq(paw.ui.views:get(view) ~= nil, true, ":bnext shows a view that is there, not " .. view)
  end
end)

test("an extension's language server in this process starts again when the extension loads again", function()
  T.start()
  local root = dir("served")
  write(
    root .. "/init.lua",
    [[
    local server = {
      initialize = function()
        _G.served_starts = (_G.served_starts or 0) + 1
        return { serverInfo = { name = "served" }, capabilities = {} }
      end,
    }
    paw.lsp.config("served", { server = server })
    paw.lsp.enable("served")
  ]]
  )
  T.after(function()
    paw.ext.unload("served")
    _G.served_starts = nil
  end)
  eq(paw.ext.load(root).ok, true, "loads")
  T.until_(function() return _G.served_starts == 1 end, "the server to start")
  paw.ext.unload("served")
  eq(paw.lsp.configs:get("served"), nil, "unloading takes its server away")
  eq(paw.ext.load(root).ok, true, "loads again")
  T.until_(function() return _G.served_starts == 2 end, "the server of the new load to start")
end)

test("an extension's pencil keys and insert keys work, show in the key bar by order, and go when it unloads", function()
  T.fresh()
  T.after(function()
    paw.keymap.feed("<Esc><Esc>")
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
    paw.ext.unload("pens")
    _G.pens_ran = nil
  end)
  local root = dir("pens")
  write(root .. "/manifest.lua", 'return { version = "0.1.0", description = "pencil keys" }')
  write(
    root .. "/init.lua",
    [[
    local function ran(what) _G.pens_ran = (_G.pens_ran or "") .. what end
    paw.roll_draw.key("gs", { desc = "Staccato: half as long", run = function() ran("s") end })
    paw.roll_draw.key("gz", { desc = "Zig", order = 5, run = function() ran("z") end })
    paw.insert.add("Q", { desc = "A cue", order = 15, insert = function() ran("q") return nil, "no cue" end })
  ]]
  )
  eq(table.concat(paw.opt.insertkeys, ","), "m,a,r,',f", "the built-in insert keys")
  eq(paw.ext.load(root).ok, true, "loads")
  eq(table.concat(paw.opt.insertkeys, ","), "m,Q,a,r,',f", "its insert key goes in by its order")
  eq(provided("pens", "pencil"), "gs (pencil) gz (pencil)", "it owns its pencil keys")
  eq(provided("pens", "insert"), "Q (insert mode)", "and its insert key")

  local track = paw.add_track({ name = "Lead" })
  local clip = track:add_clip({ name = "tune", start = 0, length = 4 })
  paw.ui.focus("arrange")
  T.keys("iQ<Esc>")
  paw.ui.show("pianoroll")
  paw.ui.views:get("pianoroll"):edit(clip)
  T.keys("i")
  local line = {}
  for _, entry in ipairs(paw.ui.keybar.entries()) do
    line[#line + 1] = entry[1] .. " " .. entry[2]
  end
  line = table.concat(line, ", ")
  eq(
    line:find("Space rest, gz zig, gs staccato, Esc write", 1, true) ~= nil,
    true,
    "the key bar lists its keys by order, then by key: " .. line
  )
  T.keys("gsgz<Esc>")
  eq(_G.pens_ran, "qsz", "its keys work")

  eq(paw.ext.unload("pens"), true, "unloads")
  eq(paw.roll_draw.keys:get("gs"), nil, "its pencil key is gone from paw.roll_draw.keys")
  eq(paw.roll_draw.keys:get("gz"), nil, "both of them")
  eq(paw.insert.get("Q"), nil, "its insert key is gone")
  eq(table.concat(paw.opt.insertkeys, ","), "m,a,r,',f", "and out of paw.opt.insertkeys")
  T.keys("igsgz<Esc>")
  paw.ui.focus("arrange")
  T.keys("iQ<Esc>")
  eq(_G.pens_ran, "qsz", "its keys no longer work")
end)

test(":ext.unload takes a bundled extension away and :ext.load brings it back", function()
  T.fresh()
  local had = paw.ext.loaded.musicops ~= nil
  if not had then paw.cmd("ext.load", { "musicops" }) end
  eq(paw.ext.loaded.musicops.ok, true, "loaded")
  eq(paw.ext.loaded.musicops.version, "0.1.0", "with its manifest")
  local commands = provided("musicops", "commands")
  eq(commands ~= "", true, "it owns commands")
  local one = commands:match(":(%S+)")
  paw.commands.exec("ext.unload musicops")
  eq(paw.ext.loaded.musicops, nil, "unloaded")
  eq(paw.commands.get(one), nil, "its command " .. one .. " is gone")
  paw.commands.exec("ext.load musicops")
  eq(paw.commands.get(one) ~= nil, true, "and back")
  if not had then paw.ext.unload("musicops") end
end)

test("every bundled extension has a manifest that names it and asks for this API", function()
  local page = T.read_file("docs/reference/extensions.md")
  for _, name in ipairs(paw.ext.bundled()) do
    local m, err = paw.ext.manifest(paw.ext.bundled_dir() .. "/" .. name, name)
    eq(err, nil, name .. "'s manifest reads")
    eq(type(m.version), "string", name .. " has a version")
    eq(type(m.description), "string", name .. " has a description")
    eq(paw.ext.satisfies(api.version, m.requires and m.requires.paw), true, name .. " asks for this API")
    eq(type(m.needs), "table", name .. " says what it needs of the build")
    -- The last column of its row in the table of bundled extensions.
    local row = page:match("\n| %[`" .. name .. "`%][^\n]*") or ""
    local listed = {}
    for _, need in ipairs(m.needs) do
      listed[#listed + 1] = "`" .. need .. "`"
    end
    local cell = #listed > 0 and table.concat(listed, ", ") or "none"
    eq(row:sub(-#cell - 3), " " .. cell .. " |", name .. "'s needs in docs/reference/extensions.md")
  end
end)

test("a role an extension defines is its own, and goes with it", function()
  T.after(read_errors)
  write(
    dir("roley") .. "/init.lua",
    [[
paw.ui.role("roley.dot", { cells = function(buf) buf:text(0, 0, "o", "Normal") end })
]]
  )
  paw.ext.load(dir("roley"))
  eq(paw.roles.registry:get("roley.dot") ~= nil, true, "the role is defined")
  eq(provided("roley", "roles"), "roley.dot", "and listed as the extension's")
  local before = paw.roles.version
  paw.ext.unload("roley")
  eq(paw.roles.registry:get("roley.dot"), nil, "unloading takes it away")
  eq(paw.roles.version > before, true, "and frontends are told the roles changed")
end)

local function offered(kind)
  for _, info in ipairs(paw.device_types()) do
    if info.kind == kind then return true end
  end
  return false
end

test(
  "unloading takes away what an extension registered later, its timers, options, and devices written in Lua",
  function()
    T.fresh()
    T.after(read_errors)
    local root = dir("later")
    write(
      root .. "/devices/laterfx.lua",
      [[
local dsp = require("paw.dsp")
local dev = dsp.device { name = "Later fx", params = { { key = "gain", name = "Gain", min = -60, max = 12, default = 0 } } }
function dev.process(b) end
return dev
]]
    )
    write(
      root .. "/init.lua",
      [[
paw.option.define("later_size", 3, { min = 1, max = 9, integer = true })
_G.later_ticks = 0
paw.every(5, function() _G.later_ticks = _G.later_ticks + 1 end)
paw.command("later.arm", function()
  paw.command("later.made", function() return "made" end, { desc = "Made later" })
  paw.keymap.set("<leader>Zl", "later.made", { desc = "Later" })
  paw.on("later.ping", function() _G.later_heard = true end)
  _G.later_timer = paw.defer(function() _G.later_fired = true end, 60000)
end)
]]
    )
    local entry = paw.ext.load(root)
    eq(entry.ok, true, "loads: " .. tostring(entry.error))
    eq(offered("lua:laterfx"), true, "its device is offered")
    eq(provided("later", "device_dirs"), root .. "/devices", "and listed as its own")
    paw.opt.later_size = 5
    advance(60)
    eq(_G.later_ticks > 0, true, "its timer runs")
    paw.cmd("later.arm")
    eq(paw.commands.get("later.made") ~= nil, true, "a command made from its own command")
    eq(provided("later", "commands"), ":later.arm :later.made", "is its own too")
    eq(provided("later", "hooks"), "later.ping", "and the hook")
    eq(provided("later", "timers"), "timer timer", "and both timers")

    -- A device of its own on a track keeps it loaded, unless forced.
    local t = paw.add_track({ name = "Uses it" })
    local d = t:add_device("lua:laterfx")
    paw.flush()
    local ok, why = paw.ext.unload("later")
    eq(ok, nil, "refused while a track holds its device")
    eq(why, "lua:laterfx on Uses it: remove it first, or `:ext.unload! later` leaves it there", "and says where")
    eq(paw.ext.loaded.later ~= nil, true, "still loaded")
    paw.commands.exec("ext.unload! later")
    eq(paw.ext.loaded.later, nil, "forced, it unloads")
    eq(
      paw.ui.message.text,
      "later unloaded: what it registered is gone; lua:laterfx on Uses it left there until removed",
      "and says what is left"
    )
    eq(api.device_get(d.id).kind, "lua:laterfx", "the device stays on its track")
    eq(offered("lua:laterfx"), false, "but is offered no more")

    eq(paw.commands.get("later.made"), nil, "the command made later is gone")
    for _, map in ipairs(paw.keymap.every()) do
      if map.lhs == "<leader>Zl" then error("the key mapped later is still mapped") end
    end
    paw.emit("later.ping")
    eq(_G.later_heard, nil, "the hook added later no longer runs")
    eq(paw.timers.waiting:get(tostring(_G.later_timer)), nil, "its timer waiting is cancelled")
    local ticks = _G.later_ticks
    advance(60)
    eq(_G.later_ticks, ticks, "the repeating one stopped")
    eq(paw.opt.later_size, nil, "its option is gone, with the value set")
    eq(paw.option.definitions().later_size, nil, "and its definition")
    -- Loaded again, it starts afresh.
    eq(paw.ext.load(root).ok, true, "loads again")
    eq(paw.opt.later_size, 3, "with its option's default")
    eq(offered("lua:laterfx"), true, "and its device")
    t:remove()
    paw.flush()
    eq(paw.ext.unload("later"), true, "with no device on a track it unloads")
    _G.later_ticks, _G.later_timer, _G.later_fired = nil, nil, nil
  end
)

test(
  "unloading an extension that redefined a core option puts the core's definition back, and leaves the core's timers",
  function()
    T.fresh()
    write(
      dir("redef") .. "/init.lua",
      [[
paw.option.define("lua_devices_watch", 250)
paw.luadev.watch()
]]
    )
    local before = paw.option.definitions().lua_devices_watch
    -- The core's watch runs before the load, as an earlier test can leave it.
    paw.luadev.watch()
    local timers = 0
    for _ in pairs(paw.timers.waiting:entries()) do
      timers = timers + 1
    end
    eq(paw.ext.load(dir("redef")).ok, true, "loads")
    eq(paw.opt.lua_devices_watch, 250, "its default")
    eq(paw.ext.unload("redef"), true, "unloads")
    eq(paw.option.definitions().lua_devices_watch, before, "the core's definition is back")
    eq(paw.opt.lua_devices_watch, before.default, "with its default")
    local after = 0
    for _ in pairs(paw.timers.waiting:entries()) do
      after = after + 1
    end
    eq(after, timers, "the core's watch, started again while it loaded, is not taken away")
  end
)

-- One row for each registry of paw.registry: `put` is the code of an
-- extension that puts an entry at `%q`, and `core` an entry of the core
-- (nil where the core has none). The registry keeps the entry at `prefix`
-- and the name, then `suffix`.
local registries = {
  { reg = paw.pick.sources, core = "tracks", put = "paw.pick.sources:put(%q, { desc = 'mine', items = {} })" },
  {
    reg = paw.statusline.components,
    core = "mode",
    put = "paw.statusline.component(%q, function() return 'mine' end)",
  },
  { reg = paw.commands.specs, core = "info", put = "paw.command(%q, function() end, { desc = 'Mine' })" },
  { reg = paw.ui.views, core = "pager", put = "paw.ui.view(%q, { render = function() end })" },
  {
    reg = paw.layout.types,
    core = "empty",
    put = "paw.buftype(%q, { create = function() return {} end, render = function() end })",
  },
  { reg = paw.textbuf.kinds, core = "history", put = "paw.textbuf.kind(%q, { read = function() return {} end })" },
  { reg = paw.track_kinds.kinds, put = "paw.track_kinds.define(%q, { title = 'Mine' })" },
  {
    reg = paw.clip_kinds.kinds,
    put = "paw.clip_kinds.define(%q, { serialize = function(d) return d end, deserialize = function(d) return d end })",
  },
  { reg = paw.nest.kinds, put = "paw.nest.define_kind(%q, { title = 'Mine' })" },
  { reg = paw.roles.registry, core = "chip", put = "paw.ui.role(%q, { cells = function() end })" },
  {
    reg = paw.query.fields,
    prefix = "note ",
    core = "pitch",
    put = "paw.query.field('note', %q, function() return 1 end)",
  },
  {
    reg = paw.ex.fields,
    core = "pitch",
    put = "paw.ex.field(%q, { level = 'note', type = 'number', get = function() return 1 end })",
  },
  { reg = paw.ex.views, put = "paw.ex.view(%q, { song = function(col) return col end })" },
  { reg = paw.commands.completers, core = "tracks", put = "paw.commands.completers:put(%q, function() return {} end)" },
  { reg = paw.trackcolumn.components, core = "fold", put = "paw.trackcolumn.add(%q, { render = function() end })" },
  { reg = paw.trackcolumn.signs, core = "diagnostics", put = "paw.trackcolumn.sign(%q, { render = function() end })" },
  { reg = paw.ruler.labels, core = "number", put = "paw.ruler.add(%q, { render = function() end })" },
  { reg = paw.insert.kinds, core = "m", put = "paw.insert.add(%q, { kind = 'midi', desc = 'Mine' })" },
  { reg = paw.grep.sources, put = "paw.grep.source(%q, function() end)" },
  { reg = paw.curves.providers, core = "lsp", put = "paw.curves.provide(%q, function() end)" },
  { reg = paw.keymap.mappings, prefix = "n global ", put = "paw.keymap.set(%q, function() end, { desc = 'Mine' })" },
  { reg = paw.keymap.group_registry, prefix = "global ", put = "paw.keymap.group(%q, 'mine')" },
  { reg = paw.option.defined, core = "lua_devices_watch", put = "paw.option.define(%q, 1)" },
  { reg = paw.lsp.configs, put = "paw.lsp.config(%q, { cmd = { 'mine' } })" },
  {
    reg = paw.formats.registry,
    put = "paw.formats.register({ name = %q, extensions = { 'mine' }, import = function() end })",
  },
  { reg = paw.health.checks, core = "extensions", put = "paw.health.register(%q, function() end)" },
  { reg = paw.lang.compilers, put = "paw.lang.add(%q, { command = 'mine %%s' })" },
  {
    reg = paw.complete.sources,
    put = "paw.complete.register({ name = %q, complete = function() end })",
  },
  { reg = paw.address.schemes, put = "paw.address.scheme(%q, { resolve = function() end })" },
  {
    reg = paw.learn.triggers,
    put = "paw.learn.trigger(%q, { press = function() end, name = function() return 'mine' end })",
  },
  {
    reg = paw.ui.layer_registry,
    prefix = "arrange header ",
    put = "paw.ui.layer('arrange', 'header', %q, 99, function() end)",
  },
  { reg = paw.ui.keybar.registry, suffix = " n", core = "arrange", put = "paw.ui.keybar.set(%q, 'n', {})" },
  { reg = paw.roll_draw.keys, put = "paw.roll_draw.key(%q, { desc = 'Mine', run = function() end })" },
  { reg = paw.frontend.bands, put = "paw.frontend.bands:put(%q, function() return {} end)" },
}

test(
  "load, unload and load again leave no entry of an extension in a registry, and the entry it replaced comes back",
  function()
    for _, row in ipairs(registries) do
      local reg, name = row.reg, "registry_" .. row.reg.kind
      local core = row.core or "aa_regtest"
      local prefix, suffix = row.prefix or "", row.suffix or ""
      local function key(name) return prefix .. name .. suffix end
      local was = reg:get(key(core))
      local root = dir(name)
      write(root .. "/init.lua", row.put:format("aa_regtest") .. "\n" .. row.put:format(core))
      for round = 1, 2 do
        local what = reg.kind .. ", round " .. round .. ": "
        local owned = row.core and { key("aa_regtest"), key(core) } or { key(core) }
        table.sort(owned)
        eq(paw.ext.load(root).ok, true, what .. "loads")
        eq(table.concat(reg:owned_by(name), " "), table.concat(owned, " "), what .. "its entries")
        eq(reg:get(key(core)) ~= was, true, what .. "its entry is on top of the core's")
        eq(paw.ext.unload(name), true, what .. "unloads")
        eq(#reg:owned_by(name), 0, what .. "no entry of it is left")
        eq(reg:get(key("aa_regtest")), nil, what .. "its own entry is gone")
        eq(reg:get(key(core)), was, what .. "the core's entry is back")
      end
    end
  end
)

test("an extension that moves an insert key to another key gives the old key back when it unloads", function()
  write(dir("mover") .. "/init.lua", "paw.insert.set('m', { key = 'Z' })")
  local m = paw.insert.get("m")
  T.after(function() paw.ext.unload("mover") end)
  eq(table.concat(paw.opt.insertkeys, ","), "m,a,r,',f", "the built-in insert keys")
  paw.ext.load(dir("mover"))
  eq(table.concat(paw.opt.insertkeys, ","), "Z,a,r,',f", "Z in place of m")
  eq(paw.insert.get("Z").kind, m.kind, "Z inserts what m did")
  paw.ext.unload("mover")
  eq(table.concat(paw.opt.insertkeys, ","), "m,a,r,',f", "m is back in its place")
  eq(paw.insert.get("m"), m, "with its kind")
  eq(paw.insert.get("Z"), nil, "and Z is gone")
end)

test("an entry over another extension's stays when the other unloads, and checkhealth says so", function()
  write(dir("under") .. "/init.lua", "paw.pick.sources:put('regtest_shared', { desc = 'under', items = {} })")
  write(dir("over") .. "/init.lua", "paw.pick.sources:put('regtest_shared', { desc = 'over', items = {} })")
  paw.ext.load(dir("under"))
  paw.ext.load(dir("over"))
  T.after(function()
    paw.ext.unload("over")
    paw.ext.unload("under")
  end)
  local said
  for _, item in ipairs(paw.health.run("extensions").items) do
    if item.text == "over replaces the picker sources regtest_shared of under" then said = item end
  end
  eq(said and said.level, "warn", "checkhealth extensions warns of it")
  paw.ext.unload("under")
  eq(paw.pick.sources:get("regtest_shared").desc, "over", "the entry on top stays")
  paw.ext.unload("over")
  eq(paw.pick.sources:get("regtest_shared"), nil, "and goes with its extension")
end)

test("an extension that maps a key another one mapped wins, and checkhealth says so", function()
  write(
    dir("first") .. "/init.lua",
    'paw.keymap.set("<F9>", function() _G.extapi_key = "first" end, { view = "arrange", desc = "First" })'
  )
  write(
    dir("second") .. "/init.lua",
    'paw.keymap.set("<F9>", function() _G.extapi_key = "second" end, { view = "arrange", desc = "Second" })'
  )
  paw.ext.load(dir("first"))
  paw.ext.load(dir("second"))
  T.after(function()
    paw.ext.unload("second")
    paw.ext.unload("first")
    _G.extapi_key = nil
  end)
  paw.ui.focus("arrange")
  paw.keymap.feed("<F9>")
  eq(_G.extapi_key, "second", "the one loaded last")
  local said
  for _, item in ipairs(paw.health.run("extensions").items) do
    if item.text:find("second replaces the keys", 1, true) and item.text:find("of first", 1, true) then said = item end
  end
  eq(said and said.level, "warn", "checkhealth extensions warns of it")
end)

test("the key rule: an extension's key of one view goes on the local leader, not the leader", function()
  write(
    dir("viewlead") .. "/init.lua",
    'paw.keymap.set("<leader>Zq", function() end, { view = "arrange", desc = "One view" })\n'
      .. 'paw.keymap.set("<localleader>Zq", function() end, { view = "arrange", desc = "One view" })'
  )
  paw.ext.load(dir("viewlead"))
  T.after(function() paw.ext.unload("viewlead") end)
  eq(
    table.concat(paw.keyrule.broken(), "\n"),
    "arrange n <leader>Zq: a key of one view on the leader: use `<localleader>`",
    "the one on the leader"
  )
end)

test("checkhealth says when an extension gives a key of the core another meaning, not when it wraps it", function()
  write(
    dir("rekey") .. "/init.lua",
    'paw.keymap.set("]s", function() end, { view = "arrange", motion = true, desc = "Something else" })\n'
      .. 'paw.keymap.set("<CR>", "clip.edit", { view = "arrange", desc = "Edit the clip\'s notes" })'
  )
  paw.ext.load(dir("rekey"))
  T.after(function() paw.ext.unload("rekey") end)
  local said = {}
  for _, item in ipairs(paw.health.run("extensions").items) do
    if item.text:find("rekey replaces the key", 1, true) then said[#said + 1] = item.level .. " " .. item.text end
  end
  local text = table.concat(said, "; ")
  eq(text:find("]s (n, arrange)", 1, true) ~= nil, true, "a warning about ]s: " .. text)
  eq(text:find("<CR>", 1, true), nil, "none about the wrap of Enter: " .. text)
end)
