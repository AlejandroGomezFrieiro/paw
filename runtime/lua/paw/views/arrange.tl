-- The arrange view: part headers on the left, clips on a timeline on the right.
--
-- The view places everything (`view:layout`), maps beats to columns through
-- the window's time axis with its time folds (`view.axis`, paw/axis.tl) and draws
-- each part of a frame in its own function: the ruler, the rows of lanes
-- and takes, the parts, the selection, the time folds, the master, the
-- layers of extensions and the playhead. What one part's header and
-- clips show is in paw/views/arrange_part.tl, the roles it marks in
-- paw/roles/arrange.tl, and the pointer in paw/views/arrange_mouse.tl.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local kernel = require("paw.events.kernel")
local derived = require("paw.derived")
local axis = require("paw.axis")
local part_draw = require("paw.views.arrange_part")
local heads = require("paw.heads")
local head_pieces = require("paw.heads.pieces")
require("paw.heads.default")
local timegrid = require("paw.timegrid")
local motion = require("paw.motion")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type util_t = require("paw.util")
local type roles = require("paw.roles.arrange")
local type DrawModule = require("paw.draw")
local type FoldsModule = require("paw.folds")
local type RolesModule = require("paw.roles")
local type FrontendModule = require("paw.frontend")
local type PartcolumnModule = require("paw.partcolumn")
local type NestModule = require("paw.nest")
local type RulerModule = require("paw.ruler")
local type Buf = contracts.Buf
local type Hue = DrawModule.Hue
local type Data = util_t.Data
local type TimeSpan = FoldsModule.TimeSpan
local type Axis = axis.Axis
local type BeatLine = roles.BeatLine

local ruler_marks = require("paw.marks")
local draw = paw.draw
local util = paw.util

-- One field of a part: a whole part's table for each part on each
-- frame costs more than the field.
local part_number = api.part_get as function(id: integer, key: string): number
local part_name = api.part_get as function(id: integer, key: string): string

--- A row of the timeline: a part's (`kind` "part"), one of its take
--- lanes ("take", `take` its number), one of its automation lanes shown
--- as a row ("lane", `lane`), the line that closes the parts of a
--- subproject shown under its return row ("end", `id` the return row), or
--- the master's ("master"). `index` is the part's place among the parts
--- drawn (for "end", the last part it closes); `y` and `h` its lines.
local record Row
  kind: string
  id: integer
  index: integer
  y: integer
  h: integer
  take: integer
  lane: types.Lane
end

--- Where everything goes on the view (`view:layout`): the headers'
--- columns with the rule (`hw`), the timeline's (`tw`), the part
--- column, rows a part (`th`), the ruler's lines (`ruler_rows`: the
--- lines of its rows, each in its place (`places`, paw/ruler.tl), then
--- the bands' from `band_y`), the time the ruler was placed in (`time`),
--- the rows of the timeline from the first part shown, the parts, the
--- line after the last row (`used`) and the master's row.
local record Layout
  hw: integer
  tw: integer
  column: PartcolumnModule.Layout
  th: integer
  ruler_rows: integer
  places: {RulerModule.Place}
  time: contracts.RulerContext
  rows: {Row}
  parts: {integer}
  used: integer
  master: Row
  bands: FrontendModule.Bands
  band_y: integer
end

--- What the last draw gave the pointer and the keys: its layout, and
--- where the ruler placed each of its marks (paw/ruler.tl).
local record Geometry is contracts.ArrangeGeometry
  layout: Layout
  ruler: RulerModule.Composition
end

--- A take lane dragged across with the pointer: from column `x0` to `x1`
--- of the view.
local record Comp
  id: integer
  take: integer
  x0: number
  x1: number
end

--- The take being made on the armed parts: from `start` to the
--- playhead `at`, no further than `to` when it is punched in.
local record Recording
  start: number
  at: number
  to: number
end

--- A bar or beat line of the timeline (`paw.draw.grid_lines`).
local type GridLine = DrawModule.GridLine

--- The stretch `{ from, to }` of columns that a thing takes.
local type Span = {integer, integer}

local type Layer = function(view: contracts.ArrangeView, layer: contracts.ArrangeLayer)

--- The arrange view. Each window of it scrolls on its own: the fields
--- of `window_state` are the window's (paw/ui.tl). The edit cursor
--- (paw/cursor.tl) is one for all of them.
local record Arrange is contracts.ArrangeView
  type Row = Row
  type Layout = Layout
  type Geometry = Geometry
  type Comp = Comp
  --- The first part shown.
  top: integer
  --- What a press on the heads does, where the heads asked for it
  --- (paw/heads.tl), in the view's columns and lines: last drawn.
  head_hits: {heads.Hit}
  --- What the window drew last, and its time axis with its time folds:
  --- where every row, the ruler and the pointer place each beat.
  geometry: Geometry
  axis: Axis
  --- The folds as plain data, for the rows that the terminal keeps.
  fold_ground: {{number}}
  --- The timeline's plane, last drawn: what a gesture marks on.
  plane: RolesModule.Plane
  --- The take lane being dragged across.
  comp: Comp
  --- The take being made, and where it began.
  rec: Recording
  rec_start: number
  --- What the window saw last, to scroll only when it changes: the
  --- cursor's row and lane, the parts that fit, the cursor's beat and
  --- the serial of the last jump.
  seen_index: integer
  seen_fit: integer
  seen_lane: integer
  seen_beat: number
  seen_jump: integer
  meter: function(buf: Buf, x: integer, y: integer, width: integer, peak: number, hold?: number)
  header_width: function(w: integer): integer
  part_height: function(count: integer, room: integer): integer
  row_height: function(id: integer, th: number): integer
  level_glyph: function(level: number): string
  clip_props: function(
    clip: types.Clip,
    part: types.Part,
    hue: Hue,
    kind: string,
    ax: Axis,
    at: number,
    chosen?: boolean,
    from?: number,
    to?: number,
    colour?: string
  ): roles.ClipProps
  layout: function(self: Arrange, w: integer, h: integer): Layout
  rows_with_lanes: function(
    self: Arrange, parts: {integer}, th: integer, ruler_rows: integer, room: integer, cursor_index: integer
  ): {Row}, integer
  draw_lane_row: function(self: Arrange, headers: Buf, timeline: Buf, row: Row, lines: {GridLine})
  draw_column: function(self: Arrange, column: Buf, L: Layout, cursor_part: integer, cursor_lane: integer)
  draw_tempo_row: function(self: Arrange, headers: Buf, timeline: Buf, y: integer, lines: {GridLine})
  draw_take_row: function(self: Arrange, headers: Buf, timeline: Buf, row: Row, lines: {GridLine}): {Span}, {Span}
  current_axis: function(self: Arrange): Axis
end

-- The view is the module.
local view = Arrange
view.scroll, view.top, view.head_hits = 0, 1, {}
-- What extensions draw on the timeline, by name, in name order, once the
-- ruler and the parts are drawn and before the playhead:
--   paw.ui.views:get("arrange").layers.marks = function(view, layer) ... end
-- See `contracts.ArrangeLayer` for what `layer` holds.
view.layers = {}
-- Parts need rows: two fifths of a column's height, and a third of the
-- room where three or more windows share it (paw/ui.tl).
view.share = {column = 2 / 5, least = 1 / 3}
view.window_state = {
  "scroll",
  "top",
  "head_hits",
  "seen_index",
  "seen_fit",
  "seen_lane",
  "seen_beat",
  "seen_jump",
  "geometry",
  "comp",
  "axis",
  "fold_ground",
}
view.window_fresh = {"geometry", "head_hits"}
-- Each seat (paw/seats.tl) has its own state of the window, as each
-- window has.
paw.seats.fields(
  "arrange", view as {string: Data}, view.window_state, {scroll = 0, top = 1, head_hits = {}} as {string: Data}
)

-- An empty list, to walk where there is none.
local NONE: {Span} = {}

-- Another project is shown from its start, as the cursor is (paw/cursor.tl).
paw.on(kernel.project_loaded, function() view.scroll, view.top, view.seen_beat = 0, 1, nil end)

view.meter = draw.meter
view.level_glyph = head_pieces.level_glyph
view.clip_props = part_draw.clip_props

-- The headers' width with "auto" on the narrowest screens.
local NARROW_HEADER = 12

--- Columns for the part headers on a screen `w` wide, the rule on their
--- right included: `paw.opt.header_width`, or by the width with "auto".
function view.header_width(w: integer): integer
  local want = math.tointeger(tonumber(paw.opt.header_width))
  if not want then
    want = w >= 120 and 26 or w >= 100 and 22 or w >= 80 and 18 or NARROW_HEADER
  end
  return math.max(4, math.min(want, w - 4))
end

--- Rows a part takes when `count` parts share `room` rows: the
--- window's vertical zoom (paw/vzoom.tl), else `paw.opt.part_height`,
--- or with "auto" the most that let every part fit, from 1 to 3. A song
--- with more parts than fit at 1 row scrolls.
function view.part_height(count: integer, room: integer): integer
  local want = paw.vzoom.part_rows() or tonumber(paw.opt.part_height)
  if want then
    return math.max(1, math.floor(want))
  end
  if count < 1 then
    return 3
  end
  return math.floor(util.clamp(math.floor(room / count), 1, 3))
end

--- Whether the user set the height of the parts: the window's vertical
--- zoom, or `paw.opt.part_height`.
local function user_height(): boolean
  return (paw.vzoom.part_rows() or tonumber(paw.opt.part_height)) ~= nil
end

