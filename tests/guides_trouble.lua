-- The how-to guides of the user guide for when something goes wrong, each
-- driven with the keys and commands that it gives (docs/how-to/fix-no-sound.md,
-- fix-crackles-and-dropouts.md, deal-with-a-plugin-that-crashes.md,
-- run-the-window-without-a-graphics-card.md). Loaded
-- by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local keys = T.keys

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
end

--- The messages after the message `from` (the last one when the test began,
--- see `mark`), as one text. The list keeps the last 500 messages, so a
--- place in it moves; the message itself does not.
local function said(from)
  local out, seen = {}, from == nil
  for _, m in ipairs(paw.ui.messages) do
    if seen then out[#out + 1] = m.text end
    if m == from then seen = true end
  end
  return table.concat(out, "\n")
end

--- The last message now, for `said`.
local function mark() return paw.ui.messages[#paw.ui.messages] end

test("guide: fix no sound", function()
  start()
  local before = mark()
  keys(":engine<CR>")
  eq(said(before):find("^null: none") ~= nil, true, ":engine names the backend and the output device: " .. said(before))
  local lead = T.tone("Lead", 8)
  local keys_track = paw.add_track({ name = "Keys" })
  keys_track:add_clip({ start = 0, length = 8, notes = { { pitch = 64, start = 0, length = 8 } } })
  lead.mute = true
  keys_track.solo = true
  paw.flush()
  eq(T.render({ tail = 0 }).peak, 0, "nothing plays")
  keys(":t* unmute<CR>")
  keys(":t* unsolo<CR>")
  eq(lead.mute or keys_track.solo, false, ":t* unmute and :t* unsolo clear them")
  eq(T.render({ tail = 0 }).peak > 0, true, "the lead plays again")
  paw.ui.focus("arrange")
  paw.cursor.set_track(keys_track)
  lead.mute = true
  paw.flush()
  eq(T.render({ tail = 0 }).peak, 0, "a MIDI track with no instrument plays nothing")
  local header = table.concat(api.ui_snapshot(100, 30), "\n")
  eq(header:find("Synth", 1, true) ~= nil, true, "the header of the lead names its instrument")
  keys("aSynth<CR>")
  eq(T.render({ tail = 0 }).peak > 0, true, "a adds an instrument, and the notes play")
end)

test("guide: fix crackles and dropouts", function()
  start()
  local before = mark()
  keys(":engine.status<CR>")
  eq(said(before):find("xruns", 1, true) ~= nil, true, ":engine.status counts the xruns: " .. said(before))
  T.after(function() paw.audio.use({ buffer = 0 }) end)
  keys(":audio.buffer 1024<CR>")
  eq(api.engine_get().block, 1024, ":audio.buffer sets a larger block")
  T.after(function() paw.opt.threads = 0 end)
  keys(":engine threads=2<CR>")
  T.until_(function() return api.engine_get().threads == 2 end, "the engine to use two threads", 3000)
  local heavy = T.tone("Heavy", 8)
  paw.ui.focus("arrange")
  paw.cursor.set_track(heavy)
  keys(":freeze<CR>")
  eq(said(before):find("frozen: Heavy", 1, true) ~= nil, true, ":freeze renders the heavy track")
end)

test("guide: deal with a plugin that crashes or hangs", function()
  start()
  -- A device in a process of its own stands for the plugin.
  local scripts = T.scratch .. "/guide-plugin"
  os.execute("mkdir -p '" .. scripts .. "'")
  T.write_file(
    scripts .. "/guide_fx.lua",
    "local dev = require('paw.dsp').device { name = 'Guide FX' }\n" .. "function dev.process(b) end\nreturn dev\n"
  )
  paw.luadev.add_dir(scripts)
  local d = T.scratch .. "/guide-plugin"
  local lead = T.tone("Lead", 8)
  paw.ui.focus("arrange")
  paw.cursor.set_track(lead)
  keys("aGuide FX<CR>")
  local fx = lead:devices()[2]
  eq(fx.kind, "lua:guide_fx", "the effect is on the track")
  local before = mark()
  local pid = tonumber(api.device_call(fx.id, "sandbox.pid"))
  os.execute("kill -KILL " .. pid)
  T.until_(function() return fx:get().stopped ~= nil end, "the crash to be told", 5000)
  eq(
    said(before):find("Guide FX on Lead stopped working: it was killed", 1, true) ~= nil,
    true,
    "a message names the device and why"
  )
  eq(T.render({ tail = 0 }).peak > 0, true, "the track plays on without the effect")
  -- A save while it is stopped (the autosave too) keeps the state it had.
  before = mark()
  paw.project.save(d .. "/crashed.json")
  paw.flush()
  eq(said(before):find("could not save plugin state", 1, true), nil, "a save says nothing more of the crash")
  keys("<Space>dd")
  keys("w")
  keys("gR")
  T.until_(function() return fx:get().stopped == nil end, "the restart", 5000)
  eq(fx:get().status, "running", "gR in the device panel starts it again")
  before = mark()
  keys("o")
  eq(fx:get().offline, true, "o sets it offline")
  eq(said(before):find("could not save plugin state", 1, true), nil, "and says nothing of the crash before the restart")
  keys("o")
  eq(fx:get().offline, false, "and o again online")
  paw.ui.focus("arrange")
  keys(":w " .. d .. "/song<CR>")
  before = mark()
  keys(":edit " .. d .. "/song offline<CR>")
  eq(
    said(before):find("opened with every plugin offline", 1, true) ~= nil,
    true,
    ":edit song.json offline opens it with the plugins offline"
  )
end)

--- The text of the page `:checkhealth` opened.
local function page()
  local lines = {}
  for _, line in ipairs(paw.ui.views:get("pager").lines) do
    lines[#lines + 1] = line.text
  end
  return table.concat(lines, "\n")
end

test("guide: run the window without a graphics card, then on the card again", function()
  start()
  local was = paw.frontend.window_renderer
  -- The window started on the processor because PAW_GUI_RENDERER asked.
  local before = mark()
  paw.frontend.window_renderer_set({
    renderer = "llvmpipe (LLVM 19.1.7, 256 bits)",
    version = "4.5",
    software = true,
    cause = "asked",
  })
  keys(":set window_fps=10<CR>")
  eq(paw.frontend.state(-1).window_fps, 10, "fewer frames a second")
  paw.opt.window_fps = "auto"
  eq(
    said(before):find("The window draws on the processor", 1, true) ~= nil,
    true,
    "a warning when it starts: " .. said(before)
  )
  keys(":checkhealth window<CR>")
  eq(page():find("- WARN the window draws on the processor", 1, true) ~= nil, true, ":checkhealth window: " .. page())
  eq(page():find("    - PAW_GUI_RENDERER=software", 1, true) ~= nil, true, "the likely cause first")
  paw.ui.close()
  -- Started again without the variable: on the card.
  paw.frontend.window_renderer_set({ renderer = "AMD Radeon 890M (radeonsi)", version = "4.6", software = false })
  keys(":checkhealth window<CR>")
  eq(page():find("- OK the window draws on the graphics card", 1, true) ~= nil, true, "OK on the card: " .. page())
  paw.ui.close()
  paw.frontend.window_renderer = was
end)
