-- Frames: when the screen is drawn while the song plays, and how much of
-- it (paw/ui.tl). Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api

local function binary()
  local pipe = io.popen("readlink /proc/" .. api.env().pid .. "/exe")
  local path = pipe:read("*l")
  pipe:close()
  return path
end

test("frames: paw.opt.fps set in init.lua is the ceiling of the frame rate", function()
  local dir = T.scratch .. "/fps-config"
  os.execute("mkdir -p '" .. dir .. "/state'")
  T.write_file(dir .. "/init.lua", "paw.opt.fps = 12\n")
  T.write_file(dir .. "/show.lua", "print('FRAME_MS ' .. paw.ui.frame_ms())\n")
  local pipe = io.popen(
    string.format(
      "XDG_STATE_HOME='%s/state' XDG_DATA_HOME='%s/state' XDG_CACHE_HOME='%s/state' '%s' --config '%s' --no-plugins --no-listen --audio null -l '%s/show.lua' 2>&1",
      dir,
      dir,
      dir,
      binary(),
      dir,
      dir
    )
  )
  local out = pipe:read("*a")
  pipe:close()
  local ms = tonumber(out:match("FRAME_MS ([%d%.]+)"))
  eq(ms and math.floor(ms + 0.5), 83, "1000 / 12 ms between frames, from init.lua: " .. out)
end)

test("frames: :set fps changes the frame rate at once", function()
  local was = paw.opt.fps
  T.after(function() paw.opt.fps = was end)
  paw.commands.exec("set fps=20")
  eq(paw.ui.frame_ms(), 50, "20 frames a second at most")
end)

--- Draw the screen whole at `at`, move the playhead to `to`, draw only the
--- live parts again, and check that each row is the row drawn whole there.
local function same_as_whole(at, to, what)
  local W, H = 120, 40
  paw.transport.position = at
  paw.flush()
  local first = api.ui_frame_snapshot(W, H)
  eq(first.live > 0, true, "the playhead, the meters and the status line are live parts")
  paw.transport.position = to
  local moved = api.ui_frame_snapshot(W, H, true)
  eq(moved ~= nil, true, what .. ": drawn by its live parts only")
  local whole = api.ui_frame_snapshot(W, H)
  local differ = false
  for row = 1, H do
    differ = differ or first.cells[row] ~= whole.cells[row]
  end
  eq(differ, true, what .. ": the playhead moved")
  for row = 1, H do
    eq(
      moved.cells[row],
      whole.cells[row],
      what .. ", row " .. row .. ":\n" .. moved.text[row] .. "\n" .. whole.text[row]
    )
  end
  return moved
end

test("frames: the live parts drawn again are the frame drawn whole", function()
  T.fresh()
  T.tone("Lead", 8)
  T.tone("Bass", 4)
  same_as_whole(1, 5, "the playhead from a clip to past one")
  same_as_whole(5, 0.5, "and back over a clip's name")
end)

test("frames: what is drawn over a live part stays over it", function()
  T.fresh()
  T.tone("Lead", 16)
  paw.ui.view(
    "frames_probe",
    { still = true, render = function(_, buf) buf:fill(0, 0, buf.width, buf.height, "#", "Normal") end }
  )
  T.after(function()
    paw.ui.close()
    paw.ui.views.frames_probe = nil
  end)
  paw.ui.open("frames_probe", { width = 60, height = 20 })
  local moved = same_as_whole(2, 6, "under a float")
  eq(table.concat(moved.text, "\n"):find("####", 1, true) ~= nil, true, "the float shows")
end)

test("frames: between whole frames the status line is drawn again only when a component may have moved", function()
  T.fresh()
  local W, H = 120, 40
  local calls = { still = 0, plain = 0 }
  paw.statusline.component("frames_still", {
    still = true,
    fn = function()
      calls.still = calls.still + 1
      return "S"
    end,
  })
  T.after(function()
    paw.statusline.reset()
    paw.statusline.components.frames_still = nil
  end)
  paw.statusline.setup({ sections = { a = { "frames_still", "transport" } } })
  api.ui_frame_snapshot(W, H)
  local n = calls.still
  eq(api.ui_frame_snapshot(W, H, true) ~= nil, true, "a frame of what moves")
  eq(calls.still, n, "nothing moved: the line keeps its cells")
  paw.transport.position = 3
  api.ui_frame_snapshot(W, H, true)
  eq(calls.still, n + 1, "the playhead moved: the line is drawn again")
  -- A component that says nothing of when it changes runs on each frame.
  local function plain()
    calls.plain = calls.plain + 1
    return "P"
  end
  paw.statusline.setup({ sections = { a = { "frames_still", plain } } })
  api.ui_frame_snapshot(W, H)
  local p = calls.plain
  api.ui_frame_snapshot(W, H, true)
  eq(calls.plain, p + 1, "drawn again with nothing moved")
end)

