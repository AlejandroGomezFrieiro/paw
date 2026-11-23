-- Tests of the mixer's strips (paw/views/mixer.lua): where a part plays
-- into, four devices, the clip light and the peak a click clears, in the
-- terminal's cells and in a window's scene; and a mixer that plays sends
-- the window its meters as live values, never as a new scene.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local W, H = 120, 90
local mixer = paw.ui.views:get("mixer")

local function m(kind, x, y) paw.ui.mouse({ kind = kind, x = x, y = y, button = "left", mods = "" }) end
local function click(x, y)
  m("down", x, y)
  m("up", x, y)
  paw.mouse.forget()
end

local function mixer_node()
  local function find(node)
    if node.view == "mixer" then return node end
    for _, child in ipairs(node) do
      local found = find(child)
      if found then return found end
    end
  end
  return find(paw.ui.layout)
end

-- The mixer's size in the layout before these tests, put back by the last.
local size

--- The mixer shown `height` rows tall in a terminal, with the cursor on
--- `part`: its first strip's pieces, a function from the strip's own cells
--- to the screen's, and the screen as text.
local function shown(part, height)
  paw.cursor.set_part(part)
  paw.ui.show("mixer")
  local node = mixer_node()
  if size == nil then size = node.size or false end
  node.size = height
  local lines = api.ui_snapshot(W, H)
  local rect
  for _, r in ipairs(paw.ui.rects) do
    if r.name == "mixer" then rect = r end
  end
  local s = mixer.geometry.strips[1]
  return s, function(x, y) return rect.x + x, rect.y + 1 + y end, table.concat(lines, "\n"), lines
end

local function done()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  mixer_node().size = size or nil
  paw.ui.hide("mixer")
end

--- Run `fn` with every part's meter reading `left` and `right`.
local function metered(left, right, fn)
  local meter = api.part_meter
  api.part_meter = function() return left, right end
  local ok, err = pcall(fn)
  api.part_meter = meter
  if not ok then error(err, 0) end
end

test("a mixer strip says where its part plays into, and a click there offers the parts to choose from", function()
  fresh()
  local a = paw.add_part({ name = "Alto" })
  local bus = paw.add_part({ name = "Bus" })
  a.output = bus
  -- The meters show silence: the sound of a test before has fallen.
  T.until_meters_at_rest()
  local s, at = shown(a, 30)
  -- Each strip names the part it plays into: Bus, Master, out.
  T.expect_screen("outputs", W, H, { rows = { 59, 88 } })
  click(at(s.x + 2, s.output))
  local pick = paw.pick.state()
  eq(pick and pick.title, "Output of Alto", "a click offers where it could play into")
  done()
end)

test("a mixer strip names four devices, the last counting those it has no room for, and a click picks one", function()
  fresh()
  local a = paw.add_part({ name = "Alto" })
  for _ = 1, 6 do
    a:add_device("gain")
  end
  local s, at, screen = shown(a, 30)
  eq(s.slots, 4, "four rows for devices")
  eq(screen:find("+3 more", 1, true) ~= nil, true, "the fourth counts the three it has no room for")
  local _, _, short = shown(a, 18)
  eq(mixer.geometry.strips[1].slots, nil, "a short strip folds them into one row")
  eq(short:find("6 ", 1, true) ~= nil, true, "which counts them")
  s, at = shown(a, 30)
  click(at(s.x + 2, s.devices + 3))
  eq(paw.ui.focused, "devices", "a click on the fourth row picks the fourth device")
  eq(paw.ui.views:get("devices"):selected().id, a:get().devices[4], "in the device panel")
  -- The keyboard's cursor on the sixth device: the fourth row names it.
  paw.ui.focus("mixer")
  paw.mixer_rows.to(6)
  eq(paw.mixer_rows.current().index, 6, "the cursor on the sixth device")
  local _, _, named = shown(a, 30)
  eq(named:find("+3 more", 1, true), nil, "the fourth row names it instead of counting")
  done()
end)

test("a meter at full scale lights the clip light, and a click on the peak or the light puts it out", function()
  fresh()
  local a = paw.add_part({ name = "Alto" })
  local s, at, _, lines
  metered(1.0, 0.5, function()
    s, at, _, lines = shown(a, 30)
  end)
  local x, y = at(s.x + 1, s.fader)
  eq(lines[y + 1]:find("▀", 1, true) ~= nil, true, "the clip light on top of the meters")
  local _, clipped = select(3, paw.draw.part_peak(a.id))
  eq(clipped, true, "lit")
  eq(paw.scene.live().clips[tostring(a.id)], true, "and a window is told so with the live values")
  -- The peak readout, at the strip's right under the fader.
  click(at(s.x + s.w - 2, s.fader + s.rows))
  local hold, out = select(3, paw.draw.part_peak(a.id))
  eq(out, false, "a click on the peak puts it out")
  eq(hold, 0, "and the peak falls")
  metered(1.0, 1.0, function() paw.draw.part_peak(a.id) end)
  click(x, y)
  eq(select(4, paw.draw.part_peak(a.id)), false, "so does a click on the light")
  done()
end)

test("in a window the clip light goes out at a click on the peak, as in the terminal", function()
  fresh()
  local a = paw.add_part({ name = "Alto" })
  paw.cursor.set_part(a)
  api.scene_forget(0)
  api.scene_roles(0, { "label", "button", "switch", "knob", "fader", "meter", "peak", "chip" })
  metered(1.0, 1.0, function() paw.ui.render_scene("mixer", 80, 30, { w = 8, h = 16 }) end)
  api.scene_end(0, "mixer")
  local s = mixer.geometry.strips[1]
  eq(select(4, paw.draw.part_peak(a.id)), true, "lit")
  local held = {}
  eq(
    paw.roles.input(
      0,
      "mixer",
      mixer,
      nil,
      { kind = "down", x = s.x + s.w - 1.5, y = 1 + s.fader + s.rows + 0.5, button = "left" },
      held
    ),
    true,
    "the peak takes the click"
  )
  eq(select(4, paw.draw.part_peak(a.id)), false, "and puts out the light")
  api.scene_forget(0)
end)

test("a mixer that plays sends its meters, peaks and clip lights as live values and no new scene", function()
  fresh()
  local a = paw.add_part({ name = "Alto" })
  paw.cursor.set_part(a)
  api.scene_forget(0)
  api.scene_roles(0, { "label", "button", "switch", "knob", "fader", "meter", "peak", "chip" })
  local function frame(left, right)
    local patch
    metered(left, right, function()
      paw.ui.render_scene("mixer", 80, 30, { w = 8, h = 16 })
      patch = api.scene_end(0, "mixer")
    end)
    return patch
  end
  eq(frame(0.1, 0.1) ~= nil, true, "the first scene")
  eq(frame(0.5, 0.4), nil, "louder: nothing new in the scene")
  eq(frame(1.0, 1.0), nil, "clipping: nothing new either")
  local live = paw.scene.live()
  eq(live.clips[tostring(a.id)], true, "the clip light is a live value")
  eq(live.peaks[tostring(a.id)], 1, "so is the peak")
  -- A frontend that does not paint the roles is sent their cells, which move.
  api.scene_roles(0, {})
  api.scene_forget(0, "mixer")
  frame(0.1, 0.1)
  eq(frame(0.5, 0.4) ~= nil, true, "cells move with the meters")
  api.scene_forget(0)
end)
