-- The drum grid: a clip of a drum track shown through its drum map, one row
-- per piece with its name, one column per step, each hit drawn as tall as
-- it is hard. It is a piano roll whose rows are the pieces of the kit, and
-- takes the same grammar: motions, counts, operators, text objects, visual
-- mode, registers and `.`.
--
-- One view for every frontend: the terminal draws it in cells, a window the
-- same layout in its own font, with the toolbar's buttons as buttons. Steps
-- and hits are roles (`step`, `hit`) and every part a hit region, so the
-- pointer does the same in both (see `view.gestures`):
--
--   toolbar   play the clip round and round, or stop; the step (straight and
--             triplet); the clip's length in bars
--   ruler     a click moves the playhead there
--   names     a click chooses the row and plays the piece
--   steps     a click puts a hit in, or takes it out (the right button takes
--             it out); a drag along the row paints hits, or from a hit erases
--             them, as one edit
--   velocity  how hard each hit of the cursor's row is: click or drag
local api = paw.api
local util = paw.util
local drums = require("drums")
local E = require("drums.edit")

local CW = 3      -- columns a step takes: a separator, then the hit
local LANE = 2    -- the velocity lane's rows, under the pieces
local EPS = 1e-6

local view = {
  clip_id = nil,
  row = 1,         -- cursor row, a place in `rows()`
  beat = 0,        -- cursor, in beats from the start of the clip
  step = nil,      -- beats a column is; paw.opt.drums_step until changed
  first = 1,       -- the row at the top of the screen
  scroll = 0,      -- the cell at the left edge
  drag = nil,      -- what a drag of the pointer is about to do
  title = "Drum grid",
}

function view:clip()
  if self.clip_id and pcall(api.clip_get, self.clip_id) then return paw.clip(self.clip_id) end
  self.clip_id = nil
end

function view:track_id()
  local clip = self:clip()
  return clip and api.clip_get(clip.id).track
end

--- The rows the open clip is shown with.
function view:rows()
  local clip = self:clip()
  if not clip then return {} end
  return drums.rows(self:track_id(), clip)
end

function view:step_size()
  return self.step or paw.opt.drums_step
end

--- The piece under the cursor: `{ note, name }`.
function view:piece()
  return self:rows()[self.row]
end

--- Open a clip of a drum track in the grid, with the cursor on its first hit.
function view:edit(clip)
  if type(clip) == "number" then clip = paw.clip(clip) end
  if clip.kind ~= "midi" then return paw.notify("only MIDI clips open in the drum grid", "warn") end
  self.clip_id, self.beat, self.scroll, self.first, self.drag = clip.id, 0, 0, 1, nil
  self.row = 1
  local rows = drums.rows(clip:get().track, clip)
  local first = clip:notes()[1]
  if first then
    for i, row in ipairs(rows) do
      if row.note == first.pitch then self.row, self.beat = i, E.cell(first.start, self:step_size()) * self:step_size() end
    end
  end
  paw.ui.focus("drums")
end

--- How a hit of some velocity is drawn: a bar as tall as it is hard.
function view.glyph(velocity)
  return paw.draw.g.eighths[util.clamp(math.ceil(velocity / 127 * 8), 1, 8)]
end

-- A step of a row, `CW` cells: its line on the left (`line`, "bar" or
-- "beat"), its shade (`dark` every other beat, so that a bar reads at a
-- glance), and a dot where a hit could go.
paw.ui.role("step", {
  props = { line = "bar | beat", dark = "boolean" },
  cells = function(buf, p)
    local g = paw.draw.g
    buf:fill(0, 0, buf.width, 1, " ", p.dark and "RollRowBlack" or "RollRow")
    if p.line == "bar" then buf:text(0, 0, g.bar, "RollBar") elseif p.line == "beat" then buf:text(0, 0, g.beat, "RollBeat") end
    buf:text(1, 0, g.dot, "Faint")
  end,
})

