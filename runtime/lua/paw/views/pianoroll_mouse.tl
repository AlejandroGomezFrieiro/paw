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
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local util = require("paw.util")
local music = require("paw.music")
local mouse = require("paw.mouse")
local axis = require("paw.axis")
local menus = require("paw.mouse_menus")
local timegrid = require("paw.timegrid")
local strip = require("paw.views.pianoroll_strip")
local type contracts = require("paw.contracts")
local type objects = require("paw.objects")
local type Roll = require("paw.views.pianoroll")

local type PianoRoll = Roll.PianoRoll
local type Grab = Roll.Grab
local type MouseEvent = contracts.MouseEvent
local opt = options.opt

-- The declaration of `paw` (paw.d.tl) does not name the types of this
-- module, so the typed global `paw` is in scope here.
local view = paw.ui.views:get("pianoroll") as PianoRoll
local A = paw.frontend.act

--- The roll's time axis at its scroll now (paw/axis.tl): the pointer reads
--- beats and columns on it, as the roll drew them.
local function axis_of(self: PianoRoll): axis.Axis
  return axis.new(self.scroll, self.geometry.zoom)
end

--- The beat at a column of the roll: its left edge.
local function beat_at(self: PianoRoll, tx: number): number
  return axis_of(self):beat_of(tx)
end

--- The grid step a column falls in, or with `free` the column's own beat.
local function start_at(self: PianoRoll, tx: number, free: boolean): number
  if free then
    return beat_at(self, tx)
  end
  return axis_of(self):step_at(math.floor(tx), timegrid.step("note"))
end

--- Where the grid step under the pointer ends: a drag to a column takes in
--- the step drawn there. A terminal's column is its left edge, so the
--- step it shows ends a column on; a window's pointer is where it is.
local function end_at(self: PianoRoll, tx: number, free: boolean, fine: boolean): number
  local beat = beat_at(self, tx + (fine and 0 or 1))
  if free then
    return beat
  end
  local grid = timegrid.step("note")
  return math.ceil(beat / grid - 1e-6) * grid
end

--- The pitch of a row of the view, which may be a fraction of one.
local function pitch_of(self: PianoRoll, y: number): integer
  local g = self.geometry
  return math.floor(util.clamp(self.top - math.floor((y - g.head) / (g.per or 1)), 0, 127))
end

--- Rows a drag went, as whole pitches: a pitch is `per` rows tall.
local function rows_moved(d: MouseEvent, per?: integer): integer
  return math.floor(d.dy / (per or 1) + 0.5)
end

--- A note as a press finds it: its pitch, and its start in the roll's beats.
local record Note
  pitch: integer
  start: number
  length: number
end

--- What a press is on, from the hit region it found: `area` "ruler",
--- "keys", "grid", "velocity" or "tool", the column of the roll, the beat
--- and the pitch there, and on a note the note (its start in the roll's
--- beats), the clip it is in (`owner`) with its place there, and the part
--- pressed ("start", "end" or "body").
local record Hit
  area: string
  tx: number
  beat: number
  pitch: integer
  note: Note
  owner: integer
  place: integer
  part: string
end

local function hit_of(self: PianoRoll, e: MouseEvent): Hit
  local g, a = self.geometry, e.hit
  local out: Hit = {area = a.kind == "note" and "grid" or a.kind, tx = e.x - g.keys}
  out.beat = beat_at(self, out.tx)
  if a.kind == "grid" and e.at then
    out.pitch = math.floor(util.clamp(math.floor(e.at.y), 0, 127))
  elseif a.kind == "keys" or a.kind == "grid" then
    out.pitch = pitch_of(self, e.y)
  end
  if a.kind ~= "note" then
    return out
  end
  local n = a as Roll.NoteHit
  out.note = {pitch = n.pitch, start = n.start, length = n.length}
  out.owner, out.place, out.pitch, out.part = n.clip, n.place, n.pitch, "body"
  -- Its ends: its first column and its last, as a terminal shows it; a
  -- column's worth of it in a window.
  local ax = axis_of(self)
  local x0, x1: number, number = ax:exact(n.start), ax:exact(n.start + n.length)
  if not e.fine then
    local first, after = ax:range(n.start, n.start + n.length)
    x0, x1 = first, after
  end
  local into, nw = out.tx - x0, x1 - x0
  if nw >= 3 and into < 1 then
    out.part = "start"
  elseif nw >= 2 and nw - into <= 1 then
    out.part = "end"
  end
  return out
