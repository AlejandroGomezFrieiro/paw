-- The curve editor: a buffer for each curve (an automation lane, a
-- parameter, a clip's controller, one note's expression, the tempo map),
-- named by its address, shown in any number of windows. docs/reference/curve-editor.md
-- says how it is used; `paw.curves` reads and writes the curves.
--
--   :vs paw://lane/9          :e paw://tempo          :curve.open
--
-- Editing is modal, as in the piano roll: the cursor is a beat and a value,
-- points are words (`w` `b`), operators take motions and selections, and
-- insert mode draws the value as the cursor moves, written as one undo
-- step when it is left. A window keeps its own time (`left`, `zoom`),
-- cursor (`beat`, `value`) and grid in `win.state`, so that two windows on
-- one curve look at different stretches of it.
local api = paw.api
local util = paw.util
local curves = paw.curves
local layout = paw.layout
local mouse = paw.mouse

local M = {}
local EPS = 1e-9
local AXIS = 10 -- the columns of the value axis at the left

-- What is under way in some window, each seat its own: the points insert
-- mode has drawn (`{ win, from, to, points }`), a wave made with `g~`
-- whose choices can still be stepped through, and what the pointer drags.
local insert, gen, drag
paw.seats.keep("curve", function() return insert, gen, drag end, function(i, g, d)
  insert, gen, drag = i, g, d
end, function() return nil, nil, nil end)

-- The window a graphical frontend draws the editor in, when it shows it in
-- a window of its own (`:curve.window`).
local loose

-- Windows and targets ------------------------------------------------------------

--- The curve window the keyboard is in: the current window, or the one a
--- graphical frontend shows.
function M.current()
  local win = layout.current()
  if win and win.view == "curve" then return win end
  if paw.ui.focused == "curve" and loose then return loose end
end

local function uri_of(win)
  local buf = win and layout.buf_of(win)
  return buf and buf.target
end

--- The curve a window shows, or nil and why not.
function M.target(win)
  local uri = uri_of(win)
  if not uri then return nil, "no curve in this window" end
  return curves.target(uri)
end

local function state(win, t)
  local s = win.state
  s.zoom = s.zoom or paw.opt.zoom
  s.grid = s.grid or paw.timegrid.step()
  s.beat = s.beat or paw.cursor.beat
  s.left = s.left or math.max(0, s.beat - 2)
  if not s.value and t then
    local points = t.points()
    s.value = curves.value_at(points, s.beat) or (t.flat and t.flat()) or (t.lo + t.hi) / 2
  end
  return s
end

--- The points a window shows: the curve's, with what insert mode or a drag
--- has not written yet in their place.
local function shown_points(win, t)
  local points = t.points()
  if insert and insert.win == win.id then return curves.splice(points, insert.from, insert.to, insert.points) end
  if drag and drag.win == win.id and drag.points then return drag.points end
  return points
end

--- The value of a curve at a beat, or of what it moves with no points.
local function value_at(t, points, beat)
  return curves.value_at(points, beat) or (t.flat and t.flat()) or (t.lo + t.hi) / 2
end

--- The time axis of a window's state (paw/axis.tl): where each beat is
--- drawn, from its left edge `left` at its zoom.
local function axis_of(s) return paw.axis.new(s.left, s.zoom) end

--- Half a column of a window's state, in beats: how near the cursor a
--- point is under it.
local function half_cell(s) return axis_of(s):beats(0.5) end

--- The point within `reach` beats of a beat: its index and the point.
local function point_at(points, beat, reach)
  reach = reach + EPS
  local best, at
  for i, q in ipairs(points) do
    local d = math.abs(q.beat - beat)
    if d <= reach and (not best or d < math.abs(best.beat - beat)) then
      best, at = q, i
    end
  end
  return at, best
end

--- A value `n` key presses away: a hundredth of the slider for a
--- parameter, as the device panel moves it, else the curve's step.
local function nudge(t, v, n)
  if t.param then return paw.params.step(t.param, v, n) end
  return util.clamp(v + n * t.step, t.min, t.max)
end

--- Write a curve's points as one undo step, named `label`.
local function write(t, points, label)
  if label then api.undo_label(label) end
  t.write(curves.fit(t, points))
end

-- Drawing ----------------------------------------------------------------------------

--- The beats a region covers, as points are chosen by it: from one end to
--- the other, both included in a selection (a point is an instant), the
--- end left out after a motion, and the whole curve for whole rows.
local function span_of(region)
  if region.kind == "line" then return -math.huge, math.huge end
  local c0, c1 = region.c0, region.c1
  if region.unstretched then c1 = c0 end
  return c0, region.visual and c1 or c1 - EPS
end

local function in_span(q, from, to) return q.beat >= from - EPS and q.beat <= to + EPS end

--- The plot in pixels (a strip below the cells, `buf:strip`): the grid, the
--- curve and the area below it, through `paw.plot`. A value is as high as
--- the middle of the dot where the cells would put it (`s.sub` dots for
--- each cell, as `paw.opt.curve_glyphs` sets them). So the points and the
--- cursor, which paw draws in cells over it, are on the line.
function M.picture(g, px, t, points, s)
  local track = t.track and api.track_get(t.track) or { master = true }
  local dot = px.cell.h / (s.sub or 4)
  paw.plot.curve(g, px, {
    points = points,
    from = s.left,
    pixels_per_beat = s.zoom * px.cell.w,
    frac = t.frac,
    flat = #points == 0 and t.flat and t.flat() or nil,
    color = paw.draw.track_colour(track),
    top = dot / 2,
    bottom = dot / 2,
    beats = s.zoom >= 4,
    markers = false,
  })
end

