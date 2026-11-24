-- What the arrange view (paw/views/arrange.tl) draws of one part: the
-- props of its clips with what is drawn in their bodies (a small piano
-- roll, a waveform, the notes of a subproject's block). The head of the
-- part's row is in paw/heads.tl.
-- Nothing here knows where the view scrolls: the view places what this
-- module draws, and gives it the time axis (paw/axis.tl) and how far into
-- its first cell each clip begins (`phase`), so that what is drawn in a
-- clip's cells is under the ruler's beats.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local axis = require("paw.axis")
local modifiers = require("paw.modifiers")
local kernel = require("paw.events.kernel")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type DrawModule = require("paw.draw")
local type roles = require("paw.roles.arrange")
local type Buf = contracts.Buf
local type Part = types.Part
local type Clip = types.Clip
local type Hue = DrawModule.Hue
local type Axis = axis.Axis

local draw = paw.draw

local record M
  places_text: function(nest: integer): string
  notes_line: function(clip: Clip, width: integer, ax: Axis, at: number): string
  cuts: function(clip: Clip, from: number, to: number): number, number
  clip_props: function(
    clip: Clip,
    part: Part,
    hue: Hue,
    kind: string,
    ax: Axis,
    at: number,
    chosen?: boolean,
    from?: number,
    to?: number,
    colour?: string
  ): roles.ClipProps
  take_body: function(
    props: roles.ClipProps, clip: Clip, take: integer, key: string, colour: string, active: boolean, ax: Axis
  )
end

-- What is kept between frames -------------------------------------------------------

-- Small piano rolls and waveforms drawn inside clips. A waveform is kept
-- until the project changes. A piano roll is kept by what it is drawn
-- from (the stamp of the clip's notes, its length and its loop): an edit
-- elsewhere (a part deleted and put back, a fader) draws it again from
-- what is kept. They are forgotten when there are too many.
local KEEP = 4096

--- A store of values made by a key, emptied when it holds KEEP: `n` is
--- how many it holds.
local record Kept<T>
  values: {string: T}
  n: integer
end

local function kept_store<T>(): Kept<T>
  return {values = {}, n = 0}
end

--- What `kept` holds for `key`, or `make()` kept there.
local function keep<T>(kept: Kept<T>, key: string, make: function(): T): T
  local v = kept.values[key]
  if v == nil then
    v = make()
    if kept.n >= KEEP then
      kept.values, kept.n = {}, 0
    end
    kept.values[key], kept.n = v, kept.n + 1
  end
  return v
end

--- What a clip's preview was drawn from, and what it drew: rows of text,
--- and the runs of a waveform's rows.
local record Preview
  width: integer
  rows: integer
  zoom: number
  phase: number
  scale: number | string
  ascii: boolean
  stamp: integer
  length: number
  loop: boolean
  loop_start: number
  loop_length: number
  out: {string}
  runs: {{DrawModule.WaveRun}}
end

local previews: {integer: Preview} = {}
local waves: {string: {types.Peak}} = {}
local rolls: Kept<{string}> = kept_store()

paw.on(kernel.changed, function() previews, waves = {}, {} end)

--- ` ×2` after the name of a subproject that the song plays in more
--- places than one; else nothing.
function M.places_text(nest: integer): string
  local n = paw.nest.places(nest)
  return n > 1 and (" " .. draw.g.places .. n) or ""
end

-- The clips -----------------------------------------------------------------------

--- An audio clip's waveform as `n` { min, max, rms } across it, kept: for
--- `paw.plot.wave` and its twin in cells. Nothing for a missing file.
local function wave_peaks(clip: Clip, n: integer): {types.Peak}
  local key = clip.id .. ":" .. n
  if not waves[key] then
    local ok, peaks = pcall(api.clip_peaks, clip.id, n)
    waves[key] = ok and peaks or {}
  end
  return waves[key]
end

--- The peaks of `n` points across a box `width` cells wide, in which a
--- clip begins `phase` of a cell into the first cell and takes `cells`
--- cells: each point gets the loudest of the clip's time under it, so that
--- the sound is under the ruler's beat (paw/axis.tl). `of(m)` gives the
--- clip's peaks at `m` points across all of it.
local function aligned(
  of: function(m: integer): {types.Peak}, n: integer, width: integer, phase: number, cells: number
): {types.Peak}
  if n < 1 or width < 1 or cells <= 0 then
    return {}
  end
  -- Four points of the clip at least for each point of the box.
  local m = math.min(65536, math.max(n, math.ceil(n * cells / width)) * 4)
  local fine = of(m) or {}
  if #fine == 0 then
    return {}
  end
  local out: {types.Peak} = {}
  for j, p in ipairs(fine) do
    local u = math.floor((phase + (j - 0.5) / #fine * cells) * n / width) + 1
    if u >= 1 and u <= n then
      local q = out[u]
      if not q then
        out[u] = {p[1], p[2], p[3]}
      else
        q[1], q[2] = math.min(q[1], p[1]), math.max(q[2], p[2])
        if p[3] and q[3] then
          q[3] = math.max(q[3], p[3])
        end
      end
    end
  end
  for u = 1, n do
    out[u] = out[u] or {0, 0, 0}
  end
  return out
end

--- Whether a clip's kept preview was drawn from what it would be drawn
--- from now.
local function still_fits(kept: Preview, clip: Clip, width: integer, rows: integer, ax: Axis, phase: number): boolean
  if not (kept.width == width and kept.rows == rows and kept.zoom == ax.zoom and kept.phase == phase) then
    return false
  end
  if not (kept.scale == paw.opt.wave_scale and kept.ascii == paw.opt.ascii) then
    return false
  end
  -- A waveform does not depend on the notes.
  if clip.kind ~= "midi" then
    return true
  end
  return kept.stamp == clip.stamp
    and kept.length == clip.length
    and kept.loop == clip.loop
    and kept.loop_start == clip.loop_start
    and kept.loop_length == clip.loop_length
end

--- The rows under a clip's name: its notes as a small piano roll, or its
--- waveform, on the axis `ax`, the clip `phase` of a cell into its first
--- column.
local function preview(
  clip: Clip, width: integer, rows: integer, ax: Axis, phase: number
): {string}, {{DrawModule.WaveRun}}
  -- Kept by the clip, then compared field by field: a string key made on
  -- each frame for each clip cost more than the look-up saved.
  local scale, ascii = paw.opt.wave_scale, paw.opt.ascii
  local kept = previews[clip.id]
  if kept and still_fits(kept, clip, width, rows, ax, phase) then
    return kept.out, kept.runs
  end
  local key = string.format(
    "%d:%d:%d:%.17g:%.17g:%s%s", clip.id, width, rows, ax.zoom, phase, tostring(scale), ascii and "a" or ""
  )
  local out: {string}
  local runs: {{DrawModule.WaveRun}}
  if clip.kind == "midi" then
    local roll = string.format(
      "%s:%s:%.17g:%s:%.17g:%s",
      key,
      tostring(clip.stamp),
      clip.length,
      tostring(clip.loop),
      clip.loop_start or 0,
      tostring(clip.loop_length)
    )
    out = rolls.values[roll]
    if out == nil then
      out = keep(
        rolls,
        roll,
        function(): {string}
          local notes = paw.stretch.sounding(clip, api.clip_notes(clip.id)) as {types.Note}
          return draw.miniroll(notes, width, rows, ax, phase)
        end
      )
    end
  else
    -- A file that has gone missing has been reported already; draw nothing.
    local function of(m: integer): {types.Peak}
      local ok, peaks = pcall(api.clip_peaks, clip.id, m)
      return ok and peaks or {}
    end
    out, runs = draw.waveform(aligned(of, width, width, phase, ax:cells(clip.length)), rows)
  end
  previews[clip.id] = {
    width = width,
    rows = rows,
    zoom = ax.zoom,
    phase = phase,
    scale = scale,
    ascii = ascii,
    stamp = clip.stamp,
    length = clip.length,
    loop = clip.loop,
    loop_start = clip.loop_start,
    loop_length = clip.loop_length,
    out = out,
    runs = runs,
  }
  return out, runs
end

--- A clip's notes in one line `width` cells wide (its waveform for an
--- audio clip), as its body draws them, for an overview of its part
--- (a member of a folded group): on the axis `ax`, the clip at place `at`
--- (`ax:view` of its start). Nil for a clip with nothing to draw in one
--- line: no notes, or a block of a subproject.
function M.notes_line(clip: Clip, width: integer, ax: Axis, at: number): string
  if clip.kind == "nest" or (clip.kind == "midi" and clip.note_count == 0) then
    return nil
  end
  return (preview(clip, width, 1, ax, ax:phase_at(at)))[1]
end

--- Style names for the runs of a waveform that `draw.waveform` marks.
local wave_style: {string: string} = {flip = "ClipWaveFlip", clip = "ClipWaveClip", clipflip = "ClipWaveClipFlip"}

--- What each clip's props (`clip_props`) draw in its body: the clip, its
--- part's colour, its kind, the axis and how far into its first cell the
--- clip begins. Kept beside the props, not in them, as they are not data
--- for a frontend; and not in a closure made for each clip on each frame,
--- which LuaJIT does not compile.
local record Body
  clip: Clip
  colour: string
  kind: string
  ax: Axis
  phase: number
end
local bodies: {roles.ClipProps: Body} = setmetatable({}, {__mode = "k"})

--- A waveform in the rows of `box` under its first: in pixels under the
--- cells where the terminal shows them, else in cells. `peaks(n)` gives it
--- at `n` points across the whole box (`aligned`). `key` names the
--- picture, so that scrolling moves pieces already made.
local function waveform(box: Buf, key: string, colour: string, peaks: function(n: integer): {types.Peak})
  local cw, height = box.width, box.height
  local body = box:sub(0, 1, cw, height - 1)
  local pictured = body:strip(
    0,
    0,
    cw,
    height - 1,
    {
      key = key,
      under = true,
      draw = function(g: contracts.Painter, px: contracts.StripPixels)
        paw.plot.wave(g, px, {peaks = peaks, color = colour})
      end,
    }
  )
  if not pictured then
    paw.plot.wave_cells(body, {peaks = peaks})
  end
end

--- The colour that the cells draw a body in (`paw.draw.hue`'s body), by
--- its kind: "_off" for a muted clip or a take that does not play.
local function body_colour(colour: string, kind: string): string
  return draw.mix(require("paw.theme").palette.bg, colour, kind == "_off" and 0.30 or 0.75)
end

--- An audio clip's waveform, the whole clip's.
local function audio_body(box: Buf, of: Body)
  local clip = of.clip
  local cells = of.ax:cells(clip.length)
  local function whole(m: integer): {types.Peak}
    return wave_peaks(clip, m)
  end
  local function peaks(n: integer): {types.Peak}
    return aligned(whole, n, box.width, of.phase, cells)
  end
  waveform(box, "arrange:wave:" .. clip.id, body_colour(of.colour, of.kind), peaks)
end

--- A block of a subproject: what it plays, as a small piano roll of the
--- notes of its subproject's parts.
local function nest_body(box: Buf, of: Body)
  local cw, height = box.width, box.height
  local key = string.format("%s:%d:%d:%.17g:%.17g", paw.nest.content_key(of.clip), cw, height - 1, of.ax.zoom, of.phase)
  local rows = rolls.values[key]
  if rows == nil then
    rows = keep(
      rolls,
      key,
      function(): {string} return draw.miniroll(paw.nest.notes(of.clip), cw, height - 1, of.ax, of.phase) end
    )
  end
  for row, text in ipairs(rows) do
    box:text(0, row, text)
  end
end

--- What is drawn in a clip's body (the `clip` role's `body(buf, props)`):
--- its waveform, or its notes as a small piano roll.
local function clip_body(box: Buf, p: roles.ClipProps)
  local of = bodies[p]
  if not of then
    return
  end
  local clip = of.clip
  if clip.kind == "audio" then
    audio_body(box, of)
  elseif clip.kind == "nest" then
    nest_body(box, of)
  elseif clip.note_count > 0 then
    local rows, runs = preview(clip, box.width, box.height - 1, of.ax, of.phase)
    for row, text in ipairs(rows) do
      if runs then
        for _, run in ipairs(runs[row]) do
          box:text(run.column, row, run.text, wave_style[run.mark])
        end
      else
        box:text(0, row, text)
      end
    end
  end
end

--- What a take lane's clip draws in its body: take `take` of `clip`, on
--- the axis `ax`. `key` changes exactly when what the take plays changes
--- (`paw.frontend.take_rows`).
local record TakeBody
  clip: Clip
  take: integer
  key: string
  colour: string
  ax: Axis
end
local take_bodies: {roles.ClipProps: TakeBody} = setmetatable({}, {__mode = "k"})

--- The body of a take lane's clip: the take's waveform, or its notes as a
--- small piano roll, under the same time as the clip's own.
local function take_body(box: Buf, p: roles.ClipProps)
  local of = take_bodies[p]
  if not of or box.height < 2 then
    return
  end
  local clip, take, rows = of.clip, of.take, box.height - 1
  local ax, phase = of.ax, p.phase or 0
  if clip.kind == "audio" then
    local function whole(m: integer): {types.Peak}
      local key = of.key .. ":" .. m
      if not waves[key] then
        waves[key] = paw.takes.peaks(clip, take, m)
      end
      return waves[key]
    end
    local cells = ax:cells(clip.length)
    local function peaks(n: integer): {types.Peak}
      return aligned(whole, n, box.width, phase, cells)
    end
    waveform(box, "arrange:take:" .. clip.id .. ":" .. take, of.colour, peaks)
    return
  end
  local key = string.format("%s:%d:%d:%.17g:%.17g", of.key, box.width, rows, ax.zoom, phase)
  local out = rolls.values[key]
  if out == nil then
    out = keep(
      rolls,
      key,
      function(): {string}
        local notes = paw.takes.content(clip, take).notes
        return draw.miniroll(paw.stretch.sounding(clip, notes) as {types.Note}, box.width, rows, ax, phase)
      end
    )
  end
  for row, text in ipairs(out) do
    box:text(0, row, text)
  end
end

--- Give a take lane's clip (`props`, take `take` of `clip`) the take's
--- waveform or notes in its body. `key` is what the take plays
--- (`paw.frontend.take_rows`), `colour` its part's, and the take is faint
--- where it does not play (not `active`).
function M.take_body(
  props: roles.ClipProps, clip: Clip, take: integer, key: string, colour: string, active: boolean, ax: Axis
)
  if not key then
    return
  end
  props.body = take_body
  take_bodies[props] = {
    clip = clip, take = take, key = key, colour = body_colour(colour, active and "" or "_off"), ax = ax
  }
end

--- The styles of a clip's title and body by its kind ("", "_cur", "_off").
local title_of: {string: string} = {[""] = "title", _cur = "title_cur", _off = "title_off"}
local body_of: {string: string} = {[""] = "body", _cur = "body_cur", _off = "body_off"}

--- The controller moves of a MIDI clip as the `clip` role's `moves`: in
--- each of its columns on the axis, the clip `phase` of a cell into the
--- first, the height (0 to 1) of the controller that moves most often,
--- where the column's middle is, and false before its first move. Kept by
--- the clip's controls, its length, its loop, the zoom and the phase. Nil
--- for a clip without controller moves.
local curves: Kept<{number | boolean}> = kept_store()

--- A controller move as `paw.stretch.sounding` takes a note: it reads a
--- length, and a move has none. `height` is its value from 0 to 1.
local record Move
  start: number
  length: number
  height: number
end

local function moves(clip: Clip, ax: Axis, phase: number): {number | boolean}
  if clip.kind ~= "midi" or (clip.control_count or 0) == 0 then
    return nil
  end
  local key = string.format(
    "%d:%s:%.17g:%s:%.17g:%.17g:%.17g:%.17g",
    clip.id,
    tostring(clip.control_stamp),
    clip.length,
    tostring(clip.loop),
    clip.loop_start or 0,
    clip.loop_length or 0,
    ax.zoom,
    phase
  )
  return keep(
    curves,
    key,
    function(): {number | boolean}
      -- The moves of each controller (its type, number and note), as they
      -- sound in a looped clip; the one with the most moves is drawn.
      local by: {string: {Move}} = {}
      local most: string
      for _, c in ipairs(api.clip_controls(clip.id)) do
        if c.type ~= "program" then
          local name = c.type .. ":" .. tostring(c.number or c.index or 0) .. ":" .. tostring(c.key)
          local list = by[name] or {}
          by[name] = list
          list[#list + 1] = {start = c.start, length = 0, height = c.type == "bend" and (c.value + 1) / 2 or c.value}
          if not most or #list > #by[most] then
            most = name
          end
        end
      end
      local list = most and paw.stretch.sounding(clip, by[most]) as {Move} or {}
      table.sort(list, function(a: Move, b: Move): boolean return a.start < b.start end)
      local out: {number | boolean} = {}
      local after = 1
      local height: number | boolean = false
      for x = 0, math.max(1, axis.cell(phase + ax:cells(clip.length))) - 1 do
        local middle = ax:beats(x + 0.5 - phase)
        while list[after] and list[after].start <= middle do
          height = list[after].height
          after = after + 1
        end
        out[x + 1] = height
      end
      return out
    end
  )
end

--- Where the window's scope (`paw.scope`) cuts a clip that crosses one of
--- its edges, in beats from the clip's start: `cut_in` at its start,
--- `cut_out` at its end, each nil where it does not cut. Only the drawing
--- is cut: an edit of the clip is an edit of all of it.
function M.cuts(clip: Clip, from: number, to: number): number, number
  if not from then
    return nil, nil
  end
  local finish = clip.start + clip.length
  local EPS = 1e-9
  local cut_in = (clip.start < from - EPS and finish > from + EPS) and from - clip.start or nil
  local cut_out = (clip.start < to - EPS and finish > to + EPS) and to - clip.start or nil
  return cut_in, cut_out
end

--- What a clip's title says: its name, and marks of what is done to it.
local function clip_label(clip: Clip): string
  local label = clip.offline and ("offline · " .. clip.name) or clip.name
  -- A muted clip: `⊘ riff`, beside its faint body, so it reads as off at a glance.
  if clip.muted then
    label = draw.g.muted .. label
  end
  -- A linked clip: `riff ≡`; with modifiers, `riff ≡ +3 v-10`.
  if clip.link then
    label = label .. " " .. draw.g.link
  end
  local stack = modifiers.label(clip.modifiers)
  if stack then
    label = label .. " " .. stack
  end
  -- A block of a subproject: its name after `⧉`, in a frame; the letter
  -- of its kind after `⧉` for a kind of subproject (`⧉D Groove`).
  if clip.kind == "nest" then
    local letter = paw.nest.letter(clip.nest)
    label = (letter and (draw.g.nest:gsub("%s+$", "") .. letter .. " ") or draw.g.nest)
      .. label
      .. M.places_text(clip.nest)
  end
  -- Stretched, shifted, looped: `×1.5 ↻ drums`.
  local mark = paw.stretch.badge(clip) as string
  if mark then
    label = mark .. " " .. label
  end
  return label
end

--- A clip on the timeline's plane, as the `clip` role it is. `kind` is
--- "" or "_cur" (the cursor's) or "_off" (muted). `ax` is the view's axis
--- and `at` the place on the plane where the clip's box begins (`ax:view`
--- of its start). `from`, `to`: the time of the window's scope, which cuts
--- it (`cut_in`, `cut_out`). `colour` is its part's
--- (`paw.draw.part_colour`), when the caller has it.
function M.clip_props(
  clip: Clip,
  part: Part,
  hue: Hue,
  kind: string,
  ax: Axis,
  at: number,
  chosen?: boolean,
  from?: number,
  to?: number,
  colour?: string
): roles.ClipProps
  colour = colour or draw.part_colour(part)
  local cut_in, cut_out = M.cuts(clip, from, to)
  local block = clip.kind == "nest"
  local warps: {number}
  for i, m in ipairs(clip.warp or {}) do
    warps = warps or {}
    warps[i] = m.beat - clip.start
  end
  local hues = hue as {string: string}
  local phase = ax:phase_at(at)
  local props: roles.ClipProps = {
    key = "clip:" .. clip.id,
    name = clip.name,
    label = clip_label(clip),
    -- A clip with takes says which plays: `take 3 ‹2/4›` (the role puts
    -- the mark first where the label does not fit).
    mark = paw.takes.badge(clip),
    per = ax.zoom,
    phase = phase,
    repeats = clip.loop and paw.stretch.repeats(clip) as {number} or nil,
    warps = warps,
    moves = moves(clip, ax, phase),
    cut_in = cut_in,
    cut_out = cut_out,
    title_style = hues[title_of[kind]],
    body_style = hues[body_of[kind]],
    body = clip_body,
    nest = block or nil,
  }
  bodies[props] = {clip = clip, colour = colour, kind = kind, ax = ax, phase = phase}
  -- What only a frontend that gets scenes reads: the terminal draws the
  -- same cells without it.
  if paw.ui.scene_drawing then
    props.id = clip.id
    props.color = colour
    props.midi = clip.kind ~= "audio"
    props.muted = clip.muted or nil
    props.current = kind == "_cur" or nil
    props.chosen = chosen or nil
    props.offline = clip.offline or nil
    props.length = clip.length
    props.repeats = props.repeats or {}
    props.warps = warps or {}
    props.fade_in = clip.fade_in
    props.fade_out = clip.fade_out
    props.gain = clip.gain
    props.content = paw.frontend.content_key(clip)
  end
  return props
end

return M
