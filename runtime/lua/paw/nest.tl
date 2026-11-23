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
local events = require("paw.events")
local registry = require("paw.registry")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type objects = require("paw.objects")
local type CursorModule = require("paw.cursor")
local type MarkersModule = require("paw.markers")
local type ScopeModule = require("paw.scope")
local type GroupsModule = require("paw.groups")
local type registry = require("paw.registry")

--- `paw.track_kinds` (paw/track_kinds.lua), the part this module calls.
local record TrackKinds
  kinds: registry.Registry<contracts.TrackKind>
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

local clip_list = api.clip_list as function(track: integer, from?: number, to?: number): {types.Clip}

--- What `paw.nest.new` takes. Beats are of the window's time.
local record NewOptions
  --- The subproject's name, and its row's: "Ballad".
  name: string
  --- How many bars from `from`: 8 when no time is given.
  bars: integer
  --- A meter of its own (`6/8`): written into the song's map over its time,
  --- unless `polymeter`: then the song's map stays as it is.
  num: integer
  den: integer
  polymeter: boolean
  --- A tempo of its own, the song's tempo at its start to begin with.
  own_tempo: boolean
  --- Its time; `from` alone: `bars` bars from there.
  from: number
  to: number
  --- The track its row goes below: the cursor's when nil.
  below: integer
  --- A kind of subproject (`paw.nest.define_kind`): its `create` makes
  --- the tracks, in place of the one empty track.
  kind: string
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

--- A kind's data as this module keeps it: it gives it to the kind's own
--- functions and never reads it.
local record Data
end

--- The payload of `nest.enter` and `nest.leave`: the subproject, the
--- window, and the block that the window went in through (nil when none).
local record Crossed
  nest: integer
  win: integer
  clip: integer
end

--- The payload of `nest.changed`: the subproject, and the undo step of
--- the edit (`paw.api.undo_current`).
local record Changed
  nest: integer
  state: integer
end

local record M
  type NewOptions = NewOptions
  type Made = Made
  type Block = Block
  type Item = Item
  type Data = Data
  type Crossed = Crossed
  type Changed = Changed
  source: contracts.PickSource<Item>
  --- The kinds of subproject that are defined, by name, with the
  --- extension that defined each one.
  kinds: registry.Registry<contracts.NestKind<Data>>
  --- The event `nest.enter`: a window went inside a subproject.
  entered: events.Event<Crossed>
  --- The event `nest.leave`: a window came out of a subproject.
  left: events.Event<Crossed>
  --- The event `nest.changed`: an edit changed the tracks, clips, devices
  --- or lanes of a subproject. It comes once for each undo step.
  changed: events.Event<Changed>
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

-- Kinds of subproject, and its events -------------------------------------------------

M.kinds = registry.new("nest_kinds", "kinds of subproject")
M.entered = events.event("nest.enter")
M.left = events.event("nest.leave")
M.changed = events.event("nest.changed")

--- Define a kind of subproject that `:nest.new kind=<name>` makes, such
--- as a drum pattern that opens in a step grid. `spec` gives `title`,
--- `letter`, `create(region)`, `enter(nest)` and `describe(nest)`, each
--- optional (`paw.contracts.NestKind`). The kind's data is in the
--- subproject's `meta` under the kind's name: read it with
--- `paw.nest.data(nest)`. Without the kind, the subproject plays and the
--- arrange view edits it. Returns the spec.
function M.define_kind<D>(name: string, spec: contracts.NestKind<D>): contracts.NestKind<D>
  if not (name is string and name:match("^[%w_][%w_.-]*$")) then
    error("a kind of subproject has a name of letters, digits, `_`, `-` and `.`: " .. tostring(name), 2)
  end
  spec.name = name
  spec.title = spec.title or name
  spec.letter = spec.letter or name:sub(1, 1):upper()
  M.kinds:put(name, spec as contracts.NestKind<Data>)
  return spec
end

--- The kind of subproject `nest` as defined, or nil: for a plain
--- subproject, and for one whose kind no extension here defines.
function M.kind<D>(nest: integer): contracts.NestKind<D>
  local n = M.get(nest)
  if n and n.kind then
    return M.kinds:get(n.kind) as contracts.NestKind<D>
  end
  return nil
end

--- The data of subproject `nest`'s kind: what its `create` gave, or what
--- `paw.nest.set_data` stored last. Nil for a plain subproject.
function M.data<D>(nest: integer): D
  local n = M.get(nest)
  if n and n.kind and n.meta then
    return n.meta[n.kind] as D
  end
  return nil
end

--- Store the data of subproject `nest`'s kind, as one undo step.
function M.set_data<D>(nest: integer, data: D)
  local n = M.get(nest)
  if not (n and n.kind) then
    error("subproject " .. tostring(nest) .. " has no kind to keep data for", 2)
  end
  local meta = n.meta or {}
  meta[n.kind] = data
  api.nest_set(nest, {meta = meta} as types.Nest)
end

