-- Clips of a kind that an extension defines: the core keeps their data,
-- sound and signals, and needs the kind to be defined before it adds one.
local T = ...
local test, eq, fails, fresh = T.test, T.eq, T.fails, T.fresh
local paw = require("paw")
local api = paw.api

test("a custom clip is added, set in one step, and undone", function()
  fresh()
  local t = paw.add_track({ name = "Film" })
  fails(function() api.clip_add(t.id, { kind = "film", data = { json = "{}" }, length = 4 }) end,
    "no clip kind `film` is defined", "an unknown kind")
  fails(function() api.clip_kind_define("midi") end, "built%-in kind", "a built-in word")
  api.clip_kind_define("film")
  eq(table.concat(api.clip_kinds(), " "), "film", "the kinds that are defined")

  local data = '{ "scenes" :[1,  2] }'
  local id = api.clip_add(t.id, { kind = "film", data = { json = data }, length = 4 })
  eq(api.clip_get(id).kind, "film", "the clip has the kind")
  eq(api.clip_custom(id).data.json, data, "its data is kept as given")

  api.undo_checkpoint()
  api.clip_set_custom(id, {
    data = { json = "[3]" },
    sound = { kind = "midi", notes = { { start = 0, length = 1, pitch = 60 } } },
    signals = { { at = 1, to = { kind = "osc", port = "qlc", address = "/go", args = { 1 } } } },
    media = { { role = "source", path = "/a.mp4" } },
    offset = 2,
  })
  api.undo_checkpoint()
  local c = api.clip_custom(id)
  eq(c.data.json .. " " .. c.offset .. " " .. #c.signals .. " " .. #c.media .. " " .. #c.sound.notes, "[3] 2 1 1 1", "all replaced")
  paw.undo()
  c = api.clip_custom(id)
  eq(c.data.json .. " " .. #(c.signals or {}) .. " " .. #(c.media or {}), data .. " 0 0", "one undo restores them all")
  fails(function() api.clip_custom(api.clip_add(t.id, { length = 1 })) end, "not a custom one", "a MIDI clip")
end)
