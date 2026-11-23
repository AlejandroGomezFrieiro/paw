-- Ex: command lines over time and tracks, as Vim's are over lines.
--
-- A line may start with a range of tracks, then a range of time, then the
-- command (docs/reference/ex.md says it for people):
--
--   :5,8d          bars 5 to 8 of every track         :t2,t4 mute    tracks 2 to 4
--   :5.3,6.1y      from beat 3 of bar 5 to beat 1 of bar 6, both beats taken in
--   :%s/c4/d4/g    every C4 of the song               :t/Drums/ solo  tracks whose name holds Drums
--   :.,.+3>        from the cursor's bar, 4 bars      :t* volume -=3  every track 3 dB down
--   :'a,'bd        from mark a up to mark b           :'<,'>s/vel>100/vel=90/
--   :t2 5,8d       bars 5 to 8 of track 2 alone       :t'<,'>         the tracks of the selection
--
-- A time range alone covers every track, or the clips the focused view
-- edits (the piano roll's); a track range alone covers whole tracks; both
-- together, that time on those tracks.
--
-- Patterns (`:s`, `:g`, `:v`) match notes, clips or tracks by their fields:
-- `c4` `c#4` `c` (any octave) `60`, `vel>100`, `len<1/8`, `beat=1`,
-- `name:Verse`, `track:Bass`; terms side by side must all hold, `c4|e4`
-- is either, `!c4` is not. The deepest field named says what is matched:
-- `name:Verse c4` matches the C4s of clips named Verse. A replacement sets
-- fields (`d4`, `+12`, `vel=90`, `vel-10`, `len*2`, `name:Chorus`), and an
-- empty one removes what matched.
--
-- Extensions add fields with `paw.ex.field` and say how a view of theirs
-- reads time with `paw.ex.view`; a command made with `range = true` gets
-- the range as `ctx.range` and the things in it from `paw.ex.items`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local commands = require("paw.commands")
local options = require("paw.options")
local music = require("paw.music")
local transform = require("paw.notes")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type objects = require("paw.objects")
local type CursorModule = require("paw.cursor")
local type AddressModule = require("paw.address")
local type QfModule = require("paw.qf")
local type AttrModule = require("paw.attr")
local type EditModule = require("paw.edit")
local type GroupsModule = require("paw.groups")
local type UiModule = require("paw.ui")
local type RollClipsModule = require("paw.roll_clips")
local type Roll = require("paw.views.pianoroll")

local EPS = 1e-9
local NEAR = 1e-6 -- how near a bar line a beat may be and still count as on it

local type Range = contracts.CommandRange
local type Item = contracts.ExItem
local type Level = contracts.ExLevel
local type Field = contracts.ExField
local type Change = contracts.ExChange
local type ExValue = contracts.ExValue
local type ExView = contracts.ExView
local type Result = contracts.CommandResult
local type PitchWord = music.PitchWord
local type Yanked = EditModule.Yanked
local type ClipSnapshot = objects.ClipSnapshot

--- What an Ex command gets besides what any command gets: the address
--- that `:g` or `:cdo` runs it at (`target`), how many `>` were typed
--- (`steps`), and for `&&`, to keep the flags of the last `:s`.
local record Context is contracts.CommandContext
  target: string
  steps: integer
  keep_flags: boolean
end

--- A pattern read (`paw.ex.pattern`): its text, the level it matches,
--- the parts of names it looks for, and its test.
local record Pattern
  text: string
  level: Level
  names: {string: string}
  test: function(item: Item): boolean
end

--- A value a replacement sets: text, a number, or a pitch (`d4`, `c`).
local type SetValue = string | number | PitchWord

--- One change a replacement makes: the field, how (`=`, `+`, `-`, `*`,
--- `:` for the part matched) and the value.
local record Set
  field: string
  op: string
  value: SetValue
end

--- An item and what a replacement makes of it (false: it goes).
local record Chosen
  item: Item
  change: Change | boolean
end

--- An item and its change, for `paw.ex.apply`.
local record Changed
  item: Item
  change: Change
end

--- A match the views show while a line is typed: the item and its change.
local record Mark
  item: Item
  change: Change | boolean
end

--- What the views show while a line is typed (`paw.ex.shown`): the
--- stretch of time, the tracks (a set), the matches, the notes lit by
--- clip and by note id (or place), how many matches each clip holds, and
--- the one that `:s///c` asks about.
local record Shown
  from: number
  to: number
  tracks: {integer: boolean}
  matches: {Item}
  notes: {integer: {integer: Mark}}
  clips: {integer: integer}
  current: Item
end

--- What `paw.ex.field` takes besides the name: a field without its name.
local type FieldSpec = Field

-- What this module reads of the modules that are still in Lua.

--- What the piano roll's layers get, and the roll (paw/views/pianoroll.tl).
local type RollLayer = Roll.Layer
local type PianoRoll = Roll.PianoRoll

--- What a layer of the arrange view's ruler gets (paw/views/arrange.lua).
local record ArrangeLayer
  ruler: contracts.Buf
  x: function(beat: number): number
end
local record Arrange
  layers: {string: function(view: Arrange, layer: ArrangeLayer)}
end

--- What a layer of a part of the arrange view gets (`paw.ui.layer`):
--- the buffer, where to draw and what it draws.
local record PartLayer
  buf: contracts.Buf
  x: number
  y: number
  width: integer
  track: integer
  clip: types.Clip
end

local record Views
  pianoroll: PianoRoll
  arrange: Arrange
end

--- paw/scope.tl, the part of it that this module reads.
local record ScopeLevel
  id: integer
end
local record Scope
  tracks: function(): {integer}
  span: function(): number, number
  bar_offset: function(): integer
  nest: function(): ScopeLevel
end

--- paw/views/cmdline.lua, as far as this module calls it.
local record Cmdline
  read_value: function(text: string, now: number): number
  ask_key: function(prompt: string, on_key: function(key: string))
end

local record Paw is partial.Paw
  keymap: KeymapModule
  ui: UiModule
  cursor: CursorModule
  address: AddressModule
  qf: QfModule
  attr: AttrModule
  edit: EditModule
  groups: GroupsModule
  time: objects.Time
  clip: function(id: integer): objects.Clip
  track: function(which: number | string): objects.Track
  restore_track: function(snap: objects.TrackSnapshot, index?: integer): objects.Track
  restore_clip: function(snap: ClipSnapshot, track: integer | objects.Track): objects.Clip
  scope: Scope
  roll_clips: RollClipsModule
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

local function keymap(): KeymapModule
  return paw.keymap
end
local function ui(): UiModule
  return paw.ui
end
local function views(): Views
  return paw.ui.views as Views
end
local function cmdline(): Cmdline
  return (require as function(string): Cmdline)("paw.views.cmdline")
end

local record M
  type Context = Context
  type Pattern = Pattern
  type Set = Set
  type Chosen = Chosen
  type Changed = Changed
  type Shown = Shown
  --- How each view reads ranges, by its name (`paw.ex.view`).
  views: {string: ExView}
  --- The fields of patterns, by name (`paw.ex.field`).
  fields: {string: Field}
  selection_range: function(): Range
  split: function(rest: string): string, string, integer
  mark: function(state: Shown, item: Item, change: Change | boolean)
end

options.define("gdefault", false) -- `:s` changes every match without `g`, and only the first of each bar with it

local function plural(n: integer, word: string): string
  return n .. " " .. word .. (n == 1 and "" or "s")
end

local function fail(text: string, ...: string | number)
  error(string.format(text, ...), 0)
end

-- Views ----------------------------------------------------------------------------
--
-- How a view's own beats (its grid's columns) map to beats of the song, and
-- which clips it edits: `paw.ex.view(name, { song = function(col) ... end,
-- col = function(beat) ... end, clips = function() return ids end,
-- track = function() return id end })`. A view not named here counts in
-- beats of the song. A view of several clips may also say: `clips_at(s, i)`,
-- the clips an address of its own at `i` names and where it ends (the
-- notation view's staves, `s4`), which a range then holds as `clips`;
-- `selection(region, r)`, what a selection of its grid is as a range (its
-- `pitches`, its `clips`); `each_clip(r, run)`, how a command of its own
-- is run on a range of its clips, `run(r)` for each.

M.views = {}

--- Tell how a view of your own maps its columns to the beats of the song,
--- and which clips it edits, for ranges. See `docs/reference/lua-commands.md`.
function M.view(name: string, spec: ExView)
  M.views[name] = spec
end

local function roll(): PianoRoll
  return views().pianoroll
end
local function roll_start(): number
  local clip = roll():clip()
  return clip and clip.start or 0
end

M.view(
  "arrange",
  {
    track = function(): integer return paw.cursor.track_id() end,
    go = function(beat: number) paw.cursor.set_beat(beat) end,
  }
)
M.view(
  "pianoroll",
  {
    song = function(col: number): number return roll_start() + col end,
    col = function(beat: number): number return beat - roll_start() end,
    clips = function(): {integer} return roll():clip() and paw.roll_clips.ids() or nil end,
    track = function(): integer local clip = roll():clip(); return clip and clip:track().id or nil end,
    go = function(beat: number) roll():set(nil, beat - roll_start()) end,
  }
)

local function adapter(): ExView
  return M.views[ui().focused] or {}
end

local function song_of(col: number): number
  local a = adapter()
  return a.song and a.song(col) or col
end

--- The beat of the song the focused view's cursor is on.
local function cursor_beat(): number
  local view = ui().views[ui().focused]
  local g = view and view.grid
  if not g then
    return paw.cursor.beat
  end
  local _, col = g.get()
  return song_of(col)
end

--- The track the focused view is about: the cursor's, or the clip's it edits.
local function cursor_track(): integer
  local a = adapter()
  return (a.track and a.track()) or paw.cursor.track_id()
end

--- The clips the focused view edits: those a range names of them (`r.clips`,
--- the notation view's staves), else the view's own; nil when it is about
--- the whole song.
local function view_clips(r?: Range): {integer}
  if r and r.clips then
    return r.clips
  end
  local a = adapter()
  return a.clips and a.clips() or nil
end

--- The tracks a range can name: those of the scope of a narrowed window
--- (`paw.scope`); `t1` is the first of them.
local function scoped(): {integer}
  return paw.scope.tracks()
end

-- Addresses of time --------------------------------------------------------------

--- A span of time an address names: a bar (`bar` its number), a beat, or
--- a point (a mark).
local record Span
  from: number
  to: number
  unit: string
  bar: integer
end

local function song_end(): number
  local finish = 0.0
  for _, id in ipairs(api.track_list()) do
    for _, c in ipairs(api.clip_list(id)) do
      finish = math.max(finish, c.start + c.length)
    end
  end
  return finish
end

--- The last bar: of the scope's time in a scope with time (`paw.scope`),
--- else the last bar with a clip in it.
local function last_bar(): integer
  local from, to = paw.scope.span()
  if from then
    return paw.time.bar_of(math.max(from, to - NEAR))
  end
  return math.max(1, paw.time.bar_of(math.max(0, song_end() - NEAR)))
end

--- `%`: the time of the scope (`paw.scope`), else the whole song.
local function whole_range(): Range
  local from, to = paw.scope.span()
  if from then
    return {from = from, to = to, whole = true}
  end
  return {from = 0, to = paw.time.bar_start(last_bar() + 1), whole = true}
end

--- Bar `n` as the user types it: in a scope with time, its own bars
--- (`paw.scope.bar_offset`), from 1 at its start.
local function bar_span(n: integer): Span
  local song = n + paw.scope.bar_offset()
  return {from = paw.time.bar_start(song), to = paw.time.bar_start(song + 1), unit = "bar", bar = n}
end

--- The bar a beat is in, as the user types it.
local function typed_bar(beat: number): integer
  return paw.time.bar_of(beat) - paw.scope.bar_offset()
end

--- The length of one beat of the signature at a place (an eighth in 6/8).
local function beat_length(at: number): number
  local num = paw.time.signature_at(at)
  return paw.time.bar(at) / (num or 4)
end

local function beat_span(bar: integer, beat: integer, text: string): Span
  local song = bar + paw.scope.bar_offset()
  local start = paw.time.bar_start(song)
  local len = beat_length(start)
  local from = start + (beat - 1) * len
  if beat < 1 or from >= paw.time.bar_start(song + 1) - EPS then
    fail("`%s`: bar %d has no beat %d", text, bar, beat)
  end
  return {from = from, to = from + len, unit = "beat"}
end

--- A mark's place in the song: Vim's marks, set with `m` in the focused view.
local function mark_beat(name: string): number
  local pos = keymap().marks()[name]
  if not pos then
    fail("`'%s`: mark %s is not set here (`m%s` sets it)", name, name, name)
  end
  if pos.beat then
    return pos.beat
  end
  return song_of((pos[2] or 0) as number)
end

--- One address at `i`: a span of time (a bar, a beat) or a point (a mark),
--- and where it ends; nil when there is none there.
local function address(s: string, i: integer): Span, integer
  local span: Span
  local j: integer
  -- `@19`, `@19.3`: a bar of the song, whatever bar the scope shows there.
  local offset = 0
  if s:sub(i, i) == "@" then
    if not s:match("^@%d", i) then
      fail("`@` names a bar of the song: `@19`")
    end
    i, offset = i + 1, paw.scope.bar_offset()
  end
  local bar, beat, e = s:match("^(%d+)%.(%d+)()", i)
  if bar then
    span, j =
      beat_span(math.tointeger(tonumber(bar)) - offset, math.tointeger(tonumber(beat)), s:sub(i, (e as integer) - 1)),
      e as integer
  else
    bar, e = s:match("^(%d+)()", i)
    if bar then
      if tonumber(bar) < 1 then
        fail("`%s`: bars count from 1", bar)
      end
      span, j = bar_span(math.tointeger(tonumber(bar)) - offset), e as integer
    elseif s:sub(i, i) == "." then
      span, j = bar_span(typed_bar(cursor_beat())), i + 1
    elseif s:sub(i, i) == "$" then
      span, j = bar_span(typed_bar(paw.time.bar_start(last_bar()))), i + 1
    elseif s:sub(i, i) == "'" and s:sub(i + 1, i + 1):match("[%a<>]") then
      local name = s:sub(i + 1, i + 1)
      if name == "<" or name == ">" then
        local r = M.selection_range()
        local at = name == "<" and r.from or r.to
        if not at then
          fail("`'%s`: the selection is of whole tracks, with no time", name)
        end
        span = {from = at, to = at, unit = "point"}
      else
        local at = mark_beat(name)
        span = {from = at, to = at, unit = "point"}
      end
      j = i + 2
    elseif s:sub(i, i):match("[%+%-]") then
      span, j = bar_span(typed_bar(cursor_beat())), i
    else
      return nil, i
    end
  end
  -- Offsets: bars, or beats after a beat.
  while true do
    local sign, digits, e2 = s:match("^([%+%-])(%d*)()", j)
    if not sign then
      break
    end
    local n = math.tointeger((digits == "" and 1 or tonumber(digits)) * (sign == "-" and -1 or 1))
    if span.unit == "bar" then
      if span.bar + n < 1 then
        fail("`%s`: before the first bar", s:sub(i, (e2 as integer) - 1))
      end
      span = bar_span(span.bar + n)
    elseif span.unit == "beat" then
      local len = span.to - span.from
      span = {from = span.from + n * len, to = span.to + n * len, unit = "beat"}
      if span.from < -EPS then
        fail("`%s`: before the start of the song", s:sub(i, (e2 as integer) - 1))
      end
    else
      local at = math.max(0, span.from + n * paw.time.bar(span.from))
      span = {from = at, to = at, unit = "point"}
    end
    j = e2 as integer
  end
  return span, j
end

-- Ranges ---------------------------------------------------------------------------
--
-- A range is a table: `from` and `to` (beats of the song, `to` not
-- included) and `bars` (the first and last bar they touch, as typed: in a scope with time, its own bars) for time;
-- `tracks` (ids) for tracks; `selection` and `region` for `'<,'>`, with
-- `pitches` ({ low, high }) when the selection was of some pitches in the
-- piano roll, and `clip_ids` (a set) when it was of clips chosen one by
-- one; `items` (see below) for the matches `:g` hands a command; `single`
-- for one plain number, a count to commands without a range; `text`, as typed.

local function finish_range(r: Range): Range
  if r.from then
    r.bars = {typed_bar(r.from), typed_bar(math.max(r.from, r.to - NEAR))}
  end
  return r
end

--- The last selection of the focused view as a range of the song.
function M.selection_range(): Range
  local region = keymap().last_selection()
  if not region then
    fail("no selection made in this view yet for '<,'>")
  end
  local view = region.view or ui().focused
  local spec = M.views[view] or {}
  local r: Range = {selection = true, region = region, view = view}
  local song = spec.song or function(c: number): number return c end
  if view == "arrange" then
    local rows = paw.groups.rows()
    r.tracks = {}
    for row = math.max(1, math.tointeger(region.r0)), math.tointeger(region.r1) do
      if rows[row] then
        r.tracks[#r.tracks + 1] = rows[row]
      end
    end
    if region.clips then
      r.clip_ids = region.clips
    end
    if region.kind ~= "line" then
      r.from, r.to = region.c0, region.c1
    end
  else
    if region.kind ~= "line" then
      r.from, r.to = song(region.c0), song(region.c1)
    end
    -- Rows are pitches in the views that have clips of notes.
    if spec.clips and region.kind ~= "char" then
      r.pitches = {math.tointeger(region.r0), math.tointeger(region.r1)}
    end
    if spec.selection then
      spec.selection(region, r)
    end
  end
  return finish_range(r)
end

local function track_index(s: string, i: integer): integer, integer
  local list = scoped()
  local n, j: integer, integer
  local num, e = s:match("^(%d+)()", i)
  if num then
    n, j = math.tointeger(tonumber(num)), e as integer
  elseif s:sub(i, i) == "." then
    local id = cursor_track()
    for k, other in ipairs(list) do
      if other == id then
        n = k
      end
    end
    if not n then
      fail("`t.`: the cursor is on no track")
    end
    j = i + 1
  elseif s:sub(i, i) == "$" then
    n, j = #list, i + 1
  else
    return nil, i
  end
  while true do
    local sign, by, e2 = s:match("^([%+%-])(%d*)()", j)
    if not sign then
      break
    end
    n = n + math.tointeger((by == "" and 1 or tonumber(by)) * (sign == "-" and -1 or 1))
    j = e2 as integer
  end
  if n < 1 or n > #list then
    fail("`t%s`: there %s %s", s:sub(i, j - 1), #list == 1 and "is" or "are", plural(#list, "track"))
  end
  return n, j
end

--- A range of tracks at `i` (`t2`, `t2,t4`, `t*`, `t/Drums/`, `t'<,'>`):
--- the ids, and where it ends; nil when there is none.
local function track_range(s: string, i: integer): {integer}, integer
  if s:sub(i, i) ~= "t" then
    return nil, i
  end
  local c, j = s:sub(i + 1, i + 1), i + 1
  if c == "*" then
    return scoped(), j + 1
  end
  if c == "/" then
    local close = s:find("/", j + 1, true)
    local text = s:sub(j + 1, (close or #s + 1) - 1)
    local out, wanted: {integer}, string = {}, text:lower()
    for _, id in ipairs(scoped()) do
      if api.track_get(id).name:lower():find(wanted, 1, true) then
        out[#out + 1] = id
      end
    end
    if #out == 0 then
      fail("`t/%s/`: no track's name holds `%s`", text, text)
    end
    return out, close and close + 1 or #s + 1
  end
  if s:match("^'<%s*,%s*'>", j) then
    local r = M.selection_range()
    local out = r.tracks
    if not out then
      -- In a view of clips: the tracks of the clips it edits.
      out = {}
      local seen: {integer: boolean} = {}
      for _, id in ipairs(view_clips() or {}) do
        local t = api.clip_get(id).track
        if not seen[t] then
          seen[t], out[#out + 1] = true, t
        end
      end
    end
    local _, last = s:find("^'<%s*,%s*'>", j)
    return out, last + 1
  end
  if not c:match("[%d%.%$]") then
    return nil, i
  end
  local a, k = track_index(s, j)
  local b = a
  local more = s:match("^,t?()", k)
  if more then
    b, k = track_index(s, more as integer)
    if not b then
      fail("`%s`: a range of tracks needs a second track: `t2,t4`", s:sub(i, (more as integer) - 1))
    end
  end
  if b < a then
    fail("`%s`: a range of tracks goes from the first to the last", s:sub(i, k - 1))
  end
  local list, out: {integer}, {integer} = scoped(), {}
  for n = a, b do
    out[#out + 1] = list[n]
  end
  return out, k
end

local function time_range(s: string, i: integer): Range, integer
  if s:sub(i, i) == "%" then
    return whole_range(), i + 1
  end
  local sel = s:match("^'<%s*,%s*'>()", i)
  if sel then
    return M.selection_range(), sel as integer
  end
  local a, j = address(s, i)
  if not a then
    return nil, i
  end
  local b = a
  local second = s:match("^[,;]()", j)
  if second then
    b, j = address(s, second as integer)
    if not b then
      fail("`%s`: a range needs a second place: `5,8`", s:sub(i, (second as integer) - 1))
    end
  end
  local from = a.from
  local to = b.unit == "point" and b.from or b.to
  if not second and a.unit == "point" then
    -- A mark alone stands for the bar it is in, as a line in Vim.
    local bar = bar_span(typed_bar(a.from))
    from, to = bar.from, bar.to
  end
  if to < from - EPS or b.from < a.from - EPS then
    fail("`%s`: a range goes from the first to the last", s:sub(i, j - 1))
  end
  if to - from < EPS then
    fail("`%s`: that range is empty", s:sub(i, j - 1))
  end
  local single = not second and s:sub(i, j - 1):match("^%d+$") ~= nil
  return {from = from, to = to, single = single}, j
end

--- The range at the start of a line and the rest of the line.
local function read_range(line: string): Range, string
  local i = line:match("^%s*()") as integer
  -- The view's own clips by an address of its own (the notation
  -- view's staves), before or after the time: `:s4 5,8>`, `:5,8 s4 >`.
  local own = adapter().clips_at
  local clips: {integer}
  local j = i
  if own then
    clips, j = own(line, i)
  end
  local tracks: {integer}
  if not clips then
    tracks, j = track_range(line, i)
  end
  local k = line:match("^%s*()", j) as integer
  local time, e = time_range(line, k)
  if time and not tracks and not clips and own then
    local after = line:match("^%s*()", e) as integer
    local found, e2 = own(line, after)
    if found then
      clips, e = found, e2
    end
  end
  if not tracks and not time and not clips then
    return nil, line
  end
  local r: Range = time or {}
  if tracks then
    -- A selection's own tracks give way to tracks named outright.
    r.tracks, r.track_range, r.single = tracks, true, nil
  end
  if clips then
    r.clips, r.tracks, r.single = clips, nil, nil
  end
  local finish = time and e or j
  r.text = line:sub(i, finish - 1):match("^(.-)%s*$")
  return finish_range(r), line:sub(finish)
end

--- Split a range from the start of a command line. Returns the range and
--- the rest. The range is nil when there is no range. When the range names
--- nothing, the third value is an error message, and there is no rest.
function M.range(line: string): Range, string, string
  local r: Range
  local rest: string
  local ok, err = pcall(function() r, rest = read_range(line) end) as (boolean, string)
  if not ok then
    return nil, nil, err
  end
  return r, rest
end

--- What a range covers, in words: "bars 5 to 8 on 2 tracks".
function M.describe(r: Range): string
  local parts: {string} = {}
  if r.from then
    local a, b = r.bars[1], r.bars[2]
    if math.abs(bar_span(a).from - r.from) < EPS and math.abs(bar_span(b).to - r.to) < EPS then
      parts[1] = a == b and "bar " .. a or string.format("bars %d–%d", a, b)
    else
      parts[1] = paw.time.format(r.from) .. "–" .. paw.time.format(r.to)
    end
  end
  if r.tracks then
    if #r.tracks == 1 then
      parts[#parts + 1] = (r.from and "on " or "") .. api.track_get(r.tracks[1]).name
    else
      parts[#parts + 1] = (r.from and "on " or "") .. plural(#r.tracks, "track")
    end
  end
  if r.items then
    parts[#parts + 1] = plural(#r.items, "match")
  end
  return table.concat(parts, " ")
end

-- Items: what a range holds -------------------------------------------------------
--
-- An item is a note, a clip or a track: `{ kind, track = id, clip = <clip
-- as paw.api gives it>, note = <note>, place = <its place in the clip>,
-- at = <beat of the song> }`, the fields a kind has.

local LEVEL: {Level: integer} = {track = 1, clip = 2, note = 3}

local function scope_clips(r: Range): {types.Clip}
  local out: {types.Clip} = {}
  local function add_track(id: integer)
    for _, c in ipairs(api.clip_list(id)) do
      out[#out + 1] = c
    end
  end
  if r.tracks then
    for _, id in ipairs(r.tracks) do
      add_track(id)
    end
  else
    local ids = view_clips(r)
    if ids then
      for _, id in ipairs(ids) do
        out[#out + 1] = api.clip_get(id)
      end
    else
      for _, id in ipairs(scoped()) do
        add_track(id)
      end
    end
  end
  if r.clip_ids then
    local kept: {types.Clip} = {}
    for _, c in ipairs(out) do
      if r.clip_ids[c.id] then
        kept[#kept + 1] = c
      end
    end
    out = kept
  end
  return out
end

local function inside(r: Range, at: number): boolean
  return not r.from or (at >= r.from - EPS and at < r.to - EPS)
end

--- The notes of a MIDI clip that can start in the range `r`, and the place
--- of each in the clip (nil: the places are the indices). The kernel gives
--- only the notes that sound in the range, so a scope of a few bars does not
--- read every note of the song. Each note that starts in the range sounds
--- in it, so the caller keeps those with `inside`.
local function notes_near(c: types.Clip, r: Range): {types.Note}, {integer}
  if not r.from then
    return api.clip_notes(c.id), nil
  end
  local range: types.NoteRange = {from = r.from - c.start - EPS, to = r.to - c.start}
  return api.clip_notes(c.id, range)
end

local function by_place(a: Item, b: Item): boolean
  if math.abs(a.at - b.at) > EPS then
    return a.at < b.at
  end
  if a.note and b.note and a.note.pitch ~= b.note.pitch then
    return a.note.pitch < b.note.pitch
  end
  return (a.order or 0) < (b.order or 0)
end

--- The notes, clips or tracks (`kind`) a range holds, in the order they
--- come in the song.
function M.items(r: Range, kind: Level): {Item}
  if r.items then
    local out: {Item} = {}
    for _, item in ipairs(r.items) do
      if item.kind == kind then
        out[#out + 1] = item
      end
    end
    return out
  end
  local out: {Item} = {}
  if kind == "track" then
    local ids = r.tracks or (view_clips() and {cursor_track()}) or scoped()
    for i, id in ipairs(ids) do
      out[i] = {kind = "track", track = id, at = 0, order = i}
    end
    return out
  end
  local order: {integer: integer} = {}
  for i, id in ipairs(api.track_list({all = true})) do
    order[id] = i
  end
  for _, c in ipairs(scope_clips(r)) do
    if kind == "clip" then
      if inside(r, c.start) then
        out[#out + 1] = {kind = "clip", track = c.track, clip = c, at = c.start, order = order[c.track]}
      end
    elseif c.kind == "midi" then
      local notes, places = notes_near(c, r)
      for i, n in ipairs(notes) do
        local at = c.start + n.start
        local pitch_ok = not r.pitches or (n.pitch >= r.pitches[1] and n.pitch <= r.pitches[2])
        if pitch_ok and inside(r, at) then
          out[#out + 1] = {
            kind = "note",
            track = c.track,
            clip = c,
            note = n,
            place = places and places[i] or i,
            at = at,
            order = order[c.track],
          }
        end
      end
    end
  end
  table.sort(out, by_place)
  return out
end

--- The address of an item, for the quickfix list and for going to it.
function M.address_of(item: Item): string
  if item.kind == "note" then
    return paw.address.note(item.clip.id, item.note.id)
  end
  if item.kind == "clip" then
    return paw.address.clip(item.clip.id)
  end
  return paw.address.track(item.track)
end

--- The item an address names, or nil.
function M.item_of(uri: string): Item
  local p = paw.address.parse(uri)
  if not p then
    return nil
  end
  if p.kind == "note" then
    local n, place = paw.address.find_note(p.clip, p.note)
    if not n then
      return nil
    end
    local c = api.clip_get(p.clip)
    return {kind = "note", track = c.track, clip = c, note = n, place = place, at = c.start + n.start}
  elseif p.kind == "clip" then
    local ok, c = pcall(api.clip_get, p.clip)
    return ok and {kind = "clip", track = c.track, clip = c, at = c.start} or nil
  elseif p.kind == "track" and p.track then
    return {kind = "track", track = p.track, at = 0}
  end
end

--- Put the cursor on an item, in the view that shows it.
function M.show(item: Item)
  paw.qf.go({location = {uri = M.address_of(item)}})
end

--- An item in a few words: "C4 vel 100 at 5.1.00 in Verse".
function M.label(item: Item): string
  if item.kind == "note" then
    local n = item.note
    return string.format(
      "%s vel %d len %g at %s in %s",
      music.name(n.pitch),
      n.velocity,
      n.length,
      paw.time.format(item.at),
      item.clip.name
    )
  elseif item.kind == "clip" then
    return string.format(
      "clip %s at %s on %s", item.clip.name, paw.time.format(item.at), api.track_get(item.track).name
    )
  end
  return "track " .. api.track_get(item.track).name
end

-- Fields and patterns --------------------------------------------------------------
--
-- A field: `paw.ex.field(name, { level = "note" | "clip" | "track", type =
-- "number" | "beats" | "pitch" | "text", get = function(item) return value
-- end, set = function(item, value, change) ... end, min, max, desc })`.
-- `set` writes what changes into `change`, a table of the fields `paw.api`
-- keeps for that kind of thing (a note's `velocity`, a clip's `name`);
-- without it the field can be matched but not set. A field of a shallower
-- level is read from the clip or track of a deeper item.

M.fields = {}

--- A field that `:s` and `:g` patterns can name (`lyric:la`): `level`
--- (note, clip or track), `type`, `get(item)`, `set(item, value, change)`.
function M.field(name: string, spec: FieldSpec)
  assert(name is string and name:match("^[%a_][%w_]*$"), "a field's name is a word")
  assert(LEVEL[spec.level], "a field's level is note, clip or track")
  M.fields[name:lower()] = util.merge(spec as {string: util.Data}, {name = name:lower()}) as Field
end

M.field(
  "pitch",
  {
    level = "note",
    type = "pitch",
    min = 0,
    max = 127,
    desc = "the note's key: `c4`, `c#4`, `bb3`, `c` in any octave, `60`",
    get = function(item: Item): ExValue return item.note.pitch end,
    set = function(_: Item, value: ExValue, change: Change) change.pitch = value as integer end,
  }
)
M.field(
  "vel",
  {
    level = "note",
    type = "number",
    min = 1,
    max = 127,
    desc = "velocity, 1 to 127",
    get = function(item: Item): ExValue return item.note.velocity end,
    set = function(_: Item, value: ExValue, change: Change) change.velocity = math.floor(value as number + 0.5) end,
  }
)
M.field(
  "len",
  {
    level = "note",
    type = "beats",
    min = 1 / 64,
    desc = "length in beats, or as a note value: `1/8`",
    get = function(item: Item): ExValue return item.note.length end,
    set = function(_: Item, value: ExValue, change: Change) change.length = value as number end,
  }
)
M.field(
  "attr",
  {
    level = "note",
    type = "text",
    desc = "the note's articulation as an M2-123 code (`11.A`, `10.2.3`), `none` for none",
    get = function(item: Item): ExValue
      local a = item.note.attr
      if not a then
        return "none"
      end
      return paw.attr.m2(a) as string or string.format("%X:%04X", a.type, a.data or 0)
    end,
    set = function(_: Item, value: ExValue, change: Change)
      if value == "none" or value == "" then
        change.attr = false
        return
      end
      local ok, attr = pcall(paw.attr.m2, value as string)
      if not ok then
        fail("`attr=%s`: %s", value, (tostring(attr):gsub("^[^:]*:%d+: ", "")))
      end
      change.attr = attr as types.NoteAttr
    end,
  }
)
M.field(
  "beat",
  {
    level = "note",
    type = "number",
    desc = "where in its bar the note starts: 1 is the downbeat, 2.5 the and of 2",
    get = function(item: Item): ExValue
      local start = paw.time.bar_floor(item.at)
      return (item.at - start) / beat_length(start) + 1
    end,
  }
)
M.field(
  "name",
  {
    level = "clip",
    type = "text",
    desc = "the clip's name",
    get = function(item: Item): ExValue return item.clip.name end,
    set = function(_: Item, value: ExValue, change: Change) change.name = value as string end,
  }
)
M.field(
  "track",
  {
    level = "track",
    type = "text",
    desc = "the track's name",
    get = function(item: Item): ExValue return api.track_get(item.track).name end,
    set = function(_: Item, value: ExValue, change: Change) change.name = value as string end,
  }
)

local pitch_word = music.pitch_word

local function field_names(): string
  local out: {string} = {}
  for name in pairs(M.fields) do
    out[#out + 1] = name
  end
  table.sort(out)
  return table.concat(out, ", ")
end

--- A value as a field of type `kind` reads it: text, a pitch, or a number.
local function value_of(kind: contracts.ExFieldType, text: string, term: string): SetValue
  if kind == "text" then
    return text
  end
  if kind == "pitch" then
    local p = pitch_word(text)
    if not p then
      fail("`%s`: `%s` is not a pitch (`c4`, `c#`, `60`)", term, text)
    end
    return p
  end
  local n = tonumber(text)
  local a, b = text:match("^(%d+)/(%d+)$")
  if not n and a and kind == "beats" and tonumber(b) > 0 then
    n = 4 * tonumber(a) / tonumber(b)
  end
  if not n then
    fail("`%s`: `%s` is not a number", term, text)
  end
  return n
end

local MATCH_OPS = {"<=", ">=", "!=", "=", "<", ">", ":"}

local function compare(op: string, a: number, b: number): boolean
  if op == "=" or op == ":" then
    return math.abs(a - b) < 1e-6
  end
  if op == "!=" then
    return math.abs(a - b) >= 1e-6
  end
  if op == "<" then
    return a < b - 1e-6
  end
  if op == "<=" then
    return a <= b + 1e-6
  end
  if op == ">" then
    return a > b + 1e-6
  end
  return a >= b - 1e-6
end

--- One alternative of a term: what it tests, the level and field it
--- names, and for text its operator and value.
local record Alternative
  level: Level
  field: string
  op: string
  value: string
  test: function(item: Item): boolean
end

--- One alternative of a term: `*`, a pitch, or a field compared with a value.
local function alternative(text: string, term: string): Alternative
  if text == "*" then
    return {test = function(): boolean return true end}
  end
  local name, rest = text:match("^([%a_][%w_]*)(.*)$")
  local spec = name and M.fields[name:lower()]
  if spec then
    for _, op in ipairs(MATCH_OPS) do
      if rest:sub(1, #op) == op then
        local value = value_of(spec.type, rest:sub(#op + 1), term)
        local get = spec.get
        if spec.type == "text" then
          if op ~= ":" and op ~= "=" and op ~= "!=" then
            fail("`%s`: text is matched with `:` (holds) or `=`", term)
          end
          local want = (value as string):lower()
          return {
            level = spec.level,
            field = spec.name,
            op = op,
            value = value as string,
            test = function(item: Item): boolean
              local got = tostring(get(item) or ""):lower()
              if op == ":" then
                return got:find(want, 1, true) ~= nil
              end
              return (got == want) == (op == "=")
            end,
          }
        elseif spec.type == "pitch" then
          local p = value as PitchWord
          if p.class then
            if op ~= "=" and op ~= ":" and op ~= "!=" then
              fail("`%s`: compare with a pitch in an octave, such as `c4`", term)
            end
            return {
              level = spec.level,
              field = spec.name,
              test = function(item: Item): boolean return ((get(item) as number) % 12 == p.class) == (op ~= "!=") end,
            }
          end
          return {
            level = spec.level,
            field = spec.name,
            test = function(item: Item): boolean return compare(op, get(item) as number, p.pitch) end,
          }
        end
        return {
          level = spec.level,
          field = spec.name,
          test = function(item: Item): boolean
            local got = get(item)
            return got ~= nil and compare(op, got as number, value as number)
          end,
        }
      end
    end
    fail("`%s`: `%s` needs a comparison and a value, such as `%s>100` or `%s=1`", term, name, name, name)
  end
  local p = pitch_word(text)
  if p then
    local get = M.fields.pitch.get
    if p.class then
      return {
        level = "note",
        field = "pitch",
        test = function(item: Item): boolean return (get(item) as number) % 12 == p.class end,
      }
    end
    return {level = "note", field = "pitch", test = function(item: Item): boolean return get(item) == p.pitch end}
  end
  fail("`%s`: not a pitch, `*` or a field compared with a value (fields: %s)", term, field_names())
end

--- What the things in the focused view are, when a pattern does not say.
local function default_level(): Level
  return view_clips() and "note" or "clip"
end

--- Read a pattern: `{ text, level, test(item), names = { substrings of names
--- it looks for } }`.
function M.pattern(text: string): Pattern
  local terms: {function(Item): boolean} = {}
  local level: Level
  local names: {string: string} = {}
  for word in text:gmatch("%S+") do
    local negated = word:sub(1, 1) == "!" and #word > 1
    local body = negated and word:sub(2) or word
    local alts: {Alternative} = {}
    for part in (body .. "|"):gmatch("([^|]*)|") do
      if part == "" then
        fail("`%s`: an empty alternative", word)
      end
      local alt = alternative(part, word)
      alts[#alts + 1] = alt
      if alt.level and (not level or LEVEL[alt.level] > LEVEL[level]) then
        level = alt.level
      end
      if alt.field == "name" and not negated and alt.op == ":" then
        names.name = alt.value
      end
      if alt.field == "track" and not negated and alt.op == ":" then
        names.track = alt.value
      end
    end
    terms[#terms + 1] = function(item: Item): boolean
      for _, alt in ipairs(alts) do
        if alt.test(item) then
          return not negated
        end
      end
      return negated
    end
  end
  level = level or default_level()
  return {
    text = text,
    level = level,
    names = names,
    test = function(item: Item): boolean
      for _, t in ipairs(terms) do
        if not t(item) then
          return false
        end
      end
      return true
    end,
  }
end

local SET_OPS = {"=", "+", "-", "*", ":"}

--- Read a replacement for what `pattern` matches: a list of changes, or
--- an empty list, which removes what matched.
function M.replacement(text: string, pattern: Pattern): {Set}
  local out: {Set} = {}
  for word in text:gmatch("%S+") do
    local set: Set
    local p = pitch_word(word)
    local by = word:match("^[%+%-]%d+$")
    if p then
      set = {field = "pitch", op = "=", value = p}
    elseif by then
      set = {field = "pitch", op = "+", value = tonumber(by)}
    else
      local name, rest = word:match("^([%a_][%w_]*)(.*)$")
      local spec = name and M.fields[name:lower()]
      if not spec then
        fail("`%s`: not a pitch, `+12`, or a field to set (fields: %s)", word, field_names())
      end
      for _, op in ipairs(SET_OPS) do
        if rest:sub(1, #op) == op then
          set = {field = spec.name, op = op, value = rest:sub(#op + 1)}
          break
        end
      end
      if not set then
        fail("`%s`: set a field with `=`, `+`, `-` or `*`: `%s=1`", word, name)
      end
      if not spec.set then
        fail("`%s`: `%s` can be matched but not set", word, spec.name)
      end
      if spec.type == "text" then
        if set.op ~= "=" and set.op ~= ":" then
          fail("`%s`: text is set with `=` (all of it) or `:` (the part matched)", word)
        end
      else
        if set.op == ":" then
          set.op = "="
        end
        -- A pitch is set to a pitch, and moved by a number of semitones.
        local kind: contracts.ExFieldType = (spec.type == "pitch" and set.op ~= "=") and "number" or spec.type
        set.value = value_of(kind, set.value as string, word)
      end
    end
    local spec = M.fields[set.field]
    if spec.level ~= pattern.level then
      fail("`%s` sets %ss, but the pattern matches %ss", word, spec.level, pattern.level)
    end
    out[#out + 1] = set
  end
  return out
end

--- What a replacement makes of one item: the fields that change, as
--- `paw.api` keeps them.
function M.change(item: Item, sets: {Set}, pattern: Pattern): Change
  local change: Change = {}
  for _, set in ipairs(sets) do
    local spec = M.fields[set.field]
    local now = spec.get(item)
    local value: ExValue
    if spec.type == "text" then
      value = set.value as string
      local part = set.op == ":" and pattern.names[set.field]
      if part and part ~= "" then
        local a, b = tostring(now):lower():find(part:lower(), 1, true)
        if a then
          value = tostring(now):sub(1, a - 1) .. (set.value as string) .. tostring(now):sub(b + 1)
        end
      end
    elseif spec.type == "pitch" and set.op == "=" then
      local p = set.value as PitchWord
      local n = now as number
      value = p.pitch or (n - n % 12 + p.class)
    elseif set.op == "=" then
      value = set.value as number
    elseif set.op == "+" then
      value = now as number + set.value as number
    elseif set.op == "-" then
      value = now as number - set.value as number
    else
      value = now as number * set.value as number
    end
    if value is number then
      if spec.min then
        value = math.max(spec.min, value)
      end
      if spec.max then
        value = math.min(spec.max, value as number)
      end
    end
    spec.set(item, value, change)
  end
  return change
end

-- Changing items -------------------------------------------------------------------

--- The edit of the notes of one clip: what changes and what goes.
local record ClipEdit
  set: {objects.NoteChangeInput}
  remove: {integer}
end

--- Make the changes `{ item, change }` and remove the items in `remove`, as
--- one edit per clip.
function M.apply(changes?: {Changed}, remove?: {Item})
  local per_clip: {integer: ClipEdit} = {}
  local order: {integer} = {}
  local function clip_edit(item: Item): ClipEdit
    local id = item.clip.id
    if not per_clip[id] then
      per_clip[id] = {set = {}, remove = {}}
      order[#order + 1] = id
    end
    return per_clip[id]
  end
  for _, c in ipairs(changes or {}) do
    local item, ch = c.item, c.change
    if item.kind == "note" then
      local n = item.note
      local e = clip_edit(item)
      e.set[#e.set + 1] = {
        index = item.place,
        start = ch.start or n.start,
        length = ch.length or n.length,
        pitch = ch.pitch or n.pitch,
        velocity = ch.velocity or n.velocity,
        meta = ch.meta or n.meta or {},
        attr = ch.attr,
      }
    elseif item.kind == "clip" then
      api.clip_set(item.clip.id, {name = ch.name, start = ch.start, muted = ch.muted})
    else
      api.track_set(item.track, {name = ch.name})
    end
  end
  local tracks: {integer} = {}
  for _, item in ipairs(remove or {}) do
    if item.kind == "note" then
      local e = clip_edit(item)
      e.remove[#e.remove + 1] = item.place
    elseif item.kind == "clip" then
      if pcall(api.clip_get, item.clip.id) then
        api.clip_remove(item.clip.id)
      end
    else
      tracks[#tracks + 1] = item.track
    end
  end
  for _, id in ipairs(order) do
    local e = per_clip[id]
    if pcall(api.clip_get, id) then
      paw.clip(id):edit_notes({set = e.set, remove = e.remove})
    end
  end
  for _, id in ipairs(tracks) do
    api.track_remove(id)
  end
end

--- Notes as a register value, as the piano roll yanks them.
local function notes_value(items: {Item}): Yanked
  local first, finish, top = math.huge, 0.0, 0
  for _, item in ipairs(items) do
    first = math.min(first, item.at)
  end
  local notes: {EditModule.YankedNote} = {}
  for i, item in ipairs(items) do
    local n = item.note
    notes[i] = {
      start = item.at - first, length = n.length, pitch = n.pitch, velocity = n.velocity, meta = n.meta, attr = n.attr
    }
    finish = math.max(finish, item.at - first + n.length)
    top = math.max(top, n.pitch)
  end
  return {kind = "notes", shape = "char", top = top, length = finish, notes = notes}
end

--- Clips as a register value: each whole, rows by track.
local function clips_value(items: {Item}): Yanked
  local first, finish = math.huge, 0.0
  for _, item in ipairs(items) do
    first = math.min(first, item.at)
  end
  local rows: {{ClipSnapshot}} = {}
  local row_of: {integer: integer} = {}
  for _, item in ipairs(items) do
    local row = row_of[item.track]
    if not row then
      rows[#rows + 1] = {}
      row = #rows
      row_of[item.track] = row
    end
    local snap = paw.clip(item.clip.id):snapshot()
    snap.start = snap.start - first
    finish = math.max(finish, snap.start + snap.length)
    rows[row][#rows[row] + 1] = snap
  end
  return {kind = "range", length = finish, rows = rows}
end

local function tracks_value(ids: {integer}): Yanked
  local tracks: {objects.TrackSnapshot} = {}
  for i, id in ipairs(ids) do
    tracks[i] = paw.track(id):snapshot()
  end
  return {kind = "tracks", tracks = tracks}
end

-- Commands -------------------------------------------------------------------------

--- The range a command works on: the one typed, the entry `:cdo` is on,
--- or the command's own default: "." the cursor's bar, "%" the whole
--- song, "track" the cursor's track.
local function range_of(ctx: Context, default: string): Range
  if ctx.range then
    return ctx.range
  end
  if ctx.target then
    local item = M.item_of(ctx.target)
    if not item then
      fail("what `%s` named is gone", ctx.target)
    end
    return {items = {item}}
  end
  local r: Range
  if default == "%" then
    r = whole_range()
  elseif default == "track" then
    local id = cursor_track()
    if not id then
      fail("no track here")
    end
    r = {tracks = {id}}
  else
    local span = bar_span(typed_bar(cursor_beat()))
    r = {from = span.from, to = span.to}
  end
  return finish_range(r)
end

--- Whether a range is about the notes of the clips the focused view edits.
local function in_view_clips(r: Range): boolean
  return not r.tracks and not r.items and view_clips(r) ~= nil
end

local function bang(ctx: Context): boolean
  return (ctx.name or ""):sub(-1) == "!"
end

local function arg_text(ctx: Context): string
  return tostring(ctx.args[1] or ""):match("^%s*(.-)%s*$")
end

local function register_of(ctx: Context): string
  local name = arg_text(ctx)
  if name == "" then
    return nil
  end
  if not name:match("^[%a%d\"_%-]$") then
    fail("`%s`: a register is one letter", name)
  end
  return name
end

local function whole_tracks(r: Range): boolean
  return r.tracks and not r.from
end

local function time_tracks(r: Range): {integer}
  return r.tracks or scoped()
end

--- Put a value in a register as `d` and `y` do.
local function keep(value: Yanked, ctx: Context, yank: boolean)
  keymap().setreg(value, register_of(ctx), yank)
end

local function remove_items(items: {Item}, ctx: Context, yank_only: boolean)
  local by: {Level: {Item}} = {note = {}, clip = {}, track = {}}
  for _, item in ipairs(items) do
    by[item.kind][#by[item.kind] + 1] = item
  end
  local kind: Level = #by.note > 0 and "note" or #by.clip > 0 and "clip" or "track"
  local list = by[kind]
  if #list == 0 then
    return paw.notify("nothing there", "warn")
  end
  local value: Yanked
  if kind == "note" then
    value = notes_value(list)
  elseif kind == "clip" then
    value = clips_value(list)
  else
    local ids: {integer} = {}
    for i, item in ipairs(list) do
      ids[i] = item.track
    end
    value = tracks_value(ids)
  end
  keep(value, ctx, yank_only)
  if not yank_only then
    M.apply(nil, list)
  end
  paw.notify(string.format("%s %s", yank_only and "yanked" or "deleted", plural(#list, kind)))
end

--- Notes whose clips start them at or after `from` move by `by` beats.
local function ripple_notes(clips: {integer}, from: number, by: number)
  for _, id in ipairs(clips) do
    local c = api.clip_get(id)
    local set: {objects.NoteChangeInput} = {}
    local notes = api.clip_notes(id)
    for place, n in ipairs(notes) do
      if c.start + n.start >= from - EPS then
        set[#set + 1] = {index = place, start = math.max(0, n.start + by)}
      end
    end
    if #set > 0 then
      paw.clip(id):edit_notes({set = set})
    end
  end
end

local function delete_or_yank(ctx: Context, yank_only: boolean)
  local r = range_of(ctx, ".")
  if r.items then
    return remove_items(r.items, ctx, yank_only)
  end
  if whole_tracks(r) then
    keep(tracks_value(r.tracks), ctx, yank_only)
    if not yank_only then
      for _, id in ipairs(r.tracks) do
        api.track_remove(id)
      end
    end
    return paw.notify(string.format("%s %s", yank_only and "yanked" or "deleted", plural(#r.tracks, "track")))
  end
  if in_view_clips(r) then
    local items = M.items(r, "note")
    if #items == 0 then
      return paw.notify("no notes in " .. M.describe(r), "warn")
    end
    remove_items(items, ctx, yank_only)
    if bang(ctx) and not yank_only then
      ripple_notes(view_clips(r), r.to, r.from - r.to)
    end
    return
  end
  local rows: {{ClipSnapshot}} = {}
  local tracks = time_tracks(r)
  for i, id in ipairs(tracks) do
    rows[i] = paw.edit.arrange.copy(id, r.from, r.to)
  end
  keep({kind = "range", length = r.to - r.from, rows = rows}, ctx, yank_only)
  if not yank_only then
    for _, id in ipairs(tracks) do
      paw.edit.arrange.clear(id, r.from, r.to)
      if bang(ctx) then
        paw.edit.arrange.ripple(id, r.to, r.from - r.to)
      end
    end
  end
  paw.notify(string.format("%s %s", yank_only and "yanked" or (bang(ctx) and "took out" or "emptied"), M.describe(r)))
end

--- The place `co` and `m` take things to: an address's start.
local function destination(text: string, name: string): number
  if text == "" then
    fail("`%s` needs a place to go to: `:5,8%s 17`", name, name)
  end
  local span, j = address(text, 1)
  if not span or text:sub(j):match("%S") then
    fail("`%s`: not a place in the song (a bar, `5.3`, `'a`, `$`)", text)
  end
  return span.from
end

--- The notes of one clip that `co` or `m` takes: their new places, or new
--- notes, and how long the clip must be.
local record Moving
  set: {objects.NoteChangeInput}
  add: {objects.NoteInput}
  clip: types.Clip
  finish: number
end

local function copy_or_move(ctx: Context, move: boolean)
  local r = range_of(ctx, ".")
  local name = move and "m" or "co"
  if r.items then
    fail("`%s` takes a range of time or tracks, not the matches of :g", name)
  end
  local text = arg_text(ctx)
  if whole_tracks(r) then
    -- Whole tracks go below track N (`0` for the top).
    local n = math.tointeger(tonumber((text:gsub("^t", ""))))
    if text == "$" or text == "t$" then
      n = #scoped()
    end
    if not n then
      fail("`%s`: tracks go below a track's number: `:t2 %s 5`, `0` for the top", text, name)
    end
    -- In a narrowed window N counts its tracks: below the Nth of them. The
    -- place counts among the tracks of the song, or of the subproject.
    local nest = paw.scope.nest()
    local place = api.track_list({nest = nest and nest.id or nil})
    local seen = scoped()
    if #seen < #place and n > 0 then
      local id = seen[math.min(n, #seen)]
      for k, other in ipairs(place) do
        if other == id then
          n = k
        end
      end
    end
    local snaps: {objects.TrackSnapshot} = {}
    for i, id in ipairs(r.tracks) do
      snaps[i] = paw.track(id):snapshot()
    end
    if move then
      local list, below = place, 0
      for _, id in ipairs(r.tracks) do
        for k = 1, math.min(n, #list) do
          if list[k] == id then
            below = below + 1
          end
        end
      end
      for _, id in ipairs(r.tracks) do
        api.track_remove(id)
      end
      n = n - below
    end
    for i, snap in ipairs(snaps) do
      paw.restore_track(snap, n + i)
    end
    return paw.notify(string.format("%s %s", move and "moved" or "copied", plural(#snaps, "track")))
  end
  local at = destination(text, name)
  local len = r.to - r.from
  if move and at > r.from + EPS and at < r.to - EPS then
    fail("`%s`: the place is inside the range moved", text)
  end
  if in_view_clips(r) then
    local items = M.items(r, "note")
    local delta = at - r.from
    local per: {integer: Moving} = {}
    for _, item in ipairs(items) do
      local n = item.note
      local start = n.start + delta
      if start < -EPS then
        fail("`%s`: before the start of clip %s; notes stay in their own clip", text, item.clip.name)
      end
      per[item.clip.id] = per[item.clip.id] or {set = {}, add = {}, clip = item.clip, finish = item.clip.length}
      local e = per[item.clip.id]
      if move then
        e.set[#e.set + 1] = {index = item.place, start = start}
      else
        e.add[#e.add + 1] = {
          start = start, length = n.length, pitch = n.pitch, velocity = n.velocity, meta = n.meta, attr = n.attr
        }
      end
      e.finish = math.max(e.finish, start + n.length)
    end
    for id, e in pairs(per) do
      if e.finish > e.clip.length + EPS then
        api.clip_set(id, {length = e.finish})
      end
      paw.clip(id):edit_notes({set = e.set, add = e.add})
    end
    return paw.notify(
      string.format("%s %s to %s", move and "moved" or "copied", plural(#items, "note"), paw.time.format(at))
    )
  end
  for _, id in ipairs(time_tracks(r)) do
    local snaps = paw.edit.arrange.copy(id, r.from, r.to)
    local target = at
    if move then
      paw.edit.arrange.clear(id, r.from, r.to)
      if bang(ctx) then
        paw.edit.arrange.ripple(id, r.to, -len)
        if target >= r.to - EPS then
          target = target - len
        end
      end
    end
    if bang(ctx) then
      paw.edit.arrange.clear(id, target, target)
      paw.edit.arrange.ripple(id, target, len)
    else
      paw.edit.arrange.clear(id, target, target + len)
    end
    for _, snap in ipairs(snaps) do
      snap.start = target + snap.start
      paw.restore_clip(snap, id)
    end
  end
  paw.notify(string.format("%s %s to %s", move and "moved" or "copied", M.describe(r), paw.time.format(at)))
end

local function shift(ctx: Context, dir: integer)
  local r = range_of(ctx, ".")
  local times = tonumber(arg_text(ctx)) or (arg_text(ctx) == "" and 1 or nil)
  if not times then
    fail("`%s`: how many steps, a number", arg_text(ctx))
  end
  local steps = (ctx.steps or 1) * times * dir
  local items: {Item}
  if r.items then
    items = M.items(r, "note")
    if #items == 0 then
      items = M.items(r, "clip")
    end
  elseif in_view_clips(r) then
    items = M.items(r, "note")
  else
    items = M.items(r, "clip")
  end
  local changes: {Changed} = {}
  for i, item in ipairs(items) do
    if item.kind == "note" then
      changes[i] = {item = item, change = {start = math.max(0, item.note.start + steps * opt.note_grid)}}
    else
      changes[i] = {item = item, change = {start = math.max(0, item.clip.start + steps * opt.grid)}}
    end
  end
  M.apply(changes)
  paw.notify(
    string.format(
      "moved %s %s", plural(#items, #items > 0 and items[1].kind or "thing"), dir > 0 and "later" or "earlier"
    )
  )
end

--- The notes a note command works on: the matches, or those in the range.
local function notes_in(ctx: Context): {Item}
  local r = range_of(ctx, ".")
  local items = M.items(r, "note")
  if #items == 0 then
    fail("no notes in %s", M.describe(r) ~= "" and M.describe(r) or "the range")
  end
  return items
end

--- The tracks a track command works on: those named, or those of the matches.
local function tracks_in(ctx: Context, name: string): {integer}
  local r = range_of(ctx, "track")
  if r.items then
    local out: {integer} = {}
    local seen: {integer: boolean} = {}
    for _, item in ipairs(r.items) do
      if not seen[item.track] then
        seen[item.track], out[#out + 1] = true, item.track
      end
    end
    return out
  end
  if not r.tracks then
    fail("`%s` takes tracks: `:t2,t4 %s`", name, name)
  end
  return r.tracks
end

--- Set a field of the tracks a command works on: `read` makes the patch
--- of each from the track as it is.
local function set_tracks(ctx: Context, name: string, read: function(types.Track): types.Track): {integer}
  local ids = tracks_in(ctx, name)
  for _, id in ipairs(ids) do
    api.track_set(id, read(api.track_get(id)))
  end
  return ids
end

--- What muting or soloing came to: `muted 3 tracks`, and those that were
--- so already, so that doing it twice does not say it did it twice.
local function said(word: string, changed: integer, total: integer, what: string): string
  if changed == total then
    return word .. " " .. plural(total, what)
  end
  if changed == 0 then
    return plural(total, what) .. (total == 1 and " was " or " were ") .. word .. " already"
  end
  return string.format(
    "%s %s (%d %s already)", word, plural(changed, what), total - changed, total - changed == 1 and "was" or "were"
  )
end

local function mute_or_solo(ctx: Context, field: string, on: boolean)
  local r = range_of(ctx, "track")
  local word = field == "mute" and (on == false and "unmuted" or "muted") or (on == false and "unsoloed" or "soloed")
  local toggle = bang(ctx)
  local function value(now: boolean): boolean
    if toggle then
      return not now
    end
    return on
  end
  local function set(get: function(integer): boolean, put: function(integer, boolean), ids: {integer}): integer
    local changed = 0
    for _, id in ipairs(ids) do
      local now = get(id)
      if value(now) ~= now then
        changed = changed + 1
      end
      put(id, value(now))
    end
    return changed
  end
  local function track_flag(id: integer): boolean
    local t = api.track_get(id)
    if field == "mute" then
      return t.mute
    end
    return t.solo
  end
  local function set_track(id: integer, to: boolean)
    if field == "mute" then
      api.track_set(id, {mute = to})
    else
      api.track_set(id, {solo = to})
    end
  end
  -- A stretch of time mutes the clips in it.
  if r.items or r.from then
    local clips = M.items(r, "clip")
    if #clips == 0 then
      if r.items then
        local ids = tracks_in(ctx, field)
        return paw.notify(said(word, set(track_flag, set_track, ids), #ids, "track"))
      end
      return paw.notify("no clips in " .. M.describe(r), "warn")
    end
    if field ~= "mute" then
      fail("clips are muted, not soloed: `solo` takes tracks")
    end
    local ids: {integer} = {}
    for i, item in ipairs(clips) do
      ids[i] = item.clip.id
    end
    local changed = set(
      function(id: integer): boolean return api.clip_get(id).muted end,
      function(id: integer, to: boolean) api.clip_set(id, {muted = to}) end,
      ids
    )
    return paw.notify(said(word, changed, #clips, "clip"))
  end
  local ids = tracks_in(ctx, field)
  paw.notify(said(word, set(track_flag, set_track, ids), #ids, "track"))
end

local function number_arg(ctx: Context, name: string, example: string): string
  local text = arg_text(ctx)
  if text == "" then
    fail("`%s` needs a value: %s", name, example)
  end
  return text
end

local function grid_arg(text: string): number
  if text == "" then
    return opt.note_grid
  end
  local a, b = text:match("^(%d+)/(%d+)$")
  local n = a and 4 * tonumber(a) / tonumber(b) or tonumber(text)
  if not n or n <= 0 then
    fail("`%s`: a grid is beats (`0.25`) or a note value (`1/16`)", text)
  end
  return n
end

--- The last pattern, and the last substitution: { pattern, replacement, flags }.
local record Last
  pattern: string
  sub: {string}
end
local last: Last = {}

--- Read `/pattern/replacement/flags` (any delimiter that is not a letter,
--- a digit or a space; `\` before it keeps it in). Missing ends are empty.
local function delimited(text: string, parts: integer): {string}, string
  text = text:match("^%s*(.*)$")
  local delim = text:sub(1, 1)
  if delim == "" then
    return nil
  end
  if delim:match("[%w%s\"|]") then
    fail("`%s`: a pattern goes between two `/`", text)
  end
  local out, cur: {string}, {string} = {}, {}
  local i = 2
  while i <= #text do
    local ch = text:sub(i, i)
    if ch == "\\" and text:sub(i + 1, i + 1) == delim then
      cur[#cur + 1], i = delim, i + 2
    elseif ch == delim and #out < parts - 1 then
      out[#out + 1], cur, i = table.concat(cur), {}, i + 1
    else
      cur[#cur + 1], i = ch, i + 1
    end
  end
  out[#out + 1] = table.concat(cur)
  return out, delim
end

local function pattern_text(text: string): string
  text = text:match("^%s*(.-)%s*$")
  if text == "" then
    if not last.pattern then
      fail("no pattern yet to use again")
    end
    return last.pattern
  end
  last.pattern = text
  return text
end

--- What a substitution would do: the matches, the ones it changes, and
--- for each its change (false to remove it).
function M.substitution(r: Range, pattern: Pattern, replacement: {Set}, flags: string): {Item}, {Chosen}
  local items: {Item} = {}
  for _, item in ipairs(M.items(r, pattern.level)) do
    if pattern.test(item) then
      items[#items + 1] = item
    end
  end
  local all = flags:find("g") ~= nil
  if opt.gdefault then
    all = not all
  end
  local chosen: {Chosen} = {}
  local seen: {integer: boolean} = {}
  for _, item in ipairs(items) do
    -- As in Vim, without `g` only the first match of each line changes,
    -- and a line here is a bar.
    local key = item.kind == "track" and item.track or paw.time.bar_of(item.at)
    if all or not seen[key] then
      seen[key] = true
      local change: Change | boolean = false
      if #replacement > 0 then
        change = M.change(item, replacement, pattern)
      end
      chosen[#chosen + 1] = {item = item, change = change}
    end
  end
  return items, chosen
end

local function substitute_args(ctx: Context): string, string, string
  local text = arg_text(ctx)
  if text == "" then
    if not last.sub then
      fail("no substitution yet to do again")
    end
    return last.sub[1], last.sub[2], ctx.keep_flags and last.sub[3] or ""
  end
  local parts = delimited(text, 3)
  local pat = pattern_text(parts[1])
  local rep, flags = parts[2] or "", parts[3] or ""
  local bad = flags:match("[^gcni&%s]")
  if bad then
    fail("`%s`: not a flag of :s (g every match, c confirm each, n only count)", bad)
  end
  if flags:find("&") then
    flags = flags:gsub("&", "") .. (last.sub and last.sub[3] or "")
  end
  return pat, rep, flags
end

--- Split the chosen into the changes to make and the items to remove.
local function split_chosen(chosen: {Chosen}): {Changed}, {Item}
  local changes: {Changed} = {}
  local removed: {Item} = {}
  for _, c in ipairs(chosen) do
    local change = c.change
    if change is Change then
      changes[#changes + 1] = {item = c.item, change = change}
    else
      removed[#removed + 1] = c.item
    end
  end
  return changes, removed
end

local confirm: function(chosen: {Chosen}, rep: string, line: string)

local function substitute(ctx: Context)
  local pat, rep, flags = substitute_args(ctx)
  last.sub = {pat, rep, flags}
  local pattern = M.pattern(pat)
  local replacement = M.replacement(rep, pattern)
  local r = range_of(ctx, ".")
  local items, chosen = M.substitution(r, pattern, replacement, flags)
  if #items == 0 then
    return paw.notify(
      string.format(
        "no %s match `%s` in %s", pattern.level .. "s", pat, M.describe(r) ~= "" and M.describe(r) or "the range"
      ),
      "warn"
    )
  end
  if flags:find("n") then
    return paw.notify(string.format("%s match", plural(#items, pattern.level)))
  end
  if flags:find("c") then
    return confirm(chosen, rep, ctx.line or (":s/" .. pat .. "/" .. rep .. "/" .. flags))
  end
  local changes, removed = split_chosen(chosen)
  M.apply(changes, removed)
  local word = #changes > 0 and "changed " or "removed "
  paw.notify(
    word
      .. plural(#chosen, pattern.level)
      .. (#chosen < #items and string.format(" of %d that match (g for all)", #items) or "")
  )
end

--- Run keys at each place: `go()` puts the cursor there first.
local function at_each(places: {function()}, keys: string)
  if keys == "" then
    fail("`normal` needs keys to type: `:5,8normal x`")
  end
  local failed: string
  for _, go in ipairs(places) do
    keymap().set_mode("n")
    go()
    local ok, err = pcall(keymap().normal, keys) as (boolean, string)
    if not ok then
      failed = failed or tostring(err)
    end
  end
  keymap().set_mode("n")
  if failed then
    paw.notify(failed, "error")
  end
end

local function normal(ctx: Context): Result
  local keys = tostring(ctx.args[1] or "")
  keys = keys:match("^%s?(.*)$")
  if not ctx.range and not ctx.target then
    keymap().normal(keys)
    return
  end
  local r = range_of(ctx, ".")
  local places: {function()} = {}
  if r.items then
    for i, item in ipairs(r.items) do
      -- By address: what an earlier run moved or removed is found or skipped.
      local uri = M.address_of(item)
      places[i] = function()
        if M.item_of(uri) then
          M.show(M.item_of(uri))
        end
      end
    end
  elseif whole_tracks(r) then
    for i, id in ipairs(r.tracks) do
      places[i] = function() ui().focus("arrange"); paw.cursor.set_track(id) end
    end
  else
    -- Where the range starts, then every bar line inside it.
    local bars: {number} = {r.from}
    for _, bar in ipairs(paw.time.bars(r.from + NEAR, r.to - NEAR)) do
      bars[#bars + 1] = bar.beat
    end
    local tracks: {integer | boolean} = in_view_clips(r) and {false} or r.tracks or {paw.cursor.track_id()}
    local a = adapter()
    for _, id in ipairs(tracks) do
      for _, beat in ipairs(bars) do
        places[#places + 1] = function()
          if id is integer then
            paw.cursor.set_track(id)
          end
          if a.go then
            a.go(beat)
          else
            paw.cursor.set_beat(beat)
          end
        end
      end
    end
  end
  at_each(places, keys)
end

--- Run a command on every match of a pattern, or put the matches in the
--- quickfix list when there is no command.
local function global(ctx: Context, invert: boolean): Result
  local parts = delimited(arg_text(ctx), 2)
  if not parts then
    fail("`g` needs a pattern: `:g/vel<20/d`")
  end
  local pat = pattern_text(parts[1])
  local pattern = M.pattern(pat)
  local r = range_of(ctx, "%")
  local matches: {Item} = {}
  for _, item in ipairs(M.items(r, pattern.level)) do
    if pattern.test(item) ~= invert then
      matches[#matches + 1] = item
    end
  end
  local cmd = (parts[2] or ""):match("^%s*(.-)%s*$")
  local title = string.format(":%s/%s/", invert and "v" or "g", pat)
  -- Vim's `:g/pat/p` prints the lines: here the list of them is the print.
  local prints: {string: boolean} = {
    [""] = true, p = true, print = true, ["#"] = true, nu = true, number = true, l = true, list = true
  }
  if prints[cmd] then
    local entries: {QfModule.Item} = {}
    for i, item in ipairs(matches) do
      entries[i] = {address = M.address_of(item), text = M.label(item), source = "ex"}
    end
    paw.qf.set(entries, {title = title})
    paw.notify(
      string.format(
        "%s in the quickfix list: ]q goes through them, :cdo runs a command on each", plural(#matches, pattern.level)
      )
    )
    return
  end
  if #matches == 0 then
    paw.notify(string.format("no %ss match `%s`", pattern.level, pat), "warn")
    return
  end
  local _, rest = M.range(cmd)
  local name, args, steps = M.split(rest or cmd)
  local spec = name and commands.get(name)
  if spec and spec.items then
    local c: Context = {range = {items = matches}, steps = steps, line = ctx.line}
    return commands.run(name, {args}, c)
  end
  -- Any other command runs once at each match, the cursor on it.
  for _, item in ipairs(matches) do
    local uri = M.address_of(item)
    local now = M.item_of(uri)
    if now then
      M.show(now)
      local c: Context = {target = uri}
      commands.exec(cmd, c)
    end
  end
end

--- What `ex` takes besides the names and the function.
local record ExOptions
  items: boolean
  desc: string
  label: string
  adjust: {contracts.AdjustParam}
end

--- Define an Ex command: a command that takes a range, as `:5,8d`.
--- `opts.items` says it also works on the matches `:g` hands it.
local function ex(names: {string}, run: function(Context): Result, opts: ExOptions)
  for i, name in ipairs(names) do
    if i == 1 then
      commands.define(name, run, {desc = opts.desc, label = opts.label, range = true, raw = true, adjust = opts.adjust})
    else
      commands.alias(name, names[1])
    end
    local spec = commands.get(name)
    spec.ex, spec.items = true, opts.items
  end
end

ex(
  {"d", "d!"},
  function(ctx: Context): Result delete_or_yank(ctx, false) end,
  {
    items = true,
    desc = "Delete what a range holds into a register: `:5,8d`, `:t2 d` whole tracks, `:5,8d!` taking the time out",
    label = "Delete",
  }
)
ex(
  {"y"},
  function(ctx: Context): Result delete_or_yank(ctx, true) end,
  {items = true, desc = "Yank what a range holds: `:5,8y`, `:5,8y a` into register a", label = "Yank"}
)
ex(
  {"co", "co!"},
  function(ctx: Context): Result copy_or_move(ctx, false) end,
  {desc = "Copy a range to a place: `:5,8co 17` over what is there, `co!` making room", label = "Copy"}
)
ex(
  {"m", "m!"},
  function(ctx: Context): Result copy_or_move(ctx, true) end,
  {desc = "Move a range to a place: `:5,8m 17`, `m!` closing the gap and making room", label = "Move"}
)
ex(
  {">"},
  function(ctx: Context): Result shift(ctx, 1) end,
  {
    items = true,
    desc = "Move the clips (or the piano roll's notes) of a range a grid step later: `:5,8>`, `:5,8>>` two",
    label = "Move later",
  }
)
ex(
  {"<"},
  function(ctx: Context): Result shift(ctx, -1) end,
  {items = true, desc = "Move the clips (or notes) of a range a grid step earlier", label = "Move earlier"}
)
ex(
  {"j"},
  function(ctx: Context): Result
    local r = range_of(ctx, ".")
    if r.items or in_view_clips(r) or whole_tracks(r) then
      fail("`j` joins the clips of a stretch of time: `:5,8j`")
    end
    local joined = 0
    for _, id in ipairs(time_tracks(r)) do
      if paw.edit.arrange.join(id, r.from, r.to) then
        joined = joined + 1
      end
    end
    paw.notify(joined == 0 and "nothing to join" or "joined clips on " .. plural(joined, "track"))
  end,
  {desc = "Join the MIDI clips of a range into one on each track: `:5,8j`", label = "Join clips"}
)
ex(
  {"mute", "mute!"},
  function(ctx: Context): Result mute_or_solo(ctx, "mute", true) end,
  {
    items = true,
    desc = "Mute tracks (`:t2,t4 mute`) or the clips of a stretch of time (`:5,8 mute`); `mute!` switches",
    label = "Mute",
  }
)
ex(
  {"unmute"},
  function(ctx: Context): Result mute_or_solo(ctx, "mute", false) end,
  {items = true, desc = "Unmute tracks or clips: `:t* unmute`", label = "Unmute"}
)
ex(
  {"solo", "solo!"},
  function(ctx: Context): Result mute_or_solo(ctx, "solo", true) end,
  {items = true, desc = "Solo tracks: `:t/Drums/ solo`; `solo!` switches", label = "Solo"}
)
ex(
  {"unsolo"},
  function(ctx: Context): Result mute_or_solo(ctx, "solo", false) end,
  {items = true, desc = "Unsolo tracks: `:t* unsolo`", label = "Unsolo"}
)
ex(
  {"volume"},
  function(ctx: Context): Result
    local text = number_arg(ctx, "volume", "`:t* volume -6` to -6 dB, `-=3` 3 dB down")
    local read = cmdline().read_value
    local ids = set_tracks(
      ctx,
      "volume",
      function(t: types.Track): types.Track
        local v = read(text, t.volume)
        if not v then
          fail("`%s`: not a volume: `-6`, `+=2`, `-=3`", text)
        end
        return {volume = util.clamp(v, -150, 24)}
      end
    )
    paw.notify("volume of " .. plural(#ids, "track"))
  end,
  {items = true, desc = "Set the volume of tracks: `:t* volume -6` sets -6 dB, `-=3` steps down 3 dB", label = "Volume"}
)
ex(
  {"pan"},
  function(ctx: Context): Result
    local text = number_arg(ctx, "pan", "`:t2 pan -0.5` half left, `+=0.1` a step right")
    local read = cmdline().read_value
    local ids = set_tracks(
      ctx,
      "pan",
      function(t: types.Track): types.Track
        local v = read(text, t.pan)
        if not v then
          fail("`%s`: not a pan: `-0.5`, `+=0.1`, `0`", text)
        end
        return {pan = util.clamp(v, -1, 1)}
      end
    )
    paw.notify("pan of " .. plural(#ids, "track"))
  end,
  {items = true, desc = "Pan tracks, -1 left to 1 right: `:t2 pan -0.5`, `+=0.1` a step right", label = "Pan"}
)
ex(
  {"quantize"},
  function(ctx: Context): Result
    local params = commands.params(ctx)
    local grid = grid_arg(params.grid ~= nil and tostring(params.grid) or "")
    local given = params.strength
    local strength: number = 100
    if given is number then
      strength = given
    elseif given ~= nil then
      fail("`strength` is from 0 to 100, not `%s`", tostring(given))
    end
    if strength < 0 or strength > 100 then
      fail("`strength` is from 0 to 100, not `%g`", strength)
    end
    local items = notes_in(ctx)
    commands.about(plural(#items, "note"))
    local changes: {Changed} = {}
    for i, item in ipairs(items) do
      -- On the song's grid, so that clips that start off it still line up.
      -- A strength under 100 moves each note that part of the way.
      local moved = transform.quantize(
        {item.note}, {grid = grid, strength = strength / 100, offset = item.at - item.note.start}
      )
      changes[i] = {item = item, change = {start = moved[1].start}}
    end
    M.apply(changes)
    paw.notify(
      string.format(
        "snapped %s to %g beats%s",
        plural(#items, "note"),
        grid,
        strength < 100 and string.format(" at %g%%", strength) or ""
      )
    )
  end,
  {
    items = true,
    desc = "Snap the notes of a range to the grid: `:%quantize`, `:5,8quantize 1/16`, `:quantize 1/16 strength=50` moves them half way",
    label = "Quantize",
    adjust = {
      {name = "grid", values = {"1/4", "1/8", "1/16", "1/32", "1/12", "1/24"}},
      {name = "strength", min = 0, max = 100, step = 5, default = 100},
    },
  }
)
ex(
  {"transpose"},
  function(ctx: Context): Result
    local given = commands.params(ctx).semitones
    local by = math.tointeger(tonumber((tostring(given == nil and "" or given):gsub("^%+", ""))))
    if not by then
      fail("`transpose` needs semitones: `:5,8transpose 12`, `-3`")
    end
    local items = notes_in(ctx)
    commands.about(plural(#items, "note"))
    local changes: {Changed} = {}
    for i, item in ipairs(items) do
      changes[i] = {item = item, change = {pitch = math.tointeger(util.clamp(item.note.pitch + by, 0, 127))}}
    end
    M.apply(changes)
    paw.notify(string.format("moved %s by %d", plural(#items, "note"), by))
  end,
  {
    items = true,
    desc = "Move the notes of a range up or down: `:5,8transpose 12`, `:%transpose -3`",
    label = "Transpose",
    adjust = {{name = "semitones", min = -127, max = 127, step = 1}},
  }
)
ex(
  {"s"},
  function(ctx: Context): Result substitute(ctx) end,
  {
    items = true,
    desc = "Change what matches a pattern: `:%s/c4/d4/g`, `:s/vel>100/vel=90/`, `:%s/name:Verse/name:Chorus/`; flags g c n",
    label = "Substitute",
  }
)
ex(
  {"&", "&&"},
  function(ctx: Context): Result ctx.args = {""}; ctx.keep_flags = ctx.name == "&&"; substitute(ctx) end,
  {items = true, desc = "Do the last :s again on a range; `&&` with its flags", label = "Substitute again"}
)
ex(
  {"g", "g!"},
  function(ctx: Context): Result return global(ctx, bang(ctx)) end,
  {
    desc = "Run a command on every match: `:g/vel<20/d`, `:g/name:Verse/mute`; no command puts them in the quickfix list",
    label = "Global",
  }
)
ex(
  {"v"},
  function(ctx: Context): Result return global(ctx, true) end,
  {desc = "Run a command on every thing that does not match: `:v/c/d`", label = "Global, not matching"}
)
-- `normal` alone types keys; with a range, at each bar, track, clip or note of it.
ex(
  {"normal"},
  normal,
  {
    items = true,
    desc = "Type keys: `normal 3j dd`; with a range at each bar of it, `:t* normal gc` at each track, `:g/c4/normal x` at each match",
  }
)

-- Running a line -------------------------------------------------------------------

--- Split what follows a range into the command's name, the text after it,
--- and how many times a `>` or `<` was typed.
function M.split(rest: string): string, string, integer
  local sym, after = rest:match("^%s*([<>]+)(.*)$")
  if sym then
    if sym:find("<") and sym:find(">") then
      fail("`%s`: `>` or `<`, not both", sym)
    end
    return sym:sub(1, 1), after, #sym
  end
  local amp = rest:match("^%s*(&&?)")
  if amp then
    return amp, rest:match("^%s*&&?(.*)$")
  end
  local name, args = rest:match("^%s*([%a_][%w_%.%-]*!?)(.*)$")
  if not name then
    return nil
  end
  if commands.get(name) then
    return name, args
  end
  -- `co16`, `s/a/b/`, `g!/x/`: the letters are the name.
  local word, bang_, more = rest:match("^%s*(%a+)(!?)(.*)$")
  if word and commands.get(word .. bang_) then
    return word .. bang_, more
  end
  return name, args
end

--- Move to where a range starts, as `:5` does in Vim.
function M.go(r: Range)
  keymap().push_jump()
  if r.tracks then
    paw.cursor.set_track(r.tracks[1])
  end
  if r.from then
    local a = adapter()
    if a.go then
      a.go(r.from)
    else
      paw.cursor.set_beat(r.from)
    end
  end
end

--- A copy of a context with a field or two more (a shallow copy: the
--- fields that the one who runs the line gave stay as they are).
local function with(ctx: Context, extra: Context): Context
  return util.merge(ctx as {string: util.Data}, extra as {string: util.Data}) as Context
end

--- Run a command line, as typed after `:`, with a range in front if it
--- has one. A line with a range, or an Ex command, is one undo step named
--- after the line (a line typed after `:` always is).
function M.exec(line: string, ctx?: Context): Result
  ctx = ctx or {}
  local range, rest, err = M.range(line)
  if err then
    error(err, 0)
  end
  if not rest:match("%S") then
    if range then
      M.go(range)
    end
    return
  end
  local name, args, steps = M.split(rest)
  if not name then
    error("`" .. rest:match("^%s*(.-)%s*$") .. "`: not a command", 0)
  end
  local spec = commands.get(name)
  if not spec then
    spec = commands.main(name)
    if not spec then
      error(commands.unknown(name), 0)
    end
    name = spec.name
  end
  local text = line:match("^%s*:?(.-)%s*$")
  if spec.ex and (range or name ~= "normal") then
    api.undo_label(":" .. text)
    return commands.run(name, {args}, with(ctx, {range = range, steps = steps, line = ":" .. text}))
  end
  local _, parsed = commands.parse(rest)
  if not range then
    return commands.run(name, parsed, ctx)
  end
  -- A number right before a command that takes no range is its count.
  if range.single and not spec.range then
    return commands.run(name, parsed, with(ctx, {count = range.bars[1]}))
  end
  api.undo_label(":" .. text)
  ctx.range = range
  if spec.range then
    local function run(r: Range): Result
      local c = with(ctx, {range = r})
      if r.selection then
        return keymap().with_selection(r.region, function(): Result return commands.run(name, parsed, c) end)
      end
      return commands.run(name, parsed, c)
    end
    -- A view of several clips runs its own commands on each in its own way.
    local each = adapter().each_clip
    if range.clips and each then
      return each(range, run)
    end
    return run(range)
  end

  if range.selection and not range.track_range then
    return keymap().with_selection(range.region, function(): Result return commands.run(name, parsed, ctx) end)
  end
  if whole_tracks(range) then
    -- Any command at each track, the cursor on it, as `:g` runs one at each match.
    for _, id in ipairs(range.tracks) do
      paw.cursor.set_track(id)
      commands.run(name, parsed, with(ctx, {target = paw.address.track(id)}))
    end
    return
  end
  error("`" .. name .. "` takes no range of bars", 0)
end

-- Confirming each change (`:s///c`) -----------------------------------------------

local view_state: Shown -- what the views show while a line is typed: see M.preview

confirm = function(chosen: {Chosen}, rep: string, line: string)
  local accepted: {Chosen} = {}
  local i = 0
  local function done()
    view_state = nil
    api.undo_label(line)
    local changes, removed = split_chosen(accepted)
    M.apply(changes, removed)
    paw.notify(string.format("changed %d of %d", #accepted, #chosen))
    api.ui_redraw()
  end
  local ask: function()
  ask = function()
    i = i + 1
    if i > #chosen then
      return done()
    end
    local c = chosen[i]
    view_state = view_state or {matches = {}, notes = {}, clips = {}}
    view_state.current = c.item
    M.show(c.item)
    local what = rep == "" and "remove" or "replace with " .. rep
    cmdline().ask_key(
      string.format("%s: %s (%d of %d)? y/n/a/q/l ", M.label(c.item), what, i, #chosen),
      function(key: string)
        if key == "y" then
          accepted[#accepted + 1] = c
          ask()
        elseif key == "n" then
          ask()
        elseif key == "a" then
          for k = i, #chosen do
            accepted[#accepted + 1] = chosen[k]
          end
          done()
        elseif key == "l" then
          accepted[#accepted + 1] = c
          done()
        elseif key == "q" or key == "<Esc>" or key == "<C-c>" then
          done()
        else
          i = i - 1
          ask()
        end
      end
    )
  end
  -- The matches stay lit while each is asked about.
  view_state = {matches = {}, notes = {}, clips = {}}
  for _, c in ipairs(chosen) do
    M.mark(view_state, c.item, c.change)
  end
  ask()
end

-- Live preview ---------------------------------------------------------------------
--
-- While a line is typed, the views show what it would act on, as Neovim's
-- `inccommand` does: the stretch of time on the rulers, the tracks in the
-- headers, the matches lit, and what a replacement would make of them as
-- ghosts in the piano roll. Nothing changes until Enter.

--- Remember an item for the views: lit, and with its change as a ghost.
function M.mark(state: Shown, item: Item, change: Change | boolean)
  state.matches[#state.matches + 1] = item
  if item.kind == "note" then
    state.notes[item.clip.id] = state.notes[item.clip.id] or {}
    state.notes[item.clip.id][item.note.id or item.place] = {item = item, change = change}
    state.clips[item.clip.id] = (state.clips[item.clip.id] or 0) + 1
  elseif item.kind == "clip" then
    state.clips[item.clip.id] = (state.clips[item.clip.id] or 0) + 1
  else
    state.tracks = state.tracks or {}
    state.tracks[item.track] = true
  end
end

local function preview_of(text: string): string, string
  local r, rest, err = M.range(text)
  if err then
    return err, "error"
  end
  local state: Shown = {matches = {}, notes = {}, clips = {}}
  if r then
    state.from, state.to = r.from, r.to
    if r.tracks then
      state.tracks = {}
      for _, id in ipairs(r.tracks) do
        state.tracks[id] = true
      end
    end
  end
  view_state = state
  local ok, name, args = pcall(M.split, rest)
  if not ok or not name then
    return r and M.describe(r) or nil
  end
  local base = name:gsub("!$", "")
  if base == "s" or base == "g" or base == "v" then
    local parts = delimited(args or "", base == "s" and 3 or 2)
    if not parts or (parts[1] == "" and not last.pattern) then
      return r and M.describe(r) or nil
    end
    local pattern = M.pattern(parts[1] ~= "" and parts[1] or last.pattern)
    local range = r or range_of({}, base == "s" and "." or "%")
    if not r then
      state.from, state.to = range.from, range.to
    end
    if base == "s" then
      local replacement = parts[2] and M.replacement(parts[2], pattern) or nil
      local items, chosen = M.substitution(range, pattern, replacement or {}, parts[3] or "")
      for _, c in ipairs(chosen) do
        M.mark(state, c.item, replacement and c.change)
      end
      local words = string.format("%s match", plural(#items, pattern.level))
      if replacement and #chosen < #items then
        words = words .. string.format(", %d change (g: all)", #chosen)
      end
      if replacement and #replacement == 0 and parts[3] then
        words = words .. ", removed"
      end
      return words
    end
    local invert = base == "v" or name == "g!"
    local n = 0
    for _, item in ipairs(M.items(range, pattern.level)) do
      if pattern.test(item) ~= invert then
        n = n + 1
        M.mark(state, item, nil)
      end
    end
    return string.format("%s %s", plural(n, pattern.level), invert and "do not match" or "match")
  end
  if r then
    return M.describe(r)
  end
end

--- Show what a line typed so far would do: called by the command line as
--- it changes, and with nil when it closes. Returns a few words for the
--- command line, and "error" when they say what is wrong.
function M.preview(text?: string): string, string
  -- The views change only when a range or a match was on them or is now:
  -- a command name alone leaves the frame as it is.
  local function lit(): boolean
    local s = view_state
    return s ~= nil and (s.from ~= nil or s.tracks ~= nil or #s.matches > 0)
  end
  local had = lit()
  view_state = nil
  if text then
    local ok, words, level = pcall(preview_of, text)
    if not ok then
      words, level = tostring(words), "error"
    end
    if level == "error" then
      view_state = nil
    end
    -- A range typed up to its comma (`:t2,`, `:5,`) is not finished yet,
    -- not wrong: it says nothing until there is more, and Enter says why.
    if level == "error" and text:match("[,;]t?%s*$") then
      words, level = nil, nil
    end
    if had or lit() then
      api.ui_redraw()
    end
    return words, level
  end
  api.ui_redraw()
end

--- What the views show now, for frontends and tests: `{ from, to, tracks,
--- matches, notes, clips, current }`, or nil.
function M.shown(): Shown
  return view_state
end

-- The piano roll: the range on its ruler, matches lit, replacements as ghosts.
local function paint_roll(p: RollLayer)
  local s = view_state
  if not s then
    return
  end
  local offset0 = roll_start()
  if s.from then
    local x0, x1 = p.x(s.from - offset0), p.x(s.to - offset0)
    local from = math.max(0, x0)
    local w = math.min(p.ruler.width, x1) - from
    if w > 0 then
      p.ruler:fill(from, 0, w, 1, nil, "ExRange")
    end
  end
  for _, part in ipairs(p.parts or {{id = p.clip.id, offset = 0}}) do
    local marks = s.notes[part.id]
    if marks then
      local offset = part.offset or 0
      for key, m in pairs(marks) do
        local n = m.item.note
        local cur = s.current
        local current = cur and cur.kind == "note" and cur.clip.id == part.id and (cur.note.id or cur.place) == key
        local x0, x1 = p.x(n.start + offset), p.x(n.start + n.length + offset)
        local row = p.row(n.pitch)
        if row then
          p.roll:fill(x0, row, math.max(1, x1 - x0), 1, nil, current and "ExCurrent" or "ExMatch")
        end
        local c = m.change
        if c is Change and (c.pitch or c.length or c.start) then
          local start, len = c.start or n.start, c.length or n.length
          local grow = p.row(c.pitch or n.pitch)
          if grow then
            local g0, g1 = p.x(start + offset), p.x(start + len + offset)
            p.roll:fill(g0, grow, math.max(1, g1 - g0), 1, opt.ascii and ":" or "░", "ExGhost")
          end
        end
      end
    end
  end
end

views().pianoroll.layer("ex", 45, paint_roll)

-- The arrange view: the range on the ruler, its tracks marked in the
-- headers, clips that match (or hold notes that do) lit with how many.
views().arrange.layers.ex = function(_: Arrange, layer: ArrangeLayer)
  local s = view_state
  if not (s and s.from) then
    return
  end
  local x0, x1 = layer.x(s.from), layer.x(s.to)
  local from = math.max(0, x0)
  local w = math.min(layer.ruler.width, x1) - from
  if w > 0 then
    layer.ruler:fill(from, 0, w, 1, nil, "ExRange")
  end
end
ui().layer(
  "arrange",
  "header",
  "ex",
  45,
  function(c: PartLayer)
    local s = view_state
    if s and s.tracks and s.tracks[c.track] then
      c.buf:text(c.x, c.y, "▌", "ExCurrent")
    end
  end
)
ui().layer(
  "arrange",
  "clip",
  "ex",
  45,
  function(c: PartLayer)
    local s = view_state
    local n = s and s.clips[c.clip.id]
    if not n then
      return
    end
    local current = s.current and s.current.clip and s.current.clip.id == c.clip.id
    c.buf:fill(0, 0, c.width, 1, nil, current and "ExCurrent" or "ExMatch")
    local label = s.notes[c.clip.id] and tostring(n) or nil
    if label and c.width > #label + 2 then
      c.buf:text(c.width - #label - 1, 0, label, current and "ExCurrent" or "ExMatch")
    end
  end
)

-- Completion of ranges ---------------------------------------------------------------

--- What could finish a range being typed: marks after `'`, tracks after
--- `t/`. Nil when the line is not in the middle of one.
function M.complete_range(line: string): {commands.Entry}
  local before = line:match("^(.-)'%a?$")
  if before and not before:find("%s") then
    local out: {commands.Entry} = {{text = before .. "'<,'>", label = "'<,'>", desc = "the last selection"}}
    local names: {string} = {}
    for name in pairs(keymap().marks()) do
      if name:match("^%a$") then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local ok, at = pcall(mark_beat, name)
      out[#out + 1] = {
        text = before .. "'" .. name, label = "'" .. name, desc = ok and "mark at " .. paw.time.format(at) or "mark"
      }
    end
    local typed = line:match("'(%a)$")
    if typed then
      local kept: {commands.Entry} = {}
      for _, c in ipairs(out) do
        if c.label:sub(2, 2) == typed then
          kept[#kept + 1] = c
        end
      end
      out = kept
    end
    return out
  end
  local stem = line:match("^%s*t/([^/]*)$")
  if stem then
    local out: {commands.Entry} = {}
    for i, id in ipairs(scoped()) do
      local name = api.track_get(id).name
      if name:lower():find(stem:lower(), 1, true) then
        out[#out + 1] = {text = "t/" .. name .. "/ ", label = "t/" .. name .. "/", desc = "track " .. i}
      end
    end
    return out
  end
end

--- Field names as they are typed in a pattern: `:%s/ve` offers `vel`.
function M.complete_pattern(line: string): {commands.Entry}
  local head, word = line:match("^(.-[/%s|!])([%a_]+)$")
  if not head or not line:find("[sgv]!?/") then
    return nil
  end
  local out: {commands.Entry} = {}
  for name, spec in pairs(M.fields) do
    if name:sub(1, #word) == word:lower() and name ~= word:lower() then
      out[#out + 1] = {text = head .. name, label = name, desc = spec.desc}
    end
  end
  table.sort(out, function(a: commands.Entry, b: commands.Entry): boolean return a.label < b.label end)
  return #out > 0 and out or nil
end

return M
