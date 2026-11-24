-- The built-in reading of the whole song: what `paw.harmony` asks for the
-- chords and keys of the song. It is made of nodes of `paw.derived`, so
-- that an edit reads again only what it changed:
--
--   harmony.clip          the notes of a clip's content (its stamp and length), in
--                         its own beats: copies with the same notes share it
--   harmony.place         a clip where it is: its content and its start
--   harmony.drums         whether a part is drums, which the reading leaves out
--   harmony.part         each part's clips that sound, with their starts
--   harmony.part_window  what one part sounds in one window (a `read.Portion`)
--   harmony.group         what 8 parts sound in one window: the sum of the above
--   harmony.mix           what all parts sound in one window: the sum of the groups
--   harmony.beat          what sounds in one beat, for a window with one pitch alone
--   harmony.window        the window's scores (`read.finish`)
--   harmony.chords        the chords (`read.decode` over the windows), in slices
--   harmony.part_bar     the pitch classes of one part in one bar
--   harmony.bar           of all parts in one bar
--   harmony.keys          the keys (`read.key_path`), in slices
--
-- So a note edit reads one clip again and the windows it covers, and a mute
-- leaves the parts of the other parts as they are: the windows add up
-- what they had. The reading is the one that `paw.harmony.read` makes of
-- all the notes at once (`M.whole`), and a change that leaves the notes as
-- they are (a fader, a device) reads nothing.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local derived = require("paw.derived")
local read = require("paw.harmony.read")
local type types = require("paw.types")

--- A note of the song, in project beats, with its part and its clip.
local record Note is read.Note
  part: integer
  clip: integer
end

--- What the reading needs to know besides the notes: the length of a
--- window (`paw.opt.harmony_step`), the beats of a bar where the song
--- starts, where bar `n` starts, and which parts are drums.
local record Options
  step: number
  bar: number
  bar_start: function(n: integer): number
  is_drums: function(t: types.Part): boolean
end

--- What reads the options when a node needs them (paw/harmony.tl).
local type OptionsFn = function(): Options

local record M
  type Note = Note
  type Options = Options
  reset: function()
end

local options: OptionsFn = function(): Options
  return {
    step = 0.5,
    bar = 4,
    bar_start = function(n: integer): number return (n - 1) * 4 end,
    is_drums = function(): boolean return false end,
  }
end

--- Read the options from `fn` (paw/harmony.tl gives `paw.opt` and `paw.time`).
function M.setup(fn: OptionsFn)
  options = fn
end

-- A key for each part and window, or bar: one number.
local WIDE = 16777216
local function pack(part: integer, i: integer): integer
  return part * WIDE + i
end
local function unpack_key(key: integer): integer, integer
  return key // WIDE, key % WIDE
end

local function same_list<T>(a: {T}, b: {T}): boolean
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

--- The content of a clip: what is read of its notes.
local record ClipKey
  id: integer -- a clip with this content
  stamp: integer
  length: number
  transpose: integer -- the clip's override: its notes sound this much higher
end

--- A clip that sounds, where it is: its content (the notes that sound,
--- in its own beats) and its start. `from` and `to` are where its notes
--- sound in the song.
local record Place
  id: integer
  stamp: integer
  start: number
  length: number
  run: read.Run
  from: number
  to: number
end

--- A part as the reading sees it: its clips that sound, in the order of
--- their start and by where their notes start (with the latest end so far,
--- for a look-up), the end of its last note, and the length of a window
--- (`paw.opt.harmony_step`). Its windows read the length here and not from
--- `harmony.step`: one entry read less for each window that is made again.
local record PartValue
  list: {Place}
  by_from: {Place}
  reach: {number}
  last: number
  step: number
end

--- The clips of a part over a stretch, and the length of a window.
local record Over is {Place}
  step: number
end

--- What a window's scores are made from.
local record WindowInputs
  length: number
  mix: read.Portion
  beat: read.Portion
end

--- What a part's bar is made from.
local record BarInputs is {Place}
  from: number
  to: number
end

--- Where the song ends, and how many windows it has.
local record Span
  last: number
  count: integer
end

local function same_portion(a: read.Portion, b: read.Portion): boolean
  return a == b or same_list(a, b)
end

local function same_weights(a: read.Weights, b: read.Weights): boolean
  for pc = 0, 11 do
    if a[pc] ~= b[pc] then
      return false
    end
  end
  return true
