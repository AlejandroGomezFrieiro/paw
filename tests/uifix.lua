-- Fixes found by a second evaluation of the terminal UI. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local L = paw.layout

local function screen(w, h) return table.concat(api.ui_snapshot(w or 160, h or 48), "\n") end
local function last_message()
  local m = paw.ui.messages[#paw.ui.messages]
  return m and m.text or ""
end

-- The focused view is drawn, and it is the one the keyboard is in.
local function focus_is_drawn(after)
  local focused = paw.ui.focused
  eq(paw.ui.visible(focused), true, "`" .. tostring(focused) .. "` has focus but is not drawn, after " .. after)
  local win = L.current()
  eq(win ~= nil and win.view == focused, true, "the current window shows `" .. tostring(focused) .. "` after " .. after)
end

test("focus only ever goes to a view that is drawn", function()
  fresh()
  paw.add_track({ name = "Lead" })
  for _, line in ipairs({
    "e paw://tracks",
    "view.focus arrange",
    "bprevious",
    "view.focus mixer",
    "view.focus arrange",
    "e paw://tracks",
    "view.focus mixer",
    "bnext",
    "view.only",
    "view.focus mixer",
    "view.focus arrange",
    "copen",
    "view.focus qflist",
    "cclose",
    "bprevious",
    "bnext",
    "view.focus arrange",
    "split",
    "vsplit",
    "wincmd j",
    "wincmd w",
    "close",
    "only",
    "e paw://tracks",
    "split",
    "view.focus mixer",
    "view.focus devices",
    "view.focus pianoroll",
    "view.close",
    "view.toggle mixer",
    "view.toggle mixer",
    "view.toggle arrange",
    "view.toggle arrange",
    "view.next",
    "view.prev",
    "tabnew",
    "view.focus arrange",
    "tabnext",
    "tabclose",
    "view.only",
    "view.toggle arrange",
    "view.focus arrange",
    "view.focus mixer",
    "view.window arrange",
    "view.maximize",
    "view.equal",
  }) do
    paw.commands.exec(line)
    focus_is_drawn(line)
  end
  -- The same through the Lua calls: hiding the only window leaves one.
  paw.commands.exec("view.only")
  for _, name in ipairs({ "arrange", "mixer", "arrange" }) do
    paw.ui.hide(name)
    focus_is_drawn("ui.hide " .. name)
    paw.ui.focus(name)
    focus_is_drawn("ui.focus " .. name)
  end
end)

test("a command of a bundled extension that is not loaded says how to load it, and :ext.load does", function()
  if paw.ext.loaded.pattern then return "pattern is loaded already" end
  local ok, err = pcall(paw.commands.exec, "pattern.open")
  eq(ok, false, "no command yet")
  eq(err:find("bundled extension that isn't loaded", 1, true) ~= nil, true, err)
  eq(err:find(":ext.load pattern", 1, true) ~= nil, true, "it names the command: " .. err)
  local names = {}
  for _, c in ipairs(paw.commands.complete("ext.load patt")) do
    names[#names + 1] = c.text
  end
  eq(names[1], "ext.load pattern", "bundled names complete: " .. table.concat(names, ","))
  paw.commands.exec("ext.load pattern")
  eq(paw.ext.loaded.pattern ~= nil and paw.ext.loaded.pattern.ok, true, "loaded")
  eq(paw.commands.get("pattern.set") ~= nil, true, "its commands exist")
  paw.commands.exec("ext.load nonesuch")
  eq(last_message():find("no bundled extension", 1, true) ~= nil, true, last_message())
end)

test(
  "panels stacked under the arrange view leave it a third of the rows, and the notation view at most half",
  function()
    fresh()
    if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
    local function heights()
      local out = {}
      for _, r in ipairs(paw.ui.arrange(160, 45)) do
        if r.win then out[r.name] = r.h end
      end
      return out
    end
    -- The panels' places stacked under the arrange view, the whole width.
    paw.layout.restore({
      {
        layout = {
          dir = "v",
          "arrange",
          { view = "roll", hidden = true, weight = 2 },
          { view = "notation", hidden = true, weight = 2 },
          { view = "mixer", hidden = true, weight = 0.5, min = 14 },
        },
      },
    })
    paw.ui.show("pianoroll")
    paw.ui.show("notation")
    paw.ui.show("mixer")
    local h = heights()
    local total = h.arrange + h.pianoroll + h.notation + h.mixer
    eq(h.arrange >= math.floor(total / 3), true, "the arrange view keeps a third: " .. h.arrange .. " of " .. total)
    eq(h.notation <= math.floor(total / 2), true, "the notation view is at most half: " .. h.notation)
    paw.ui.hide("pianoroll")
    h = heights()
    total = h.arrange + h.notation + h.mixer
    eq(
      h.arrange >= math.floor(total / 3) and h.notation <= math.floor(total / 2),
      true,
      "three views: arrange " .. h.arrange .. ", notation " .. h.notation .. ", mixer " .. h.mixer
    )
    paw.ui.hide("mixer")
    h = heights()
    eq(h.arrange < h.notation, true, "with only two, the notation view keeps the larger share it had")
    paw.cmd("view.equal")
    paw.ui.show("mixer")
    h = heights()
    total = h.arrange + h.notation + h.mixer
    eq(h.arrange >= math.floor(total / 3) - 1, true, "after `Ctrl-w =` the arrange view still has its third")
    paw.ui.hide("notation")
    paw.ui.hide("mixer")
  end
)

test("in insert mode a message goes beside the key line instead of hiding it", function()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.keybar.set("arrange", "i", { { "zq", "test key" }, { "<Esc>", "done" } })
  paw.keymap.set_mode("i")
  paw.notify("a message long enough to be seen beside the keys of insert mode, as the notation view says them")
  local rows = api.ui_snapshot(100, 30)
  local last = rows[#rows]
  eq(last:find("test key", 1, true) ~= nil, true, "the keys stay: " .. last)
  eq(last:find("a message long", 1, true) ~= nil, true, "and the message is there: " .. last)
  paw.keymap.set_mode("n")
  paw.ui.keybar.set("arrange", "i", nil)
  paw.ui.message = nil
  rows = api.ui_snapshot(100, 30)
  eq(rows[#rows]:find("a message long", 1, true), nil, "gone with the message")
end)

test("the arrange view draws a volume curve only on the track the cursor is on", function()
  fresh()
  local pad = paw.add_track({ name = "Pad" })
  local lead = paw.add_track({ name = "Lead" })
  lead:add_clip({ start = 0, length = 2, name = "tune", notes = { { pitch = 60, start = 0, length = 1 } } })
  pad:automate("volume"):set_points({ { beat = 0, value = -12 }, { beat = 8, value = 0 } })
  paw.cursor.set_track(lead)
  paw.ui.focus("arrange")
  local braille = "[\240][\159][\172-\175]"
  eq(screen():find(braille) == nil, true, "no curve on a track the cursor is not on")
  paw.cursor.set_track(pad)
  eq(screen():find(braille) ~= nil, true, "the curve of the track the cursor is on")
end)

test(
  "dd on a track names it in the removal of its devices, and the clips above draw their notes as they are",
  function()
    fresh()
    local lead = paw.add_track({ name = "Lead" })
    local pad = paw.add_track({ name = "Pad" })
    local tune =
      lead:add_clip({ start = 0, length = 4, name = "tune", notes = { { pitch = 60, start = 0, length = 1 } } })
    pad:add_device("synth")
    paw.flush()
    api.undo_checkpoint()
    paw.cursor.set_track(lead)
    paw.ui.focus("arrange")
    -- The rows under the clip's name: its small piano roll.
    local function roll()
      local lines = api.ui_snapshot(160, 48)
      for i, line in ipairs(lines) do
        if line:find("tune", 1, true) then return table.concat(lines, "\n", i + 1, i + 2) end
      end
    end
    local before = roll()
    local tracks = {}
    local off = paw.on("device.removed", function(e) tracks[#tracks + 1] = e.track end)
    paw.keymap.feed("<Esc>jdd")
    paw.flush()
    paw.off(off)
    eq(#api.track_list(), 1, "the track the cursor was on is gone")
    eq(table.concat(tracks, " "), tostring(pad.id), "the device's track is named")
    paw.keymap.feed("u")
    paw.flush()
    eq(roll(), before, "the track back: the roll as it was")
    -- The clip's notes change: its small roll draws them, not what was kept.
    api.clip_set_notes(tune.id, { { pitch = 60, start = 2, length = 1 } })
    paw.flush()
    eq(roll() ~= before, true, "the moved note is drawn where it is now")
    paw.keymap.feed("u")
    paw.flush()
    eq(roll(), before, "and back")
  end
)

test(
  "a picker's pane stops saying it is off the moment hearing is turned on, and marks what plays with a note",
  function()
    fresh()
    paw.keymap.feed("<Esc><Esc>")
    if paw.ui.float then paw.ui.close() end
    paw.state["pick.audition.zz uifix"] = false
    paw.pick({
      title = "Sounds",
      audition_key = "zz uifix",
      items = { "one", "two" },
      on_choose = function() end,
      audition = function(item) return "hearing " .. item end,
    })
    local function pane() return table.concat(api.ui_snapshot(120, 30), "\n") end
    eq(pane():find("off · Ctrl-Space hears", 1, true) ~= nil, true, "off to begin with")
    paw.keymap.feed("<C-Space>")
    local text = pane()
    eq(text:find("off · Ctrl-Space hears", 1, true), nil, "on at once")
    eq(text:find("…", 1, true) ~= nil, true, "waiting to hear")
    paw.wait(paw.opt.audition_delay + 200)
    text = pane()
    eq(
      text:find("♪ hearing one", 1, true) ~= nil,
      true,
      "a note marks what plays, the cursor stays an arrow: " .. text
    )
    eq(text:find("▶ hearing", 1, true), nil, "the play mark is not the list cursor")
    paw.keymap.feed("<Esc>")
    paw.state["pick.audition.zz uifix"] = nil
  end
)

test("the mixer's scale and every strip's fader cap agree, whatever the strip holds", function()
  fresh()
  local plain = paw.add_track({ name = "Plain" })
  local with_fx = paw.add_track({ name = "Fx" })
  with_fx:add_device("synth")
  with_fx.volume = -6
  plain.volume = 0
  paw.flush()
  paw.ui.show("mixer")
  paw.ui.focus("mixer")
  local lines = api.ui_snapshot(160, 45)
  local function caps(line) return select(2, line:gsub("━━━", "")) end
  local zero, minus6
  for _, line in ipairs(lines) do
    if line:find("^%s*0%s") and line:find("━━━", 1, true) then zero = line end
    if line:find("^%s*%-6%s") and line:find("━━━", 1, true) then minus6 = line end
  end
  eq(zero ~= nil and caps(zero), 2, "the 0 dB caps (the plain track, the master) are on the row the scale calls 0")
  eq(minus6 ~= nil and caps(minus6), 1, "the -6 dB cap is on the row the scale calls -6")
  -- The cursor's row is lit across the strip, in a colour of its own.
  local theme = require("paw.theme").groups
  eq(
    theme.CursorLine.bg ~= theme.Selected.bg and theme.CursorLine.bg ~= theme.TrackHeaderSel.bg,
    true,
    "brighter than the selected strip it is on"
  )
  paw.ui.hide("mixer")
end)

test(":notation.export takes the focused notation view's clip, else the arrange cursor's, and says which", function()
  fresh()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  local view = require("notation")
  local lead = paw.add_track({ name = "Lead" })
  local drums = paw.add_track({ name = "Drums" })
  local melody = lead:add_clip({
    start = 0,
    length = 4,
    name = "melody",
    notes = { { pitch = 72, start = 0, length = 1 }, { pitch = 74, start = 1, length = 1 } },
  })
  drums:add_clip({ start = 0, length = 4, name = "beat", notes = { { pitch = 36, start = 0, length = 1 } } })
  paw.flush()
  local path = T.scratch .. "/uifix-export.pdf"
  paw.cursor.set_track(lead)
  paw.cursor.set_beat(1)
  paw.commands.exec("notation.export " .. path)
  eq(last_message(), "wrote 'melody' (Lead) to " .. path .. ", 1 page", "the clip under the arrange cursor")
  local f = io.open(path, "rb")
  local pdf = f and f:read("*a") or ""
  if f then f:close() end
  local box = { pdf:match("/MediaBox%s*%[%s*([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)") }
  eq(
    #box == 4 and tonumber(box[4]) < tonumber(box[3]) * 1.2,
    true,
    "a short score does not leave the page's empty foot: " .. table.concat(box, " ")
  )
  os.remove(path)
  paw.cursor.set_track(drums)
  paw.commands.exec("notation.export " .. T.scratch .. "/uifix-export.musicxml")
  eq(last_message():find("'beat' (Drums)", 1, true) ~= nil, true, last_message())
  view:edit(melody)
  paw.ui.focus("notation")
  paw.commands.exec("notation.export " .. T.scratch .. "/uifix-export.musicxml")
  eq(
    last_message():find("'melody' (Lead)", 1, true) ~= nil,
    true,
    "the focused notation view's clip wins over the cursor: " .. last_message()
  )
  os.remove(T.scratch .. "/uifix-export.musicxml")
  paw.ui.focus("arrange")
end)
