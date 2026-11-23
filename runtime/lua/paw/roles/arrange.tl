-- The roles of the arrange view (paw/views/arrange.tl): its clips, the
-- ground of each row of its timeline with the bars and the loop, and the
-- meters across a header's row. Each draws in cells as the terminal always
-- drew it; a window paints them where they are between cells
-- (crates/paw-gui/src/timeline.rs): a clip with its notes or its waveform,
-- its fades and warp markers, lines at the exact beat.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. The module
-- gives the record of each role's props, which the view marks with.
local api = require("paw.api")
local type contracts = require("paw.contracts")
local type Buf = require("paw.buf")

local type Style = contracts.Style

local role = paw.roles.define
local draw = paw.draw
local util = paw.util

--- The props of a `clip` (see the role below).
local record ClipProps is contracts.MarkProps
  id: integer
  name: string
  label: string
  mark: string
  color: string
  midi: boolean
  muted: boolean
  current: boolean
  chosen: boolean
  offline: boolean
  length: number
  per: number
  repeats: {number}
  warps: {number}
  moves: {number | boolean}
  fade_in: number
  fade_out: number
  gain: number
  gain_line: boolean
  cut_in: number
  cut_out: number
  content: string
  ghost: boolean
  nest: boolean
  take: integer
  active: boolean
  title_style: Style
  body_style: Style
  body: function(buf: contracts.Buf, props: ClipProps)
end

--- A line of a row's ground: `{ beat, bar }`, a bar's line when `bar`.
local type BeatLine = {number, boolean}

--- The props of `beats`.
local record BeatsProps is contracts.MarkProps
  from: number
  per: number
  style: Style
  tone: string
  loop: {number, number}
  lines: {BeatLine}
  beats: boolean
  color: string
  selected: boolean
  index: integer
end

--- The props of `curve`.
local record CurveProps is contracts.MarkProps
  values: {number | boolean}
  points: {{number, number}}
  from: number
  per: number
  color: string
  enabled: boolean
  draw: function(buf: contracts.Buf)
end

--- The props of `trackhead`.
local record TrackheadProps is contracts.MarkProps
  style: Style
  stripe: string
  stripe_style: Style
  color: string
  selected: boolean
end

--- The props of `recording`.
local record RecordingProps is contracts.MarkProps
  start: number
  at: number
  to: number
  per: number
  color: string
end

--- The props of `hmeter`.
local record HmeterProps is contracts.MarkProps
  levels: {number}
  hold: number
  clipped: boolean
  stereo: boolean
  at: number
end

local record M
  type ClipProps = ClipProps
  type BeatLine = BeatLine
  type BeatsProps = BeatsProps
  type CurveProps = CurveProps
  type TrackheadProps = TrackheadProps
  type RecordingProps = RecordingProps
  type HmeterProps = HmeterProps
end

-- The fewest columns of a clip's label that its take mark leaves.
local LABEL_ROOM = 4

--- What a clip's row says in `room` columns: its label, and its take mark
--- after it (`riff ‹2/4›`). Where both do not fit, the label keeps its room:
--- the mark gives only the take that plays (`rif…‹2›`), and goes away where
--- it would leave fewer than LABEL_ROOM columns of the label.
local function title(p: ClipProps, room: integer): string
  local label = p.label or p.name or ""
  if not p.mark then
    return label
  end
  local full = label .. " ‹" .. p.mark .. "›"
  if api.str_width(full) <= room then
    return full
  end
  local short = "‹" .. p.mark:match("^[^/]*") .. "›"
  local left = room - api.str_width(short)
  if left < math.min(api.str_width(label), LABEL_ROOM) then
    return label
  end
  -- A space between them where the label is whole and leaves one.
  local cut = util.fit(label, left):gsub("%s+$", "")
  return cut .. (api.str_width(cut) < left and " " or "") .. short
end

--- Where a beat falls in a role marked from beat `from`, `per` columns a
--- beat: the column a terminal shows it on.
local function column(p: BeatsProps, beat: number): integer
  return math.floor((beat - (p.from or 0)) * (p.per or 1) + 0.5)
end

