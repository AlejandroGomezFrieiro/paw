-- The session view: a column of slots for each part and a row for each
-- scene, with the scenes' names down the right. A clip that plays is lit in
-- its part's colour and filled as it goes round its loop; one queued to
-- start is marked until its boundary comes. The last row says what each
-- part plays: a slot, nothing (stopped), or its timeline. One view for the
-- terminal and the window: the window draws it from its scene.
local api = paw.api
local util = paw.util
local draw = paw.draw
local mouse = paw.mouse
local launcher = require("launcher")

-- Each window of the session view has its own scroll: it shows in any
-- number of windows. The slot of the cursor is one for them all.
local view = {
  scroll = 0,
  top = 0,
  title = "Session",
  help = "launcher",
  window_state = { "scroll", "top", "geometry" },
  window_fresh = { "geometry" },
  -- What plays fills its slot while the song plays: the view is drawn
  -- again as one live part, not the whole screen.
  live_part = true,
}

local GUTTER = 4 -- the row numbers
local SCENES = 14 -- the scenes' column

--- Columns a part takes on a screen `w` wide with `n` parts, the gap after it included.
function view.column_width(w, n) return util.clamp(math.floor((w - GUTTER - SCENES) / math.max(1, n)), 10, 20) end

--- The text of a slot, `width` cells: a mark, then the clip's name.
local function label(mark, name, width) return util.fit(mark .. " " .. name, width) end

local function slot_cell(buf, x, y, width, clip, hue, state)
  local g = draw.g
  if not clip then
    buf:fill(x, y, width, 1, " ", "PartHeader")
    buf:text(x + 1, y, g.dot, state.queued and "Accent" or "PartIndex")
    return
  end
  if state.playing then
    -- Lit, and filled as far as it has gone round its loop.
    local text = label(g.play, clip.name, width)
    buf:fill(x, y, width, 1, " ", hue.title)
    buf:text(x, y, text, hue.title)
    local filled = math.floor(util.clamp(state.progress, 0, 1) * width + 0.5)
    if filled > 0 then
      buf:fill(x, y, filled, 1, " ", hue.pill)
      buf:text(x, y, util.fit(text, filled), hue.pill)
    end
  elseif state.queued then
    buf:fill(x, y, width, 1, " ", hue.body_cur)
    buf:text(x, y, label(g.closed, clip.name, width), hue.body_cur)
  else
    buf:fill(x, y, width, 1, " ", clip.muted and hue.body_off or hue.body)
    buf:text(x, y, label(g.stop, clip.name, width), clip.muted and hue.title_off or hue.body)
  end
end

--- What the last row says of a part.
local function status_text(s)
  local g = draw.g
  if not s then return "timeline", "PartIndex" end
  local queued = s.queued == "stop" and (" " .. g.closed .. g.stop)
    or s.queued == "arrangement" and (" " .. g.closed .. "tl")
    or type(s.queued) == "number" and (" " .. g.closed .. (s.queued + 1))
    or ""
  if s.slot then
    local bar = paw.time.bar(0)
    local at = s.length
        and string.format(" %d/%d", math.floor(s.phase / bar) + 1, math.max(1, math.ceil(s.length / bar - 1e-9)))
      or ""
    return g.play .. " " .. (s.slot + 1) .. at .. queued, "Bright"
  elseif s.stopped then
    return g.stop .. " stopped" .. queued, "PartInfo"
  end
  return "timeline" .. queued, "PartIndex"
end

