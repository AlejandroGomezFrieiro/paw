-- Extensions that wait for their first use (paw/lazy.tl): the triggers of a
-- manifest and of `paw.ext.use`, the stubs, the first use, the kinds, and
-- what `:extensions` and `:help` say. Loaded by tests/suite.lua.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api

local function write(path, text)
  os.execute("mkdir -p '" .. path:match("^(.*)/") .. "'")
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

--- A scratch extension `name` with its manifest and its init.lua. Gives its
--- folder. The test takes it away (waiting or loaded) at its end.
local function extension(name, manifest, init)
  local root = T.scratch .. "/lazy/" .. name
  write(root .. "/manifest.lua", manifest)
  write(root .. "/init.lua", init)
  T.after(function() paw.ext.unload(name, { force = true }) end)
  return root
end

local function track_names()
  local out = {}
  for _, t in ipairs(paw.tracks()) do
    out[#out + 1] = t.name
  end
  return table.concat(out, " ")
end

test("a command of an extension that waits is listed, and its first use loads it and runs as one undo step", function()
  T.start()
  local root = extension(
    "lazycmd",
    'return { cmd = { { "lz.add", desc = "Add a track named after the word" }, "lz.*" } }',
    [[
    paw.command("lz.add", function(ctx) paw.add_track({ name = ctx.args[1] }) end, { desc = "Add a track" })
    paw.command("lz.more", function() paw.add_track({ name = "More" }) end, { desc = "Add More" })
  ]]
  )
  eq(paw.ext.use(root), nil, "it waits")
  eq(paw.ext.loaded.lazycmd, nil, "and is not loaded")
  eq(
    paw.commands.get("lz.add").desc,
    "Add a track named after the word",
    "its command is listed with the words of the manifest"
  )
  eq(paw.commands.get("lz.add").ext, "lazycmd", "as its own")
  local found = false
  for _, entry in ipairs(paw.commands.complete("lz.a")) do
    if entry.text:match("lz%.add") then found = true end
  end
  eq(found, true, "completion offers it")

  T.keys(":lz.add Drums<CR>")
  eq(paw.ext.loaded.lazycmd.loaded_by, ":lz.add", "the first use loaded it, and says so")
  eq(track_names(), "Drums", "and ran the command with its argument")
  eq(paw.commands.get("lz.add").desc, "Add a track", "the real command took the place of the stub")
  T.keys("u")
  eq(track_names(), "", "one u undoes the command")

  eq(paw.ext.unload("lazycmd"), true, "it unloads")
  eq(paw.commands.get("lz.add"), nil, "with its commands, and the stubs do not come back")

  paw.ext.use(root)
  T.keys(":lz.more<CR>")
  eq(paw.ext.loaded.lazycmd.loaded_by, ":lz.more", "a command under a prefix loads it too")
  eq(track_names(), "More", "and runs")
end)

test("a key of an extension that waits loads it, and runs with its count and register as one undo step", function()
  T.start()
  local root = extension(
    "lazykey",
    'return { keys = { { "<localleader>Zk", view = "arrange", desc = "Add tracks for the count" } } }',
    [[
    paw.keymap.set("<localleader>Zk", function(ctx)
      for i = 1, ctx.count or 1 do
        paw.add_track({ name = (ctx.register or "none") .. i })
      end
    end, { view = "arrange", desc = "Add tracks" })
  ]]
  )
  paw.ext.use(root)
  local stub
  paw.keymap.each(function(map, _, scope)
    if map.lhs == "<localleader>Zk" and scope == "arrange" then stub = map end
  end)
  eq(stub and stub.desc .. " " .. stub.ext, "Add tracks for the count lazykey", "the key is mapped, with its words")
  T.keys('"a2<localleader>Zk')
  eq(paw.ext.loaded.lazykey.loaded_by, "<localleader>Zk", "the key loaded it")
  eq(track_names(), "a1 a2", "the real key ran with the count and the register")
  T.keys("u")
  eq(track_names(), "", "one u undoes the key")
end)

test("an event or a view of an extension that waits loads it, and its handler gets the event", function()
  T.start()
  paw.events.event("lazy.ping")
  local root = extension(
    "lazywatch",
    'return { event = "lazy.ping", view = "lazyview" }',
    [[
    paw.on("lazy.ping", function(p) _G.lazy_pinged = p.n end)
    paw.ui.view("lazyview", { render = function(_, buf) buf:text(0, 0, "the real view") end })
  ]]
  )
  T.after(function() _G.lazy_pinged = nil end)
  paw.ext.use(root)
  paw.emit("lazy.ping", { n = 7 })
  eq(paw.ext.loaded.lazywatch.loaded_by, "event lazy.ping", "the event loaded it")
  eq(_G.lazy_pinged, 7, "and its handler got that event")

  paw.ext.unload("lazywatch")
  paw.ext.use(root)
  paw.ui.open("lazyview")
  T.after(function() paw.ui.close() end)
  T.screen()
  T.until_(function() return paw.ext.loaded.lazywatch end, "the view loads it")
  eq(paw.ext.loaded.lazywatch.loaded_by, "view lazyview", "and says so")
  eq(T.screen():find("the real view", 1, true) ~= nil, true, "the real view draws")
end)

test(
  "a project with a clip of a kind that waits opens and plays as it was saved, and the kind loads its extension",
  function()
    T.fresh()
    local root = extension(
      "lazyfilm",
      'return { kind = "film" }',
      [[
    paw.clip_kinds.define("film", {
      serialize = function(d) return d end,
      deserialize = function(s) return s end,
      create = function() return { scenes = 2 } end,
      compile = function(d)
        local notes = {}
        for i = 1, d.scenes do notes[i] = { start = i - 1, length = 1, pitch = 60 + i } end
        return { sound = { kind = "midi", notes = notes }, length = d.scenes }
      end,
    })
  ]]
    )
    paw.ext.load(root)
    local clip = paw.clip_kinds.add(paw.add_track({ name = "Film" }), "film", {})
    api.undo_checkpoint()
    local saved = paw.inspect(api.clip_custom(clip.id).sound)
    local path = T.scratch .. "/lazy/film.paw"
    api.project_save(path)
    paw.ext.unload("lazyfilm")

    paw.ext.use(root)
    eq(paw.ext.loaded.lazyfilm, nil, "it waits")
    api.project_load(path)
    paw.flush()
    eq(paw.ext.loaded.lazyfilm and paw.ext.loaded.lazyfilm.loaded_by, "kind film", "the clip of its kind loaded it")
    local id = api.clip_list(api.track_list()[1])[1].id
    eq(paw.inspect(api.clip_custom(id).sound), saved, "the clip plays what it saved")
    eq(api.undo_pending(), false, "opening is not an undo step")
  end
)

test("a kind trigger is any key of any registry", function()
  T.fresh()
  local root = extension(
    "lazypick",
    'return { kind = { { registry = "pickers", key = "lazypick" } } }',
    'paw.pick.sources:put("lazypick", { desc = "Things", items = function() return {} end })'
  )
  paw.ext.use(root)
  eq(paw.ext.loaded.lazypick, nil, "it waits")
  eq(paw.pick.sources:get("lazypick").desc, "Things", "asking the registry for the key loads it")
  eq(paw.ext.loaded.lazypick.loaded_by, "kind pickers lazypick", "and says so")
end)

test("an extension that waits and fails to load says so once, and its stub stays", function()
  T.start()
  local root = extension("lazybad", 'return { cmd = "bad.go" }', 'error("broken on purpose")')
  paw.ext.use(root)
  local before = #paw.ui.messages
  T.keys(":bad.go<CR>")
  eq(paw.ext.loaded.lazybad.ok, false, "it failed")
  local said = {}
  for i = before + 1, #paw.ui.messages do
    said[#said + 1] = paw.ui.messages[i].text:match("^[^\n]*")
  end
  eq(#said, 1, "one message: " .. table.concat(said, " | "))
  eq(said[1]:find("extension lazybad failed: ", 1, true) ~= nil, true, "which says which extension failed")
  eq(paw.ext.lazy.waiting.lazybad ~= nil and paw.commands.get("bad.go") ~= nil, true, "and waits again, with its stub")
end)

test(":extensions says what loaded each extension, and what the others wait for", function()
  T.start()
  -- Only these two on the page: the extensions that earlier tests left
  -- loaded go until the end of the test.
  local others = {}
  for _, e in ipairs(paw.ext.list()) do
    if paw.ext.unload(e.name, { force = true }) then others[#others + 1] = e.path end
  end
  T.after(function()
    paw.ext.unload("templates")
    paw.ext.unload("continue")
    for _, path in ipairs(others) do
      paw.ext.load(path)
    end
  end)
  eq(paw.ext.use("templates"), nil, "templates waits for its first use")
  eq(paw.ext.use("continue").loaded_by, "paw.ext.use", "continue has no trigger, and loads")
  T.keys(":extensions<CR>")
  T.expect_screen("extensions", 100, 24, { rows = { 2, 16 }, styles = false })
  T.keys("<Esc>")
  T.keys(":help templates<CR>")
  local screen = T.screen(100, 40)
  eq(screen:find("This extension loads when you first use one of these:", 1, true) ~= nil, true, ":help says it waits")
  eq(screen:find(":ext.load templates", 1, true) ~= nil, true, "and how to load it now")
end)