--- The lines a part's row takes, `th` the parts' height. The height that
--- the user set comes first: its own rows in the window's vertical zoom
--- (paw/vzoom.tl), its own share of `th` (`height`, which a drag of its
--- header's bottom edge sets), or the height of all parts. Else one line
--- on a crowded screen (`th` 1), else the larger of `th` and the rows
--- that its head wishes for (paw/heads.tl), at most 6.
function view.row_height(id: integer, th: number): integer
  local own = paw.vzoom.rows_of(id)
  if own then
    return own
  end
  local share = part_number(id, "height") or 1
  if share ~= 1 or th <= 1 or user_height() then
    return math.max(1, math.floor(th * share + 0.5))
  end
  local wish = heads.wish(id)
  return math.floor(math.max(th, math.min(6, wish or 0)))
end

--- The parts of `parts` that end the parts of a subproject shown
--- under its return row (paw/nest.tl), each with that return row: a
--- closing line goes under each.
local function closing_lines(parts: {integer}): {integer: integer}
  local out: {integer: integer} = {}
  for i, id in ipairs(parts) do
    local under = paw.nest.shown_under(id)
    local next_id = parts[i + 1]
    if under and not (next_id and paw.nest.shown_under(next_id) == under) then
      out[id] = under
    end
  end
  return out
end

--- The rows from `self.top` when some parts show their take lanes or their
--- automation lanes, or the parts of a subproject under its return row:
--- each part, then a row `{ kind = "take", id, take, index, y, h }` for
--- each of its take lanes, then a row `{ kind = "lane", id, lane, index,
--- y, h }` for each of its automation lanes (`h` 2 for each lane, or as
--- the window's vertical zoom says), then the closing line `{ kind =
--- "end", id, index, y, h = 1 }` under the last part of a subproject.
--- Scrolls so that the cursor's row is in view. Returns the rows and the
--- line after the last.
function view:rows_with_lanes(
  parts: {integer}, th: integer, ruler_rows: integer, room: integer, cursor_index: integer
): {Row}, integer
  local bottom = ruler_rows + room
  local lane_rows = paw.vzoom.lane_rows()
  local closing = closing_lines(parts)
  -- The rows from part `top` down, the line after them, and whether
  -- every row of the parts placed fits.
  local function place(top: integer): {Row}, integer, boolean
    local out: {Row} = {}
    local y = ruler_rows
    for index = top, #parts do
      local id = parts[index]
      local h = view.row_height(id, th)
      if #out > 0 and y + h > bottom then
        break
      end
      out[#out + 1] = {kind = "part", id = id, index = index, y = y, h = h}
      y = y + h
      for k = 1, paw.takes.lane_count(id) do
        if y + lane_rows > bottom then
          return out, y, false
        end
        out[#out + 1] = {kind = "take", id = id, take = k, index = index, y = y, h = lane_rows}
        y = y + lane_rows
      end
      for _, l in ipairs(paw.lanes.shown(id)) do
        if y + lane_rows > bottom then
          return out, y, false
        end
        out[#out + 1] = {kind = "lane", id = id, lane = l, index = index, y = y, h = lane_rows}
        y = y + lane_rows
      end
      if closing[id] then
        if y + 1 > bottom then
          return out, y, false
        end
        out[#out + 1] = {kind = "end", id = closing[id], index = index, y = y, h = 1}
        y = y + 1
      end
    end
    return out, y, true
  end
  local function shows_cursor(rows: {Row}): boolean
    local lane = paw.cursor.lane_id()
    for _, row in ipairs(rows) do
      if row.index == cursor_index and ((row.kind == "part" and not lane) or (row.lane and row.lane.id == lane)) then
        return true
      end
    end
    return false
  end
  local lane = paw.cursor.lane_id()
  if cursor_index ~= self.seen_index or lane ~= self.seen_lane then
    if cursor_index < self.top then
      self.top = cursor_index
    end
    while self.top < cursor_index and not shows_cursor((place(self.top))) do
      self.top = self.top + 1
    end
  end
  self.seen_index, self.seen_lane, self.seen_fit = cursor_index, lane, nil
  self.top = math.floor(util.clamp(self.top, 1, math.max(1, #parts)))
  -- No room left empty below while parts above are scrolled away.
  while self.top > 1 do
    local rows, _, whole = place(self.top - 1)
    if not whole or rows[#rows].index < #parts or not shows_cursor(rows) then
      break
    end
    self.top = self.top - 1
  end
  local rows, y = place(self.top)
  return rows, y
end

--- Where everything goes on a `w` by `h` view: the header width, the ruler's
--- rows, and the rows of the timeline, each `{ kind = "part", id, index, y,
--- h }` from the first part shown, then the master's. All placement is
--- here, so that rows of other kinds can be added in one place.
function view:layout(w: integer, h: integer): Layout
  local parts = paw.groups.rows()
  local header = view.header_width(w)
  -- The part column (paw/partcolumn.tl) at the left of the headers takes
  -- the columns of the parts that the options set (the numbers) from the
  -- timeline, as Neovim's number column takes them from the text. The
  -- parts that come and go with the project (signs, the tree of groups)
  -- take theirs from the headers, so that the timeline starts in the same
  -- column with and without groups or a scope. The headers give the
  -- columns that they have beyond the narrowest width (`NARROW_HEADER`),
  -- so a name stays readable in a narrow window; there the rest comes from
  -- the timeline. `count` is how far the counts of `j` and `k` go: over
  -- lane rows too, in normal mode, when lanes are open.
  local count = #parts
  if paw.lanes.any_open() and paw.keymap.mode == "n" then
    count = #paw.lanes.lines()
  end
  local column = paw.partcolumn.layout(
    {rows = parts, count = count}, math.max(0, w - header - 8), math.max(0, header - NARROW_HEADER)
  )
  local hw = header + column.width - column.from_header
  -- The heads' width class, which the heads' wishes depend on: the
  -- headers less the part column, the stripe and the rule.
  heads.begin_layout(hw - column.width - 2)
  -- The ruler: the lines of its rows (paw/ruler.tl), then a line for each
  -- band of an extension (`paw.frontend.bands`) that has entries.
  local bands = paw.frontend.band_state()
  -- The time in sight, which the rows need lines for: at the zoom and
  -- the folds of the last frame.
  local time = paw.ruler.time()
  local seen = axis.new(self.scroll, paw.opt.zoom, self.axis and self.axis.spans)
  time.left, time.right = self.scroll, seen:beat_of(math.max(1, w - hw))
  local places, band_y = paw.ruler.places(time)
  local ruler_rows = band_y + bands.rows
  local master_rows = 2
  local room = math.max(1, h - ruler_rows - master_rows)
  -- Take lanes and automation lanes shown as rows (two lines each, or as
  -- the window's vertical zoom says) take their lines first.
  local lane_lines, own = 0, paw.vzoom.any_own()
  local lane_rows = paw.vzoom.lane_rows()
  for _, id in ipairs(parts) do
    lane_lines = lane_lines + lane_rows * (paw.takes.lane_count(id) + #paw.lanes.shown(id))
    own = own or (part_number(id, "height") or 1) ~= 1
  end
  local th = view.part_height(#parts, math.max(1, room - lane_lines))
  -- Squeezed by panels below, a part takes what there is rather than vanish.
  if not user_height() and room < th then
    th = math.max(1, room)
  end
  -- A head that wishes for more rows than the parts' height gives its
  -- row a height of its own.
  if th > 1 and not user_height() then
    for _, id in ipairs(parts) do
      own = own or (heads.wish(id) or 0) > th
    end
  end
  local L: Layout = {
    hw = hw,
    tw = w - hw,
    column = column,
    th = th,
    ruler_rows = ruler_rows,
    places = places,
    time = time,
    parts = parts,
    master = {kind = "master", id = 0, y = h - master_rows, h = master_rows},
    bands = bands,
    band_y = band_y,
  }
  local cursor_index = paw.cursor.row() or 1
  -- Parts of heights of their own are placed one by one, as lanes and
  -- the closing lines of subprojects shown in place are.
  if lane_lines > 0 or own or next(closing_lines(parts)) then
    L.rows, L.used = self:rows_with_lanes(parts, th, ruler_rows, room, cursor_index)
    return L
  end
  local fit = math.max(1, room // th)
  if cursor_index ~= self.seen_index or fit ~= self.seen_fit then
    if cursor_index < self.top then
      self.top = cursor_index
    end
    if cursor_index >= self.top + fit then
      self.top = cursor_index - fit + 1
    end
  end
  self.seen_index, self.seen_fit = cursor_index, fit
  self.top = math.floor(util.clamp(self.top, 1, math.max(1, #parts - fit + 1)))
  local rows: {Row} = {}
  local y = ruler_rows
  for index = self.top, #parts do
    if y + th > ruler_rows + room then
      break
    end
    rows[#rows + 1] = {kind = "part", id = parts[index], index = index, y = y, h = th}
    y = y + th
  end
  L.rows, L.used = rows, y
  return L
end

-- The time axis -------------------------------------------------------------------

-- Time folds (paw/folds.tl). A closed region or range of bars is drawn
-- as one narrow column, so the beats of the timeline are not even: each
-- render makes the window's axis (`self.axis`, paw/axis.tl) with its folds,
-- and every place that turns a beat into a column, or a column into a
-- beat, goes through it. The timeline's plane counts in the beats of that
-- axis (`axis:view`), so a window places the clips on it as the terminal does.

--- The window's axis: the one its last render made, or one at its scroll
--- before the first.
local function axis_of(self: Arrange): Axis
  return self.axis or axis.new(self.scroll, paw.opt.zoom)
end

--- The window's axis at its scroll now: the one its last render made, or,
--- when a key or the pointer has scrolled since, one with the same zoom and
--- time folds at the new scroll. The pointer reads beats and columns on it.
function view:current_axis(): Axis
  local ax = axis_of(self)
  if ax.scroll ~= self.scroll then
    return axis.new(self.scroll, ax.zoom, ax.spans)
  end
  return ax
end

--- The bar and beat lines (`grid_lines`) as the `beats` role takes them:
--- the same on each row, so that the lines run down the timeline.
local function grid_marks(lines: {GridLine}): {BeatLine}
  local out: {BeatLine} = {}
  for i, line in ipairs(lines) do
    out[i] = {line.v, line.bar and true or false}
  end
  return out
end

--- Whether the rows draw the lines of the beats too, not only the bars':
--- from 4 columns a beat.
local function shows_beats(ax: Axis): boolean
  return ax:cells(1) >= 4
end

--- The cursor's cells at `beat`: its first column, how many, and its
--- style. On the grid, the cells of its grid cell, up to the next line.
--- Off the grid, the one column that holds it, in `CursorOff`, so that it
--- never covers two cells of the ruler.
local function cursor_cells(ax: Axis, beat: number): integer, integer, string
  local mode = paw.keymap.mode
  local style = mode == "x" and "CursorVisual" or mode == "i" and "InsertCursor" or "Cursor"
  local t = timegrid.tick(beat)
  if motion.off(t) then
    return ax:x_of(beat), 1, style == "Cursor" and "CursorOff" or style
  end
  local _, to = motion.cell(t)
  local x0, x1 = ax:range(beat, timegrid.beat(to))
  return x0, x1 - x0, style
end

-- Curves ----------------------------------------------------------------------------

--- The height of a curve at half column `i`, from 0 to 1; nil for none.
local type Height = function(i: integer): number

-- What `lane_sample` reads: the lane `lane` on the window's axis `axis`,
-- in half columns, nothing over the columns of `skip` (spans), and the
-- level of a value by `lo` and `hi` (a volume in dB when they are nil).
-- Set before each curve that it samples: a frame draws a curve for each
-- lane with no new function for it.
local record Sampled
  lane: integer
  axis: Axis
  skip: {Span}
  lo: number
  hi: number
end
local sampled: Sampled = {lane = 0}

local function lane_sample(i: integer): number
  local skip = sampled.skip
  if skip then
    local col = i // 2
    for _, span in ipairs(skip) do
      if col >= span[1] and col < span[2] then
        return nil
      end
    end
  end
  local v = api.lane_value_at(sampled.lane, sampled.axis:half_beat(i))
  local lo, hi = sampled.lo, sampled.hi
  if lo == nil then
    return (v + 60) / 66
  end
  return hi ~= lo and util.clamp((v - lo) / (hi - lo), 0, 1) or 0.5
end

-- Set what `lane_sample` reads, and give it.
local function lane_sampler(lane: integer, ax: Axis, skip: {Span}, lo: number, hi: number): Height
  sampled.lane, sampled.axis, sampled.skip, sampled.lo, sampled.hi = lane, ax, skip, lo, hi
  return lane_sample
end

--- A point marked on a curve: its beat, its height, and its glyph (a
--- diamond when nil).
local type CurvePoint = {number, number, string}

--- How a curve is drawn (`curve`): the points marked on it, the style of
--- its cells, the window's axis, which places its beats, and how a window
--- draws it (`color`, `enabled`).
local record CurveStyle
  points: {CurvePoint}
  style: string
  axis: Axis
  color: string
  enabled: boolean
end

--- A curve over `w` columns and `h` rows of `buf` from `x`, `y`, as the
--- `curve` role: `value(i)` is its height at half column `i` (nil for
--- none); the points of `o` are marked on its top row or its bottom by
--- their height.
local function curve(buf: Buf, x: integer, y: integer, w: integer, h: integer, value: Height, o: CurveStyle)
  local values: {number | boolean} = {}
  local marks: {{number, number}} = {}
  for i = 0, 2 * w - 1 do
    values[i + 1] = value and value(i) or false
  end
  local ax = o.axis
  for i, p in ipairs(o.points or {}) do
    marks[i] = {ax:view(p[1]), p[2]}
  end
  local function height(i: integer): number
    local v = values[i + 1]
    return v is number and v or nil
  end
  local props: roles.CurveProps = {
    values = values,
    points = marks,
    from = ax.left,
    per = ax.zoom,
    color = o.color,
    enabled = o.enabled ~= false,
    draw = function(b: Buf)
      if value then
        draw.curve(b, 0, h, height, o.style)
      end
      for _, p in ipairs(o.points or {}) do
        local px = ax:x_of(p[1])
        if px >= 0 and px < w then
          b:text(px, p[2] >= 0.5 and 0 or h - 1, p[3] or "◆", o.style)
        end
      end
    end,
  }
  buf:mark("curve", x, y, w, h, props)
end

-- A part's row of the timeline -------------------------------------------------------

--- Whether two values of plain data (numbers, text, flags, tables of
--- them) are the same.
local function same(a: Data, b: Data): boolean
  if a == b then
    return true
  end
  if not (a is {Data: Data} and b is {Data: Data}) then
    return false
  end
  for k, v in pairs(a) do
    if not same(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

--- What a row of the timeline is drawn from, besides its clips: plain
--- values, the glyphs and the roles it draws with, the bar lines, and
--- the time folds (where each is, and how wide).
local record RowGround
  values: {number | string | boolean}
  glyphs: contracts.Glyphs
  clip_role: contracts.Role<contracts.MarkProps>
  beats_role: contracts.Role<contracts.MarkProps>
  marks: {BeatLine}
  folds: {{number}}
end

local function same_ground(a: RowGround, b: RowGround): boolean
  return a.glyphs == b.glyphs
    and a.clip_role == b.clip_role
    and a.beats_role == b.beats_role
    and same(a.values as Data, b.values as Data)
    and same(a.marks as Data, b.marks as Data)
    and same(a.folds as Data, b.folds as Data)
end

-- The rows of the timeline that the terminal drew last, by their part and
-- place: what each was drawn from, and the columns its clips take. A row
-- drawn from the same things again puts back the cells it drew
-- (`buf:put_kept`) instead of drawing its clips again. Only the rows that
-- are all MIDI clips, not the cursor's, with nothing live, are kept.
local record KeptRow
  ground: RowGround
  clips: {types.Clip}
end
local kept_rows: {string: KeptRow} = {}

--- The part of the screen a buffer draws on (paw/buf.tl).
local record Clipped
  x: integer
  y: integer
  width: integer
  cx: integer
  cy: integer
  cw: integer
  ch: integer
end

local function row_ground(
  self: Arrange,
  buf: Buf,
  row: Row,
  hue: Hue,
  marks: {BeatLine},
  loop: {number, number},
  colour: string,
  scope_from: number,
  scope_to: number
): RowGround
  local b = buf as Clipped
  return {
    values = {
      b.x,
      b.y,
      b.width,
      b.cx,
      b.cy,
      b.cw,
      b.ch,
      row.y,
      row.h,
      self.scroll,
      self.geometry.zoom,
      colour,
      hue.title,
      hue.body,
      hue.title_off,
      hue.body_off,
      paw.opt.ascii,
      loop and loop[1] or false,
      loop and loop[2] or false,
      scope_from or false,
      scope_to or false,
    },
    glyphs = draw.g,
    clip_role = paw.roles.registry:get("clip"),
    beats_role = paw.roles.registry:get("beats"),
    marks = marks,
    folds = self.fold_ground,
  }
end

--- A clip in view on a part's row, or a piece of one cut by a time fold:
--- its columns (`cw`), which piece it is (`k`), where the clip would start
--- were its piece's stretch of the view even (`v`, a place on the plane),
--- and the beats where it is cut (`from`, `to`).
local record Shown
  clip: types.Clip
  cw: integer
  k: integer
  v: number
  from: number
  to: number
end

--- Where a clip of a part shown under its return row is drawn: the
--- block of the return row it plays in (`from` up to `to`, beats of the
--- window), and which block it is (`k`).
local record InBlock
  from: number
  to: number
  k: integer
end

--- The clips of a part's row that its timeline shows, and a column more
--- each side. The parts of a subproject shown in place under its return
--- row (`windows`, paw/nest.tl) draw their clips in each block of the
--- row, where the subproject plays them there, and nowhere else: a copy
--- of each clip moved to its place, with the block it is cut at.
local function row_clips(
  ax: Axis, part: types.Part, last: number, windows: {NestModule.Window}
): {types.Clip}, {types.Clip: InBlock}
  local first, cell = ax.scroll, ax:beats(1)
  if not windows then
    return api.clip_list(part.id, first - cell, last + cell), nil
  end
  local clips: {types.Clip} = {}
  local blocks: {types.Clip: InBlock} = {}
  for k, win in ipairs(windows) do
    local from, to = math.max(first - cell, win.from), math.min(last + cell, win.to)
    if to > from then
      for _, clip in ipairs(api.clip_list(part.id, from - win.shift, to - win.shift)) do
        local moved: {string: Data} = {}
        for key, v in pairs(clip as {string: Data}) do
          moved[key] = v
        end
        moved.start = clip.start + win.shift
        local copy = moved as types.Clip
        clips[#clips + 1] = copy
        blocks[copy] = {from = win.from, to = win.to, k = k}
      end
    end
  end
  return clips, blocks
end

--- The clips in view, and the columns each takes: a piece each, cut at the
--- time folds, at the edges of the scope, and at the edges of the block a
--- clip of a subproject shown in place is drawn in (`blocks`). Gives the
--- pieces and their spans of columns.
local function shown_pieces(
  ax: Axis, clips: {types.Clip}, w: integer, folds: boolean, from: number, to: number, blocks: {types.Clip: InBlock}
): {Shown}, {Span}
  local spans: {Span} = {}
  local shown: {Shown} = {}
  for _, clip in ipairs(clips) do
    local scope_from, scope_to = from, to
    local block = blocks and blocks[clip]
    if block then
      scope_from = math.max(scope_from or block.from, block.from)
      scope_to = math.min(scope_to or block.to, block.to)
    end
    local finish = clip.start + clip.length
    local pieces = folds and ax:unfolded(clip.start, finish) or {{clip.start, finish}}
    for k, piece in ipairs(pieces) do
      local x0, x1 = ax:range(piece[1], piece[2])
      local cw = x1 - x0
      if x0 < w and x1 > 0 then
        spans[#spans + 1] = {x0, x0 + cw}
        local cut_from, cut_to = scope_from, scope_to
        if #pieces > 1 then
          cut_from = piece[1] > clip.start and math.max(piece[1], scope_from or piece[1]) or scope_from or -math.huge
          cut_to = piece[2] < finish and math.min(piece[2], scope_to or piece[2]) or scope_to or math.huge
        end
        shown[#shown + 1] = {
          clip = clip,
          cw = cw,
          k = k,
          v = ax:view(piece[1]) - (piece[1] - clip.start),
          from = cut_from,
          to = cut_to,
        }
      end
    end
  end
  return shown, spans
end

--- The key a part's row is kept by, or nil when it may not be kept: a
--- row with an audio clip, the cursor's clip, or clips that share a
--- column (the layers are painted after the row is kept, each in its
--- clip's cells).
local function keep_key_of(part: types.Part, buf: Buf, clips: {types.Clip}, spans: {Span}, cursor_clip: integer): string
  for _, clip in ipairs(clips) do
    if clip.kind ~= "midi" or clip.id == cursor_clip then
      return nil
    end
  end
  local right = -math.huge
  for _, span in ipairs(spans) do
    if span[1] < right then
      return nil
    end
    right = math.max(right, span[2])
  end
  return "arrange:row:" .. part.id .. ":" .. buf.x .. ":" .. buf.y
end

--- The ground of the row of a part shown under its return row: the
--- bars only in the blocks of the row, blank outside them, as no clip of
--- the subproject can be there.
local function nest_ground(
  self: Arrange, buf: Buf, row: Row, windows: {NestModule.Window}, beats: roles.BeatsProps, last: number
)
  buf:fill(0, row.y, buf.width, row.h, " ", "Lane")
  for _, win in ipairs(windows) do
    local from, to = math.max(self.scroll, win.from), math.min(last, win.to)
    if to > from then
      local ground: roles.BeatsProps = {}
      for k, v in pairs(beats as {string: Data}) do
        (ground as {string: Data})[k] = v
      end
      local ax = self.axis
      local v = ax:view(from)
      -- The ground's lines count from the left edge of its first cell.
      ground.from = v - ax:beats(ax:phase_at(v))
      self.plane:mark("beats", v, row.y, ax:view(to) - v, row.h, ground)
    end
  end
end

--- The dotted edges of each block of a return row (`windows`) down a row
--- of the parts its subproject shows in place: in the first and the last
--- column of the block, as the block's frame on the return row.
local function nest_edges(self: Arrange, buf: Buf, row: Row, windows: {NestModule.Window}, style: string, glyph: string)
  for _, win in ipairs(windows) do
    local x0, x1 = self.axis:range(win.from, win.to)
    for _, x in ipairs({x0, x1 - 1}) do
      if x >= 0 and x < buf.width then
        buf:fill(x, row.y, 1, row.h, glyph, style)
      end
    end
  end
end

--- What the timeline of a part's row draws, besides the row itself: is
--- it the cursor's part, the cursor's clip, the lanes of its automation
--- whose curve it draws, its hue, the bar lines, the loop, and the clips
--- chosen with the pointer.
local record RowDraw
  selected: boolean
  cursor_clip: integer
  lanes: {types.Lane}
  hue: Hue
  marks: {BeatLine}
  loop: {number, number}
  chosen: {integer: boolean}
end

--- A part's row of the timeline: its ground with the bars and the loop,
--- its clips, the take being made, and the volume curve. Gives the spans
--- of columns its clips take, for the playhead.
local function part_lane(self: Arrange, buf: Buf, row: Row, part: types.Part, o: RowDraw): {Span}
  local y, height = row.y, row.h
  local ax = self.axis
  local zoom = ax.zoom
  local plane = self.plane
  local w = buf.width
  local vscroll = ax.left
  local colour = draw.part_colour(part)
  local scope_from, scope_to = paw.scope.span()
  local layers = paw.ui.layers.arrange
  local painted = layers and layers.clip
  -- Time folds (paw/folds.tl): the time in view runs further, and a clip
  -- across a fold is drawn in pieces, each cut at the fold.
  local folds = #ax.spans > 0
  local last = ax:beat_of(w)
  local windows = paw.nest.windows(part.id)
  local clips, blocks = row_clips(ax, part, last, windows)
  local shown, spans = shown_pieces(ax, clips, w, folds, scope_from, scope_to, blocks)
  --- What other modules mark on each clip (`paw.ui.layer("arrange",
  --- "clip", ...)`), in its cells.
  local function paint_layers()
    for _, s in ipairs(shown) do
      local clip = s.clip
      local box = plane.buf:sub(plane:cells(s.v, y, clip.length, height))
      paw.ui.paint("arrange", "clip", {buf = box, width = s.cw, height = height, clip = clip})
    end
  end
  local keep_key: string
  if not (paw.ui.scene_drawing or o.selected or (self.rec and part.armed) or windows) then
    keep_key = keep_key_of(part, buf, clips, spans, o.cursor_clip)
  end
  local ground: RowGround
  if keep_key then
    ground = row_ground(self, buf, row, o.hue, o.marks, o.loop, colour, scope_from, scope_to)
    local was = kept_rows[keep_key]
    if
      was
      and same_ground(was.ground, ground)
      and same(was.clips as Data, clips as Data)
      and buf:put_kept(keep_key, 0, y, w, height)
    then
      if painted then
        paint_layers()
      end
      return spans
    end
  end
  local beats: roles.BeatsProps = {
    from = vscroll,
    per = zoom,
    style = o.selected and o.hue.lane_sel or "Lane",
    tone = "lane",
    selected = o.selected or nil,
    color = colour,
    index = row.index,
    loop = o.loop,
    lines = o.marks,
    beats = zoom >= 4 or nil,
  }
  if windows then
    nest_ground(self, buf, row, windows, beats, last)
  else
    plane:mark("beats", vscroll, y, ax:beats(w), height, beats)
  end
  for _, s in ipairs(shown) do
    local clip = s.clip
    local kind = clip.muted and "_off" or clip.id == o.cursor_clip and "_cur" or ""
    local props = view.clip_props(clip, part, o.hue, kind, ax, s.v, o.chosen[clip.id], s.from, s.to, colour)
    if s.k > 1 then
      props.key = props.key .. ":" .. s.k
    end
    if blocks then
      props.key = props.key .. ":block" .. blocks[clip].k
    end
    local box = plane:mark("clip", s.v, y, clip.length, height, props)
    if painted and not keep_key then
      paw.ui.paint("arrange", "clip", {buf = box, width = s.cw, height = height, clip = clip})
    end
  end
  -- The take being made on an armed part, which a window makes grow with
  -- the playhead.
  local rec = self.rec
  if rec and part.armed then
    -- The take's beats are the song's, as the playhead's is; it is drawn
    -- in the window's time.
    local here = paw.time.local_beat
    local v0 = ax:view(here(rec.start))
    local recording: roles.RecordingProps = {
      start = rec.start,
      at = rec.at,
      to = rec.to,
      per = zoom,
      phase = ax:phase_at(v0),
      color = colour,
      bind = "position",
    }
    local finish = rec.to and ax:view(here(rec.to)) or ax:view(ax:beat_of(w))
    plane:mark("recording", v0, y, math.max(finish - v0, ax:beats(1)), height, recording)
  end
  if windows then
    nest_edges(self, buf, row, windows, "NestGuide", draw.g.nest_guide)
  end
  -- The volume curve runs over the empty lane, never over clips, and only
  -- on the part the cursor is on: drawn on every part it ran along the
  -- clips' edges and made the notes harder to read, and the curve of a
  -- part is a thing to look at while working on that part (the others
  -- show an `A` in their header; `<leader>a` opens their lanes as rows).
  for _, l in ipairs(o.lanes) do
    if o.selected and height >= 2 and l.target == "volume" and l.point_count > 0 then
      curve(
        buf,
        0,
        y + 1,
        w,
        height - 1,
        lane_sampler(l.id, ax, spans, nil, nil),
        {style = l.enabled and "Automation" or "Faint", color = colour, enabled = l.enabled, axis = ax}
      )
    end
  end
  if keep_key then
    buf:keep(keep_key, 0, y, w, height)
    kept_rows[keep_key] = {ground = ground, clips = clips}
    if painted then
      paint_layers()
    end
  end
  return spans
end

-- Rows of lanes, takes and the tempo ------------------------------------------------

--- The header's ground and stripe of a lane's row, `lh` lines from `y`.
local function lane_header(headers: Buf, y: integer, lh: integer, hue: Hue, style: string)
  headers:fill(0, y, headers.width, lh, " ", style)
  for r = 0, lh - 1 do
    headers:text(0, y + r, "▏", hue.fg)
  end
end

--- One automation lane row: the header names what the lane moves, its value
--- at the cursor and whether it is read or bypassed; the timeline has its
--- curve and points.
function view:draw_lane_row(headers: Buf, timeline: Buf, row: Row, lines: {GridLine})
  local l, y, lh = row.lane, row.y, row.h
  local ax = self.axis
  local beat = paw.cursor.beat
  local hw, tw = headers.width, timeline.width
  local on = paw.cursor.lane_id() == l.id
  local part = api.part_get(row.id)
  local hue = draw.part_hue(part, row.index)
  local style = on and "PartHeaderSel" or "PartHeader"
  lane_header(headers, y, lh, hue, style)
  headers:text(2, y, util.fit("↳ " .. paw.lanes.name(l), math.max(1, hw - 3)), style)
  local state = l.enabled and "read" or "bypass"
  headers:text(math.max(2, hw - #state - 1), y + 1, state, l.enabled and "Automation" or "FlagOff")
  local value = paw.lanes.format(l, paw.lanes.value_at(l, beat))
  headers:text(4, y + 1, util.fit(value, math.max(1, hw - #state - 5)), "PartInfo")
  local ground: roles.BeatsProps = {
    from = ax.left,
    per = ax.zoom,
    style = on and hue.lane_sel or "Lane",
    tone = "auto",
    lines = grid_marks(lines),
    beats = shows_beats(ax) or nil,
  }
  self.plane:mark("beats", ax.left, y, ax:beats(tw), lh, ground)
  local o: CurveStyle = {
    points = {},
    style = l.enabled and "Automation" or "Faint",
    axis = ax,
    color = draw.part_colour(part, row.index),
    enabled = l.enabled,
  }
  if l.target == "state" then
    -- No curve: each point's state, by name, up to the next point.
    local list = api.lane_points(l.id)
    for i, p in ipairs(list) do
      o.points[i] = {p[1], 1}
    end
    curve(timeline, 0, y, tw, lh, nil, o)
    for i, p in ipairs(list) do
      local x0 = math.max(0, ax:x_of(p[1]))
      local x1 = math.min(tw, list[i + 1] and ax:x_of(list[i + 1][1]) or tw)
      if x1 - x0 >= 2 then
        timeline:text(x0, y + 1, util.fit(paw.lanes.format(l, p[2]), x1 - x0 - 1), o.style)
      end
    end
  else
    -- Volume on the fader's useful stretch, -60 to +6 dB; the rest across their range.
    local lo, hi = l.min or 0, l.max or 1
    if l.target == "volume" then
      lo, hi = -60, 6
    end
    for i, p in ipairs(api.lane_points(l.id)) do
      o.points[i] = {p[1], hi ~= lo and util.clamp((p[2] - lo) / (hi - lo), 0, 1) or 0.5}
    end
    curve(timeline, 0, y, tw, lh, l.point_count > 0 and lane_sampler(l.id, ax, nil, lo, hi) or nil, o)
  end
  if not on then
    return
  end
  -- A selection on this lane: the stretch of time chosen.
  local selection = paw.keymap.selection()
  if selection then
    local x0 = math.max(0, ax:x_of(selection.c0))
    local x1 = math.min(tw, ax:x_of(selection.c1))
    if x1 > x0 then
      timeline:fill(x0, y, x1 - x0, lh, nil, "Visual")
    end
  end
  local x, cw, cursor_style = cursor_cells(ax, beat)
  timeline:fill(x, y, cw, 1, nil, cursor_style)
  timeline:fill(x, y + 1, cw, lh - 1, nil, "CursorTail")
end

--- Where each row is among the lines that the counts of `j` and `k` go
--- over, and the cursor's: rows of parts, and the lane rows too in normal
--- mode while lanes are open (paw/cursor.tl `move_part`). A take lane and,
--- in other modes, a lane row is on no line.
local function counted_lines(L: Layout, cursor_part: integer, cursor_lane: integer): {Row: integer}, integer
  local line_of: {Row: integer} = {}
  local at: integer
  if paw.lanes.any_open() and paw.keymap.mode == "n" then
    local lines = paw.lanes.lines()
    local index: {string: integer} = {}
    for i, l in ipairs(lines) do
      index[l.part .. ":" .. (l.lane and tostring(l.lane) or "")] = i
    end
    for _, row in ipairs(L.rows) do
      if row.kind == "part" or row.kind == "lane" then
        line_of[row] = index[row.id .. ":" .. (row.lane and tostring(row.lane.id) or "")]
      end
    end
    at = cursor_part == 0 and #lines + 1
      or index[tostring(cursor_part) .. ":" .. (cursor_lane and tostring(cursor_lane) or "")]
  else
    for _, row in ipairs(L.rows) do
      if row.kind == "part" then
        line_of[row] = row.index
      end
    end
    at = paw.cursor.row()
  end
  return line_of, at
end

--- The part column (paw/partcolumn.tl) on each line of each row shown.
function view:draw_column(column: Buf, L: Layout, cursor_part: integer, cursor_lane: integer)
  local line_of, at = counted_lines(L, cursor_part, cursor_lane)
  for _, row in ipairs(L.rows) do
    local line = line_of[row]
    local on = row.id == cursor_part
      and (row.kind == "part" and not cursor_lane or row.kind == "lane" and row.lane.id == cursor_lane)
    for k = 0, row.h - 1 do
      paw.partcolumn.draw(
        column,
        L.column,
        row.y + k,
        row.id,
        {
          row = row.index,
          line = k,
          kind = row.kind,
          lane = row.lane and row.lane.id or nil,
          relative = line and at and math.abs(line - at) or nil,
          cursor = on or nil,
        }
      )
    end
  end
end

--- The tempo lane: the header says what the tempo is at the cursor, the
--- timeline draws the map as a curve, a step where a change holds and a slope
--- where it ramps, a mark on each change. `:tempo.lane` or `zT` hides it.
--- It shows the window's time: inside a subproject with its own tempo, its
--- own map.
function view:draw_tempo_row(headers: Buf, timeline: Buf, y: integer, lines: {GridLine})
  local ax = self.axis
  local hw, tw = headers.width, timeline.width
  local beat = paw.cursor.beat
  headers:fill(0, y, hw, 2, " ", "PartHeader")
  headers:text(2, y, util.fit("tempo", math.max(1, hw - 3)), "PartHeader")
  headers:text(2, y + 1, util.fit(string.format("%g bpm", paw.time.tempo_at(beat)), math.max(1, hw - 3)), "PartInfo")
  timeline:fill(0, y, tw, 2, " ", "Lane")
  local beats = shows_beats(ax)
  for _, line in ipairs(lines) do
    if line.bar then
      timeline:fill(line.x, y, 1, 2, draw.g.bar, "LaneBar")
    elseif beats then
      timeline:fill(line.x, y, 1, 2, draw.g.beat, "LaneBeat")
    end
  end
  local lo, hi = paw.tempolane.range()
  local function level(bpm: number): number
    return util.clamp((bpm - lo) / (hi - lo), 0, 1)
  end
  local points: {CurvePoint} = {}
  for i, p in ipairs(paw.time.tempo_points()) do
    points[i] = {p.beat, level(p.bpm), paw.opt.ascii and (p.ramp and ">" or "*") or (p.ramp and "↗" or "◆")}
  end
  local function tempo_height(i: integer): number
    return level(paw.time.tempo_at(ax:half_beat(i)))
  end
  curve(
    timeline,
    0,
    y,
    tw,
    2,
    tempo_height,
    {
      points = points,
      style = "Automation",
      axis = ax,
      color = require("paw.theme").palette.accent,
    }
  )
  local x, cw, cursor_style = cursor_cells(ax, beat)
  timeline:fill(x, y, cw, 1, nil, cursor_style)
end

-- The tempo lane is the ruler's row `tempo`: two lines while it is shown,
-- which the view draws itself.
paw.ruler.row(
  "tempo",
  {
    height = function(_: contracts.RulerContext): integer return paw.tempolane.shown() and 2 or 0 end,
    draw = function(ctx: contracts.RulerContext)
      view:draw_tempo_row(ctx.header, ctx.buf, 0, draw.grid_lines(ctx.axis, ctx.right))
    end,
  }
)

-- The text that the time selection covers on the ruler, by its own style.
local IN_SELECTION: {string: string} = {
  RulerBar = "Visual",
  RulerBarRelative = "Visual",
  RulerBarCursor = "Visual",
  RulerTick = "Visual",
}

-- The time selection of visual mode, over the bars as on the parts it
-- covers. Styles: `selection`.
ruler_marks.namespace(
  "paw.selection",
  {
    route = "over:bars",
    priority = 20,
    styles = {selection = "Visual"},
    source = function(ctx: contracts.RulerContext): {contracts.RulerMark}
      local selection = paw.keymap.selection()
      if not selection or selection.kind == "line" or paw.cursor.lane_id() then
        return {}
      end
      return {
        {
          beat = selection.c0,
          to = selection.c1,
          style = ctx.styles.selection,
          restyle = IN_SELECTION,
          priority = 4,
          kind = "selection",
          text = "the time selection",
        },
      }
    end,
  }
)

--- What `K` says first in the arrange view: the closed fold or the scope
--- under the cursor (paw/scope.tl), then, off a clip, the marks of the
--- ruler in the cursor's column when there is more there than the bar's
--- number.
function view:describe(): contracts.Description
  local lines: contracts.Description = {}
  local function add(more: contracts.Description)
    for _, line in ipairs(more or {}) do
      lines[#lines + 1] = line
    end
  end
  add(paw.scope.under_cursor())
  -- On a clip, `K` tells of the clip: the ruler only between clips.
  local g = self.geometry
  if g and g.ruler and paw.cursor.beat and not paw.cursor.clip() then
    add(paw.ruler.describe(g.ruler, g.axis:x_of(paw.cursor.beat)))
  end
  return #lines > 0 and lines or nil
end

--- One take lane: take `row.take` of every clip of the part that has that
--- many, over the clip's own stretch of time, lit where it is the one that
--- plays and faint where it is not: its name on the first row, and its
--- waveform or its notes on the rows under it. To look at: comping here
--- is `:take 2` over a selection, or a drag across the lane, with the
--- mouse in the terminal or the window. Returns the columns its names take,
--- for the playhead to keep their letters, and the columns its clips take,
--- for the playhead to keep what their bodies show.
function view:draw_take_row(headers: Buf, timeline: Buf, row: Row, lines: {GridLine}): {Span}, {Span}
  local y, k, h = row.y, row.take, row.h
  local ax = self.axis
  local hw, tw = headers.width, timeline.width
  local part = api.part_get(row.id)
  local hue = draw.part_hue(part, row.index)
  local colour = draw.part_colour(part, row.index)
  local names, covered: {Span}, {Span} = {}, {}
  headers:fill(0, y, hw, h, " ", "PartHeader")
  for line = y, y + h - 1 do
    headers:text(0, line, "▏", hue.fg)
  end
  headers:text(2, y, util.fit("↳ take " .. k, math.max(1, hw - 3)), "PartInfo")
  local ground: roles.BeatsProps = {
    from = ax.left,
    per = ax.zoom,
    style = "TakeLane",
    tone = "take",
    lines = grid_marks(lines),
    beats = shows_beats(ax) or nil,
  }
  self.plane:mark("beats", ax.left, y, ax:beats(tw), h, ground)
  -- The clips that have this take, in pieces cut at the time folds and
  -- the scope's edges, as the part's row draws them.
  local clips: {types.Clip} = {}
  for _, clip in ipairs(api.clip_list(row.id, ax.scroll - ax:beats(1), ax:beat_of(tw) + ax:beats(1))) do
    local takes = paw.takes.of(clip)
    if takes and takes.list[k] then
      clips[#clips + 1] = clip
    end
  end
  local scope_from, scope_to = paw.scope.span()
  local shown, spans = shown_pieces(ax, clips, tw, #ax.spans > 0, scope_from, scope_to, nil)
  for i, s in ipairs(shown) do
    local clip = s.clip
    local takes = paw.takes.of(clip)
    local entry = takes.list[k]
    local x0, x1 = spans[i][1], spans[i][2]
    local on = takes.active == k
    local label = (on and (draw.g.play .. " ") or "") .. (entry.name or ("take " .. k))
    local cut_in, cut_out = part_draw.cuts(clip, s.from, s.to)
    -- A clip of its own, with the take's notes or waveform in its body.
    local row_of = paw.frontend.take_rows(clip)
    local props: roles.ClipProps = {
      key = "take:" .. clip.id .. ":" .. k .. (s.k > 1 and (":" .. s.k) or ""),
      id = clip.id,
      take = k,
      active = on or nil,
      name = entry.name,
      label = label,
      color = colour,
      midi = clip.kind ~= "audio",
      length = clip.length,
      per = ax.zoom,
      phase = ax:phase_at(s.v),
      cut_in = cut_in,
      cut_out = cut_out,
      content = row_of and row_of[k] and row_of[k].key,
      title_style = on and hue.title or "TakeLaneName",
      body_style = on and hue.body or "TakeLane",
    }
    part_draw.take_body(props, clip, k, props.content, colour, on, ax)
    self.plane:mark("clip", s.v, y, clip.length, h, props)
    local at = x1 - x0 > 2 and 1 or 0
    names[#names + 1] = {x0 + at, math.min(x1, x0 + at + api.str_width(label))}
    covered[#covered + 1] = {x0, x1}
  end
  -- The stretch being dragged over.
  local comp = self.comp
  if comp and comp.id == row.id and comp.take == k then
    local x0 = math.floor(math.min(comp.x0, comp.x1)) - hw
    local x1 = math.floor(math.max(comp.x0, comp.x1)) - hw
    timeline:fill(math.max(0, x0), y, math.max(0, x1 - math.max(0, x0) + 1), h, nil, "Visual")
  end
  return names, covered
end

-- The fewest columns for the descriptions beside the keys of the welcome
-- page. With fewer, each description goes on the rows under its key.
local WELCOME_MIN_TEXT = 20

--- A row of the welcome page: a key, its text, or both.
local record WelcomeRow
  key: string
  text: string
end

--- What a new project shows in place of parts: how to begin.
local function welcome(buf: Buf)
  local lines: {{string, string}} = {
    {"o", "add a part"},
    {"a", "put an instrument on it"},
    {"i Enter", "enter notes: a clip opens to draw them (i alone: insert mode)"},
    {"then I", "play them on a MIDI keyboard (step input)"},
    {paw.keymap.human("<leader><Space>"), "play, and stop"},
    {paw.keymap.human("<leader>f:"), "find any command"},
    {"?", "every key that works where you are"},
    {":", "run a command by name"},
    {":help", "the manual, inside the program"},
  }
  if paw.commands.get("tutor") then
    lines[#lines + 1] = {":tutor", "take the course, ten minutes a lesson"}
  end
  local intro = "Everything is driven from the keyboard. To begin:"
  -- The key column is as wide as the widest key: a key comes from the
  -- user's mappings (the leader, for example), so it has no fixed width.
  local key_width, text_width = 0, 0
  for _, line in ipairs(lines) do
    key_width = math.max(key_width, api.str_width(line[1]))
    text_width = math.max(text_width, api.str_width(line[2]))
  end
  -- The block is in the middle when it fits, else at the left edge.
  local gap = 3
  local block = math.max(api.str_width(intro), 2 + key_width + gap + text_width)
  local x = math.max(1, (buf.width - block) // 2)
  local text_x = x + 2 + key_width + gap
  -- Too little room right of the keys: each description goes under its key.
  local beside = buf.width - 1 - text_x >= WELCOME_MIN_TEXT
  if not beside then
    text_x = x + 6
  end
  local room = math.max(1, buf.width - 1 - text_x)

  -- The rows: a key and a text for the first row of a line, a text alone
  -- for each row that a long description wraps to, a key alone when the
  -- description goes under it.
  local rows: {WelcomeRow} = {}
  for _, line in ipairs(lines) do
    if not beside then
      rows[#rows + 1] = {key = line[1]}
    end
    for i, part in ipairs(util.wrap(line[2], room)) do
      rows[#rows + 1] = {key = beside and i == 1 and line[1] or nil, text = part}
    end
  end
  local intro_rows = util.wrap(intro, math.max(1, buf.width - 1 - x))

  -- One plain ground, so that the rule between the part headers and the
  -- lanes does not cut through the text.
  buf:fill(0, 0, buf.width, buf.height, " ", "Normal")
  local y = math.max(1, (buf.height - #rows - #intro_rows - 2) // 2)
  buf:text(x, y, "A new project", "WelcomeTitle")
  for i, part in ipairs(intro_rows) do
    buf:text(x, y + i, part, "Dim")
  end
  y = y + #intro_rows + 2
  for i, row in ipairs(rows) do
    if row.key then
      buf:text(x + 2, y + i - 1, row.key, "HintKey")
    end
    if row.text then
      buf:text(text_x, y + i - 1, row.text, "Welcome")
    end
  end
end

-- What windows ask of the view --------------------------------------------------------

--- The time this view shows, for windows bound in time (`timebind`): the
--- beat at the left edge, columns per beat, and beats shown.
function view:time_axis(_?: contracts.RenderContext): number, number, number
  return self.scroll, paw.opt.zoom, self.geometry and self.geometry.span
end

function view:set_time_axis(left: number, zoom: number, _?: contracts.RenderContext)
  self.scroll = math.max(0, left)
  if zoom and paw.opt.zoom ~= zoom then
    paw.opt.zoom = zoom
  end
end

--- On an automation lane row the lane's own keys come first. On a part's
--- row the keys of its head come first (paw/heads.tl).
function view:subscope(): string | {string}
  if paw.cursor.lane_id() then
    return "arrange.lane"
  end
  local part = paw.cursor.part_id()
  return part and heads.scope(part) or nil
end

--- What a window of the arrange view shows besides what events announce
--- (the screen keeps the window while it is the same): its scroll, the
--- take being made, whether a jump or another window moves its time, the
--- selection of visual mode, and the clips chosen with the pointer.
function view:stamp(ctx: contracts.RenderContext): string
  local selection = paw.keymap.selection()
  local selected = ""
  if selection then
    selected = table.concat({selection.kind, selection.r0, selection.r1, selection.c0, selection.c1} as {string}, ",")
  end
  return table.concat(
    {
      tostring(self.scroll),
      tostring(self.top),
      tostring(self.rec_start),
      tostring(self.seen_jump == paw.keymap.jump_serial),
      tostring(ctx.follower),
      selected,
      table.concat(paw.frontend.chosen_clips(), ","),
    },
    " "
  )
end

-- A frame ---------------------------------------------------------------------------

--- What the parts of one frame share: the buffers of the whole view, the
--- headers, the timeline under the ruler (`lanes`) and the ruler's first
--- line; the layout, the window's axis (`ax`, its time folds in it), the
--- beats shown and the beat at the right edge; the transport and `here`,
--- which turns a beat of the song into the window's time; the bar and beat
--- lines; the cursor's part and lane.
local record Frame
  buf: Buf
  headers: Buf
  --- The first column of `headers` in the view.
  headers_x: integer
  lanes: Buf
  ruler: Buf
  L: Layout
  ax: Axis
  span: number
  last: number
  t: types.Transport
  here: function(beat: number): number
  spans: {TimeSpan}
  lines: {GridLine}
  cursor_part: integer
  cursor_lane: integer
  --- The cursor's beat in this window's time, or nil when the current
  --- window is elsewhere in the song (`paw.scope.cursor_beat`).
  cursor_beat: number
  --- The spans of the clips of each part's row, and of the names of
  --- each take lane's, for the playhead.
  covered: {Row: {Span}}
  names_of: {Row: {Span}}
end

--- Keep the playhead in view while playing, and the cursor whenever it
--- moves or playback stops (the cursor stays on screen, as in Vim);
--- unless another window leads this one's time (`timebind`). Each window
--- follows them in its own time, and only while they are inside the time
--- it shows: a window inside a subproject stays in its bars while the
--- cursor or the playhead is elsewhere in the song.
local function follow(self: Arrange, F: Frame, led: boolean)
  local t, span = F.t, F.span
  -- The axis at the scroll the window has before it follows.
  local ax = axis.new(self.scroll, paw.opt.zoom, F.spans)
  local function ahead(beat: number): number
    return ax:view(beat) - ax.left
  end
  local from, to = paw.scope.span()
  local function shown(beat: number): boolean
    return not from or (beat >= from - 1e-9 and beat <= to + 1e-9)
  end
  local beat = F.cursor_beat
  if t.playing and paw.opt.follow and not led then
    local position = F.here(t.position)
    if shown(position) and (position < self.scroll or ahead(position) >= span) then
      self.scroll = paw.time.bar_floor(position)
    end
    -- The playhead moved the view, so the cursor may be off screen. Forget
    -- the seen beat: the first frame after the stop scrolls to the cursor.
    beat = nil
  elseif beat and beat ~= self.seen_beat and not led then
    -- A jump aligns the cursor in the view's beats, through the folds.
    local jumped = paw.keymap.jump_serial ~= self.seen_jump
    local target = draw.jump_scroll(ax, ax:view(beat), span, jumped)
    if target then
      self.scroll = math.max(0, ax:unview(target))
    elseif beat < self.scroll then
      self.scroll = paw.time.bar_floor(beat)
    elseif ahead(beat) >= span - ax:beats(1) then
      local back = ax:unview(ax:view(beat) - span)
      local bar = paw.time.bar()
      self.scroll = math.max(0, math.ceil(back / bar + 1) * bar)
    end
  end
  self.seen_beat, self.seen_jump = beat, paw.keymap.jump_serial
end

--- A path of scopes cut at its left to `room` columns: the outer levels
--- go first (`…› Verse › Keys`), then the innermost name is cut.
local function fit_path(path: string, room: integer): string
  if api.str_width(path) <= room then
    return path
  end
  local levels: {string} = {}
  for level in (path .. " › "):gmatch("(.-) › ") do
    levels[#levels + 1] = level
  end
  for i = 2, #levels do
    local rest = "…› " .. table.concat(levels, " › ", i)
    if api.str_width(rest) <= room then
      return rest
    end
  end
  return util.fit(levels[#levels] or path, room)
end

--- The window bar, in the ruler's two left cells over the headers, each
--- window its own: where the window is (its scope's path, `Song` with
--- none) and where the cursor is in it, at `beat` of the window's time
--- (`cur 1.2 @9.2`, nothing when the cursor is outside that time). With
--- one row of ruler, both on it: `Verse 1.2 @9.2`, as the status line.
local function window_bar(buf: Buf, hw: integer, two_rows: boolean, beat: number)
  if hw < 12 then
    return
  end
  local room = hw - 2
  local path = paw.scope.where()
  -- Off the grid, the hundredths too: `Song 2.2.31`.
  local place = beat and (motion.off(timegrid.tick(beat)) and paw.scope.format(beat) or paw.scope.place(beat))
  if not two_rows then
    local after = place and (" " .. place) or ""
    local fitted = fit_path(path, math.max(1, room - api.str_width(after)))
    local x = 1 + buf:text(1, 0, fitted, "RulerWhere")
    if api.str_width(fitted .. after) <= room then
      buf:text(x, 0, after, "RulerCorner")
    end
    return
  end
  buf:text(1, 0, fit_path(path, room), "RulerWhere")
  if not place then
    return
  end
  if room >= api.str_width(place) + 4 then
    local label: contracts.LabelMark = {text = "cur", style = "RulerCornerLabel", font = "sans", tone = "text_3"}
    buf:mark("label", 1, 1, 3, 1, label)
    buf:text(5, 1, place, "RulerCorner")
  else
    buf:text(1, 1, util.fit(place, room), "RulerCorner")
  end
end

--- The bands of extensions under the ruler (`paw.frontend.bands`), a row
--- each: an entry with a length over its stretch, one without a flag where
--- it is, each in its colour with its name.
local function draw_bands(F: Frame)
  local bands, lanes, y, ax = F.L.bands, F.lanes, F.L.band_y, F.ax
  if bands.rows == 0 then
    return
  end
  for row = 0, bands.rows - 1 do
    lanes:fill(0, y + row, lanes.width, 1, " ", "Ruler")
  end
  for _, e in ipairs(bands.entries) do
    local x0, x1 = ax:range(e.beat, e.beat + e.length)
    local span = e.length > 0 and x1 - x0 or api.str_width(e.name) + 2
    if x0 < lanes.width and x0 + span > 0 then
      local box = lanes:sub(x0, y + e.row, span, 1)
      box:fill(0, 0, span, 1, " ", e.color ~= "" and draw.hue(e.color).pill or "RulerBar")
      box:text(0, 0, (e.length > 0 and draw.g.clip_start or "▾") .. e.name)
    end
  end
end

--- The ruler: the window bar in the corner; the rows of the ruler, with
--- their marks placed by the compositor (paw/ruler.tl), which the view
--- keeps for the pointer and `K`; the bands of extensions under them.
local function draw_ruler(self: Arrange, F: Frame)
  local ax = F.ax
  local buf, L = F.buf, F.L
  local hw, tw = L.hw, L.tw
  local rows = L.ruler_rows - L.bands.rows
  buf:fill(0, 0, hw - 1, L.ruler_rows, " ", "Ruler")
  F.ruler = buf:sub(hw, 0, tw, 1)
  local area = buf:sub(hw, 0, tw, math.max(1, rows))
  area:fill(0, 0, tw, area.height, " ", "Ruler")
  F.lines = draw.grid_lines(ax, F.last)
  -- The window bar has two lines over the ruler's second line, unless a
  -- row that draws itself (the tempo lane) has its header there.
  local corner = 0
  for _, place in ipairs(L.places) do
    if place.row.draw then
      break
    end
    corner = place.y + place.h
  end
  window_bar(buf, hw, corner + L.bands.rows >= 2, F.cursor_beat)
  -- The time of the frame, with the window's axis and its folds.
  local ctx = L.time
  ctx.axis, ctx.left, ctx.right, ctx.cursor = ax, ax.scroll, F.last, F.cursor_beat
  ctx.folded = function(beat: number): boolean return ax:folded(beat) end
  ctx.closed = function(id: integer): boolean
    for _, s in ipairs(F.spans) do
      if s.fold.kind == "region" and s.fold.id == id then
        return true
      end
    end
    return false
  end
  local comp = paw.ruler.compose(L.places, ctx, tw)
  paw.ruler.paint(area, F.headers:sub(0, 0, F.headers.width, area.height), comp)
  self.geometry.ruler = comp
  draw_bands(F)
end

--- The take being made: from where the playhead was when it began, or
--- from the punch-in.
local function recording(self: Arrange, t: types.Transport)
  if t.take then
    self.rec_start = self.rec_start or t.position
  else
    self.rec_start = nil
  end
  if not self.rec_start then
    self.rec = nil
    return
  end
  self.rec = {
    start = t.punch_enabled and math.max(self.rec_start, t.punch_start) or self.rec_start,
    at = t.position,
    to = t.punch_enabled and t.punch_end or nil,
  }
end

--- The cursor's cell on a row, in the mode's colour where the clips'
--- names are, a shadow below. The window keeps where it is on the
--- screen (`caret`), for the float of `K`.
local function cursor_cell(self: Arrange, F: Frame, y: integer, h: integer)
  if not F.cursor_beat then
    return
  end
  local x, cw, style = cursor_cells(F.ax, F.cursor_beat)
  self.caret = {x = F.lanes.x + math.max(0, x), y = F.lanes.y + y, w = cw, h = 1}
  F.lanes:fill(x, y, cw, 1, nil, style)
  if h > 1 then
    F.lanes:fill(x, y + 1, cw, h - 1, nil, "CursorTail")
  end
end

--- The line that closes the parts of a subproject shown under its
--- return row (`row.id`): `end of ⧉Bridge` in the headers, and under each
--- block of the row a dotted line between its edges; blank outside them.
local function draw_closing_line(F: Frame, row: Row)
  local g = draw.g
  local headers, lanes = F.headers, F.lanes
  headers:fill(0, row.y, headers.width, 1, g.nest_close, "NestGuide")
  local nest = paw.nest.get(paw.nest.returns(row.id))
  local words = " end of ⧉" .. (nest and nest.name or "?") .. " "
  if api.str_width(words) > headers.width - 2 then
    words = util.fit(words, math.max(1, headers.width - 2))
  end
  headers:text(1, row.y, words, "PartFold")
  lanes:fill(0, row.y, lanes.width, 1, " ", "Lane")
  for _, win in ipairs(paw.nest.windows(F.L.parts[row.index]) or {}) do
    local x0, x1 = F.ax:x_of(win.from), F.ax:x_of(win.to) - 1
    if x1 > x0 then
      lanes:fill(x0, row.y, x1 - x0, 1, g.nest_close, "NestGuide")
      lanes:text(x0, row.y, g.bl, "NestGuide")
      lanes:text(x1, row.y, g.br, "NestGuide")
    end
  end
end

-- Overviews -------------------------------------------------------------------------

--- The columns where a part has clips in view, between the beats `from`
--- and `to` when they are given: one span for each piece of a clip that
--- the time folds leave.
local function clip_columns(ax: Axis, id: integer, w: integer, from?: number, to?: number): {Span}
  local first, last = ax.scroll, ax:beat_of(w)
  if from then
    first = math.max(first, from)
  end
  if to then
    last = math.min(last, to)
  end
  local out: {Span} = {}
  if last <= first then
    return out
  end
  for _, clip in ipairs(api.clip_list(id, first, last)) do
    local a, b = math.max(clip.start, first), math.min(clip.start + clip.length, last)
    for _, piece in ipairs(ax:unfolded(a, b)) do
      local x0, x1 = math.max(0, ax:x_of(piece[1])), math.min(w, ax:x_of(piece[2]))
      if x1 > x0 then
        out[#out + 1] = {x0, x1}
      end
    end
  end
  return out
end

--- Every part inside a group, at any depth.
local function inside(group: integer, out?: {integer}): {integer}
  out = out or {}
  for _, id in ipairs(paw.groups.members(group)) do
    out[#out + 1] = id
    if paw.groups.is_group(id) then
      inside(id, out)
    end
  end
  return out
end

--- The overview `━` on line `y` over spans of columns.
local function overview(buf: Buf, y: integer, spans: {Span}, style: string)
  local glyph = draw.g.overview
  for _, span in ipairs(spans) do
    buf:text(span[1], y, glyph:rep(span[2] - span[1]), style)
  end
end

--- The columns where any part inside a group has clips in view.
local function group_columns(ax: Axis, group: integer, w: integer): {Span}
  local spans: {Span} = {}
  for _, id in ipairs(inside(group)) do
    for _, span in ipairs(clip_columns(ax, id, w)) do
      spans[#spans + 1] = span
    end
  end
  return spans
end

--- A line of a folded group for one of its members: the member's name,
--- then its clips. A clip that is all in one stretch of the view shows
--- its notes in one line; a clip that a time fold cuts, and a group
--- inside the group, show the overview.
local function member_line(ax: Axis, buf: Buf, y: integer, id: integer)
  local w = buf.width
  local hue = draw.part_hue(api.part_get(id))
  if paw.groups.is_group(id) then
    overview(buf, y, group_columns(ax, id, w), hue.fg)
  else
    for _, clip in ipairs(api.clip_list(id, ax.scroll, ax:beat_of(w))) do
      local finish = clip.start + clip.length
      local x0, x1 = ax:range(clip.start, finish)
      local whole = #ax:unfolded(clip.start, finish) == 1
      local line = whole and part_draw.notes_line(clip, x1 - x0, ax, ax:view(clip.start))
      if line then
        buf:text(x0, y, line, hue.fg)
      else
        overview(buf, y, clip_columns(ax, id, w, clip.start, finish), hue.fg)
      end
    end
  end
  -- From the second column, as a clip's name: the first is where the
  -- playhead and a clip's start stand.
  buf:text(1, y, part_name(id, "name") .. " ", hue.title)
end

--- What a group's row shows of its parts: on its first line, the
--- overview where any of them has a clip. A folded group lists its
--- members on its other lines, one a line; when they do not fit, the
--- last line says how many more there are.
local function group_overview(F: Frame, row: Row, hue: Hue)
  local members = paw.groups.members(row.id)
  if #members == 0 then
    return
  end
  local buf = F.lanes
  overview(buf, row.y, group_columns(F.ax, row.id, buf.width), hue.fg)
  if not paw.groups.folded(row.id) then
    return
  end
  local lines = row.h - 1
  local shown = #members > lines and lines - 1 or #members
  for i = 1, shown do
    member_line(F.ax, buf, row.y + i, members[i])
  end
  if shown < #members and lines > 0 then
    buf:text(1, row.y + lines, "+" .. (#members - shown) .. " more", "Faint")
  end
end

--- Add the hits of a head to the window's (`self.head_hits`).
local function add_hits(self: Arrange, list: {heads.Hit})
  for _, hit in ipairs(list) do
    self.head_hits[#self.head_hits + 1] = hit
  end
end

--- The rows of the timeline: lanes and takes first, then each part's
--- header and clips, and the cursor on its part. The timeline under the
--- ruler is a plane, beats along and the view's lines down: a window
--- paints the clips and the lines on it where they are between cells.
--- Lines, not parts, go down, because rows of other kinds (take lanes,
--- automation lanes) have heights of their own, and a drag goes across
--- all of them in one domain.
local function draw_rows(self: Arrange, F: Frame)
  local L, ax, t = F.L, F.ax, F.t
  self.plane = F.buf:plane(
    L.hw,
    L.ruler_rows,
    L.tw,
    math.max(1, L.master.y - L.ruler_rows),
    {
      key = "timeline",
      x = {domain = "beat", from = ax.left, per = ax.zoom},
      y = {domain = "line", from = L.ruler_rows, per = 1},
    }
  ) as RolesModule.Plane
  local marks = grid_marks(F.lines)
  local loop: {number, number}
  if t.loop_enabled and t.loop_end > t.loop_start then
    loop = {ax:view(F.here(t.loop_start)), ax:view(F.here(t.loop_end))}
  end
  recording(self, t)
  self.caret = nil
  local cursor_clip = paw.cursor.clip()
  local chosen: {integer: boolean} = {}
  for _, id in ipairs(paw.frontend.chosen_clips()) do
    chosen[id] = true
  end
  F.covered, F.names_of = {}, {}
  for _, row in ipairs(L.rows) do
    if row.kind == "lane" then
      self:draw_lane_row(F.headers, F.lanes, row, F.lines)
    end
    if row.kind == "take" then
      F.names_of[row], F.covered[row] = self:draw_take_row(F.headers, F.lanes, row, F.lines)
    end
    if row.kind == "end" then
      draw_closing_line(F, row)
    end
  end
  for _, row in ipairs(L.rows) do
    if row.kind == "part" then
      local part = api.part_get(row.id)
      local selected = row.id == F.cursor_part
      local automation = api.lane_list(row.id)
      local hue = draw.part_hue(part, row.index)
      local on_part = selected and not F.cursor_lane
      add_hits(
        self,
        heads.draw(
          {
            buf = F.headers,
            y = row.y,
            h = row.h,
            part = part,
            index = row.index,
            selected = on_part,
            hue = hue,
            x = F.headers_x,
          }
        )
      )
      -- With its lanes open as rows, a part's curve is drawn there, not here.
      F.covered[row] = part_lane(
        self,
        F.lanes,
        row,
        part,
        {
          selected = selected,
          cursor_clip = cursor_clip and cursor_clip.id,
          lanes = paw.lanes.is_open(row.id) and {} or automation,
          hue = hue,
          marks = marks,
          loop = loop,
          chosen = chosen,
        }
      )
      if paw.groups.is_group(row.id) then
        group_overview(F, row, hue)
      end
      if on_part then
        cursor_cell(self, F, row.y, row.h)
      end
    end
  end
end

--- The selection of visual mode: whole parts, or a stretch of time on some.
local function draw_selection(F: Frame)
  local selection = paw.keymap.selection()
  if not selection or F.cursor_lane then
    return
  end
  local L = F.L
  for _, row in ipairs(L.rows) do
    if row.kind == "part" and row.index >= selection.r0 and row.index <= selection.r1 then
      if selection.kind == "line" then
        F.buf:fill(0, row.y, L.hw - 1, row.h, nil, "Visual")
        F.lanes:fill(0, row.y, L.tw, row.h, nil, "Visual")
      else
        local x0 = math.max(0, F.ax:x_of(selection.c0))
        local x1 = math.min(L.tw, F.ax:x_of(selection.c1))
        if x1 > x0 then
          F.lanes:fill(x0, row.y, x1 - x0, row.h, nil, "Visual")
        end
      end
    end
  end
end

--- The time outside a scope. Before it (the rest of the bar it starts
--- in), dimmed. At its end, a hard edge: `┃` on the ruler and down every
--- row, nothing after it, and on the ruler what is there and the key to
--- see it (`end of Verse · zw: the song`).
local function draw_scope_edges(F: Frame, scope_from: number, scope_to: number)
  if not scope_from then
    return
  end
  local L = F.L
  local tw, top, rows = L.tw, L.ruler_rows, L.master.y - L.ruler_rows
  local a = math.max(0, F.ax:x_of(scope_from))
  if a > 0 then
    F.lanes:fill(0, top, a, rows, nil, "ScopeOutside")
  end
  local b = F.ax:x_of(scope_to)
  if b >= tw then
    return
  end
  b = math.max(0, b)
  F.lanes:fill(b, 0, tw - b, L.master.y, " ", "ScopeOutside")
  local bottom = math.max(L.ruler_rows, L.used)
  F.lanes:fill(b, 0, 1, bottom, draw.g.scope_end, "ScopeEnd")
  -- The level whose time ends here: the innermost one with time.
  local path = paw.scope.path()
  local name = "the scope"
  for i = #path, 1, -1 do
    local level = path[i]
    if level.kind == "region" or level.kind == "nest" or level.from then
      name = (level.kind == "nest" and "⧉" or "") .. level.name
      break
    end
  end
  local back = #path > 1 and "zW" or "zw"
  local words = string.format(" end of %s · %s: the song", name, back)
  local y = L.ruler_rows >= 2 and 1 or 0
  if tw - b - 1 > 1 then
    F.lanes:text(b + 1, y, util.fit(words, tw - b - 1), "ScopeEndText")
  end
end

--- Each time fold: one narrow column with its name and its bars, on the
--- ruler and down the parts (paw/folds.tl), and the cursor on it.
local function draw_time_folds(F: Frame)
  local L, cursor = F.L, paw.cursor
  for _, s in ipairs(F.spans) do
    local x0 = F.ax:x_of(s.from)
    if x0 < L.tw and x0 + s.cells > 0 then
      local label = util.fit(s.label, math.max(1, s.cells - 1))
      F.ruler:fill(x0, 0, s.cells, 1, " ", "TimeFold")
      F.ruler:text(x0 + 1, 0, label, "TimeFold")
      F.lanes:fill(x0, L.ruler_rows, s.cells, L.master.y - L.ruler_rows, " ", "TimeFoldBody")
      for _, row in ipairs(L.rows) do
        if row.kind == "part" then
          F.lanes:text(x0 + 1, row.y, label, "TimeFold")
        end
      end
      if cursor.beat >= s.from - 1e-9 and cursor.beat < s.to - 1e-9 and F.cursor_part ~= 0 then
        for _, row in ipairs(L.rows) do
          if row.kind == "part" and row.id == F.cursor_part then
            F.lanes:fill(x0, row.y, s.cells, 1, nil, paw.keymap.mode == "x" and "CursorVisual" or "Cursor")
          end
        end
      end
    end
  end
end

--- The top edge of a closed block fold, `width` cells wide: `╭▸`, its
--- name, its bars and its parts, then `─` to its end. Where it does not
--- fit, the parts go first (their names, then how many), then the bars;
--- the name stays. A name made of the parts (the default, `Piano, Pad
--- 9-24`) does not name them again.
local function block_top(f: FoldsModule.Fold, width: integer): string
  local g = draw.g
  local head = g.tl .. g.closed .. " "
  local sep = " " .. g.dot .. " "
  local name = paw.folds.name(f)
  local n = paw.folds.bars(f)
  local bars = n .. (n == 1 and " bar" or " bars")
  local names = paw.folds.part_names(f)
  local choices: {string} = {}
  if name:sub(1, #names) ~= names then
    local count = paw.folds.count(f)
    choices[#choices + 1] = name .. sep .. bars .. sep .. names
    choices[#choices + 1] = name .. sep .. bars .. sep .. count .. (count == 1 and " part" or " parts")
  end
  choices[#choices + 1] = name .. sep .. bars
  for _, text in ipairs(choices) do
    local line = head .. text .. " "
    local used = api.str_width(line)
    if used <= width then
      return line .. g.h:rep(width - used)
    end
  end
  return util.fit(head .. name, width)
end

--- Each closed block fold: a frame over the rows of its parts and its
--- time (paw/folds.tl). The top edge has its name, its bars and its
--- parts; each part has a line of overview `━` where it has clips; the
--- bottom edge has the keys, when the block is more than one part high.
--- The other parts show that time as usual. The cursor on the block
--- marks its top edge: the block is one row and one step for the cursor.
local function draw_block_folds(F: Frame)
  local L, g, ax = F.L, draw.g, F.ax
  for _, f in ipairs(paw.folds.blocks()) do
    local x0 = math.max(0, ax:x_of(f.from))
    local x1 = math.min(L.tw, ax:x_of(f.to))
    if x1 > x0 then
      local member: {integer: boolean} = {}
      for _, id in ipairs(f.parts) do
        member[id] = true
      end
      -- Its rows, and the line of overview of each of its parts: the
      -- first line of the part's row, or the next one under the top edge.
      local top, bottom: integer, integer
      local lines: {integer: integer} = {}
      for _, row in ipairs(L.rows) do
        if member[row.id] then
          F.lanes:fill(x0, row.y, x1 - x0, row.h, " ", "TimeFoldBody")
          top = top or row.y
          bottom = row.y + row.h - 1
          if row.kind == "part" then
            local y = row.y == top and row.y + 1 or row.y
            if y < row.y + row.h then
              lines[y] = row.id
            end
          end
        end
      end
      if top then
        local inner = x0 + 1
        for y, id in pairs(lines) do
          local spans = clip_columns(ax, id, x1, f.from, f.to)
          for _, span in ipairs(spans) do
            span[1] = math.max(span[1], inner)
          end
          overview(F.lanes, y, spans, "TimeFoldBody")
        end
        for y = top + 1, bottom do
          F.lanes:text(x0, y, g.v, "TimeFold")
        end
        F.lanes:text(x0, top, block_top(f, x1 - x0), "TimeFold")
        if bottom > top and not lines[bottom] then
          local hint = #f.parts > 1 and (" za opens " .. g.dot .. " znn enters ") or ""
          local edge = g.bl .. g.h .. hint
          F.lanes:text(x0, bottom, edge .. g.h:rep(math.max(0, x1 - x0 - api.str_width(edge))), "TimeFold")
        end
        local beat = F.cursor_beat
        local here = beat and beat >= f.from - 1e-9 and beat < f.to - 1e-9
        if here and member[F.cursor_part] then
          F.lanes:fill(x0, top, x1 - x0, 1, nil, paw.keymap.mode == "x" and "CursorVisual" or "Cursor")
        end
      end
    end
  end
end

--- Under the last part: the welcome of a new project, or, with room left,
--- how to add a part (a button in a window, which a click opens the kinds
--- of part from).
local function draw_below(F: Frame)
  local L = F.L
  local mst = L.master
  if #L.parts == 0 then
    welcome(F.buf:sub(0, L.ruler_rows, F.buf.width, mst.y - L.ruler_rows))
  elseif mst.y - L.used >= 2 then
    local wide = F.headers.width + 1 >= 16
    F.headers:text(wide and 4 or 2, L.used, "o", "EmptyKey")
    local at = wide and 6 or 4
    local button: contracts.ButtonMark = {
      text = "new part",
      words = "New part",
      icon = "plus",
      style = "Empty",
      quiet = true,
      label = "new part",
    }
    F.headers:mark("button", at, L.used, math.max(9, math.min(13, (F.headers.width + 1) - 1 - at)), 1, button)
  end
end

--- The master part, pinned to the bottom, with its level on both sides.
--- The cursor reaches it with `j` from the last part, and `/master`.
--- Beside it, its automation when it has some; else nothing.
local function draw_master(self: Arrange, F: Frame)
  local mst, ax = F.L.master, F.ax
  local master = api.part_get(0)
  local on_master = F.cursor_part == 0
  add_hits(
    self,
    heads.draw(
      {
        buf = F.headers,
        y = mst.y,
        h = mst.h,
        part = master,
        selected = on_master,
        hue = draw.part_hue(master),
        x = F.headers_x,
      }
    )
  )
  if on_master and F.cursor_beat then
    local x, cw, style = cursor_cells(ax, F.cursor_beat)
    F.lanes:fill(x, mst.y, cw, 1, nil, style)
  end
  for _, l in ipairs(api.lane_list(0)) do
    if l.target == "volume" and l.point_count > 0 then
      curve(
        F.lanes,
        0,
        mst.y,
        F.L.tw,
        mst.h,
        lane_sampler(l.id, ax, nil, nil, nil),
        {
          style = l.enabled and "Automation" or "Faint",
          color = draw.part_colour(master),
          enabled = l.enabled,
          axis = ax,
        }
      )
    end
  end
end

--- What extensions draw on the timeline (`view.layers`), in name order.
--- A layer that fails says so on the ruler.
local function draw_layers(self: Arrange, F: Frame)
  local names: {string} = {}
  for name in pairs(self.layers) do
    names[#names + 1] = name
  end
  if #names == 0 then
    return
  end
  table.sort(names)
  local L = F.L
  local layer: contracts.ArrangeLayer = {
    ruler = F.ruler,
    lanes = F.buf:sub(L.hw, L.ruler_rows, L.tw, L.master.y - L.ruler_rows),
    x = function(beat: number): integer return F.ax:x_of(beat) end,
    axis = F.ax,
    scroll = self.scroll,
    zoom = F.ax.zoom,
    span = F.span,
    top = self.top,
    rows = #L.rows,
    th = L.th,
  }
  for _, name in ipairs(names) do
    local ok, err = pcall(self.layers[name] as Layer, self, layer) as (boolean, string)
    if not ok then
      F.ruler:text(0, 0, util.fit(name .. ": " .. tostring(err), L.tw), "Error")
    end
  end
end

--- The playhead: a mark on the ruler and a thin line on the beat's left
--- edge. Over a clip's body it shades its column and keeps what the cells
--- show, so that the notes or the sound under it stay in view: a clip
--- shows all of its time, its first cell too. A window moves it as the
--- song plays, and so does a terminal, which asks for the spans at the
--- column it moves it to.
local function draw_playhead(self: Arrange, F: Frame)
  local L, t = F.L, F.t
  -- The spans of the column the playhead was at last: a live frame asks
  -- again for the same column until the playhead moves on.
  local last_px: integer
  local last_spans: {contracts.PlayheadSpan}
  local function spans_at(px: integer): {contracts.PlayheadSpan}
    if px == last_px then
      return last_spans
    end
    local spans: {contracts.PlayheadSpan} = {}
    for _, row in ipairs(L.rows) do
      local on_clip, on_name = false, false
      for _, s in ipairs(F.covered[row] or NONE) do
        if px >= s[1] and px < s[2] then
          on_clip = true
        end
      end
      for _, s in ipairs(F.names_of[row] or NONE) do
        if px >= s[1] and px < s[2] then
          on_name = true
        end
      end
      if on_name then
        -- A take's name keeps its letter, in the playhead's colour.
        spans[#spans + 1] = {row.y, 1, "PlayheadClip", false}
      elseif on_clip then
        -- Under the clip's name only, so the name row reads unbroken: a
        -- shade that keeps the notes or the waveform of the column.
        local skip = row.h > 1 and 1 or 0
        spans[#spans + 1] = {row.y + skip, row.h - skip, "PlayheadShade", false}
      else
        spans[#spans + 1] = {row.y, row.h, "Playhead"}
      end
    end
    last_px, last_spans = px, spans
    return spans
  end
  -- Over a folded span the playhead waits on its column, then goes on after it.
  local jumps: {{number, number, number}}
  local ax = F.ax
  if #F.spans > 0 then
    jumps = {}
    for i, s in ipairs(F.spans) do
      jumps[i] = {paw.time.song_beat(s.from), paw.time.song_beat(s.to), ax:beats(s.cells)}
    end
  end
  -- A beat of the window is this many of the song's: 1, or another
  -- number in a subproject with a tempo of its own.
  local rate = paw.time.song_beat(self.scroll + 1) - paw.time.song_beat(self.scroll)
  local playhead: contracts.PlayheadMark = {
    at = t.position,
    -- In the song's beats, as the playhead is.
    from = paw.time.song_beat(ax.left),
    jumps = jumps,
    per = ax.zoom / rate,
    lo = 0,
    hi = 1e12,
    spans = spans_at(ax:x_of(F.here(t.position))),
    spans_at = spans_at,
    bind = "position",
  }
  F.buf:mark("playhead", L.hw, 0, L.tw, L.master.y, playhead)
end

--- With lanes open, the counts at the left count lane rows in normal mode
--- and parts after an operator (`counted_lines`).
function view:operator_shown(): boolean
  return paw.lanes.any_open()
end

function view:render(buf: Buf, ctx: contracts.RenderContext)
  local w, h = buf.width, buf.height
  local zoom = paw.opt.zoom
  local L = self:layout(w, h)
  local hw, tw = L.hw, L.tw
  -- The window's time folds: the map of its beats to its columns, and
  -- the folds as plain data, for the rows that the terminal keeps.
  local spans = paw.folds.time_spans()
  local fold_ground: {{number}} = {}
  for i, s in ipairs(spans) do
    fold_ground[i] = {s.from, s.to, s.cells}
  end
  self.fold_ground = fold_ground
  local F: Frame = {
    buf = buf,
    L = L,
    span = axis.new(self.scroll, zoom):beats(tw),
    t = paw.ui.transport(),
    -- In a subproject, a beat of the song (the playhead's) is `here(beat)`
    -- in the window's time (paw.time).
    here = paw.time.local_beat,
    spans = spans,
    cursor_part = paw.cursor.part_id(),
    cursor_lane = paw.cursor.lane_id(),
    cursor_beat = paw.scope.cursor_beat(ctx.win),
  }
  follow(self, F, ctx.follower)
  -- In a scope with time, the view starts no earlier than the bar it starts in.
  local scope_from, scope_to = paw.scope.span()
  self.scroll = math.max(scope_from and paw.time.bar_floor(scope_from) or 0, self.scroll)
  -- The window's axis, at the scroll it has now: every row draws on it.
  local ax = axis.new(self.scroll, zoom, spans)
  self.axis, F.ax = ax, ax
  self.geometry = {hw = hw, th = L.th, rows = #L.rows, zoom = zoom, span = F.span, layout = L, axis = ax}
  -- The beat at the right edge of the timeline.
  F.last = ax:beat_of(tw)
  -- What this window shows, in the song's beats, comes first: the chord
  -- reading there, and the bakes of the stretched clips there.
  local origin = paw.time.origin()
  local shown = {0}
  for _, row in ipairs(L.rows) do
    if row.kind == "part" then
      shown[#shown + 1] = row.id
    end
  end
  derived.visible(ctx.win and tostring(ctx.win.id) or "arrange", self.scroll + origin, F.last + origin, shown)

  -- All of it takes the pointer, in both frontends (paw/views/arrange_mouse.tl).
  buf:hit(0, 0, w, h, {kind = "arrange"})
  -- The rule between the headers and the timeline, from top to bottom.
  buf:fill(hw - 1, 0, 1, h, draw.g.rule, "Rule")
  -- The part column at the left, then the headers. The heads give their
  -- hits for the pointer in the view's columns.
  local cw = L.column.width
  self.head_hits = {}
  local column = cw > 0 and buf:sub(0, 0, cw, h) or nil
  F.headers, F.lanes = buf:sub(cw, 0, hw - 1 - cw, h), buf:sub(hw, 0, tw, h)
  F.headers_x = cw
  buf:fill(0, 0, hw - 1, h, " ", "PartHeader")
  draw_ruler(self, F)
  draw_rows(self, F)
  if column then
    self:draw_column(column, L, F.cursor_part, F.cursor_lane)
  end
  draw_selection(F)
  draw_scope_edges(F, scope_from, scope_to)
  draw_time_folds(F)
  draw_block_folds(F)
  draw_below(F)
  draw_master(self, F)
  draw_layers(self, F)
  draw_playhead(self, F)
end

-- Scrolling ---------------------------------------------------------------------------

--- Scroll so that the cursor is in the middle of the timeline.
function view:center()
  local g = self.geometry
  if not g then
    return
  end
  local ax = axis_of(self)
  self.scroll = math.max(0, ax:unview(ax:view(paw.cursor.beat) - g.span / 2))
  api.ui_redraw()
end

--- Scroll so that the cursor is at the left margin (`paw.opt.jumpmargin`)
--- or, with `right`, at the right edge of the timeline.
function view:place(right?: boolean)
  local g = self.geometry
  if not g then
    return
  end
  local ax = axis_of(self)
  local at = right and g.span - ax:beats(1) or ax:beats(paw.opt.jumpmargin)
  self.scroll = math.max(0, ax:unview(ax:view(paw.cursor.beat) - at))
  api.ui_redraw()
end

--- Scroll by bars without moving the cursor.
function view:scroll_by(bars: number)
  self.scroll = math.max(0, self.scroll + bars * paw.time.bar(self.scroll))
  -- A time fold is one step: the scroll does not stop inside one.
  for _, s in ipairs(axis_of(self).spans) do
    if self.scroll > s.from and self.scroll < s.to then
      self.scroll = bars > 0 and s.to or s.from
    end
  end
  api.ui_redraw()
end

-- What modal editing works on: rows are positions in the part list.
view.grid = {
  get = function(): number, number return paw.cursor.row() or 1, paw.cursor.beat end,
  set = function(row: number, col: number)
    local list = paw.groups.rows()
    local id = list[math.floor(util.clamp(row, 1, #list))]
    -- The row after the last part is the master's.
    if row > #list and paw.cursor.master_reachable() then
      id = 0
    end
    -- Staying on the same part keeps the cursor on the lane row it is on.
    if #list > 0 and id ~= paw.cursor.part_id() then
      paw.cursor.set_part(id)
    end
    paw.cursor.set_beat(col)
  end,
  step = function(): number return timegrid.step() end,
  cell = function(col: number): number local _, to = motion.cell(timegrid.tick(col)); return timegrid.beat(to) end,
  label = function(): string return timegrid.label() end,
  -- A mark stays with its part when parts are moved around.
  mark = function(): contracts.GridMark return {part = paw.cursor.part_id(), beat = paw.cursor.beat} end,
  jump = function(pos: contracts.GridMark)
    if pos.part and pcall(api.part_get, pos.part) then
      paw.cursor.set_part(pos.part)
    end
    paw.cursor.set_beat(pos.beat)
  end,
  -- Clips by name where they start, and parts by name at the cursor's beat.
  search = function(text: string): {contracts.GridHit}
    local wanted = text:lower()
    local hits: {contracts.GridHit} = {}
    for row, id in ipairs(paw.groups.rows()) do
      if part_name(id, "name"):lower():find(wanted, 1, true) then
        hits[#hits + 1] = {row = row, col = paw.cursor.beat}
      end
      for _, clip in ipairs(api.clip_list(id)) do
        if clip.name:lower():find(wanted, 1, true) then
          hits[#hits + 1] = {row = row, col = clip.start}
        end
      end
    end
    if part_name(0, "name"):lower():find(wanted, 1, true) then
      hits[#hits + 1] = {row = #paw.groups.rows() + 1, col = paw.cursor.beat}
    end
    return hits
  end,
}

-- Its ruler is its first row: a graphical frontend shows it with no title
-- of its own over it (paw/panes.tl).
view.titled = true
-- What moves on its own as the song plays: the playhead and the meters. A
-- frontend that paints them with the live values needs no new scene for
-- them, but for when the view must scroll to follow the playhead.
view.live_roles = {"playhead", "hmeter", "recording"}

--- Whether the view must be drawn again although its live roles move on
--- their own: the playhead it follows has left the time it shows.
function view:moving(): boolean
  local g = self.geometry
  if not (g and g.span and paw.opt.follow) then
    return false
  end
  -- Asked on each frame of what moves: the playhead alone, not the transport's table.
  local playing, at = api.transport_playhead()
  local position = paw.time.local_beat(at)
  local ax = axis_of(self)
  return playing and (position < self.scroll or ax:view(position) - ax.left >= g.span)
end

paw.ui.view("arrange", view)
return Arrange