-- A step with a hit: a step whose dot is a bar as tall as the hit is hard
-- (`velocity`), in the track's colour (`style`; `color` for a window), with
-- a tick after it when it is off the grid (`off`).
paw.ui.role("hit", {
  props = { velocity = "number 1..127", off = "boolean", line = "bar | beat", dark = "boolean", style = "highlight group", color = "#rrggbb" },
  cells = function(buf, p)
    local g = paw.draw.g
    buf:fill(0, 0, buf.width, 1, " ", p.dark and "RollRowBlack" or "RollRow")
    if p.line == "bar" then buf:text(0, 0, g.bar, "RollBar") elseif p.line == "beat" then buf:text(0, 0, g.beat, "RollBeat") end
    local glyph = view.glyph(p.velocity)
    buf:text(1, 0, glyph .. (p.off and "'" or glyph), p.style)
  end,
})

--- The toolbar: play or stop, the steps, the clip's length.
local function toolbar(buf, y, clip, step)
  local x = 1
  local function button(text, on, action)
    local w = api.str_width(text) + 2
    if x + w > buf.width then return end
    buf:mark("button", x, y, w, 1, { text = " " .. text .. " ", on = on, style = "TrackInfo", on_style = "TitleBarFocus", hit = action })
    x = x + w + 1
  end
  local playing = api.transport_get().playing
  button(playing and "■ stop" or "▶ play", playing, { kind = "tool", play = true })
  x = x + 1
  for _, s in ipairs({ { 1, "1/4" }, { 1 / 2, "1/8" }, { 1 / 4, "1/16" }, { 1 / 8, "1/32" }, { 1 / 3, "1/8T" }, { 1 / 6, "1/16T" } }) do
    button(s[2], math.abs(step - s[1]) < EPS, { kind = "tool", step = s[1] })
  end
  x = x + 1
  local bars = clip.length / paw.time.bar()
  button("−", false, { kind = "tool", bars = -1 })
  local said = string.format(bars % 1 < EPS and "%d bar%s" or "%.2f bars", bars, bars == 1 and "" or "s")
  if x + #said <= buf.width then
    buf:mark("label", x, y, api.str_width(said), 1, { text = said, style = "TrackInfo", tone = "text" })
    x = x + api.str_width(said) + 1
  end
  button("+", false, { kind = "tool", bars = 1 })
end