end

local function portion_bytes(p: read.Portion): integer
  return 64 + 8 * #p
end

-- The options -----------------------------------------------------------------------------

local step_now: number = 0.5 -- the step the windows have now
local bars_now: {number} = {} -- the bars as they are now

local step_node_spec: derived.Spec<integer, number, boolean> = {
  name = "harmony.step",
  eager = true,
  kind = "memo",
  make = function(ctx: derived.Ctx): number ctx:option("harmony_step"); step_now = options().step; return step_now end,
  same = function(a: number, b: number): boolean return a == b end,
}
local step_node = derived.node(step_node_spec)

local parts_node_spec: derived.Spec<integer, {integer}, boolean> = {
  name = "harmony.parts",
  eager = true,
  kind = "memo",
  make = function(ctx: derived.Ctx): {integer} return ctx:parts() end,
  same = same_list,
}
local parts_node = derived.node(parts_node_spec)

-- Clips and parts ------------------------------------------------------------------------

local clip_node_spec: derived.Spec<ClipKey, read.Run, boolean> = {
  name = "harmony.clip",
  kind = "family",
  id = function(k: ClipKey): string return string.format("%s:%.17g:%d", tostring(k.stamp), k.length, k.transpose) end,
  -- The notes that a trim of the clip's edges hides are left out, and those
  -- that the transpose takes out of the MIDI range.
  make = function(_: derived.Ctx, k: ClipKey): read.Run
    local notes: {read.Note} = {}
    local list = api.clip_notes(k.id)
    for i_n = 1, #list do
      local n = list[i_n]
      local pitch = n.pitch + k.transpose
      if n.start >= 0 and n.start < k.length and pitch >= 0 and pitch <= 127 then
        notes[#notes + 1] = {
          pitch = pitch,
          start = n.start,
          length = math.min(n.length, k.length - n.start),
          velocity = n.velocity,
        }
      end
    end
    return read.run(notes)
  end,
  bytes = function(r: read.Run): integer return 160 + 36 * r.n end,
  limit = 8 * 1048576,
}
local clip_node = derived.node(clip_node_spec)

-- Whether a part is drums, which the reading leaves out: only a change of
-- its name, meta or devices asks again, not a change of its clips.
local drums_node_spec: derived.Spec<integer, boolean, boolean> = {
  name = "harmony.drums",
  kind = "family",
  make = function(ctx: derived.Ctx, id: integer): boolean
    local t = ctx:part(id, {"name", "meta", "devices"})
    return t ~= nil and options().is_drums(t)
  end,
  same = function(a: boolean, b: boolean): boolean return a == b end,
}
local drums_node = derived.node(drums_node_spec)

-- A clip that does not sound: not MIDI, muted, gone, or with no notes.
local SILENT: Place = {}

-- Each clip on its own: an edit of a clip's notes reads that clip again,
-- not every clip of its part (the kernel gives a clip by its id).
local place_node_spec: derived.Spec<integer, Place, boolean> = {
  name = "harmony.place",
  kind = "family",
  -- The place before, when its content and start are the same: the part
  -- and its windows compare places as they are.
  make = function(ctx: derived.Ctx, id: integer, old: Place): Place
    ctx:source("clip:" .. id)
    local ok, c = pcall(api.clip_get, id)
    if not ok or c.kind ~= "midi" or c.muted then
      return SILENT
    end
    local run = ctx:get(clip_node, {id = id, stamp = c.stamp, length = c.length, transpose = c.transpose or 0})
    if run.n == 0 then
      return SILENT
    end
    if old and old.run == run and old.start == c.start then
      return old
    end
    -- Where the notes sound, added up as `read.portion` adds them: a window
    -- that only touches a changed place is not read again (`touched`).
    local reach: number = -math.huge
    for k = 1, run.n do
      reach = math.max(reach, (c.start + run.start[k]) + run.length[k])
    end
    return {
      id = id,
      stamp = c.stamp,
      start = c.start,
      length = c.length,
      run = run,
      from = c.start + run.start[1],
      to = reach,
    }
  end,
  same = function(a: Place, b: Place): boolean return a == b end,
  limit = 65536,
}
local place_node = derived.node(place_node_spec)

local function by_start(a: Place, b: Place): boolean
  return a.start < b.start or (a.start == b.start and a.id < b.id)
