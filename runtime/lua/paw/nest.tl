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
local type GroupsModule = require("paw.groups")

--- `paw.track_kinds` (paw/track_kinds.lua), the part this module calls.
local record TrackKinds
  kinds: {string: contracts.TrackKind}
  add: function(name: string, opts: {string: string}): objects.Track
end

local record Paw is partial.Paw
  cursor: CursorModule
  markers: MarkersModule
  scope: ScopeModule
  groups: GroupsModule
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

--- A clip that places a subproject, and the row it is on.
local record Block
  clip: types.Clip
  row: integer
end

--- An entry of `:nest.list`: a block, or a subproject that no block plays.
local record Item
  nest: integer
  clip: integer
  label: string
end

local record M
  type NewOptions = NewOptions
  type Made = Made
  type Block = Block
  type Item = Item
  source: contracts.PickSource<Item>
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

-- Blocks: the clips that place a subproject ----------------------------------------------

local clip_list = api.clip_list as function(track: integer, from?: number, to?: number): {types.Clip}
local track_nest = api.track_get as function(id: integer, key: string): integer
local track_name = api.track_get as function(id: integer, key: string): string

--- A track's name.
local function name_of(id: integer): string
  return track_name(id, "name")
end

--- The subproject a track belongs to, or nil for a track of the song.
local function nest_of(track: integer): integer
  local ok, n = pcall(track_nest, track, "nest") as (boolean, integer)
  return ok and n or nil
end

--- The track that a clip plays alone (a stem), or nil when it plays the mix.
local function stem_of(c: types.Clip): integer
  local play = c.play
  if play is types.NestTrack then
    return play.track
  end
  return nil
end

