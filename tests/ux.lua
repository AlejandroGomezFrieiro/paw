-- Tests of small things in the terminal UI that people trip over: the
-- mixer's fader scale, texts that said the wrong key, what leaving insert
-- mode says, the order of the pickers, how the messages are shown, and a
-- window whose buffer went with the project. Loaded by tests/suite.lua with
-- its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local function shot(w, h) return api.ui_snapshot(w or 140, h or 44) end
local function screen(w, h) return table.concat(shot(w, h), "\n") end

--- The character in a cell of the screen.
local function cell(x, y, w, h)
  local col = 0
  for ch in (shot(w, h)[y + 1] or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if col == x then return ch end
    col = col + api.str_width(ch)
  end
end

local function start()
  fresh()
  api.engine_restart({ backend = "null" })
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  for _, name in ipairs({ "pianoroll", "mixer", "devices" }) do
    paw.ui.hide(name)
  end
  paw.ui.focus("arrange")
end

test("the mixer's fader scale labels the rows its cap takes", function()
  start()
  paw.add_track({ name = "A" })
  paw.ui.show("mixer")
  local mixer = paw.ui.views:get("mixer")
  api.undo_checkpoint()
  shot(160, 60)
  local rect
  for _, r in ipairs(paw.ui.rects) do
    if r.name == "mixer" then rect = r end
  end
  local s = mixer.geometry.strips[#mixer.geometry.strips]
  local fx = s.x + math.floor(s.w / 2) + 1
  for _, mark in ipairs({ 6, 0, -6, -12, -24, -48 }) do
    paw.master.volume = mark
    local y = rect.y + 1 + s.y + s.rows - 1 - mixer.fader_row(mark, s.rows)
    eq(cell(rect.x + fx, y, 160, 60), paw.draw.g.fader, mark .. " dB: the cap is on its row")
    local label = (mark > 0 and "+" or "") .. mark
    eq(cell(rect.x + 3 - #label, y, 160, 60), label:sub(1, 1), mark .. " dB: and the scale names it there")
  end
  paw.master.volume = 0
end)

test("the welcome page and the empty roll name the right keys", function()
  start()
  local lines = screen()
  eq(
    lines:find("i Enter%s+enter notes") ~= nil,
    true,
    "`i` `Enter` enters notes (`I` in the arrange view chooses the input)"
  )
  paw.ui.show("pianoroll")
  local text = screen(140, 44)
  local at = text:find("press Enter", 1, true)
  eq(at ~= nil, true, "the roll asks for Enter after a space: " .. (text:match("press%S*") or "nothing"))
  paw.ui.hide("pianoroll")
end)

test("leaving insert mode says how many notes were written", function()
  start()
  local t = paw.add_track({ name = "Keys" })
  local clip = t:add_clip({ start = 0, length = 4 })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  api.undo_checkpoint()
  paw.ui.views:get("pianoroll"):edit(clip)
  paw.ui.focus("pianoroll")
  paw.keymap.feed("i")
  paw.keymap.feed("l")
  paw.keymap.feed("<CR>")
  paw.keymap.feed("l")
  paw.keymap.feed("<Esc>")
  eq(#clip:notes(), 2, "two notes were drawn")
  eq(paw.ui.messages[#paw.ui.messages].text, "wrote 2 notes", "and Escape says so")
  paw.keymap.feed("i")
  paw.keymap.feed("<Esc>")
  eq(paw.ui.messages[#paw.ui.messages].text, "wrote 2 notes", "an insert that wrote nothing says nothing")
end)

test("the device picker lists instruments first on a track without one, effects on a track with one", function()
  start()
  local library = paw.fx.library()
  local kept = { library.favourites, library.recent }
  library.favourites, library.recent = {}, {}
  local t = paw.add_track({ name = "Empty" })
  paw.cursor.set_track(t)
  local items = paw.pick.sources:get("devices").items()
  eq(items[1].category, "instrument", "a track with nothing in it is offered instruments first")
  eq(paw.fx.preferred(t.id), "instrument", "that is what `preferred` says")
  t:add_device("synth")
  items = paw.pick.sources:get("devices").items()
  eq(items[1].category, "effect", "once it has one, effects come first")
  eq(paw.fx.preferred(0), "effect", "and the master wants effects")
  library.favourites, library.recent = kept[1], kept[2]
end)

test("the send picker lists returns before tracks that play an instrument, and a new send starts at -12 dB", function()
  start()
  local source = paw.add_track({ name = "Source" })
  local synth = paw.add_track({ name = "Synth" })
  synth:add_device("synth")
  local verb = paw.add_track({ name = "Verb" })
  verb:add_device("reverb")
  paw.cursor.set_track(source)
  local seen
  local pick = paw.pick
  paw.pick = setmetatable({}, { __index = pick, __call = function(_, spec) seen = spec end })
  paw.commands.run("send")
  paw.pick = pick
  eq(seen.items[1].name, "Verb", "the return is first")
  eq(seen.items[2].name, "Synth", "the instrument after it")
  paw.commands.run("send", { "Verb" })
  eq(source:get().sends[1].level, -12, "a send starts at -12 dB")
  paw.opt.send_level = -3
  paw.commands.run("send", { "Synth" })
  eq(source:get().sends[2].level, -3, "or at what `send_level` says")
  paw.opt.send_level = -12
end)

test(":messages keeps every message and lists the newest last", function()
  start()
  local before = #paw.ui.messages
  paw.notify("added Synth to Track 1")
  local long = "one two three four five six seven eight nine ten " .. ("long "):rep(30) .. "end"
  paw.notify(long)
  eq(#paw.ui.messages, math.min(500, before + 2), "both are kept")
  eq(paw.ui.messages[#paw.ui.messages - 1].text, "added Synth to Track 1", "the one a picker made too")
  paw.commands.run("messages")
  local pager = paw.ui.views:get("pager")
  eq(pager.lines[#pager.lines - 1].text, "added Synth to Track 1", "the page lists them, the newest last")
  paw.ui.close()
end)

test("a window whose curve is gone with the project closes", function()
  start()
  local t = paw.add_track({ name = "A" })
  local lane = t:automate("volume")
  local uri = paw.address.lane(lane.id)
  paw.commands.run("vs", { uri })
  local function shows()
    for _, entry in ipairs(paw.layout.all_windows()) do
      local buf = paw.layout.buf_of(entry.win)
      if buf and buf.target == uri then return true end
    end
    return false
  end
  eq(shows(), true, "a window shows the lane")
  fresh()
  eq(shows(), false, "after a new project it does not")
  paw.keymap.feed("<Esc><Esc>")
  paw.commands.run("only")
end)