--- The letter of the kind of subproject `nest`, which its blocks show
--- after `⧉`, or nil for a plain subproject.
function M.letter(nest: integer): string
  local kind = M.kind(nest) as contracts.NestKind<Data>
  return kind and kind.letter
end

--- Make the tracks of a new subproject of `kind` with its `create`, and
--- keep the data it gives. A kind that makes no track gets one empty
--- track. Gives the first track of the subproject.
local function create(kind: contracts.NestKind<Data>, region: contracts.NestRegion): integer
  if kind.create then
    local data, why = kind.create(region)
    if why then
      error(kind.title .. ": " .. why, 0)
    end
    if data ~= nil then
      M.set_data(region.nest, data)
    end
  end
  local tracks = api.nest_get(region.nest).tracks
  if #tracks == 0 then
    return api.track_add({nest = region.nest} as types.TrackOptions)
  end
  return tracks[1]
end

-- The subproject of each track of a subproject, as the last edit left
-- them: a track that an edit removes is no longer in the kernel.
local nest_tracks: {integer: integer} = {}

--- Read the tracks of every subproject again into `nest_tracks`.
local function remember_tracks()
  nest_tracks = {}
  for _, n in ipairs(api.nest_list()) do
    local got = api.nest_get(n)
    nest_tracks[got.master] = n
    for _, id in ipairs(got.tracks) do
      nest_tracks[id] = n
    end
  end
end

-- The subprojects that each window is inside, outermost first, by the
-- window's id: the levels of its scope of kind `nest`. `scope.changed`
-- changes it. A window that closes keeps its entry.
local inside: {integer: {contracts.Scope}} = {}

--- The levels of kind `nest` from the song to `level`, outermost first.
local function nest_levels(level: contracts.Scope): {contracts.Scope}
  local out: {contracts.Scope} = {}
  while level do
    if level.kind == "nest" then
      table.insert(out, 1, level)
    end
    level = level.parent
  end
  return out
end

--- Run the `enter` of the kind of subproject `nest`, if it has one. A
--- failure is a message: the window stays inside, in the arrange view.
local function enter_kind(nest: integer)
  local kind = M.kind(nest) as contracts.NestKind<Data>
  if not (kind and kind.enter) then
    return
  end
  local ok, err = pcall(kind.enter, nest) as (boolean, string)
  if not ok then
    paw.notify(kind.title .. ": " .. tostring(err), "warn")
  end
end