function view:render(buf, ctx)
  local w, h = buf.width, buf.height
  local clip = self:clip()
  local g = paw.draw.g
  buf:fill(0, 0, w, h, " ", "Normal")
  if not clip then
    paw.ui.titlebar(buf, { name = "Drum grid", focused = ctx.focused })
    buf:text(2, 2, "No clip open. Put the cursor on a clip of a drum track and press", "Empty")
    buf:text(67, 2, "Enter", "EmptyKey")
    buf:text(2, 4, ":drums.track", "EmptyKey")
    buf:text(15, 4, "makes a drum track;", "Empty")
    buf:text(35, 4, ":drums.map", "EmptyKey")
    buf:text(46, 4, "makes any track one.", "Empty")
    return
  end
  local c = clip:get()
  local track = api.track_get(c.track)
  local hue = paw.draw.track_hue(track)
  local colour = paw.draw.track_colour(track)
  local rows = self:rows()
  local step = self:step_size()
  local info = drums.info(c.track)
  self.row = util.clamp(self.row, 1, math.max(1, #rows))

  -- The names on the left: as wide as the longest, within reason.
  local namew = 6
  for _, row in ipairs(rows) do namew = math.max(namew, api.str_width(row.name) + 2) end
  namew = math.min(namew, 16)
  -- Under the title the toolbar, then the ruler; under the pieces the
  -- velocity lane. The toolbar and the lane are there when every piece has
  -- a row besides, or the grid is tall enough to give them one anyway.
  local tools = (h - 3 >= #rows or h >= 24) and 1 or 0
  local head = 2 + tools
  local lane = (h - head - LANE >= #rows or h >= 30) and LANE or 0
  local body = h - head - lane
  local cells = math.max(1, math.floor((w - namew) / CW))
  local total = math.max(1, math.ceil(c.length / step - EPS))

  -- Keep the cursor on screen.
  local cur = E.cell(self.beat, step)
  if cur < self.scroll then self.scroll = cur end
  if cur >= self.scroll + cells then self.scroll = cur - cells + 1 end
  self.scroll = math.max(0, self.scroll)
  if self.row < self.first then self.first = self.row end
  if self.row >= self.first + body then self.first = self.row - body + 1 end
  self.first = math.max(1, self.first)
  self.geometry = { namew = namew, cells = cells, body = body, lane = lane, head = head }

  -- Title: the clip in its track's colour, the piece and place under the cursor, the step.
  local piece = rows[self.row]
  local under = piece and E.hit(clip, piece.note, cur * step, step)
  local status = string.format("step %s  vel %d%s  %s", E.step_label(step),
    under and under.velocity or paw.opt.drums_velocity, under and "" or " new", info and info.map or "")
  paw.ui.titlebar(buf, {
    pill = { c.name, hue.pill }, name = track.name, focused = ctx.focused,
    context = string.format("%s  %s", piece and piece.name or "-", paw.time.format(c.start + self.beat)),
    right = status,
  })
  if tools > 0 then toolbar(buf, 1, clip, step) end

  -- The ruler: bars as the project counts them, beats between as ticks, as in the roll.
  local ry = head - 1
  buf:fill(0, ry, w, 1, " ", "Ruler")
  buf:hit(namew, ry, math.min(cells, total - self.scroll) * CW, 1, { kind = "ruler", hint = "click to move the playhead here" })
  local bar = paw.time.bar()
  for i = 0, cells - 1 do
    local cell = self.scroll + i
    if cell >= total then break end
    local pos = c.start + cell * step
    local cx = namew + i * CW
    local on_bar = math.abs(pos / bar - math.floor(pos / bar + 0.5)) < EPS
    local on_beat = math.abs(pos - math.floor(pos + 0.5)) < EPS
    if on_bar then
      buf:text(cx, ry, tostring(math.floor(pos / bar + 0.5) + 1), "RulerBar")
    elseif on_beat then
      buf:text(cx, ry, g.tick, "RulerTick")
    end
  end

  -- The rows: name, then a cell per step. A drag of the pointer shows what
  -- it is about to do before it is done.
  local hits = E.cells(clip, step, self.scroll * step, (self.scroll + cells) * step)
  local selection = ctx.focused and paw.keymap.selection()
  local drag = self.drag
  for r = 0, body - 1 do
    local index = self.first + r
    local row = rows[index]
    local y = head + r
    if not row then break end
    local on_row = index == self.row
    buf:fill(0, y, namew, 1, " ", on_row and "TrackHeaderSel" or "TrackHeader")
    buf:text(1, y, row.name, row.extra and "Faint" or on_row and hue.fg or nil)
    buf:hit(0, y, namew, 1, { kind = "name", row = index, hint = row.name .. ": click to hear it" })
    for i = 0, cells - 1 do
      local cell = self.scroll + i
      local cx = namew + i * CW
      if cell >= total then
        buf:fill(cx, y, w - cx, 1, " ", "RollOutside")
        break
      end
      local pos = cell * step
      local abs = c.start + pos
      local line = math.abs(abs / bar - math.floor(abs / bar + 0.5)) < EPS and "bar"
        or math.abs(abs - math.floor(abs + 0.5)) < EPS and "beat" or nil
      local dark = math.floor(abs + EPS) % 2 == 1
      local hit = hits[row.note] and hits[row.note][cell]
      local velocity, off = hit and hit.velocity, hit and hit.off
      if drag and drag.row == index and drag.cells and drag.cells[cell] ~= nil then
        velocity, off = drag.cells[cell] and paw.opt.drums_velocity or nil, false
      end
      local action = { kind = "cell", row = index, cell = cell }
      if velocity then
        buf:mark("hit", cx, y, CW, 1, { velocity = velocity, off = off, line = line, dark = dark, style = hue.fg, color = colour, hit = action })
      else
        buf:mark("step", cx, y, CW, 1, { line = line, dark = dark, hit = action })
      end
      if selection then
        local in_time = selection.kind == "line" or (pos >= selection.c0 - EPS and pos < selection.c1 - EPS)
        local in_rows = selection.kind == "char" or (index >= selection.r0 and index <= selection.r1)
        if in_time and in_rows then buf:fill(cx + 1, y, CW - 1, 1, nil, "Visual") end
      end
      if on_row and cell == cur and not selection then
        buf:fill(cx + 1, y, CW - 1, 1, nil, velocity and "NoteCursor" or "RollCursor")
      end
    end
  end

  -- How hard each hit of the cursor's row is, as bars two rows tall.
  if lane > 0 then
    local ly = h - lane
    buf:fill(0, ly, w, lane, " ", "Ruler")
    buf:text(1, ly, "velocity", "Faint")
    if piece then buf:text(1, ly + 1, util.fit(piece.name, namew - 2), hue.fg) end
    buf:hit(namew, ly, math.min(cells, total - self.scroll) * CW, lane, { kind = "velocity", hint = "click or drag: how hard the row's hits are" })
    for i = 0, cells - 1 do
      local cell = self.scroll + i
      if cell >= total then break end
      local hit = piece and hits[piece.note] and hits[piece.note][cell]
      local v = hit and hit.velocity
      if v and drag and drag.values and drag.values[cell] then v = drag.values[cell] end
      if v then
        -- Sixteen eighths over the two rows.
        local eighths = math.max(1, math.floor(v / 127 * 16 + 0.5))
        local cx = namew + i * CW + 1
        if eighths > 8 then buf:text(cx, ly, string.rep(g.eighths[eighths - 8], CW - 1), hue.fg) end
        buf:text(cx, ly + 1, string.rep(g.eighths[math.min(8, eighths)], CW - 1), hue.fg)
      end
    end
  end

  local t = api.transport_get()
  if t.position >= c.start and t.position < c.start + c.length then
    local i = E.cell(t.position - c.start, step) - self.scroll
    if i >= 0 and i < cells then
      local cx = namew + i * CW
      buf:text(cx, ry, g.cap, "RulerPlayhead")
      for r = 0, math.min(body, #rows - self.first + 1) - 1 do buf:fill(cx, head + r, 1, 1, nil, "PlayheadShade") end
    end
  end
end

-- Moving --------------------------------------------------------------------

function view:set(row, beat)
  local clip = self:clip()
  if not clip then return end
  if row then self.row = util.clamp(row, 1, math.max(1, #self:rows())) end
  if beat then self.beat = util.clamp(beat, 0, clip.length) end
  api.ui_redraw()
end

function view:move(dsteps, drows)
  local clip = self:clip()
  if not clip then return end
  local step = self:step_size()
  -- One step past the last is allowed, so that a selection can reach the end.
  local to = (E.cell(self.beat, step) + dsteps) * step
  self:set(self.row + drows, util.clamp(to, 0, clip.length))
end

--- The next (`dir` 1) or previous (-1) hit on the cursor's row.
function view:to_hit(dir, count)
  local piece, clip = self:piece(), self:clip()
  if not (piece and clip) then return end
  local starts = {}
  for _, n in ipairs(clip:notes({ low = piece.note, high = piece.note })) do starts[#starts + 1] = n.start end
  for _ = 1, count or 1 do
    local found
    if dir > 0 then
      for _, s in ipairs(starts) do
        if s > self.beat + EPS then found = s break end
      end
    else
      for i = #starts, 1, -1 do
        if starts[i] < self.beat - EPS then found = starts[i] break end
      end
    end
    if not found then return end
    self:set(nil, E.cell(found, self:step_size()) * self:step_size())
  end
end

function view:to_bar(n)
  local clip = self:clip()
  if not clip then return end
  local bar = paw.time.bar()
  local at = (clip.start + self.beat) / bar
  local to = n > 0 and math.floor(at + EPS) + n or math.ceil(at - EPS) + n
  self:set(nil, to * bar - clip.start)
end

-- Changing ------------------------------------------------------------------

--- Put a hit in at the cursor or take it out; a new hit is heard.
function view:toggle()
  local clip, piece = self:clip(), self:piece()
  if not (clip and piece) then return end
  local step = self:step_size()
  local beat = E.cell(self.beat, step) * step
  if E.set(clip, piece.note, beat, step, nil, paw.opt.drums_velocity) then self:hear() end
end

function view:hear(note)
  local track, piece = self:track_id(), self:piece()
  if track and (note or piece) then drums.hear(track, note or piece.note) end
end

--- Harder (`by` > 0) or softer: the hit under the cursor.
function view:velocity(by)
  local clip, piece = self:clip(), self:piece()
  if not (clip and piece) then return end
  local step = self:step_size()
  local v = E.velocity(clip, piece.note, E.cell(self.beat, step) * step, step, by)
  if v then paw.notify(piece.name .. " velocity " .. v) end
end

function view:set_step(step)
  self.step = step
  -- The cursor stays on a step of the new grid.
  self.beat = E.cell(self.beat, step) * step
  paw.notify("step " .. E.step_label(step))
  api.ui_redraw()
end

-- What modal editing works on: rows are the pieces, counted downwards.
view.grid = {
  get = function() return view.row, view.beat end,
  set = function(row, col) view:set(row, col) end,
  step = function() return view:step_size() end,
  -- The step under the cursor is a cell: a selection takes it in, as Vim's
  -- takes in the character under the cursor.
  extent = function(_, col)
    local step = view:step_size()
    return (math.floor(col / step + 1e-9) + 1) * step
  end,
  -- Pieces by name: `/snare` goes to the snare's row.
  search = function(text)
    local wanted, out = text:lower(), {}
    for i, row in ipairs(view:rows()) do
      if row.name:lower():find(wanted, 1, true) then out[#out + 1] = { row = i, col = view.beat } end
    end
    return out
  end,
}

-- The pointer -----------------------------------------------------------------

--- Play the clip round and round from its start, or stop.
local function play_clip(clip)
  local t = paw.transport
  if api.transport_get().playing then return t.stop() end
  t.loop_start, t.loop_end, t.loop_enabled = clip.start, clip.start + clip.length, true
  t.seek(clip.start)
  t.play()
end

--- The step whose column is under the pointer, on the clip or nil.
local function cell_at(self, x)
  local g, clip = self.geometry, self:clip()
  if not (g and clip) then return nil end
  local cell = self.scroll + math.floor((x - g.namew) / CW)
  local total = math.max(1, math.ceil(clip.length / self:step_size() - EPS))
  if cell >= 0 and cell < total then return cell end
end

--- How hard a hit is for a point of the velocity lane `rect`: as hard as
--- can be at its top, half as hard half way down.
local function velocity_at(rect, y)
  return drums.clamp_velocity((rect.y + rect.h - y) / rect.h * 127)
end

--- Apply what a drag collected, as one edit: the cells of a row painted
--- (true) or erased (false), or the velocities of the cursor's row.
local function finish(self, drag)
  local clip = self:clip()
  if not (clip and drag) then return end
  local step = self:step_size()
  if drag.cells then
    local piece = self:rows()[drag.row]
    if not piece then return end
    local add, remove, existing = {}, {}, {}
    for index, n in ipairs(clip:notes()) do
      if n.pitch == piece.note then
        local cell = E.cell(n.start, step)
        existing[cell] = true
        if drag.cells[cell] == false then remove[#remove + 1] = index end
      end
    end
    for cell, on in pairs(drag.cells) do
      if on and not existing[cell] and cell * step < clip.length - EPS then
        add[#add + 1] = { pitch = piece.note, start = cell * step, length = math.min(step, clip.length - cell * step), velocity = paw.opt.drums_velocity }
      end
    end
    if #add > 0 or #remove > 0 then clip:edit_notes({ add = add, remove = remove }) end
  elseif drag.values then
    local piece = self:rows()[self.row]
    if not piece then return end
    local set = {}
    for index, n in ipairs(clip:notes()) do
      local v = n.pitch == piece.note and drag.values[E.cell(n.start, step)]
      if v and v ~= n.velocity then set[#set + 1] = { index = index, velocity = v } end
    end
    if #set > 0 then clip:edit_notes({ set = set }) end
  end
end

--- Hold the pointer for a drag that collects cells (`collect(drag, cell,
--- d)` for each crossed), applied when it is let go.
local function hold(self, e, drag, collect)
  self.drag = drag
  paw.mouse.grab(e, {
    drag = function(d)
      local at = cell_at(self, d.x)
      if not at then return end
      -- Every cell crossed since the last move, so a quick stroke leaves no gaps.
      for k = math.min(drag.last, at), math.max(drag.last, at) do collect(drag, k, d) end
      drag.last = at
    end,
    up = function()
      self.drag = nil
      finish(self, drag)
      api.ui_redraw()
    end,
    cancel = function() self.drag = nil end,
  })
end

-- What the pointer does on each part of the grid, from a terminal in cells
-- or a window in fractions of one alike (paw/roles.lua). The wheel is left to
-- `on_mouse`.
view.gestures = {
  tool = function(self, e)
    if e.kind ~= "down" or e.button ~= "left" then return false end
    local clip, h = self:clip(), e.hit
    if not clip then return end
    if h.play then
      play_clip(clip)
    elseif h.step then
      self:set_step(h.step)
    elseif h.bars then
      local bars = clip.length / paw.time.bar()
      E.set_bars(clip, h.bars > 0 and math.floor(bars + EPS) + 1 or math.max(1, math.ceil(bars - EPS) - 1))
    end
  end,
  ruler = function(self, e)
    if e.kind ~= "down" then return false end
    local clip, cell = self:clip(), cell_at(self, e.x)
    if clip and cell then api.transport_seek(clip.start + cell * self:step_size()) end
  end,
  name = function(self, e)
    if e.kind ~= "down" then return false end
    self.row = e.hit.row
    self:hear()
    api.ui_redraw()
  end,
  cell = function(self, e)
    if e.kind ~= "down" or (e.button ~= "left" and e.button ~= "right") then return false end
    local clip, piece = self:clip(), self:rows()[e.hit.row]
    if not (clip and piece) then return end
    local step, cell = self:step_size(), e.hit.cell
    self.row, self.beat = e.hit.row, cell * step
    local paint = e.button == "left" and E.hit(clip, piece.note, cell * step, step) == nil
    if paint then self:hear() end
    hold(self, e, { row = e.hit.row, cells = { [cell] = paint }, last = cell }, function(drag, k)
      drag.cells[k] = paint
      self.beat = k * step
    end)
    api.ui_redraw()
  end,
  velocity = function(self, e)
    if e.kind ~= "down" or e.button ~= "left" then return false end
    local cell = cell_at(self, e.x)
    if not cell then return end
    local rect = e.rect
    self.beat = cell * self:step_size()
    hold(self, e, { values = { [cell] = velocity_at(rect, e.y) }, last = cell }, function(drag, k, d)
      drag.values[k] = velocity_at(rect, d.y)
    end)
    api.ui_redraw()
  end,
}

--- The wheel scrolls the rows.
function view:on_mouse(event)
  if not self:clip() then return end
  if event.kind == "scroll_up" then self.first = math.max(1, self.first - 2) end
  if event.kind == "scroll_down" then self.first = self.first + 2 end
  api.ui_redraw()
end

paw.ui.view("drums", view)
paw.ui.dock("drums", { side = "bottom", hidden = true })

return view
