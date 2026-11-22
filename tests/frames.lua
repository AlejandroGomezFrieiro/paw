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