end

local function by_from(a: Place, b: Place): boolean
  return a.from < b.from
end

-- One field of a part: quicker than the whole part, which lists its
-- devices and lanes too. They fail when the part is gone.
local part_mute = api.part_get as function(integer, string): boolean
local part_clips = api.part_get as function(integer, string): {integer}

local part_node_spec: derived.Spec<integer, PartValue, boolean> = {
  name = "harmony.part",
  eager = true,
  kind = "family",
  make = function(ctx: derived.Ctx, id: integer): PartValue
    ctx:source("part:" .. id .. ":mute")
    ctx:source("part:" .. id .. ":clips")
    local v: PartValue = {list = {}, by_from = {}, reach = {}, last = 0, step = ctx:get(step_node, 0)}
    local ok, mute = pcall(part_mute, id, "mute")
    if not ok or mute or ctx:get(drums_node, id) then
      return v
    end
    local clips = part_clips(id, "clips")
    for i = 1, #clips do
      local place = ctx:get(place_node, clips[i])
      if place ~= SILENT then
        v.list[#v.list + 1] = place
        v.by_from[#v.by_from + 1] = place
        v.last = math.max(v.last, place.to)
      end
    end
    table.sort(v.list, by_start)
    table.sort(v.by_from, by_from)
    local reach: number = -math.huge
    for i = 1, #v.by_from do
      local p = v.by_from[i]
      reach = math.max(reach, p.to)
      v.reach[i] = reach
    end
    return v
  end,
  same = function(a: PartValue, b: PartValue): boolean return a.step == b.step and same_list(a.list, b.list) end,
  -- The clips that came or went, or moved: where their notes sound. A new
  -- length of the windows touches all of them.
  touched = function(a: PartValue, b: PartValue): number, number
    if a.step ~= b.step then
      return -math.huge, math.huge
    end
    local from, to = math.huge, -math.huge
    local function add(list: {Place}, other: {Place})
      local kept: {Place: boolean} = {}
      for i_p = 1, #other do
        local p = other[i_p]
        kept[p] = true
      end
      for i_p = 1, #list do
        local p = list[i_p]
        if not kept[p] then
          from, to = math.min(from, p.from), math.max(to, p.to)
        end
      end
    end
    add(a.list, b.list)
    add(b.list, a.list)
    return from, to
  end,
}
local part_node = derived.node(part_node_spec)

--- The places of part value `v` whose notes can sound from `from` to `to`, in `out`.
local function over(v: PartValue, from: number, to: number, out: {Place})
  local list = v.by_from
  -- The last place that starts before `to`.
  local lo, hi = 0, #list
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if list[mid].from < to + 1e-6 then
      lo = mid
    else
      hi = mid - 1
    end
  end
  local k = lo
  while k >= 1 and v.reach[k] > from - 1e-6 do
    if list[k].to > from - 1e-6 then
      out[#out + 1] = list[k]
    end
    k = k - 1
  end
end

-- Windows ---------------------------------------------------------------------------------

local last_over: Over -- the inputs the last part window was given

--- Where window `i` is, as its `make` has it: the same sums give the same
--- edges, so that a note that ends where the window starts is not in it.
local function window_span(i: integer): number, number
  local at = (i - 1) * step_now
  return at, at + step_now
end

local part_window_spec: derived.Spec<integer, read.Portion, Over> = {
  name = "harmony.part_window",
  kind = "family",
  span = function(key: integer): number, number local _, i = unpack_key(key); return window_span(i) end,
  inputs = function(ctx: derived.Ctx, key: integer): Over
    local part, i = unpack_key(key)
    local value = ctx:get(part_node, part)
    local step = value.step
    local at = (i - 1) * step
    local out: Over = {step = step}
    over(value, at, at + step, out)
    -- The windows of one clip have the same inputs: they share them.
    if last_over and last_over.step == step and same_list(last_over, out) then
      return last_over
    end
    last_over = out
    return out
  end,
  same_inputs = function(a: Over, b: Over): boolean return a.step == b.step and same_list(a, b) end,
  undo = true,
  make = function(_: derived.Ctx, key: integer, _: read.Portion, places: Over): read.Portion
    local _, i = unpack_key(key)
    local at = (i - 1) * places.step
    if #places == 1 then
      local p = places[1]
      return read.portion(p.run, p.start, at, at + places.step)
    end
    local portions: {read.Portion} = {}
    for k = 1, #places do
      local p = places[k]
      portions[k] = read.portion(p.run, p.start, at, at + places.step)
    end
    return read.merge(portions)
  end,
  same = same_portion,
  bytes = portion_bytes,
  limit = 16 * 1048576,
}
local part_window = derived.node(part_window_spec)

-- The parts of a window are added up in groups of GROUP: a change of one
-- part adds up its group and the groups, not every part.
local GROUP = 8

local group_node_spec: derived.Spec<integer, read.Portion, boolean> = {
  name = "harmony.group",
  kind = "join",
  make = function(ctx: derived.Ctx, key: integer): read.Portion
    local g, i = unpack_key(key)
    local parts = ctx:get(parts_node, 0)
    local portions: {read.Portion} = {}
    for k = g * GROUP + 1, math.min(#parts, g * GROUP + GROUP) do
      portions[#portions + 1] = ctx:get(part_window, pack(parts[k], i))
    end
    return read.merge(portions)
  end,
  same = same_portion,
  bytes = portion_bytes,
  limit = 4 * 1048576,
}
local group_node = derived.node(group_node_spec)

local mix_node_spec: derived.Spec<integer, read.Portion, boolean> = {
  name = "harmony.mix",
  kind = "join",
  make = function(ctx: derived.Ctx, i: integer): read.Portion
    local portions: {read.Portion} = {}
    for g = 0, (#ctx:get(parts_node, 0) - 1) // GROUP do
      portions[#portions + 1] = ctx:get(group_node, pack(g, i))
    end
    return read.merge(portions)
  end,
  same = same_portion,
  bytes = portion_bytes,
  limit = 4 * 1048576,
}
local mix_node = derived.node(mix_node_spec)

local beat_node_spec: derived.Spec<integer, read.Portion, boolean> = {
  name = "harmony.beat",
  kind = "join",
  make = function(ctx: derived.Ctx, b: integer): read.Portion
    local step = ctx:get(step_node, 0)
    local per = math.floor(1 / step + 0.5)
    local portions: {read.Portion} = {}
    if math.abs(per * step - 1) < 1e-9 then
      -- The windows of the beat, side by side.
      for i = b * per + 1, b * per + per do
        portions[#portions + 1] = ctx:get(mix_node, i)
      end
    else
      -- Windows that do not fit a beat: the notes of every part over it.
      local parts = ctx:get(parts_node, 0)
      for i_part = 1, #parts do
        local part = parts[i_part]
        local places: {Place} = {}
        over(ctx:get(part_node, part), b, b + 1, places)
        for i_p = 1, #places do
          local p = places[i_p]
          portions[#portions + 1] = read.portion(p.run, p.start, b, b + 1)
        end
      end
    end
    return read.merge(portions)
  end,
  same = same_portion,
  bytes = portion_bytes,
  limit = 2 * 1048576,
}
local beat_node = derived.node(beat_node_spec)

local span_node_spec: derived.Spec<integer, Span, boolean> = {
  name = "harmony.span",
  eager = true,
  kind = "join",
  make = function(ctx: derived.Ctx): Span
    local last: number = 0
    local parts = ctx:get(parts_node, 0)
    for i_part = 1, #parts do
      local part = parts[i_part]
      last = math.max(last, ctx:get(part_node, part).last)
    end
    local step = ctx:get(step_node, 0)
    local count = 0
    while count * step < last - 1e-9 do
      count = count + 1
    end
    return {last = last, count = count}
  end,
  same = function(a: Span, b: Span): boolean return a.last == b.last and a.count == b.count end,
}
local span_node = derived.node(span_node_spec)

-- The window that `read.finish` may ask for its beat: no new function for each window.
local beat_ctx: derived.Ctx
local beat_at: number
local function beat_of_window(): read.Portion
  return beat_ctx:get(beat_node, math.floor(beat_at + 1e-9))
end

local window_node_spec: derived.Spec<integer, read.Window, WindowInputs> = {
  name = "harmony.window",
  kind = "family",
  span = window_span,
  inputs = function(ctx: derived.Ctx, i: integer, old: read.Window): WindowInputs
    local step = ctx:get(step_node, 0)
    local at = (i - 1) * step
    local inputs: WindowInputs = {
      length = math.min(step, ctx:get(span_node, 0).last - at),
      mix = ctx:get(mix_node, i),
    }
    if old and old.beat then
      inputs.beat = ctx:get(beat_node, math.floor(at + 1e-9))
    end
    return inputs
  end,
  same_inputs = function(a: WindowInputs, b: WindowInputs): boolean
    return a.length == b.length and a.mix == b.mix and a.beat == b.beat
  end,
  -- The window before goes: its scores are written over.
  make = function(ctx: derived.Ctx, i: integer, old: read.Window, inputs: WindowInputs): read.Window
    local step = ctx:get(step_node, 0)
    local at = (i - 1) * step
    beat_ctx, beat_at = ctx, at
    return read.finish(inputs.mix, at, inputs.length, step, beat_of_window, old)
  end,
  limit = 65536,
}
local window_node = derived.node(window_node_spec)

local decode_rows: {{number}} = {} -- kept for `read.decode` from one reading to the next

local chords_node_spec: derived.Spec<integer, {read.Chord}, boolean> = {
  name = "harmony.chords",
  kind = "sliced",
  label = "chords",
  make = function(ctx: derived.Ctx): {read.Chord}
    ctx:tempo()
    local bar = options().bar
    local windows: {read.Window} = {}
    for i = 1, ctx:get(span_node, 0).count do
      windows[i] = ctx:get(window_node, i)
      if i % 64 == 0 then
        ctx:pause()
      end
    end
    return read.decode(windows, bar, function() ctx:pause() end, decode_rows)
  end,
}
local chords_node = derived.node(chords_node_spec)

-- Bars and keys --------------------------------------------------------------------------

local bars_node_spec: derived.Spec<integer, {number}, boolean> = {
  name = "harmony.bars",
  eager = true,
  kind = "memo",
  make = function(ctx: derived.Ctx): {number}
    ctx:tempo()
    local last = ctx:get(span_node, 0).last
    local opts = options()
    local out, n: {number}, integer = {}, 1
    repeat
      out[#out + 1] = opts.bar_start(n)
      n = n + 1
    until out[#out] > last or n > 100000
    bars_now = out
    return out
  end,
  same = same_list,
}
local bars_node = derived.node(bars_node_spec)

local part_bar_spec: derived.Spec<integer, read.Weights, BarInputs> = {
  name = "harmony.part_bar",
  kind = "family",
  span = function(key: integer): number, number
    local _, b = unpack_key(key)
    return bars_now[b] or -math.huge, bars_now[b + 1] or math.huge
  end,
  inputs = function(ctx: derived.Ctx, key: integer): BarInputs
    local part, b = unpack_key(key)
    local bars = ctx:get(bars_node, 0)
    local out: BarInputs = {from = bars[b], to = bars[b + 1]}
    over(ctx:get(part_node, part), out.from, out.to, out)
    return out
  end,
  same_inputs = function(a: BarInputs, b: BarInputs): boolean
    return a.from == b.from and a.to == b.to and same_list(a, b)
  end,
  undo = true,
  make = function(_: derived.Ctx, _: integer, _: read.Weights, places: BarInputs): read.Weights
    local h: read.Weights = {}
    for pc = 0, 11 do
      h[pc] = 0
    end
    for i_p = 1, #places do
      local p = places[i_p]
      read.bar_part(p.run, p.start, places.from, places.to, h)
    end
    return h
  end,
  same = same_weights,
  limit = 65536,
}
local part_bar = derived.node(part_bar_spec)

local bar_node_spec: derived.Spec<integer, read.Weights, boolean> = {
  name = "harmony.bar",
  kind = "join",
  make = function(ctx: derived.Ctx, b: integer): read.Weights
    local h: read.Weights = {}
    for pc = 0, 11 do
      h[pc] = 0
    end
    local parts = ctx:get(parts_node, 0)
    for i_part = 1, #parts do
      local part = parts[i_part]
      local t = ctx:get(part_bar, pack(part, b))
      for pc = 0, 11 do
        h[pc] = h[pc] + t[pc]
      end
    end
    return h
  end,
  same = same_weights,
  limit = 8192,
}
local bar_node = derived.node(bar_node_spec)

local keys_node_spec: derived.Spec<integer, {read.Key}, boolean> = {
  name = "harmony.keys",
  kind = "sliced",
  label = "keys",
  make = function(ctx: derived.Ctx): {read.Key}
    local bars = ctx:get(bars_node, 0)
    local hist: {read.Weights} = {}
    for b = 1, #bars - 1 do
      hist[b] = ctx:get(bar_node, b)
      if b % 64 == 0 then
        ctx:pause()
      end
    end
    local chords = ctx:get(chords_node, 0)
    return read.key_path(hist, bars, chords, function() ctx:pause() end)
  end,
}
local keys_node = derived.node(keys_node_spec)
keys_node:want(0)

-- The reading ----------------------------------------------------------------------------

--- Whether there is work left before the reading is up to date.
function M.busy(): boolean
  return not keys_node:fresh(0)
end

--- Bring the reading up to date. With `budget`, work for about that many
--- milliseconds: true when it is up to date.
function M.update(budget?: number): boolean
  if budget then
    derived.run(budget)
    return keys_node:fresh(0)
  end
  keys_node:get(0, true)
  return true
end

--- Forget all of it: the next update reads the whole song.
function M.reset()
  step_node:reset()
  parts_node:reset()
  span_node:reset()
  chords_node:reset()
  bars_node:reset()
  keys_node:reset()
  clip_node:reset()
  place_node:reset()
  drums_node:reset()
  part_node:reset()
  part_window:reset()
  group_node:reset()
  mix_node:reset()
  beat_node:reset()
  window_node:reset()
  part_bar:reset()
  bar_node:reset()
end

--- A number that goes up each time the reading may have changed.
function M.stamp(): integer
  return keys_node:revision() + chords_node:revision()
end

--- The chords and the keys as they stand.
function M.reading(): {read.Chord}, {read.Key}
  return chords_node:get(0) or {}, keys_node:get(0) or {}
end

--- The nodes' counts, by name (`paw.derived`).
function M.stats(name: string): derived.Stats
  for _, s in ipairs(derived.stats()) do
    if s.name == name then
      return s
    end
  end
  return nil
end

local notes_list: {Note} -- `notes()`, made when asked
local notes_of: integer -- the revision it was made for

--- Each note that sounds, part by part and clip by clip, as of the last
--- update.
function M.notes(): {Note}
  local revision = parts_node:revision() * WIDE + part_node:revision()
  if not notes_list or notes_of ~= revision then
    local out: {Note} = {}
    for _, part in ipairs(parts_node:get(0) or {}) do
      local v = part_node:get(part)
      for _, place in ipairs(v and v.list or {}) do
        local run = place.run
        for k = 1, run.n do
          out[#out + 1] = {
            pitch = run.pitch[k],
            start = place.start + run.start[k],
            length = run.length[k],
            velocity = run.velocity[k],
            part = part,
            clip = place.id,
          }
        end
      end
    end
    notes_list, notes_of = out, revision
  end
  return notes_list
end

--- The reading of all the notes at once, as `paw.harmony.read` makes it,
--- with windows from the start of the song: what the nodes must give.
--- `notes` sorted by start.
function M.whole(notes: {Note}, opts: Options): {read.Chord}, {read.Key}
  local run = read.run(notes)
  local step = opts.step
  local last: number = 0
  for i_n = 1, #notes do
    local n = notes[i_n]
    last = math.max(last, n.start + n.length)
  end
  local windows: {read.Window} = {}
  local i = 1
  while (i - 1) * step < last - 1e-9 do
    local at = (i - 1) * step
    local beat = math.floor(at + 1e-9)
    windows[i] = read.finish(
      read.portion(run, 0, at, at + step),
      at,
      math.min(step, last - at),
      step,
      function(): read.Portion return read.portion(run, 0, beat, beat + 1) end
    )
    i = i + 1
  end
  local chords = read.decode(windows, opts.bar)
  local bars, n: {number}, integer = {}, 1
  repeat
    bars[#bars + 1] = opts.bar_start(n)
    n = n + 1
  until bars[#bars] > last or n > 100000
  local hist: {read.Weights} = {}
  for b = 1, #bars - 1 do
    local h: read.Weights = {}
    for pc = 0, 11 do
      h[pc] = 0
    end
    read.bar_part(run, 0, bars[b], bars[b + 1], h)
    hist[b] = h
  end
  return chords, read.key_path(hist, bars, chords)
end

return M