--- Every clip that places subproject `nest`, in order of time.
function M.blocks(nest: integer): {Block}
  local out: {Block} = {}
  for _, id in ipairs(api.track_list({all = true})) do
    for _, c in ipairs(clip_list(id)) do
      if c.nest == nest then
        out[#out + 1] = {clip = c, row = id}
      end
    end
  end
  table.sort(
    out,
    function(a: Block, b: Block): boolean
      if a.clip.start ~= b.clip.start then
        return a.clip.start < b.clip.start
      end
      return a.clip.id < b.clip.id
    end
  )
  return out
end

--- How many times the song plays a subproject: its blocks, counting the
--- stems of one block once.
local function instances(nest: integer): integer
  local seen: {string: boolean} = {}
  local n = 0
  for _, b in ipairs(M.blocks(nest)) do
    local key = string.format("%.9g:%.9g", b.clip.start, b.clip.offset or 0)
    if not seen[key] then
      seen[key], n = true, n + 1
    end
  end
  return n
end

--- The notes that a block plays, from its start, for the small picture
--- inside it: { start, length, pitch } each, at most `limit`.
function M.notes(c: types.Clip, limit?: integer): {types.Note}
  local out: {types.Note} = {}
  local offset, length = c.offset or 0, c.length
  local only = stem_of(c)
  limit = limit or 2000
  for _, t in ipairs(api.track_list({nest = c.nest})) do
    if not only or only == t then
      for _, inner in ipairs(clip_list(t, offset, offset + length)) do
        if inner.kind == "midi" and inner.note_count > 0 then
          local notes: {types.Note} = api.clip_notes(inner.id)
          for _, n in ipairs(notes) do
            local at = inner.start + n.start - offset
            if n.start < inner.length and at >= 0 and at < length and #out < limit then
              out[#out + 1] = {start = at, length = n.length, pitch = n.pitch, velocity = n.velocity}
            end
          end
        end
      end
    end
  end
  return out
end

--- A key that changes when what a block plays changes: the stamps of the
--- clips of its subproject, and the block's own place in it.
function M.content_key(c: types.Clip): string
  local sum = 0.0
  for _, t in ipairs(api.track_list({nest = c.nest})) do
    for _, inner in ipairs(clip_list(t)) do
      sum = sum + (inner.stamp or 0) + inner.start * 7 + inner.length * 13
    end
  end
  return string.format("nest|%d|%.17g|%.17g|%.17g", c.nest, c.offset or 0, c.length, sum)
end

--- `K` on a block: `nest Ballad · 6/8 · 8 bars · follows the tempo ·
--- 2 tracks · 1 instance · live`. `c` is the clip, in the window's time.
function M.describe(c: types.Clip): string
  local n = M.get(c.nest)
  if not n then
    return "a subproject that is gone"
  end
  local meter: string
  local bars: number
  if n.meter and n.meter.mode == "own" and n.meter.changes and n.meter.changes[1] then
    local first = n.meter.changes[1]
    meter = first.num .. "/" .. first.den
    bars = n.length / (first.num * 4 / first.den)
  else
    local zero = c.start - (c.offset or 0)
    local num, den = paw.time.signature_at(zero)
    meter = num .. "/" .. den .. " of the song"
    bars = paw.time.bar_of(zero + n.length - 1e-6) - paw.time.bar_of(zero) + 1
  end
  local count = instances(c.nest)
  return string.format(
    "nest %s · %s · %g bar%s · %s · %d track%s · %d instance%s · live%s",
    n.name,
    meter,
    bars,
    bars == 1 and "" or "s",
    (n.tempo and n.tempo.mode == "own") and "own tempo" or "follows the tempo",
    #n.tracks,
    #n.tracks == 1 and "" or "s",
    count,
    count == 1 and "" or "s",
    stem_of(c) and (" · the stem " .. name_of(stem_of(c))) or ""
  )
end

-- In place: `za` on a return row -------------------------------------------------------

--- The return rows open in place, and the subproject each shows. View
--- state: no undo step, not saved.
local open: {integer: integer} = {}

--- The first block on a row that plays the whole of subproject `nest`,
--- or nil.
local function block_on(row: integer, nest: integer): types.Clip
  for _, c in ipairs(clip_list(row)) do
    if c.nest == nest and not stem_of(c) then
      return c
    end
  end
end

--- The subproject a row returns (its first block that plays the mix), or nil.
local function returned(row: integer): integer
  for _, c in ipairs(clip_list(row)) do
    if c.nest and not stem_of(c) then
      return c.nest
    end
  end
end

--- Whether the window shows the place of a row: the song, or the
--- subproject the row is in.
local function shows_place_of(row: integer): boolean
  local here = paw.scope.nest()
  return (here and here.id or nil) == nest_of(row)
end

--- The tracks to draw under a row that is open in place, or nil
--- (`paw.groups.rows` asks for each row).
function M.under(row: integer): {integer}
  local n = open[row]
  if not n then
    return nil
  end
  if not (shows_place_of(row) and block_on(row, n)) then
    return nil
  end
  return api.track_list({nest = n})
end

--- For a track of a subproject shown in place under its return row: the
--- beat of the window where the subproject's beat 0 is. Nil for any other
--- track. The arrange view draws its clips that much later, and the
--- cursor finds them there.
function M.shift(track: integer): number
  if next(open) == nil then
    return nil
  end
  local n = nest_of(track)
  if not n then
    return nil
  end
  for row, shown in pairs(open) do
    if shown == n and shows_place_of(row) then
      local c = block_on(row, n)
      if c then
        return c.start - (c.offset or 0)
      end
    end
  end
  return nil
end

--- `za` on a return row: open its subproject's tracks under it, in the
--- song's time, or close them. On a track shown in place: close its row.
--- False when the track is neither.
function M.toggle(track: integer): boolean
  for row, n in pairs(open) do
    if nest_of(track) == n and row ~= track then
      open[row] = nil
      paw.cursor.set_track(row)
      api.ui_redraw()
      return true
    end
  end
  local n = returned(track)
  if not n then
    return false
  end
  if open[track] then
    open[track] = nil
  else
    open[track] = n
  end
  api.ui_redraw()
  return true
end

--- Whether a row is open in place.
function M.is_open(row: integer): boolean
  return open[row] ~= nil
end

-- The list: `:nest.list` ---------------------------------------------------------------

local function items(): {Item}
  local out: {Item} = {}
  for _, n in ipairs(M.list()) do
    local blocks = M.blocks(n.id)
    if #blocks == 0 then
      out[#out + 1] = {nest = n.id, label = string.format("%s · unused · %d tracks", n.name, #n.tracks)}
    end
    for _, b in ipairs(blocks) do
      local row = name_of(b.row)
      out[#out + 1] = {
        nest = n.id,
        clip = b.clip.id,
        label = string.format(
          "%s · bar %d on %s · %d tracks%s",
          n.name,
          paw.time.bar_of(b.clip.start),
          row,
          #n.tracks,
          stem_of(b.clip) and (" · stem " .. name_of(stem_of(b.clip))) or ""
        ),
      }
    end
  end
  return out
end

--- Enter the subproject of an entry, from the song.
local function choose(item: Item)
  local s: contracts.Scope = {kind = "nest", id = item.nest, clip = item.clip}
  local ok, err = pcall(paw.scope.enter, s) as (boolean, string)
  if not ok then
    paw.scope.widen(true)
    ok, err = pcall(paw.scope.enter, s) as (boolean, string)
  end
  if not ok then
    paw.notify(tostring(err), "warn")
    return
  end
  paw.notify(paw.scope.breadcrumb())
end

M.source = {
  desc = "Enter a subproject: each block, and the subprojects that no block plays",
  title = "Subprojects",
  empty = "No subproject: `<Space>za` adds one.",
  items = items,
  format = function(item: Item): string return item.label end,
  primary = function(item: Item): string return item.label end,
  search = function(item: Item): string return item.label end,
  on_choose = choose,
} as contracts.PickSource<Item>

commands.define(
  "nest.list",
  function(): contracts.CommandResult commands.run("pick", {"nests"}) end,
  {desc = "List the subprojects, their blocks and the unused ones; choose one to enter it"}
)

-- Outputs: one stereo return, or stems ---------------------------------------------------

local track_meta = api.track_get as function(id: integer, key: string): types.Meta

--- The meta of a track, a copy to change.
local function meta_of(id: integer): types.Meta
  local out: types.Meta = {}
  local ok, m = pcall(track_meta, id, "meta")
  for k, v in pairs(ok and m or {}) do
    out[k] = v
  end
  return out
end

local function set_meta(id: integer, m: types.Meta)
  api.track_set(id, {meta = m})
end

--- The stem rows of a subproject under a row: tracks marked `nest_stem`.
local function stem_rows(row: integer, nest: integer): {integer}
  local out: {integer} = {}
  for _, id in ipairs(api.track_list({all = true})) do
    local m = meta_of(id)
    if m.group == row and m.nest_stem == nest then
      out[#out + 1] = id
    end
  end
  return out
end

--- The subproject and the return row at the cursor: the block under the
--- cursor, else the row's block, else the group row of its stems.
local function at_cursor(): integer, integer
  local id = paw.cursor.track_id()
  if not id or id == 0 then
    return nil, nil
  end
  local m = meta_of(id)
  if m.nest_stem then
    return m.nest_stem as integer, m.group as integer
  end
  local n = returned(id)
  if n then
    return n, id
  end
  for _, other in ipairs(api.track_list({all = true})) do
    local om = meta_of(other)
    if om.group == id and om.nest_stem then
      return om.nest_stem as integer, id
    end
  end
  return nil, nil
end

--- Give a subproject one row of its own for each of its tracks (`stems`),
--- or one stereo return again (`master`), on its return row `row`. Call it
--- in one undo step. Returns the message.
function M.outputs(nest: integer, row: integer, how: string): string
  local n = M.get(nest)
  if not n then
    error("no subproject " .. tostring(nest), 0)
  end
  local m = meta_of(row)
  if how == "stems" then
    local blocks: {types.Clip} = {}
    for _, c in ipairs(clip_list(row)) do
      if c.nest == nest and not stem_of(c) then
        blocks[#blocks + 1] = c
      end
    end
    if #blocks == 0 then
      error(n.name .. " has stems already: `:nest.outputs master` gives one row again", 0)
    end
    if #n.tracks == 0 then
      error(n.name .. " has no tracks to make stems of", 0)
    end
    if m.group_head then
      error(name_of(row) .. " is a group already", 0)
    end
    -- The row becomes a group: the stems play into it, and its fader,
    -- sends and devices act on their sum, as on the stereo return.
    m.group_head, m.nest_stems = true, nest
    set_meta(row, m)
    local names: {string} = {}
    for i, t in ipairs(n.tracks) do
      local name = name_of(t)
      names[i] = name
      local stem = api.track_add({name = name, nest = nest_of(row)})
      local sm = meta_of(stem)
      sm.nest_stem = nest
      set_meta(stem, sm)
      for _, c in ipairs(blocks) do
        local made = api.clip_add(
          stem,
          {nest = nest, start = c.start, length = c.length, offset = c.offset, play = {track = t}} as types.ClipOptions
        )
        if c.muted then
          api.clip_set(made, {muted = true})
        end
      end
      paw.groups.add(stem, row)
    end
    for _, c in ipairs(blocks) do
      api.clip_remove(c.id)
    end
    return string.format(
      "%s: a stem row for each track, %s, under %s", n.name, table.concat(names, " and "), name_of(row)
    )
  elseif how == "master" then
    local stems = stem_rows(row, nest)
    if #stems == 0 then
      error(n.name .. " has one row already", 0)
    end
    -- The blocks again, where the first stem's are.
    for _, c in ipairs(clip_list(stems[1])) do
      if c.nest == nest then
        local made = api.clip_add(
          row, {nest = nest, start = c.start, length = c.length, offset = c.offset} as types.ClipOptions
        )
        if c.muted then
          api.clip_set(made, {muted = true})
        end
      end
    end
    for _, s in ipairs(stems) do
      api.track_remove(s)
    end
    m = meta_of(row)
    m.nest_stems = nil
    if #paw.groups.members(row) == 0 then
      m.group_head, m.group_folded = nil, nil
    end
    set_meta(row, m)
    return string.format("%s: one row again, %s", n.name, name_of(row))
  end
  error("nest.outputs takes stems or master, not " .. tostring(how), 0)
end

commands.define(
  "nest.outputs",
  function(ctx: contracts.CommandContext): contracts.CommandResult
    local how = tostring(ctx.args[1] or "")
    local nest, row = at_cursor()
    if not nest then
      error("not on a subproject's row: put the cursor on its block", 0)
    end
    paw.notify(M.outputs(nest, row, how))
  end,
  {
    label = "Change the outputs of the subproject",
    desc = "Give the subproject at the cursor a row for each of its tracks, under its row (`nest.outputs stems`), or one row again (`nest.outputs master`)",
    complete = function(): {string} return {"stems", "master"} end,
  }
)

-- Promote: a subproject becomes a view ---------------------------------------------------

--- The block at the cursor: the clip under it when it places a
--- subproject, else the block on the cursor's row; inside a subproject,
--- the block the window entered it through.
local function block_at_cursor(): types.Clip
  local here = paw.scope.nest()
  if here and here.clip then
    local ok, c = pcall(api.clip_get, here.clip) as (boolean, types.Clip)
    if ok and c and c.nest == here.id then
      return c
    end
  end
  local clip = paw.cursor.clip()
  if clip then
    local c = api.clip_get(clip.id)
    if c.nest then
      return c
    end
  end
  local id = paw.cursor.track_id()
  local n = id and id ~= 0 and returned(id)
  return n and block_on(id, n) or nil
end

--- A region over `from..to` of the song named `name`: the one there, or a new one.
local function region_over(from: number, to: number, name: string): MarkersModule.Marker
  for _, m in ipairs(paw.markers.regions()) do
    if math.abs(m.beat - from) < 1e-9 and math.abs(m.beat + m.length - to) < 1e-9 then
      return m
    end
  end
  return paw.markers.add(from, name, {length = to - from})
end

--- Promote the subproject of block `clip` to a view, as `:nest.promote`
--- does: its tracks come back in a group named after it at the place of
--- its return row (`paw.api.nest_promote`); its regions come back as
--- children of a region named after it over the block (made if there is
--- none); its own meter goes into the song's map over the block; and the
--- window that was inside it is now inside a view of the group's tracks
--- over the region's time, at the same place. With `deep`, the
--- subprojects inside it too. Call it in one undo step. Returns the message.
function M.promote(clip: integer, deep?: boolean): string
  local c = api.clip_get(clip)
  local n = c and c.nest and M.get(c.nest)
  if not n then
    error("not a block of a subproject: put the cursor on one", 0)
  end
  local markers = (n.meta and n.meta.markers or {}) as {MarkersModule.Marker}
  local inside = paw.scope.nest()
  local was_inside = inside and inside.id == n.id
  local track, beat = paw.cursor.track_id(), paw.cursor.beat
  local r = api.nest_promote(clip)
  -- Its meter, where the song plays it.
  local own = n.meter and n.meter.mode == "own" and n.meter.changes and n.meter.changes[1]
  local wrote = false
  if own then
    local num, den = api.tempo_signature(r.from)
    if not (num == own.num and den == own.den) then
      write_meter(r.from, r.to, own.num, own.den)
      wrote = true
    end
  end
  -- The bars of the message, with its meter in the song's map.
  local where = bars_text(r.from, r.to)
  -- Its regions, inside a region named after it.
  local parent = region_over(r.from, r.to, n.name)
  local regions = 0
  for _, m in ipairs(markers) do
    local at = m.beat + r.zero
    if at >= r.from - 1e-9 and at < r.to then
      local length = m.length and math.min(m.length, r.to - at) or nil
      paw.markers.add(at, m.name, {length = length, color = m.color})
      regions = regions + 1
    end
  end
  -- The view that takes its place: the group's tracks over the region's time.
  local tracks: {integer} = {r.group}
  for _, id in ipairs(r.tracks) do
    tracks[#tracks + 1] = id
  end
  paw.scope.widen(true)
  paw.scope.enter({kind = "range", tracks = tracks, from = parent.beat, to = parent.beat + parent.length})
  paw.scope.name(n.name)
  if was_inside then
    paw.cursor.set_track(track)
    paw.cursor.set_beat(beat + r.zero)
  else
    paw.cursor.set_track(r.group)
    paw.cursor.set_beat(r.from)
  end
  local words = {
    string.format(
      "promoted %s: %d track%s in the group %s, %s", n.name, #r.tracks, #r.tracks == 1 and "" or "s", n.name, where
    ),
  }
  if regions > 0 then
    words[#words + 1] = string.format("%d regions inside the region %s", regions, n.name)
  end
  if wrote then
    words[#words + 1] = string.format("%d/%d in the song's map", own.num, own.den)
  end
  if #r.combined > 0 then
    words[#words + 1] = "its master's and its row's lanes made one: " .. table.concat(r.combined, ", ")
  end
  -- The subprojects inside it, with `!`.
  if deep then
    for _, id in ipairs(r.tracks) do
      for _, inner in ipairs(clip_list(id)) do
        if inner.nest and not stem_of(inner) then
          local ok, said = pcall(M.promote, inner.id, true) as (boolean, string)
          words[#words + 1] = ok and said or (n.name .. " keeps a subproject: " .. tostring(said))
        end
      end
    end
  end
  return table.concat(words, "; ")
end

for _, bang in ipairs({"", "!"}) do
  commands.define(
    "nest.promote" .. bang,
    function(): contracts.CommandResult
      local c = block_at_cursor()
      if not c then
        error("not on a block of a subproject: put the cursor on one", 0)
      end
      paw.notify(M.promote(c.id, bang == "!"))
    end,
    {
      label = "Promote the subproject to a view",
      desc = bang == ""
        and "Promote the subproject at the cursor to a view: its tracks come back into the song in a group named after it, and a view of them takes its place" or "Promote the subproject at the cursor to a view, and the subprojects inside it too",
    }
  )
end

-- The rows in place: the arrange view and the cursor ask here.
paw.groups.under = M.under
paw.cursor.shift = M.shift

return M
