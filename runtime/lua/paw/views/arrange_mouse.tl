-- The pointer in the arrange view, in both frontends. The view marks all
-- of itself as one hit region (`arrange`) and its timeline as a plane: a
-- press comes here from the terminal in whole cells and from a window in
-- fractions of them (`e.fine`), and finds what is under it (a clip and
-- which part, a header's control, the ruler's flags and edges, a lane's
-- point). The gesture calls `paw.frontend.act` with beats, rows and values.
-- A gesture that changes the project does so once, when the button is let
-- go, and is drawn over the view until then; one that moves a control or a
-- selection does so as it goes. Parts smaller than a cell (an audio clip's
-- fade handles, its gain line) only a window's pointer finds.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local menus = require("paw.mouse_menus")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type Arrange = require("paw.views.arrange")
local type roles = require("paw.roles.arrange")
local type FrontendModule = require("paw.frontend")
local type MouseModule = require("paw.mouse")
local type MarkersModule = require("paw.markers")
local type TempoModule = require("paw.tempo")
local type Buf = contracts.Buf
local type MouseEvent = contracts.MouseEvent
local type Row = Arrange.Row

local util = paw.util
local mouse = paw.mouse
local view = paw.ui.views:get("arrange") as Arrange
local A = paw.frontend.act

--- What is under the pointer (`hit`): where it is in the view (`x`, `y`)
--- and on the timeline (`tx`, `beat`), whether over the headers or the
--- timeline, and the area: "ruler", "markers" (`lane_row` the regions'
--- row), "band" (`band` the entry), "tempo" (`y0` its first line),
--- "track", "take", "lane" (`row` the row), "master" or "below". On a
--- track's timeline, the clip under it, which part (`part`) and the warp
--- marker (`warp`).
local record Hit
  x: number
  y: number
  tx: number
  beat: number
  header: boolean
  timeline: boolean
  fine: boolean
  area: string
  lane_row: integer
  band: FrontendModule.BandState
  y0: integer
  row: Row
  clip: types.Clip
  part: string
  warp: integer
end

--- A gesture of this view: what it draws over the view while it holds
--- the pointer (`arrange`), the clip a window may let go over another
--- view (`clip`), and the last drag (`d`) or the columns of it (`dx`).
local record Grab is MouseModule.Handlers
  arrange: function(v: Arrange, buf: Buf)
  clip: integer
  d: MouseEvent
  dx: number
end

--- Hold the pointer from a press with this view's gesture.
local function hold(e: MouseEvent, grab: Grab)
  mouse.grab(e, grab)
end

--- The gesture under way, as this view made it.
local function held(): Grab
  return mouse.gesture() as Grab
end

-- Columns and beats through the view's map, which has its time folds
-- (paw/views/arrange.tl `view:col`, `view:beat`).
local function grid_at(self: Arrange, tx: number): number
  local grid = paw.opt.grid
  return math.floor(self:beat(tx) / grid + 1e-6) * grid
end
local function cells(self: Arrange, d: number): number
  return d / self.geometry.zoom
end

--- Where the pointer of `e` is on the screen, for a menu there; `down`
--- lines lower.
local function screen_at(e: MouseEvent, down?: integer): contracts.MenuOptions
  return {x = e.x + (e.view_x or 0), y = e.y + (e.view_y or 0) + (down or 0)}
end

--- The beats from a press at column `x0` to the pointer at `x1` of the
--- timeline: a terminal's cells taken in whole, a window's pointer where
--- it is.
local function stretch(self: Arrange, x0: number, x1: number, fine: boolean): number, number
  if not fine then
    if x1 >= x0 then
      x1 = x1 + 1
    else
      x0 = x0 + 1
    end
  end
  return self:beat(x0), self:beat(x1)
end

--- Which part of clip `c` a press `into` columns from its start is on,
--- `cw` columns wide, `dy` lines under the row's top: "warp" with the
--- marker's place, an audio clip's "fade_in", "fade_out" or "gain" (a
--- window's handles at its top), "start" or "end" (a cell's worth at
--- either end, when it is three cells or more), or "body".
local function clip_part(
  zoom: number, c: types.Clip, into: number, cw: number, dy: number, fine: boolean
): string, integer
  local part, index = "body", nil as integer
  for i, m in ipairs(c.warp or {}) do
    local nx = (m.beat - c.start) * zoom
    if fine then
      if nx > 0 and nx < cw and math.abs(into - nx) <= 0.6 and dy < 1 then
        part, index = "warp", i
      end
    else
      local cell = math.floor(nx + 0.5)
      if cell > 0 and cell < cw and into == cell then
        part, index = "warp", i
      end
    end
  end
  if part == "body" and fine and c.kind == "audio" and dy < 0.55 then
    -- The handles at the top corners, where the fades end; the gain
    -- line along the top between them.
    local fade_in, fade_out = (c.fade_in or 0) * zoom, cw - (c.fade_out or 0) * zoom
    if math.abs(into - fade_in) <= 0.6 then
      part = "fade_in"
    elseif math.abs(into - fade_out) <= 0.6 then
      part = "fade_out"
    elseif dy < 0.3 and into >= 1.3 and into <= cw - 1.3 then
      part = "gain"
    end
  end
  if part == "body" then
    local edge = fine and 0.9 or 1
    if cw >= 3 and into < edge then
      part = "start"
    elseif cw >= 2 and cw - into <= edge then
      part = "end"
    end
  end
  return part, index
end

--- The clip of a track row under timeline column `tx`, `dy` lines under
--- the row's top, and which part of it (`clip_part`).
local function clip_at(self: Arrange, row: Row, tx: number, dy: number, fine: boolean): types.Clip, string, integer
  local found: types.Clip
  local part: string
  local index: integer
  -- A time fold's column holds no clip.
  if self:fold_at(tx) then
    return nil
  end
  for _, c in ipairs(api.clip_list(row.id)) do
    local x0, cw: number, number
    if fine then
      x0 = self:x(c.start)
      cw = math.max(1, self:x(c.start + c.length) - x0)
    else
      x0 = self:col(c.start)
      cw = math.max(1, self:col(c.start + c.length) - x0)
    end
    if tx >= x0 and tx < x0 + cw then
      found = c
      part, index = clip_part(self.geometry.zoom, c, tx - x0, cw, dy, fine)
    end
  end
  return found, part, index
end

