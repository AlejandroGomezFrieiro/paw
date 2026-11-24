-- The vocal editor's window, curve panel: one singing curve at a time under
-- the notes, in time with them, chosen from the tabs above it. A curve is
-- an automation lane on a parameter of the part's `utau` device (see the
-- extension's README), so what is drawn here is that lane.
--
-- Drag to draw; right drag puts the curve back to its default over that
-- stretch; double click puts it back under the note above.
local api = paw.api
local util = paw.util
local notes = require("utau.notes")
local c = require("paw.canvas").palette

local TABS = 22
local SHORT = {
  pitd = "Pitch",
  dyn = "Dynamics",
  tenc = "Tension",
  brec = "Breathiness",
  genc = "Gender",
  voic = "Voicing",
  shfc = "Tone shift",
  grwc = "Growl",
  xsy = "Cross synth",
}

return function(gui)
  local M = {}
  local x_of, beat_at = gui.x_of, gui.beat_at

  --- Where the graph is, and a value's height in it and back.
  local function graph()
    local geo = gui.geo
    local top = geo.curve_y + TABS + 6
    local h = geo.curve_h - TABS - 12
    return top, h
  end
  local function y_of(info, v, top, h) return top + (1 - (v - info.min) / (info.max - info.min)) * h end
  local function value_at_y(info, y, top, h)
    return util.clamp(info.min + (1 - (y - top) / h) * (info.max - info.min), info.min, info.max)
  end

  function M.paint(view, g, S)
    local geo = gui.geo
    local w = geo.w - geo.side_w
    local cy = geo.curve_y
    local list = view:curves()
    local info = view:curve_info() or list[1]
    if not info then return end
    view.curve = info.key
    g:rect(0, cy, w, geo.curve_h, { fill = c.well })
    g:rect(0, cy, w, TABS, { fill = c.panel })
    -- The tabs, one per curve; a dot on those that have a lane.
    local lanes = {}
    for _, lane in ipairs(api.lane_list(S.clip.part)) do
      if lane.target == "param" and lane.device == S.device and lane.point_count > 0 then lanes[lane.param] = true end
    end
    local x = gui.KEYS
    for _, cinfo in ipairs(list) do
      local label = (SHORT[cinfo.key] or cinfo.name) .. (lanes[cinfo.key] and " •" or "")
      x = gui.button(
        g,
        x,
        cy + 2,
        label,
        cinfo.key == info.key,
        function() view.curve = cinfo.key end,
        { height = 18, size = 11, width = #label * 6.5 + 14 }
      )
      x = x - 2
    end
    local top, h = graph()
    local area = g:sub(gui.KEYS, cy + TABS, S.roll_w, geo.curve_h - TABS)
    local oy = cy + TABS
    -- The beats, as above, and the notes' edges, faintly.
    for _, line in ipairs(S.beat_lines or {}) do
      area:line(line.x, 0, line.x, geo.curve_h, { color = line.bar and c.text_3 or c.line_beat })
    end
    for _, n in ipairs(S.list) do
      local nx = x_of(n.start)
      if nx >= 0 and nx <= S.roll_w then
        area:rect(nx, 2, math.max(2, n.length * gui.zoom - 1), 3, { fill = S.hue .. "88", radius = 1 })
      end
    end
    -- The default, as a line across.
    local dy = y_of(info, info.default, top, h) - oy
    area:line(0, dy, S.roll_w, dy, { color = c.text_3, width = 1 })
    -- The curve: its lane's points as they are joined, else the value the
    -- parameter holds.
    local lane = notes.lane(S.clip.part, S.device, info.key)
    local points = lane and api.lane_points(lane) or {}
    local constant = api.device_get(S.device).params[info.key] or info.default
    local line = {}
    local first, last = S.clip.start + beat_at(-4), S.clip.start + beat_at(S.roll_w + 4)
    local function put(beat, v)
      line[#line + 1] = x_of(beat - S.clip.start)
      line[#line + 1] = y_of(info, v, top, h) - oy
    end
    if #points == 0 then
      put(first, constant)
      put(last, constant)
    else
      local value = notes.sampler(points, info.default)
      put(first, value(first))
      for _, p in ipairs(points) do
        if p[1] > first and p[1] < last then put(p[1], p[2]) end
      end
      put(last, value(last))
    end
    -- Filled from the default, so that a curve reads at a glance.
    local fill = { x_of(first - S.clip.start), dy }
    for i = 1, #line do
      fill[#fill + 1] = line[i]
    end
    fill[#fill + 1], fill[#fill + 2] = x_of(last - S.clip.start), dy
    area:poly(fill, { fill = c.play_on .. "30" })
    area:poly(line, { color = c.play_on, width = 2 })
    -- What is being drawn or erased.
    local drag = gui.drag
    if drag and drag.mode == "curve" and #drag.line >= 4 then area:poly(drag.line, { color = c.warn, width = 2 }) end
    if drag and drag.mode == "erase" then
      local x0, x1 = math.min(drag.x0, drag.x1), math.max(drag.x0, drag.x1)
      area:rect(x0, 0, x1 - x0, geo.curve_h - TABS, { fill = c.error .. "33", stroke = c.error })
    end
    local cx = x_of(view.beat)
    area:line(cx, 0, cx, geo.curve_h, { color = c.select .. "66" })
    local t = api.transport_get()
    if t.position >= S.clip.start and t.position <= S.clip.start + S.clip.length then
      local px = x_of(t.position - S.clip.start)
      area:line(px, 0, px, geo.curve_h, { color = c.select, width = 2 })
    end
    -- The scale on the left, and the value at the cursor.
    g:rect(0, cy + TABS, gui.KEYS, geo.curve_h - TABS, { fill = c.panel })
    g:text(
      gui.KEYS - 6,
      top - 6,
      string.format("%g", info.max),
      { color = c.text_3, size = 9, align = "right", width = gui.KEYS - 8 }
    )
    g:text(
      gui.KEYS - 6,
      top + h - 6,
      string.format("%g", info.min),
      { color = c.text_3, size = 9, align = "right", width = gui.KEYS - 8 }
    )
    local here = #points > 0 and notes.value_at(points, S.clip.start + view.beat, info.default) or constant
    g:text(
      6,
      top + h / 2 - 8,
      string.format("%g", math.floor(here * 10 + 0.5) / 10),
      { color = c.play_on, size = 12, bold = true, width = gui.KEYS - 8 }
    )
    g:text(6, top + h / 2 + 6, "at cursor", { color = c.text_3, size = 8, width = gui.KEYS - 8 })
    S.curve = { info = info, top = top, h = h }
  end

  local function stroke(view, e, clip, x)
    local d = gui.drag
    local info = d.info
    if e.kind == "move" then
      if d.mode == "curve" then
        local beat = util.clamp(beat_at(x), 0, clip.length)
        local v = value_at_y(info, e.y, d.top, d.h)
        -- A drag back over what it drew draws it again.
        while #d.samples > 0 and d.samples[#d.samples][1] >= clip.start + beat - 1e-9 and #d.samples > 1 do
          table.remove(d.samples)
          table.remove(d.line)
          table.remove(d.line)
        end
        d.samples[#d.samples + 1] = { clip.start + beat, v }
        d.line[#d.line + 1] = x_of(beat)
        d.line[#d.line + 1] = e.y - gui.geo.curve_y - TABS
        d.label = string.format(
          "%s %g at %s",
          info.name:lower(),
          math.floor(v * 10 + 0.5) / 10,
          paw.time.format(clip.start + beat)
        )
      else
        d.x1 = x
        local a, b = beat_at(math.min(d.x0, d.x1)), beat_at(math.max(d.x0, d.x1))
        d.label = string.format(
          "%s back to %g from %s to %s",
          info.name:lower(),
          info.default,
          paw.time.format(clip.start + math.max(0, a)),
          paw.time.format(clip.start + b)
        )
      end
    elseif e.kind == "up" then
      gui.drag = nil
      if d.mode == "erase" then d.x1 = x end
      local device = view:device()
      if not device then return end
      if d.mode == "curve" and #d.samples >= 1 then
        table.sort(d.samples, function(a, b) return a[1] < b[1] end)
        notes.stroke(clip.part, device, info.key, d.samples)
      elseif d.mode == "erase" then
        local a = clip.start + math.max(0, beat_at(math.min(d.x0, d.x1)))
        local b = clip.start + math.min(clip.length, beat_at(math.max(d.x0, d.x1)))
        if b - a < 1e-6 then
          local note = notes.near(clip.id, a - clip.start)
          if note then
            a, b = clip.start + note.start, clip.start + note.start + note.length
          end
        end
        if b > a then notes.reset(clip.part, device, info.key, a, b) end
      end
    end
  end

  --- A press in the curve panel.
  function M.pointer(view, e, clip)
    local S = gui.S
    if not (S and S.curve) or e.y < gui.geo.curve_y + TABS or e.x < gui.KEYS then return end
    local info, x = S.curve.info, e.x - gui.KEYS
    view.beat = util.clamp(gui.snap(beat_at(x) - paw.timegrid.step("note") / 2), 0, clip.length)
    if e.kind == "double" then
      gui.drag = nil
      local note = notes.near(clip.id, beat_at(x))
      if note then
        notes.reset(clip.part, view:device(), info.key, clip.start + note.start, clip.start + note.start + note.length)
      end
      return
    end
    if e.button == "right" then
      gui.drag = { mode = "erase", panel = stroke, info = info, x0 = x, x1 = x }
    else
      gui.drag =
        { mode = "curve", panel = stroke, info = info, samples = {}, line = {}, top = S.curve.top, h = S.curve.h }
      stroke(view, { kind = "move", x = e.x, y = e.y }, clip, x)
    end
  end

  return M
end
