-- Subprojects (nests): tracks with a timeline of their own, placed in the
-- song by nest clips. The kernel keeps them (crates/paw-core/src/model/nest.rs)
-- and saves each in `nests/<name>/` of the project's folder; this module
-- reads them and makes new ones.
--
--   paw.nest.list()        -- every subproject, in the order they were made
--   paw.nest.get(id)       -- one subproject, or nil
--   paw.nest.new({ name = "Ballad", bars = 8, num = 6, den = 8 })
--
-- A subproject made with `paw.nest.new` (`:nest.new`, `<Space>za`) has a
-- row of its own in the song, its return row: a usual track whose clip
-- (the block) plays the subproject's mix. Its tracks are usual tracks with
-- a `nest`. Lower down: `paw.api.nest_add({ name = "Bridge", length = 32 })`,
-- then `paw.api.track_add({ nest = id })` for each of its tracks.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local commands = require("paw.commands")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type objects = require("paw.objects")
local type CursorModule = require("paw.cursor")
local type MarkersModule = require("paw.markers")
local type ScopeModule = require("paw.scope")

--- `paw.track_kinds` (paw/track_kinds.lua), the part this module calls.
local record TrackKinds
  kinds: {string: contracts.TrackKind}
  add: function(name: string, opts: {string: string}): objects.Track
end

local record Paw is partial.Paw
  cursor: CursorModule
  markers: MarkersModule
  scope: ScopeModule
  time: objects.Time
  add_track: function(opts?: objects.TrackInput): objects.Track
end
local paw = (_G as {string: Paw}).paw

--- What `paw.nest.new` takes. Beats are of the window's time.
local record NewOptions
  --- The subproject's name, and its row's: "Ballad".
  name: string
  --- How many bars from `from`: 8 when no time is given.
  bars: integer
  --- A meter of its own (`6/8`): written into the song's map over its time.
  num: integer
  den: integer
  --- Its time; `from` alone: `bars` bars from there.
  from: number
  to: number
  --- The track its row goes below: the cursor's when nil.
  below: integer
end

--- What `paw.nest.new` made.
local record Made
  nest: integer
  row: integer
  clip: integer
  track: integer
  message: string
end

local record M
  type NewOptions = NewOptions
  type Made = Made
end

local opt = options.opt
options.define(
  "nest_track", "track"
) -- the track a new subproject starts with: "track" (a plain track, as `o` adds), or a kind of track (`vocal`)