--- A tempo or signature flag on the ruler: its columns and its mark.
local record Flag
  x0: integer
  x1: integer
  mark: TempoModule.Mark
end

--- The tempo and signature flags on the ruler, where they are drawn.
local function ruler_marks(self: Arrange): {Flag}
  local out: {Flag} = {}
  local mark_end = -1
  for _, mark in ipairs(paw.tempo.marks(self.scroll, self:beat(self.geometry.layout.tw))) do
    local x = self:col(mark.beat)
    if paw.tempo.is_bar_line(mark.beat) then
      x = x + #tostring(paw.time.bar_of(mark.beat))
    end
    x = math.max(x, mark_end)
    local w = 1 + api.str_width(mark.text)
    out[#out + 1] = {x0 = x, x1 = x + w, mark = mark}
    mark_end = x + w + 1
  end
  return out
end

--- The marker or region whose name (or band) is under column `tx` of row
--- `row` of the regions' lane (0 the first; paw/markers.tl).
local function marker_at(self: Arrange, tx: number, row: integer): MarkersModule.Marker
  -- Each one where the lane draws it (`paw.markers.placed`): inside a
  -- subproject or a scope, in the window's time and cut at its edges.
  local record Placed
    m: MarkersModule.Marker
    x0: integer
    x1: integer
  end
  local list: {Placed} = {}
  local time = paw.ruler.lane_time()
  for _, m in ipairs(paw.markers and paw.markers.list() or {}) do
    local start, stop = paw.markers.placed(m, time)
    if start and paw.markers.lane_row(m.id) == (row or 0) then
      list[#list + 1] = {m = m, x0 = self:col(start), x1 = self:col(stop)}
    end
  end
  local width = self.geometry.layout.tw
  local band: MarkersModule.Marker
  for i, p in ipairs(list) do
    local x = p.x0
    local stop = width
    for j = i + 1, #list do
      local nx = list[j].x0
      if nx > x then
        stop = math.min(stop, nx)
        break
      end
    end
    local w = 1 + api.str_width(paw.markers.label(p.m))
    if tx >= x and tx < math.min(stop, x + w) then
      return p.m
    end
    if p.m.length and tx >= x and tx < p.x1 then
      band = p.m
    end
  end
  return band
end

--- The entry of an extension's band on band row `row` under column `tx`
--- of the timeline, as the view draws it.
local function band_at(self: Arrange, bands: FrontendModule.Bands, row: integer, tx: number): FrontendModule.BandState
  local found: FrontendModule.BandState
  for _, e in ipairs(bands.entries) do
    if e.row == row then
      local x0 = self:col(e.beat)
      local span = e.length > 0 and math.max(1, self:col(e.beat + e.length) - x0) or api.str_width(e.name) + 2
      if tx >= x0 and tx < x0 + span then
        found = e
      end
    end
  end
  return found
end

--- What is under the pointer at `x`, `y` of the view (fractions of cells
--- from a window, `fine`).
local function hit(self: Arrange, x: number, y: number, fine: boolean): Hit
  local g = self.geometry
  local L = g.layout
  local out: Hit = {x = x, y = y, tx = x - g.hw, header = x < g.hw - 1, timeline = x >= g.hw, fine = fine}
  out.beat = self:beat(out.tx)
  local tempo_y = L.ruler_rows - L.tempo_rows
  if y < 1 then
    out.area = "ruler"
  elseif y < L.band_y then
    out.area, out.lane_row = "markers", math.floor(y) - 1
  elseif y < tempo_y then
    out.area = "band"
    out.band = band_at(self, L.bands, math.floor(y - L.band_y), out.tx)
  elseif y < L.ruler_rows then
    out.area, out.y0 = "tempo", tempo_y
  elseif y >= L.master.y then
    out.area = "master"
  else
    for _, row in ipairs(L.rows) do
      if y >= row.y and y < row.y + row.h then
        out.area, out.row = row.kind, row
      end
    end
    out.area = out.area or "below"
  end
  if out.area == "track" and out.timeline then
    out.clip, out.part, out.warp = clip_at(self, out.row, fine and out.tx or math.floor(out.tx), y - out.row.y, fine)
  end
  return out
end

--- The row of a drawn track (its place in `paw.groups.rows()`) at line `y`
--- of the view, the nearest one above or below when it is off the tracks.
local function row_index(self: Arrange, y: number): integer
  local rows = self.geometry.layout.rows
  local best: integer
  for _, row in ipairs(rows) do
    if y >= row.y and y < row.y + row.h then
      return row.index
    end
    if row.y <= y then
      best = row.index
    end
  end
  return best or (rows[1] and rows[1].index) or 1
end

--- The line of the view where a drawn track's row is, if it is shown.
local function row_of(self: Arrange, index: integer): Row
  for _, row in ipairs(self.geometry.layout.rows) do
    if row.kind == "track" and row.index == index then
      return row
    end
  end
end

--- Where a gesture over the timeline is drawn: the view without its headers.
local function timeline(self: Arrange, buf: Buf): Buf
  local g = self.geometry
  return buf:sub(g.hw, 0, g.layout.tw, g.layout.master.y)
end

--- A clip where a drag will put it: on the timeline's plane, which a
--- window paints where the pointer is, between cells.
local function ghost(self: Arrange, row: Row, start: number, length: number, text: string)
  if not self.plane then
    return
  end
  local props: roles.ClipProps = {
    ghost = true,
    name = text,
    color = paw.draw.track_colour(api.track_get(row.id), row.index),
  }
  self.plane:mark("clip", self:v(start), row.y, length, row.h, props)
end

local function box(buf: Buf, x0: integer, y0: integer, x1: integer, y1: integer)
  local g = paw.draw.g
  local l, r, t, b = math.min(x0, x1), math.max(x0, x1), math.min(y0, y1), math.max(y0, y1)
  buf:fill(l, t, r - l + 1, 1, g.h, "MouseBox")
  buf:fill(l, b, r - l + 1, 1, g.h, "MouseBox")
  buf:fill(l, t, 1, b - t + 1, g.v, "MouseBox")
  buf:fill(r, t, 1, b - t + 1, g.v, "MouseBox")
end

-- The menu at the pointer -------------------------------------------------------------

--- The menu for what a right click was on, at `where` on the screen.
local function menu_at(self: Arrange, h: Hit, where: contracts.MenuOptions)
  local items: {contracts.MenuEntry}
  if h.area == "track" and h.timeline then
    if h.clip and h.part == "warp" then
      items = menus.warp(h.clip.id, h.warp)
    elseif h.clip then
      A.menu_target(h.clip.id, grid_at(self, h.tx))
      items = menus.clip(h.clip.id, grid_at(self, h.tx))
    else
      local sel = paw.keymap.mode == "x" and paw.keymap.selection()
      local in_selection = sel
        and not sel.clips
        and sel.c0
        and h.beat >= sel.c0
        and h.beat < sel.c1
        and h.row.index >= sel.r0
        and h.row.index <= sel.r1
      if in_selection then
        items = menus.selection()
      else
        A.select(h.row.id, grid_at(self, h.tx))
        items = menus.timeline(h.row.id, grid_at(self, h.tx))
      end
    end
  elseif h.area == "track" then
    A.select(h.row.id)
    items = menus.track(h.row.id)
  elseif h.area == "take" then
    items = menus.takes(h.row.id)
  elseif h.area == "lane" then
    items = menus.lane(h.row.lane.id)
  elseif h.area == "tempo" then
    items = menus.tempo_lane()
  end
  if items then
    paw.ui.menu(items, where)
  end
end

--- The menu of what a press was on, when its button is let go.
local function menu_on_release(self: Arrange, e: MouseEvent, h: Hit)
  hold(e, {up = function() menu_at(self, h, screen_at(e)) end})
end

-- Clips ---------------------------------------------------------------------------

--- The clips a gesture on clip `id` moves: the chosen ones, if it is one.
local function grabbed(id: integer): {integer}
  local ids = paw.frontend.chosen_clips()
  for _, other in ipairs(ids) do
    if other == id then
      return ids
    end
  end
  return {id}
end

local function among_chosen(id: integer): boolean
  local ids = paw.frontend.chosen_clips()
  for _, other in ipairs(ids) do
    if other == id then
      return #ids > 1
    end
  end
  return false
end

--- The clip `c` on its row as it would be with `change` made to its props:
--- drawn over itself while a fade or its gain is dragged.
local function redrawn(self: Arrange, row: Row, c: types.Clip, change: function(props: roles.ClipProps))
  if not self.plane then
    return
  end
  local track = api.track_get(row.id)
  local hue = paw.draw.track_hue(track, row.index)
  local props = view.clip_props(c, track, hue, "", self.geometry.zoom)
  props.key = "drag:clip"
  change(props)
  self.plane:mark("clip", self:v(c.start), row.y, c.length, row.h, props)
end

--- An audio clip's fade handle dragged: the fade ends where it is let go.
local function press_fade(self: Arrange, e: MouseEvent, h: Hit, c: types.Clip)
  local out = h.part == "fade_out"
  local function beats(dx: number): number
    local d = cells(self, dx)
    return util.clamp(out and (c.fade_out or 0) - d or (c.fade_in or 0) + d, 0, c.length)
  end
  hold(
    e,
    {
      arrange = function(v: Arrange)
        local d = held().d
        if d then
          redrawn(
            v,
            h.row,
            c,
            function(props: roles.ClipProps)
              if out then
                props.fade_out = beats(d.dx)
              else
                props.fade_in = beats(d.dx)
              end
            end
          )
        end
      end,
      drag = function(d: MouseEvent)
        held().d = d
        mouse.hint(string.format("fade %s: %s beats", out and "out" or "in", util.round(beats(d.dx), 0.01)))
      end,
      up = function(u: MouseEvent)
        if u.moved then
          A.set_fade(c.id, out and "out" or "in", beats(u.dx))
        end
      end,
    }
  )
end

--- An audio clip's gain dragged up or down: four dB a line, a fifth of
--- one with Shift.
local function press_gain(e: MouseEvent, h: Hit, c: types.Clip)
  local function gain(d: MouseEvent): number
    return util.clamp((c.gain or 0) - d.dy * (mouse.has(d, "S") and 0.8 or 4), -60, 24)
  end
  hold(
    e,
    {
      arrange = function(v: Arrange)
        local d = held().d
        if d then
          redrawn(v, h.row, c, function(props: roles.ClipProps) props.gain, props.gain_line = gain(d), true end)
        end
      end,
      drag = function(d: MouseEvent)
        held().d = d
        mouse.hint(string.format("clip gain: %s dB", util.round(gain(d), 0.1)))
      end,
      up = function(u: MouseEvent)
        if u.moved then
          A.set_clip_gain(c.id, gain(u))
        end
      end,
    }
  )
end

--- A warp marker dragged: it moves where it is let go (Shift off the
--- grid); a click without a drag does what `click` does.
local function press_warp(self: Arrange, e: MouseEvent, h: Hit, c: types.Clip, free: boolean, click: function())
  local m = c.warp[h.warp]
  hold(
    e,
    {
      arrange = function(v: Arrange, buf: Buf)
        local dx = held().dx
        if dx then
          timeline(v, buf):fill(v:col(m.beat + cells(v, dx)), h.row.y, 1, h.row.h, paw.draw.g.tick, "MouseGhost")
        end
      end,
      drag = function(d: MouseEvent) held().dx = d.dx end,
      up = function(u: MouseEvent)
        if not u.moved then
          return click()
        end
        A.warp_move(c.id, h.warp, m.beat + cells(self, u.dx), free)
      end,
    }
  )
end

--- Where the clips a drag moves would go, `drows` tracks down and `by`
--- beats later: ghosts of them on their rows.
local function ghosts_moved(v: Arrange, c: types.Clip, by: number, drows: integer)
  local rows: {integer: integer} = {}
  for i, track in ipairs(paw.groups.rows()) do
    rows[track] = i
  end
  for _, id in ipairs(grabbed(c.id)) do
    local other = api.clip_get(id)
    local row = rows[other.track] and row_of(v, rows[other.track] + drows)
    if row then
      ghost(v, row, math.max(0, other.start + by), other.length, other.name)
    end
  end
end

--- Where a trim of edge `edge` of `c` by `dbeat` would put it: a ghost.
local function ghost_trimmed(v: Arrange, row: Row, c: types.Clip, edge: string, dbeat: number, free: boolean)
  local at = edge == "start" and c.start or c.start + c.length
  local to = free and math.max(0, at + dbeat) or math.max(0, paw.cursor.snap(at + dbeat))
  local a, b = c.start, c.start + c.length
  if edge == "start" then
    a = math.min(to, b - paw.opt.grid)
  else
    b = math.max(to, a + paw.opt.grid)
  end
  ghost(v, row, a, b - a, c.name)
end

--- A press on a clip: a click chooses it (Ctrl and Shift as the window),
--- a drag moves it and the chosen with it (Ctrl copies, Shift off the
--- grid), a drag of its first or last cell trims that edge (Alt slips what
--- plays inside, Alt and Shift on the end stretches it), a drag of a warp
--- marker moves it, a double click opens it (on an audio clip's top row in
--- a window, puts a warp marker there).
local function press_clip(self: Arrange, e: MouseEvent, h: Hit)
  local c = h.clip
  if e.double then
    if h.fine and c.kind == "audio" and h.y - h.row.y < 1 then
      return A.warp_add(c.id, h.beat)
    end
    return A.open_clip(c.id)
  end
  if h.part == "fade_in" or h.part == "fade_out" then
    return press_fade(self, e, h, c)
  end
  if h.part == "gain" then
    return press_gain(e, h, c)
  end
  local mode = mouse.mode(e)
  -- A plain press chooses at once, unless the clip is among the chosen:
  -- then a drag moves them all, and a click without one chooses it alone.
  local deferred = mode ~= "only" or among_chosen(c.id)
  if not deferred then
    A.select_clip(c.id, grid_at(self, h.tx), "only")
  end
  local free = mouse.has(e, "S")
  local function click()
    if deferred then
      A.select_clip(c.id, grid_at(self, h.tx), mode)
    end
  end
  if h.part == "warp" then
    return press_warp(self, e, h, c, free, click)
  end
  local edge = (h.part == "start" or h.part == "end") and h.part or nil
  local copy, slip = mouse.has(e, "C"), mouse.has(e, "A")
  hold(
    e,
    {
      -- The clip moved: a window lets it go onto another view, which may take it (`on_drop`).
      clip = not edge and c.id or nil,
      arrange = function(v: Arrange)
        local d = held().d
        if not (d and d.moved) then
          return
        end
        local dbeat = cells(v, d.dx)
        if edge then
          return ghost_trimmed(v, h.row, c, edge, dbeat, free)
        end
        ghosts_moved(v, c, free and dbeat or util.round(dbeat, paw.opt.grid), row_index(v, d.y) - h.row.index)
      end,
      drag = function(d: MouseEvent)
        held().d = d
        local dbeat = cells(self, d.dx)
        local at = edge and (edge == "start" and c.start or c.start + c.length) or c.start
        local does = edge and "  trims the " .. edge or copy and "  copies" or "  moves"
        mouse.hint(paw.time.format(math.max(0, at + dbeat)) .. does)
      end,
      up = function(u: MouseEvent)
        if not u.moved then
          return click()
        end
        if edge then
          A.trim_clips(c.id, edge, cells(self, u.dx), free, slip)
        else
          A.drag_clips(c.id, cells(self, u.dx), row_index(self, u.y) - h.row.index, copy, free)
        end
      end,
    }
  )
end

-- The empty timeline ------------------------------------------------------------------

--- A press where there is no clip: a click puts the cursor there and lets go
--- of the chosen clips, a drag selects that stretch of time on the tracks
--- it crosses, a double click makes a clip of a bar.
local function press_empty(self: Arrange, e: MouseEvent, h: Hit)
  local track = h.row.id
  if e.double then
    A.add_clip(track, h.beat)
    return
  end
  A.select(track, grid_at(self, h.tx))
  local row0, x0 = h.row.index, h.fine and h.tx or math.floor(h.tx)
  hold(
    e,
    {
      drag = function(d: MouseEvent)
        if not d.moved then
          return
        end
        local from, to = stretch(self, x0, d.x - self.geometry.hw, d.fine)
        A.select_range(row0, from, row_index(self, d.y), to)
      end,
    }
  )
end

--- A drag with the right button: a box that chooses the clips it touches
--- (Shift adds, Ctrl turns over). Without moving it is a right click: the
--- menu of what is under it.
local function press_right(self: Arrange, e: MouseEvent, h: Hit)
  local row0, x0, y0 = h.row and h.row.index, h.fine and h.tx or math.floor(h.tx), e.y
  local where = screen_at(e)
  hold(
    e,
    {
      arrange = function(v: Arrange, buf: Buf)
        local d = held().d
        if d and d.moved and row0 then
          local hw = v.geometry.hw
          box(buf, math.max(hw, math.floor(x0 + hw)), math.floor(y0), math.max(hw, math.floor(d.x)), math.floor(d.y))
        end
      end,
      drag = function(d: MouseEvent) held().d = d end,
      up = function(u: MouseEvent)
        if u.moved and row0 then
          local from, to = stretch(self, x0, u.x - self.geometry.hw, u.fine)
          local mode = mouse.has(u, "S") and "add" or mouse.has(u, "C") and "toggle" or nil
          A.select_clips_box(row0, from, row_index(self, u.y), to, mode)
          return
        end
        menu_at(self, h, where)
      end,
    }
  )
end

-- Headers ------------------------------------------------------------------------------

--- Whether a press or the pointer at line `y` is on the bottom edge of a
--- header's `row`: a window's pointer within a third of a line of it. A
--- terminal's cell is too big for an edge: Alt and a press on the header
--- stands for it.
local function on_edge(row: Row, y: number, fine: boolean, e?: MouseEvent): boolean
  if fine then
    return y >= row.y + row.h - 0.3
  end
  return e ~= nil and mouse.has(e, "A")
end

--- The bottom edge of a header dragged: the track taller or shorter, in
--- whole lines; a double click gives it the height of the others.
local function press_height(self: Arrange, e: MouseEvent, row: Row)
  local id, th = row.id, self.geometry.th
  if e.double then
    A.set_track_height(id, 1)
    return
  end
  local function lines(d: MouseEvent): integer
    return math.floor(util.clamp(math.floor(row.h + d.dy + 0.5), 1, 24))
  end
  hold(
    e,
    {
      arrange = function(_: Arrange, buf: Buf)
        local d = held().d
        if d then
          buf:fill(0, row.y + lines(d) - 1, buf.width, 1, nil, "MouseGhost")
        end
      end,
      drag = function(d: MouseEvent) held().d = d; mouse.hint(string.format("%d lines", lines(d)), "resize_v") end,
      up = function(u: MouseEvent)
        if u.moved then
          A.set_track_height(id, lines(u) / th)
        end
      end,
    }
  )
end

--- A value of a track dragged sideways from where it was (`get()`): `per`
--- a column, `fine` a column with Shift; the track holds `target`
--- (paw.frontend.act.hold) until the button is let go.
local function drag_value(
  e: MouseEvent,
  track: integer,
  target: string,
  get: function(): number,
  set: function(v: number),
  per: number,
  fine: number
)
  local start = get()
  A.hold(track, target, 0, "", true)
  local function release()
    A.hold(track, target, 0, "", false)
  end
  hold(
    e,
    {
      drag = function(d: MouseEvent) local step = mouse.has(d, "S") and fine or per; set(start + d.dx * step) end,
      up = release,
      cancel = release,
    }
  )
end

--- A press on the first row of a header: on one of its M, S, R and I
--- buttons (a press on one swept across the others sets them all alike),
--- or on the fold mark of a group. True when it was on one.
local function press_chips(
  self: Arrange, e: MouseEvent, row: Row, t: types.Track, cx: integer, column_width: integer
): boolean
  local id = row.id
  -- The chips are where the view has them (`view.flags`, in its columns).
  for field, x in pairs(self.flags) do
    if cx + column_width == x then
      if field == "monitor" then
        A.toggle(id, field)
        return true
      end
      local on = not (t as {string: boolean})[field]
      A.set_flag(id, field, on)
      hold(e, {drag = function(d: MouseEvent) A.sweep_flag(row.index, row_index(self, d.y), field, on) end})
      return true
    end
  end
  -- Without the column's `fold`, the group's mark is before its name.
  if paw.groups.is_group(id) and not paw.trackcolumn.shows("fold") and cx == 2 then
    A.fold(id)
    return true
  end
  return false
end

--- A press on the second row of a header: the input's button, the
--- volume, which a click puts the clip light out on, and the meter, which
--- a drag moves the volume along (a double click puts it back). True
--- when it was on one.
local function press_volume(
  e: MouseEvent, row: Row, t: types.Track, cx: integer, hw: integer, name_at: integer
): boolean
  local id = row.id
  if hw >= 16 and cx >= 1 and cx < 3 then
    paw.ui.menu(require("paw.window_menus").input(id), screen_at(e, 1))
    return true
  end
  if cx >= hw - 1 - #paw.draw.db_text(t.volume) then
    paw.draw.clear_peak(id)
    api.ui_redraw()
    return true
  end
  if cx < name_at then
    return false
  end
  if e.double then
    A.set_volume(id, 0)
    return true
  end
  A.select(id)
  drag_value(
    e,
    id,
    "volume",
    function(): number return api.track_get(id).volume end,
    function(v: number) A.set_volume(id, v) end,
    1,
    0.1
  )
  return true
end

--- A press on the pan of a header's third row: dragged sideways, a
--- double click puts it back.
local function press_pan(e: MouseEvent, id: integer)
  if e.double then
    A.set_pan(id, 0)
    return
  end
  A.select(id)
  drag_value(
    e,
    id,
    "pan",
    function(): number return api.track_get(id).pan or 0 end,
    function(v: number) A.set_pan(id, v) end,
    0.05,
    0.01
  )
end

--- A press on a header elsewhere: it selects the track, renames it on a
--- double click, and drags it to another place.
local function press_track(self: Arrange, e: MouseEvent, row: Row)
  local id = row.id
  if e.double then
    A.track_command(id, "track.rename")
    return
  end
  A.select(id)
  hold(
    e,
    {
      arrange = function(v: Arrange, buf: Buf)
        local d = held().d
        if not (d and math.abs(d.dy) >= 0.5) then
          return
        end
        local target = row_of(v, row_index(v, d.y))
        if target then
          buf:fill(0, target.y, v.geometry.hw - 1, 1, nil, "MouseGhost")
        end
      end,
      drag = function(d: MouseEvent) held().d = d end,
      up = function(u: MouseEvent)
        local to = row_index(self, u.y)
        if u.moved and to ~= row.index then
          A.move_track(id, to)
        end
      end,
    }
  )
end

--- A press on a track's header: the track column at its left, its bottom
--- edge, its chips, its volume and its pan, or the rest of it.
local function press_header(self: Arrange, e: MouseEvent, h: Hit)
  local row, id = h.row, h.row.id
  local t = api.track_get(id)
  -- The track column at the left (paw/trackcolumn.tl), then the header,
  -- whose controls are placed from its own left edge.
  local column = self.geometry.layout.column
  local cx, cy = math.floor(e.x), math.floor(e.y)
  if cx < column.width and row.kind == "track" then
    A.select(id)
    paw.trackcolumn.click(column, cx, id, {row = row.index, line = cy - row.y, kind = row.kind})
    api.ui_redraw()
    return
  end
  cx = cx - column.width
  local hw = self.geometry.hw - 1 - column.width
  local name_at = hw < 16 and 2 or 4
  if on_edge(row, e.y, h.fine, e) then
    return press_height(self, e, row)
  end
  if cy == row.y and press_chips(self, e, row, t, cx, column.width) then
    return
  end
  if row.h >= 2 and cy == row.y + 1 and press_volume(e, row, t, cx, hw, name_at) then
    return
  end
  if row.h >= 3 and cy == row.y + 2 and cx >= name_at and cx < name_at + 4 then
    return press_pan(e, id)
  end
  press_track(self, e, row)
end

-- Lanes under the ruler and under the tracks -----------------------------------------------

--- A height in a row of `h` lines from line `top`, as a fraction (0 at the
--- bottom), for line `y`: a terminal's at the middle of the line, a
--- window's where it is, and past the row its ends.
local function fraction(y: number, top: number, h: number, fine: boolean): number
  return util.clamp(1 - (y - top + (fine and 0 or 0.5)) / h, 0, 1)
end

--- A point of a lane as the pencil sees it: `{ beat, fraction }`.
local type LanePoint = FrontendModule.Point

--- What the pencil edits over a lane: `points()`, and `add(beat,
--- fraction)`, `draw(points)`, `move(index, beat, fraction)`,
--- `remove(index)`, `ramp(index)` (when the lane has ramps), and
--- `say(beat, fraction)`, what a point there is.
local record LaneEdit
  points: function(): {LanePoint}
  add: function(beat: number, f: number)
  draw: function(stroke: {LanePoint})
  move: function(i: integer, beat: number, f: number)
  remove: function(i: integer)
  ramp: function(i: integer)
  say: function(beat: number, f: number): string
end

--- The point of a lane under a press, if any.
local function point_under(
  self: Arrange, e: MouseEvent, h: Hit, top: number, rows: number, points: {LanePoint}
): integer
  local index: integer
  for i, p in ipairs(points) do
    local near: boolean
    if h.fine then
      local x, y = self:x(p[1]), top + (1 - p[2]) * rows
      near = math.abs(x - h.tx) <= 0.7 and math.abs(y - e.y) <= 0.6
    else
      local line = p[2] >= 0.5 and top or top + rows - 1
      near = self:col(p[1]) == h.tx and (not index or line == e.y)
    end
    if near then
      index = i
    end
  end
  return index
end

--- The pencil over a lane: a click puts a point, a drag draws, a press on a
--- point drags it (its height by an eighth a line, Shift finer) and a right
--- click takes it away. `o` names what the lane is.
local function press_lane(self: Arrange, e: MouseEvent, h: Hit, top: number, rows: number, o: LaneEdit)
  local tx, fine = h.tx, h.fine
  local points = o.points()
  local index = point_under(self, e, h, top, rows, points)
  if e.button == "right" then
    if index then
      return o.remove(index)
    end
    return menu_on_release(self, e, h)
  end
  if index then
    if e.double and o.ramp then
      return o.ramp(index)
    end
    local p = points[index]
    local function height(d: MouseEvent): number
      return util.clamp(p[2] - d.dy * (fine and 1 / rows or (mouse.has(d, "S") and 1 / 32 or 1 / 8)), 0, 1)
    end
    return hold(
      e,
      {
        drag = function(d: MouseEvent) mouse.hint(o.say(p[1] + cells(self, d.dx), height(d))) end,
        up = function(u: MouseEvent)
          if not u.moved then
            return
          end
          o.move(index, p[1] + cells(self, u.dx), height(u))
        end,
      }
    )
  end
  local stroke: {LanePoint} = {{fine and self:beat(tx) or grid_at(self, tx), fraction(e.y, top, rows, fine)}}
  hold(
    e,
    {
      drag = function(d: MouseEvent)
        stroke[#stroke + 1] = {self:beat(d.x - self.geometry.hw), fraction(d.y, top, rows, d.fine)}
        mouse.hint(o.say(stroke[#stroke][1], stroke[#stroke][2]))
      end,
      up = function(u: MouseEvent)
        if u.moved then
          return o.draw(stroke)
        end
        o.add(stroke[1][1], stroke[1][2])
      end,
    }
  )
end

--- An automation lane shown as a row, as the pencil edits it.
local function automation(row: Row): LaneEdit
  local lane = row.lane.id
  return {
    points = function(): {LanePoint}
      local lo, hi = paw.frontend.lane_span(api.lane_get(lane))
      local out: {LanePoint} = {}
      for i, p in ipairs(api.lane_points(lane)) do
        out[i] = {p[1], hi ~= lo and util.clamp((p[2] - lo) / (hi - lo), 0, 1) or 0.5}
      end
      return out
    end,
    add = function(beat: number, f: number) A.add_point(lane, beat, f) end,
    draw = function(stroke: {LanePoint}) A.draw_lane(lane, stroke) end,
    move = function(i: integer, beat: number, f: number) A.move_point(lane, i, beat, f) end,
    remove = function(i: integer) A.remove_point(lane, i) end,
    say = function(beat: number, f: number): string
      local l = api.lane_get(lane)
      local lo, hi = paw.frontend.lane_span(l)
      return paw.time.format(math.max(0, beat)) .. "  " .. paw.lanes.format(l, lo + f * (hi - lo))
    end,
  }
end

-- The lane's points are of the window's time, as it draws them: inside a
-- subproject, its own tempo or the song's from its start.
local function tempo_beat(i: integer): number
  return paw.tempolane.points()[i].beat
end
local tempo: LaneEdit = {
  points = function(): {LanePoint}
    local out: {LanePoint} = {}
    for i, p in ipairs(paw.tempolane.points()) do
      out[i] = {p.beat, paw.tempolane.fraction(p.bpm)}
    end
    return out
  end,
  add = function(beat: number, f: number) A.tempo_point_add(beat, f) end,
  draw = function(stroke: {LanePoint}) A.tempo_draw(stroke) end,
  move = function(i: integer, beat: number, f: number) A.tempo_point_move(tempo_beat(i), beat, f) end,
  remove = function(i: integer) A.tempo_point_remove(tempo_beat(i)) end,
  ramp = function(i: integer) A.tempo_point_ramp(tempo_beat(i)) end,
  say = function(beat: number, f: number): string
    return paw.time.format(math.max(0, beat)) .. "  " .. paw.tempolane.bpm(f) .. " bpm"
  end,
}

-- The ruler and the band of markers ----------------------------------------------------

--- A press on a tempo or signature flag: drag it, double click to type a
--- value, right click for its menu.
local function press_flag(self: Arrange, e: MouseEvent, mark: TempoModule.Mark)
  if e.button == "right" then
    local where = screen_at(e)
    return hold(e, {up = function() paw.ui.menu(menus.tempo_mark(mark.kind, mark.beat), where) end})
  end
  if e.double then
    return A.tempo_mark("edit", mark.kind, mark.beat)
  end
  hold(
    e,
    {
      drag = function(d: MouseEvent) mouse.hint(paw.time.format(math.max(0, mark.beat + cells(self, d.dx)))) end,
      up = function(u: MouseEvent)
        if u.moved then
          A.tempo_mark("move", mark.kind, mark.beat, mark.beat + cells(self, u.dx))
        end
      end,
    }
  )
end

--- An edge of the loop or the punch range on the ruler: the column of the
--- mark in the cell before it, and what a drag of it sets.
local record Edge
  x: integer
  set: function(beat: number)
end

--- The edges of the loop and of the punch range that the ruler shows.
local function ruler_edges(self: Arrange, free: boolean): {Edge}
  local t = api.transport_get()
  local edges: {Edge} = {}
  if t.loop_enabled and t.loop_end > t.loop_start then
    edges[#edges + 1] = {x = self:col(t.loop_start) - 1, set = function(b: number) A.set_loop_edge("start", b) end}
    edges[#edges + 1] = {x = self:col(t.loop_end) - 1, set = function(b: number) A.set_loop_edge("end", b) end}
  end
  if t.punch_enabled and t.punch_end > t.punch_start then
    edges[#edges + 1] = {
      x = self:col(t.punch_start) - 1, set = function(b: number) A.set_punch_edge("start", b, free) end
    }
    edges[#edges + 1] = {x = self:col(t.punch_end) - 1, set = function(b: number) A.set_punch_edge("end", b, free) end}
  end
  return edges
end

--- A press on the ruler: on a tempo or signature flag, `press_flag`; on an
--- edge of the loop or the punch range, drag it; elsewhere a click puts
--- the cursor and the playhead there, a drag loops what it crosses, a
--- double click turns the loop on or off.
local function press_ruler(self: Arrange, e: MouseEvent, h: Hit)
  local tx = h.tx
  for _, m in ipairs(ruler_marks(self)) do
    if tx >= m.x0 and tx < m.x1 then
      return press_flag(self, e, m.mark)
    end
  end
  if e.button ~= "left" then
    return
  end
  for _, edge in ipairs(ruler_edges(self, mouse.has(e, "S"))) do
    if math.floor(tx) == edge.x then
      -- The mark sits in the cell before the edge, which is its right
      -- side: a terminal's cell stands for that side, a window's pointer
      -- is where it is.
      return hold(
        e,
        {
          drag = function(d: MouseEvent) edge.set(self:beat(d.x - self.geometry.hw + (d.fine and 0 or 1))) end,
        }
      )
    end
  end
  local double = e.double
  local x0 = h.fine and tx or math.floor(tx)
  hold(
    e,
    {
      drag = function(d: MouseEvent)
        if not d.moved then
          return
        end
        A.set_loop(stretch(self, x0, d.x - self.geometry.hw, d.fine))
      end,
      up = function(u: MouseEvent)
        if u.moved then
          return
        end
        if double then
          paw.transport.loop_enabled = not api.transport_get().loop_enabled
        else
          A.ruler_click(grid_at(self, x0))
        end
      end,
    }
  )
end

--- A press in the band of markers: a click goes to one, a drag moves it, a
--- double click renames it, a right click opens its menu.
local function press_markers(self: Arrange, e: MouseEvent, h: Hit)
  local m = marker_at(self, h.tx, h.lane_row)
  if not m then
    if e.button == "left" then
      A.ruler_click(grid_at(self, h.tx))
    end
    return
  end
  local where = screen_at(e)
  if e.button == "right" then
    return hold(e, {up = function() paw.ui.menu(menus.marker(m as menus.MenuTable), where) end})
  end
  if e.double then
    paw.commands.exec("marker.rename id=" .. m.id)
    return
  end
  -- The marker keeps a beat of the song; the mouse moves in the window's
  -- time (a subproject's own), so the drag goes through it both ways.
  local start = paw.time.local_beat(m.beat)
  local function moved_to(d: MouseEvent): number
    local to = start + cells(self, d.dx)
    return mouse.has(d, "S") and to or paw.cursor.snap(to)
  end
  hold(
    e,
    {
      drag = function(d: MouseEvent) mouse.hint(paw.time.format(moved_to(d))) end,
      up = function(u: MouseEvent)
        if not u.moved then
          paw.commands.exec("marker.goto id=" .. m.id)
          return
        end
        local to = math.max(0, paw.time.song_beat(moved_to(u)))
        paw.commands.exec(string.format("marker.set id=%d beat=%s", m.id, tostring(to)))
      end,
    }
  )
end

-- Take lanes ---------------------------------------------------------------------------

--- A drag across a take lane, as the window's: the cells from where the
--- button went down to where it is now are marked, and on release that
--- take plays over them (`paw.frontend.act.comp`; a cell shorter than a
--- grid step is a click, which chooses the take for the piece under it).
local function press_take(self: Arrange, e: MouseEvent, h: Hit)
  local row = h.row
  if e.button == "right" then
    return menu_on_release(self, e, h)
  end
  if not h.timeline then
    -- The label makes the take play wherever the track has it.
    local last = 0.0
    for _, clip in ipairs(api.clip_list(row.id)) do
      last = math.max(last, clip.start + clip.length)
    end
    paw.takes.comp(row.id, row.take, 0, last)
    return paw.cursor.set_track(row.id)
  end
  local x = h.fine and e.x or math.floor(e.x)
  self.comp = {id = row.id, take = row.take, x0 = x, x1 = x}
  hold(
    e,
    {
      drag = function(d: MouseEvent)
        if self.comp then
          self.comp.x1 = math.max(self.geometry.hw, d.x)
        end
      end,
      up = function(u: MouseEvent)
        local comp, g = self.comp, self.geometry
        self.comp = nil
        if not comp then
          return
        end
        comp.x1 = math.max(g.hw, u.x)
        local from, to = stretch(self, comp.x0 - g.hw, comp.x1 - g.hw, u.fine)
        A.comp(comp.id, comp.take, math.min(from, to), math.max(from, to), mouse.has(u, "S"))
      end,
      cancel = function() self.comp = nil end,
    }
  )
end

-- The wheel and the pointer going over -----------------------------------------------------

local function wheel(self: Arrange, e: MouseEvent, h: Hit)
  local step, sideways = mouse.wheel(e)
  if mouse.has(e, "C") and not sideways and h.timeline then
    -- Zoom in time, keeping the beat under the pointer where it is.
    local zoom = util.clamp(paw.opt.zoom * (step < 0 and math.sqrt(2) or 1 / math.sqrt(2)), 0.125, 64)
    local at = self:beat(h.tx)
    paw.opt.zoom = zoom
    self.scroll = math.max(0, at - h.tx / zoom)
  elseif (mouse.has(e, "C") or mouse.has(e, "A")) and not sideways then
    -- The vertical zoom (paw/vzoom.tl): Alt anywhere, Ctrl over the headers.
    return paw.vzoom.step(-step, {view = "arrange"})
  elseif sideways or mouse.has(e, "S") then
    self.scroll = math.max(0, self.scroll + step * paw.time.bar(self.scroll))
  else
    self.top = math.max(1, self.top + step)
  end
  api.ui_redraw()
end

local hints: {string: string} = {
  ruler = "ruler: click moves the playhead · drag loops · drag the loop's edges · double click turns the loop on or off",
  flag = "tempo flag: drag to move · double click to type a value · right click to remove",
  markers = "marker: click goes there · drag to move · double click renames · right click for more",
  tempo = "tempo lane: click adds a change · hold and draw a curve · drag a change to move it · double click makes it ramp or hold · right click one removes it",
  lane = "lane: click adds a point · hold to draw · drag a point · right click removes it",
  take = "take lane: drag across to play this take there · click a piece to choose it · right click to hide",
  empty = "click puts the cursor · drag selects time · right drag chooses clips · double click makes a clip · right click for more",
  edge = "drag the edge to trim (Alt slips, Alt+Shift stretches)",
  clip = "click chooses (Ctrl adds, Shift takes in) · drag moves (Ctrl copies) · double click opens · right click for more",
  warp = "warp marker: drag to move · right click to remove",
  fade = "fade: drag to make it longer or shorter",
  gain = "clip gain: drag up or down, with Shift finely",
  header = "click selects · drag up or down to reorder · M S R I switch · drag the volume or pan sideways · right click for more",
}

--- What the status line says of a clip's part under the pointer.
local function clip_hint(h: Hit): string
  local part = h.part
  local said: string
  if part == "warp" then
    said = hints.warp
  elseif part == "start" or part == "end" then
    said = hints.edge
  elseif part == "fade_in" or part == "fade_out" then
    said = hints.fade
  elseif part == "gain" then
    said = hints.gain .. " · " .. util.round(h.clip.gain or 0, 0.1) .. " dB"
  else
    said = hints.clip
  end
  return paw.time.format(h.beat) .. "  " .. h.clip.name .. " · " .. said
end

local function hover(self: Arrange, h: Hit)
  local text: string
  if h.area == "ruler" and h.timeline then
    text = hints.ruler
    for _, m in ipairs(ruler_marks(self)) do
      if h.tx >= m.x0 and h.tx < m.x1 then
        text = hints.flag
      end
    end
  elseif h.area == "markers" and h.timeline then
    local m = marker_at(self, h.tx, h.lane_row)
    text = m and (paw.markers.label(m) .. " · " .. hints.markers) or nil
  elseif h.area == "band" and h.timeline then
    text = h.band and h.band.hint or nil
  elseif h.area == "tempo" and h.timeline then
    text = paw.time.format(h.beat) .. "  " .. string.format("%g bpm", paw.tempo.at(h.beat)) .. " · " .. hints.tempo
  elseif h.area == "lane" and h.timeline then
    text = paw.time.format(h.beat) .. " · " .. hints.lane
  elseif h.area == "take" then
    text = hints.take
  elseif h.area == "track" and h.timeline then
    text = h.clip and clip_hint(h) or paw.time.format(h.beat) .. " · " .. hints.empty
  elseif h.area == "track" and h.header then
    if on_edge(h.row, h.y, h.fine) then
      return mouse.hint("track height: drag the bottom edge · double click for the others' height", "resize_v")
    end
    text = api.track_get(h.row.id).name .. " · " .. hints.header
  end
  local edge = h.area == "track" and h.clip and (h.part == "start" or h.part == "end")
  mouse.hint(text, edge and "resize_h" or nil)
end

--- A press on a lane's row: its header puts the cursor on it (a right
--- click opens its menu), its timeline is the pencil's.
local function press_lane_row(self: Arrange, e: MouseEvent, h: Hit)
  paw.cursor.set_track(h.row.id, h.row.lane.id)
  if h.timeline then
    return press_lane(self, e, h, h.row.y, h.row.h, automation(h.row))
  end
  if e.button == "right" then
    return menu_on_release(self, e, h)
  end
end

--- A press on a track's row: on its header or its timeline, with the left
--- button or the right.
local function press_track_row(self: Arrange, e: MouseEvent, h: Hit)
  if e.button == "right" then
    if h.header then
      return menu_on_release(self, e, h)
    end
    return press_right(self, e, h)
  end
  if e.button ~= "left" then
    return
  end
  if h.header then
    return press_header(self, e, h)
  end
  if not h.timeline then
    return
  end
  if h.clip then
    return press_clip(self, e, h)
  end
  press_empty(self, e, h)
end

function view:on_mouse(e: MouseEvent): boolean
  if not self.geometry then
    return
  end
  local h = hit(self, e.x, e.y, e.fine)
  if e.kind == "move" then
    hover(self, h)
    return
  end
  if mouse.wheel(e) then
    wheel(self, e, h)
    return
  end
  if e.kind ~= "down" then
    return
  end
  if e.button == "middle" then
    -- The middle button held pans.
    local scroll, top = self.scroll, self.top
    hold(
      e,
      {
        drag = function(d: MouseEvent)
          self.scroll = math.max(0, scroll - cells(self, d.dx))
          self.top = math.max(1, top - math.floor(d.dy + 0.5))
        end,
      }
    )
    return
  end
  local area = h.area
  if area == "ruler" and h.timeline then
    press_ruler(self, e, h)
  elseif area == "markers" and h.timeline then
    press_markers(self, e, h)
  elseif area == "band" then
    -- An entry of an extension's band does what it stands for.
    if h.band and h.band.active and e.button == "left" then
      A.band(h.band.band, h.band.index)
    end
  elseif area == "tempo" and h.timeline then
    press_lane(self, e, h, h.y0, 2, tempo)
  elseif area == "take" then
    press_take(self, e, h)
  elseif area == "lane" and (h.header or h.timeline) then
    press_lane_row(self, e, h)
  elseif area == "tempo" and e.button == "right" then
    menu_on_release(self, e, h)
  elseif area == "below" and h.header and e.button == "left" then
    -- Under the last track: the kinds of track to make one of.
    paw.ui.menu(require("paw.window_menus").add_track(), screen_at(e, 1))
  elseif area == "track" then
    press_track_row(self, e, h)
  end
end

-- The view's one hit region: every press, move and wheel over it, from
-- either frontend, comes here.
view.gestures = {
  arrange = function(self: contracts.View, e: MouseEvent): boolean self:on_mouse(e) end,
}

-- What a gesture under way draws over the view.
local render = view.render
function view:render(buf: Buf, ctx: contracts.RenderContext)
  render(self, buf, ctx)
  local g = held()
  if g and g.arrange and self.geometry then
    g.arrange(self, buf)
  end
end
