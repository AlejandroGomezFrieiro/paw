-- The roles of the arrange view (paw/views/arrange.lua): its clips, the
-- ground of each row of its timeline with the bars and the loop, and the
-- meters across a header's row. Each draws in cells as the terminal always
-- drew it; a window paints them where they are between cells
-- (crates/paw-gui/src/timeline.rs): a clip with its notes or its waveform,
-- its fades and warp markers, lines at the exact beat.
local role = paw.roles.define
local draw = paw.draw
local util = paw.util

--- Where a beat falls in a role marked from beat `from`, `per` columns a
--- beat: the column a terminal shows it on.
local function column(p, beat) return math.floor((beat - (p.from or 0)) * (p.per or 1) + 0.5) end

--- A clip on the timeline: a row with its `label` (its name, how it is
--- stretched, which take plays) over its body, a hairline where it starts,
--- a notch where each repeat of a looped clip begins (`repeats`, beats from
--- its start) and a mark on each warp marker (`warps`, the same). `per` is
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
--- `nest` it is a block of a subproject: a frame around it, and in its
--- body the notes that the subproject plays there.
role("clip", {
  props = {
    id = "clip id",
    name = "string",
    label = "string",
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
  cells = function(buf, p)
    local g = draw.g
    local w, h = buf.width, buf.height
    if p.ghost then
      buf:fill(0, 0, w, h, nil, "MouseGhost")
      if p.name then buf:text(1, 0, (util.fit(p.name, math.max(0, w - 1)):gsub("%s+$", "")), "MouseGhost") end
      return
    end
    buf:fill(0, 0, w, 1, " ", p.title_style)
    buf:text(w > 2 and 1 or 0, 0, p.label or p.name or "")
    if h >= 2 then
      buf:fill(0, 1, w, h - 1, " ", p.body_style)
      if p.body then p.body(buf, p) end
    end
    -- A notch where each repeat of a looped clip begins.
    for _, at in ipairs(p.repeats or {}) do
      local x = math.floor(at * p.per + 0.5)
      if x > 0 and x < w and h >= 2 then buf:fill(x, 1, 1, h - 1, g.step, "ClipEdge") end
    end
    -- A warp marker, where a moment of the file is pinned to a beat.
    for _, at in ipairs(p.warps or {}) do
      local x = math.floor(at * p.per + 0.5)
      if x > 0 and x < w then buf:fill(x, 0, 1, h, g.tick, "ClipWarp") end
    end
    -- A hairline where the clip starts, so that clips side by side stay apart.
    buf:fill(0, 0, 1, h, g.clip_start, "ClipEdge")
    -- A block of a subproject has a frame: a line where it ends too.
    if p.nest and w > 2 then buf:fill(w - 1, 0, 1, h, g.clip_start, "ClipEdge") end
    -- Where a scope cuts it: `‹` and the name where the scope starts (the
    -- start of the clip is out of sight), `›` where it ends.
    if p.cut_in then
      local x = math.floor(p.cut_in * p.per + 0.5)
      if x >= 0 and x < w then
        buf:text(x, 0, "‹", "ClipEdge")
        local room = math.max(0, w - x - 2)
        if room > 0 then buf:text(x + 1, 0, util.fit(p.label or p.name or "", room), p.title_style) end
      end
    end
    if p.cut_out then
      local x = math.floor(p.cut_out * p.per + 0.5) - 1
      if x >= 0 and x < w then buf:text(x, 0, "›", "ClipEdge") end
    end
  end,
})

--- The ground of a row of a timeline, `from` the beat at its left edge and
--- `per` columns a beat: in `style`, the `loop` (`{ start, end }`, beats)
--- shaded, a line on each of `lines` (`{ beat, bar }` each: a bar's when
--- `bar`), beats' lines only with `beats`. A window paints it by `tone`
--- ("lane", "take", "auto"), a track's lane tinted with `color` when
--- `selected`, every other row (`index`) a little lighter.
role("beats", {
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
  cells = function(buf, p)
    local g = draw.g
    local w, h = buf.width, buf.height
    buf:fill(0, 0, w, h, " ", p.style)
    if p.loop then
      local x0, x1 = math.max(0, column(p, p.loop[1])), math.min(w, column(p, p.loop[2]))
      if x1 > x0 then buf:fill(x0, 0, x1 - x0, h, nil, "LaneLoop") end
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
})

--- A curve over a stretch of time (an automation lane, the tempo map):
--- `values`, its height from 0 at the bottom to 1 at the top in the
--- middle of each column (false where it is not drawn), and `points`
--- (`{ beat, height }` each) marked on it, `from` the beat at the left edge
--- and `per` columns a beat. `draw(buf)` draws it in cells (the curve in
--- line characters, the points as diamonds). A window draws a line through
--- the values and a dot on each point, in `color` (its track's), grey when
--- not `enabled`.
role("curve", {
  props = {
    values = "list of numbers 0..1 or false",
    points = "list of { beat, height }",
    from = "beat at the left edge",
    per = "columns a beat",
    color = "#rrggbb",
    enabled = "boolean",
  },
  cells = function(buf, p)
    if p.draw then p.draw(buf) end
  end,
})

--- A track's header: its ground in `style`, with a stripe (`stripe`, a
--- glyph in `stripe_style`) down its left. A window paints a panel, lighter
--- when `selected`, with a stripe of `color` and a line under it, whose
--- bottom edge a drag makes taller or shorter.
role("trackhead", {
  props = {
    style = "highlight group",
    stripe = "glyph",
    stripe_style = "highlight group",
    color = "#rrggbb",
    selected = "boolean",
  },
  cells = function(buf, p)
    buf:fill(0, 0, buf.width, buf.height, " ", p.style)
    for row = 0, buf.height - 1 do
      buf:text(0, row, p.stripe, p.stripe_style)
    end
  end,
})

--- A take being recorded on an armed track, from `start` (a beat) to
--- `at`, the playhead, in `color`; no further than `to` when it is
--- punched in. `per` is columns a beat. Bound to `position`, a window
--- makes it grow with the live values, with no new scene.
role("recording", {
  props = { start = "beat", at = "beat", to = "beat", per = "columns a beat", color = "#rrggbb" },
  bound = { "at" },
  cells = function(buf, p)
    local stop = math.min(p.at or p.start, p.to or math.huge)
    local w = math.floor((stop - p.start) * p.per + 0.5)
    if w > 0 then buf:fill(0, 0, math.min(w, buf.width), buf.height, " ", "Armed") end
  end,
})

--- A level across a row, lit from the left (`paw.draw.meter`): `levels`
--- (linear, both sides), `hold`, the loudest of late, marked. With
--- `stereo`, both sides in one row of half blocks. With `at` (0 to 1), a
--- fader's place along it, which a window shows as a thumb: the volume a
--- drag across the row sets. A window always shows both sides, a thin bar
--- each, on the fader's scale. Bound to a track's meter (`bind =
--- "meter:<id>"`), a window moves the levels with `scene.live`.
role("hmeter", {
  props = {
    levels = "list of two numbers 0..",
    hold = "number",
    stereo = "boolean",
    at = "number 0..1",
    clipped = "boolean",
  },
  bound = { "levels", "hold", "clipped" },
  cells = function(buf, p)
    local l, r = (p.levels or {})[1] or 0, (p.levels or {})[2] or 0
    if p.stereo then
      draw.stereo_meter(buf, 0, 0, buf.width, l, r)
    else
      draw.meter(buf, 0, 0, buf.width, math.max(l, r), p.hold)
    end
  end,
  -- What the cells show: as the song stops, a level falls on each frame,
  -- and a cell changes only now and then.
  stamp = function(buf, p)
    local l, r = (p.levels or {})[1] or 0, (p.levels or {})[2] or 0
    if p.stereo then return draw.stereo_meter_shown(buf.width, l, r) end
    return draw.meter_shown(buf.width, math.max(l, r), p.hold)
  end,
})
