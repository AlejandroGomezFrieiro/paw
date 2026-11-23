-- Tests of the device panel (paw/views/devices.lua) as one view for both
-- frontends: its buttons, menus, sliders and sends worked by the pointer in
-- the terminal's cells, and its scene as a window gets it, the widget roles
-- painted there, a press coming back in fractions of a cell, and a
-- parameter that a lane moves bound to the live values.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api
local panel = paw.ui.views:get("devices")

local W, H, CELL = 140, 44, { w = 8, h = 16 }
local ROLES = { "label", "button", "switch", "knob", "fader", "meter", "peak", "chip", "param", "power", "band" }

local function m(kind, x, y, button, mods)
  paw.ui.mouse({ kind = kind, x = x, y = y, button = button or "left", mods = mods or "" })
end
local function click(x, y, button, mods)
  m("down", x, y, button, mods)
  m("up", x, y, button, mods)
  paw.mouse.forget()
end

--- The panel shown with the cursor on `part`: its rectangle on the
--- screen, and the screen's lines.
local function shown(part)
  paw.cursor.set_part(part)
  paw.ui.show("devices")
  local lines = api.ui_snapshot(W, H)
  for _, r in ipairs(paw.ui.rects) do
    if r.name == "devices" then return r, lines end
  end
end

--- The screen row of the panel's row `index`.
local function row_y(rect, index) return rect.y + 1 + index - 1 - panel.scroll end

