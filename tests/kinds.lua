-- Tests of the kinds of each family (paw.kinds): stream kinds and their
-- properties, a clip kind whose extension is gone, a part kind that no
-- extension defines, `:part.kind`, groups in groups, and the keys of meta
-- (paw.meta). Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fails, fresh = T.test, T.eq, T.fails, T.fresh
local api = paw.api

--- The kinds of `family` that the kernel keeps, as `name=owner` words.
local function kept(family)
  local out = {}
  for _, kind in ipairs(paw.kinds.list(family)) do
    out[#out + 1] = kind.name .. "=" .. kind.owner
  end
  return table.concat(out, " ")
end

--- The loudest sample of a render of the project, of both sides.
local function loudest()
  local info = T.render({ tail = 0, bits = 16, ["end"] = 2 })
  local l, r = T.channel_peaks(info, 0, 1.9)
  return math.max(l, r)
end

test("a stream kind takes the properties that it declares, and the kernel names each one it does not", function()
  fresh()
  T.after(function() paw.kinds.remove("stream", "film.frames") end)
  paw.kinds.define("stream", "film.frames", {
    title = "Film frames",
    time = "seconds",
    records = true,
    props = { rate = { type = "number", minimum = 1 }, alpha = { type = "boolean" } },
  })
  eq(
    kept("stream"),
    "audio=paw.streams curve=paw.streams film.frames=the user midi=paw.streams state=paw.streams",
    "the kernel keeps it beside the core's, with its owner"
  )
  api.stream_check({ base = "film.frames", props = { rate = { 30000, 1001 }, alpha = true } })
  api.stream_check({ base = "midi", props = { lyrics = true } })
  fails(
    function() api.stream_check({ base = "film.frames", props = { fps = 24 } }) end,
    "the stream kind `film.frames` has no property `fps` %(it has: alpha, rate%)",
    "a property that it does not declare"
  )
  fails(
    function() paw.kinds.define("stream", "film.frames", { time = "bars" }) end,
    "its time is `samples`, `beats` or `seconds`",
    "a time that no stream has"
  )
  fails(function() paw.kinds.define("stream", "Film", {}) end, "`Film` is not a name of a kind", "a name")
  fails(function() paw.kinds.define("lane", "x", {}) end, "`lane` is no family of kinds", "a family")
end)

test("a project with a clip kind of an extension that is gone opens and plays the sound that the kind made", function()
  fresh()
  local root = T.scratch .. "/ext-beeps"
  os.execute("mkdir -p '" .. root .. "'")
  T.write_file(
    root .. "/init.lua",
    [[paw.kinds.define("clip", "beeps", {
      gives = "midi",
      serialize = function(d) return d end,
      deserialize = function(s) return s end,
      create = function() return { pitch = 69 } end,
      compile = function(d)
        return { sound = { kind = "midi", notes = { { start = 0, length = 1, pitch = d.pitch } } }, length = 1 }
      end,
    })]]
  )
  eq(paw.ext.load(root).ok, true, "the extension loads")
  T.after(function() paw.ext.unload("ext-beeps") end)
  local part = paw.add_part({ name = "Beeps" })
  part:add_device("synth")
  paw.clip_kinds.add(part, "beeps", {})
  eq(kept("clip"):find("beeps=ext-beeps", 1, true) ~= nil, true, "the kernel names the extension as its owner")
  local path = T.scratch .. "/beeps.paw"
  api.project_save(path)
  paw.ext.unload("ext-beeps")
  fresh()
  api.project_load(path)
  paw.flush()
  local clip = paw.clip(api.clip_list(api.part_list()[1])[1].id)
  eq(clip.kind .. " " .. kept("clip"), "beeps audio=paw.clips curve=paw.clips midi=paw.clips nest=paw.clips", "no kind")
  eq(loudest() > 0.01, true, "the kept sound plays")
end)

test("a part of a kind that no extension defines shows the kind, plays, and keeps it all on save", function()
  fresh()
  local part = paw.add_part({ name = "Odd" })
  part:add_device("synth")
  part:add_clip({ start = 0, length = 1, notes = { { pitch = 69, start = 0, length = 1 } } })
  api.part_set(part.id, { kind = "theremin" })
  part.meta = { theremin = { hand = "left" } }
  eq(paw.part_kinds.describe(part.id), "theremin (no extension here defines it)", "K names the kind")
  paw.ui.focus("arrange")
  T.settle()
  T.expect_screen("absent-kind", 80, 20, { rows = { 2, 4 }, cols = { 1, 20 } })
  eq(loudest() > 0.01, true, "it plays")
  local path = T.scratch .. "/odd.paw"
  api.project_save(path)
  fresh()
  api.project_load(path)
  local back = paw.parts()[1]
  eq(
    back:get().kind .. " " .. back.meta.theremin.hand .. " " .. #back:devices() .. " " .. #back:clips(),
    "theremin left 1 1",
    "the kind, its meta, its devices and its clips stay"
  )
end)

test(":part.kind sets the kind of the part and :part.kind alone clears it, each one undo step", function()
  T.start()
  paw.kinds.define("part", "bleep", { title = "Bleep part" })
  T.after(function() paw.kinds.remove("part", "bleep") end)
  local part = paw.add_part({ name = "Lead" })
  paw.cursor.set_part(part)
  api.undo_checkpoint()
  T.keys(":part.kind bleep<CR>")
  eq(paw.part_kinds.of(part.id), "bleep", "the kind is set")
  eq(paw.ui.message.text, "Lead is a bleep part", "and said")
  T.keys(":part.kind<CR>")
  eq(paw.part_kinds.of(part.id), nil, "cleared")
  eq(paw.ui.message.text, "Lead is an ordinary part again: its clips, lanes and devices stay", "and said")
  T.keys("u")
  eq(paw.part_kinds.of(part.id), "bleep", "one u brings the kind back")
  T.keys("u")
  eq(paw.part_kinds.of(part.id), nil, "one more u, and it never had one")
  T.keys(":part.kind harp<CR>")
  eq(paw.ui.message.text:find("no kind of part `harp`", 1, true), 1, "an unknown kind is named")
end)

test(
  "groups go into groups three deep, sum what they hold, and a move that puts a group inside itself is refused",
  function()
    fresh()
    local voice = paw.add_part({ name = "Voice" })
    voice:add_device("synth")
    voice:add_clip({ start = 0, length = 1, notes = { { pitch = 69, start = 0, length = 1 } } })
    local inner = paw.groups.make({ voice }, "Inner")
    local middle = paw.groups.make({ inner }, "Middle")
    local outer = paw.groups.make({ middle }, "Outer")
    api.undo_checkpoint()
    eq(
      paw.groups.depth(voice) .. " " .. tostring(api.part_get(voice.id, "parent") == inner.id),
      "3 true",
      "three deep, the field names the group"
    )
    eq(loudest() > 0.01, true, "the voice sounds through the three groups")
    fails(function() paw.groups.add(outer, inner) end, "`Outer` cannot go into `Inner`: it holds that group", "a cycle")
    eq(api.part_get(outer.id, "parent"), nil, "and nothing moved")
  end
)

test("a key of meta names the module that keeps it, and :checkhealth lists the keys that no module declares", function()
  fresh()
  paw.meta.define("film", { title = "The film of a part" })
  T.after(function() paw.kinds.remove("meta", "film") end)
  local part = paw.add_part({ name = "Score" })
  part.meta = { film = "intro.mp4", stray = 1, group_head = true }
  eq(paw.meta.owner("group_head") .. "|" .. paw.meta.owner("film"), "paw|the user's config", "the owners")
  eq(paw.meta.owner("stray"), nil, "a key that no module declares")
  paw.cursor.set_part(part)
  paw.ui.focus("arrange")
  paw.cmd("info")
  eq(T.screen(120, 40):find("meta    stray (no loaded module declares it)", 1, true) ~= nil, true, "K says so")
  paw.keymap.feed("<Esc>")
  local undeclared = paw.meta.undeclared()
  eq(#undeclared .. " " .. undeclared[1].key .. " " .. undeclared[1].places[1], "1 stray part Score", "listed")
  T.keys(":checkhealth meta<CR>")
  eq(T.screen(120, 40):find("`stray` on part Score", 1, true) ~= nil, true, ":checkhealth lists it")
end)
