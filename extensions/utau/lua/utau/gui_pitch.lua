-- The vocal editor's window, Pitch tool and phoneme row: each note's
-- transition points (OpenUtau's pitch points, `note.meta.utau.pp`), the
-- handles of its vibrato (`vb`), and the starts and names of its phonemes.
--
-- Points: drag one to move it, double click a note to add one where the
-- pointer is, right click to remove one (two stay), Ctrl+click to change
-- how the line leaves it (ease in and out, straight, ease in, ease out).
-- Vibrato, on the notes the edits work on: drag its start (length), its
-- fades, its depth (up and down), a period, a trough (shift) and its drift.
-- Ctrl+click a note switches its vibrato on or off.
local util = paw.util
local api = paw.api
local notes = require("utau.notes")
local shapes = require("utau.shapes")
local proto = require("utau.proto")
local c = require("paw.canvas").palette

local VIB_COLOURS = {
  length = "#ffd040",
  ["in"] = "#ff9f40",
  out = "#ff9f40",
  depth = "#ff6fae",
  period = "#40d0ff",
  shift = "#8f8fff",
  drift = "#b0e060",
}
local VIB_NAMES = {
  length = "start",
  ["in"] = "fade in",
  out = "fade out",
  depth = "depth",
  period = "period",
  shift = "shift",
  drift = "drift",
}

return function(gui)
  local M = {}
  local x_of, y_of, beat_at, pitch_at = gui.x_of, gui.y_of, gui.beat_at, gui.pitch_at

  --- A marker for a point of a transition, shaped by how the line leaves it.
  local function marker(roll, x, y, shape, colour, big)
    local r = big and 5.5 or 4.5
    if shape == 1 then
      roll:poly({ x, y - r, x + r, y, x, y + r, x - r, y }, { fill = colour, color = c.surface, width = 1 })
    elseif shape == 2 then
      roll:poly({ x - r, y + r, x + r, y + r, x, y - r }, { fill = colour, color = c.surface, width = 1 })
    elseif shape == 3 then
      roll:poly({ x - r, y - r, x + r, y - r, x, y + r }, { fill = colour, color = c.surface, width = 1 })
    else
      roll:rect(x - r, y - r, 2 * r, 2 * r, { fill = colour, stroke = c.surface, radius = r })
    end
  end

  --- The pitch of a note's line at a beat of the clip, as a y in the roll.
  local function y_cents(note, cents) return y_of(note.pitch + cents / 100) + gui.row / 2 end

  function M.paint(view, roll, S)
    local list, tempo, drag = S.list, S.tempo, gui.drag
    local left, right = beat_at(-40), beat_at(S.roll_w + 40)
    S.pp_handles, S.vb_handles = {}, {}
    for i, note in ipairs(list) do
      if note.start + note.length >= left and note.start - 0.5 <= right then
        local pp = (drag and drag.mode == "pp" and drag.index == i) and drag.pp or shapes.pp(note)
        local pts = shapes.points(note, list[i - 1], pp)
        if #pts >= 2 then
          local line = {}
          local a, b = pts[1][1], pts[#pts][1]
          local steps = math.max(2, math.floor((b - a) / 4))
          for s = 0, steps do
            local ms = a + (b - a) * s / steps
            line[#line + 1] = x_of(note.start + shapes.beats(ms, tempo))
            line[#line + 1] = y_cents(note, shapes.transition_at(pts, ms) * 100)
          end
          roll:poly(line, { color = c.play_on, width = 1.5 })
        end
        local own = shapes.has_pp(note)
        for k, p in ipairs(pts) do
          local px, py = x_of(note.start + shapes.beats(p[1], tempo)), y_cents(note, p[2] * 10)
          if px > -10 and px < S.roll_w + 10 then
            local held = drag and drag.mode == "pp" and drag.index == i and drag.k == k
            marker(roll, px, py, p[3], held and c.warn or own and c.play_on or c.play_on .. "99", held)
            S.pp_handles[#S.pp_handles + 1] = { index = i, k = k, x = px, y = py }
          end
        end
      end
    end
    -- Vibrato: the line it sings and its handles, on the notes edited.
    for _, i in ipairs(S.targets) do
      local note = list[i]
      local vb = (drag and drag.mode == "vb" and drag.index == i) and drag.vb or shapes.vb(note)
      if note and vb then
        local dur = shapes.ms(note.length, tempo)
        local line = {}
        local from = 1 - vb[1] / 100
        local steps = math.max(8, math.floor(note.length * vb[1] / 100 * gui.zoom / 2))
        for s = 0, steps do
          local pos = from + (1 - from) * s / steps
          line[#line + 1] = x_of(note.start + note.length * pos)
          line[#line + 1] = y_cents(note, shapes.vibrato_at(vb, pos, dur))
        end
        roll:poly(line, { color = "#ff6fae", width = 1.5 })
        local h = shapes.vibrato_handles(note, vb, tempo)
        -- Handles stand clear of the note however shallow the vibrato is.
        local cy = y_cents(note, 0)
        local lift = math.max(14, vb[3] / 100 * gui.row)
        local depth_y = cy - lift
        roll:line(
          x_of(note.start + h["in"][1]),
          depth_y,
          x_of(note.start + h.out[1]),
          depth_y,
          { color = "#ff6fae66", width = 1 }
        )
        for _, which in ipairs({ "length", "in", "out", "depth", "period", "shift", "drift" }) do
          local hb = h[which]
          local hx, hy = x_of(note.start + hb[1]), y_cents(note, hb[2])
          if which == "in" or which == "out" or which == "depth" then hy = cy - lift end
          if which == "shift" then hy = cy + lift end
          local held = drag and drag.mode == "vb" and drag.index == i and drag.which == which
          roll:rect(
            hx - 4.5,
            hy - 4.5,
            9,
            9,
            { fill = held and c.warn or VIB_COLOURS[which], stroke = c.surface, radius = which == "depth" and 2 or 4.5 }
          )
          if which == "length" then roll:text(hx + 6, hy - 16, "vibrato", { color = VIB_COLOURS.length, size = 10 }) end
          S.vb_handles[#S.vb_handles + 1] = { index = i, which = which, x = hx, y = hy }
        end
      end
    end
  end

  local function nearest(handles, x, y, reach)
    local best, best_d
    for _, h in ipairs(handles or {}) do
      local d = (h.x - x) ^ 2 + (h.y - y) ^ 2
      if d <= reach * reach and (not best_d or d < best_d) then
        best, best_d = h, d
      end
    end
    return best
  end

  --- The note sounding at a beat, whatever its pitch.
  local function note_over(list, beat)
    for i = #list, 1, -1 do
      local n = list[i]
      if beat >= n.start and beat < n.start + n.length then return n, i end
    end
  end

  local function store_pp(view, index, pp)
    notes.change_props(view.clip_id, function(p)
      p.pp = { snap = pp.snap, pts = pp.pts }
      return true
    end, { [index] = true })
  end

  -- Dragging a transition point.
  local function pp_drag(view, e, clip, x, y)
    local d = gui.drag
    if e.kind == "move" then
      local pts = shapes.copy(d.pp0.pts)
      local p = pts[d.k]
      local lo = pts[d.k - 1] and pts[d.k - 1][1] or -1e9
      local hi = pts[d.k + 1] and pts[d.k + 1][1] or 1e9
      local dms = shapes.ms((x - d.x0) / gui.zoom, d.tempo)
      local dy = (d.y0 - y) / gui.row * 10
      p[1] = util.clamp(math.floor(p[1] + dms + 0.5), lo, hi)
      d.pp = { snap = d.pp0.snap, pts = pts }
      if d.k == 1 and d.pp0.snap and math.abs(dy) < 0.5 then
        -- Still where the note before ends.
        p[2] = d.pp0.pts[1][2]
      else
        -- The first point moved up or down no longer follows the note before.
        p[2] = math.floor((d.shown_y + dy) * 10 + 0.5) / 10
        if d.k == 1 then d.pp.snap = false end
      end
      d.moved = true
      d.label = string.format("point %d: %+d ms, %+.1f semitones, %s", d.k, p[1], p[2] / 10, shapes.SHAPES[p[3]])
    elseif e.kind == "up" then
      gui.drag = nil
      if d.moved then store_pp(view, d.index, d.pp) end
    end
  end

  -- Dragging a vibrato handle.
  local function vb_drag(view, e, clip, x, y)
    local d = gui.drag
    if e.kind == "move" then
      d.vb = shapes.drag_vibrato(d.vb0, d.which, d.note, (x - d.x0) / gui.zoom, (d.y0 - y) / gui.row * 100, d.tempo)
      d.moved = true
      local vb = d.vb
      d.label = string.format(
        "vibrato %s · length %g%%  period %g ms  depth %g c  in %g%%  out %g%%  shift %g%%  drift %g%%",
        VIB_NAMES[d.which],
        vb[1],
        vb[2],
        vb[3],
        vb[4],
        vb[5],
        vb[6],
        vb[7]
      )
    elseif e.kind == "up" then
      gui.drag = nil
      if d.moved then
        notes.change_props(view.clip_id, function(p)
          p.vb = d.vb
          return true
        end, { [d.index] = true })
      end
    end
  end

  --- A press or double click in the roll with the Pitch tool. Returns true
  --- when it was on a point, a handle or a note's vibrato switch.
  function M.pointer(view, e, clip, list, x, y)
    local S = gui.S or {}
    local tempo = api.project_get("tempo")
    if e.kind == "double" then
      local note, index = note_over(list, beat_at(x))
      if not note then return true end
      local pp = shapes.pp(note)
      local ms = math.floor(shapes.ms(beat_at(x) - note.start, tempo) + 0.5)
      local tenths = math.floor((pitch_at(y) + 0.5 - note.pitch) * 100 + 0.5) / 10
      for _, p in ipairs(pp.pts) do
        if math.abs(p[1] - ms) < 2 then return true end
      end
      table.insert(pp.pts, { ms, tenths, 0 })
      table.sort(pp.pts, function(a, b) return a[1] < b[1] end)
      store_pp(view, index, pp)
      gui.drag = nil
      return true
    end
    local h = nearest(S.vb_handles, x, y, 7)
    if h and e.button ~= "right" then
      local note = list[h.index]
      gui.drag = {
        mode = "vb",
        panel = vb_drag,
        index = h.index,
        which = h.which,
        note = note,
        vb0 = shapes.vb(note),
        x0 = x,
        y0 = y,
        tempo = tempo,
      }
      gui.drag.vb = gui.drag.vb0
      if not gui.drag.vb0 then gui.drag = nil end
      return true
    end
    h = nearest(S.pp_handles, x, y, 7)
    if h then
      local note = list[h.index]
      if not note then return true end
      local pp = shapes.pp(note)
      if e.button == "right" then
        if #pp.pts > 2 then
          table.remove(pp.pts, h.k)
          store_pp(view, h.index, pp)
        else
          paw.notify("a transition keeps two points", "warn")
        end
      elseif e.ctrl then
        pp.pts[h.k][3] = ((pp.pts[h.k][3] or 0) + 1) % 4
        store_pp(view, h.index, pp)
        paw.notify("point " .. h.k .. ": " .. shapes.SHAPES[pp.pts[h.k][3]])
      else
        local shown = shapes.points(note, list[h.index - 1], pp)
        gui.drag = {
          mode = "pp",
          panel = pp_drag,
          index = h.index,
          k = h.k,
          pp0 = pp,
          pp = pp,
          x0 = x,
          y0 = y,
          tempo = tempo,
          shown_y = shown[h.k][2],
        }
      end
      return true
    end
    local note, index = gui.note_at(list, x, y)
    if note and e.ctrl and e.button ~= "right" then
      notes.change_props(view.clip_id, function(p)
        p.vb = not shapes.vb(note) and shapes.copy(shapes.DEFAULT_VB) or nil
        return true
      end, { [index] = true })
      view.pitch, view.beat = note.pitch, note.start
      return true
    end
    -- A click on a note makes it the one whose vibrato shows.
    if note and e.button ~= "right" and not next(view.sel) then
      view.pitch, view.beat = note.pitch, note.start
    end
    return false
  end

  -- Phonemes -----------------------------------------------------------------------

  local function ph_drag(view, e, clip, x)
    local d = gui.drag
    if e.kind == "move" then
      local ticks = (x - d.x0) / gui.zoom * proto.TICKS
      local step = e.shift and 1 or 5
      d.dticks = math.floor(ticks / step + 0.5) * step
      d.label = string.format(
        "phoneme %s starts %+d ticks (%+d ms) from where it was; Shift for single ticks",
        d.name,
        d.dticks,
        math.floor(shapes.ms(d.dticks / proto.TICKS, api.project_get("tempo")) + 0.5)
      )
    elseif e.kind == "up" then
      gui.drag = nil
      if d.dticks ~= 0 then
        view:set_phoneme(d.note, d.k, "offset", (view:phoneme_override(d.note, d.k).offset or 0) + d.dticks)
      end
    end
  end

  --- A press or double click in the phoneme row.
  function M.phoneme_pointer(view, e, clip)
    local S = gui.S or {}
    local x = e.x - gui.KEYS
    local hit, edge
    for _, b in ipairs(S.phoneme_boxes or {}) do
      if math.abs(x - b.x0) <= 5 and (not edge or math.abs(x - b.x0) < math.abs(x - edge.x0)) then edge = b end
      if x >= b.x0 and x < b.x1 then hit = b end
    end
    local b = edge or hit
    if not b then return end
    view:go_to(b.note)
    view.ph = { note = b.note, k = b.k }
    if e.button == "right" then return view:reset_phoneme() end
    if e.kind == "double" then
      gui.drag = nil
      return view:replace_phoneme()
    end
    if edge then
      local p = b.p
      gui.drag = {
        mode = "phoneme",
        panel = ph_drag,
        note = b.note,
        k = b.k,
        x0 = x,
        dticks = 0,
        name = p.phoneme ~= "" and p.phoneme or p.alias,
      }
    end
  end

  return M
end
