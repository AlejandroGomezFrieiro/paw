-- The pointer in the piano roll: a pencil, as in REAPER's MIDI editor. A
-- press on empty grid draws a note as long as the drag (a click gives the
-- roll's note length), a press on a note chooses it and a drag moves it,
-- or either end of it; the right button drags a box that chooses notes, or
-- clicked removes a note or opens the menu; Alt and a drag erases. The
-- keyboard sounds a key; the velocity strip is drawn on; the row of tools
-- does what each says.
--
-- The roll marks every part of itself as a hit region when it draws (the
-- grid is a plane, each note on it a role): a press comes here as the
-- gesture of what it is on (`view.gestures`), from the terminal in cells
-- and from a window in fractions of them (`e.fine`), so both frontends do
-- the same. Each gesture calls `paw.frontend.act` once, and is drawn as a
-- layer of the roll until the button is let go. Beats are the roll's (the
-- active clip's); a note of another clip edited with it is named by that
-- clip and its place there.
local api = paw.api
local util = paw.util
local music = paw.music
local mouse = paw.mouse
local menus = require("paw.mouse_menus")
local strip = require("paw.views.pianoroll_strip")
local view = paw.ui.views.pianoroll
local A = paw.frontend.act

local function beat_at(self, tx) return mouse.beat(tx, self.scroll, self.geometry.zoom) end

--- The grid step a column falls in, or with `free` the column's own beat.
local function start_at(self, tx, free)
  if free then return beat_at(self, tx) end
  return mouse.on_grid(tx, self.scroll, self.geometry.zoom, paw.opt.note_grid)
end

--- Where the grid step under the pointer ends: a drag to a column takes in
--- the step drawn there. A terminal's column is its left edge, so the
--- step it shows ends a column on; a window's pointer is where it is.
local function end_at(self, tx, free, fine)
  local beat = beat_at(self, tx + (fine and 0 or 1))
  if free then return beat end
  local grid = paw.opt.note_grid
  return math.ceil(beat / grid - 1e-6) * grid
end

--- The pitch of a row of the view, which may be a fraction of one.
local function pitch_of(self, y)
  local g = self.geometry
  return util.clamp(self.top - math.floor((y - g.head) / (g.per or 1)), 0, 127)
end

--- Rows a drag went, as whole pitches: a pitch is `per` rows tall.
local function rows_moved(d, per) return math.floor(d.dy / (per or 1) + 0.5) end

--- What a press is on, from the hit region it found: `area` "ruler",
--- "keys", "grid", "velocity" or "tool", the column of the roll, the beat
--- and the pitch there, and on a note the note (its start in the roll's
--- beats), the clip it is in (`owner`) with its place there, and the part
--- pressed ("start", "end" or "body").
local function hit_of(self, e)
  local g, a = self.geometry, e.hit
  local out = { area = a.kind == "note" and "grid" or a.kind, tx = e.x - g.keys }
  out.beat = beat_at(self, out.tx)
  if a.kind == "grid" and e.at then
    out.pitch = util.clamp(math.floor(e.at.y), 0, 127)
  elseif a.kind == "keys" or a.kind == "grid" then
    out.pitch = pitch_of(self, e.y)
  end
  if a.kind ~= "note" then return out end
  out.note = { pitch = a.pitch, start = a.start, length = a.length }
  out.owner, out.place, out.pitch, out.part = a.clip, a.place, a.pitch, "body"
  -- Its ends: its first column and its last, as a terminal shows it; a
  -- column's worth of it in a window.
  local x0, x1 = (a.start - self.scroll) * g.zoom, (a.start + a.length - self.scroll) * g.zoom
  if not e.fine then
    x0 = math.floor(x0 + 0.5)
    x1 = math.max(x0 + 1, math.floor(x1 + 0.5))
  end
  local into, nw = out.tx - x0, x1 - x0
  if nw >= 3 and into < 1 then
    out.part = "start"
  elseif nw >= 2 and nw - into <= 1 then
    out.part = "end"
  end
  return out
end

local function say(n, clip)
  return string.format("%s  %s  length %g", music.name(n.pitch), paw.time.format(clip.start + n.start), n.length)
end

--- Draw a note where a gesture will put it, over the roll: on the cells it
--- rounds to in a terminal, with the pointer between them in a window.
local function ghost(p, start, length, pitch)
  if not p.row(pitch) then return end
  p.plane:mark("note", start, pitch, length, 1, {
    ghost = true,
    style = "MouseGhost",
    label = music.name(pitch),
    color = paw.draw.track_colour(api.track_get(p.data.track)),
  })
end

--- The notes a gesture on the note at `place` of clip `owner` takes
--- along: every chosen note of the clips edited, if it is one of them, as
--- `{ clip, place }` each.
local function grabbed(owner, place)
  local refs = paw.frontend.chosen_refs()
  for _, ref in ipairs(refs) do
    if ref[1] == owner and ref[2] == place then return refs end
  end
  return { { owner, place } }
end

local function among(owner, place)
  for _, other in ipairs(paw.frontend.chosen_notes(owner)) do
    if other == place then return true end
  end
  return false
end

--- A press on a note: chooses it, drags it and the chosen with it, or
--- either end of them.
local function press_note(self, e, h, clip)
  local id, place, n = h.owner, h.place, h.note
  if e.double then return A.remove_note(id, place) end
  local mode = (mouse.has(e, "C") or mouse.has(e, "S")) and "toggle" or "only"
  local deferred = mode ~= "only" or among(id, place)
  if not deferred then A.select_note(id, place, "only") end
  self:set(n.pitch, n.start)
  local free, copy = mouse.has(e, "S"), mouse.has(e, "C")
  local part = h.part
  local zoom = self.geometry.zoom
  mouse.grab(e, {
    roll = function(p)
      local d = mouse.gesture().d
      if not (d and d.moved) then return end
      local dbeat, dpitch = d.dx / zoom, -rows_moved(d, self.geometry.per)
      for _, ref in ipairs(grabbed(id, place)) do
        local m = paw.clip(ref[1]):notes()[ref[2]]
        if m then
          m.start = m.start + paw.roll_clips.offset(ref[1]) - paw.roll_clips.offset(clip.id)
          if part == "start" then
            local stop = m.start + m.length
            local start = math.min(stop - 1 / 64, m.start + dbeat)
            ghost(p, start, stop - start, m.pitch)
          elseif part == "end" then
            ghost(p, m.start, math.max(1 / 64, m.length + dbeat), m.pitch)
          else
            ghost(p, m.start + dbeat, m.length, util.clamp(m.pitch + dpitch, 0, 127))
          end
        end
      end
    end,
    drag = function(d)
      mouse.gesture().d = d
      local dbeat = d.dx / zoom
      local shown = part == "start" and { pitch = n.pitch, start = n.start + dbeat, length = n.length - dbeat }
        or part == "end" and { pitch = n.pitch, start = n.start, length = n.length + dbeat }
        or {
          pitch = util.clamp(n.pitch - rows_moved(d, self.geometry.per), 0, 127),
          start = math.max(0, n.start + dbeat),
          length = n.length,
        }
      mouse.hint(say(shown, clip))
    end,
    up = function(u)
      if not u.moved then
        if deferred then A.select_note(id, place, mode) end
        return
      end
      local dbeat = u.dx / zoom
      if part == "start" then
        A.stretch_notes(id, place, dbeat, nil, free)
      elseif part == "end" then
        A.stretch_notes(id, place, nil, dbeat, free)
      else
        A.drag_notes(id, place, dbeat, -rows_moved(u), copy, free)
      end
    end,
  })
end

--- A press on empty grid: a note from the step pressed to the step the
--- pointer is let go over; a click gives the roll's note length.
local function press_draw(self, e, h, clip)
  local free = mouse.has(e, "S") or not paw.opt.note_snap
  local start, pitch, tx0 = start_at(self, h.tx, free), h.pitch, h.tx
  self:set(pitch, start)
  local function stop(tx) return end_at(self, math.max(tx, tx0), free, e.fine) end
  mouse.grab(e, {
    roll = function(p)
      local d = mouse.gesture().d
      local length = d and d.moved and stop(d.x - self.geometry.keys) - start or self:step_length()
      ghost(p, start, length, pitch)
    end,
    drag = function(d)
      mouse.gesture().d = d
      if d.moved then
        mouse.hint(say({ pitch = pitch, start = start, length = stop(d.x - self.geometry.keys) - start }, clip))
      end
    end,
    up = function(u)
      local length = u.moved and stop(u.x - self.geometry.keys) - start or nil
      A.add_note(clip.id, pitch, start, length, free)
    end,
  })
end

--- A box drawn over the grid: the notes it touches are chosen. From the
--- right button (Shift adds, Ctrl turns over) or the left with Ctrl.
--- Without moving, the right button removes the note it was on (with Ctrl
--- opens the note's menu: its fixes) or opens the menu of the grid, and
--- the left with Ctrl edits the clip of another track's note shown there
--- too (or no longer).
local function press_box(self, e, h, clip)
  local x0, y0 = e.x, e.y
  local right = e.button == "right"
  local where = { x = math.floor(e.x + (e.view_x or 0)), y = math.floor(e.y + (e.view_y or 0)) }
  local g = self.geometry
  -- The last column a box takes in: a terminal's whole column, a window's
  -- pointer where it is.
  local reach = e.fine and 0 or 1
  mouse.grab(e, {
    roll = function(p)
      local d = mouse.gesture().d
      if not (d and d.moved) then return end
      local g2 = paw.draw.g
      local l, r = math.floor(math.min(x0, d.x)) - g.keys, math.floor(math.max(x0, d.x)) - g.keys
      local t, b = math.floor(math.min(y0, d.y)) - g.head, math.floor(math.max(y0, d.y)) - g.head
      p.roll:fill(l, t, r - l + 1, 1, g2.h, "MouseBox")
      p.roll:fill(l, b, r - l + 1, 1, g2.h, "MouseBox")
      p.roll:fill(l, t, 1, b - t + 1, g2.v, "MouseBox")
      p.roll:fill(r, t, 1, b - t + 1, g2.v, "MouseBox")
    end,
    drag = function(d) mouse.gesture().d = d end,
    up = function(u)
      if u.moved then
        local a, b = math.min(x0, u.x) - g.keys, math.max(x0, u.x) - g.keys
        local mode = mouse.has(u, "S") and "add" or (right and mouse.has(u, "C")) and "toggle" or "only"
        A.select_notes_box(
          clip.id,
          beat_at(self, a),
          pitch_of(self, y0),
          beat_at(self, b + reach),
          pitch_of(self, u.y),
          mode
        )
      elseif right and h.note and mouse.has(u, "C") then
        paw.ui.menu(menus.note(h.owner, h.place), where)
      elseif right and h.note then
        A.remove_note(h.owner, h.place)
      elseif right then
        paw.ui.menu(menus.roll(clip.id), where)
      else
        -- Ctrl and a click on another track's note shown behind: its clip
        -- is edited too, or no longer.
        A.context_click(clip.id, beat_at(self, h.tx), h.pitch)
      end
    end,
  })
end

--- Alt and a drag: every note the pointer crosses is taken away.
local function press_erase(self, e, h, clip)
  local g = self.geometry
  -- A terminal's column at its middle, a window's pointer where it is.
  local middle = e.fine and 0 or 0.5
  local function point(x, y) return { beat_at(self, x - g.keys + middle), pitch_of(self, y) } end
  local stroke = { point(e.x, e.y) }
  mouse.grab(e, {
    drag = function(d) stroke[#stroke + 1] = point(d.x, d.y) end,
    up = function(u)
      stroke[#stroke + 1] = point(u.x, u.y)
      A.erase_notes(clip.id, stroke)
    end,
  })
end

--- The keyboard down the left: a key sounds under a click or a drag; the
--- right button dragged chooses the notes of the pitches it crosses.
local function press_keys(self, e, h, clip)
  if e.button == "right" then
    return mouse.grab(e, {
      up = function(u)
        if u.moved then
          A.select_pitches(
            clip.id,
            h.pitch,
            pitch_of(self, u.y),
            mouse.has(u, "S") and "add" or mouse.has(u, "C") and "toggle" or "only"
          )
        end
      end,
    })
  end
  A.audition(clip.id, h.pitch)
  local last = h.pitch
  mouse.grab(e, {
    drag = function(d)
      local pitch = pitch_of(self, d.y)
      if pitch ~= last then
        last = pitch
        A.audition(clip.id, pitch)
      end
    end,
  })
end

--- The velocity strip: what is drawn over it sets how hard the notes
--- under the stroke are played (only the chosen, if any are).
local function press_velocity(self, e, h, clip)
  local g = self.geometry
  local top = g.head + g.lines
  -- A terminal's cell at its middle, a window's pointer where it is.
  local half = e.fine and 0 or 0.5
  local reach = 0.5 / g.zoom
  local function point(x, y)
    return { beat_at(self, x - g.keys) + half / g.zoom, util.clamp(1 - (y - top + half) / g.vel, 0, 1) }
  end
  local stroke = { point(e.x, e.y) }
  mouse.grab(e, {
    drag = function(d)
      stroke[#stroke + 1] = point(d.x, d.y)
      mouse.hint(string.format("velocity %d", util.clamp(math.floor(stroke[#stroke][2] * 127 + 0.5), 1, 127)))
    end,
    up = function() A.draw_velocities(clip.id, stroke, reach) end,
  })
end

--- The furthest left the roll scrolls: its start, or before it the start
--- of an earlier clip edited with it.
local function leftmost() return math.min(0, math.floor((paw.roll_clips.span()))) end

local function wheel(self, e, h)
  local step, sideways = mouse.wheel(e)
  local g = self.geometry
  if mouse.has(e, "C") and not sideways then
    -- Zoom in time, keeping the beat under the pointer where it is.
    local tx = math.max(0, h.tx)
    local at = beat_at(self, tx)
    local zoom = util.clamp(paw.opt.note_zoom * (step < 0 and math.sqrt(2) or 1 / math.sqrt(2)), 0.125, 64)
    paw.opt.note_zoom = zoom
    self.scroll = math.max(leftmost(), at - tx / zoom)
  elseif mouse.has(e, "A") and not sideways then
    -- Taller or shorter keys: the vertical zoom (paw/vzoom.tl).
    return paw.vzoom.step(-step, { view = "pianoroll" })
  elseif sideways or mouse.has(e, "S") then
    self.scroll = math.max(leftmost(), self.scroll + step)
  else
    self.top = util.clamp(self.top - 2 * step, g.rows - 1, 127)
  end
  self:follow()
end

--- Scrolling moves what is shown, so the cursor is brought along with it.
function view:follow()
  local g = self.geometry
  local span = g.span or 1
  self.pitch = util.clamp(self.pitch, self.top - g.rows + 1, self.top)
  self.beat = util.clamp(self.beat, self.scroll, math.max(self.scroll, self.scroll + span - 2 * paw.opt.note_grid))
  api.ui_redraw()
end

local hints = {
  grid = "click draws a note (drag for its length) · right drag chooses · right click for more · Alt drag erases",
  note = "click chooses · drag moves (Ctrl copies) · drag an end to resize · double or right click removes",
  keys = "click sounds the key · right drag chooses the notes of those pitches",
  velocity = "draw across the bars to set how hard the notes play (only the chosen, if any are)",
  controller = "draw with the button held · right drag draws a line · drag a move's head to move the chosen · Ctrl drag chooses · right click for more",
  ruler = "click moves the playhead",
}

local function hover(self, h, clip)
  local text
  if h.area == "grid" then
    local at = music.name(h.pitch) .. "  " .. paw.time.format(clip.start + math.max(0, h.beat))
    text = h.note and (say(h.note, clip) .. " · " .. hints.note) or (at .. " · " .. hints.grid)
  elseif h.area == "keys" then
    text = music.name(h.pitch) .. " · " .. hints.keys
  elseif h.area == "velocity" then
    text = h.tx < 0 and "click to choose what the strip shows: velocity or a controller"
      or strip.shown().kind and hints.controller
      or hints.velocity
  elseif h.area == "ruler" then
    text = hints.ruler
  end
  mouse.hint(text)
end

--- A press, a move or the wheel on the ruler, the keyboard, the grid, a
--- note or the velocity strip.
local function pointer(self, e)
  local clip = self:clip()
  if not (self.geometry and self.geometry.keys and clip) then return false end
  local h = hit_of(self, e)
  if e.kind == "move" then return hover(self, h, clip) end
  if mouse.wheel(e) then return wheel(self, e, h) end
  if e.kind ~= "down" then return end
  if e.button == "middle" then
    -- The middle button held pans.
    local scroll, top, zoom = self.scroll, self.top, self.geometry.zoom
    return mouse.grab(e, {
      drag = function(d)
        self.scroll = math.max(leftmost(), scroll - d.dx / zoom)
        self.top = util.clamp(top + rows_moved(d, self.geometry.per), self.geometry.rows - 1, 127)
        self:follow()
      end,
    })
  end
  if h.area == "ruler" then
    if h.tx >= 0 and e.button == "left" then A.roll_seek(clip.id, beat_at(self, h.tx)) end
    return
  end
  if h.area == "keys" then return press_keys(self, e, h, clip) end
  if h.area == "velocity" then
    if strip.press(self, e, clip) then return end
    if h.tx >= 0 and e.button == "left" then press_velocity(self, e, h, clip) end
    return
  end
  if e.button == "right" or (e.button == "left" and mouse.has(e, "C") and not h.note) then
    return press_box(self, e, h, clip)
  end
  if e.button ~= "left" then return end
  if mouse.has(e, "A") then return press_erase(self, e, h, clip) end
  if h.note then return press_note(self, e, h, clip) end
  press_draw(self, e, h, clip)
end

--- A menu of choices, the one standing ticked.
local function choices(list, now, choose)
  local items = {}
  for _, c in ipairs(list) do
    items[#items + 1] = { label = c[1], checked = c[2] == now, run = function() choose(c[2]) end }
  end
  return items
end

--- A button of the row of tools.
local function tool(self, e)
  local t = e.hit
  if e.kind == "move" then return mouse.hint(t.tip) end
  if e.kind ~= "down" or e.button ~= "left" then return end
  local clip = self:clip()
  if not clip then return end
  -- A menu opens under the button.
  local where = { x = math.floor(e.rect.x + (e.view_x or 0)), y = math.floor(e.rect.y + (e.view_y or 0)) + 1 }
  local name = t.name
  if name == "grid" then
    paw.ui.menu(choices(view.grids, paw.opt.note_grid, function(v) paw.opt.note_grid = v end), where)
  elseif name == "length" then
    local list = { { "Grid", 0 } }
    for i = 1, 6 do
      list[#list + 1] = view.grids[i]
    end
    paw.ui.menu(choices(list, self.length or 0, function(v) A.set_note_length(v) end), where)
  elseif name == "snap" then
    A.toggle_note_snap()
  elseif name == "quantize" then
    A.quantize_notes(clip.id)
  elseif name == "step" then
    paw.roll_draw.click_step()
  elseif name == "list" then
    A.open_event_list(clip.id)
  elseif name == "tracks" then
    paw.roll_clips.pick()
  elseif name == "zoom_in" or name == "zoom_out" then
    paw.opt.note_zoom =
      util.clamp(paw.opt.note_zoom * (name == "zoom_in" and math.sqrt(2) or 1 / math.sqrt(2)), 0.125, 64)
  elseif name == "window" then
    paw.commands.exec("view.window pianoroll")
  elseif name == "close" then
    A.close_roll()
  elseif name == "layer" and A[t.act] then
    A[t.act](clip.id)
  end
  api.ui_redraw()
end

--- The scroll bar through the pitches dragged: the pitches shown follow it.
local function scrollbar(self, e)
  if e.kind == "move" then return mouse.hint("drag to scroll through the pitches") end
  if e.kind ~= "down" or e.button ~= "left" then return end
  local g = self.geometry
  local top = self.top
  mouse.grab(e, {
    drag = function(d)
      self.top = util.clamp(top - math.floor(d.dy * 128 / g.lines + 0.5), g.rows - 1, 127)
      self:follow()
    end,
  })
end

--- A chip a layer marked as a hit region `{ kind = "act", act, arg, tip }`:
--- a click calls `paw.frontend.act[act](clip, arg)`.
local function chip(self, e)
  local t = e.hit
  if e.kind == "move" then return mouse.hint(t.tip) end
  if e.kind ~= "down" or e.button ~= "left" then return end
  local clip = self:clip()
  if clip and A[t.act] then A[t.act](clip.id, t.arg) end
  api.ui_redraw()
end

view.gestures = {
  ruler = pointer,
  keys = pointer,
  grid = pointer,
  note = pointer,
  velocity = pointer,
  tool = tool,
  act = chip,
  scrollbar = scrollbar,
}

-- What a gesture under way draws: over the notes, under the cursor.
view.layer("mouse", 60, function(p)
  local g = mouse.gesture()
  if g and g.roll then g.roll(p) end
end)