local function render(win, canvas, ctx)
  local t, why = M.target(win)
  local W, H = canvas.width, canvas.height
  if not t then
    paw.ui.titlebar(canvas, { name = uri_of(win) or "curve", focused = ctx.focused })
    canvas:text(2, 2, why or "nothing to show", "Empty")
    return
  end
  local s = state(win, t)
  local g = paw.draw.g
  local points = shown_points(win, t)
  local inserting = insert and insert.win == win.id
  local mode = ctx.focused and paw.keymap.mode or "n"
  local where = paw.time.format(s.beat) .. "  " .. t.format(s.value)
  paw.ui.titlebar(canvas, {
    name = t.name(),
    context = where,
    focused = ctx.focused,
    right = string.format("%d point%s", #points, #points == 1 and "" or "s"),
  })
  if inserting and ctx.focused then
    local text = " INS draw "
    canvas:text(math.max(0, W - api.str_width(text) - 1), 0, text, "RulerInsert")
  end
  local pw, rows = W - AXIS, H - 3
  if pw < 4 or rows < 2 then return end
  local top = 2
  s.geo = { x = AXIS, y = top, w = pw, rows = rows }
  -- The cursor stays in sight, unless another window leads this one's time.
  if not ctx.follower then
    local col = axis_of(s):exact(s.beat)
    if col < 0 then
      s.left = s.beat
    elseif col >= pw - 1 then
      s.left = s.beat - axis_of(s):beats(pw - 2)
    end
    s.left = math.max(0, s.left)
  end
  -- The window's axis at its scroll now: each row of it draws on it.
  local ax = axis_of(s)
  local span = ax:beats(pw)

  -- The ruler and the grid: bars and beats in their cell.
  canvas:fill(0, 1, W, 1, " ", "Ruler")
  local lines = paw.draw.beats(canvas:sub(AXIS, 1, pw, 1), ax, span, 0)
  local plot = canvas:sub(AXIS, top, pw, rows)
  plot:fill(0, 0, pw, rows, " ", "Lane")
  -- Where the terminal shows pictures, the grid and the curve are one under
  -- the cells, which keep the points, the cursor and the playhead.
  local pictured = plot:strip(0, 0, pw, rows, {
    key = "curve:" .. tostring(win.id),
    under = true,
    draw = function(gp, px)
      M.picture(
        gp,
        px,
        t,
        points,
        { left = s.left, zoom = s.zoom, sub = paw.draw.curve_glyphs() == "braille" and 4 or 3 }
      )
    end,
  })
  -- Beats only once they are far enough apart not to be noise, as in the arrange view.
  for _, line in ipairs(lines) do
    if not pictured and line.x >= 0 and line.x < pw and (line.bar or ax:cells(1) >= 4) then
      plot:fill(line.x, 0, 1, rows, line.bar and g.bar or g.beat, line.bar and "LaneBar" or "LaneBeat")
    end
  end

  -- A selection: its stretch of time, behind the curve.
  local sel = ctx.focused and paw.keymap.selection()
  if sel and sel.view == "curve" then
    local from, to = span_of(sel)
    local x0 = math.max(0, ax:x_of(from))
    local x1 = math.min(pw, ax:x_of(to) + 1)
    if x1 > x0 then plot:fill(x0, 0, x1 - x0, rows, " ", "Visual") end
  end

  -- The value axis: the top, the middle and the bottom, in the curve's units.
  canvas:fill(0, top, AXIS, rows, " ", "Panel")
  for _, r in ipairs({ 0, math.floor((rows - 1) / 2), rows - 1 }) do
    local f = 1 - r / math.max(1, rows - 1)
    canvas:text(0, top + r, util.fit(t.format(t.unfrac(f)), AXIS - 1), "Dim")
  end
  canvas:fill(AXIS - 1, top, 1, rows, g.v, "Rule")

  -- The curve, two samples a cell across, joined into a line.
  local hue = paw.draw.track_hue(t.track and api.track_get(t.track) or { master = true })
  local kind = paw.draw.curve_glyphs()
  local sub = kind == "braille" and 4 or 3
  local dots = rows * sub
  local function dot_y(v) return util.clamp(math.floor((1 - t.frac(v)) * (dots - 1) + 0.5), 0, dots - 1) end
  local have = #points > 0 or t.flat
  if have and not pictured then
    if kind == "line" then
      for cx = 0, pw - 1 do
        local beat = ax:beat_of(cx + 0.5)
        local y = dot_y(value_at(t, points, beat))
        plot:text(cx, math.floor(y / sub), paw.opt.ascii and "*" or "─", hue.fg)
      end
    else
      local cells = paw.draw.trace(
        pw,
        pw * 2,
        function(sx) return dot_y(value_at(t, points, ax:half_beat(sx))) end,
        sub,
        kind
      )
      local glyph = kind == "braille" and paw.draw.braille or paw.draw.sextant
      for key, bits in pairs(cells) do
        plot:text(key % pw, math.floor(key / pw), glyph(bits), hue.fg)
      end
    end
  elseif not have then
    plot:text(1, 0, "No points yet: `o` adds one at the cursor, `i` draws.", "Empty")
  end

  -- The points, the chosen brighter.
  for _, q in ipairs(points) do
    local x = ax:x_of(q.beat)
    if x >= 0 and x < pw then
      local y = math.floor(dot_y(q.value) / sub)
      local style = sel and sel.view == "curve" and in_span(q, span_of(sel)) and "CursorVisual" or hue.note
      if inserting and in_span(q, insert.from, insert.to) then style = "InsertCursor" end
      plot:text(x, y, q.shape == "hold" and "■" or q.shape == "smooth" and "●" or g.point, style)
    end
  end

  -- The playhead, then the cursor: a beat and a value.
  local play = ax:x_of(paw.transport.position)
  if play >= 0 and play < pw then plot:fill(play, 0, 1, rows, g.playhead, "Playhead") end
  local cx = ax:x_of(s.beat)
  if cx >= 0 and cx < pw then
    local cy = math.floor(dot_y(s.value) / sub)
    local under = point_at(points, s.beat, half_cell(s))
    plot:text(cx, cy, under and g.point or "┼", ctx.focused and (mode == "i" and "InsertCursor" or "Cursor") or "Dim")
  end

  -- The line along the bottom: where the cursor is, the point under it, and
  -- what is under way.
  local bottom = top + rows
  canvas:fill(0, bottom, W, 1, " ", "Ruler")
  local at, q = point_at(points, s.beat, half_cell(s))
  local text
  if gen and gen.win == win.id then
    text = M.gen_text()
  elseif q then
    text = string.format(
      "point %d: %s at %s · %s%s",
      at,
      t.format(q.value),
      paw.time.format(q.beat),
      q.shape,
      q.shape == "smooth" and string.format(" %+.2f", q.tension) or ""
    )
  else
    text = string.format(
      "curve %s at %s · grid %s",
      t.format(value_at(t, points, s.beat)),
      paw.time.format(s.beat),
      paw.ui.views:get("status").grid_text(s.grid)
    )
  end
  canvas:text(1, bottom, util.fit(text, W - 2), "Dim")
end

-- The buffer type ----------------------------------------------------------------

local def = layout.buftype("curve", {
  claims = function(name) return curves.is_curve(name) end,
  bufname = function(target) return target end,
  title = function(buf)
    local t = curves.target(buf.target)
    return t and t.name() or buf.target
  end,
  create = function(target) return { uri = target } end,
  -- The lane or parameter is in the project, or the window has nothing to show.
  alive = function(buf) return curves.target(buf.target) ~= nil end,
  render = render,
  window = function() return loose end,
  time = {
    get = function(win)
      if not win then return nil end
      local s = state(win)
      return s.left, s.zoom, s.geo and axis_of(s):beats(s.geo.w)
    end,
    set = function(win, left, zoom)
      if not win then return end
      local s = state(win)
      s.left, s.zoom = math.max(0, left), zoom or s.zoom
    end,
  },
})
local view = paw.ui.views:get("curve")
view.title = "Curve"

-- What modal editing works on: rows are steps of the value, counting upwards.
view.grid = {
  down = -1,
  get = function()
    local win = M.current()
    local t = win and M.target(win)
    if not t then return 0, 0 end
    local s = state(win, t)
    local row = t.param and math.floor(t.frac(s.value) * 100 + 0.5) or math.floor((s.value - t.lo) / t.step + 0.5)
    return row, s.beat
  end,
  set = function(row, col)
    local win = M.current()
    local t = win and M.target(win)
    if not t then return end
    local s = state(win, t)
    s.beat = math.max(0, col)
    s.value = t.param and t.unfrac(row / 100) or util.clamp(t.lo + row * t.step, t.min, t.max)
    api.ui_redraw()
  end,
  step = function()
    local win = M.current()
    return win and state(win).grid or paw.timegrid.step()
  end,
}

-- While a wave's choices can be stepped through, keys of their own come first.
function view:subscope()
  local win = M.current()
  if gen and win and gen.win == win.id then return "curve.gen" end
end

-- Opening -----------------------------------------------------------------------------

--- Show a curve. It shows in the window that shows it already. If not, it
--- shows in a new window split below the current window (to the side with
--- `opts.vertical`), or in this window with `opts.here`. With `opts.window`,
--- it shows in a separate window of a graphical frontend. `opts.beat` puts
--- the cursor there.
function M.open(uri, opts)
  opts = opts or {}
  local t, why = curves.target(uri)
  if not t then return nil, why end
  local buf = layout.buf_create("curve", uri)
  local win
  if opts.window then
    loose = layout.leaf("curve", { buf = buf.id })
    win = loose
    paw.canvas.open_view("curve", { title = t.name() })
  else
    for _, w in ipairs(layout.windows()) do
      if w.view == "curve" and w.buf == buf.id then win = w end
    end
    if win then
      layout.enter(win)
    elseif opts.here then
      win = layout.show_in(layout.current(), "curve", buf.id)
    else
      win = layout.split({ view = "curve", buf = buf.id, vertical = opts.vertical })
      if not win then win = layout.show_in(layout.current(), "curve", buf.id) end
    end
  end
  local s = state(win)
  if opts.beat then
    s.beat, s.value = opts.beat, nil
    s.left = math.max(0, opts.beat - 2)
  end
  state(win, t)
  api.ui_redraw()
  return win
end

--- The curve of the item under the cursor in the focused view. In the
--- arrange view, it is a lane row or the tempo lane. In the device panel,
--- it is a parameter. In the piano roll, it is the controller of the strip
--- (with `note`, only that of the note under the cursor). Nil and the
--- reason when there is none.
function M.under_cursor(note)
  local focused = paw.ui.focused
  if focused == "curve" then
    local win = M.current()
    return win and uri_of(win)
  end
  if focused == "devices" then
    local _, row = paw.ui.views:get("devices"):selected()
    if not (row and row.param) then return nil, "no parameter under the cursor" end
    return paw.address.param(row.device.id, row.param.key)
  end
  if focused == "pianoroll" then
    local roll = paw.ui.views:get("pianoroll")
    local clip = roll:clip()
    if not clip then return nil, "no clip in the piano roll" end
    local shown = require("paw.views.pianoroll_strip").shown()
    local kind, number = shown.kind or "cc", shown.kind and shown.number or 1
    local uri = paw.address.clip(clip.id) .. "/control/" .. kind .. (kind == "cc" and "/" .. number or "")
    if note then
      local n = roll:note_at(roll.pitch, roll.beat)
      if not n then return nil, "no note under the cursor" end
      uri = uri .. "#key=" .. n.pitch
    end
    return uri
  end
  if focused == "arrange" then
    local lane = paw.cursor.lane_id()
    if lane then return paw.address.lane(lane) end
    if paw.tempolane.shown() then return paw.address.tempo() end
    return nil,
      "not on a lane row: `" .. paw.keymap.human("<leader>aa") .. "` shows the lanes, `" .. paw.keymap.human(
        "<leader>al"
      ) .. "` chooses one"
  end
  -- A view that knows the curve of what is under its cursor (the mixer's fader).
  local view = paw.ui.views:get(focused)
  if view and view.curve_uri then return view:curve_uri() end
  return nil, "no curve under the cursor here"
end

-- Editing -----------------------------------------------------------------------------

--- The window, its curve, its state and the curve's points, for a key.
local function here()
  local win = M.current()
  if not win then return nil end
  local t, why = M.target(win)
  if not t then
    paw.notify(why, "warn")
    return nil
  end
  return win, t, state(win, t), t.points()
end

local function say(t, q) paw.notify(string.format("%s: %s at %s", t.name(), t.format(q.value), paw.time.format(q.beat))) end

--- Move the cursor along the grid, `n` steps.
function M.move(n)
  local win, _, s = here()
  if not win then return end
  local grid = s.grid
  -- Off the grid (on a point), the first step lands on it.
  local base = n > 0 and math.floor(s.beat / grid + EPS) * grid or math.ceil(s.beat / grid - EPS) * grid
  if math.abs(base - s.beat) > EPS then n = n - (n > 0 and 1 or -1) end
  s.beat = math.max(0, base + n * grid)
  api.ui_redraw()
end

--- Move the cursor's value `n` steps up.
function M.climb(n)
  local win, t, s = here()
  if not win then return end
  s.value = nudge(t, s.value, n)
  api.ui_redraw()
end

--- Go to the next point (`dir` 1) or the previous point, `n` times. The
--- cursor takes its value.
function M.to_point(dir, n)
  local win, _, s, points = here()
  if not win then return end
  for _ = 1, n or 1 do
    local to
    for _, q in ipairs(points) do
      if dir > 0 and q.beat > s.beat + EPS and not to then to = q end
      if dir < 0 and q.beat < s.beat - EPS then to = q end
    end
    if not to then break end
    s.beat, s.value = to.beat, to.value
  end
  api.ui_redraw()
end

--- To the first (`dir` -1) or last point.
function M.to_end(dir)
  local win, _, s, points = here()
  if not (win and #points > 0) then return end
  local q = dir < 0 and points[1] or points[#points]
  s.beat, s.value = q.beat, q.value
  api.ui_redraw()
end

--- Add a point at the cursor: at the cursor's value, or with `on_curve`
--- at the curve's value there.
function M.add(on_curve)
  local win, t, s, points = here()
  if not win then return end
  local v = on_curve and value_at(t, points, s.beat) or s.value
  local at = point_at(points, s.beat, 0)
  local q = { beat = s.beat, value = v, shape = "linear", tension = 0 }
  if at then
    points[at] = q
  else
    points[#points + 1] = q
  end
  write(t, points, "Add a point")
  s.value = v
  say(t, q)
end

--- Remove `n` points from the one under the cursor on.
function M.remove(n)
  local win, t, s, points = here()
  if not win then return end
  local at = point_at(points, s.beat, half_cell(s))
  if not at then return paw.notify("no point under the cursor", "warn") end
  for _ = 1, n or 1 do
    if points[at] then table.remove(points, at) end
  end
  write(t, points, "Remove a point")
end

--- Raise or lower the point under the cursor `n` steps.
function M.nudge_point(n)
  local win, t, s, points = here()
  if not win then return end
  local at, q = point_at(points, s.beat, half_cell(s))
  if not at then return paw.notify("no point under the cursor: `o` adds one", "warn") end
  q.value = nudge(t, q.value, n)
  s.value = q.value
  write(t, points, "Change a point")
  say(t, q)
end

--- Type the value of the point under the cursor, or of a new one there.
function M.type_value()
  local win, t, s, points = here()
  if not win then return end
  local at, q = point_at(points, s.beat, half_cell(s))
  local now = q and q.value or s.value
  paw.ui.ask_value({
    label = t.name(),
    now = now * t.scale,
    min = t.min * t.scale,
    max = t.max * t.scale,
    show = function(v) return t.format(v / t.scale) end,
  }, function(v)
    v = v / t.scale
    local list = t.points()
    if at then
      list[at].value = v
    else
      list[#list + 1] = { beat = s.beat, value = v, shape = "linear", tension = 0 }
    end
    write(t, list, "Set a point")
    s.value = v
  end)
end

local SHAPES = { "linear", "hold", "smooth" }

--- Give the stretches that leave the points `list` (indices) a shape: the
--- next one in turn after the first's when `shape` is nil.
local function shape_points(t, points, list, shape)
  if #list == 0 then return paw.notify("no point there", "warn") end
  if not shape then
    local now = points[list[1]].shape
    for i, name in ipairs(SHAPES) do
      if name == now then shape = SHAPES[i % #SHAPES + 1] end
    end
    -- The next shape the curve has.
    for _ = 1, #SHAPES do
      if t.has(shape) then break end
      for i, name in ipairs(SHAPES) do
        if name == shape then
          shape = SHAPES[i % #SHAPES + 1]
          break
        end
      end
    end
  end
  if not t.has(shape) then
    return paw.notify(
      t.name()
        .. " has no "
        .. shape
        .. " stretches"
        .. (t.kind == "control" and ": a controller's moves hold until the next" or ""),
      "warn"
    )
  end
  for _, i in ipairs(list) do
    points[i].shape = shape
  end
  write(t, points, "Shape the curve")
  paw.notify(shape .. (shape == "smooth" and ": `[` `]` bend it" or ""))
end

--- The next shape for the stretch from the point under the cursor.
function M.cycle_shape()
  local win, t, s, points = here()
  if not win then return end
  local at = point_at(points, s.beat, half_cell(s))
  if not at then return paw.notify("no point under the cursor", "warn") end
  shape_points(t, points, { at }, nil)
end

--- Bend the smooth stretch from the point under the cursor.
function M.tension(by)
  local win, t, s, points = here()
  if not win then return end
  local _, q = point_at(points, s.beat, half_cell(s))
  if not (q and q.shape == "smooth") then return paw.notify("no smooth stretch from here: `~` makes one", "warn") end
  q.tension = util.clamp((q.tension or 0) + by, -1, 1)
  write(t, points, "Bend the curve")
  paw.notify(string.format("tension %+.2f", q.tension))
end

--- The indices of the points in a region.
local function chosen(points, region)
  local from, to = span_of(region)
  local out = {}
  for i, q in ipairs(points) do
    if in_span(q, from, to) then out[#out + 1] = i end
  end
  return out
end

--- Operators: each `fn(t, points, list, region, ctx)` on the points of a
--- region (`list` their indices), on the focused window's curve.
local function on_region(fn)
  return function(region, ctx)
    local win, t, s, points = here()
    if not win then return end
    return fn(t, points, chosen(points, region), region, ctx or {}, s)
  end
end

local function without(points, list)
  local gone, out = {}, {}
  for _, i in ipairs(list) do
    gone[i] = true
  end
  for i, q in ipairs(points) do
    if not gone[i] then out[#out + 1] = q end
  end
  return out
end

local function yank(points, list, register)
  local first = list[1] and points[list[1]].beat or 0
  local out = {}
  for _, i in ipairs(list) do
    local q = curves.copy(points[i])
    q.beat = q.beat - first
    out[#out + 1] = q
  end
  paw.keymap.setreg({ kind = "curve", points = out }, register, true)
  return #out
end

M.ops = {
  delete = on_region(function(t, points, list, _, ctx)
    if #list == 0 then return end
    yank(points, list, ctx.register)
    write(t, without(points, list))
  end),
  yank = on_region(
    function(_, points, list, _, ctx) paw.notify(yank(points, list, ctx.register) .. " points yanked") end
  ),
  raise = function(n)
    return on_region(function(t, points, list, _, ctx)
      for _, i in ipairs(list) do
        points[i].value = nudge(t, points[i].value, n * (ctx.count or 1))
      end
      write(t, points)
    end)
  end,
  shift = function(n)
    return on_region(function(t, points, list, _, ctx, s)
      local by = n * (ctx.count or 1) * s.grid
      local moving, keep = {}, {}
      for _, i in ipairs(list) do
        moving[i] = true
      end
      local landed = {}
      for i, q in ipairs(points) do
        if moving[i] then
          q.beat = math.max(0, q.beat + by)
          landed[#landed + 1] = q.beat
        end
      end
      -- A point moved onto another's beat takes its place.
      for i, q in ipairs(points) do
        local covered = false
        if not moving[i] then
          for _, b in ipairs(landed) do
            covered = covered or math.abs(q.beat - b) < EPS
          end
        end
        if not covered then keep[#keep + 1] = q end
      end
      write(t, keep)
      if paw.keymap.visual then
        paw.keymap.visual.col = math.max(0, paw.keymap.visual.col + by)
        s.beat = math.max(0, s.beat + by)
      end
    end)
  end,
  shape = on_region(function(t, points, list) shape_points(t, points, list, nil) end),
  thin = on_region(function(t, points, list, region)
    if #list < 3 and region.kind ~= "line" then return paw.notify("thinning needs three points or more", "warn") end
    local a, b = list[1], list[#list]
    local part = {}
    for i = a, b do
      part[#part + 1] = points[i]
    end
    local thinned = curves.thin(part, 0.01, t.frac)
    local out = {}
    for i = 1, a - 1 do
      out[#out + 1] = points[i]
    end
    for _, q in ipairs(thinned) do
      out[#out + 1] = q
    end
    for i = b + 1, #points do
      out[#out + 1] = points[i]
    end
    write(t, out)
    paw.notify(string.format("%d points, %d before", #out, #points))
  end),
  smooth = on_region(function(t, points, list, _, ctx)
    if #list < 3 then return paw.notify("smoothing needs three points or more", "warn") end
    local a, b = list[1], list[#list]
    local part = {}
    for i = a, b do
      part[#part + 1] = points[i]
    end
    local soft = curves.smooth(part, ctx.count or 1)
    for k = 1, #soft do
      points[a + k - 1] = soft[k]
    end
    write(t, points)
    paw.notify(string.format("smoothed %d points", #list))
  end),
  quantize = on_region(function(t, points, list, _, _, s)
    if #list == 0 then return end
    local part, rest = {}, without(points, list)
    for _, i in ipairs(list) do
      part[#part + 1] = points[i]
    end
    local snapped = curves.quantize(part, s.grid)
    -- What lands on a beat a point outside it holds takes its place.
    local out = {}
    for _, q in ipairs(rest) do
      local covered = false
      for _, p in ipairs(snapped) do
        covered = covered or math.abs(p.beat - q.beat) < EPS
      end
      if not covered then out[#out + 1] = q end
    end
    for _, q in ipairs(snapped) do
      out[#out + 1] = q
    end
    write(t, curves.sorted(out))
  end),
}

--- Put the points of a register at the cursor, over what is there.
function M.paste(register, count)
  local win, t, s, points = here()
  if not win then return end
  local value = paw.keymap.getreg(register)
  if not (value and value.kind == "curve") then
    return paw.notify("no points in the register: `y` some first", "warn")
  end
  local new, at = {}, s.beat
  local length = 0
  for _, q in ipairs(value.points) do
    length = math.max(length, q.beat)
  end
  local period = length + s.grid
  for k = 0, (count or 1) - 1 do
    for _, q in ipairs(value.points) do
      local c = curves.copy(q)
      c.beat = at + k * period + q.beat
      new[#new + 1] = c
    end
  end
  write(t, curves.splice(points, at, at + (count or 1) * period - s.grid, new), "Paste points")
end

-- Insert mode: drawing -----------------------------------------------------------------

--- Start drawing at the cursor: from here, each move of the cursor puts a
--- point where it lands, at its value. Nothing is written until insert
--- mode is left.
function M.insert_start(on_curve)
  local win, t, s, points = here()
  if not win then return end
  if on_curve then s.value = value_at(t, points, s.beat) end
  insert = { win = win.id, from = s.beat, to = s.beat, points = {} }
  M.insert_mark()
  paw.keymap.set_mode("i")
end

--- Put the cursor's beat and value among the points drawn.
function M.insert_mark()
  local win = M.current()
  if not (insert and win and insert.win == win.id) then return end
  local s = state(win)
  local q = { beat = s.beat, value = s.value, shape = "linear", tension = 0 }
  local kept = {}
  for _, p in ipairs(insert.points) do
    if math.abs(p.beat - q.beat) > EPS then kept[#kept + 1] = p end
  end
  kept[#kept + 1] = q
  insert.points = curves.sorted(kept)
  insert.from, insert.to = math.min(insert.from, q.beat), math.max(insert.to, q.beat)
  api.ui_redraw()
end

--- Write what was drawn, as one undo step.
function M.insert_finish()
  local done = insert
  insert = nil
  if not (done and #done.points > 0) then return end
  local win = layout.get(done.win) or (loose and loose.id == done.win and loose)
  local t = win and M.target(win)
  if not t then return end
  write(t, curves.splice(t.points(), done.from, done.to, done.points), "Draw the curve")
  api.ui_redraw()
end

paw.on("mode.changed", function(e)
  if e.old == "i" and insert then M.insert_finish() end
end)

-- Waves --------------------------------------------------------------------------------

local CHOICES = { "wave", "rate", "depth" }

--- What the wave under way reads as on the bottom line.
function M.gen_text()
  if not gen then return "" end
  local parts = {}
  for i, name in ipairs(CHOICES) do
    local value = name == "wave" and curves.waves[gen.wave]
      or name == "rate" and curves.rates[gen.rate][2]
      or curves.depths[gen.depth][2]
    parts[#parts + 1] = (i == gen.choice and "[" .. value .. "]" or value)
  end
  return table.concat(parts, " · ") .. "   Tab next choice · Ctrl-n Ctrl-p change it · Ctrl-y keep"
end

local function gen_write(first)
  local win = layout.get(gen.win) or (loose and loose.id == gen.win and loose)
  local t = win and M.target(win)
  if not t then
    gen = nil
    return
  end
  -- Changed after the turn that wrote it: into the same undo step.
  if not first and api.undo_current() ~= gen.undo_before then api.undo_join(api.undo_current()) end
  local wave = curves.generate(curves.waves[gen.wave], gen.from, gen.to, {
    rate = curves.rates[gen.rate][1],
    depth = curves.depths[gen.depth][1],
    centre = gen.centre,
    unfrac = t.unfrac,
    smooth = t.has("smooth"),
    seed = gen.seed,
  })
  write(t, curves.splice(gen.before, gen.from, gen.to, wave), first and "Make a " .. curves.waves[gen.wave] or nil)
  api.ui_redraw()
end

--- Make a wave over a range of the curve, from beat `from` to `to`. `wave`
--- is a name or a number in `paw.curves.waves`. `opts.rate` and
--- `opts.depth` are numbers or places in their lists. You can then step
--- through the choices until `<C-y>` or `<Esc>` keeps them.
function M.generate(wave, from, to, opts)
  opts = opts or {}
  local win, t, _, points = here()
  if not win then return end
  if to - from < EPS then return paw.notify("a wave needs a stretch of time: select one, or give a motion", "warn") end
  local index = tonumber(wave)
  for i, name in ipairs(curves.waves) do
    if name == wave then index = i end
  end
  if not (index and curves.waves[index]) then
    return paw.notify("no wave `" .. tostring(wave) .. "`: " .. table.concat(curves.waves, ", "), "warn")
  end
  local function place(list, v, default)
    for i, entry in ipairs(list) do
      if math.abs(entry[1] - (tonumber(v) or -1)) < EPS then return i end
    end
    return default
  end
  gen = {
    win = win.id,
    wave = index,
    from = from,
    to = to,
    before = points,
    choice = 1,
    seed = math.floor(from * 97 + to),
    rate = place(curves.rates, opts.rate, 3),
    depth = place(curves.depths, opts.depth, 2),
    centre = t.frac(value_at(t, points, from)),
    undo_before = api.undo_current(),
  }
  gen_write(true)
end

--- Step the current choice of the wave under way, or go to the next choice.
function M.gen_step(by)
  if not gen then return end
  local name = CHOICES[gen.choice]
  local list = name == "wave" and curves.waves or name == "rate" and curves.rates or curves.depths
  gen[name] = (gen[name] - 1 + by) % #list + 1
  gen_write(false)
end

--- Select the next shape (`by` 1) or the previous shape (-1) while you generate a wave.
function M.gen_next(by)
  if not gen then return end
  gen.choice = (gen.choice - 1 + by) % #CHOICES + 1
  api.ui_redraw()
end

--- Keep the wave as it is.
function M.gen_finish()
  gen = nil
  api.ui_redraw()
end

--- The wave menu, then the wave over a region.
local function wave_menu(from, to, where)
  local items = {}
  for i, name in ipairs(curves.waves) do
    items[#items + 1] = {
      label = name:sub(1, 1):upper() .. name:sub(2),
      keys = tostring(i),
      run = function() M.generate(i, from, to) end,
    }
  end
  paw.ui.menu(items, where or { x = 4, y = 4 })
end
M.wave_menu = wave_menu

-- Zoom and grid --------------------------------------------------------------------------

--- Zoom the editor's window in or out by `factor`.
function M.zoom(factor)
  local win, _, s = here()
  if not win then return end
  s.zoom = util.clamp(s.zoom * factor, 0.125, 64)
  api.ui_redraw()
end

--- Make the editor's grid `factor` times as fine or as coarse.
function M.grid(factor)
  local win, _, s = here()
  if not win then return end
  s.grid = util.clamp(s.grid * factor, 1 / 64, 16)
  paw.notify("grid " .. paw.ui.views:get("status").grid_text(s.grid))
end

-- The mouse ------------------------------------------------------------------------------

--- The beat and value under a cell of the drawing.
local function at_cell(win, t, x, y)
  local s = state(win, t)
  local geo = s.geo
  local beat = axis_of(s):beat_of(x - geo.x)
  local f = 1 - (y - geo.y + 0.5) / geo.rows
  return math.max(0, beat), t.unfrac(util.clamp(f, 0, 1))
end

local function snapped(s, beat, free)
  if free then return beat end
  return math.max(0, util.round(beat, s.grid))
end

local function point_menu(win, t, at)
  local points = t.points()
  local q = points[at]
  local items = {}
  for _, shape in ipairs(SHAPES) do
    items[#items + 1] = {
      label = shape:sub(1, 1):upper() .. shape:sub(2),
      checked = q.shape == shape,
      enabled = t.has(shape),
      run = function() shape_points(t, t.points(), { at }, shape) end,
    }
  end
  items[#items + 1] = "-"
  items[#items + 1] = {
    label = "Set its value…",
    run = function()
      local s = state(win, t)
      s.beat, s.value = q.beat, q.value
      M.type_value()
    end,
  }
  items[#items + 1] = {
    label = "Remove the point",
    run = function()
      local list = t.points()
      table.remove(list, at)
      write(t, list, "Remove a point")
    end,
  }
  return items
end

local function curve_menu(win, t, where)
  local s = state(win, t)
  local whole = { kind = "line", c0 = 0, c1 = 0, r0 = 0, r1 = 0 }
  local visible = { kind = "char", c0 = s.left, c1 = axis_of(s):beat_of(s.geo.w), visual = true }
  return {
    { label = "Add a point here", run = function() M.add(false) end },
    { label = "Draw a wave over what shows…", run = function() wave_menu(visible.c0, visible.c1, where) end },
    "-",
    { label = "Thin out the points", run = function() M.ops.thin(whole) end },
    { label = "Smooth the curve", run = function() M.ops.smooth(whole) end },
    { label = "Quantize to the grid", run = function() M.ops.quantize(whole) end },
    "-",
    { label = "Close the window", run = function() layout.close(win) end, enabled = win ~= loose },
  }
end

function def.on_mouse(win, e)
  local t = M.target(win)
  if not t then return end
  local s = state(win, t)
  local geo = s.geo
  if not geo then return end
  -- The wheel scrolls in time; with Ctrl it zooms.
  local step = mouse.wheel(e)
  if step then
    if mouse.has(e, "C") then
      s.zoom = util.clamp(s.zoom * (step < 0 and 2 or 0.5), 0.125, 64)
    else
      s.left = math.max(0, s.left + axis_of(s):beats(step * 4))
    end
    return api.ui_redraw()
  end
  local inside = e.x >= geo.x and e.x < geo.x + geo.w and e.y >= geo.y and e.y < geo.y + geo.rows
  if e.kind == "move" then
    if inside then
      mouse.hint("curve: click a point to choose it, drag to move it · drag elsewhere to draw · right click for more")
    end
    return
  end
  if e.kind ~= "down" or not inside then return end
  if layout.current() ~= win and win ~= loose then layout.enter(win) end
  local where = { x = e.x + (e.view_x or 0), y = e.y + (e.view_y or 0) }
  local beat, value = at_cell(win, t, e.x, e.y)
  local points = t.points()
  -- A point under the press: its column, and a row of either side of it.
  local at
  for i, q in ipairs(points) do
    local x = geo.x + axis_of(s):x_of(q.beat)
    local y = geo.y + math.floor((1 - t.frac(q.value)) * (geo.rows - 0.01))
    if x == e.x and math.abs(y - e.y) <= 1 then at = i end
  end
  if e.button == "right" then
    return mouse.grab(e, {
      up = function(u)
        if u.moved then return end
        if at then return paw.ui.menu(point_menu(win, t, at), where) end
        s.beat, s.value = snapped(s, beat), value
        paw.ui.menu(curve_menu(win, t, where), where)
      end,
    })
  end
  if e.button ~= "left" then return end
  local free = mouse.has(e, "S")
  if at then
    -- Choose the point, and drag it in time and value.
    local q = points[at]
    s.beat, s.value = q.beat, q.value
    drag = { win = win.id }
    return mouse.grab(e, {
      drag = function(d)
        local b, v = at_cell(win, t, d.x, d.y)
        local moved = {}
        for i, p in ipairs(points) do
          moved[i] = curves.copy(p)
        end
        moved[at].beat, moved[at].value = snapped(s, b, free), util.clamp(v, t.min, t.max)
        drag.points = curves.sorted(moved)
        s.beat, s.value = moved[at].beat, moved[at].value
      end,
      up = function()
        local done = drag
        drag = nil
        if done and done.points then write(t, done.points, "Move a point") end
      end,
      cancel = function() drag = nil end,
    })
  end
  -- Elsewhere: draw. A click alone adds a point.
  local drawn = { [snapped(s, beat, free)] = value }
  s.beat, s.value = snapped(s, beat, free), value
  local function list()
    local out, from, to = {}, math.huge, -math.huge
    for b, v in pairs(drawn) do
      out[#out + 1] = { beat = b, value = v, shape = "linear", tension = 0 }
      from, to = math.min(from, b), math.max(to, b)
    end
    return curves.sorted(out), from, to
  end
  drag = { win = win.id }
  local prev_b, prev_v = s.beat, s.value
  mouse.grab(e, {
    drag = function(d)
      local b, v = at_cell(win, t, d.x, d.y)
      b = snapped(s, b, free)
      -- The steps a quick move jumps over are drawn on the line between.
      if not free and math.abs(b - prev_b) > s.grid + EPS then
        local dir = b > prev_b and 1 or -1
        for k = 1, math.floor(math.abs(b - prev_b) / s.grid + EPS) - 1 do
          local f = k * s.grid / math.abs(b - prev_b)
          drawn[prev_b + dir * k * s.grid] = prev_v + (v - prev_v) * f
        end
      end
      drawn[b] = v
      prev_b, prev_v = b, v
      s.beat, s.value = b, v
      local new, from, to = list()
      drag.points = curves.splice(points, from, to, new)
    end,
    up = function()
      drag = nil
      local new, from, to = list()
      write(t, curves.splice(points, from, to, new), #new > 1 and "Draw the curve" or "Add a point")
    end,
    cancel = function() drag = nil end,
  })
end

-- Automating a parameter ------------------------------------------------------------------

--- Automate a parameter of a device. paw makes its lane, with a first point
--- at its current value at the beat of the arrange cursor. paw shows the
--- lanes of the track as rows, with the cursor on the new lane, and tells you.
function M.automate(device_id, key)
  local d = api.device_get(device_id)
  local info
  for _, p in ipairs(d.param_info) do
    if p.key == key then info = p end
  end
  if not info then return paw.notify("no parameter `" .. tostring(key) .. "` on " .. d.name, "warn") end
  local device = paw.device(device_id)
  local lane = device:lane(key)
  local beat = paw.cursor.beat
  if lane then
    paw.notify(paw.lanes.name(lane.id) .. " is automated already: `gc` edits its curve")
  else
    api.undo_label("Automate " .. info.name)
    lane = device:automate(key)
    lane:add(beat, d.params[key])
    paw.notify(
      string.format(
        "%s automated: a point at %s, %s · `gc` edits the curve",
        paw.lanes.name(lane.id),
        paw.time.format(beat),
        paw.frontend.format_value(info, d.params[key])
      )
    )
  end
  paw.lanes.open(d.track)
  paw.cursor.set_track(d.track, lane.id)
  return lane
end

-- Commands and keys ---------------------------------------------------------------------

local command, map = paw.command, paw.keymap.set

command("curve.open", function(ctx)
  local uri = ctx.args[1] and tostring(ctx.args[1])
  local opts = {}
  if uri == "window" or uri == "here" or uri == "note" then
    opts[uri], uri = true, nil
  end
  for i = 2, #ctx.args do
    opts[tostring(ctx.args[i])] = true
  end
  if ctx.args.device and ctx.args.param then
    uri = paw.address.param(tonumber(ctx.args.device), tostring(ctx.args.param))
  end
  local why
  if not uri then
    uri, why = M.under_cursor(opts.note)
  end
  if not uri then return paw.notify(why, "warn") end
  local beat = paw.ui.focused ~= "curve" and paw.cursor.beat or nil
  if paw.ui.focused == "pianoroll" then
    local roll = paw.ui.views:get("pianoroll")
    local clip = roll:clip()
    beat = clip and clip.start + roll.beat
  end
  local win, err = M.open(uri, { window = opts.window, here = opts.here, vertical = opts.vertical, beat = beat })
  if not win then return paw.notify(err, "warn") end
end, {
  desc = "Edit a curve: `curve.open paw://lane/3`, `curve.open paw://tempo`; without one, what the cursor is on (a lane row, a parameter, the piano roll's strip; `note` the note's own); `window` in a window of its own",
  complete = function() return { "window", "here", "note", "vertical", "paw://tempo" } end,
})
command("curve.window", function()
  local win = M.current()
  local uri = win and uri_of(win)
  if not uri then return paw.notify("no curve here: `:curve.open` opens one", "warn") end
  M.open(uri, { window = true })
end, { desc = "Show this curve in a window of its own, in the graphical frontend" })
command("param.automate", function(ctx)
  local device, key = tonumber(ctx.args[1]), ctx.args[2] and tostring(ctx.args[2])
  if not (device and key) then
    local _, row = paw.ui.views:get("devices"):selected()
    if not (row and row.param) then return paw.notify("no parameter under the cursor", "warn") end
    device, key = row.device.id, row.param.key
  end
  M.automate(device, key)
end, {
  desc = "Automate a parameter (the device panel's under the cursor): its lane, a first point at its value at the cursor, shown as a row",
})
command("curve.generate", function(ctx)
  local win, _, s = here()
  if not win then return end
  local sel = paw.keymap.selection()
  local from, to = s.left, axis_of(s):beat_of(s.geo and s.geo.w or 40)
  if sel and sel.view == "curve" then
    from, to = sel.c0, sel.c1
  end
  paw.keymap.set_mode("n")
  M.generate(
    ctx.args[1] and tostring(ctx.args[1]) or "sine",
    from,
    to,
    { rate = ctx.args.rate, depth = ctx.args.depth }
  )
end, {
  desc = "Draw a wave over the selection, or what shows: `curve.generate sine rate=1 depth=0.5` (rate in beats a cycle, depth a fraction of the height)",
  complete = function() return curves.waves end,
})

local nx = { "n", "x" }
local motion = { motion = true }
local function cmap(lhs, rhs, desc, opts) map(lhs, rhs, util.merge({ view = "curve", desc = desc }, opts)) end
local function count(fn)
  return function(ctx) fn(ctx.count or 1) end
end

cmap("l", count(M.move), "Right one grid step", motion)
cmap("h", count(function(n) M.move(-n) end), "Left one grid step", motion)
cmap("<Right>", count(M.move), "Right one grid step", motion)
cmap("<Left>", count(function(n) M.move(-n) end), "Left one grid step", motion)
cmap("k", count(M.climb), "A step higher", motion)
cmap("j", count(function(n) M.climb(-n) end), "A step lower", motion)
cmap("<Up>", count(M.climb), "A step higher", motion)
cmap("<Down>", count(function(n) M.climb(-n) end), "A step lower", motion)
cmap("<C-u>", count(function(n) M.climb(10 * n) end), "Ten steps higher", motion)
cmap("<C-d>", count(function(n) M.climb(-10 * n) end), "Ten steps lower", motion)
cmap("w", function(ctx) M.to_point(1, ctx.count) end, "Next point", motion)
cmap("b", function(ctx) M.to_point(-1, ctx.count) end, "Previous point", motion)
cmap("e", function(ctx) M.to_point(1, ctx.count) end, "Next point", motion)
cmap("0", function() M.to_end(-1) end, "First point", motion)
cmap("$", function() M.to_end(1) end, "Last point", motion)
cmap("o", function() M.add(false) end, "Add a point at the cursor")
cmap("A", function() M.add(true) end, "Add a point on the curve at the cursor")
cmap("x", count(M.remove), "Remove the point under the cursor")
-- A point's main value is its height, its second the bend of the smooth
-- stretch from it.
cmap("+", count(M.nudge_point), "Raise the point under the cursor", { role = "main+" })
cmap("-", count(function(n) M.nudge_point(-n) end), "Lower the point under the cursor", { role = "main-" })
cmap("<C-a>", count(M.nudge_point), "Raise the point under the cursor by the count", { role = "main+" })
cmap(
  "<C-x>",
  count(function(n) M.nudge_point(-n) end),
  "Lower the point under the cursor by the count",
  { role = "main-" }
)
cmap("]", count(function(n) M.tension(0.25 * n) end), "Bend the smooth stretch: move early", { role = "second+" })
cmap("[", count(function(n) M.tension(-0.25 * n) end), "Bend the smooth stretch: move late", { role = "second-" })
cmap("c", M.type_value, "Type the value of the point under the cursor")
cmap("~", M.cycle_shape, "The next shape of the stretch from the point: straight, held, smooth")
cmap("i", function() M.insert_start(false) end, "Draw: the cursor's moves put points, from its value")
cmap("a", function() M.insert_start(true) end, "Draw from the curve's value at the cursor")
cmap("p", function(ctx) M.paste(ctx.register, ctx.count) end, "Paste points at the cursor")
cmap("zi", function() M.zoom(2) end, "Zoom in")
cmap("zo", function() M.zoom(0.5) end, "Zoom out")
cmap("]g", function() M.grid(2) end, "Coarser grid")
cmap("[g", function() M.grid(0.5) end, "Finer grid")
cmap("<C-w>f", "curve.window", "Show the curve in a window of its own")

local function op(lhs, fn, desc) map(lhs, nil, { view = "curve", mode = nx, desc = desc, operator = fn }) end
op("d", M.ops.delete, "Delete points")
op("y", M.ops.yank, "Yank points")
op("gS", M.ops.thin, "Thin out points")
op("gs", M.ops.smooth, "Smooth points")
op("gq", M.ops.quantize, "Quantize points to the grid")
op(">", M.ops.shift(1), "Move points later")
op("<lt>", M.ops.shift(-1), "Move points earlier")
function M.ops.wave(region)
  if region.kind == "line" then
    local win, _, s = here()
    if not win then return end
    return wave_menu(s.left, axis_of(s):beat_of(s.geo.w))
  end
  wave_menu(region.c0, region.c1)
end
-- `~` looks like a wave.
op("g~", M.ops.wave, "Draw a wave")
local function vmap(lhs, fn, desc) map(lhs, nil, { view = "curve", mode = "x", desc = desc, operator = fn }) end
vmap("x", M.ops.delete, "Delete the points selected")
vmap("+", M.ops.raise(1), "Raise the points selected")
vmap("-", M.ops.raise(-1), "Lower the points selected")
vmap("<C-a>", M.ops.raise(1), "Raise the points selected by the count")
vmap("<C-x>", M.ops.raise(-1), "Lower the points selected by the count")
vmap("L", M.ops.shift(1), "Move the points selected later")
vmap("H", M.ops.shift(-1), "Move the points selected earlier")
vmap("~", M.ops.shape, "The next shape for the points selected")

-- Insert mode: each move of the cursor draws.
local function imap(lhs, fn, desc)
  map(lhs, function(ctx)
    fn(ctx)
    M.insert_mark()
  end, { view = "curve", mode = "i", desc = desc })
end
imap("l", function() M.move(1) end, "Draw a grid step right")
imap("h", function() M.move(-1) end, "Back a grid step")
imap("<Right>", function() M.move(1) end, "Draw a grid step right")
imap("<Left>", function() M.move(-1) end, "Back a grid step")
imap("k", function() M.climb(1) end, "Draw a step higher")
imap("j", function() M.climb(-1) end, "Draw a step lower")
imap("<Up>", function() M.climb(1) end, "Draw a step higher")
imap("<Down>", function() M.climb(-1) end, "Draw a step lower")
imap("K", function() M.climb(10) end, "Draw ten steps higher")
imap("J", function() M.climb(-10) end, "Draw ten steps lower")
imap("<C-u>", function() M.climb(10) end, "Draw ten steps higher")
imap("<C-d>", function() M.climb(-10) end, "Draw ten steps lower")

-- A wave's choices.
local function gmap(lhs, fn, desc) map(lhs, fn, { view = "curve.gen", desc = desc, repeatable = false }) end
gmap("<Tab>", function() M.gen_next(1) end, "The wave's next choice")
gmap("<S-Tab>", function() M.gen_next(-1) end, "The wave's choice before")
gmap("<C-n>", function() M.gen_step(1) end, "Change the choice")
gmap("<C-p>", function() M.gen_step(-1) end, "Change the choice back")
gmap("<C-y>", M.gen_finish, "Keep the wave")
gmap("<Esc>", M.gen_finish, "Keep the wave")
paw.on("view.focused", function()
  if gen then M.gen_finish() end
end)

paw.ui.keybar.set("curve", "n", {
  { "i", "draw" },
  { "o", "point" },
  { "x", "remove" },
  { "w", "next" },
  { "~", "shape" },
  { "g~", "wave" },
  { "?", "keys" },
})
paw.ui.keybar.set(
  "curve",
  "i",
  { { "h", "back" }, { "l", "right" }, { "k", "up" }, { "j", "down" }, { "<Esc>", "write" } }
)
paw.ui.keybar.set(
  "curve",
  "x",
  { { "d", "delete" }, { "+", "raise" }, { "<lt>", "earlier" }, { ">", "later" }, { "gs", "smooth" }, { "g~", "wave" } }
)
paw.ui.keybar.set("curve.gen", "n", { { "<Tab>", "next choice" }, { "<C-n>", "change" }, { "<C-y>", "keep" } })

-- Where it opens from: `gC` or Enter on a lane row, a parameter, the mixer's
-- fader or pan, the piano roll's strip (`gX` the note's own expression).
map("gC", "curve.open", { view = "arrange.lane", desc = "Edit this lane's curve" })
map("<CR>", "curve.open", { view = "arrange.lane", desc = "Edit this lane's curve" })
map("gC", "curve.open", { view = "devices", desc = "Edit the parameter's curve" })
map(
  "A",
  "param.automate",
  { view = "devices", desc = "Automate the parameter: its lane, with a point at its value at the cursor" }
)
map("gC", "curve.open", { view = "pianoroll", desc = "Edit the strip's controller as a curve" })
map("gX", "curve.open note", { view = "pianoroll", desc = "Edit the note's own expression as a curve" })

-- The keys the curve editor had before the rule (`paw.opt.keys = "classic"`).
local function classic(lhs, rhs, desc, opts)
  paw.keymap.classic(lhs, rhs, util.merge({ view = "curve", desc = desc }, opts))
end
classic("K", count(function(n) M.climb(10 * n) end), "Ten steps higher", motion)
classic("J", count(function(n) M.climb(-10 * n) end), "Ten steps lower", motion)
classic("s", M.cycle_shape, "The next shape of the stretch from the point: straight, held, smooth")
classic(">", count(function(n) M.tension(0.25 * n) end), "Bend the smooth stretch: move early", { mode = "n" })
classic("<lt>", count(function(n) M.tension(-0.25 * n) end), "Bend the smooth stretch: move late", { mode = "n" })
classic("gw", "curve.window", "Show the curve in a window of its own")
classic("gn", nil, "Draw a wave", { mode = nx, operator = M.ops.wave })
paw.keymap.classic("gc", "curve.open", { view = "pianoroll", desc = "Edit the strip's controller as a curve" })
paw.keymap.classic("gC", "curve.open note", { view = "pianoroll", desc = "Edit the note's own expression as a curve" })
paw.keymap.classic("gc", "curve.open", { view = "devices", desc = "Edit the parameter's curve" })

-- The frontends' menus and gestures.
paw.frontend.act.automate_param = function(device, key) return M.automate(device, key) end
paw.frontend.act.open_curve = function(uri, window) return M.open(uri, { window = window }) end

return M