--- Every subproject, in the order they were made: { id, name, length,
--- tempo, meter, master, tracks, kind, meta, used }.
function M.list(): {types.Nest}
  local out: {types.Nest} = {}
  for _, id in ipairs(api.nest_list()) do
    out[#out + 1] = api.nest_get(id)
  end
  return out
end

--- The subproject `id`, or nil when there is none.
function M.get(id: integer): types.Nest
  local ok, nest = pcall(api.nest_get, id) as (boolean, types.Nest)
  if ok then
    return nest
  end
  return nil
end

-- Making one ----------------------------------------------------------------------------

--- The bars from one beat of the window to another, as a message names
--- them: "bars 33-40", or "bar 33".
local function bars_text(from: number, to: number): string
  local offset = paw.scope.bar_offset()
  local a = paw.time.bar_of(from) - offset
  local b = paw.time.bar_of(math.max(from, to - 1e-6)) - offset
  return a == b and ("bar " .. a) or string.format("bars %d-%d", a, b)
end

--- Write a meter into the song's map from song beat `from` to `to`, and the
--- meter that was at `to` back after it. Changes inside go: the section has
--- one meter.
local function write_meter(from: number, to: number, num: integer, den: integer)
  local back_num, back_den = api.tempo_signature(to)
  for _, s in ipairs(api.tempo_points().signatures) do
    if s.beat > from + 1e-9 and s.beat < to - 1e-9 then
      api.signature_remove(s.beat)
    end
  end
  api.signature_set(from, num, den)
  local at_end = false
  for _, s in ipairs(api.tempo_points().signatures) do
    if math.abs(s.beat - to) < 1e-9 then
      at_end = true
    end
  end
  if not at_end and not (back_num == num and back_den == den) then
    api.signature_set(to, back_num, back_den)
  end
end

--- The first track of a new subproject, in the window that is inside it:
--- `paw.opt.nest_track`.
local function first_track(): objects.Track
  local kind = opt.nest_track as string
  local kinds = (paw.track_kinds as TrackKinds)
  if kind and kind ~= "" and kind ~= "track" then
    if not kinds.kinds[kind] then
      error("nest_track is `" .. kind .. "`, which is no kind of track here", 0)
    end
    return kinds.add(kind, {})
  end
  return paw.add_track()
end

--- Make a subproject with a row of its own, as `:nest.new` does (see the
--- top): the subproject over the time given, a return row below the
--- track `below` with one block, the meter in the song's map when one is
--- given; then the window enters it, with one empty track
--- (`paw.opt.nest_track`). Call it in one undo step (a command is one).
function M.new(o: NewOptions): Made
  local from = o.from or paw.time.bar_floor(paw.cursor.beat)
  local to = o.to
  local bars = o.bars or 8
  if o.num and o.den then
    if not (
      o.num >= 1
      and o.num <= 64
      and (o.den == 1 or o.den == 2 or o.den == 4 or o.den == 8 or o.den == 16 or o.den == 32)
    ) then
      error(string.format("%d/%d is not a meter", o.num, o.den), 0)
    end
    to = to or (from + bars * o.num * 4 / o.den)
  else
    to = to or paw.time.bar_start(paw.time.bar_of(from) + bars)
  end
  if not (to > from) then
    error("a subproject needs some time", 0)
  end
  local name = o.name and o.name:match("^%s*(.-)%s*$") or ""
  if name == "" then
    name = "Subproject " .. (#api.nest_list() + 1)
  end
  local place = paw.scope.nest()
  local song_from = from + paw.time.origin()
  local meter: types.NestMeter = nil
  if o.num then
    meter = {mode = "own", changes = {{beat = 0, num = o.num, den = o.den}}}
    write_meter(song_from, song_from + (to - from), o.num, o.den)
  end
  -- The words of the message: the song's bars, the meter written.
  local where = bars_text(from, to)
  local nest = api.nest_add({name = name, length = to - from, meter = meter})
  -- The return row, below the track given (in the place the window shows).
  local below = o.below or paw.cursor.track_id()
  local index: integer
  for i, id in ipairs(api.track_list({nest = place and place.id or nil})) do
    if id == below then
      index = i + 1
    end
  end
  local row = paw.add_track({name = name, index = index})
  local clip = api.clip_add(row.id, {nest = nest, start = from} as types.ClipOptions)
  paw.scope.enter({kind = "nest", id = nest, clip = clip})
  local track = first_track()
  paw.cursor.set_track(track.id)
  paw.cursor.set_beat(0)
  local message = string.format(
    "added the subproject %s over %s%s, on its own row; inside it now: `zw` goes back",
    name,
    where,
    o.num and string.format(" in %d/%d", o.num, o.den) or ""
  )
  return {nest = nest, row = row.id, clip = clip, track = track.id, message = message}
end

--- `:nest.new`'s words: a meter (`6/8`), a number of bars (`8`), and the
--- rest is the name; or `name=`, `bars=`, `meter=`.
local function parse(args: contracts.CommandArgs): NewOptions
  local o: NewOptions = {}
  local words: {string} = {}
  local function meter(text: string)
    local num, den = text:match("^(%d+)/(%d+)$")
    o.num, o.den = math.tointeger(tonumber(num)), math.tointeger(tonumber(den))
  end
  for _, arg in ipairs(args as {string}) do
    local word = tostring(arg)
    if word:match("^%d+/%d+$") then
      meter(word)
    elseif word:match("^%d+$") and not o.bars then
      o.bars = math.tointeger(tonumber(word))
    else
      words[#words + 1] = word
    end
  end
  local named = args as {string: string}
  if named.meter then
    if not tostring(named.meter):match("^%d+/%d+$") then
      error("a meter is written 6/8, not " .. tostring(named.meter), 0)
    end
    meter(tostring(named.meter))
  end
  if named.bars then
    o.bars = math.tointeger(tonumber(named.bars))
  end
  o.name = named.name and tostring(named.name) or table.concat(words, " ")
  if o.bars and o.bars < 1 then
    error("a subproject is a bar long at least", 0)
  end
  return o
end

commands.define(
  "nest.new",
  function(ctx: contracts.CommandContext): contracts.CommandResult
    local o = parse(ctx.args)
    local r = ctx.range
    if r and r.from and r.to and r.to > r.from then
      -- Over the selection or the range typed.
      o.from, o.to = r.from, r.to
    elseif not o.bars and not paw.scope.nest() and paw.markers then
      -- The region at the cursor, if any.
      local path = paw.markers.path(paw.cursor.beat)
      local region = path[#path]
      if region and region.length then
        o.from, o.to = region.beat, region.beat + region.length
        if o.name == "" then
          o.name = region.name
        end
      end
    end
    local made = M.new(o)
    paw.notify(made.message)
  end,
  {
    range = true,
    label = "Add a subproject",
    desc = "Add a subproject with its own row and tracks, and go inside: `nest.new Ballad 8 6/8` (8 bars of 6/8 from the cursor's bar); over the selection or the region at the cursor when no bars are given",
  }
)

return M
