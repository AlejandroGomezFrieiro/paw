-- Tests of roles (paw/roles.tl): what a view marks on its buffer is drawn
-- in cells by the role in a terminal, sent as the role to a window that
-- paints it, and a hit region on it takes the pointer the same from both.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api

paw.ui.role("roles_test_bar", {
  props = { amount = "number 0..1" },
  cells = function(buf, p)
    buf:fill(0, 0, math.floor(buf.width * p.amount + 0.5), 1, "#", "Title")
  end,
})

-- What the gestures of the test view were given.
local seen = {}
paw.ui.view("zz_roles", {
  render = function(_, buf)
    buf:fill(0, 0, buf.width, buf.height, " ", "Normal")
    buf:text(0, 0, "bars", "Title")
    buf:mark("roles_test_bar", 2, 1, 10, 1, { amount = 0.5, hit = { kind = "bar", n = 1 }, key = "bar1" })
    buf:hit(0, 3, 6, 1, { kind = "row", hint = "a row to press" })
    buf:hit(8, 3, 6, 1, { cmd = "set grid=0.5" })
  end,
  gestures = {
    bar = function(_, e)
      seen[#seen + 1] = e
      if e.kind == "down" then
        paw.mouse.grab(e, { drag = function(d) seen.dy = d.dy end, up = function(u) seen.up = u end })
      end
    end,
  },
})

paw.ui.dock("zz_roles", { side = "bottom", hidden = true })

local W, H = 30, 6

--- The view's scene for a window, as the patch that makes it, decoded.
local function scene(id)
  api.scene_forget(0, id)
  paw.ui.render_scene("zz_roles", W, H, { w = 8, h = 16 })
  return api.json_decode(api.scene_end(0, id))
end

local function node(patch, key)
  for _, n in ipairs(patch.set) do
    if n.k == key then return n end
  end
end

test("a role mark draws its cells in a terminal and is a role with its props in a scene", function()
  fresh()
  local function row(snap, y)
    local text = ""
    for _, run in ipairs(snap.rows[y + 1]) do text = text .. run.text end
    return text
  end
  eq(row(api.ui_view_snapshot("zz_roles", W, H), 1):sub(1, 8), "  ##### ", "the role's cells where it was marked")
  local patch = scene("roles")
  local bar = node(patch, "bar1")
  eq(bar.t, "role", "a role node")
  eq(bar.role, "roles_test_bar")
  eq(bar.props.amount, 0.5, "with its props")
  eq(bar.hit.kind, "bar", "and its hit region")
  eq(api.json_encode(bar.r), "[2,1,10,1]", "over the rectangle marked")
  eq(#(bar.kids or {}) > 0, true, "its cells under it, for a frontend that does not know it")
  eq(row(api.scene_cells(0, "roles"), 1):sub(1, 8), "  ##### ", "which lowered to cells are the terminal's")
  api.scene_forget(0)
end)

test("a frontend that paints a role is sent it without its cells", function()
  fresh()
  api.scene_roles(0, { "roles_test_bar" })
  local patch = scene("roles")
  local bar = node(patch, "bar1")
  api.scene_forget(0)
  eq(bar.kids, nil, "no cells")
  for _, n in ipairs(patch.set) do eq(n.k:match("^bar1/") , nil, "nothing of its cells: " .. n.k) end
end)

test("a role is defined with its cells, and marking one there is not is an error", function()
  eq(pcall(paw.ui.role, "roles_test_none", {}), false, "a role without cells")
  eq(paw.ui.roles.fader ~= nil and paw.ui.roles.meter ~= nil and paw.ui.roles.switch ~= nil, true, "the widgets are roles")
  local ok, err = pcall(paw.ui.Buf.mark, paw.ui.Buf.root(4, 1), "roles_test_nothing", 0, 0, 1, 1)
  eq(ok, false)
  eq(tostring(err):find("no role roles_test_nothing", 1, true) ~= nil, true, tostring(err))
end)

test("a hit region takes a press in the terminal in cells and in a window in units, alike", function()
  fresh()
  paw.ui.show("zz_roles")
  api.ui_snapshot(80, 30)
  local rect
  for _, r in ipairs(paw.ui.rects) do if r.name == "zz_roles" then rect = r end end
  seen = {}
  -- The terminal: a press on the bar's third cell, a drag two rows down.
  paw.ui.mouse({ kind = "down", x = rect.x + 4, y = rect.y + 1, button = "left", mods = "" })
  paw.ui.mouse({ kind = "drag", x = rect.x + 4, y = rect.y + 3, button = "left", mods = "" })
  paw.ui.mouse({ kind = "up", x = rect.x + 4, y = rect.y + 3, button = "left", mods = "" })
  eq(#seen, 1, "the bar's gesture")
  eq(seen[1].hit.n, 1, "with the hit region's action")
  eq(seen[1].x == 4 and seen[1].rect.x == 2 and seen[1].rect.w == 10, true, "in the view's cells")
  eq(seen[1].fine, nil, "whole cells")
  eq(seen.dy, 2, "the drag in cells")
  paw.ui.hide("zz_roles")
  -- A window: the same press, in units, on the scene it was sent.
  scene("roles")
  seen = {}
  local held = {}
  eq(paw.roles.input(0, "roles", paw.ui.views.zz_roles, nil, { kind = "down", x = 4.5, y = 1.25, button = "left" }, held), true)
  eq(paw.roles.input(0, "roles", paw.ui.views.zz_roles, nil, { kind = "move", x = 4.5, y = 2.75 }, held), true, "the drag")
  eq(paw.roles.input(0, "roles", paw.ui.views.zz_roles, nil, { kind = "up", x = 4.5, y = 2.75 }, held), true)
  eq(#seen, 1, "the bar's gesture")
  eq(seen[1].fine and seen[1].x == 4.5 and seen[1].hit.n == 1, true, "in units, with the same action")
  eq(seen[1].rect.x == 2 and seen[1].rect.w == 10, true, "the region as the terminal has it")
  near(seen.dy, 1.5, 1e-9, "the drag in fractions of a row")
  eq(seen.up ~= nil, true, "and let go")
  -- Off every region, the event is the view's own.
  eq(paw.roles.input(0, "roles", paw.ui.views.zz_roles, nil, { kind = "down", x = 20.5, y = 4.5, button = "left" }, held), false)
  api.scene_forget(0)
end)

test("a hit region with a command runs it on a click, and one with a hint says it", function()
  fresh()
  scene("roles")
  local grid = paw.opt.grid
  paw.roles.input(0, "roles", paw.ui.views.zz_roles, nil, { kind = "down", x = 9.5, y = 3.5, button = "left" }, {})
  eq(paw.opt.grid, 0.5, "the command ran")
  paw.roles.input(0, "roles", paw.ui.views.zz_roles, nil, { kind = "hover", x = 1.5, y = 3.5 }, {})
  eq(paw.mouse.hint_text(), "a row to press", "the hint")
  paw.opt.grid = grid
  api.scene_forget(0)
end)

test("the mixer's fader drags in a window's units as in the terminal's cells, and its switches switch", function()
  fresh()
  local t = paw.add_track({ name = "A" })
  paw.cursor.set_track(t)
  api.scene_forget(0)
  paw.ui.render_scene("mixer", 80, 24, { w = 8, h = 16 })
  api.scene_end(0, "mixer")
  local s = paw.ui.views.mixer.geometry.strips[1]
  local view = paw.ui.views.mixer
  local x = s.x + math.floor(s.w / 2) + 1 + 0.5
  local y = 1 + s.fader + s.rows - 1.5
  local held = {}
  eq(paw.roles.input(0, "mixer", view, nil, { kind = "down", x = x, y = y, button = "left" }, held), true, "the fader")
  paw.roles.input(0, "mixer", view, nil, { kind = "move", x = x, y = y - 1.5 }, held)
  paw.roles.input(0, "mixer", view, nil, { kind = "up", x = x, y = y - 1.5 }, held)
  -- A row and a half up the travel from 0 dB.
  local want = view.fader_volume(view.fader_position(0) + 1.5 / (s.rows - 1))
  near(t:get().volume, want, 1e-6, "louder by a row and a half of the travel")
  paw.mouse.forget()
  paw.roles.input(0, "mixer", view, nil, { kind = "down", x = s.x + 1.5, y = 1 + s.chips + 0.5, button = "left" }, held)
  eq(t:get().mute, true, "M mutes")
  api.scene_forget(0)
end)
