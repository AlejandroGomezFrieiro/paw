-- Clips of a kind that an extension defines: the core keeps their data,
-- sound and signals, and needs the kind to be defined before it adds one.
local T = ...
local test, eq, fails, fresh = T.test, T.eq, T.fails, T.fresh
local paw = require("paw")
local api = paw.api

test("a custom clip is added, set in one step, and undone", function()
  fresh()
  local t = paw.add_track({ name = "Film" })
  fails(function() api.clip_add(t.id, { kind = "film", data = { json = {} }, length = 4 }) end,
    "no clip kind `film` is defined", "an unknown kind")
  fails(function() api.clip_kind_define("midi") end, "built%-in kind", "a built-in word")
  api.clip_kind_define("film")
  eq(table.concat(api.clip_kinds(), " "), "film", "the kinds that are defined")

  local data = { scenes = { 1, 2.5, { title = "Intro", dark = true } }, cut = "x" }
  local id = api.clip_add(t.id, { kind = "film", data = { json = data }, length = 4 })
  eq(api.clip_get(id).kind, "film", "the clip has the kind")
  eq(paw.json.encode(api.clip_custom(id).data.json), paw.json.encode(data), "its data comes back as the table")

  api.undo_checkpoint()
  api.clip_set_custom(id, {
    data = { json = { 3 } },
    sound = { kind = "midi", notes = { { start = 0, length = 1, pitch = 60 } } },
    signals = { { at = 1, to = { kind = "osc", port = "qlc", address = "/go", args = { 1 } } } },
    media = { { role = "source", path = "/a.mp4" } },
    offset = 2,
  })
  api.undo_checkpoint()
  local c = api.clip_custom(id)
  eq(c.data.json[1] .. " " .. c.offset .. " " .. #c.signals .. " " .. #c.media .. " " .. #c.sound.notes, "3 2 1 1 1", "all replaced")
  paw.undo()
  c = api.clip_custom(id)
  eq(c.data.json.cut .. " " .. #(c.signals or {}) .. " " .. #(c.media or {}), "x 0 0", "one undo restores them all")
  fails(function() api.clip_custom(api.clip_add(t.id, { length = 1 })) end, "not a custom one", "a MIDI clip")
end)

-- A kind of film clips: its data names a file and its scenes; it sounds as
-- one note per scene. It saves its data as it is; version 1 had no scenes.
local function film(version)
  return {
    version = version,
    serialize = function(data) return data end,
    deserialize = function(stored, from)
      if from < 2 and (version or 1) >= 2 then return { file = stored.file, scenes = 2 } end
      return stored
    end,
    create = function(args) return { file = args[1], scenes = 1 } end,
    check = function(data) if type(data.file) ~= "string" then return "a film names its file" end end,
    compile = function(data)
      local notes = {}
      for i = 1, data.scenes do notes[i] = { start = i - 1, length = 1, pitch = 60 } end
      return { sound = { kind = "midi", notes = notes }, length = data.scenes }
    end,
    describe = function(clip) return clip:data().file end,
  }
end

test("clip_kinds: a kind's clip is made, set as one undo step and described; a slow kind is stopped", function()
  fresh()
  T.after(function() paw.clip_kinds.remove("film") end)
  paw.clip_kinds.define("film", film())
  local t = paw.add_track({ name = "Film" })
  local clip = paw.clip_kinds.add(t, "film", { "intro.mp4" })
  api.undo_checkpoint()
  eq(clip:data().file .. " " .. clip.length, "intro.mp4 1", "made by create, as long as it compiled")
  eq(paw.clip_kinds.describe(clip), "Film clip · intro.mp4", "described")

  clip:set_data({ file = "intro.mp4", scenes = 3 })
  api.undo_checkpoint()
  eq(#api.clip_custom(clip.id).sound.notes, 3, "set compiles its sound again")
  paw.undo()
  eq(clip:data().scenes .. " " .. #api.clip_custom(clip.id).sound.notes, "1 1", "one undo puts data and sound back")
  fails(function() clip:set_data({ scenes = 2 }) end, "kind `film`: a film names its file", "its check refuses bad data")
  fails(function() clip:set_data({ file = "x", scenes = 1, frames = { 1, 2, print } }) end,
    "^kind `film`: .-%.frames%[3%]: a function is not data", "data that is not plain")

  local slow = film()
  slow.compile = function() while true do end end
  paw.clip_kinds.define("film", slow)
  fails(function() clip:set_data({ file = "x", scenes = 1 }) end, "ran for more than 0.05 s", "a compile that does not return")
end)

test("clip_kinds: older data is migrated when the kind is defined and when the project opens; newer data is refused", function()
  fresh()
  T.after(function() paw.clip_kinds.remove("film") end)
  paw.clip_kinds.define("film", film())
  local clip = paw.clip_kinds.add(paw.add_track({ name = "Film" }), "film", { "a.mp4" })
  api.undo_checkpoint()
  local path = T.scratch .. "/film.paw"
  api.project_save(path)
  paw.clip_kinds.define("film", film(2))
  local c = api.clip_custom(clip.id)
  eq((c.version or 1) .. " " .. clip:data().scenes .. " " .. #c.sound.notes, "2 2 2", "migrated and compiled at define")

  api.project_load(path)
  paw.flush()
  clip = paw.clip(api.clip_list(api.track_list()[1])[1].id)
  eq((api.clip_custom(clip.id).version or 1) .. " " .. clip:data().scenes, "2 2", "migrated when it opens")
  eq(api.undo_pending(), false, "opening is not an undo step")

  paw.clip_kinds.define("film", film(1))
  local data, why = clip:data()
  eq(data, nil, "a newer clip's data is not read")
  eq(why, "this clip was made by a newer film extension (data 2, this one knows 1)", "and why")
  fails(function() clip:set_data({ file = "b.mp4", scenes = 1 }) end, "data 2, this one knows 1", "nor changed")
end)

test("clip_kinds: unloading the extension removes its kind; its clips keep their data and say which kind", function()
  fresh()
  local root = T.scratch .. "/ext-lyrics"
  os.execute("mkdir -p '" .. root .. "'")
  local f = assert(io.open(root .. "/init.lua", "w"))
  f:write('paw.clip_kinds.define("lyrics", { serialize = function(d) return d end, deserialize = function(s) return s end,'
    .. ' create = function() return { words = "la" } end })')
  f:close()
  eq(paw.ext.load(root).ok, true, "the extension loads")
  local clip = paw.clip_kinds.add(paw.add_track({ name = "Words" }), "lyrics", { length = 4 })
  api.undo_checkpoint()
  paw.ext.unload("ext-lyrics")
  eq(table.concat(paw.clip_kinds.list(), " ") .. "|" .. table.concat(api.clip_kinds(), " "), "|", "the kind is gone")
  eq(paw.clip_kinds.describe(clip), "lyrics (no extension here defines it)", "described without it")
  eq(clip:data().words, "la", "its data stays")
  fails(function() clip:set_data({ words = "da" }) end, "load the extension that defines `lyrics`", "not changed")
  local _, right = paw.clip_kinds.split(clip, 1)
  eq(right.offset .. " " .. right.data.json.words, "1 la", "split without the kind: the same data, from the cut")
end)

test("a custom clip's data is plain data, never binary", function()
  fresh()
  local t = paw.add_track({ name = "Film" })
  api.clip_kind_define("film")
  local id = api.clip_add(t.id, { kind = "film", data = { json = { n = 1 } }, length = 4 })
  local function set(json) api.clip_set_custom(id, { data = { json = json } }) end
  fails(function() set({ frames = { 1, 2, print } }) end, "^.-%.frames%[3%]: a function is not data", "a function")
  fails(function() set({ blob = "\255\0" }) end, "%.blob: a string that is not UTF%-8 is not data: binary data goes in a media file",
    "binary")
  fails(function() set({ big = string.rep("x", 1100000) }) end, "over the limit of 1 MB", "too big")
  eq(api.clip_custom(id).data.json.n, 1, "a refused set changes nothing")
end)