end

--- What the status line says of a note: its name, where it starts, how long it is.
local function say(n: Note, clip: objects.Clip): string
  return string.format("%s  %s  length %g", music.name(n.pitch), paw.time.format(clip.start + n.start), n.length)
end

--- Draw a note where a gesture will put it, over the roll: on the cells it
--- rounds to in a terminal, with the pointer between them in a window.
local function ghost(p: Roll.Layer, start: number, length: number, pitch: integer)
  if not p.row(pitch) then
    return
  end
  local mark: Roll.NoteMark = {
    ghost = true,
    style = "MouseGhost",
    label = music.name(pitch),
    color = paw.draw.part_colour(api.part_get(p.data.part)),
  }
  p.plane:mark("note", start, pitch, length, 1, mark)
end

--- The notes a gesture on the note at `place` of clip `owner` takes
--- along: every chosen note of the clips edited, if it is one of them, as
--- `{ clip, place }` each.
local function grabbed(owner: integer, place: integer): {{integer}}
  local refs = paw.frontend.chosen_refs()
  for _, ref in ipairs(refs) do
    if ref[1] == owner and ref[2] == place then
      return refs
    end
  end
  return {{owner, place}}
end

--- True if the note at `place` of clip `owner` is chosen.
local function among(owner: integer, place: integer): boolean
  for _, other in ipairs(paw.frontend.chosen_notes(owner)) do
    if other == place then
      return true
    end
  end
  return false
end

--- The drag under way, which the gesture keeps for its layer.
local function last_drag(): MouseEvent
  return (mouse.gesture() as Grab).d
end

--- A gesture that keeps each drag for what it draws.
local function keep_drag(d: MouseEvent)
  (mouse.gesture() as Grab).d = d
end

--- A press on a note: chooses it, drags it and the chosen with it, or
--- either end of them.
local function press_note(self: PianoRoll, e: MouseEvent, h: Hit, clip: objects.Clip)
  local id, place, n = h.owner, h.place, h.note
  if e.double then
    return A.remove_note(id, place)
  end
  local mode = (mouse.has(e, "C") or mouse.has(e, "S")) and "toggle" or "only"
  local deferred = mode ~= "only" or among(id, place)
  if not deferred then
    A.select_note(id, place, "only")
  end
  self:set(n.pitch, n.start)
  local free, copy = mouse.has(e, "S"), mouse.has(e, "C")
  local part = h.part
  local ax = axis_of(self)
  local grab: Grab = {
    roll = function(p: Roll.Layer)
      local d = last_drag()
      if not (d and d.moved) then
        return
      end
      local dbeat, dpitch = ax:beats(d.dx), -rows_moved(d, self.geometry.per)
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
            ghost(p, m.start + dbeat, m.length, math.floor(util.clamp(m.pitch + dpitch, 0, 127)))
          end
        end
      end
    end,
    drag = function(d: MouseEvent)
      keep_drag(d)
      local dbeat = ax:beats(d.dx)
      local shown: Note = part == "start" and {pitch = n.pitch, start = n.start + dbeat, length = n.length - dbeat}
        or part == "end" and {pitch = n.pitch, start = n.start, length = n.length + dbeat}
        or {
          pitch = math.floor(util.clamp(n.pitch - rows_moved(d, self.geometry.per), 0, 127)),
          start = math.max(0, n.start + dbeat),
          length = n.length,
        }
      mouse.hint(say(shown, clip))
    end,
    up = function(u: MouseEvent)
      if not u.moved then
        if deferred then
          A.select_note(id, place, mode)
        end
        return
      end
      local dbeat = ax:beats(u.dx)
      if part == "start" then
        A.stretch_notes(id, place, dbeat, nil, free)
      elseif part == "end" then
        A.stretch_notes(id, place, nil, dbeat, free)
      else
        A.drag_notes(id, place, dbeat, -rows_moved(u), copy, free)
      end
    end,
  }
  mouse.grab(e, grab)
