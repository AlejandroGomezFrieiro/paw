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
