-- The strip under the piano roll: the notes' velocities, as the roll draws
-- them, or one controller's moves (the pitch wheel, modulation,
-- expression, the sustain pedal), drawn over with the pointer. A click on
-- the strip's name, at its left, chooses what it shows.
--
-- Over a controller: the left button held draws it, a press on a move's
-- head (the top of its bar) chooses it (Ctrl or Shift adds it or takes it
-- out) and a drag moves the chosen, Ctrl and a drag chooses the moves in a
-- box, the right button dragged draws a straight line and clicked opens
-- the menu. Each through `paw.frontend.act`.
local api = paw.api
local util = paw.util
local mouse = paw.mouse
local controls = paw.controls
local menus = require("paw.mouse_menus")
local view = paw.ui.views.pianoroll
local A = paw.frontend.act

local M = {
  -- What the strip can show, in the order the menu lists them.
  kinds = {
    { label = "Velocity", short = "vel" },
    { label = "Pitch wheel", short = "bend", kind = "bend" },
    { label = "Modulation", short = "mod", kind = "cc", number = 1 },
    { label = "Expression", short = "expr", kind = "cc", number = 11 },
    { label = "Sustain pedal", short = "ped", kind = "cc", number = 64 },
  },
}

-- What the strip shows, for each seat: one of `M.kinds`.
local shown = M.kinds[1]
paw.seats.keep(
  "pianoroll.strip",
  function() return shown end,
  function(s) shown = s end,
  function() return M.kinds[1] end
)

--- What the strip shows now: `{ label, short, kind, number }`, `kind` nil
--- for the velocities.
function M.shown() return shown end

--- Show the velocities (nil) or a controller: "bend", or "cc" with its number.
function M.show(kind, number)
  for _, k in ipairs(M.kinds) do
    if k.kind == kind and k.number == number then shown = k end
  end
  api.ui_redraw()
end

-- Drawing ----------------------------------------------------------------------------------

