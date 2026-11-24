-- The rows and the namespaces of marks that paw puts on the ruler
-- (paw/ruler.tl, paw/marks.tl).
--
-- Rows: `bars` (the number of each bar, and the song's bars under a scope's
-- own), `beats` (a tick on each beat, over the bars) and `regions` (a line
-- for each level of the tree of regions). The arrange view adds `tempo`
-- (the tempo lane) and the namespace of the time selection.
--
-- Namespaces: `paw.meter` and `paw.tempo` (the changes of the time
-- signature and the tempo, over the bars), `paw.cues` (the markers) and
-- `paw.regions` (on the regions' row), `paw.loop` and `paw.punch` (the
-- loop and the punch range, over the bars). Each computes its marks for
-- the time in sight, in the window's beats.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local marks = require("paw.marks")
local ruler = require("paw.ruler")
local type contracts = require("paw.contracts")
local type MarkersModule = require("paw.markers")
local type DrawModule = require("paw.draw")

local type Mark = contracts.RulerMark
local type Context = contracts.RulerContext
local type Marker = MarkersModule.Marker
local type Node = MarkersModule.Node

local opt = options.opt

local record M
end

-- The bars and the beats ------------------------------------------------------------------

--- Whether the bars row has a line of the song's bars (`@9`) under the
--- bars of the window's scope: in a scope with time whose bars count
--- from 1 (`scopebars=local`) and are not the song's. A region scope counts
--- from its first bar (`bar_offset`); a subproject counts from where its
--- block plays in the song (`origin`).
local function shows_song_bars(): boolean
  if opt.scopebars == "song" or not paw.scope.span() then
    return false
  end
  return paw.scope.bar_offset() ~= 0 or paw.scope.origin() ~= 0
end