--- The column of a place `at` beats into a clip.
local function into(p: ClipProps, at: number): integer
  return math.floor(at * p.per + 0.5)
end

--- A clip on the timeline: a row with its `label` (its name, how it is
--- stretched) and its take `mark` ("2/4": `label ‹2/4›`, or `lab…‹2›`
--- where that does not fit) over its body. On the name row only, so that
--- each cell of the body shows exactly its time: a hairline where it
--- starts, a mark on each warp marker (`warps`, beats from its start),
--- and after the label a notch where each repeat of a looped clip begins
--- (`repeats`, the same) and a small curve of the controller that moves
--- most in a MIDI clip (`moves`, its height from 0 to 1 in each column,
--- false before its first move). `per` is
--- columns a beat. The terminal draws the row in `title_style` and the
--- body in `body_style`, and `body(buf, props)` draws what is in the body (notes,
--- a waveform). A window paints it in `color` (its track's), lit when
--- `current` (the cursor's) or `chosen`, faint when `muted`; its notes or
--- its waveform from `content` (`midi` or not: `paw.frontend.preview`,
--- `paw.frontend.peaks`, fetched again when the key changes); an audio
--- clip's fades (`fade_in`, `fade_out`, beats) and `gain` (dB). Where the
--- window's scope cuts it (`cut_in`, `cut_out`, beats from its start), a
--- `‹` after the cut at its start, its name beside it, and a `›` before
--- the cut at its end. `ghost`
--- is where a drag will put one. With `take` it is that take of the clip
--- in a take lane (`paw.frontend.take_preview`), lit when `active`. With
--- `nest` it is a block of a subproject: a frame around it (`╭⧉ Bridge
--- ──╮`, its edges down the body), and in its body the notes that the
--- subproject plays there.
role(
  "clip",
  {
    props = {
      id = "clip id",
      name = "string",
      label = "string",
      mark = "string",
      color = "#rrggbb",
      midi = "boolean",
      muted = "boolean",
      current = "boolean",
      chosen = "boolean",
      offline = "boolean",
      length = "beats",
      per = "columns a beat",
      repeats = "list of beats",
      warps = "list of beats",
      moves = "list of numbers 0..1 or false",
      fade_in = "beats",
      fade_out = "beats",
      gain = "dB",
      cut_in = "beats",
      cut_out = "beats",
      content = "key of what it shows",
      ghost = "boolean",
      nest = "boolean",
      take = "number",
      active = "boolean",
      title_style = "highlight group",
      body_style = "highlight group",
    },
    cells = function(whole: contracts.Buf, p: ClipProps)
      local g = draw.g
      local buf = whole as Buf
      local w, h = buf.width, buf.height
      -- Cut (by a scope's edge or a time fold), only the part between the
      -- cuts is drawn: the buffer keeps its place and draws on fewer cells.
      if p.cut_in or p.cut_out then
        local a = p.cut_in and into(p, p.cut_in) or 0
        local b = p.cut_out and into(p, p.cut_out) or w
        local cut = buf:sub(0, 0, w, h)
        local left, right = math.max(cut.cx, cut.x + a), math.min(cut.cx + cut.cw, cut.x + b)
        cut.cx, cut.cw = left, math.max(0, right - left)
        buf = cut
      end
      if p.ghost then
        buf:fill(0, 0, w, h, nil, "MouseGhost")
        if p.name then
          buf:text(1, 0, (util.fit(p.name, math.max(0, w - 1)):gsub("%s+$", "")), "MouseGhost")
        end
        return
      end
      buf:fill(0, 0, w, 1, " ", p.title_style)
      if h >= 2 then
        buf:fill(0, 1, w, h - 1, " ", p.body_style)
        if p.body then
          p.body(buf, p)
        end
      end
      local x0 = w > 2 and 1 or 0
      local text = title(p, w - x0)
      buf:text(x0, 0, text)
      -- The marks in the clip are on the name row, as the hairline is, so
      -- that each cell of the body shows the notes or the sound of exactly
      -- its time. The curve and the notches are after the label, so that
      -- it stays whole.
      local free = x0 + api.str_width(text)
      if p.nest and w > 2 and free + 1 < w - 1 then
        buf:fill(free + 1, 0, w - 1 - (free + 1), 1, g.h, "ClipEdge")
      end
      -- The controller moves of a MIDI clip: a small curve, a cell's
      -- height in each column, a space after the label.
      for x = free + 1, w - 1 do
        local height = p.moves and p.moves[x + 1]
        if height is number then
          buf:text(x, 0, g.eighths[math.floor(util.clamp(height * 8 + 0.5, 1, 8))])
        end
      end
      -- A notch where each repeat of a looped clip begins.
      for _, at in ipairs(p.repeats or {}) do
        local x = into(p, at)
        if x >= free and x < w then
          buf:fill(x, 0, 1, 1, g.step, "ClipEdge")
        end
      end
      -- A warp marker, where a moment of the file is pinned to a beat. It
      -- is a thing to move, so it stays in view over a letter of the label.
      for _, at in ipairs(p.warps or {}) do
        local x = into(p, at)
        if x > 0 and x < w then
          buf:fill(x, 0, 1, 1, g.tick, "ClipWarp")
        end
      end
      -- A hairline where the clip starts, so that clips side by side stay
      -- apart.
      buf:fill(0, 0, 1, 1, g.clip_start, "ClipEdge")
      -- A block of a subproject has a frame around all of it: `╭⧉ Bridge
      -- ──╮` on the name row (its line drawn before the notches, which
      -- stay on it), and its edges down the body in its first and last
      -- columns.
      if p.nest and w > 2 then
        buf:text(0, 0, g.tl, "ClipEdge")
        buf:text(w - 1, 0, g.tr, "ClipEdge")
        if h >= 2 then
          buf:fill(0, 1, 1, h - 1, g.v, "ClipEdge")
          buf:fill(w - 1, 1, 1, h - 1, g.v, "ClipEdge")
        end
      end
      -- Where a scope cuts it: `‹` and the name where the scope starts (the
      -- start of the clip is out of sight), `›` where it ends.
      if p.cut_in then
        local x = into(p, p.cut_in)
        if x >= 0 and x < w then
          buf:text(x, 0, "‹", "ClipEdge")
          local room = math.max(0, w - x - 2)
          if room > 0 then
            buf:text(x + 1, 0, util.fit(title(p, room), room), p.title_style)
          end
        end
      end
      if p.cut_out then
        local x = into(p, p.cut_out) - 1
        if x >= 0 and x < w then
          buf:text(x, 0, "›", "ClipEdge")
        end
      end
    end,
  } as contracts.Role<ClipProps>
)

--- The ground of a row of a timeline, `from` the beat at its left edge and
--- `per` columns a beat: in `style`, the `loop` (`{ start, end }`, beats)
--- shaded, a line on each of `lines` (`{ beat, bar }` each: a bar's when
--- `bar`), beats' lines only with `beats`. A window paints it by `tone`
--- ("lane", "take", "auto"), a track's lane tinted with `color` when
--- `selected`, every other row (`index`) a little lighter.
role(
  "beats",
  {
    props = {
      from = "beat at the left edge",
      per = "columns a beat",
      style = "highlight group",
      tone = "lane | take | auto",
      loop = "{ start, end }",
      lines = "list of { beat, bar }",
      beats = "boolean",
      color = "#rrggbb",
      selected = "boolean",
      index = "number",
    },
    cells = function(buf: contracts.Buf, p: BeatsProps)
      local g = draw.g
      local w, h = buf.width, buf.height
      buf:fill(0, 0, w, h, " ", p.style)
      if p.loop then
        local x0, x1 = math.max(0, column(p, p.loop[1])), math.min(w, column(p, p.loop[2]))
        if x1 > x0 then
          buf:fill(x0, 0, x1 - x0, h, nil, "LaneLoop")
        end
      end
      for _, line in ipairs(p.lines or {}) do
        local x = column(p, line[1])
        if line[2] then
          buf:fill(x, 0, 1, h, g.bar, "LaneBar")
        elseif p.beats then
          buf:fill(x, 0, 1, h, g.beat, "LaneBeat")
        end
      end
    end,
  } as contracts.Role<BeatsProps>
)

--- A curve over a stretch of time (an automation lane, the tempo map):
--- `values`, its height from 0 at the bottom to 1 at the top in the
--- middle of each column (false where it is not drawn), and `points`
--- (`{ beat, height }` each) marked on it, `from` the beat at the left edge
--- and `per` columns a beat. `draw(buf)` draws it in cells (the curve in
--- line characters, the points as diamonds). A window draws a line through
--- the values and a dot on each point, in `color` (its track's), grey when
--- not `enabled`.
role(
  "curve",
  {
    props = {
      values = "list of numbers 0..1 or false",
      points = "list of { beat, height }",
      from = "beat at the left edge",
      per = "columns a beat",
      color = "#rrggbb",
      enabled = "boolean",
    },
    cells = function(buf: contracts.Buf, p: CurveProps)
      if p.draw then
        p.draw(buf)
      end
    end,
  } as contracts.Role<CurveProps>
)

--- A track's header: its ground in `style`, with a stripe (`stripe`, a
--- glyph in `stripe_style`) down its left. A window paints a panel, lighter
--- when `selected`, with a stripe of `color` and a line under it, whose
--- bottom edge a drag makes taller or shorter.
role(
  "trackhead",
  {
    props = {
      style = "highlight group",
      stripe = "glyph",
      stripe_style = "highlight group",
      color = "#rrggbb",
      selected = "boolean",
    },
    cells = function(buf: contracts.Buf, p: TrackheadProps)
      buf:fill(0, 0, buf.width, buf.height, " ", p.style)
      for row = 0, buf.height - 1 do
        buf:text(0, row, p.stripe, p.stripe_style)
      end
    end,
  } as contracts.Role<TrackheadProps>
)

--- A take being recorded on an armed track, from `start` (a beat) to
--- `at`, the playhead, in `color`; no further than `to` when it is
--- punched in. `per` is columns a beat. Bound to `position`, a window
--- makes it grow with the live values, with no new scene.
role(
  "recording",
  {
    props = {start = "beat", at = "beat", to = "beat", per = "columns a beat", color = "#rrggbb"},
    bound = {"at"},
    cells = function(buf: contracts.Buf, p: RecordingProps)
      local stop = math.min(p.at or p.start, p.to or math.huge)
      local w = math.floor((stop - p.start) * p.per + 0.5)
      if w > 0 then
        buf:fill(0, 0, math.min(w, buf.width), buf.height, " ", "Armed")
      end
    end,
  } as contracts.Role<RecordingProps>
)

--- The two sides of a meter's levels, 0 for a side it does not have.
local function sides(p: HmeterProps): number, number
  local levels = p.levels or {}
  return levels[1] or 0, levels[2] or 0
end

--- A level across a row, lit from the left (`paw.draw.meter`): `levels`
--- (linear, both sides), `hold`, the loudest of late, marked. With
--- `stereo`, both sides in one row of half blocks. With `at` (0 to 1), a
--- fader's place along it, which a window shows as a thumb: the volume a
--- drag across the row sets. A window always shows both sides, a thin bar
--- each, on the fader's scale. Bound to a track's meter (`bind =
--- "meter:<id>"`), a window moves the levels with `scene.live`.
role(
  "hmeter",
  {
    props = {
      levels = "list of two numbers 0..",
      hold = "number",
      stereo = "boolean",
      at = "number 0..1",
      clipped = "boolean",
    },
    bound = {"levels", "hold", "clipped"},
    cells = function(buf: contracts.Buf, p: HmeterProps)
      local l, r = sides(p)
      if p.stereo then
        draw.stereo_meter(buf, 0, 0, buf.width, l, r)
      else
        draw.meter(buf, 0, 0, buf.width, math.max(l, r), p.hold)
      end
    end,
    -- What the cells show: as the song stops, a level falls on each frame,
    -- and a cell changes only now and then.
    stamp = function(buf: contracts.Buf, p: HmeterProps): string
      local l, r = sides(p)
      if p.stereo then
        return draw.stereo_meter_shown(buf.width, l, r)
      end
      return draw.meter_shown(buf.width, math.max(l, r), p.hold)
    end,
  } as contracts.Role<HmeterProps>
)

return M