--- The controller's bars over the strip: each column as high as the value
--- that holds there, the columns where a move is lit, the chosen brighter.
local function draw(self, buf)
  local g = self.geometry
  local clip = self:clip()
  if not (shown.kind and clip and g and g.vel and g.vel > 0) then return end
  local eighths = paw.draw.g.eighths
  local top, rows, keys = g.head + g.rows, g.vel, g.keys
  local tw = buf.width - keys
  -- Its name at the left is the roll's (a button that chooses what it shows).
  buf:fill(keys, top, tw, rows, " ", "VelocityLane")
  local lane = buf:sub(keys, top, tw, rows)
  local hue = paw.draw.track_hue(api.track_get(api.clip_get(clip.id).track))
  local list, value = {}, shown.kind == "bend" and 0 or nil
  local chosen = {}
  for _, place in ipairs(controls.chosen(clip.id)) do
    chosen[place] = true
  end
  for place, c in ipairs(clip:controls()) do
    if controls.is(c, shown.kind, shown.number) then list[#list + 1] = { c = c, place = place } end
  end
  local length = clip.length
  -- In pixels under the cells, where the terminal shows them: the value
  -- held from each move as a line with the area under it, and a mark on
  -- each move, the chosen brighter.
  local scroll, zoom, kind = self.scroll, g.zoom, shown.kind
  local pictured = lane:strip(0, 0, tw, rows, {
    key = "pianoroll:strip",
    under = true,
    draw = function(gp, px)
      M.picture(gp, px, {
        list = list,
        chosen = chosen,
        kind = kind,
        scroll = scroll,
        zoom = zoom,
        length = length,
        color = paw.draw.track_colour(api.track_get(api.clip_get(clip.id).track)),
      })
    end,
  })
  if pictured then return end
  local at = 1
  for x = 0, tw - 1 do
    local from, to = self.scroll + x / g.zoom, self.scroll + (x + 1) / g.zoom
    -- Nothing plays past the clip's end.
    if from >= length then break end
    local here
    while list[at] and list[at].c.start < to - 1e-9 do
      value = list[at].c.value
      if list[at].c.start >= from - 1e-9 then here = list[at] end
      at = at + 1
    end
    if value then
      local level = controls.fraction(shown.kind, value) * rows * 8
      local style = here and (chosen[here.place] and "Bright" or hue.fg) or "Faint"
      for row = 0, rows - 1 do
        local amount = level - (rows - 1 - row) * 8
        if amount >= 1 then lane:text(x, row, eighths[math.min(8, math.floor(amount))], style) end
      end
    end
  end
end

--- The strip's picture: `o.list` the moves shown (`{ c, place }` each),
--- `o.chosen` the places chosen, `o.kind` "bend" or "cc", `o.scroll` and
--- `o.zoom` the roll's, `o.length` the clip's, `o.color` the track's.
function M.picture(g, px, o)
  local P = require("paw.theme").palette
  local ppb = o.zoom * px.cell.w
  local function X(beat) return (beat - o.scroll) * ppb end
  -- From the first move (the wheel rests in the middle before it) to the clip's end.
  local first = o.list[1]
  local x0 = o.kind == "bend" and 0 or (first and math.max(0, math.floor(X(first.c.start))) or px.w)
  local x1 = math.min(px.w, math.floor(X(o.length) + 0.5))
  if x1 <= x0 then return end
  local points = {}
  if o.kind == "bend" then points[1] = { beat = o.scroll - 1, value = 0.5, shape = "hold" } end
  for _, item in ipairs(o.list) do
    points[#points + 1] = { beat = item.c.start, value = controls.fraction(o.kind, item.c.value), shape = "hold" }
  end
  local part = { w = x1 - x0, h = px.h, cell = px.cell }
  local _, Y = paw.plot.curve(g:sub(x0, 0, x1 - x0, px.h), part, {
    points = points,
    from = o.scroll + x0 / ppb,
    pixels_per_beat = ppb,
    color = o.color,
    guides = false,
    markers = false,
    grid = false,
    fill = 0.3,
  })
  for _, item in ipairs(o.list) do
    local x = X(item.c.start)
    if x >= x0 - 3 and x <= x1 + 3 then
      local y = Y(controls.fraction(o.kind, item.c.value))
      g:rect(x - 2, y - 2, 4, 4, { fill = o.chosen[item.place] and P.bright or o.color })
    end
  end
end

local render = view.render
function view:render(buf, ctx)
  render(self, buf, ctx)
  draw(self, buf)
  local gesture = mouse.gesture()
  if gesture and gesture.strip then gesture.strip(self, buf) end
end

-- The pointer ------------------------------------------------------------------------------

--- The menu of what the strip shows, at `where` on the screen.
local function choose_kind(where)
  local items = {}
  for _, k in ipairs(M.kinds) do
    items[#items + 1] = { label = k.label, checked = k == shown, run = function() M.show(k.kind, k.number) end }
  end
  paw.ui.menu(items, where)
end

--- A press on the strip, `e` in the view's cells (fractions of them from a
--- window, `e.fine`): the strip's name opens the menu of what it shows;
--- the rest is drawn on. Returns whether the press was taken here.
function M.press(self, e, clip)
  local g = self.geometry
  local top, rows = g.head + g.rows, g.vel
  local where = { x = math.floor(e.x + (e.view_x or 0)), y = math.floor(e.y + (e.view_y or 0)) }
  if e.x < g.keys then
    if e.button == "left" or e.button == "right" then
      mouse.grab(e, {
        up = function(u)
          if not u.moved then choose_kind(where) end
        end,
      })
    end
    return true
  end
  if not shown.kind then return false end
  local kind, number = shown.kind, shown.number
  local function beat(x) return mouse.beat(x - g.keys, self.scroll, g.zoom) end
  -- A terminal's cell at its middle, a window's pointer where it is.
  local half = e.fine and 0 or 0.5
  local function fraction(y) return util.clamp(1 - (y - top + half) / rows, 0, 1) end
  if e.button == "right" then
    local x0, y0 = math.floor(e.x), math.floor(e.y)
    mouse.grab(e, {
      strip = function(_, buf)
        local d = mouse.gesture().d
        if d and d.moved then
          buf:text(x0, y0, paw.draw.g.point, "MouseBox")
          buf:text(math.floor(d.x), util.clamp(math.floor(d.y), top, top + rows - 1), paw.draw.g.point, "MouseBox")
        end
      end,
      drag = function(d) mouse.gesture().d = d end,
      up = function(u)
        if not u.moved then return paw.ui.menu(menus.strip(clip.id, kind, number), where) end
        A.line_controls(clip.id, kind, number, beat(x0), fraction(y0), beat(u.x), fraction(u.y), mouse.has(u, "S"))
      end,
    })
    return true
  end
  if e.button ~= "left" then return true end
  -- A move whose head is under the pointer: the top of its bar, in the
  -- cell a terminal draws it in; within half a cell of it in a window.
  local tx = e.x - g.keys
  local function on_head(c)
    local x = (c.start - self.scroll) * g.zoom
    local f = controls.fraction(kind, c.value)
    if e.fine then return math.abs(tx - x) <= 0.5 and math.abs(e.y - (top + rows * (1 - f))) <= 0.5 end
    local level = f * rows * 8
    return math.floor(x + 0.5) == tx and e.y == top + rows - 1 - math.max(0, math.floor((level - 1) / 8))
  end
  for place, c in ipairs(clip:controls()) do
    if controls.is(c, kind, number) then
      if on_head(c) then
        local toggling = mouse.has(e, "C") or mouse.has(e, "S")
        if toggling then
          A.select_control(clip.id, place, mouse.has(e, "C") and "toggle" or "add")
        else
          local among = false
          for _, p in ipairs(controls.chosen(clip.id)) do
            among = among or p == place
          end
          if not among then A.select_control(clip.id, place, "only") end
        end
        mouse.grab(e, {
          drag = function(d)
            mouse.hint(
              string.format("moving the chosen moves by %g beats", math.floor(d.dx / g.zoom * 100 + 0.5) / 100)
            )
          end,
          up = function(u)
            if u.moved and not toggling then
              A.move_controls(clip.id, u.dx / g.zoom, -u.dy / rows, mouse.has(u, "S"))
            end
          end,
        })
        return true
      end
    end
  end
  if mouse.has(e, "C") then
    local x0, y0 = e.x, e.y
    mouse.grab(e, {
      up = function(u)
        local a, b = math.min(x0, u.x), math.max(x0, u.x)
        A.select_controls(
          clip.id,
          kind,
          number,
          beat(a),
          fraction(math.max(y0, u.y)),
          beat(b + (e.fine and 0 or 1)),
          fraction(math.min(y0, u.y)),
          mouse.has(u, "S") and "add" or "only"
        )
      end,
    })
    return true
  end
  local stroke = { { beat(e.x), fraction(e.y) } }
  mouse.grab(e, {
    drag = function(d)
      stroke[#stroke + 1] = { beat(d.x), fraction(d.y) }
      local f = stroke[#stroke][2]
      mouse.hint(
        kind == "bend" and string.format("bend %d", math.floor(8192 * (f * 2 - 1) + 0.5))
          or string.format("value %d", math.floor(127 * f + 0.5))
      )
    end,
    up = function() A.draw_controls(clip.id, kind, number, stroke) end,
  })
  return true
end

return M