--- The column of the first `text` on screen line `y` at or after the
--- panel's left edge, in cells.
local function column(lines, rect, y, text)
  local line = lines[y + 1]
  local cells, x = {}, 0
  for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    cells[#cells + 1] = { ch = ch, x = x }
    x = x + api.str_width(ch)
  end
  local want = {}
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    want[#want + 1] = ch
  end
  for i = 1, #cells - #want + 1 do
    if cells[i].x >= rect.x then
      local same = true
      for j = 1, #want do
        if cells[i + j - 1].ch ~= want[j] then
          same = false
          break
        end
      end
      if same then return cells[i].x end
    end
  end
end

--- The row of the panel that is device `id`'s heading.
local function heading_of(id)
  for i, row in ipairs(panel:rows()) do
    if row.device.id == id and not row.param and not row.picture then return i end
  end
end

local function done()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  require("paw.menu").close(0)
  paw.mouse.forget()
  api.scene_forget(0)
  paw.ui.hide("devices")
end

test("the device panel's buttons move a device along the chain and remove it, in the terminal", function()
  fresh()
  T.after(done)
  local t = paw.add_part({ name = "Keys" })
  local synth, delay = t:add_device("synth"), t:add_device("delay")
  local rect, lines = shown(t)
  local y = row_y(rect, heading_of(delay.id))
  local up = column(lines, rect, y, paw.draw.g.move_up)
  eq(up ~= nil, true, "the heading has its buttons: " .. lines[y + 1])
  click(up, y)
  eq(t:get().devices[1], delay.id, "↑ moves the delay before the synth")
  rect, lines = shown(t)
  y = row_y(rect, heading_of(synth.id))
  click(column(lines, rect, y, paw.draw.g.remove), y)
  eq(#t:get().devices, 1, "× removes the synth")
  eq(t:get().devices[1], delay.id, "and leaves the delay")
end)

test("a click on a device's preset caret opens its presets; + add a device opens the picker", function()
  fresh()
  T.after(done)
  local t = paw.add_part({ name = "Keys" })
  local synth = t:add_device("synth")
  local rect, lines = shown(t)
  local y = row_y(rect, heading_of(synth.id))
  -- The caret after its name: no preset is loaded.
  click(column(lines, rect, y, "Synth " .. paw.draw.g.open) + 6, y)
  local items = require("paw.menu").shown()
  local labels = {}
  for _, item in ipairs(items or {}) do
    labels[#labels + 1] = type(item) == "table" and item.label or item
  end
  eq(
    table.concat(labels, "|"):find("Save as a preset…", 1, true) ~= nil,
    true,
    "the menu of presets: " .. table.concat(labels, "|")
  )
  require("paw.menu").close(0)
  rect, lines = shown(t)
  local foot = rect.y + 1 + panel.geometry.foot
  eq(lines[foot + 1]:find("+ add a device", 1, true) ~= nil, true, "the add line under the chain")
  click(column(lines, rect, foot, "+ add"), foot)
  local pick = paw.pick.state()
  eq(pick and pick.title, "Add a device", "the picker of devices")
end)

test("the panel's foot: where the part plays into, its sends with their level, pre and remove", function()
  fresh()
  T.after(done)
  local a = paw.add_part({ name = "Alto" })
  local verb = paw.add_part({ name = "Verb" })
  a:add_device("synth")
  a:send(verb, -10)
  local rect, lines = shown(a)
  local foot = rect.y + 1 + panel.geometry.foot
  local out_y, send_y = foot + 1, foot + 2
  eq(lines[out_y + 1]:find("→ Master", 1, true) ~= nil, true, "the output: " .. lines[out_y + 1])
  click(column(lines, rect, out_y, "→"), out_y)
  local items = require("paw.menu").shown()
  eq(items and items[1].label, "Master", "a click offers where it could play into")
  require("paw.menu").close(0)
  click(column(lines, rect, out_y, "+ send"), out_y)
  items = require("paw.menu").shown()
  eq(items ~= nil and #items >= 2, true, "+ send offers the parts to send to")
  require("paw.menu").close(0)
  -- The send's slider: its last cell is nearly the top of its travel.
  local name_w = math.min(10, math.max(4, rect.w - 26))
  local bar = math.max(3, math.max(4, rect.w - name_w - 9) - 9)
  click(rect.x + name_w + 2 + bar - 1, send_y)
  near(a:get().sends[1].level, (1 - 0.5 / bar) * 66 - 60, 0.01, "the last cell of the send's slider")
  rect, lines = shown(a)
  click(column(lines, rect, send_y, "pre"), send_y)
  eq(a:get().sends[1].pre, true, "pre takes the send before the fader")
  rect, lines = shown(a)
  click(column(lines, rect, send_y, paw.draw.g.remove), send_y)
  eq(#a:get().sends, 0, "× removes the send")
end)

test("on another part, j goes from the panel's first device to its first parameter", function()
  fresh()
  T.after(done)
  local a, b = paw.add_part({ name = "A" }), paw.add_part({ name = "B" })
  a:add_device("synth")
  b:add_device("saturation")
  shown(a)
  paw.ui.focus("devices")
  T.keys("jjj")
  paw.cursor.set_part(b)
  T.keys("j")
  local row = panel:rows()[panel.row]
  eq(row.param and row.param.key, "drive", "the row under the first device of B, not one below the row on A")
end)

test("Ctrl and the wheel nudge a parameter, the wheel alone moves the row; A automates it and L learns it", function()
  fresh()
  T.after(function() paw.learn.cancel() end)
  T.after(done)
  local t = paw.add_part({ name = "Keys" })
  local synth = t:add_device("synth")
  local rect = shown(t)
  local index = heading_of(synth.id) + 1
  local row = panel:rows()[index]
  local p, y = row.param, row_y(rect, index)
  local lay = panel.layout(rect.w)
  local before = api.device_get(synth.id).params[p.key]
  m("scroll_up", rect.x + lay.bar_at + 1, y, "", "C")
  eq(api.device_get(synth.id).params[p.key] ~= before, true, "Ctrl and the wheel up change it")
  eq(panel.row, index, "on the row under the pointer")
  m("scroll_down", rect.x + 1, y, "", "")
  eq(panel.row, index + 1, "the wheel alone moves the row")
  eq(lay.tools ~= nil, true, "a wide panel has its automate and learn buttons")
  local _, lines = shown(t)
  y = row_y(rect, index)
  eq(lines[y + 1]:sub(-6):find("A", 1, true) ~= nil, true, "A on the row: " .. lines[y + 1])
  click(rect.x + lay.tools, y)
  local lane
  for _, l in ipairs(api.lane_list(t.id)) do
    if l.target == "param" and l.param == p.key then lane = l end
  end
  eq(lane ~= nil, true, "A gives the parameter a lane")
  click(rect.x + lay.tools + 2, y)
  eq(paw.learn.learning ~= nil and paw.learn.learning.param, p.key, "L waits for a controller for it")
end)

test("a device's name dragged down the panel moves it after the device it is let go on", function()
  fresh()
  T.after(done)
  local t = paw.add_part({ name = "Keys" })
  local gain = t:add_device("gain")
  local delay = t:add_device("delay")
  local rect = shown(t)
  local from = row_y(rect, heading_of(gain.id))
  local to = row_y(rect, heading_of(delay.id))
  m("down", rect.x + 4, from)
  m("drag", rect.x + 4, from + 1)
  m("drag", rect.x + 4, to)
  m("up", rect.x + 4, to)
  eq(t:get().devices[2], gain.id, "the gain after the delay")
end)

-- In a window ------------------------------------------------------------------------------

--- The panel's scene for a window that paints the widget roles, `w` by
--- `h` cells, as the kernel sends it; the patch, decoded.
local function scene(w, h)
  paw.ui.render_scene("devices", w or 50, h or 40, CELL)
  local patch = api.scene_end(0, "devices")
  return patch and api.json_decode(patch)
end

local function nodes(patch, role)
  local out = {}
  for _, n in ipairs(patch and patch.set or {}) do
    if n.role == role then out[#out + 1] = n end
  end
  return out
end

test("in a window the panel is its scene: a band, a name and a power button a device, a slider a parameter", function()
  fresh()
  T.after(done)
  local t = paw.add_part({ name = "Keys" })
  local synth = t:add_device("synth")
  paw.cursor.set_part(t)
  api.scene_forget(0)
  api.scene_roles(0, ROLES)
  local patch = scene()
  eq(panel:title_of(), "Devices · Keys · 1 device", "the window's title over it names the part")
  eq(#nodes(patch, "band"), 1, "the device's heading is a band")
  eq(#nodes(patch, "power"), 1, "with its power button")
  local params = nodes(patch, "param")
  eq(#params, #api.device_get(synth.id).param_info, "a slider for each parameter")
  eq(params[1].hit.kind, "param", "which takes the pointer")
  -- A press in the middle of the first slider, in a window's fractions of a cell.
  local index = heading_of(synth.id) + 1
  local p = panel:rows()[index].param
  local r = params[1].r
  local bar = params[1].hit.bar
  local held = {}
  eq(
    paw.roles.input(
      0,
      "devices",
      panel,
      nil,
      { kind = "down", x = r[1] + bar / 2, y = r[2] + 0.5, button = "left" },
      held
    ),
    true,
    "the slider takes the press"
  )
  paw.roles.input(0, "devices", panel, nil, { kind = "up", x = r[1] + bar / 2, y = r[2] + 0.5, button = "left" }, held)
  near(
    paw.params.fraction(p, api.device_get(synth.id).params[p.key]),
    0.5,
    0.01,
    "halfway along it, halfway along the range"
  )
  eq(panel.row, index, "and the row is chosen")
  -- The power button bypasses the device.
  local power = nodes(patch, "power")[1]
  paw.mouse.forget()
  paw.roles.input(
    0,
    "devices",
    panel,
    nil,
    { kind = "down", x = power.r[1] + 1, y = power.r[2] + 0.5, button = "left" },
    held
  )
  paw.roles.input(
    0,
    "devices",
    panel,
    nil,
    { kind = "up", x = power.r[1] + 1, y = power.r[2] + 0.5, button = "left" },
    held
  )
  eq(api.device_get(synth.id).bypass, true, "the power button bypasses it")
end)

test("a parameter a lane moves is bound to the live values: the song moves it with no new scene", function()
  fresh()
  T.after(function() api.transport_seek(0) end)
  T.after(done)
  local t = paw.add_part({ name = "Keys" })
  local synth = t:add_device("synth")
  paw.cursor.set_part(t)
  local p
  for _, row in ipairs(panel:rows()) do
    if row.param and row.device.id == synth.id and #row.param.choices == 0 and not row.host then
      p = row.param
      break
    end
  end
  local lane = paw.device(synth.id):automate(p.key)
  lane:add(0, p.min)
  lane:add(4, p.max)
  api.transport_seek(0)
  api.scene_forget(0)
  api.scene_roles(0, ROLES)
  local bind = "param:" .. synth.id .. ":" .. p.key
  local patch = scene()
  local found
  for _, n in ipairs(nodes(patch, "param")) do
    if n.bind == bind then found = n end
  end
  eq(found ~= nil, true, "the slider is bound to its parameter")
  eq(found.props.fraction, nil, "and is sent without where it sits")
  eq(found.props.bar ~= nil, true, "but with its slider's length")
  near(paw.scene.live().params[bind].fraction, 0, 1e-3, "the live values say where the lane has it")
  api.transport_seek(2)
  local at = paw.scene.live().params[bind]
  near(paw.params.fraction(p, api.lane_value_at(lane.id, 2)), at.fraction, 1e-3, "two beats on, where the lane is then")
  eq(at.text, paw.frontend.format_value(p, api.lane_value_at(lane.id, 2)), "with its value as text")
  eq(scene(), nil, "and the scene is the same")
  -- The terminal shows the lane's value too.
  local _, lines = shown(t)
  local screen = table.concat(lines, "\n")
  eq(screen:find(at.text, 1, true) ~= nil, true, "the terminal reads " .. at.text)
end)