--- The bar lines in sight with a number: every bar, or one bar in
--- `every` when the bars are too narrow for their numbers.
local function labelled_bars(ctx: Context): {DrawModule.GridLine}
  local ax = ctx.axis
  local every = math.max(1, math.ceil(5 / ax:cells(paw.time.bar(ax.scroll))))
  local out: {DrawModule.GridLine} = {}
  for _, line in ipairs(paw.draw.grid_lines(ax, ctx.right)) do
    if line.bar and (line.bar - 1) % every == 0 then
      out[#out + 1] = line
    end
  end
  return out
end

-- Glyphs: `ahead` and `behind` before the counts of `relativebar` (none by
-- default). Styles: `bar`, `cursor` (the cursor's bar, with
-- `relativebar`) and `relative` (the counts).
ruler.row(
  "bars",
  {
    priority = 10,
    glyphs = {ahead = "", behind = ""},
    styles = {bar = "RulerBar", cursor = "RulerBarCursor", relative = "RulerBarRelative"},
    height = function(_: Context): integer return shows_song_bars() and 2 or 1 end,
    marks = function(ctx: Context): {Mark}
      local g, s = ctx.glyphs, ctx.styles
      local cursor = paw.cursor.beat
      local here_bar = paw.time.bar_of(cursor)
      local out: {Mark} = {}
      local song = shows_song_bars()
      local last_song: integer
      for _, line in ipairs(labelled_bars(ctx)) do
        local bar = ruler.bar_number(line.bar)
        local text, style = tostring(bar), s.bar
        local relative = opt.relativebar and ruler.relative(line.bar, cursor) or nil
        if opt.relativebar and line.bar == here_bar then
          style = s.cursor
        elseif relative then
          text = (line.bar > here_bar and g.ahead or g.behind) .. tostring(relative)
          style = s.relative
        end
        out[#out + 1] = {
          beat = line.beat,
          label = text,
          whole = true,
          style = style,
          kind = "bar",
          text = "bar " .. bar,
        }
        -- The song's bar there, once for each bar of the song.
        if song then
          local song_bar = math.floor(api.tempo_bar_of(paw.time.song_beat(line.beat))) + 1
          if song_bar ~= last_song then
            out[#out + 1] = {
              beat = line.beat,
              line = 1,
              label = "@" .. song_bar,
              whole = true,
              style = s.bar,
              kind = "bar",
              text = "bar @" .. song_bar .. " of the song",
            }
          end
          last_song = song_bar
        end
      end
      return out
    end,
  }
)

-- Glyphs: `tick`. Styles: `tick`. From two columns a beat.
ruler.row(
  "beats",
  {
    over = "bars",
    priority = 1,
    glyphs = {},
    styles = {tick = "RulerTick"},
    marks = function(ctx: Context): {Mark}
      local out: {Mark} = {}
      if ctx.axis:cells(1) < 2 then
        return out
      end
      local tick = ctx.glyphs.tick or paw.draw.g.tick
      for _, line in ipairs(paw.draw.grid_lines(ctx.axis, ctx.right)) do
        if not line.bar then
          out[#out + 1] = {
            beat = line.beat, sign = tick, soft = true, style = ctx.styles.tick, kind = "beat", text = "beat"
          }
        end
      end
      return out
    end,
  }
)

-- The regions ----------------------------------------------------------------------------
--
-- A line for each level of the tree of regions (up to `regionlevels`): a
-- region is drawn under the region around it, as a part under its group.
-- Deeper regions share the last line, marked `+`. The markers (cues) are
-- on the first line.

options.define(
  "regionlevels", 3, {}
) -- lines of the regions' row on the ruler; deeper regions share the last line, marked `+`

local function levels(): integer
  return math.max(1, math.tointeger((options.opt as {string: number}).regionlevels) or 3)
end

--- Where a region (with `length`) or a marker shows in the window: its
--- start and end in the window's time (`ctx.here`), cut at the edges of
--- the time of the window's scope (`ctx.from`, `ctx.to`). Nil when it is
--- outside that time: inside a subproject, the song's regions that its
--- block covers show at their place in it, and no others.
local function placed(ctx: Context, beat: number, length?: number): number, number
  local a = ctx.here(beat)
  local b = length and ctx.here(beat + length) or a
  if not ctx.from then
    return a, b
  end
  local from, to = ctx.from, ctx.to
  if length then
    if b <= from + 1e-9 or a >= to - 1e-9 then
      return nil
    end
    return math.max(a, from), math.min(b, to)
  end
  -- A marker at the end of the scope's time marks what comes after it.
  if a < from - 1e-9 or a >= to - 1e-9 then
    return nil
  end
  return a, b
end

--- Whether a region covers all the time of the window's scope: it only
--- says again what the window bar says (`Verse` in `Verse`), so the row
--- does not show it, and the regions inside it go up a line.
local function repeats_scope(ctx: Context, r: Marker): boolean
  if not (ctx.from and r.length) then
    return false
  end
  return ctx.here(r.beat) <= ctx.from + 1e-9 and ctx.here(r.beat + r.length) >= ctx.to - 1e-9
end

--- The level of a region on the row: its depth, less the regions around
--- it (itself too) that cover the scope's time. Nil for a region that
--- covers it.
local function shown_depth(ctx: Context, node: Node): integer
  if repeats_scope(ctx, node.region) then
    return nil
  end
  local depth = node.depth
  local up = node.parent
  while up do
    if repeats_scope(ctx, up.region) then
      depth = depth - 1
    end
    up = up.parent
  end
  return depth
end

--- Whether a region does not show: a region around it is folded into its
--- column, or its start is in a time fold.
local function hidden(ctx: Context, node: Node, start: number): boolean
  local up = node.parent
  while up do
    if ctx.closed(up.region.id) then
      return true
    end
    up = up.parent
  end
  return ctx.folded(start)
end

ruler.row(
  "regions",
  {
    -- One line for each level of the regions that show, at most
    -- `regionlevels`. The cues (`paw.cues`) give it a line of their own.
    height = function(ctx: Context): integer
      local deepest = 0
      for _, node in ipairs(paw.markers.walk()) do
        local depth = shown_depth(ctx, node)
        if depth and placed(ctx, node.region.beat, node.region.length) then
          deepest = math.max(deepest, depth)
        end
      end
      return math.min(deepest, levels())
    end,
  }
)

-- Glyphs: `open` before a region with regions inside (as a group's fold in
-- the part column), `closed` before one folded into its column, `start`
-- before one with none, `deeper` before the name of a region deeper than
-- the last line. Styles: `level1`, `level2`, `deep` (the third level and
-- deeper).
marks.namespace(
  "paw.regions",
  {
    route = "row:regions",
    priority = 20,
    glyphs = {open = "▾", closed = "▸", start = "▏", deeper = "+"},
    styles = {level1 = "RulerRegion1", level2 = "RulerRegion2", deep = "RulerRegionDeep"},
    source = function(ctx: Context): {Mark}
      local g, s = ctx.glyphs, ctx.styles
      local out: {Mark} = {}
      for _, node in ipairs(paw.markers.walk()) do
        local r = node.region
        local start, stop = placed(ctx, r.beat, r.length)
        local depth = shown_depth(ctx, node)
        if start and depth and not hidden(ctx, node, start) then
          local line = math.min(depth, levels()) - 1
          local style = depth == 1 and s.level1 or depth == 2 and s.level2 or s.deep
          local name = paw.markers.label(r)
          out[#out + 1] = {
            beat = start, to = stop, line = line, style = style, priority = 1, kind = "region", ref = r.id
          }
          out[#out + 1] = {
            beat = start,
            line = line,
            sign = ctx.closed(r.id) and g.closed or #node.children > 0 and g.open or g.start,
            label = (depth > levels() and g.deeper or "") .. name,
            style = style,
            kind = "region",
            ref = r.id,
            text = "region " .. name,
          }
        end
      end
      return out
    end,
  }
)

-- Glyphs: `sign`. Styles: `cue`.
marks.namespace(
  "paw.cues",
  {
    route = "row:regions",
    priority = 30,
    glyphs = {sign = "▼"},
    styles = {cue = "Marker"},
    source = function(ctx: Context): {Mark}
      local out: {Mark} = {}
      for _, m in ipairs(paw.markers.list()) do
        local at: number
        if not m.length then
          at = placed(ctx, m.beat)
        end
        if at and not ctx.folded(at) then
          local name = paw.markers.label(m)
          out[#out + 1] = {
            beat = at,
            sign = ctx.glyphs.sign,
            label = name,
            style = ctx.styles.cue,
            kind = "cue",
            ref = m.id,
            text = "cue " .. name,
          }
        end
      end
      return out
    end,
  }
)

-- The tempo and the meter -------------------------------------------------------------------

--- A namespace of the changes of one kind (`tempo` or `signature`) of
--- `paw.tempo.marks`: a sign in the column of each, and its value whole.
local function changes(kind: string, words: string): function(ctx: Context): {Mark}
  return function(ctx: Context): {Mark}
    local out: {Mark} = {}
    for _, m in ipairs(paw.tempo.marks(ctx.left or -1e12, ctx.right or 1e12)) do
      if m.kind == kind then
        out[#out + 1] = {
          beat = m.beat,
          sign = ctx.glyphs.sign,
          label = m.text,
          whole = true,
          style = ctx.styles.mark,
          kind = kind,
          text = words .. " " .. m.text,
        }
      end
    end
    return out
  end
end

-- Glyphs: `sign`. Styles: `mark`. A meter change wins a column over a tempo change.
marks.namespace(
  "paw.meter",
  {
    route = "over:bars",
    priority = 50,
    glyphs = {sign = "‖"},
    styles = {mark = "RulerTempo"},
    source = changes("signature", "meter"),
  }
)
marks.namespace(
  "paw.tempo",
  {
    route = "over:bars",
    priority = 40,
    glyphs = {sign = "▾"},
    styles = {mark = "RulerTempo"},
    source = changes("tempo", "tempo"),
  }
)

-- The loop and the punch range ------------------------------------------------------------

-- The styles that the text over the loop, the loop that is off and the
-- punch range takes, by its own style.
local IN_LOOP: {string: string} = {RulerBar = "RulerLoop", RulerBarRelative = "RulerLoop", RulerTick = "RulerLoopTick"}
local IN_LOOP_OFF: {string: string} = {
  RulerBar = "RulerLoopOffBar",
  RulerBarRelative = "RulerLoopOffBar",
  RulerTick = "RulerLoopOffTick",
}
local IN_PUNCH: {string: string} = {
  RulerBar = "RulerPunch", RulerBarRelative = "RulerPunch", RulerTick = "RulerPunchTick"
}

-- The loop's band: bright while looping is on, dim while it is off (the
-- range stays in sight). Its edges are in the cell before each edge's
-- column; at the end of the scope, the scope's `┃` marks the end.
-- Glyphs: `start`, `end`.
marks.namespace(
  "paw.loop",
  {
    route = "over:bars",
    priority = 20,
    glyphs = {},
    styles = {},
    source = function(ctx: Context): {Mark}
      local t = paw.ui.transport()
      local out: {Mark} = {}
      if t.loop_end <= t.loop_start then
        return out
      end
      local on = t.loop_enabled
      local from, to = ctx.here(t.loop_start), ctx.here(t.loop_end)
      local words = "loop, " .. ruler.loop_text(t.loop_start, t.loop_end, on)
      local g = paw.draw.g
      out[1] = {
        beat = from,
        to = to,
        style = on and "RulerLoop" or "RulerLoopOff",
        restyle = on and IN_LOOP or IN_LOOP_OFF,
        priority = 2,
        kind = "loop",
        text = words,
      }
      out[2] = {
        beat = from,
        edge = true,
        sign = ctx.glyphs.start or g.loop_in,
        style = on and "RulerLoopEdge" or "RulerLoopOffEdge",
        kind = "loop",
        text = "the start of the " .. words,
      }
      local at_end = ctx.to and math.abs(to - ctx.to) < 1e-9
      if not at_end then
        out[3] = {
          beat = to,
          edge = true,
          sign = ctx.glyphs["end"] or g.loop_out,
          style = on and "RulerLoopEdgeIn" or "RulerLoopOffEdge",
          kind = "loop",
          text = "the end of the " .. words,
        }
      end
      return out
    end,
  }
)

