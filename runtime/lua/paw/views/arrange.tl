-- The arrange view: track headers on the left, clips on a timeline on the right.
--
-- The view places everything (`view:layout`), maps beats to columns through
-- the window's time folds (`view:x`, `view:col`, `view:beat`) and draws
-- each part of a frame in its own function: the ruler, the rows of lanes
-- and takes, the tracks, the selection, the time folds, the master, the
-- layers of extensions and the playhead. What one track's header and
-- clips show is in paw/views/arrange_track.tl, the roles it marks in
-- paw/roles/arrange.tl, and the pointer in paw/views/arrange_mouse.tl.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local kernel = require("paw.events.kernel")
local derived = require("paw.derived")
local track_parts = require("paw.views.arrange_track")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type util_t = require("paw.util")
local type roles = require("paw.roles.arrange")
local type DrawModule = require("paw.draw")
local type FoldsModule = require("paw.folds")
local type RolesModule = require("paw.roles")
local type FrontendModule = require("paw.frontend")
local type TrackcolumnModule = require("paw.trackcolumn")
local type Buf = contracts.Buf
local type Hue = DrawModule.Hue
local type Data = util_t.Data
local type TimeMap = FoldsModule.TimeMap
local type TimeSpan = FoldsModule.TimeSpan
local type BeatLine = roles.BeatLine

local draw = paw.draw
local util = paw.util

-- One field of a track: a whole track's table for each track on each
-- frame costs more than the field.
local track_number = api.track_get as function(id: integer, key: string): number
local track_name = api.track_get as function(id: integer, key: string): string

--- A row of the timeline: a track's (`kind` "track"), one of its take
--- lanes ("take", `take` its number), one of its automation lanes shown
--- as a row ("lane", `lane`), or the master's ("master"). `index` is the
--- track's place among the tracks drawn; `y` and `h` its lines.
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
--- columns with the rule (`hw`), the timeline's (`tw`), the track
--- column, rows a track (`th`), the ruler's rows (`ruler_rows`, the tempo
--- lane's `tempo_rows` and the bands' from `band_y` among them), the rows
--- of the timeline from the first track shown, the tracks, the line after
--- the last row (`used`) and the master's row.
local record Layout
  hw: integer
  tw: integer
  column: TrackcolumnModule.Layout
  th: integer
  ruler_rows: integer
  tempo_rows: integer
  rows: {Row}
  tracks: {integer}
  used: integer
  master: Row
  bands: FrontendModule.Bands
  band_y: integer
end

--- What the last draw gave the pointer and the keys: its layout, too.
local record Geometry is contracts.ArrangeGeometry
  layout: Layout
end

--- A take lane dragged across with the pointer: from column `x0` to `x1`
--- of the view.
local record Comp
  id: integer
  take: integer
  x0: number
  x1: number
end

--- The take being made on the armed tracks: from `start` to the
--- playhead `at`, no further than `to` when it is punched in.
local record Recording
  start: number
  at: number
  to: number
end

--- A bar or beat line of the timeline (`grid_lines`): its column, its bar
--- (nil on a beat), its beat and its place on the plane.
local record GridLine
  x: integer
  bar: integer
  beat: number
  v: number
end

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
  --- The first track shown.
  top: integer
  --- The header columns of the M, S, R and I chips, for the mouse.
  flags: track_parts.Flags
  --- The track column's width at the left of the headers, last drawn.
  column_width: integer
  --- What the window drew last, and its time folds.
  geometry: Geometry
  tmap: TimeMap
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
  --- cursor's row and lane, the tracks that fit, the cursor's beat and
  --- the serial of the last jump.
  seen_index: integer
  seen_fit: integer
  seen_lane: integer
  seen_beat: number
  seen_jump: integer
  meter: function(buf: Buf, x: integer, y: integer, width: integer, peak: number, hold?: number)
  header_width: function(w: integer): integer
  track_height: function(count: integer, room: integer): integer
  row_height: function(id: integer, th: number): integer
  level_glyph: function(level: number): string
  clip_props: function(
    clip: types.Clip,
    track: types.Track,
    hue: Hue,
    kind: string,
    zoom: number,
    chosen?: boolean,
    from?: number,
    to?: number,
    colour?: string
  ): roles.ClipProps
  layout: function(self: Arrange, w: integer, h: integer): Layout
  rows_with_lanes: function(
    self: Arrange, tracks: {integer}, th: integer, ruler_rows: integer, room: integer, cursor_index: integer
  ): {Row}, integer
  v: function(self: Arrange, beat: number): number
  x: function(self: Arrange, beat: number): number
  beat: function(self: Arrange, x: number): number
  fold_at: function(self: Arrange, x: number): TimeSpan
  unfolded: function(self: Arrange, a: number, b: number): {{number, number}}
  folded: function(self: Arrange, beat: number): boolean
  draw_lane_row: function(self: Arrange, headers: Buf, timeline: Buf, row: Row, lines: {GridLine})
  draw_column: function(self: Arrange, column: Buf, L: Layout, cursor_track: integer, cursor_lane: integer)
  draw_tempo_row: function(self: Arrange, headers: Buf, timeline: Buf, y: integer, lines: {GridLine})
  draw_take_row: function(self: Arrange, headers: Buf, timeline: Buf, row: Row, lines: {GridLine}): {Span}, {Span}
end

-- The view is the module.
local view = Arrange
view.scroll, view.top, view.flags = 0, 1, {}
-- What extensions draw on the timeline, by name, in name order, once the
-- ruler and the tracks are drawn and before the playhead:
--   paw.ui.views:get("arrange").layers.marks = function(view, layer) ... end
-- See `contracts.ArrangeLayer` for what `layer` holds.
view.layers = {}
-- Tracks need rows: two fifths of a column's height, and a third of the
-- room where three or more windows share it (paw/ui.tl).
view.share = {column = 2 / 5, least = 1 / 3}
view.window_state = {
  "scroll",
  "top",
  "flags",
  "seen_index",
  "seen_fit",
  "seen_lane",
  "seen_beat",
  "seen_jump",
  "geometry",
  "comp",
  "tmap",
  "fold_ground",
}
view.window_fresh = {"geometry", "flags"}
-- Each seat (paw/seats.tl) has its own state of the window, as each
-- window has.
paw.seats.fields(
  "arrange", view as {string: Data}, view.window_state, {scroll = 0, top = 1, flags = {}} as {string: Data}
)

-- An empty list, to walk where there is none.
local NONE: {Span} = {}

-- Another project is shown from its start, as the cursor is (paw/cursor.tl).
paw.on(kernel.project_loaded, function() view.scroll, view.top, view.seen_beat = 0, 1, nil end)

view.meter = draw.meter
view.level_glyph = track_parts.level_glyph
view.clip_props = track_parts.clip_props

-- The headers' width with "auto" on the narrowest screens.
local NARROW_HEADER = 12

--- Columns for the track headers on a screen `w` wide, the rule on their
--- right included: `paw.opt.header_width`, or by the width with "auto".
function view.header_width(w: integer): integer
  local want = math.tointeger(tonumber(paw.opt.header_width))
  if not want then
    want = w >= 120 and 26 or w >= 100 and 22 or w >= 80 and 18 or NARROW_HEADER
  end
  return math.max(4, math.min(want, w - 4))
end

--- Rows a track takes when `count` tracks share `room` rows: the
--- window's vertical zoom (paw/vzoom.tl), else `paw.opt.track_height`,
--- or with "auto" the most that let every track fit, from 1 to 3. A song
--- with more tracks than fit at 1 row scrolls.
function view.track_height(count: integer, room: integer): integer
  local want = paw.vzoom.track_rows() or tonumber(paw.opt.track_height)
  if want then
    return math.max(1, math.floor(want))
  end
  if count < 1 then
    return 3
  end
  return math.floor(util.clamp(math.floor(room / count), 1, 3))
end