--- What the drawing in a window shows of what plays, as a key (see
--- `paw.scene`): the cells each slot that plays is filled to, and what the
--- last row says. While it stays the same, the window gets no new scene of
--- the view as the song plays.
function view:scene_key()
  local geo = self.geometry
  if not geo then return nil end
  local state = launcher.state()
  local parts = { tostring(launcher.capturing), tostring(launcher.recording ~= nil) }
  for _, c in ipairs(geo.columns) do
    local s = state[c.id]
    if s then
      local filled = s.length
          and s.length > 0
          and math.floor(util.clamp((s.phase or 0) / s.length, 0, 1) * (geo.cw - 1) + 0.5)
        or 0
      parts[#parts + 1] = table.concat({ c.id, tostring(s.slot), tostring(s.queued), filled, (status_text(s)) }, "/")
    end
  end
  return table.concat(parts, ";")
end

function view:render(buf, ctx)
  local g = draw.g
  -- A VCA has no clips to launch.
  local parts = {}
  for _, id in ipairs(paw.scope.parts()) do
    if not paw.vca.is_vca(id) then parts[#parts + 1] = id end
  end
  local body = paw.ui.titlebar(buf, {
    name = "Session",
    context = "launches on " .. launcher.quantize() .. (launcher.capturing and ("  " .. g.rec .. " capturing") or ""),
    focused = ctx.focused,
  })
  local w, h = body.width, body.height
  body:fill(0, 0, w, h, " ", "PartHeader")
  local cw = view.column_width(w, #parts)
  local room = math.max(1, math.floor((w - GUTTER - SCENES) / cw))
  local index = 1
  for i, id in ipairs(parts) do
    if id == paw.cursor.part_id() then index = i end
  end
  if index <= self.scroll then self.scroll = index - 1 end
  if index > self.scroll + room then self.scroll = index - room end
  self.scroll = util.clamp(self.scroll, 0, math.max(0, #parts - room))
  -- Rows: the names, the slots, and the line saying what plays.
  local rows = launcher.rows()
  local shown = math.max(1, h - 2)
  if launcher.row < self.top then self.top = launcher.row end
  if launcher.row >= self.top + shown then self.top = launcher.row - shown + 1 end
  self.top = util.clamp(self.top, 0, math.max(0, rows - shown))
  local state = launcher.state()
  local cursor_part = paw.cursor.part_id()
  local columns = {}
  for col = 0, room - 1 do
    local i = self.scroll + col + 1
    local id = parts[i]
    if not id then break end
    local t = api.part_get(id)
    local hue = draw.part_hue(t, i)
    local x = GUTTER + col * cw
    local selected = id == cursor_part
    columns[#columns + 1] = { id = id, x = x }
    body:fill(x, 0, cw - 1, 1, " ", selected and hue.title_cur or hue.plate)
    body:text(x + 1, 0, util.fit(t.name, cw - 2), selected and hue.title_cur or hue.plate)
    local s = state[id] or {}
    local slots = launcher.slots(id)
    for r = 0, shown - 1 do
      local row = self.top + r
      if row >= rows then break end
      local clip = slots[row]
      local cell = {
        playing = s.slot == row,
        queued = s.queued == row,
        progress = (s.slot == row and s.length and s.length > 0) and s.phase / s.length or 0,
      }
      local rec = launcher.recording
      if rec and rec.part == id and rec.row == row then
        body:fill(x, r + 1, cw - 1, 1, " ", "Armed")
        body:text(x, r + 1, label(g.rec, "recording", cw - 1), "Armed")
      else
        slot_cell(body, x, r + 1, cw - 1, clip, hue, cell)
      end
      if selected and row == launcher.row then body:text(x - 1, r + 1, g.mark, ctx.focused and "Cursor" or "Accent") end
    end
    local text, style = status_text(state[id])
    body:text(x, h - 1, util.fit(text, cw - 1), style)
  end
  -- Row numbers, and the scenes down the right.
  local sx = GUTTER + #columns * cw + 1
  body:fill(sx - 1, 0, 1, h, g.rule, "Rule")
  body:text(sx, 0, util.fit("Scenes", SCENES - 1), "PartName")
  for r = 0, shown - 1 do
    local row = self.top + r
    if row >= rows then break end
    local here = row == launcher.row
    body:text(0, r + 1, string.format("%3d", row + 1), here and "Bright" or "PartIndex")
    body:text(sx, r + 1, label(g.play, launcher.scene_name(row), SCENES - 1), here and "PartNameSel" or "PartInfo")
  end
  body:text(0, h - 1, util.fit(g.stop, GUTTER - 1), "PartIndex")
  body:text(sx, h - 1, util.fit(g.stop .. " stop all", SCENES - 1), "PartInfo")
  self.geometry = { columns = columns, cw = cw, sx = sx, shown = shown, h = h }
end

-- What the pointer does ---------------------------------------------------------
--
-- The play mark of a slot pressed launches the clip (or stops the part, on
-- an empty slot); let go, it stops a gate clip. The rest of a slot: a click
-- chooses it, a double click opens its notes (an empty one gets a new MIDI
-- clip first), a drag moves the clip to another slot (Ctrl copies). A
-- scene launches its row. The last row stops the part, or every part
-- under the scenes. A clip from the timeline let go on a slot (in the
-- window) is copied there.

local act = {}
view.act = act

--- A click on a slot: the cursor goes there, launching nothing, and the
--- keys are the session view's.
function act.choose(part, row)
  paw.cursor.set_part(part)
  launcher.row = row
  if paw.ui.visible("session") then paw.ui.focus("session") end
  api.ui_redraw()
end

--- A slot pressed, or let go of (`down` false): see `launcher.press` and `release`.
function act.press(part, row, down)
  paw.cursor.set_part(part)
  launcher.row = row
  if down == false then return launcher.release(part, row) end
  launcher.press(part, row)
end

--- Record into an empty slot, or stop the recording.
function act.record(part, row)
  act.choose(part, row)
  if launcher.recording then return launcher.finish_recording() end
  launcher.record(part, row)
end

--- A double click on an empty slot: a MIDI clip of a bar there, opened in
--- the piano roll. On a slot with a MIDI clip it opens that. Returns the clip.
function act.open(part, row)
  act.choose(part, row)
  local clip = launcher.clip(part, row)
  local id = clip and clip.id or launcher.new_clip(part, row)
  if not clip or clip.kind == "midi" then paw.ui.views:get("pianoroll"):edit(paw.clip(id)) end
  return id
end

--- A clip from the timeline let go on a slot: a copy of it goes there.
function act.drop(clip, part, row)
  act.choose(part, row)
  local id = launcher.copy(clip, part, row)
  paw.notify("copied " .. api.clip_get(id).name .. " into slot " .. (row + 1))
  return id
end

--- A slot's clip dragged to another, with `copy` (Ctrl) as a copy.
function act.move(clip, part, row, copy)
  if copy then
    launcher.copy(clip, part, row)
  else
    launcher.move(clip, part, row)
  end
  act.choose(part, row)
end

local hints = {
  clip = "clip: its play mark launches it · click chooses · double click opens its notes · drag moves it, Ctrl copies · right click for more",
  empty = "empty slot: double click makes a MIDI clip · its dot records a bar into it",
  scene = "scene: launches every clip in its row together",
  stop = "stops the part's clip",
}

--- The column of the session view under `x`, if any.
local function column_at(geo, x)
  for _, c in ipairs(geo.columns) do
    if x >= c.x - 1 and x < c.x + geo.cw - 1 then return c end
  end
end

local function screen(e) return { x = e.x + (e.view_x or 0), y = e.y + (e.view_y or 0) } end

function view:on_mouse(e)
  local geo = self.geometry
  if not geo then return end
  -- Under the title bar, in the body's own lines.
  local x, y = e.x, e.y - 1
  local row = self.top + y - 1
  local step, sideways = mouse.wheel(e)
  if step then
    if sideways or mouse.has(e, "S") then
      paw.cursor.move_part(step)
    else
      self.top = math.max(0, self.top + step)
    end
    return api.ui_redraw()
  end
  local in_slots = y >= 1 and y <= geo.shown
  if x >= geo.sx then
    if e.kind == "move" then return mouse.hint(in_slots and hints.scene or nil) end
    if e.kind ~= "down" or e.button ~= "left" then return end
    if y == geo.h - 1 then return launcher.stop(nil) end
    if in_slots then
      launcher.row = row
      return launcher.scene(row)
    end
    return
  end
  local col = column_at(geo, x)
  if not col then return end
  local clip = in_slots and launcher.clip(col.id, row) or nil
  if e.kind == "move" then
    return mouse.hint(y == geo.h - 1 and hints.stop or in_slots and (clip and hints.clip or hints.empty) or nil)
  end
  if e.kind ~= "down" then return end
  if y == geo.h - 1 then
    if e.button == "left" then launcher.stop(col.id) end
    return
  end
  if not in_slots then return end
  if e.button == "right" then
    if clip then
      local where = screen(e)
      local menus = require("paw.mouse_menus")
      mouse.grab(e, {
        up = function(u)
          if not u.moved then paw.ui.menu(menus.clip(clip.id, clip.start), where) end
        end,
      })
    end
    return
  end
  if e.button ~= "left" then return end
  if e.double then return act.open(col.id, row) end
  if clip and x == col.x then
    -- The play mark launches it, and its release lets a gate or a one-shot go.
    act.press(col.id, row, true)
    return mouse.grab(e, { up = function() act.press(col.id, row, false) end })
  end
  if not clip and x == col.x + 1 then return act.record(col.id, row) end
  act.choose(col.id, row)
  if not clip then return end
  mouse.grab(e, {
    up = function(u)
      local to = u.moved and column_at(geo, u.x)
      local to_row = self.top + u.y - 2
      if to and to_row >= 0 then act.move(clip.id, to.id, to_row, mouse.has(u, "C")) end
    end,
  })
end

--- A clip let go over the view (from the window's arrange view): into the
--- slot under the pointer.
function view:on_drop(e)
  local geo = self.geometry
  if not (geo and e.clip) then return end
  local y = e.y - 1
  local col = column_at(geo, e.x)
  if not col or y < 1 or y > geo.shown then return end
  act.drop(e.clip, col.id, self.top + y - 1)
end

paw.ui.view("session", view)
paw.ui.dock("session", { side = "bottom", hidden = true })
paw.panes.least.session = { h = 150 }
return view