-- The punch range, in red over the loop's amber where they meet.
-- Glyphs: `start`, `end`.
marks.namespace(
  "paw.punch",
  {
    route = "over:bars",
    priority = 20,
    glyphs = {},
    styles = {},
    source = function(ctx: Context): {Mark}
      local t = paw.ui.transport()
      local out: {Mark} = {}
      if not t.punch_enabled or t.punch_end <= t.punch_start then
        return out
      end
      local from, to = ctx.here(t.punch_start), ctx.here(t.punch_end)
      local first, last = ruler.bars_of(t.punch_start, t.punch_end)
      local words = string.format("punch range, bars %d to %d", first, last)
      local g = paw.draw.g
      out[1] = {
        beat = from, to = to, style = "RulerPunch", restyle = IN_PUNCH, priority = 3, kind = "punch", text = words
      }
      out[2] = {
        beat = from,
        edge = true,
        sign = ctx.glyphs.start or g.punch_in,
        style = "RulerPunchEdge",
        kind = "punch",
        text = "the start of the " .. words,
      }
      out[3] = {
        beat = to,
        edge = true,
        sign = ctx.glyphs["end"] or g.punch_out,
        style = "RulerPunchEdge",
        kind = "punch",
        text = "the end of the " .. words,
      }
      return out
    end,
  }
)

return M
