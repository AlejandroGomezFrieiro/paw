-- Tests of insert mode in the arrange view (paw/insert.tl): `i`, then one
-- key for each kind of thing to insert at the cursor. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local eq, keys = T.eq, T.keys
local api = paw.api

--- A fresh project with one track, the cursor on it at `beat`, in the
--- arrange view in normal mode; put back as it was after the test.
local function track_at(beat)
  T.fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  paw.opt.clip_length, paw.opt.grid = 4, 1
  local track = paw.add_track({ name = "Keys" })
  paw.cursor.set_track(track)
  paw.cursor.set_beat(beat)
  api.undo_checkpoint()
  T.after(function()
    paw.keymap.feed("<Esc><Esc>")
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
  end)
  return track
end

local function spans(track)
  local out = {}
  for _, c in ipairs(track:clips()) do out[#out + 1] = c.start .. "+" .. c.length end
  table.sort(out)
  return table.concat(out, " ")
end

T.test("insert mode: i m m Escape lays two clips from the cursor, and u takes both back", function()
  local track = track_at(8)
  keys("i")
  eq(paw.keymap.mode, "i", "i starts insert mode in the arrange view")
  keys("m")
  keys("m")
  keys("<Esc>")
  eq(spans(track), "12+4 8+4", "each m a clip at the cursor, which steps past it")
  eq(paw.cursor.beat, 16, "the cursor after the last one")
  eq(paw.keymap.mode, "n", "Escape ends insert mode")
  keys("u")
  eq(spans(track), "", "one undo step for all that insert mode made")
end)

T.test("insert mode: a count makes as many, and a clip in the way is refused", function()
  local track = track_at(0)
  track:add_clip({ start = 12, length = 4 })
  keys("i3m<Esc>")
  eq(spans(track), "0+4 12+4 4+4 8+4", "3m makes three clips one after the other")
  paw.cursor.set_beat(13)
  keys("im<Esc>")
  eq(#track:clips(), 4, "no clip where one is: insert mode moves nothing")
  eq(paw.ui.messages[#paw.ui.messages].text:find("a clip is there already", 1, true) ~= nil, true, "it says why")
end)

T.test("insert mode: r makes a region and ' a marker at the cursor", function()
  track_at(4)
  keys("ir'<Esc>")
  local list = paw.markers.list()
  eq(#list, 2, "a region and a marker")
  eq(list[1].beat .. "+" .. tostring(list[1].length), "4+4", "the region at the cursor, a clip's length long")
  eq(list[2].beat .. " " .. tostring(list[2].length), "8 nil", "the marker where the region ends")
end)

T.test("insert mode: Enter with nothing inserted enters notes here, as i did", function()
  local track = track_at(4)
  keys("i<CR>")
  eq(paw.ui.focused .. paw.keymap.mode, "pianorolli", "the piano roll, in insert mode")
  eq(spans(track), "4+4", "on a new clip at the cursor")
  keys("4l<Esc>")
  eq(#track:clips()[1]:notes(), 1, "the note drawn")
  keys("u")
  eq(spans(track), "", "the clip and its note are one undo step")
end)

T.test("insert mode: an extension's key and kind of clip come and go with it", function()
  track_at(0)
  local dir = T.scratch .. "/insertext"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(dir .. "/init.lua", [[
    paw.clip_kinds.define("cue", {
      title = "Cue clip", insert = "c",
      serialize = function(d) return { text = d.text } end,
      deserialize = function(s) return { text = s.text } end,
      create = function() return { text = "go" } end,
    })
    paw.insert.add("M", { kind = "midi", desc = "A two-bar clip", length = "2 bars" })
  ]])
  T.write_file(dir .. "/manifest.lua", 'return { name = "insertext", version = "0.1.0" }')
  local before = table.concat(paw.opt.insertkeys, ",")
  T.after(function() if paw.ext.loaded.insertext then paw.ext.unload("insertext") end end)
  assert(paw.ext.load(dir).ok, "the extension loads")
  local track = paw.cursor.track()
  keys("iMc<Esc>")
  eq(spans(track), "0+8 8+4", "M a two-bar clip, c a cue clip after it")
  eq(track:clips()[2].kind, "cue", "of the kind")
  local insert_keys = table.concat(paw.opt.insertkeys, ",")
  eq(insert_keys:find("M", 1, true) ~= nil and insert_keys:find("c", 1, true) ~= nil, true, "both keys work: " .. insert_keys)
  paw.ext.unload("insertext")
  eq(tostring(paw.insert.get("M")) .. " " .. tostring(paw.insert.get("c")), "nil nil", "both go with it")
  eq(table.concat(paw.opt.insertkeys, ","), before, "and out of paw.opt.insertkeys")
end)