end

--- A press on empty grid: a note from the step pressed to the step the
--- pointer is let go over; a click gives the roll's note length.
local function press_draw(self: PianoRoll, e: MouseEvent, h: Hit, clip: objects.Clip)
  local free = mouse.has(e, "S") or not opt.note_snap
  local start, pitch, tx0 = start_at(self, h.tx, free), h.pitch, h.tx
  self:set(pitch, start)
  local function stop(tx: number): number
    return end_at(self, math.max(tx, tx0), free, e.fine)
  end
  local grab: Grab = {
    roll = function(p: Roll.Layer)
      local d = last_drag()
      local length = d and d.moved and stop(d.x - self.geometry.keys) - start or self:step_length()
      ghost(p, start, length, pitch)
    end,
    drag = function(d: MouseEvent)
      keep_drag(d)
      if d.moved then
        mouse.hint(say({pitch = pitch, start = start, length = stop(d.x - self.geometry.keys) - start}, clip))
      end
    end,
    up = function(u: MouseEvent)
      local length = u.moved and stop(u.x - self.geometry.keys) - start or nil
      A.add_note(clip.id, pitch, start, length, free)
    end,
  }
  mouse.grab(e, grab)
end

--- A box drawn over the grid: the notes it touches are chosen. From the
--- right button (Shift adds, Ctrl turns over) or the left with Ctrl.
--- Without moving, the right button removes the note it was on (with Ctrl
--- opens the note's menu: its fixes) or opens the menu of the grid, and
--- the left with Ctrl edits the clip of another part's note shown there
--- too (or no longer).
local function press_box(self: PianoRoll, e: MouseEvent, h: Hit, clip: objects.Clip)
  local x0, y0 = e.x, e.y
  local right = e.button == "right"
  local where: contracts.MenuOptions = {x = math.floor(e.x + (e.view_x or 0)), y = math.floor(e.y + (e.view_y or 0))}
  local g = self.geometry
  -- The last column a box takes in: a terminal's whole column, a window's
  -- pointer where it is.
  local reach = e.fine and 0 or 1
  local grab: Grab = {
    roll = function(p: Roll.Layer)
      local d = last_drag()
      if not (d and d.moved) then
        return
      end
      local g2 = paw.draw.g
      local l, r = math.floor(math.min(x0, d.x)) - g.keys, math.floor(math.max(x0, d.x)) - g.keys
      local t, b = math.floor(math.min(y0, d.y)) - g.head, math.floor(math.max(y0, d.y)) - g.head
      p.roll:fill(l, t, r - l + 1, 1, g2.h, "MouseBox")
      p.roll:fill(l, b, r - l + 1, 1, g2.h, "MouseBox")
      p.roll:fill(l, t, 1, b - t + 1, g2.v, "MouseBox")
      p.roll:fill(r, t, 1, b - t + 1, g2.v, "MouseBox")
    end,
    drag = keep_drag,
    up = function(u: MouseEvent)
      if u.moved then
        local a, b = math.min(x0, u.x) - g.keys, math.max(x0, u.x) - g.keys
        local mode = mouse.has(u, "S") and "add" or (right and mouse.has(u, "C")) and "toggle" or "only"
        A.select_notes_box(
          clip.id, beat_at(self, a), pitch_of(self, y0), beat_at(self, b + reach), pitch_of(self, u.y), mode
        )
      elseif right and h.note and mouse.has(u, "C") then
        paw.ui.menu(menus.note(h.owner, h.place), where)
      elseif right and h.note then
        A.remove_note(h.owner, h.place)
      elseif right then
        paw.ui.menu(menus.roll(clip.id), where)
      else
        -- Ctrl and a click on another part's note shown behind: its clip
        -- is edited too, or no longer.
        A.context_click(clip.id, beat_at(self, h.tx), h.pitch)
      end
    end,
  }
  mouse.grab(e, grab)
end

--- Alt and a drag: every note the pointer crosses is taken away.
local function press_erase(self: PianoRoll, e: MouseEvent, clip: objects.Clip)
  local g = self.geometry
  -- A terminal's column at its middle, a window's pointer where it is.
  local middle = e.fine and 0 or 0.5
  local function point(x: number, y: number): {number, number}
    return {beat_at(self, x - g.keys + middle), pitch_of(self, y)}
  end
  local stroke = {point(e.x, e.y)}
  mouse.grab(
    e,
    {
      drag = function(d: MouseEvent) stroke[#stroke + 1] = point(d.x, d.y) end,
      up = function(u: MouseEvent) stroke[#stroke + 1] = point(u.x, u.y); A.erase_notes(clip.id, stroke) end,
    }
  )
end

--- The keyboard down the left: a key sounds under a click or a drag; the
--- right button dragged chooses the notes of the pitches it crosses.
local function press_keys(self: PianoRoll, e: MouseEvent, h: Hit, clip: objects.Clip)
  if e.button == "right" then
    return mouse.grab(
      e,
      {
        up = function(u: MouseEvent)
          if u.moved then
            A.select_pitches(
              clip.id,
              h.pitch,
              pitch_of(self, u.y),
              mouse.has(u, "S") and "add" or mouse.has(u, "C") and "toggle" or "only"
            )
          end
        end,
      }
    )
  end
  A.audition(clip.id, h.pitch)
  local last = h.pitch
  mouse.grab(
    e,
    {
      drag = function(d: MouseEvent)
        local pitch = pitch_of(self, d.y)
        if pitch ~= last then
          last = pitch
          A.audition(clip.id, pitch)
        end
      end,
    }
  )
end

--- The velocity strip: what is drawn over it sets how hard the notes
--- under the stroke are played (only the chosen, if any are).
local function press_velocity(self: PianoRoll, e: MouseEvent, clip: objects.Clip)
  local g = self.geometry
  local top = g.head + g.lines
  -- A terminal's cell at its middle, a window's pointer where it is.
  local half = e.fine and 0 or 0.5
  local ax = axis_of(self)
  local reach = ax:beats(0.5)
  local function point(x: number, y: number): {number, number}
    return {ax:beat_of(x - g.keys + half), util.clamp(1 - (y - top + half) / g.vel, 0, 1)}
  end
  local stroke = {point(e.x, e.y)}
  mouse.grab(
    e,
    {
      drag = function(d: MouseEvent)
        stroke[#stroke + 1] = point(d.x, d.y)
        local velocity = math.floor(util.clamp(math.floor(stroke[#stroke][2] * 127 + 0.5), 1, 127))
        mouse.hint(string.format("velocity %d", velocity))
      end,
      up = function() A.draw_velocities(clip.id, stroke, reach) end,
    }
  )
end

--- The furthest left the roll scrolls: its start, or before it the start
--- of an earlier clip edited with it.
local function leftmost(): number
  return math.min(0, math.floor((paw.roll_clips.span())))
end

--- The wheel: Ctrl zooms in time where the pointer is, Alt makes the keys
--- taller or shorter, Shift (or a wheel to the side) scrolls in time, and
--- the wheel alone scrolls through the pitches.
local function wheel(self: PianoRoll, e: MouseEvent, h: Hit)
  local step, sideways = mouse.wheel(e)
  local g = self.geometry
  if mouse.has(e, "C") and not sideways then
    -- Zoom in time, keeping the beat under the pointer where it is.
    local tx = math.max(0, h.tx)
    local at = beat_at(self, tx)
    local zoom = util.clamp(opt.note_zoom * (step < 0 and math.sqrt(2) or 1 / math.sqrt(2)), 0.125, 64)
    opt.note_zoom = zoom
    self.scroll = math.max(leftmost(), at - axis.new(0, zoom):beats(tx))
  elseif mouse.has(e, "A") and not sideways then
    -- Taller or shorter keys: the vertical zoom (paw/vzoom.tl).
    return paw.vzoom.step(-step, {view = "pianoroll"})
  elseif sideways or mouse.has(e, "S") then
    self.scroll = math.max(leftmost(), self.scroll + step)
  else
    self.top = math.floor(util.clamp(self.top - 2 * step, g.rows - 1, 127))
  end
  self:follow()
end

--- Scrolling moves what is shown, so the cursor is brought along with it.
function view:follow()
  local g = self.geometry
  local span = g.span or 1
  self.pitch = math.floor(util.clamp(self.pitch, self.top - g.rows + 1, self.top))
  self.beat = util.clamp(self.beat, self.scroll, math.max(self.scroll, self.scroll + span - 2 * timegrid.step("note")))
  api.ui_redraw()
end

-- What the status line says under the pointer, by what it is over.
local hints = {
  grid = "click draws a note (drag for its length) · right drag chooses · right click for more · Alt drag erases",
  note = "click chooses · drag moves (Ctrl copies) · drag an end to resize · double or right click removes",
  keys = "click sounds the key · right drag chooses the notes of those pitches",
  velocity = "draw across the bars to set how hard the notes play (only the chosen, if any are)",
  controller = "draw with the button held · right drag draws a line · drag a move's head to move the chosen · Ctrl drag chooses · right click for more",
  ruler = "click moves the playhead",
}

local function hover(h: Hit, clip: objects.Clip)
  local text: string
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

--- A press of the left button on the grid: Alt erases, on a note it is
--- the note's, else it draws one.
local function press_left(self: PianoRoll, e: MouseEvent, h: Hit, clip: objects.Clip)
  if mouse.has(e, "A") then
    return press_erase(self, e, clip)
  end
  if h.note then
    return press_note(self, e, h, clip)
  end
  press_draw(self, e, h, clip)
end

--- The middle button held pans.
local function press_pan(self: PianoRoll, e: MouseEvent)
  local scroll, top, ax = self.scroll, self.top, axis_of(self)
  mouse.grab(
    e,
    {
      drag = function(d: MouseEvent)
        self.scroll = math.max(leftmost(), scroll - ax:beats(d.dx))
        self.top = math.floor(util.clamp(top + rows_moved(d, self.geometry.per), self.geometry.rows - 1, 127))
        self:follow()
      end,
    }
  )
end

--- A press, a move or the wheel on the ruler, the keyboard, the grid, a
--- note or the velocity strip.
local function pointer(self: PianoRoll, e: MouseEvent): boolean
  local clip = self:clip()
  if not (self.geometry and self.geometry.keys and clip) then
    return false
  end
  local h = hit_of(self, e)
  if e.kind == "move" then
    return hover(h, clip)
  end
  if mouse.wheel(e) then
    return wheel(self, e, h)
  end
  if e.kind ~= "down" then
    return
  end
  if e.button == "middle" then
    return press_pan(self, e)
  end
  if h.area == "ruler" then
    if h.tx >= 0 and e.button == "left" then
      A.roll_seek(clip.id, beat_at(self, h.tx))
    end
    return
  end
  if h.area == "keys" then
    return press_keys(self, e, h, clip)
  end
  if h.area == "velocity" then
    if strip.press(self, e, clip) then
      return
    end
    if h.tx >= 0 and e.button == "left" then
      press_velocity(self, e, clip)
    end
    return
  end
  if e.button == "right" or (e.button == "left" and mouse.has(e, "C") and not h.note) then
    return press_box(self, e, h, clip)
  end
  if e.button == "left" then
    press_left(self, e, h, clip)
  end
end

--- A menu of choices, the one standing ticked.
local function choices(
  list: {Roll.GridChoice}, now: number | string, choose: function(value: number)
): {contracts.MenuEntry}
  local items: {contracts.MenuEntry} = {}
  for _, c in ipairs(list) do
    local value = c[2] as number
    items[#items + 1] = {label = c[1] as string, checked = value == now, run = function() choose(value) end}
  end
  return items
end

-- The `paw.frontend.act` functions that a hit region names: called with
-- the clip, and a chip's argument.
local named_acts = A as {string: function(clip: integer, arg?: integer)}

--- What a button of the row of tools does, by its name.
local tool_actions: {string: function(
  self: PianoRoll, clip: objects.Clip, where: contracts.MenuOptions, hit: Roll.ToolHit
)} = {
  grid = function(_: PianoRoll, _: objects.Clip, where: contracts.MenuOptions)
    paw.ui.menu(choices(view.grids, opt.note_grid, function(v: number) opt.note_grid = v end), where)
  end,
  length = function(self: PianoRoll, _: objects.Clip, where: contracts.MenuOptions)
    local list: {Roll.GridChoice} = {{"Grid", 0}}
    for i = 1, 6 do
      list[#list + 1] = view.grids[i]
    end
    paw.ui.menu(choices(list, self.length or 0, function(v: number) A.set_note_length(v) end), where)
  end,
  snap = function() A.toggle_note_snap() end,
  quantize = function(_: PianoRoll, clip: objects.Clip) A.quantize_notes(clip.id) end,
  step = function() paw.roll_draw.click_step() end,
  list = function(_: PianoRoll, clip: objects.Clip) A.open_event_list(clip.id) end,
  parts = function() paw.roll_clips.pick() end,
  zoom_in = function() opt.note_zoom = util.clamp(opt.note_zoom * math.sqrt(2), 0.125, 64) end,
  zoom_out = function() opt.note_zoom = util.clamp(opt.note_zoom * (1 / math.sqrt(2)), 0.125, 64) end,
  window = function() paw.commands.exec("view.window pianoroll") end,
  close = function() A.close_roll() end,
  layer = function(_: PianoRoll, clip: objects.Clip, _: contracts.MenuOptions, hit: Roll.ToolHit)
    local act = named_acts[hit.act]
    if act then
      act(clip.id)
    end
  end,
}

--- A button of the row of tools.
local function tool(self: PianoRoll, e: MouseEvent): boolean
  local t = e.hit as Roll.ToolHit
  if e.kind == "move" then
    return mouse.hint(t.tip)
  end
  if e.kind ~= "down" or e.button ~= "left" then
    return
  end
  local clip = self:clip()
  if not clip then
    return
  end
  -- A menu opens under the button.
  local where: contracts.MenuOptions = {
    x = math.floor(e.rect.x + (e.view_x or 0)),
    y = math.floor(e.rect.y + (e.view_y or 0)) + 1,
  }
  local action = tool_actions[t.name]
  if action then
    action(self, clip, where, t)
  end
  api.ui_redraw()
end

--- The scroll bar through the pitches dragged: the pitches shown follow it.
local function scrollbar(self: PianoRoll, e: MouseEvent): boolean
  if e.kind == "move" then
    return mouse.hint("drag to scroll through the pitches")
  end
  if e.kind ~= "down" or e.button ~= "left" then
    return
  end
  local g = self.geometry
  local top = self.top
  mouse.grab(
    e,
    {
      drag = function(d: MouseEvent)
        self.top = math.floor(util.clamp(top - math.floor(d.dy * 128 / g.lines + 0.5), g.rows - 1, 127))
        self:follow()
      end,
    }
  )
end

--- A chip a layer marked as a hit region `{ kind = "act", act, arg, tip }`:
--- a click calls `paw.frontend.act[act](clip, arg)`.
local function chip(self: PianoRoll, e: MouseEvent): boolean
  local t = e.hit as Roll.ActHit
  if e.kind == "move" then
    return mouse.hint(t.tip)
  end
  if e.kind ~= "down" or e.button ~= "left" then
    return
  end
  local clip = self:clip()
  local act = named_acts[t.act]
  if clip and act then
    act(clip.id, t.arg)
  end
  api.ui_redraw()
end

local type Gesture = function(self: contracts.View, e: MouseEvent): boolean
view.gestures = {
  ruler = pointer as Gesture,
  keys = pointer as Gesture,
  grid = pointer as Gesture,
  note = pointer as Gesture,
  velocity = pointer as Gesture,
  tool = tool as Gesture,
  act = chip as Gesture,
  scrollbar = scrollbar as Gesture,
}

-- What a gesture under way draws: over the notes, under the cursor.
view.layer(
  "mouse",
  60,
  function(p: Roll.Layer)
    local g = mouse.gesture() as Grab
    if g and g.roll then
      g.roll(p)
    end
  end
)