--- Whether the ruler has a second row: when something registered in
--- `view.ruler2` (by name, a function of the view) has something to show.
--- The lanes of `paw.ruler` (the regions' rows) add rows of their own, and
--- a layer draws on the first of them.
---   paw.ui.views:get("arrange").ruler2.marks = function(view) return #my_marks > 0 end
view.ruler2 = {}

local function wants_ruler2(self: Arrange): boolean
  for _, wants in pairs(self.ruler2) do
    local ok, yes = pcall(wants, self) as (boolean, boolean)
    if ok and yes then
      return true
    end
  end
  return false
end

--- The lines a track's row takes, `th` the tracks' height: its own rows
--- in the window's vertical zoom (paw/vzoom.tl), else its own share of
--- `th` (`height`, which a drag of its header's bottom edge sets), at
--- least one.
function view.row_height(id: integer, th: number): integer
  return paw.vzoom.rows_of(id) or math.max(1, math.floor(th * (track_number(id, "height") or 1) + 0.5))
end

--- The rows from `self.top` when some tracks show their take lanes or their
--- automation lanes: each track, then a row `{ kind = "take", id, take,
--- index, y, h }` for each of its take lanes, then a row `{ kind =
--- "lane", id, lane, index, y, h }` for each of its automation lanes (`h`
--- 2 for each lane, or as the window's vertical zoom says).
--- Scrolls so that the cursor's row is in view. Returns the rows and the
--- line after the last.
function view:rows_with_lanes(
  tracks: {integer}, th: integer, ruler_rows: integer, room: integer, cursor_index: integer
): {Row}, integer
  local bottom = ruler_rows + room
  local lane_rows = paw.vzoom.lane_rows()
  -- The rows from track `top` down, the line after them, and whether
  -- every row of the tracks placed fits.
  local function place(top: integer): {Row}, integer, boolean
    local out: {Row} = {}
    local y = ruler_rows
    for index = top, #tracks do
      local id = tracks[index]
      local h = view.row_height(id, th)
      if #out > 0 and y + h > bottom then
        break
      end
      out[#out + 1] = {kind = "track", id = id, index = index, y = y, h = h}
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
    end
    return out, y, true
  end
  local function shows_cursor(rows: {Row}): boolean
    local lane = paw.cursor.lane_id()
    for _, row in ipairs(rows) do
      if row.index == cursor_index and ((row.kind == "track" and not lane) or (row.lane and row.lane.id == lane)) then
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
  self.top = math.floor(util.clamp(self.top, 1, math.max(1, #tracks)))
  -- No room left empty below while tracks above are scrolled away.
  while self.top > 1 do
    local rows, _, whole = place(self.top - 1)
    if not whole or rows[#rows].index < #tracks or not shows_cursor(rows) then
      break
    end
    self.top = self.top - 1
  end
  local rows, y = place(self.top)
  return rows, y
end

--- Where everything goes on a `w` by `h` view: the header width, the ruler's
--- rows, and the rows of the timeline, each `{ kind = "track", id, index, y,
--- h }` from the first track shown, then the master's. All placement is
--- here, so that rows of other kinds can be added in one place.
function view:layout(w: integer, h: integer): Layout
  local tracks = paw.groups.rows()
  local header = view.header_width(w)
  -- The track column (paw/trackcolumn.tl) at the left of the headers takes
  -- the columns of the parts that the options set (the numbers) from the
  -- timeline, as Neovim's number column takes them from the text. The
  -- parts that come and go with the project (signs, the tree of groups)
  -- take theirs from the headers, so that the timeline starts in the same
  -- column with and without groups or a scope. The headers give the
  -- columns that they have beyond the narrowest width (`NARROW_HEADER`),
  -- so a name stays readable in a narrow window; there the rest comes from
  -- the timeline. `count` is how far the counts of `j` and `k` go: over
  -- lane rows too, in normal mode, when lanes are open.
  local count = #tracks
  if paw.lanes.any_open() and paw.keymap.mode == "n" then
    count = #paw.lanes.lines()
  end
  local column = paw.trackcolumn.layout(
    {rows = tracks, count = count}, math.max(0, w - header - 8), math.max(0, header - NARROW_HEADER)
  )
  local hw = header + column.width - column.from_header
  -- The ruler, its second row if something asks for one, a row for each
  -- band of an extension's (`paw.frontend.bands`) that has entries, and
  -- the tempo lane's two rows when it is shown.
  local tempo_rows = paw.tempolane.shown() and 2 or 0
  local bands = paw.frontend.band_state()
  local band_y = 1 + math.max(paw.ruler.lane_rows(), wants_ruler2(self) and 1 or 0)
  local ruler_rows = band_y + bands.rows + tempo_rows
  local master_rows = 2
  local room = math.max(1, h - ruler_rows - master_rows)
  -- Take lanes and automation lanes shown as rows (two lines each, or as
  -- the window's vertical zoom says) take their lines first.
  local lane_lines, own = 0, paw.vzoom.any_own()
  local lane_rows = paw.vzoom.lane_rows()
  for _, id in ipairs(tracks) do
    lane_lines = lane_lines + lane_rows * (paw.takes.lane_count(id) + #paw.lanes.shown(id))
    own = own or (track_number(id, "height") or 1) ~= 1
  end
  local th = view.track_height(#tracks, math.max(1, room - lane_lines))
  -- Squeezed by panels below, a track takes what there is rather than vanish.
  if not (paw.vzoom.track_rows() or tonumber(paw.opt.track_height)) and room < th then
    th = math.max(1, room)
  end
  local L: Layout = {
    hw = hw,
    tw = w - hw,
    column = column,
    th = th,
    ruler_rows = ruler_rows,
    tempo_rows = tempo_rows,
    tracks = tracks,
    master = {kind = "master", id = 0, y = h - master_rows, h = master_rows},
    bands = bands,
    band_y = band_y,
  }
  local cursor_index = paw.cursor.row() or 1
  -- Tracks of heights of their own are placed one by one, as lanes are.
  if lane_lines > 0 or own then
    L.rows, L.used = self:rows_with_lanes(tracks, th, ruler_rows, room, cursor_index)
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
  self.top = math.floor(util.clamp(self.top, 1, math.max(1, #tracks - fit + 1)))
  local rows: {Row} = {}
  local y = ruler_rows
  for index = self.top, #tracks do
    if y + th > ruler_rows + room then
      break
    end
    rows[#rows + 1] = {kind = "track", id = tracks[index], index = index, y = y, h = th}
    y = y + th
  end
  L.rows, L.used = rows, y
  return L
end

-- Time folds ------------------------------------------------------------------------

-- Time folds (paw/folds.tl). A closed region or range of bars is drawn
-- as one narrow column, so the beats of the timeline are not even: each
-- render keeps the window's map (`self.tmap`), and every place that turns
-- a beat into a column goes through `view:x`, `view:col` and `view:beat`.
-- The timeline's plane counts in the beats of that map (`view:v`), so a
-- window places the clips on it as the terminal does.
local no_folds: TimeMap = {
  spans = {},
  view = function(beat: number): number return beat end,
  beat = function(v: number): number return v end,
}

--- The window's map of its beats to its columns.
local function time_map(self: Arrange): TimeMap
  return self.tmap or no_folds
end

--- The place of a beat in the beats of the view (the plane's domain).
function view:v(beat: number): number
  return time_map(self).view(beat)
end

--- The column of a beat from the timeline's left edge, in fractions of a cell.
function view:x(beat: number): number
  local m = time_map(self)
  return (m.view(beat) - m.view(self.scroll)) * self.geometry.zoom
end

--- The column a beat is drawn in, from the timeline's left edge.
function view:col(beat: number): integer
  return math.floor(self:x(beat) + 0.5)
end

--- The beat at a column of the timeline (fractions of a cell): on a folded
--- column, the start of what it folds.
function view:beat(x: number): number
  local m = time_map(self)
  return m.beat(m.view(self.scroll) + x / self.geometry.zoom)
end

--- The folded span drawn at a column of the timeline, or nil.
function view:fold_at(x: number): TimeSpan
  for _, s in ipairs(time_map(self).spans) do
    local x0 = self:x(s.from)
    if x >= x0 and x < x0 + s.cells then
      return s
    end
  end
end

--- The stretches of `a` to `b` that are not folded away, as `{ from, to }`.
function view:unfolded(a: number, b: number): {{number, number}}
  local out: {{number, number}} = {}
  local at = a
  for _, s in ipairs(time_map(self).spans) do
    if s.to > at and s.from < b then
      if s.from > at then
        out[#out + 1] = {at, s.from}
      end
      at = math.max(at, s.to)
    end
  end
  if at < b then
    out[#out + 1] = {at, b}
  end
  return out
end

--- Whether a beat is inside a folded span, after its start.
function view:folded(beat: number): boolean
  for _, s in ipairs(time_map(self).spans) do
    if beat > s.from + 1e-9 and beat < s.to - 1e-9 then
      return true
    end
  end
  return false
end

--- The bar and beat lines on the timeline. None inside a fold.
local function grid_lines(self: Arrange, width: integer): {GridLine}
  local out: {GridLine} = {}
  local last = self:beat(width)
  for _, piece in ipairs(self:unfolded(self.scroll, last + 1e-6)) do
    for _, line in ipairs(draw.bar_lines(piece[1], piece[2] - piece[1])) do
      if line.beat >= piece[1] - 1e-9 and line.beat < piece[2] - 1e-9 then
        out[#out + 1] = {x = self:col(line.beat), bar = line.bar, beat = line.beat, v = self:v(line.beat)}
      end
    end
  end
  return out
end

--- The lines of the bars among `lines` (`grid_lines`), as the `beats`
--- role takes them.
local function bar_marks(lines: {GridLine}): {BeatLine}
  local out: {BeatLine} = {}
  for _, line in ipairs(lines) do
    if line.bar then
      out[#out + 1] = {line.v or line.beat, true}
    end
  end
  return out
end

-- Curves ----------------------------------------------------------------------------

--- The height of a curve at half column `i`, from 0 to 1; nil for none.
local type Height = function(i: integer): number

-- What `lane_sample` reads: the lane `lane` from the beat `scroll` at
-- `zoom` columns a beat, in half columns, nothing over the columns of
-- `skip` (spans), and the level of a value by `lo` and `hi` (a volume in
-- dB when they are nil); with `view`, the view with time folds, whose map
-- gives the beat of each column. Set before each curve that it samples: a
-- frame draws a curve for each lane with no new function for it.
local record Sampled
  lane: integer
  scroll: number
  zoom: number
  skip: {Span}
  lo: number
  hi: number
  view: Arrange
end
local sampled: Sampled = {lane = 0, scroll = 0, zoom = 1}

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
  local folded = sampled.view
  local beat = folded and folded:beat((i + 0.5) / 2) or sampled.scroll + (i + 0.5) / (sampled.zoom * 2)
  local v = api.lane_value_at(sampled.lane, beat)
  local lo, hi = sampled.lo, sampled.hi
  if lo == nil then
    return (v + 60) / 66
  end
  return hi ~= lo and util.clamp((v - lo) / (hi - lo), 0, 1) or 0.5
end

-- Set what `lane_sample` reads, and give it.
local function lane_sampler(
  lane: integer, scroll: number, zoom: number, skip: {Span}, lo: number, hi: number, self: Arrange
): Height
  sampled.lane, sampled.scroll, sampled.zoom, sampled.skip, sampled.lo, sampled.hi = lane, scroll, zoom, skip, lo, hi
  sampled.view = self and #time_map(self).spans > 0 and self or nil
  return lane_sample
end

--- A point marked on a curve: its beat, its height, and its glyph (a
--- diamond when nil).
local type CurvePoint = {number, number, string}

--- How a curve is drawn (`curve`): the points marked on it, the style of
--- its cells, where the beats are (`from`, `per`, and `v`, the place of a
--- beat on the plane), and how a window draws it (`color`, `enabled`).
local record CurveStyle
  points: {CurvePoint}
  style: string
  from: number
  per: number
  v: function(beat: number): number
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
  local function place(p: CurvePoint): number
    return o.v and o.v(p[1]) or p[1]
  end
  for i, p in ipairs(o.points or {}) do
    marks[i] = {place(p), p[2]}
  end
  local function height(i: integer): number
    local v = values[i + 1]
    return v is number and v or nil
  end
  local props: roles.CurveProps = {
    values = values,
    points = marks,
    from = o.from,
    per = o.per,
    color = o.color,
    enabled = o.enabled ~= false,
    draw = function(b: Buf)
      if value then
        draw.curve(b, 0, h, height, o.style)
      end
      for _, p in ipairs(o.points or {}) do
        local px = math.floor((place(p) - o.from) * o.per + 0.5)
        if px >= 0 and px < w then
          b:text(px, p[2] >= 0.5 and 0 or h - 1, p[3] or "◆", o.style)
        end
      end
    end,
  }
  buf:mark("curve", x, y, w, h, props)
end

-- A track's row of the timeline -------------------------------------------------------

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

-- The rows of the timeline that the terminal drew last, by their track and
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

--- A clip in view on a track's row, or a piece of one cut by a time fold:
--- its columns (`cw`), which piece it is (`k`), where the clip would start
--- were its piece's stretch of the view even (`v`), and the beats where
--- it is cut (`from`, `to`).
local record Shown
  clip: types.Clip
  cw: integer
  k: integer
  v: number
  from: number
  to: number
end

--- The clips of a track's row that its timeline shows, and a column more
--- each side. The tracks of a subproject open in place under its return
--- row draw their clips where the subproject plays them (`paw.nest.shift`).
local function row_clips(self: Arrange, track: types.Track, last: number): {types.Clip}
  local scroll, zoom = self.scroll, self.geometry.zoom
  local shift = paw.nest.shift(track.id)
  local clips = api.clip_list(track.id, scroll - (shift or 0) - 1 / zoom, last - (shift or 0) + 1 / zoom)
  if shift then
    for i, clip in ipairs(clips) do
      local moved: {string: Data} = {}
      for k, v in pairs(clip as {string: Data}) do
        moved[k] = v
      end
      moved.start = clip.start + shift
      clips[i] = moved as types.Clip
    end
  end
  return clips
end

--- The clips in view, and the columns each takes: a piece each, cut at the
--- time folds. Gives the pieces and their spans of columns.
local function shown_pieces(
  self: Arrange, clips: {types.Clip}, w: integer, folds: boolean, scope_from: number, scope_to: number
): {Shown}, {Span}
  local spans: {Span} = {}
  local shown: {Shown} = {}
  for _, clip in ipairs(clips) do
    local finish = clip.start + clip.length
    local pieces = folds and self:unfolded(clip.start, finish) or {{clip.start, finish}}
    for k, piece in ipairs(pieces) do
      local x0, x1 = self:col(piece[1]), self:col(piece[2])
      local cw = math.max(1, x1 - x0)
      if x0 < w and x0 + cw > 0 then
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
          v = self:v(piece[1]) - (piece[1] - clip.start),
          from = cut_from,
          to = cut_to,
        }
      end
    end
  end
  return shown, spans
end

--- The key a track's row is kept by, or nil when it may not be kept: a
--- row with an audio clip, the cursor's clip, or clips that share a
--- column (the layers are painted after the row is kept, each in its
--- clip's cells).
local function keep_key_of(
  track: types.Track, buf: Buf, clips: {types.Clip}, spans: {Span}, cursor_clip: integer
): string
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
  return "arrange:row:" .. track.id .. ":" .. buf.x .. ":" .. buf.y
end

--- What the timeline of a track's row draws, besides the row itself: is
--- it the cursor's track, the cursor's clip, the lanes of its automation
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

--- A track's row of the timeline: its ground with the bars and the loop,
--- its clips, the take being made, and the volume curve. Gives the spans
--- of columns its clips take, for the playhead.
local function track_lane(self: Arrange, buf: Buf, row: Row, track: types.Track, o: RowDraw): {Span}
  local y, height = row.y, row.h
  local scroll, zoom = self.scroll, self.geometry.zoom
  local plane = self.plane
  local w = buf.width
  local vscroll = self:v(scroll)
  local colour = draw.track_colour(track)
  local scope_from, scope_to = paw.scope.span()
  local layers = paw.ui.layers.arrange
  local painted = layers and layers.clip
  -- Time folds (paw/folds.tl): the time in view runs further, and a clip
  -- across a fold is drawn in pieces, each cut at the fold.
  local folds = #time_map(self).spans > 0
  local last = folds and self:beat(w) or scroll + w / zoom
  local clips = row_clips(self, track, last)
  local shown, spans = shown_pieces(self, clips, w, folds, scope_from, scope_to)
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
  if not (paw.ui.scene_drawing or o.selected or (self.rec and track.armed)) then
    keep_key = keep_key_of(track, buf, clips, spans, o.cursor_clip)
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
  plane:mark("beats", vscroll, y, w / zoom, height, beats)
  for _, s in ipairs(shown) do
    local clip = s.clip
    local kind = clip.muted and "_off" or clip.id == o.cursor_clip and "_cur" or ""
    local props = view.clip_props(clip, track, o.hue, kind, zoom, o.chosen[clip.id], s.from, s.to, colour)
    if s.k > 1 then
      props.key = props.key .. ":" .. s.k
    end
    local box = plane:mark("clip", s.v, y, clip.length, height, props)
    if painted and not keep_key then
      paw.ui.paint("arrange", "clip", {buf = box, width = s.cw, height = height, clip = clip})
    end
  end
  -- The take being made on an armed track, which a window makes grow with
  -- the playhead.
  local rec = self.rec
  if rec and track.armed then
    local v0 = self:v(rec.start)
    local recording: roles.RecordingProps = {
      start = rec.start,
      at = rec.at,
      to = rec.to,
      per = zoom,
      color = colour,
      bind = "position",
    }
    local width = math.max((rec.to and self:v(rec.to) or (vscroll + w / zoom)) - v0, 1 / zoom)
    plane:mark("recording", v0, y, width, height, recording)
  end
  -- The volume curve runs over the empty lane, never over clips, and only
  -- on the track the cursor is on: drawn on every track it ran along the
  -- clips' edges and made the notes harder to read, and the curve of a
  -- track is a thing to look at while working on that track (the others
  -- show an `A` in their header; `<leader>a` opens their lanes as rows).
  for _, l in ipairs(o.lanes) do
    if o.selected and height >= 2 and l.target == "volume" and l.point_count > 0 then
      curve(
        buf,
        0,
        y + 1,
        w,
        height - 1,
        lane_sampler(l.id, scroll, zoom, spans, nil, nil, self),
        {
          style = l.enabled and "Automation" or "Faint",
          color = colour,
          enabled = l.enabled,
          from = vscroll,
          per = zoom,
        }
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
  local zoom, scroll = self.geometry.zoom, self.scroll
  local beat = paw.cursor.beat
  local hw, tw = headers.width, timeline.width
  local on = paw.cursor.lane_id() == l.id
  local track = api.track_get(row.id)
  local hue = draw.track_hue(track, row.index)
  local style = on and "TrackHeaderSel" or "TrackHeader"
  lane_header(headers, y, lh, hue, style)
  headers:text(2, y, util.fit("↳ " .. paw.lanes.name(l), math.max(1, hw - 3)), style)
  local state = l.enabled and "read" or "bypass"
  headers:text(math.max(2, hw - #state - 1), y + 1, state, l.enabled and "Automation" or "FlagOff")
  local value = paw.lanes.format(l, paw.lanes.value_at(l, beat))
  headers:text(4, y + 1, util.fit(value, math.max(1, hw - #state - 5)), "TrackInfo")
  local vscroll = self:v(scroll)
  local function v(b: number): number
    return self:v(b)
  end
  local ground: roles.BeatsProps = {
    from = vscroll,
    per = zoom,
    style = on and hue.lane_sel or "Lane",
    tone = "auto",
    lines = bar_marks(lines),
  }
  self.plane:mark("beats", vscroll, y, tw / zoom, lh, ground)
  local o: CurveStyle = {
    points = {},
    style = l.enabled and "Automation" or "Faint",
    from = vscroll,
    v = v,
    per = zoom,
    color = draw.track_colour(track, row.index),
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
      local x0 = math.max(0, self:col(p[1]))
      local x1 = math.min(tw, list[i + 1] and self:col(list[i + 1][1]) or tw)
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
    curve(timeline, 0, y, tw, lh, l.point_count > 0 and lane_sampler(l.id, scroll, zoom, nil, lo, hi, self) or nil, o)
  end
  if not on then
    return
  end
  -- A selection on this lane: the stretch of time chosen.
  local selection = paw.keymap.selection()
  if selection then
    local x0 = math.max(0, self:col(selection.c0))
    local x1 = math.min(tw, self:col(selection.c1))
    if x1 > x0 then
      timeline:fill(x0, y, x1 - x0, lh, nil, "Visual")
    end
  end
  local x = self:col(beat)
  local cw = math.max(1, math.floor(paw.opt.grid * zoom))
  timeline:fill(x, y, cw, 1, nil, paw.keymap.mode == "x" and "CursorVisual" or "Cursor")
  timeline:fill(x, y + 1, cw, lh - 1, nil, "CursorTail")
end

--- Where each row is among the lines that the counts of `j` and `k` go
--- over, and the cursor's: rows of tracks, and the lane rows too in normal
--- mode while lanes are open (paw/cursor.tl `move_track`). A take lane and,
--- in other modes, a lane row is on no line.
local function counted_lines(L: Layout, cursor_track: integer, cursor_lane: integer): {Row: integer}, integer
  local line_of: {Row: integer} = {}
  local at: integer
  if paw.lanes.any_open() and paw.keymap.mode == "n" then
    local lines = paw.lanes.lines()
    local index: {string: integer} = {}
    for i, l in ipairs(lines) do
      index[l.track .. ":" .. (l.lane and tostring(l.lane) or "")] = i
    end
    for _, row in ipairs(L.rows) do
      if row.kind ~= "take" then
        line_of[row] = index[row.id .. ":" .. (row.lane and tostring(row.lane.id) or "")]
      end
    end
    at = cursor_track == 0 and #lines + 1
      or index[tostring(cursor_track) .. ":" .. (cursor_lane and tostring(cursor_lane) or "")]
  else
    for _, row in ipairs(L.rows) do
      if row.kind == "track" then
        line_of[row] = row.index
      end
    end
    at = paw.cursor.row()
  end
  return line_of, at
end

--- The track column (paw/trackcolumn.tl) on each line of each row shown.
function view:draw_column(column: Buf, L: Layout, cursor_track: integer, cursor_lane: integer)
  local line_of, at = counted_lines(L, cursor_track, cursor_lane)
  for _, row in ipairs(L.rows) do
    local line = line_of[row]
    local on = row.id == cursor_track
      and (row.kind == "track" and not cursor_lane or row.kind == "lane" and row.lane.id == cursor_lane)
    for k = 0, row.h - 1 do
      paw.trackcolumn.draw(
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
  local zoom = self.geometry.zoom
  local hw, tw = headers.width, timeline.width
  local beat = paw.cursor.beat
  headers:fill(0, y, hw, 2, " ", "TrackHeader")
  headers:text(2, y, util.fit("tempo", math.max(1, hw - 3)), "TrackHeader")
  headers:text(2, y + 1, util.fit(string.format("%g bpm", paw.time.tempo_at(beat)), math.max(1, hw - 3)), "TrackInfo")
  timeline:fill(0, y, tw, 2, " ", "Lane")
  for _, line in ipairs(lines) do
    if line.bar then
      timeline:fill(line.x, y, 1, 2, draw.g.bar, "LaneBar")
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
    return level(paw.time.tempo_at(self:beat((i + 0.5) / 2)))
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
      from = self:v(self.scroll),
      v = function(b: number): number return self:v(b) end,
      per = zoom,
      color = require("paw.theme").palette.accent,
    }
  )
  local x = self:col(beat)
  timeline:fill(x, y, math.max(1, math.floor(paw.opt.grid * zoom)), 1, nil, "Cursor")
end

--- One take lane: take `row.take` of every clip of the track that has that
--- many, over the clip's own stretch of time, lit where it is the one that
--- plays and faint where it is not: its name on the first row, and its
--- waveform or its notes on the rows under it. To look at: comping here
--- is `:take 2` over a selection, or a drag across the lane, with the
--- mouse in the terminal or the window. Returns the columns its names take,
--- for the playhead to keep their letters, and the columns its clips take,
--- for the playhead to keep what their bodies show.
function view:draw_take_row(headers: Buf, timeline: Buf, row: Row, lines: {GridLine}): {Span}, {Span}
  local y, k, h = row.y, row.take, row.h
  local zoom, vscroll = self.geometry.zoom, self:v(self.scroll)
  local hw, tw = headers.width, timeline.width
  local track = api.track_get(row.id)
  local hue = draw.track_hue(track, row.index)
  local colour = draw.track_colour(track, row.index)
  local names, covered: {Span}, {Span} = {}, {}
  headers:fill(0, y, hw, h, " ", "TrackHeader")
  for line = y, y + h - 1 do
    headers:text(0, line, "▏", hue.fg)
  end
  headers:text(2, y, util.fit("↳ take " .. k, math.max(1, hw - 3)), "TrackInfo")
  local ground: roles.BeatsProps = {
    from = vscroll, per = zoom, style = "TakeLane", tone = "take", lines = bar_marks(lines)
  }
  self.plane:mark("beats", vscroll, y, tw / zoom, h, ground)
  for _, clip in ipairs(api.clip_list(row.id)) do
    local takes = paw.takes.of(clip)
    local entry = takes and takes.list[k]
    if entry then
      local x0 = self:col(clip.start)
      local x1 = self:col(clip.start + clip.length)
      local cw = math.max(1, x1 - x0)
      if x0 < tw and x0 + cw > 0 then
        local on = takes.active == k
        local label = (on and (draw.g.play .. " ") or "") .. (entry.name or ("take " .. k))
        -- A clip of its own, with the take's notes or waveform in its body.
        local row_of = paw.frontend.take_rows(clip)
        local props: roles.ClipProps = {
          key = "take:" .. clip.id .. ":" .. k,
          id = clip.id,
          take = k,
          active = on or nil,
          name = entry.name,
          label = label,
          color = colour,
          midi = clip.kind ~= "audio",
          length = clip.length,
          per = zoom,
          content = row_of and row_of[k] and row_of[k].key,
          title_style = on and hue.title or "TakeLaneName",
          body_style = on and hue.body or "TakeLane",
        }
        track_parts.take_body(props, clip, k, props.content, colour, on, zoom)
        self.plane:mark("clip", self:v(clip.start), y, clip.length, h, props)
        local at = cw > 2 and 1 or 0
        names[#names + 1] = {x0 + at, x0 + at + math.min(api.str_width(label), cw - at)}
        covered[#covered + 1] = {x0, x0 + cw}
      end
    end
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

--- What a new project shows in place of tracks: how to begin.
local function welcome(buf: Buf)
  local lines: {{string, string}} = {
    {"o", "add a track"},
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

  -- One plain ground, so that the rule between the track headers and the
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

--- On an automation lane row the lane's own keys come first.
function view:subscope(): string | {string}
  return paw.cursor.lane_id() and "arrange.lane" or nil
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
--- headers, the timeline under the ruler (`lanes`) and the ruler row; the
--- layout, the columns a beat, the beats shown and the beat at the right
--- edge; the transport and `here`, which turns a beat of the song into the
--- window's time; the map of the time folds; the bar and beat lines; the
--- loop's columns (on or off) and the punch range's; the cursor's track
--- and lane.
local record Frame
  buf: Buf
  headers: Buf
  lanes: Buf
  ruler: Buf
  ruler2: Buf
  L: Layout
  zoom: number
  span: number
  last: number
  t: types.Transport
  here: function(beat: number): number
  tmap: TimeMap
  lines: {GridLine}
  loop: Span
  loop_off: Span
  punch: Span
  cursor_track: integer
  cursor_lane: integer
  --- The cursor's beat in this window's time, or nil when the current
  --- window is elsewhere in the song (`paw.scope.cursor_beat`).
  cursor_beat: number
  --- The spans of the clips of each track's row, and of the names of
  --- each take lane's, for the playhead.
  covered: {Row: {Span}}
  names_of: {Row: {Span}}
end

--- Keep the playhead in view while playing, and the cursor whenever it
--- moves; unless another window leads this one's time (`timebind`). Each
--- window follows them in its own time, and only while they are inside
--- the time it shows: a window inside a subproject stays in its bars
--- while the cursor or the playhead is elsewhere in the song.
local function follow(self: Arrange, F: Frame, led: boolean)
  local t, tmap, span, zoom = F.t, F.tmap, F.span, F.zoom
  local function ahead(beat: number): number
    return tmap.view(beat) - tmap.view(self.scroll)
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
  elseif beat and beat ~= self.seen_beat and not led then
    -- A jump aligns the cursor in the view's beats, through the folds.
    local jumped = paw.keymap.jump_serial ~= self.seen_jump
    local target = draw.jump_scroll(tmap.view(beat), tmap.view(self.scroll), span, zoom, jumped)
    if target then
      self.scroll = math.max(0, tmap.beat(target))
    elseif beat < self.scroll then
      self.scroll = paw.time.bar_floor(beat)
    elseif ahead(beat) >= span - 1 / zoom then
      local back = tmap.beat(tmap.view(beat) - span)
      local bar = paw.time.bar()
      self.scroll = math.max(0, math.ceil(back / bar + 1) * bar)
    end
  end
  self.seen_beat, self.seen_jump = beat, paw.keymap.jump_serial
end

--- True if the column `x` is in `span` (`{ from, to }`), when there is one.
local function within(span: Span, x: integer): boolean
  return span and x >= span[1] and x < span[2]
end

--- The style of a thing on the ruler at column `x`: in the punch range,
--- in the loop, in the loop that is off, or none of them.
local function ruler_style(F: Frame, x: integer, punch: string, loop: string, loop_off: string, plain: string): string
  if within(F.punch, x) then
    return punch
  elseif within(F.loop, x) then
    return loop
  elseif within(F.loop_off, x) then
    return loop_off
  end
  return plain
end

--- The ruler's corner over the headers: where the cursor is, at `beat`
--- of the window's time; nothing when it is outside that time.
local function ruler_corner(buf: Buf, hw: integer, beat: number)
  if hw < 12 or not beat then
    return
  end
  local pos = paw.scope.format(beat)
  if hw - 2 >= #pos + 5 then
    local label: contracts.LabelMark = {text = "cur", style = "RulerCornerLabel", font = "sans", tone = "text_3"}
    buf:mark("label", 1, 0, 3, 1, label)
    buf:text(5, 0, pos, "RulerCorner")
  else
    buf:text(1, 0, util.fit(pos, hw - 2), "RulerCorner")
  end
end

--- The loop's band on the ruler: bright while looping is on, dim while it
--- is off (the range stays in sight); then the punch range, in red over
--- the loop's amber where they meet. Only an on loop shades the lanes.
local function ruler_ranges(self: Arrange, F: Frame)
  local t, tw, ruler = F.t, F.L.tw, F.ruler
  if t.loop_end > t.loop_start then
    local x0, x1 = math.max(0, self:col(F.here(t.loop_start))), math.min(tw, self:col(F.here(t.loop_end)))
    if x1 > x0 then
      if t.loop_enabled then
        F.loop = {x0, x1}
        ruler:fill(x0, 0, x1 - x0, 1, nil, "RulerLoop")
      else
        F.loop_off = {x0, x1}
        ruler:fill(x0, 0, x1 - x0, 1, nil, "RulerLoopOff")
      end
    end
  end
  if t.punch_enabled and t.punch_end > t.punch_start then
    local x0, x1 = math.max(0, self:col(t.punch_start)), math.min(tw, self:col(t.punch_end))
    if x1 > x0 then
      F.punch = {x0, x1}
      ruler:fill(x0, 0, x1 - x0, 1, nil, "RulerPunch")
    end
  end
end

--- The bars' labels and the beats' ticks on the ruler. Bar numbers that
--- would run into each other when zoomed out are skipped. Gives where
--- each bar's label ends, by its column.
local function ruler_bars(self: Arrange, F: Frame): {integer: integer}
  local ruler, zoom = F.ruler, F.zoom
  local every = math.max(1, math.ceil(5 / (paw.time.bar(self.scroll) * zoom)))
  local free = 0 -- the first column a label has not taken
  local label_end: {integer: integer} = {}
  for _, line in ipairs(F.lines) do
    if line.bar then
      if (line.bar - 1) % every == 0 and line.x >= free then
        local style = ruler_style(F, line.x, "RulerPunch", "RulerLoop", "RulerLoopOffBar", "RulerBar")
        -- Its label: the parts of `paw.opt.barlabel` (paw/ruler.tl), in
        -- its room: up to a column before the next bar whose label shows.
        local x = line.x
        local room = math.max(1, math.floor(paw.time.bar(line.beat) * zoom * every) - 1)
        for _, piece in ipairs(paw.ruler.label(line.bar, line.beat, style, paw.cursor.beat, room)) do
          x = x + ruler:text(x, 0, piece[1], piece[2])
        end
        free, label_end[line.x] = x + 1, x
      end
    elseif zoom >= 2 and line.x >= free then
      local style = ruler_style(F, line.x, "RulerPunchTick", "RulerLoopTick", "RulerLoopOffTick", "RulerTick")
      ruler:text(line.x, 0, draw.g.tick, style)
    end
  end
  return label_end
end

--- The marks of the loop's and the punch range's edges on the ruler.
local function ruler_edges(self: Arrange, F: Frame)
  local g, t, tw, ruler = draw.g, F.t, F.L.tw, F.ruler
  if F.loop or F.loop_off then
    local start, finish = self:col(F.here(t.loop_start)), self:col(F.here(t.loop_end))
    if start >= 1 then
      ruler:text(start - 1, 0, g.loop_in, F.loop and "RulerLoopEdge" or "RulerLoopOffEdge")
    end
    -- The end's mark sits in the band's last cell, clear of the next bar's number.
    if finish >= 1 and finish <= tw then
      ruler:text(finish - 1, 0, g.loop_out, F.loop and "RulerLoopEdgeIn" or "RulerLoopOffEdge")
    end
  end
  if F.punch then
    local start, finish = self:col(t.punch_start), self:col(t.punch_end)
    if start >= 1 then
      ruler:text(start - 1, 0, g.punch_in, "RulerPunchEdge")
    end
    if finish >= 1 and finish <= tw then
      ruler:text(finish - 1, 0, g.punch_out, "RulerPunchEdge")
    end
  end
end

--- Tempo and signature changes on the ruler: a mark and the value, after
--- the bar number. A mark inside a time fold is folded away with it.
local function ruler_tempo_marks(self: Arrange, F: Frame, label_end: {integer: integer})
  local mark_end = -1
  for _, mark in ipairs(paw.tempo.marks(self.scroll, F.last)) do
    if not self:folded(mark.beat) then
      local x = self:col(mark.beat)
      if paw.tempo.is_bar_line(mark.beat) then
        x = label_end[x] or (x + #tostring(paw.time.bar_of(mark.beat)))
      end
      x = math.max(x, mark_end)
      mark_end = x + F.ruler:text(x, 0, (mark.kind == "tempo" and "▾" or "‖") .. mark.text, "RulerTempo") + 1
    end
  end
end

--- The bands of extensions under the ruler (`paw.frontend.bands`), a row
--- each: an entry with a length over its stretch, one without a flag where
--- it is, each in its colour with its name.
local function draw_bands(self: Arrange, F: Frame)
  local bands, lanes, y = F.L.bands, F.lanes, F.L.band_y
  if bands.rows == 0 then
    return
  end
  for row = 0, bands.rows - 1 do
    lanes:fill(0, y + row, lanes.width, 1, " ", "Ruler")
  end
  for _, e in ipairs(bands.entries) do
    local x0 = self:col(e.beat)
    local span = e.length > 0 and math.max(1, self:col(e.beat + e.length) - x0) or api.str_width(e.name) + 2
    if x0 < lanes.width and x0 + span > 0 then
      local box = lanes:sub(x0, y + e.row, span, 1)
      box:fill(0, 0, span, 1, " ", e.color ~= "" and draw.hue(e.color).pill or "RulerBar")
      box:text(0, 0, (e.length > 0 and draw.g.clip_start or "▾") .. e.name)
    end
  end
end

--- The ruler: where the cursor is in the corner; bars, beat ticks, the
--- loop and the punch range, the tempo's marks; under it the regions'
--- rows and a second row (`view.ruler2`), the bands of extensions and the
--- tempo lane.
local function draw_ruler(self: Arrange, F: Frame)
  local buf, L = F.buf, F.L
  local hw, tw = L.hw, L.tw
  buf:fill(0, 0, hw - 1, L.ruler_rows, " ", "Ruler")
  F.ruler = buf:sub(hw, 0, tw, 1)
  F.ruler:fill(0, 0, tw, 1, " ", "Ruler")
  ruler_corner(buf, hw, F.cursor_beat)
  ruler_ranges(self, F)
  F.lines = grid_lines(self, tw)
  local label_end = ruler_bars(self, F)
  ruler_edges(self, F)
  ruler_tempo_marks(self, F, label_end)
  if L.band_y > 1 then
    -- The lanes of markers and regions under the ruler (paw/ruler.tl).
    F.ruler2 = buf:sub(hw, 1, tw, L.band_y - 1)
    F.ruler2:fill(0, 0, tw, L.band_y - 1, " ", "Ruler")
    paw.ruler.draw_lanes(
      F.ruler2,
      function(beat: number): integer return self:col(beat) end,
      self.scroll,
      F.last - self.scroll,
      F.tmap.spans
    )
  end
  draw_bands(self, F)
  if L.tempo_rows > 0 then
    self:draw_tempo_row(F.headers, F.lanes, L.ruler_rows - L.tempo_rows, F.lines)
  end
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
  local zoom = F.zoom
  local x = self:col(F.cursor_beat)
  local cw = math.max(1, math.floor(paw.opt.grid * zoom))
  self.caret = {x = F.lanes.x + math.max(0, math.floor(x)), y = F.lanes.y + y, w = cw, h = 1}
  local mode = paw.keymap.mode
  F.lanes:fill(x, y, cw, 1, nil, mode == "x" and "CursorVisual" or mode == "i" and "InsertCursor" or "Cursor")
  if h > 1 then
    F.lanes:fill(x, y + 1, cw, h - 1, nil, "CursorTail")
  end
end

-- Overviews -------------------------------------------------------------------------

--- The columns where a track has clips in view, between the beats `from`
--- and `to` when they are given: one span for each piece of a clip that
--- the time folds leave.
local function clip_columns(self: Arrange, id: integer, w: integer, from?: number, to?: number): {Span}
  local first, last = self.scroll, self:beat(w)
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
    for _, piece in ipairs(self:unfolded(a, b)) do
      local x0, x1 = math.max(0, self:col(piece[1])), math.min(w, self:col(piece[2]))
      if x1 > x0 then
        out[#out + 1] = {x0, x1}
      end
    end
  end
  return out
end

--- Every track inside a group, at any depth.
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

--- The columns where any track inside a group has clips in view.
local function group_columns(self: Arrange, group: integer, w: integer): {Span}
  local spans: {Span} = {}
  for _, id in ipairs(inside(group)) do
    for _, span in ipairs(clip_columns(self, id, w)) do
      spans[#spans + 1] = span
    end
  end
  return spans
end

--- A line of a folded group for one of its members: the member's name,
--- then its clips. A clip that is all in one stretch of the view shows
--- its notes in one line; a clip that a time fold cuts, and a group
--- inside the group, show the overview.
local function member_line(self: Arrange, buf: Buf, y: integer, id: integer)
  local w = buf.width
  local hue = draw.track_hue(api.track_get(id))
  if paw.groups.is_group(id) then
    overview(buf, y, group_columns(self, id, w), hue.fg)
  else
    for _, clip in ipairs(api.clip_list(id, self.scroll, self:beat(w))) do
      local finish = clip.start + clip.length
      local x0, x1 = self:col(clip.start), self:col(finish)
      local whole = x1 > x0 and #self:unfolded(clip.start, finish) == 1
      local line = whole and track_parts.notes_line(clip, x1 - x0, self.geometry.zoom)
      if line then
        buf:text(x0, y, line, hue.fg)
      else
        overview(buf, y, clip_columns(self, id, w, clip.start, finish), hue.fg)
      end
    end
  end
  -- From the second column, as a clip's name: the first is where the
  -- playhead and a clip's start stand.
  buf:text(1, y, track_name(id, "name") .. " ", hue.title)
end

--- What a group's row shows of its tracks: on its first line, the
--- overview where any of them has a clip. A folded group lists its
--- members on its other lines, one a line; when they do not fit, the
--- last line says how many more there are.
local function group_overview(self: Arrange, F: Frame, row: Row, hue: Hue)
  local members = paw.groups.members(row.id)
  if #members == 0 then
    return
  end
  local buf = F.lanes
  overview(buf, row.y, group_columns(self, row.id, buf.width), hue.fg)
  if not paw.groups.folded(row.id) then
    return
  end
  local lines = row.h - 1
  local shown = #members > lines and lines - 1 or #members
  for i = 1, shown do
    member_line(self, buf, row.y + i, members[i])
  end
  if shown < #members and lines > 0 then
    buf:text(1, row.y + lines, "+" .. (#members - shown) .. " more", "Faint")
  end
end

--- The rows of the timeline: lanes and takes first, then each track's
--- header and clips, and the cursor on its track. The timeline under the
--- ruler is a plane, beats along and the view's lines down: a window
--- paints the clips and the lines on it where they are between cells.
--- Lines, not tracks, go down, because rows of other kinds (take lanes,
--- automation lanes) have heights of their own, and a drag goes across
--- all of them in one domain.
local function draw_rows(self: Arrange, F: Frame)
  local L, zoom, t = F.L, F.zoom, F.t
  self.plane = F.buf:plane(
    L.hw,
    L.ruler_rows,
    L.tw,
    math.max(1, L.master.y - L.ruler_rows),
    {
      key = "timeline",
      x = {domain = "beat", from = self:v(self.scroll), per = zoom},
      y = {domain = "line", from = L.ruler_rows, per = 1},
    }
  ) as RolesModule.Plane
  local marks: {BeatLine} = {}
  for i, line in ipairs(F.lines) do
    marks[i] = {line.v, line.bar and true or false}
  end
  local loop: {number, number}
  if F.loop then
    loop = {self:v(F.here(t.loop_start)), self:v(F.here(t.loop_end))}
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
  end
  for _, row in ipairs(L.rows) do
    if row.kind == "track" then
      local track = api.track_get(row.id)
      local selected = row.id == F.cursor_track
      local automation = api.lane_list(row.id)
      local hue = draw.track_hue(track, row.index)
      local on_track = selected and not F.cursor_lane
      self.flags = track_parts.header(
        F.headers, row.y, row.h, track, row.index, on_track, automation, hue, self.column_width
      )
      -- With its lanes open as rows, a track's curve is drawn there, not here.
      F.covered[row] = track_lane(
        self,
        F.lanes,
        row,
        track,
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
        group_overview(self, F, row, hue)
      end
      if on_track then
        cursor_cell(self, F, row.y, row.h)
      end
    end
  end
end

--- The selection of visual mode: whole tracks, or a stretch of time on some.
local function draw_selection(self: Arrange, F: Frame)
  local selection = paw.keymap.selection()
  if not selection or F.cursor_lane then
    return
  end
  local L = F.L
  for _, row in ipairs(L.rows) do
    if row.kind == "track" and row.index >= selection.r0 and row.index <= selection.r1 then
      if selection.kind == "line" then
        F.buf:fill(0, row.y, L.hw - 1, row.h, nil, "Visual")
        F.lanes:fill(0, row.y, L.tw, row.h, nil, "Visual")
      else
        local x0 = math.max(0, self:col(selection.c0))
        local x1 = math.min(L.tw, self:col(selection.c1))
        if x1 > x0 then
          F.lanes:fill(x0, row.y, x1 - x0, row.h, nil, "Visual")
        end
      end
    end
  end
end

--- The time outside a scope, dimmed: it is not part of what the tab shows.
local function draw_scope_outside(self: Arrange, F: Frame, scope_from: number, scope_to: number)
  if not scope_from then
    return
  end
  local L = F.L
  local tw, top, rows = L.tw, L.ruler_rows, L.master.y - L.ruler_rows
  local a, b = math.max(0, self:col(scope_from)), math.min(tw, self:col(scope_to))
  if a > 0 then
    F.lanes:fill(0, top, a, rows, nil, "ScopeOutside")
  end
  if b < tw then
    F.lanes:fill(math.max(0, b), top, tw - math.max(0, b), rows, nil, "ScopeOutside")
  end
end

--- Each time fold: one narrow column with its name and its bars, on the
--- ruler and down the tracks (paw/folds.tl), and the cursor on it.
local function draw_time_folds(self: Arrange, F: Frame)
  local L, cursor = F.L, paw.cursor
  for _, s in ipairs(F.tmap.spans) do
    local x0 = self:col(s.from)
    if x0 < L.tw and x0 + s.cells > 0 then
      local label = util.fit(s.label, math.max(1, s.cells - 1))
      F.ruler:fill(x0, 0, s.cells, 1, " ", "TimeFold")
      F.ruler:text(x0 + 1, 0, label, "TimeFold")
      F.lanes:fill(x0, L.ruler_rows, s.cells, L.master.y - L.ruler_rows, " ", "TimeFoldBody")
      for _, row in ipairs(L.rows) do
        if row.kind == "track" then
          F.lanes:text(x0 + 1, row.y, label, "TimeFold")
        end
      end
      if cursor.beat >= s.from - 1e-9 and cursor.beat < s.to - 1e-9 and F.cursor_track ~= 0 then
        for _, row in ipairs(L.rows) do
          if row.kind == "track" and row.id == F.cursor_track then
            F.lanes:fill(x0, row.y, s.cells, 1, nil, paw.keymap.mode == "x" and "CursorVisual" or "Cursor")
          end
        end
      end
    end
  end
end

--- The top edge of a closed block fold, `width` cells wide: `╭▸`, its
--- name, its bars and its tracks, then `─` to its end. Where it does not
--- fit, the tracks go first (their names, then how many), then the bars;
--- the name stays. A name made of the tracks (the default, `Piano, Pad
--- 9-24`) does not name them again.
local function block_top(f: FoldsModule.Fold, width: integer): string
  local g = draw.g
  local head = g.tl .. g.closed .. " "
  local sep = " " .. g.dot .. " "
  local name = paw.folds.name(f)
  local n = paw.folds.bars(f)
  local bars = n .. (n == 1 and " bar" or " bars")
  local names = paw.folds.track_names(f)
  local choices: {string} = {}
  if name:sub(1, #names) ~= names then
    local count = paw.folds.count(f)
    choices[#choices + 1] = name .. sep .. bars .. sep .. names
    choices[#choices + 1] = name .. sep .. bars .. sep .. count .. (count == 1 and " track" or " tracks")
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

--- Each closed block fold: a frame over the rows of its tracks and its
--- time (paw/folds.tl). The top edge has its name, its bars and its
--- tracks; each track has a line of overview `━` where it has clips; the
--- bottom edge has the keys, when the block is more than one track high.
--- The other tracks show that time as usual. The cursor on the block
--- marks its top edge: the block is one row and one step for the cursor.
local function draw_block_folds(self: Arrange, F: Frame)
  local L, g = F.L, draw.g
  for _, f in ipairs(paw.folds.blocks()) do
    local x0 = math.max(0, self:col(f.from))
    local x1 = math.min(L.tw, self:col(f.to))
    if x1 > x0 then
      local member: {integer: boolean} = {}
      for _, id in ipairs(f.tracks) do
        member[id] = true
      end
      -- Its rows, and the line of overview of each of its tracks: the
      -- first line of the track's row, or the next one under the top edge.
      local top, bottom: integer, integer
      local lines: {integer: integer} = {}
      for _, row in ipairs(L.rows) do
        if member[row.id] then
          F.lanes:fill(x0, row.y, x1 - x0, row.h, " ", "TimeFoldBody")
          top = top or row.y
          bottom = row.y + row.h - 1
          if row.kind == "track" then
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
          local spans = clip_columns(self, id, x1, f.from, f.to)
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
          local hint = #f.tracks > 1 and (" za opens " .. g.dot .. " znn enters ") or ""
          local edge = g.bl .. g.h .. hint
          F.lanes:text(x0, bottom, edge .. g.h:rep(math.max(0, x1 - x0 - api.str_width(edge))), "TimeFold")
        end
        local beat = F.cursor_beat
        local here = beat and beat >= f.from - 1e-9 and beat < f.to - 1e-9
        if here and member[F.cursor_track] then
          F.lanes:fill(x0, top, x1 - x0, 1, nil, paw.keymap.mode == "x" and "CursorVisual" or "Cursor")
        end
      end
    end
  end
end

--- Under the last track: the welcome of a new project, or, with room left,
--- how to add a track (a button in a window, which a click opens the kinds
--- of track from).
local function draw_below(F: Frame)
  local L = F.L
  local mst = L.master
  if #L.tracks == 0 then
    welcome(F.buf:sub(0, L.ruler_rows, F.buf.width, mst.y - L.ruler_rows))
  elseif mst.y - L.used >= 2 then
    local wide = F.headers.width + 1 >= 16
    F.headers:text(wide and 4 or 2, L.used, "o", "EmptyKey")
    local at = wide and 6 or 4
    local button: contracts.ButtonMark = {
      text = "new track",
      words = "New track",
      icon = "plus",
      style = "Empty",
      quiet = true,
      label = "new track",
    }
    F.headers:mark("button", at, L.used, math.max(9, math.min(13, (F.headers.width + 1) - 1 - at)), 1, button)
  end
end

--- The master track, pinned to the bottom, with its level on both sides.
--- The cursor reaches it with `j` from the last track, and `/master`.
--- Beside it, its automation when it has some; else nothing.
local function draw_master(self: Arrange, F: Frame)
  local mst, zoom = F.L.master, F.zoom
  local master = api.track_get(0)
  local on_master = F.cursor_track == 0
  track_parts.header(
    F.headers, mst.y, mst.h, master, nil, on_master, api.lane_list(0), draw.track_hue(master), self.column_width
  )
  if on_master and F.cursor_beat then
    local cw = math.max(1, math.floor(paw.opt.grid * zoom))
    F.lanes:fill(self:col(F.cursor_beat), mst.y, cw, 1, nil, paw.keymap.mode == "x" and "CursorVisual" or "Cursor")
  end
  for _, l in ipairs(api.lane_list(0)) do
    if l.target == "volume" and l.point_count > 0 then
      curve(
        F.lanes,
        0,
        mst.y,
        F.L.tw,
        mst.h,
        lane_sampler(l.id, self.scroll, zoom, nil, nil, nil, self),
        {
          style = l.enabled and "Automation" or "Faint",
          color = draw.track_colour(master),
          enabled = l.enabled,
          from = self:v(self.scroll),
          per = zoom,
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
    ruler2 = F.ruler2,
    lanes = F.buf:sub(L.hw, L.ruler_rows, L.tw, L.master.y - L.ruler_rows),
    x = function(beat: number): integer return self:col(beat) end,
    scroll = self.scroll,
    zoom = F.zoom,
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
  if #F.tmap.spans > 0 then
    jumps = {}
    for i, s in ipairs(F.tmap.spans) do
      jumps[i] = {paw.time.song_beat(s.from), paw.time.song_beat(s.to), s.width}
    end
  end
  -- A beat of the window is this many of the song's: 1, or another
  -- number in a subproject with a tempo of its own.
  local rate = paw.time.song_beat(self.scroll + 1) - paw.time.song_beat(self.scroll)
  local playhead: contracts.PlayheadMark = {
    at = t.position,
    -- In the song's beats, as the playhead is.
    from = paw.time.song_beat(self:v(self.scroll)),
    jumps = jumps,
    per = F.zoom / rate,
    lo = 0,
    hi = 1e12,
    spans = spans_at(self:col(F.here(t.position))),
    spans_at = spans_at,
    bind = "position",
  }
  F.buf:mark("playhead", L.hw, 0, L.tw, L.master.y, playhead)
end

--- With lanes open, the counts at the left count lane rows in normal mode
--- and tracks after an operator (`counted_lines`).
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
  local tmap = paw.folds.time_map(zoom)
  self.tmap = tmap
  local fold_ground: {{number}} = {}
  for i, s in ipairs(tmap.spans) do
    fold_ground[i] = {s.from, s.to, s.cells}
  end
  self.fold_ground = fold_ground
  local F: Frame = {
    buf = buf,
    L = L,
    zoom = zoom,
    span = tw / zoom,
    t = paw.ui.transport(),
    -- In a subproject, a beat of the song (the playhead's) is `here(beat)`
    -- in the window's time (paw.time).
    here = paw.time.local_beat,
    tmap = tmap,
    cursor_track = paw.cursor.track_id(),
    cursor_lane = paw.cursor.lane_id(),
    cursor_beat = paw.scope.cursor_beat(ctx.win),
  }
  follow(self, F, ctx.follower)
  -- In a scope with time, the view starts no earlier than the bar it starts in.
  local scope_from, scope_to = paw.scope.span()
  self.scroll = math.max(scope_from and paw.time.bar_floor(scope_from) or 0, self.scroll)
  self.geometry = {hw = hw, th = L.th, rows = #L.rows, zoom = zoom, span = F.span, layout = L}
  -- The beat at the right edge of the timeline.
  F.last = self:beat(tw)
  -- What this window shows, in the song's beats, comes first: the chord
  -- reading there, and the bakes of the stretched clips there.
  local origin = paw.time.origin()
  local shown = {0}
  for _, row in ipairs(L.rows) do
    if row.kind == "track" then
      shown[#shown + 1] = row.id
    end
  end
  derived.visible(ctx.win and tostring(ctx.win.id) or "arrange", self.scroll + origin, F.last + origin, shown)

  -- All of it takes the pointer, in both frontends (paw/views/arrange_mouse.tl).
  buf:hit(0, 0, w, h, {kind = "arrange"})
  -- The rule between the headers and the timeline, from top to bottom.
  buf:fill(hw - 1, 0, 1, h, draw.g.rule, "Rule")
  -- The track column at the left, then the headers. Where the chips are,
  -- for the pointer, is in the view's columns.
  local cw = L.column.width
  self.column_width = cw
  local column = cw > 0 and buf:sub(0, 0, cw, h) or nil
  F.headers, F.lanes = buf:sub(cw, 0, hw - 1 - cw, h), buf:sub(hw, 0, tw, h)
  buf:fill(0, 0, hw - 1, h, " ", "TrackHeader")
  draw_ruler(self, F)
  draw_rows(self, F)
  if column then
    self:draw_column(column, L, F.cursor_track, F.cursor_lane)
  end
  draw_selection(self, F)
  draw_scope_outside(self, F, scope_from, scope_to)
  draw_time_folds(self, F)
  draw_block_folds(self, F)
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
  local m = time_map(self)
  self.scroll = math.max(0, m.beat(m.view(paw.cursor.beat) - g.span / 2))
  api.ui_redraw()
end

--- Scroll so that the cursor is at the left margin (`paw.opt.jumpmargin`)
--- or, with `right`, at the right edge of the timeline.
function view:place(right?: boolean)
  local g = self.geometry
  if not g then
    return
  end
  local at = right and g.span - 1 / g.zoom or paw.opt.jumpmargin / g.zoom
  local m = time_map(self)
  self.scroll = math.max(0, m.beat(m.view(paw.cursor.beat) - at))
  api.ui_redraw()
end

--- Scroll by bars without moving the cursor.
function view:scroll_by(bars: number)
  self.scroll = math.max(0, self.scroll + bars * paw.time.bar(self.scroll))
  -- A time fold is one step: the scroll does not stop inside one.
  for _, s in ipairs(time_map(self).spans) do
    if self.scroll > s.from and self.scroll < s.to then
      self.scroll = bars > 0 and s.to or s.from
    end
  end
  api.ui_redraw()
end

-- What modal editing works on: rows are positions in the track list.
view.grid = {
  get = function(): number, number return paw.cursor.row() or 1, paw.cursor.beat end,
  set = function(row: number, col: number)
    local list = paw.groups.rows()
    local id = list[math.floor(util.clamp(row, 1, #list))]
    -- The row after the last track is the master's.
    if row > #list and paw.cursor.master_reachable() then
      id = 0
    end
    -- Staying on the same track keeps the cursor on the lane row it is on.
    if #list > 0 and id ~= paw.cursor.track_id() then
      paw.cursor.set_track(id)
    end
    paw.cursor.set_beat(col)
  end,
  step = function(): number return paw.opt.grid end,
  -- A mark stays with its track when tracks are moved around.
  mark = function(): contracts.GridMark return {track = paw.cursor.track_id(), beat = paw.cursor.beat} end,
  jump = function(pos: contracts.GridMark)
    if pos.track and pcall(api.track_get, pos.track) then
      paw.cursor.set_track(pos.track)
    end
    paw.cursor.set_beat(pos.beat)
  end,
  -- Clips by name where they start, and tracks by name at the cursor's beat.
  search = function(text: string): {contracts.GridHit}
    local wanted = text:lower()
    local hits: {contracts.GridHit} = {}
    for row, id in ipairs(paw.groups.rows()) do
      if track_name(id, "name"):lower():find(wanted, 1, true) then
        hits[#hits + 1] = {row = row, col = paw.cursor.beat}
      end
      for _, clip in ipairs(api.clip_list(id)) do
        if clip.name:lower():find(wanted, 1, true) then
          hits[#hits + 1] = {row = row, col = clip.start}
        end
      end
    end
    if track_name(0, "name"):lower():find(wanted, 1, true) then
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
  return playing and (position < self.scroll or self:x(position) >= g.span * g.zoom)
end

paw.ui.view("arrange", view)
return Arrange