test("frames: a meter is drawn again exactly when a cell of it changes", function()
  -- The terminal keeps a meter's cells while what it shows stays the same
  -- (paw.draw.meter_shown): a level that falls by less than a cell.
  local function cells(draw_it)
    local out = {}
    draw_it({
      text = function(_, x, _, s, style)
        out[x + 1] = s .. "/" .. tostring(style)
        return 1
      end,
    })
    return table.concat(out, " ")
  end
  local draw = paw.draw
  local width = 16
  local last_cells, last_shown
  for step = 0, 400 do
    local peak = 10 ^ (-step / 400 * 3.2) -- 0 dB down to -64 dB
    local hold = step % 50 == 0 and 1 or 10 ^ (-step / 800)
    local now_cells = cells(function(b) draw.meter(b, 0, 0, width, peak, hold) end)
      .. "|"
      .. cells(function(b) draw.stereo_meter(b, 0, 0, width, peak, peak * 0.7) end)
    local now_shown = draw.meter_shown(width, peak, hold) .. "|" .. draw.stereo_meter_shown(width, peak, peak * 0.7)
    if last_cells then eq(now_shown ~= last_shown, now_cells ~= last_cells, "step " .. step .. ": " .. now_shown) end
    last_cells, last_shown = now_cells, now_shown
  end
end)

test("frames: a view that does not say what moves in it is drawn whole", function()
  T.fresh()
  paw.ui.view("frames_moving", { render = function(_, buf) buf:text(0, 0, tostring(paw.transport.position)) end })
  T.after(function()
    paw.ui.close()
    paw.ui.views.frames_moving = nil
  end)
  paw.ui.open("frames_moving", { width = 30, height = 6 })
  api.ui_frame_snapshot(120, 40)
  eq(api.ui_frame_snapshot(120, 40, true), nil, "no frame of the live parts only")
end)

test("frames: a track that listens to its input keeps the meters moving while the song is stopped", function()
  T.fresh()
  local gtr = paw.add_track({ name = "Guitar" })
  gtr.input = "1"
  gtr.armed = true
  -- Past the moment that any key keeps the screen live.
  local t0 = api.now()
  T.until_(function() return api.now() > t0 + 2000 end, "two seconds with no key")
  eq(api.transport_get().playing, false, "the song is stopped")
  eq(paw.ui.active(), true, "an armed input is live")
  gtr.armed = false
  gtr.monitor = true
  eq(paw.ui.active(), true, "a monitored input is live")
  gtr.monitor = false
  T.until_(function() return not paw.ui.active() end, "the frames to end with no input listened to", 5000)
end)

test("frames: a row of the timeline the cursor is not on shows each change to its clips and colours", function()
  -- Such a row puts back the cells it drew last when nothing it is drawn
  -- from changed (paw/views/arrange.lua): each change must still show.
  T.fresh()
  local W, H = 120, 40
  local one, two = paw.add_track({ name = "one" }), paw.add_track({ name = "two" })
  one:add_clip({ name = "first", start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  two:add_clip({ name = "second", start = 0, length = 4, notes = { { pitch = 64, start = 0, length = 1 } } })
  paw.flush()
  paw.keymap.feed("<Esc>gg")
  local function frame() return api.ui_frame_snapshot(W, H) end
  --- The screen's row that shows `text`.
  local function row_with(drawn, text)
    for i, line in ipairs(drawn.text) do
      if line:find(text, 1, true) then return i end
    end
  end
  frame()
  eq(row_with(frame(), "second") ~= nil, true, "the other track's clip is drawn")
  two:clips()[1].name = "renamed"
  local drawn = frame()
  local row = row_with(drawn, "renamed")
  eq(row ~= nil, true, "a new name shows")
  local was = paw.opt.termcolors
  T.after(function() paw.opt.termcolors = was end)
  paw.opt.termcolors = paw.draw.truecolor() and "256" or "true"
  eq(frame().cells[row] ~= drawn.cells[row], true, "new colours show")
end)