-- A window that shows another scope leaves the subprojects that it is no
-- longer inside, innermost first, and enters the new ones, outermost first.
-- A move between two blocks of one subproject is no leave. The kind of the
-- innermost subproject that it entered opens its view.
events.on(
  paw.scope.changed, function(e: ScopeModule.Changed)
    local was = inside[e.win] or {}
    local now = nest_levels(e.level)
    inside[e.win] = #now > 0 and now or nil
    local kept = 0
    while kept < #was and kept < #now and was[kept + 1].id == now[kept + 1].id do
      kept = kept + 1
    end
    for i = #was, kept + 1, -1 do
      events.emit(M.left, {nest = was[i].id, win = e.win, clip = was[i].clip})
    end
    for i = kept + 1, #now do
      events.emit(M.entered, {nest = now[i].id, win = e.win, clip = now[i].clip})
    end
    if #now > kept then
      remember_tracks()
      enter_kind(now[#now].id)
    end
  end
)

--- The fields of a change's payload that name a track: `id` for the
--- events of a track, `track` for a clip, device, lane or cue.
local record Touched
  id: integer
  track: integer
end
--- One change of an edit, as `edit.after` gives it (paw/hooks.tl).
local record EditChange
  name: string
  payload: Touched
end
--- The payload of `edit.after`.
local record EditDone
  changes: {EditChange}
  state: integer
end
-- paw/hooks.tl sends `edit.after` and declares its name. That module is in
-- a higher layer, so this one names the event by its own descriptor.
local edit_after: events.Event<EditDone> = events.event("edit.after")

--- The subproject of a track, or nil for a track of the song.
local function nest_of_track(id: integer): integer
  local ok, n = pcall(api.track_get as (function(integer, string): integer), id, "nest") as (boolean, integer)
  if ok then
    return n
  end
  return nest_tracks[id]
end

-- `nest.changed` once for each subproject that an edit changed, in the
-- order of its first change. Only while something listens to it: the work
-- reads each change's track.
events.on(
  edit_after, function(e: EditDone)
    if not events.listened(M.changed.name) then
      return
    end
    local order: {integer} = {}
    local seen: {integer: boolean} = {}
    for _, change in ipairs(e.changes) do
      local p = change.payload
      local track = change.name:match("^track%.") and p.id or p.track
      local nest = track and nest_of_track(track)
      if nest and not seen[nest] then
        seen[nest] = true
        order[#order + 1] = nest
      end
    end
    for _, nest in ipairs(order) do
      events.emit(M.changed, {nest = nest, state = e.state})
    end
    remember_tracks()
  end
)

-- Making one ----------------------------------------------------------------------------

--- The bars from one beat of the window to another, as a message names
--- them: "bars 33-40", or "bar 33". With `song`, `from` and `to` are
--- beats of the song, and the bars are the song's even in a view whose
--- bars count from 1.
local function bars_text(from: number, to: number, song?: boolean): string
  local function bar(beat: number): integer
    if song then
      return api.tempo_bar_of(beat) + 1
    end
    return paw.time.bar_of(beat) - paw.scope.bar_offset()
  end
  local a = bar(from)
  local b = bar(math.max(from, to - 1e-6))
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

--- Move what starts at or after beat `at` of the window by `by` beats: the
--- clips and the automation of the tracks of the place `place` (the song
--- when nil, with its master), and in the song its markers, regions and
--- tempo and meter changes. Part of the caller's undo step.
local function shift_after(place: ScopeModule.Scope, at: number, by: number)
  local tracks = api.track_list({nest = place and place.id or nil})
  if not place then
    tracks[#tracks + 1] = 0
  end
  local function moved(beat: number): number
    return beat >= at - 1e-9 and math.max(0, beat + by) or beat
  end
  for _, id in ipairs(tracks) do
    -- Later clips first when they move later, so that none lands on one not moved yet.
    local clips = clip_list(id)
    for i = 1, #clips do
      local c = by > 0 and clips[#clips + 1 - i] or clips[i]
      if c.start >= at - 1e-9 then
        api.clip_set(c.id, {start = moved(c.start)})
      end
    end
    for _, lane in ipairs(api.lane_list(id)) do
      local points: {types.LanePoint} = api.lane_points(lane.id)
      local any = false
      for _, p in ipairs(points) do
        if p[1] >= at - 1e-9 then
          p[1], any = moved(p[1]), true
        end
      end
      if any then
        api.lane_set_points(lane.id, points)
      end
    end
  end
  if place then
    return
  end
  local origin = paw.time.origin()
  for _, m in ipairs(paw.markers.list()) do
    if m.beat >= at - 1e-9 then
      paw.markers.set(m.id, {beat = moved(m.beat)})
    end
  end
  local map = api.tempo_points()
  local tempos: {types.TempoPoint} = {}
  for _, t in ipairs(map.tempos) do
    tempos[#tempos + 1] = {beat = moved(t.beat - origin) + origin, bpm = t.bpm, ramp = t.ramp}
  end
  local signatures: {types.SigPoint} = {}
  for _, s in ipairs(map.signatures) do
    signatures[#signatures + 1] = {beat = moved(s.beat - origin) + origin, num = s.num, den = s.den}
  end
  api.tempo_set_points(tempos, signatures)
end

--- The first track of a new subproject, in the window that is inside it:
--- `paw.opt.nest_track`.
local function first_track(): objects.Track
  local kind = opt.nest_track as string
  local kinds = (paw.track_kinds as TrackKinds)
  if kind and kind ~= "" and kind ~= "track" then
    if not kinds.kinds:get(kind) then
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
--- (`paw.opt.nest_track`), or with the tracks that the `create` of its
--- kind (`o.kind`) makes. Call it in one undo step (a command is one).
function M.new(o: NewOptions): Made
  local from = o.from or paw.time.bar_floor(paw.cursor.beat)
  local to = o.to
  local bars = o.bars or 8
  local ends: number
  if o.num and o.den then
    if not (
      o.num >= 1
      and o.num <= 64
      and (o.den == 1 or o.den == 2 or o.den == 4 or o.den == 8 or o.den == 16 or o.den == 32)
    ) then
      error(string.format("%d/%d is not a meter", o.num, o.den), 0)
    end
    if not to then
      to = from + bars * o.num * 4 / o.den
      -- The song after the section keeps its bars: it moves by what the
      -- section's beats changed (8 bars of 6/8 are 8 beats shorter than
      -- 8 bars of 4/4).
      ends = paw.time.bar_start(paw.time.bar_of(from) + bars)
    end
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
  local kind: contracts.NestKind<Data>
  if o.kind then
    kind = M.kinds:get(o.kind)
    if not kind then
      local names: {string} = {}
      for known in pairs(M.kinds:entries()) do
        names[#names + 1] = known
      end
      table.sort(names)
      error(
        string.format(
          "no kind of subproject `%s` here%s",
          o.kind,
          #names > 0 and (": the kinds are " .. table.concat(names, ", ")) or ""
        ),
        0
      )
    end
  end
  local place = paw.scope.nest()
  local song_from = paw.time.song_beat(from)
  local meter: types.NestMeter = nil
  -- With a meter of its own apart from the song's (polymeter), the song's
  -- map and its bars after the section stay as they are.
  local moved = not o.polymeter and ends and math.abs(to - ends) > 1e-9 and to - ends or nil
  if moved then
    shift_after(place, ends, moved)
  end
  if o.num then
    meter = {mode = "own", changes = {{beat = 0, num = o.num, den = o.den}}}
    if not o.polymeter then
      write_meter(song_from, song_from + (to - from), o.num, o.den)
    end
  end
  local tempo: types.NestTempo = nil
  if o.own_tempo then
    tempo = {mode = "own", points = {{beat = 0, bpm = api.tempo_at(song_from), ramp = false}}}
  end
  -- The words of the message: the song's bars, the meter written.
  local where = bars_text(from, to)
  local nest = api.nest_add({name = name, length = to - from, meter = meter, tempo = tempo, kind = o.kind})
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
  local track: integer
  if kind then
    -- The kind makes the tracks before the window enters, so that its
    -- `enter` finds them and its data.
    track = create(kind, {nest = nest, row = row.id, clip = clip, name = name, from = from, to = to})
    paw.scope.enter({kind = "nest", id = nest, clip = clip})
  else
    paw.scope.enter({kind = "nest", id = nest, clip = clip})
    track = first_track().id
  end
  paw.cursor.set_track(track)
  paw.cursor.set_beat(0)
  local message = string.format(
    "added the subproject %s%s over %s%s%s, on its own row; inside it now: `zw` goes back",
    name,
    kind and (" (" .. kind.title .. ")") or "",
    where,
    o.num and string.format(" in %d/%d", o.num, o.den) or "",
    (o.polymeter and o.num) and " (the song's meter stays)" or ""
  )
  if o.own_tempo then
    message = message .. string.format("; its own tempo, %g bpm", tempo.points[1].bpm)
  end
  if moved then
    message = message
      .. string.format(
        "; the rest of the song moved %g beat%s %s",
        math.abs(moved),
        math.abs(moved) == 1 and "" or "s",
        moved < 0 and "earlier" or "later"
      )
  end
  return {nest = nest, row = row.id, clip = clip, track = track, message = message}
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
  for _, given in ipairs(args as {string}) do
    local word = tostring(given)
    if word:match("^%d+/%d+$") then
      meter(word)
    elseif word:match("^%d+$") and not o.bars then
      o.bars = math.tointeger(tonumber(word))
    else
      words[#words + 1] = word
    end
  end
  local named = args as {string: string}
  if named.meter == "own" then
    o.polymeter = true
  elseif named.meter then
    if not tostring(named.meter):match("^%d+/%d+$") then
      error("a meter is written 6/8, or meter=own, not " .. tostring(named.meter), 0)
    end
    meter(tostring(named.meter))
  end
  if named.tempo == "own" then
    o.own_tempo = true
  elseif named.tempo then
    error("tempo=own gives the subproject its own tempo, not tempo=" .. tostring(named.tempo), 0)
  end
  if named.bars then
    o.bars = math.tointeger(tonumber(named.bars))
  end
  if named.kind then
    o.kind = tostring(named.kind)
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
    -- A failure leaves the project as the command found it: a kind's
    -- `create` can fail after the subproject is there.
    local clean = not api.undo_pending()
    local ok, made = pcall(M.new, o) as (boolean, Made)
    if not ok then
      if clean and api.undo_pending() then
        api.undo_discard()
        paw.flush()
      end
      error(made, 0)
    end
    paw.notify(made.message)
  end,
  {
    range = true,
    label = "Add a subproject",
    desc = "Add a subproject with its own row and tracks, and go inside: `nest.new Ballad 8 6/8` (8 bars of 6/8 from the cursor's bar; `meter=own` keeps the song's meter, `tempo=own` gives it its own tempo, `kind=` makes a kind of subproject that an extension defines); over the selection or the region at the cursor when no bars are given",
  }
)

-- Blocks: the clips that place a subproject ----------------------------------------------

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

--- What tells one instance of a subproject from another: the stems of
--- one block start at the same beat, from the same beat of it.
local function instance_key(c: types.Clip): string
  return string.format("%.9g:%.9g", c.start, c.offset or 0)
end

--- How many times the song plays a subproject: its blocks, counting the
--- stems of one block once.
local function instances(nest: integer): integer
  local seen: {string: boolean} = {}
  local n = 0
  for _, b in ipairs(M.blocks(nest)) do
    local key = instance_key(b.clip)
    if not seen[key] then
      seen[key], n = true, n + 1
    end
  end
  return n
end

--- The song's bars where the other instances of block `c`'s subproject
--- start, as a message names them: "bar 97", "bars 49 and 97".
local function other_places(c: types.Clip): string
  local bars: {string} = {}
  local seen: {string: boolean} = {[instance_key(c)] = true}
  for _, b in ipairs(M.blocks(c.nest)) do
    local key = instance_key(b.clip)
    if not seen[key] then
      seen[key] = true
      bars[#bars + 1] = tostring(api.tempo_bar_of(b.clip.start) + 1)
    end
  end
  if #bars == 0 then
    return nil
  elseif #bars == 1 then
    return "bar " .. bars[1]
  end
  local last = table.remove(bars)
  return "bars " .. table.concat(bars, ", ") .. " and " .. last
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

--- What `K` says of a subproject's kind: ` (Drum pattern: 16 steps)`,
--- or the kind's name when no extension here defines it. Empty for a
--- plain subproject.
local function kind_text(n: types.Nest): string
  if not n.kind then
    return ""
  end
  local kind = M.kinds:get(n.kind)
  if not kind then
    return string.format(" (%s, which no extension here defines)", n.kind)
  end
  local words: string
  if kind.describe then
    local ok, said = pcall(kind.describe, n.id) as (boolean, string)
    words = ok and said or nil
  end
  return string.format(" (%s%s)", kind.title, words and (": " .. words) or "")
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
    "nest %s%s · %s · %g bar%s · %s · %d track%s · %d instance%s · live%s",
    n.name,
    kind_text(n),
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

--- Write the own tempo of subproject `n` into the song's map over its block
--- `c` (a block of the song), and the song's tempo back after it, so that
--- the sound and the beats stay: the block then lasts its beats of the
--- subproject, and the song after it moves by what that changes. The
--- subproject then follows the song's tempo. Part of the caller's undo
--- step. Returns the words of the message.
local function tempo_into_song(c: types.Clip, n: types.Nest): string
  local own = paw.scope.nest_time(c.id)
  local offset = c.offset or 0
  local finish = c.start + c.length
  local span = own:nest_beat(finish) - offset
  local back = api.tempo_at(finish)
  -- The song after the block keeps its seconds: it moves by the beats the
  -- block gains or loses.
  local moved = span - c.length
  if math.abs(moved) > 1e-9 then
    shift_after(nil, finish, moved)
  end
  local to = c.start + span
  local tempos: {types.TempoPoint} = {}
  for _, t in ipairs(api.tempo_points().tempos) do
    if t.beat < c.start - 1e-9 or t.beat > to + 1e-9 then
      tempos[#tempos + 1] = t
    end
  end
  -- The tempo in effect where the block starts, then its changes inside.
  local ramp = false
  for _, p in ipairs(n.tempo.points) do
    if p.beat <= offset + 1e-9 then
      ramp = p.ramp
    elseif p.beat < offset + span - 1e-9 then
      tempos[#tempos + 1] = {beat = c.start + p.beat - offset, bpm = p.bpm, ramp = p.ramp}
    end
  end
  tempos[#tempos + 1] = {beat = c.start, bpm = own:tempo(offset), ramp = ramp}
  tempos[#tempos + 1] = {beat = to, bpm = back, ramp = false}
  table.sort(tempos, function(a: types.TempoPoint, b: types.TempoPoint): boolean return a.beat < b.beat end)
  api.tempo_set_points(tempos, api.tempo_points().signatures)
  api.nest_set(n.id, {tempo = {mode = "follow"}} as types.Nest)
  local bpms: {string} = {}
  for _, p in ipairs(n.tempo.points) do
    bpms[#bpms + 1] = string.format("%g", p.bpm)
  end
  return string.format(
    "its own tempo, %s bpm, in the song's map over %s, and %g bpm back after it",
    table.concat(bpms, " to "),
    bars_text(c.start, to, true),
    back
  )
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
  local old_name = n.name
  local inside = paw.scope.nest()
  local was_inside = inside and inside.id == n.id
  local track, beat = paw.cursor.track_id(), paw.cursor.beat
  -- Per track: the row that each of its tracks plays on.
  local row_of: {integer: integer} = {}
  for _, b in ipairs(M.blocks(n.id)) do
    local t = stem_of(b.clip)
    if t then
      row_of[t] = b.row
    end
  end
  -- Other blocks play it too: this block gets a copy of its own to promote.
  local still = other_places(c)
  if still then
    -- The copy goes in this step: the group takes the subproject's name.
    local copy = api.nest_unique(clip)
    api.nest_set(copy, {name = old_name} as types.Nest)
    c = api.clip_get(clip)
    n = M.get(copy)
    markers = (n.meta and n.meta.markers or {}) as {MarkersModule.Marker}
  end
  -- Its own tempo, into the song's map over the block, from the song's
  -- time (the song moves after the block).
  local tempo_words: string = nil
  if n.tempo and n.tempo.mode == "own" then
    paw.scope.widen(true)
    tempo_words = tempo_into_song(c, n)
  end
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
  local where = bars_text(r.from, r.to, true)
  -- Its regions, inside a region named after it.
  local parent = region_over(r.from, r.to, n.name)
  -- Its key, when it has one of its own (`meta.key`), on that region: the
  -- region is a key over its time for harmony (paw/harmony.tl).
  local key = n.meta and n.meta.key
  local keyed = false
  if key is string and key ~= "" and key ~= api.project_get().key then
    paw.markers.set(parent.id, {key = key})
    keyed = true
  end
  local regions = 0
  for _, m in ipairs(markers) do
    local at = m.beat + r.zero
    if at >= r.from - 1e-9 and at < r.to then
      local length = m.length and math.min(m.length, r.to - at) or nil
      paw.markers.add(at, m.name, {length = length, color = m.color})
      regions = regions + 1
    end
  end
  -- The view that takes its place: the group's tracks over the region's
  -- time; per track, the rows.
  local tracks: {integer} = {r.group}
  for _, id in ipairs(r.tracks) do
    tracks[#tracks + 1] = id
  end
  paw.scope.widen(true)
  paw.scope.enter({kind = "range", tracks = tracks, from = parent.beat, to = parent.beat + parent.length})
  paw.scope.name(n.name)
  if was_inside and not r.group then
    -- Its clips went back to the rows: the cursor on the row of its track.
    track = row_of[track] or r.tracks[1]
  end
  if was_inside then
    paw.cursor.set_track(track)
    paw.cursor.set_beat(beat + r.zero)
  else
    paw.cursor.set_track(tracks[1])
    paw.cursor.set_beat(r.from)
  end
  local words: {string} = {}
  if r.group then
    words[1] = string.format(
      "promoted %s: %d track%s in the group %s, %s", n.name, #r.tracks, #r.tracks == 1 and "" or "s", n.name, where
    )
  else
    words[1] = string.format(
      "promoted %s: its clips back on %d row%s, %s", n.name, #r.tracks, #r.tracks == 1 and "" or "s", where
    )
  end
  if regions > 0 then
    words[#words + 1] = string.format("%d regions inside the region %s", regions, n.name)
  end
  if keyed then
    words[#words + 1] = string.format("the region %s is in %s", n.name, key as string)
  end
  if wrote then
    words[#words + 1] = string.format("%d/%d in the song's map", own.num, own.den)
  end
  if tempo_words then
    words[#words + 1] = tempo_words
  end
  if #r.combined > 0 then
    words[#words + 1] = "its master's and its row's lanes made one: " .. table.concat(r.combined, ", ")
  end
  if still then
    words[#words + 1] = string.format("%s still plays at %s", old_name, still)
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

-- Its own time, and a block of its own ----------------------------------------------------

--- The song's tempo over a block `c` of the song, from the subproject's
--- beat 0, as a tempo of its own keeps it: the sound does not change
--- when it starts to keep it.
local function song_tempo_over(c: types.Clip, length: number): {types.TempoChange}
  local zero = c.start - (c.offset or 0)
  local points: {types.TempoChange} = {{beat = 0, bpm = api.tempo_at(zero), ramp = false}}
  for _, t in ipairs(api.tempo_points().tempos) do
    if t.beat <= zero + 1e-9 then
      points[1].ramp = t.ramp
    elseif t.beat < zero + length - 1e-9 then
      points[#points + 1] = {beat = t.beat - zero, bpm = t.bpm, ramp = t.ramp}
    end
  end
  return points
end

--- Give subproject `nest` a tempo of its own (`own`: the song's over its
--- first block, or `bpm` throughout) or the song's again (`follow`), as
--- `:nest.time` does. Its blocks keep their start; their length in the
--- song follows. Call it in one undo step. Returns the message.
function M.set_time(nest: integer, how: string, bpm?: number): string
  local n = M.get(nest)
  if not n then
    error("no subproject " .. tostring(nest), 0)
  end
  if how == "follow" then
    if n.tempo.mode ~= "own" then
      error(n.name .. " follows the song's tempo already", 0)
    end
    api.nest_set(nest, {tempo = {mode = "follow"}} as types.Nest)
    return n.name .. " follows the song's tempo again: a tempo change of the song changes it"
  elseif how ~= "own" then
    error("nest.time takes own or follow, not " .. tostring(how), 0)
  end
  if bpm and not (bpm >= 1 and bpm <= 999) then
    error(string.format("a tempo is from 1 to 999 bpm, not %s", tostring(bpm)), 0)
  end
  local points: {types.TempoChange}
  if bpm then
    points = {{beat = 0, bpm = bpm, ramp = false}}
  else
    local first = M.blocks(nest)[1]
    points = first and song_tempo_over(first.clip, n.length) or {{beat = 0, bpm = api.tempo_at(0), ramp = false}}
  end
  api.nest_set(nest, {tempo = {mode = "own", points = points}} as types.Nest)
  return string.format(
    "%s has its own tempo, %g bpm: a tempo change of the song leaves it as it is, and its blocks last its seconds",
    n.name,
    points[1].bpm
  )
end

--- Give subproject `nest` a meter of its own (`6/8`), with the song's map
--- as it is (polymeter), or the song's meter again (`follow`), as
--- `:nest.meter` does. Returns the message.
function M.set_meter(nest: integer, meter: string): string
  local n = M.get(nest)
  if not n then
    error("no subproject " .. tostring(nest), 0)
  end
  if meter == "follow" then
    api.nest_set(nest, {meter = {mode = "follow"}} as types.Nest)
    return n.name .. " follows the song's meter"
  end
  local num, den = (meter or ""):match("^(%d+)/(%d+)$")
  local a, b = math.tointeger(tonumber(num)), math.tointeger(tonumber(den))
  if not (a and b and a >= 1 and a <= 64 and (b == 1 or b == 2 or b == 4 or b == 8 or b == 16 or b == 32)) then
    error("nest.meter takes a meter (6/8) or follow, not " .. tostring(meter), 0)
  end
  api.nest_set(nest, {meter = {mode = "own", changes = {{beat = 0, num = a, den = b}}}} as types.Nest)
  return string.format("%s in %d/%d of its own; the song's meter stays as it is", n.name, a, b)
end

--- The subproject at the cursor: the one the window is in, else the one of
--- the block at the cursor.
local function nest_here(): integer
  local here = paw.scope.nest()
  if here then
    return here.id
  end
  local c = block_at_cursor()
  if not c then
    error("not in a subproject or on a block of one", 0)
  end
  return c.nest
end

commands.define(
  "nest.time",
  function(ctx: contracts.CommandContext): contracts.CommandResult
    local how = tostring(ctx.args[1] or "")
    local bpm = ctx.args[2] and tonumber(ctx.args[2]) or nil
    if ctx.args[2] and not bpm then
      error("a tempo is a number of bpm, not " .. tostring(ctx.args[2]), 0)
    end
    paw.notify(M.set_time(nest_here(), how, bpm))
  end,
  {
    label = "Give the subproject its own tempo, or the song's",
    desc = "Give the subproject at the cursor its own tempo (`nest.time own`, or `nest.time own 90`): the song's tempo no longer changes it; or the song's again (`nest.time follow`)",
    complete = function(): {string} return {"own", "follow"} end,
  }
)

commands.define(
  "nest.meter",
  function(ctx: contracts.CommandContext): contracts.CommandResult
    paw.notify(M.set_meter(nest_here(), tostring(ctx.args[1] or "")))
  end,
  {
    label = "Give the subproject its own meter, or the song's",
    desc = "Give the subproject at the cursor a meter of its own with the song's meter as it is (`nest.meter 6/8`), or the song's meter again (`nest.meter follow`)",
    complete = function(): {string} return {"follow", "6/8", "3/4", "4/4", "7/8"} end,
  }
)

--- Make the block `clip` a subproject of its own, as `:nest.unique` does:
--- a copy of its subproject that only this block plays; the others keep
--- the subproject. A window inside it through this block goes inside the
--- copy. Call it in one undo step. Returns the message.
function M.unique(clip: integer): string
  local c = api.clip_get(clip)
  local n = c and c.nest and M.get(c.nest)
  if not n then
    error("not a block of a subproject: put the cursor on one", 0)
  end
  local still = other_places(c)
  local here = paw.scope.nest()
  local copy = api.nest_unique(clip)
  local made = M.get(copy)
  if here and here.clip == clip then
    paw.scope.widen(true)
    paw.scope.enter({kind = "nest", id = copy, clip = clip})
  end
  return string.format(
    "%s: the block at bar %d is a subproject of its own; %s still plays at %s",
    made.name,
    api.tempo_bar_of(c.start) + 1,
    n.name,
    still
  )
end

commands.define(
  "nest.unique",
  function(): contracts.CommandResult
    local c = block_at_cursor()
    if not c then
      error("not on a block of a subproject: put the cursor on one", 0)
    end
    paw.notify(M.unique(c.id))
  end,
  {
    label = "Make the block a subproject of its own",
    desc = "Make the block at the cursor a subproject of its own: an edit inside it then changes this block only, and the other blocks keep the subproject",
  }
)

-- Save a view: <Space>zw per track, <Space>zW with a row of its own ----------------------

--- The meter of the window's time from `from` to `to` (its beats): the
--- meter at `from` and its changes inside, from beat 0, as a subproject
--- keeps it. Inside a subproject with its own time, its own map; else
--- the song's map, from the window's origin.
local function meter_over(from: number, to: number): types.NestMeter
  local own = paw.time.own()
  local origin = own and 0 or paw.time.origin()
  local points = own and own:points() or api.tempo_points()
  local a, b = from + origin, to + origin
  local num, den = paw.time.signature_at(from)
  local changes: {types.SigChange} = {{beat = 0, num = num, den = den}}
  for _, s in ipairs(points.signatures) do
    if s.beat > a + 1e-9 and s.beat < b - 1e-9 then
      changes[#changes + 1] = {beat = s.beat - a, num = s.num, den = s.den}
    end
  end
  return {mode = "own", changes = changes}
end

--- The name a saved view takes when none is given: the view's, else its
--- region's, else `Subproject N`.
local function view_name(s: contracts.Scope): string
  if s.name and s.name ~= "" then
    return s.name
  end
  if s.kind == "region" and paw.markers then
    local m = paw.markers.region({id = s.id})
    if m then
      return m.name
    end
  end
  return "Subproject " .. (#api.nest_list() + 1)
end

--- The time of the tracks when a view has none: from 0 to the end of
--- their last clip.
local function extent(tracks: {integer}): number
  local to = 0.0
  for _, id in ipairs(tracks) do
    for _, c in ipairs(clip_list(id)) do
      to = math.max(to, c.start + c.length)
    end
  end
  return to
end

--- Move the markers and regions strictly inside `from..to` of the
--- window's time into subproject `nest`, from its beat 0. A region over
--- the whole time stays. Returns how many moved.
local function move_markers(nest: integer, from: number, to: number): integer
  if not paw.markers then
    return 0
  end
  local moved: {MarkersModule.Marker} = {}
  for _, m in ipairs(paw.markers.list()) do
    local fits = m.beat >= from - 1e-9 and m.beat < to - 1e-9 and (not m.length or m.beat + m.length <= to + 1e-9)
    local is_range = m.length and math.abs(m.beat - from) < 1e-9 and math.abs(m.beat + m.length - to) < 1e-9
    if fits and not is_range then
      moved[#moved + 1] = m
    end
  end
  if #moved == 0 then
    return 0
  end
  local meta = api.nest_get(nest).meta or {}
  local list: {MarkersModule.Marker} = {}
  for i, m in ipairs(moved) do
    list[i] = {id = i, beat = m.beat - from, name = m.name, length = m.length, color = m.color, key = m.key}
    paw.markers.remove(m.id)
  end
  meta.markers = list
  api.nest_set(nest, {meta = meta} as types.Nest)
  return #moved
end

--- Save the window's view as a subproject, as `:scope.write` does: per
--- track, or with a row of its own (`own_row`, `:scope.write!`). The
--- view's clips move into the subproject (`paw.api.nest_save`); the rows
--- get its blocks; its markers and regions inside move in, and a region
--- over its time stays. The meter of the time is the subproject's own.
--- Per track, the window stays in the view; with a row of its own, it is
--- inside the subproject at the same place. Call it in one undo step.
--- Returns the message.
function M.save(name?: string, own_row?: boolean): string
  local s = paw.scope.current()
  if not s then
    error("the window shows the whole song: enter a view first, for example `znar` on a region", 0)
  end
  if s.kind == "nest" then
    error("this is a subproject already: `<Space>zp` makes it a view", 0)
  end
  local tracks = paw.scope.tracks()
  local from, to = paw.scope.span()
  local meter: types.NestMeter = {mode = "follow"}
  if from then
    meter = meter_over(from, to)
  else
    from, to = 0, extent(tracks)
  end
  if not (to > from) then
    error("the view has no time to save", 0)
  end
  name = name and name:match("^%s*(.-)%s*$") or ""
  -- A name has no slash; a word with one is a path (a folder).
  if name:find("/", 1, true) then
    error(string.format("%s is a path: a subproject's name has no `/`", name), 0)
  end
  if name == "" then
    name = view_name(s)
  end
  local track, beat = paw.cursor.track_id(), paw.cursor.beat
  local saved = api.nest_save({name = name, tracks = tracks, from = from, to = to, meter = meter, own_row = own_row})
  if own_row then
    api.clip_add(saved.row, {nest = saved.nest, start = from} as types.ClipOptions)
  else
    for _, r in ipairs(saved.rows) do
      api.clip_add(
        r.row, {nest = saved.nest, start = from, length = to - from, play = {track = r.track}} as types.ClipOptions
      )
    end
  end
  -- The markers of the song; a view inside a subproject keeps them there.
  local markers = paw.scope.nest() and 0 or move_markers(saved.nest, from, to)
  local first = meter.changes and meter.changes[1]
  local words = {
    string.format(
      "nested %d track%s, %s, as %s%s",
      #saved.tracks,
      #saved.tracks == 1 and "" or "s",
      bars_text(paw.time.song_beat(from), paw.time.song_beat(to), true),
      name,
      first and string.format(" (%d/%d)", first.num, first.den) or ""
    ),
  }
  if own_row then
    words[#words + 1] = "on its own row " .. name_of(saved.row)
  end
  if markers > 0 then
    words[#words + 1] = string.format(
      "%d marker%s and region%s inside it", markers, markers == 1 and "" or "s", markers == 1 and "" or "s"
    )
  end
  for _, change in ipairs(saved.changes) do
    words[#words + 1] = change
  end
  if own_row then
    -- The view's tracks went in: the window goes inside, at the same place.
    local block = block_on(saved.row, saved.nest)
    paw.scope.widen()
    paw.scope.enter({kind = "nest", id = saved.nest, clip = block and block.id})
    local inside = false
    for _, id in ipairs(saved.tracks) do
      inside = inside or id == track
    end
    paw.cursor.set_track(inside and track or saved.tracks[1])
    paw.cursor.set_beat(beat - from)
  end
  return table.concat(words, "; ")
end

for _, bang in ipairs({"", "!"}) do
  commands.define(
    "scope.write" .. bang,
    function(ctx: contracts.CommandContext): contracts.CommandResult
      local words: {string} = {}
      for _, word in ipairs(ctx.args as {string}) do
        words[#words + 1] = tostring(word)
      end
      paw.notify(M.save(table.concat(words, " "), bang == "!"))
    end,
    {
      label = bang == "" and "Save the view as a subproject, per track"
        or "Save the view as a subproject with its own row",
      desc = bang == ""
        and "Save this window's view as a subproject: its clips move in, and the rows they came from play them through their own devices (`scope.write Bridge`)" or "Save this window's view as a subproject with its own row: its tracks, their devices and lanes go in, and one row plays its mix (`scope.write! Bridge`)",
    }
  )
end

-- The rows in place: the arrange view and the cursor ask here.
paw.groups.under = M.under
paw.cursor.shift = M.shift

return M
