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
local api = paw.api
local util = paw.util
local commands = paw.commands
local EPS = 1e-9
local NEAR = 1e-6   -- how near a bar line a beat may be and still count as on it

local M = {}

paw.option.define("gdefault", false)   -- `:s` changes every match without `g`, and only the first of each bar with it

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

local function fail(text, ...) error(string.format(text, ...), 0) end

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
function M.view(name, spec) M.views[name] = spec end

local function roll() return paw.ui.views.pianoroll end
local function roll_start()
  local clip = roll():clip()
  return clip and clip.start or 0
end

M.view("arrange", {
  track = function() return paw.cursor.track_id() end,
  go = function(beat) paw.cursor.set_beat(beat) end,
})
M.view("pianoroll", {
  song = function(col) return roll_start() + col end,
  col = function(beat) return beat - roll_start() end,
  clips = function() return roll():clip() and paw.roll_clips.ids() or nil end,
  track = function()
    local clip = roll():clip()
    return clip and clip.track or nil
  end,
  go = function(beat) roll():set(nil, beat - roll_start()) end,
})

local function adapter() return M.views[paw.ui.focused] or {} end

local function song_of(col)
  local a = adapter()
  return a.song and a.song(col) or col
end

--- The beat of the song the focused view's cursor is on.
local function cursor_beat()
  local view = paw.ui.views[paw.ui.focused]
  local g = view and view.grid
  if not g then return paw.cursor.beat end
  local _, col = g.get()
  return song_of(col)
end

--- The track the focused view is about: the cursor's, or the clip's it edits.
local function cursor_track()
  local a = adapter()
  return (a.track and a.track()) or paw.cursor.track_id()
end

--- The clips the focused view edits, or nil when it is about the whole song.
--- The clips the focused view edits: those a range names of them (`r.clips`,
--- the notation view's staves), else the view's own.
local function view_clips(r)
  if r and r.clips then return r.clips end
  local a = adapter()
  return a.clips and a.clips() or nil
end

--- The tracks a range can name: those of the narrowed tab's group, in a
--- tab narrowed to one (`paw.scope`); `t1` is the first of them.
local function scoped() return paw.scope.tracks() end

-- Addresses of time --------------------------------------------------------------

local function song_end()
  local finish = 0
  for _, id in ipairs(api.track_list()) do
    for _, c in ipairs(api.clip_list(id)) do finish = math.max(finish, c.start + c.length) end
  end
  return finish
end

local function last_bar() return math.max(1, paw.time.bar_of(math.max(0, song_end() - NEAR))) end

local function bar_span(n) return { from = paw.time.bar_start(n), to = paw.time.bar_start(n + 1), unit = "bar", bar = n } end

--- The length of one beat of the signature at a place (an eighth in 6/8).
local function beat_length(at)
  local num = paw.time.signature_at(at)
  if type(num) == "table" then num = num[1] end
  return paw.time.bar(at) / (num or 4)
end

local function beat_span(bar, beat, text)
  local start = paw.time.bar_start(bar)
  local len = beat_length(start)
  local from = start + (beat - 1) * len
  if beat < 1 or from >= paw.time.bar_start(bar + 1) - EPS then fail("`%s`: bar %d has no beat %d", text, bar, beat) end
  return { from = from, to = from + len, unit = "beat" }
end

--- A mark's place in the song: Vim's marks, set with `m` in the focused view.
local function mark_beat(name)
  local pos = paw.keymap.marks()[name]
  if not pos then fail("`'%s`: mark %s is not set here (`m%s` sets it)", name, name, name) end
  if pos.beat then return pos.beat end
  return song_of(pos[2] or 0)
end

--- One address at `i`: a span of time (a bar, a beat) or a point (a mark),
--- and where it ends; nil when there is none there.
local function address(s, i)
  local span, j
  local bar, beat, e = s:match("^(%d+)%.(%d+)()", i)
  if bar then
    span, j = beat_span(tonumber(bar), tonumber(beat), s:sub(i, e - 1)), e
  else
    bar, e = s:match("^(%d+)()", i)
    if bar then
      if tonumber(bar) < 1 then fail("`%s`: bars count from 1", bar) end
      span, j = bar_span(tonumber(bar)), e
    elseif s:sub(i, i) == "." then
      span, j = bar_span(paw.time.bar_of(cursor_beat())), i + 1
    elseif s:sub(i, i) == "$" then
      span, j = bar_span(last_bar()), i + 1
    elseif s:sub(i, i) == "'" and s:sub(i + 1, i + 1):match("[%a<>]") then
      local name = s:sub(i + 1, i + 1)
      if name == "<" or name == ">" then
        local r = M.selection_range()
        local at = name == "<" and r.from or r.to
        if not at then fail("`'%s`: the selection is of whole tracks, with no time", name) end
        span = { from = at, to = at, unit = "point" }
      else
        local at = mark_beat(name)
        span = { from = at, to = at, unit = "point" }
      end
      j = i + 2
    elseif s:sub(i, i):match("[%+%-]") then
      span, j = bar_span(paw.time.bar_of(cursor_beat())), i
    else
      return nil, i
    end
  end
  -- Offsets: bars, or beats after a beat.
  while true do
    local sign, n, e2 = s:match("^([%+%-])(%d*)()", j)
    if not sign then break end
    n = (n == "" and 1 or tonumber(n)) * (sign == "-" and -1 or 1)
    if span.unit == "bar" then
      if span.bar + n < 1 then fail("`%s`: before the first bar", s:sub(i, e2 - 1)) end
      span = bar_span(span.bar + n)
    elseif span.unit == "beat" then
      local len = span.to - span.from
      span = { from = span.from + n * len, to = span.to + n * len, unit = "beat" }
      if span.from < -EPS then fail("`%s`: before the start of the song", s:sub(i, e2 - 1)) end
    else
      local at = math.max(0, span.from + n * paw.time.bar(span.from))
      span = { from = at, to = at, unit = "point" }
    end
    j = e2
  end
  return span, j
end

-- Ranges ---------------------------------------------------------------------------
--
-- A range is a table: `from` and `to` (beats of the song, `to` not
-- included) and `bars` (the first and last bar they touch) for time;
-- `tracks` (ids) for tracks; `selection` and `region` for `'<,'>`, with
-- `pitches` ({ low, high }) when the selection was of some pitches in the
-- piano roll, and `clip_ids` (a set) when it was of clips chosen one by
-- one; `items` (see below) for the matches `:g` hands a command; `single`
-- for one plain number, a count to commands without a range; `text`, as typed.

local function finish_range(r)
  if r.from then
    r.bars = { paw.time.bar_of(r.from), paw.time.bar_of(math.max(r.from, r.to - NEAR)) }
  end
  return r
end

--- The last selection of the focused view as a range of the song.
function M.selection_range()
  local region = paw.keymap.last_selection()
  if not region then fail("no selection made in this view yet for '<,'>") end
  local view = region.view or paw.ui.focused
  local spec = M.views[view] or {}
  local r = { selection = true, region = region, view = view }
  local song = spec.song or function(c) return c end
  if view == "arrange" then
    local rows = paw.groups.rows()
    r.tracks = {}
    for row = math.max(1, region.r0), region.r1 do
      if rows[row] then r.tracks[#r.tracks + 1] = rows[row] end
    end
    if region.clips then r.clip_ids = region.clips end
    if region.kind ~= "line" then r.from, r.to = region.c0, region.c1 end
  else
    if region.kind ~= "line" then r.from, r.to = song(region.c0), song(region.c1) end
    -- Rows are pitches in the views that have clips of notes.
    if spec.clips and region.kind ~= "char" then r.pitches = { region.r0, region.r1 } end
    if spec.selection then spec.selection(region, r) end
  end
  return finish_range(r)
end

local function track_index(s, i)
  local list = scoped()
  local n, j
  local num, e = s:match("^(%d+)()", i)
  if num then
    n, j = tonumber(num), e
  elseif s:sub(i, i) == "." then
    local id = cursor_track()
    for k, other in ipairs(list) do
      if other == id then n = k end
    end
    if not n then fail("`t.`: the cursor is on no track") end
    j = i + 1
  elseif s:sub(i, i) == "$" then
    n, j = #list, i + 1
  else
    return nil, i
  end
  while true do
    local sign, by, e2 = s:match("^([%+%-])(%d*)()", j)
    if not sign then break end
    n = n + (by == "" and 1 or tonumber(by)) * (sign == "-" and -1 or 1)
    j = e2
  end
  if n < 1 or n > #list then
    fail("`t%s`: there %s %s", s:sub(i, j - 1), #list == 1 and "is" or "are", plural(#list, "track"))
  end
  return n, j
end

--- A range of tracks at `i` (`t2`, `t2,t4`, `t*`, `t/Drums/`, `t'<,'>`):
--- the ids, and where it ends; nil when there is none.
local function track_range(s, i)
  if s:sub(i, i) ~= "t" then return nil, i end
  local c, j = s:sub(i + 1, i + 1), i + 1
  if c == "*" then return scoped(), j + 1 end
  if c == "/" then
    local close = s:find("/", j + 1, true)
    local text = s:sub(j + 1, (close or #s + 1) - 1)
    local out, wanted = {}, text:lower()
    for _, id in ipairs(scoped()) do
      if api.track_get(id, "name"):lower():find(wanted, 1, true) then out[#out + 1] = id end
    end
    if #out == 0 then fail("`t/%s/`: no track's name holds `%s`", text, text) end
    return out, close and close + 1 or #s + 1
  end
  if s:match("^'<%s*,%s*'>", j) then
    local r = M.selection_range()
    local out = r.tracks
    if not out then
      -- In a view of clips: the tracks of the clips it edits.
      out = {}
      local seen = {}
      for _, id in ipairs(view_clips() or {}) do
        local t = api.clip_get(id).track
        if not seen[t] then seen[t], out[#out + 1] = true, t end
      end
    end
    return out, select(2, s:find("^'<%s*,%s*'>", j)) + 1
  end
  if not c:match("[%d%.%$]") then return nil, i end
  local a, k = track_index(s, j)
  local b = a
  local more = s:match("^,t?()", k)
  if more then
    b, k = track_index(s, more)
    if not b then fail("`%s`: a range of tracks needs a second track: `t2,t4`", s:sub(i, more - 1)) end
  end
  if b < a then fail("`%s`: a range of tracks goes from the first to the last", s:sub(i, k - 1)) end
  local list, out = scoped(), {}
  for n = a, b do out[#out + 1] = list[n] end
  return out, k
end

local function time_range(s, i)
  if s:sub(i, i) == "%" then
    return { from = 0, to = paw.time.bar_start(last_bar() + 1), whole = true }, i + 1
  end
  local sel = s:match("^'<%s*,%s*'>()", i)
  if sel then return M.selection_range(), sel end
  local a, j = address(s, i)
  if not a then return nil, i end
  local b = a
  local second = s:match("^[,;]()", j)
  if second then
    b, j = address(s, second)
    if not b then fail("`%s`: a range needs a second place: `5,8`", s:sub(i, second - 1)) end
  end
  local from = a.from
  local to = b.unit == "point" and b.from or b.to
  if not second and a.unit == "point" then
    -- A mark alone stands for the bar it is in, as a line in Vim.
    local bar = bar_span(paw.time.bar_of(a.from))
    from, to = bar.from, bar.to
  end
  if to < from - EPS or b.from < a.from - EPS then fail("`%s`: a range goes from the first to the last", s:sub(i, j - 1)) end
  if to - from < EPS then fail("`%s`: that range is empty", s:sub(i, j - 1)) end
  local single = not second and s:sub(i, j - 1):match("^%d+$") ~= nil
  return { from = from, to = to, single = single }, j
end

--- Split a range from the start of a command line. Returns the range and
--- the rest. The range is nil when there is no range. When the range names
--- nothing, the third value is an error message, and there is no rest.
function M.range(line)
  local ok, r, rest = pcall(function()
    local i = line:match("^%s*()")
    -- The view's own clips by an address of its own (the notation
    -- view's staves), before or after the time: `:s4 5,8>`, `:5,8 s4 >`.
    local own = adapter().clips_at
    local clips, j = nil, i
    if own then clips, j = own(line, i) end
    local tracks
    if not clips then tracks, j = track_range(line, i) end
    local k = line:match("^%s*()", j)
    local time, e = time_range(line, k)
    if time and not tracks and not clips and own then
      local after = line:match("^%s*()", e)
      local found, e2 = own(line, after)
      if found then clips, e = found, e2 end
    end
    if not tracks and not time and not clips then return nil, line end
    local r = time or {}
    if tracks then
      -- A selection's own tracks give way to tracks named outright.
      r.tracks, r.track_range, r.single = tracks, true, nil
    end
    if clips then r.clips, r.tracks, r.single = clips, nil, nil end
    local finish = time and e or j
    r.text = line:sub(i, finish - 1):match("^(.-)%s*$")
    return finish_range(r), line:sub(finish)
  end)
  if not ok then return nil, nil, r end
  return r, rest
end

--- What a range covers, in words: "bars 5 to 8 on 2 tracks".
function M.describe(r)
  local parts = {}
  if r.from then
    local a, b = r.bars[1], r.bars[2]
    if math.abs(paw.time.bar_start(a) - r.from) < EPS and math.abs(paw.time.bar_start(b + 1) - r.to) < EPS then
      parts[1] = a == b and "bar " .. a or string.format("bars %d–%d", a, b)
    else
      parts[1] = paw.time.format(r.from) .. "–" .. paw.time.format(r.to)
    end
  end
  if r.tracks then
    if #r.tracks == 1 then
      parts[#parts + 1] = (r.from and "on " or "") .. api.track_get(r.tracks[1], "name")
    else
      parts[#parts + 1] = (r.from and "on " or "") .. plural(#r.tracks, "track")
    end
  end
  if r.items then parts[#parts + 1] = plural(#r.items, "match") end
  return table.concat(parts, " ")
end

-- Items: what a range holds -------------------------------------------------------
--
-- An item is a note, a clip or a track: `{ kind, track = id, clip = <clip
-- as paw.api gives it>, note = <note>, place = <its place in the clip>,
-- at = <beat of the song> }`, the fields a kind has.

local LEVEL = { track = 1, clip = 2, note = 3 }

local function scope_clips(r)
  local out = {}
  local function add_track(id)
    for _, c in ipairs(api.clip_list(id)) do out[#out + 1] = c end
  end
  if r.tracks then
    for _, id in ipairs(r.tracks) do add_track(id) end
  else
    local ids = view_clips(r)
    if ids then
      for _, id in ipairs(ids) do out[#out + 1] = api.clip_get(id) end
    else
      for _, id in ipairs(scoped()) do add_track(id) end
    end
  end
  if r.clip_ids then
    local kept = {}
    for _, c in ipairs(out) do
      if r.clip_ids[c.id] then kept[#kept + 1] = c end
    end
    out = kept
  end
  return out
end

local function inside(r, at)
  return not r.from or (at >= r.from - EPS and at < r.to - EPS)
end

local function by_place(a, b)
  if math.abs(a.at - b.at) > EPS then return a.at < b.at end
  if a.note and b.note and a.note.pitch ~= b.note.pitch then return a.note.pitch < b.note.pitch end
  return (a.order or 0) < (b.order or 0)
end

--- The notes, clips or tracks (`kind`) a range holds, in the order they
--- come in the song.
function M.items(r, kind)
  if r.items then
    local out = {}
    for _, item in ipairs(r.items) do
      if item.kind == kind then out[#out + 1] = item end
    end
    return out
  end
  local out = {}
  if kind == "track" then
    local ids = r.tracks or (view_clips() and { cursor_track() }) or scoped()
    for i, id in ipairs(ids) do out[i] = { kind = "track", track = id, at = 0, order = i } end
    return out
  end
  local order = {}
  for i, id in ipairs(api.track_list()) do order[id] = i end
  for _, c in ipairs(scope_clips(r)) do
    if kind == "clip" then
      if inside(r, c.start) then out[#out + 1] = { kind = "clip", track = c.track, clip = c, at = c.start, order = order[c.track] } end
    elseif c.kind == "midi" then
      for place, n in ipairs(api.clip_notes(c.id)) do
        local at = c.start + n.start
        local pitch_ok = not r.pitches or (n.pitch >= r.pitches[1] and n.pitch <= r.pitches[2])
        if pitch_ok and inside(r, at) then
          out[#out + 1] = { kind = "note", track = c.track, clip = c, note = n, place = place, at = at, order = order[c.track] }
        end
      end
    end
  end
  table.sort(out, by_place)
  return out
end

--- The address of an item, for the quickfix list and for going to it.
function M.address_of(item)
  if item.kind == "note" then return paw.address.note(item.clip.id, item.note.id) end
  if item.kind == "clip" then return paw.address.clip(item.clip.id) end
  return paw.address.track(item.track)
end

--- The item an address names, or nil.
function M.item_of(uri)
  local p = paw.address.parse(uri)
  if not p then return nil end
  if p.kind == "note" then
    local n, place = paw.address.find_note(p.clip, p.note)
    if not n then return nil end
    local c = api.clip_get(p.clip)
    return { kind = "note", track = c.track, clip = c, note = n, place = place, at = c.start + n.start }
  elseif p.kind == "clip" then
    local ok, c = pcall(api.clip_get, p.clip)
    return ok and { kind = "clip", track = c.track, clip = c, at = c.start } or nil
  elseif p.kind == "track" and p.track then
    return { kind = "track", track = p.track, at = 0 }
  end
end

--- Put the cursor on an item, in the view that shows it.
function M.show(item)
  paw.qf.go({ location = { uri = M.address_of(item) } })
end

--- An item in a few words: "C4 vel 100 at 5.1.00 in Verse".
function M.label(item)
  if item.kind == "note" then
    local n = item.note
    return string.format("%s vel %d len %g at %s in %s", paw.music.name(n.pitch), n.velocity, n.length, paw.time.format(item.at), item.clip.name)
  elseif item.kind == "clip" then
    return string.format("clip %s at %s on %s", item.clip.name, paw.time.format(item.at), api.track_get(item.track, "name"))
  end
  return "track " .. api.track_get(item.track, "name")
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
function M.field(name, spec)
  assert(type(name) == "string" and name:match("^[%a_][%w_]*$"), "a field's name is a word")
  assert(LEVEL[spec.level], "a field's level is note, clip or track")
  M.fields[name:lower()] = util.merge(spec, { name = name:lower() })
end

M.field("pitch", { level = "note", type = "pitch", min = 0, max = 127,
  desc = "the note's key: `c4`, `c#4`, `bb3`, `c` in any octave, `60`",
  get = function(item) return item.note.pitch end,
  set = function(_, value, change) change.pitch = value end })
M.field("vel", { level = "note", type = "number", min = 1, max = 127, desc = "velocity, 1 to 127",
  get = function(item) return item.note.velocity end,
  set = function(_, value, change) change.velocity = math.floor(value + 0.5) end })
M.field("len", { level = "note", type = "beats", min = 1 / 64, desc = "length in beats, or as a note value: `1/8`",
  get = function(item) return item.note.length end,
  set = function(_, value, change) change.length = value end })
M.field("attr", { level = "note", type = "text",
  desc = "the note's articulation as an M2-123 code (`11.A`, `10.2.3`), `none` for none",
  get = function(item)
    local a = item.note.attr
    if not a then return "none" end
    return paw.attr.m2(a) or string.format("%X:%04X", a.type, a.data or 0)
  end,
  set = function(_, value, change)
    if value == "none" or value == "" then change.attr = false return end
    local ok, attr = pcall(paw.attr.m2, value)
    if not ok then fail("`attr=%s`: %s", value, tostring(attr):gsub("^[^:]*:%d+: ", "")) end
    change.attr = attr
  end })
M.field("beat", { level = "note", type = "number", desc = "where in its bar the note starts: 1 is the downbeat, 2.5 the and of 2",
  get = function(item)
    local start = paw.time.bar_floor(item.at)
    return (item.at - start) / beat_length(start) + 1
  end })
M.field("name", { level = "clip", type = "text", desc = "the clip's name",
  get = function(item) return item.clip.name end,
  set = function(_, value, change) change.name = value end })
M.field("track", { level = "track", type = "text", desc = "the track's name",
  get = function(item) return api.track_get(item.track, "name") end,
  set = function(_, value, change) change.name = value end })

local pitch_word = require("paw.music").pitch_word

local function field_names()
  local out = {}
  for name in pairs(M.fields) do out[#out + 1] = name end
  table.sort(out)
  return table.concat(out, ", ")
end

local function value_of(spec, text, term)
  if spec.type == "text" then return text end
  if spec.type == "pitch" then
    local p = pitch_word(text)
    if not p then fail("`%s`: `%s` is not a pitch (`c4`, `c#`, `60`)", term, text) end
    return p
  end
  local n = tonumber(text)
  local a, b = text:match("^(%d+)/(%d+)$")
  if not n and a and spec.type == "beats" and tonumber(b) > 0 then n = 4 * tonumber(a) / tonumber(b) end
  if not n then fail("`%s`: `%s` is not a number", term, text) end
  return n
end

local MATCH_OPS = { "<=", ">=", "!=", "=", "<", ">", ":" }

local function compare(op, a, b)
  if op == "=" or op == ":" then return math.abs(a - b) < 1e-6 end
  if op == "!=" then return math.abs(a - b) >= 1e-6 end
  if op == "<" then return a < b - 1e-6 end
  if op == "<=" then return a <= b + 1e-6 end
  if op == ">" then return a > b + 1e-6 end
  return a >= b - 1e-6
end

--- One alternative of a term: `*`, a pitch, or a field compared with a value.
local function alternative(text, term)
  if text == "*" then return { test = function() return true end } end
  local name, rest = text:match("^([%a_][%w_]*)(.*)$")
  local spec = name and M.fields[name:lower()]
  if spec then
    for _, op in ipairs(MATCH_OPS) do
      if rest:sub(1, #op) == op then
        local value = value_of(spec, rest:sub(#op + 1), term)
        local get = spec.get
        if spec.type == "text" then
          if op ~= ":" and op ~= "=" and op ~= "!=" then fail("`%s`: text is matched with `:` (holds) or `=`", term) end
          local want = value:lower()
          return { level = spec.level, field = spec.name, op = op, value = value, test = function(item)
            local got = tostring(get(item) or ""):lower()
            if op == ":" then return got:find(want, 1, true) ~= nil end
            return (got == want) == (op == "=")
          end }
        elseif spec.type == "pitch" then
          if value.class then
            if op ~= "=" and op ~= ":" and op ~= "!=" then fail("`%s`: compare with a pitch in an octave, such as `c4`", term) end
            return { level = spec.level, field = spec.name, test = function(item)
              return (get(item) % 12 == value.class) == (op ~= "!=")
            end }
          end
          return { level = spec.level, field = spec.name, test = function(item) return compare(op, get(item), value.pitch) end }
        end
        return { level = spec.level, field = spec.name, test = function(item)
          local got = get(item)
          return got ~= nil and compare(op, got, value)
        end }
      end
    end
    fail("`%s`: `%s` needs a comparison and a value, such as `%s>100` or `%s=1`", term, name, name, name)
  end
  local p = pitch_word(text)
  if p then
    local get = M.fields.pitch.get
    if p.class then return { level = "note", field = "pitch", test = function(item) return get(item) % 12 == p.class end } end
    return { level = "note", field = "pitch", test = function(item) return get(item) == p.pitch end }
  end
  fail("`%s`: not a pitch, `*` or a field compared with a value (fields: %s)", term, field_names())
end

--- What the things in the focused view are, when a pattern does not say.
local function default_level() return view_clips() and "note" or "clip" end

--- Read a pattern: `{ text, level, test(item), names = { substrings of names
--- it looks for } }`.
function M.pattern(text)
  local terms, level, names = {}, nil, {}
  for word in text:gmatch("%S+") do
    local negated = word:sub(1, 1) == "!" and #word > 1
    local body = negated and word:sub(2) or word
    local alts = {}
    for part in (body .. "|"):gmatch("([^|]*)|") do
      if part == "" then fail("`%s`: an empty alternative", word) end
      local alt = alternative(part, word)
      alts[#alts + 1] = alt
      if alt.level and (not level or LEVEL[alt.level] > LEVEL[level]) then level = alt.level end
      if alt.field == "name" and not negated and alt.op == ":" then names.name = alt.value end
      if alt.field == "track" and not negated and alt.op == ":" then names.track = alt.value end
    end
    terms[#terms + 1] = function(item)
      for _, alt in ipairs(alts) do
        if alt.test(item) then return not negated end
      end
      return negated
    end
  end
  level = level or default_level()
  return {
    text = text, level = level, names = names,
    test = function(item)
      for _, t in ipairs(terms) do
        if not t(item) then return false end
      end
      return true
    end,
  }
end

local SET_OPS = { "=", "+", "-", "*", ":" }

--- Read a replacement for what `pattern` matches: a list of changes, or
--- an empty list, which removes what matched.
function M.replacement(text, pattern)
  local out = {}
  for word in text:gmatch("%S+") do
    local set
    local p = pitch_word(word)
    local by = word:match("^[%+%-]%d+$")
    if p then
      set = { field = "pitch", op = "=", value = p }
    elseif by then
      set = { field = "pitch", op = "+", value = tonumber(by) }
    else
      local name, rest = word:match("^([%a_][%w_]*)(.*)$")
      local spec = name and M.fields[name:lower()]
      if not spec then fail("`%s`: not a pitch, `+12`, or a field to set (fields: %s)", word, field_names()) end
      for _, op in ipairs(SET_OPS) do
        if rest:sub(1, #op) == op then
          set = { field = spec.name, op = op, value = rest:sub(#op + 1) }
          break
        end
      end
      if not set then fail("`%s`: set a field with `=`, `+`, `-` or `*`: `%s=1`", word, name) end
      if not spec.set then fail("`%s`: `%s` can be matched but not set", word, spec.name) end
      if spec.type == "text" then
        if set.op ~= "=" and set.op ~= ":" then fail("`%s`: text is set with `=` (all of it) or `:` (the part matched)", word) end
      else
        if set.op == ":" then set.op = "=" end
        set.value = (spec.type == "pitch" and set.op == "=") and value_of(spec, set.value, word)
          or value_of(spec.type == "pitch" and { type = "number" } or spec, set.value, word)
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
function M.change(item, sets, pattern)
  local change = {}
  for _, set in ipairs(sets) do
    local spec = M.fields[set.field]
    local now = spec.get(item)
    local value
    if spec.type == "text" then
      value = set.value
      local part = set.op == ":" and pattern.names[set.field]
      if part and part ~= "" then
        local a, b = tostring(now):lower():find(part:lower(), 1, true)
        if a then value = tostring(now):sub(1, a - 1) .. set.value .. tostring(now):sub(b + 1) end
      end
    elseif spec.type == "pitch" and set.op == "=" then
      value = set.value.pitch or (now - now % 12 + set.value.class)
    elseif set.op == "=" then
      value = set.value
    elseif set.op == "+" then
      value = now + set.value
    elseif set.op == "-" then
      value = now - set.value
    else
      value = now * set.value
    end
    if type(value) == "number" then
      if spec.min then value = math.max(spec.min, value) end
      if spec.max then value = math.min(spec.max, value) end
    end
    spec.set(item, value, change)
  end
  return change
end

-- Changing items -------------------------------------------------------------------

--- Make the changes `{ item, change }` and remove the items in `remove`, as
--- one edit per clip.
function M.apply(changes, remove)
  local per_clip, order = {}, {}
  local function clip_edit(item)
    local id = item.clip.id
    if not per_clip[id] then
      per_clip[id] = { set = {}, remove = {} }
      order[#order + 1] = id
    end
    return per_clip[id]
  end
  for _, c in ipairs(changes or {}) do
    local item = c.item
    if item.kind == "note" then
      local n = item.note
      local e = clip_edit(item)
      e.set[#e.set + 1] = util.merge({ index = item.place, start = n.start, length = n.length, pitch = n.pitch,
        velocity = n.velocity, meta = n.meta or {} }, c.change)
    elseif item.kind == "clip" then
      for key, value in pairs(c.change) do api.clip_set(item.clip.id, key, value) end
    else
      for key, value in pairs(c.change) do api.track_set(item.track, key, value) end
    end
  end
  local tracks = {}
  for _, item in ipairs(remove or {}) do
    if item.kind == "note" then
      local e = clip_edit(item)
      e.remove[#e.remove + 1] = item.place
    elseif item.kind == "clip" then
      if pcall(api.clip_get, item.clip.id) then api.clip_remove(item.clip.id) end
    else
      tracks[#tracks + 1] = item.track
    end
  end
  for _, id in ipairs(order) do
    local e = per_clip[id]
    if pcall(api.clip_get, id) then paw.clip(id):edit_notes({ set = e.set, remove = e.remove }) end
  end
  for _, id in ipairs(tracks) do api.track_remove(id) end
end

--- Notes as a register value, as the piano roll yanks them.
local function notes_value(items)
  local first, finish, top = math.huge, 0, 0
  for _, item in ipairs(items) do first = math.min(first, item.at) end
  local notes = {}
  for i, item in ipairs(items) do
    local n = item.note
    notes[i] = util.merge(n, { start = item.at - first, id = false })
    notes[i].id = nil
    finish = math.max(finish, item.at - first + n.length)
    top = math.max(top, n.pitch)
  end
  return { kind = "notes", shape = "char", top = top, length = finish, notes = notes }
end

--- Clips as a register value: each whole, rows by track.
local function clips_value(items)
  local first, finish = math.huge, 0
  for _, item in ipairs(items) do first = math.min(first, item.at) end
  local rows, row_of = {}, {}
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
  return { kind = "range", length = finish, rows = rows }
end

local function tracks_value(ids)
  local tracks = {}
  for i, id in ipairs(ids) do tracks[i] = paw.track(id):snapshot() end
  return { kind = "tracks", tracks = tracks }
end

-- Commands -------------------------------------------------------------------------

--- The range a command works on: the one typed, the entry `:cdo` is on,
--- or the command's own default: "." the cursor's bar, "%" the whole
--- song, "track" the cursor's track.
local function range_of(ctx, default)
  if ctx.range then return ctx.range end
  if ctx.target then
    local item = M.item_of(ctx.target)
    if not item then fail("what `%s` named is gone", ctx.target) end
    return { items = { item } }
  end
  local r
  if default == "%" then
    r = { from = 0, to = paw.time.bar_start(last_bar() + 1), whole = true }
  elseif default == "track" then
    local id = cursor_track()
    if not id then fail("no track here") end
    r = { tracks = { id } }
  else
    r = bar_span(paw.time.bar_of(cursor_beat()))
  end
  return finish_range(r)
end

--- Whether a range is about the notes of the clips the focused view edits.
local function in_view_clips(r)
  return not r.tracks and not r.items and view_clips(r) ~= nil
end

local function bang(ctx) return (ctx.name or ""):sub(-1) == "!" end

local function arg(ctx) return (ctx.args[1] or ""):match("^%s*(.-)%s*$") end

local function register_of(ctx)
  local name = arg(ctx)
  if name == "" then return nil end
  if not name:match("^[%a%d\"_%-]$") then fail("`%s`: a register is one letter", name) end
  return name
end

local function whole_tracks(r) return r.tracks and not r.from end

local function time_tracks(r) return r.tracks or scoped() end

--- Put a value in a register as `d` and `y` do, and say what it was.
local function keep(value, ctx, yank)
  paw.keymap.setreg(value, register_of(ctx), yank)
end

local function remove_items(items, ctx, yank_only)
  local by = { note = {}, clip = {}, track = {} }
  for _, item in ipairs(items) do by[item.kind][#by[item.kind] + 1] = item end
  local kind = #by.note > 0 and "note" or #by.clip > 0 and "clip" or "track"
  local list = by[kind]
  if #list == 0 then return paw.notify("nothing there", "warn") end
  local value
  if kind == "note" then
    value = notes_value(list)
  elseif kind == "clip" then
    value = clips_value(list)
  else
    local ids = {}
    for i, item in ipairs(list) do ids[i] = item.track end
    value = tracks_value(ids)
  end
  keep(value, ctx, yank_only)
  if not yank_only then M.apply(nil, list) end
  paw.notify(string.format("%s %s", yank_only and "yanked" or "deleted", plural(#list, kind)))
end

--- Notes whose clips start them at or after `from` move by `by` beats.
local function ripple_notes(clips, from, by)
  for _, id in ipairs(clips) do
    local c = api.clip_get(id)
    local set = {}
    for place, n in ipairs(api.clip_notes(id)) do
      if c.start + n.start >= from - EPS then set[#set + 1] = { index = place, start = math.max(0, n.start + by) } end
    end
    if #set > 0 then paw.clip(id):edit_notes({ set = set }) end
  end
end

local function delete_or_yank(ctx, yank_only)
  local r = range_of(ctx, ".")
  if r.items then return remove_items(r.items, ctx, yank_only) end
  if whole_tracks(r) then
    keep(tracks_value(r.tracks), ctx, yank_only)
    if not yank_only then
      for _, id in ipairs(r.tracks) do api.track_remove(id) end
    end
    return paw.notify(string.format("%s %s", yank_only and "yanked" or "deleted", plural(#r.tracks, "track")))
  end
  if in_view_clips(r) then
    local items = M.items(r, "note")
    if #items == 0 then return paw.notify("no notes in " .. M.describe(r), "warn") end
    remove_items(items, ctx, yank_only)
    if bang(ctx) and not yank_only then ripple_notes(view_clips(r), r.to, r.from - r.to) end
    return
  end
  local rows = {}
  local tracks = time_tracks(r)
  for i, id in ipairs(tracks) do rows[i] = paw.edit.arrange.copy(id, r.from, r.to) end
  keep({ kind = "range", length = r.to - r.from, rows = rows }, ctx, yank_only)
  if not yank_only then
    for _, id in ipairs(tracks) do
      paw.edit.arrange.clear(id, r.from, r.to)
      if bang(ctx) then paw.edit.arrange.ripple(id, r.to, r.from - r.to) end
    end
  end
  paw.notify(string.format("%s %s", yank_only and "yanked" or (bang(ctx) and "took out" or "emptied"), M.describe(r)))
end

--- The place `co` and `m` take things to: an address's start.
local function destination(text, name)
  if text == "" then fail("`%s` needs a place to go to: `:5,8%s 17`", name, name) end
  local span, j = address(text, 1)
  if not span or text:sub(j):match("%S") then fail("`%s`: not a place in the song (a bar, `5.3`, `'a`, `$`)", text) end
  return span.from
end

local function copy_or_move(ctx, move)
  local r = range_of(ctx, ".")
  local name = move and "m" or "co"
  if r.items then fail("`%s` takes a range of time or tracks, not the matches of :g", name) end
  local text = arg(ctx)
  if whole_tracks(r) then
    -- Whole tracks go below track N (`0` for the top).
    local n = tonumber((text:gsub("^t", "")))
    if text == "$" or text == "t$" then n = #scoped() end
    if not n then fail("`%s`: tracks go below a track's number: `:t2 %s 5`, `0` for the top", text, name) end
    -- In a narrowed tab N counts its tracks: below the Nth of them.
    local seen = scoped()
    if #seen < #api.track_list() and n > 0 then
      local id = seen[math.min(n, #seen)]
      for k, other in ipairs(api.track_list()) do
        if other == id then n = k end
      end
    end
    local snaps = {}
    for i, id in ipairs(r.tracks) do snaps[i] = paw.track(id):snapshot() end
    if move then
      local list, below = api.track_list(), 0
      for _, id in ipairs(r.tracks) do
        for k = 1, math.min(n, #list) do
          if list[k] == id then below = below + 1 end
        end
      end
      for _, id in ipairs(r.tracks) do api.track_remove(id) end
      n = n - below
    end
    for i, snap in ipairs(snaps) do paw.restore_track(snap, n + i) end
    return paw.notify(string.format("%s %s", move and "moved" or "copied", plural(#snaps, "track")))
  end
  local at = destination(text, name)
  local len = r.to - r.from
  if move and at > r.from + EPS and at < r.to - EPS then fail("`%s`: the place is inside the range moved", text) end
  if in_view_clips(r) then
    local items = M.items(r, "note")
    local delta = at - r.from
    local per = {}
    for _, item in ipairs(items) do
      local start = item.note.start + delta
      if start < -EPS then fail("`%s`: before the start of clip %s; notes stay in their own clip", text, item.clip.name) end
      per[item.clip.id] = per[item.clip.id] or { set = {}, add = {}, clip = item.clip, finish = item.clip.length }
      local e = per[item.clip.id]
      if move then
        e.set[#e.set + 1] = { index = item.place, start = start }
      else
        e.add[#e.add + 1] = util.merge(item.note, { start = start, id = false })
        e.add[#e.add].id = nil
      end
      e.finish = math.max(e.finish, start + item.note.length)
    end
    for id, e in pairs(per) do
      if e.finish > e.clip.length + EPS then api.clip_set(id, "length", e.finish) end
      paw.clip(id):edit_notes({ set = e.set, add = e.add })
    end
    return paw.notify(string.format("%s %s to %s", move and "moved" or "copied", plural(#items, "note"), paw.time.format(at)))
  end
  for _, id in ipairs(time_tracks(r)) do
    local snaps = paw.edit.arrange.copy(id, r.from, r.to)
    local target = at
    if move then
      paw.edit.arrange.clear(id, r.from, r.to)
      if bang(ctx) then
        paw.edit.arrange.ripple(id, r.to, -len)
        if target >= r.to - EPS then target = target - len end
      end
    end
    if bang(ctx) then
      paw.edit.arrange.clear(id, target, target)
      paw.edit.arrange.ripple(id, target, len)
    else
      paw.edit.arrange.clear(id, target, target + len)
    end
    for _, snap in ipairs(snaps) do paw.restore_clip(util.merge(snap, { start = target + snap.start }), id) end
  end
  paw.notify(string.format("%s %s to %s", move and "moved" or "copied", M.describe(r), paw.time.format(at)))
end

local function shift(ctx, dir)
  local r = range_of(ctx, ".")
  local times = tonumber(arg(ctx)) or (arg(ctx) == "" and 1)
  if not times then fail("`%s`: how many steps, a number", arg(ctx)) end
  local steps = (ctx.steps or 1) * times * dir
  local items
  if r.items then
    items = M.items(r, "note")
    if #items == 0 then items = M.items(r, "clip") end
  elseif in_view_clips(r) then
    items = M.items(r, "note")
  else
    items = M.items(r, "clip")
  end
  local changes = {}
  for i, item in ipairs(items) do
    if item.kind == "note" then
      changes[i] = { item = item, change = { start = math.max(0, item.note.start + steps * paw.opt.note_grid) } }
    else
      changes[i] = { item = item, change = { start = math.max(0, item.clip.start + steps * paw.opt.grid) } }
    end
  end
  M.apply(changes)
  paw.notify(string.format("moved %s %s", plural(#items, #items > 0 and items[1].kind or "thing"), dir > 0 and "later" or "earlier"))
end

--- The notes a note command works on: the matches, or those in the range.
local function notes_in(ctx)
  local r = range_of(ctx, ".")
  local items = M.items(r, "note")
  if #items == 0 then fail("no notes in %s", M.describe(r) ~= "" and M.describe(r) or "the range") end
  return items
end

--- The tracks a track command works on: those named, or those of the matches.
local function tracks_in(ctx, name)
  local r = range_of(ctx, "track")
  if r.items then
    local out, seen = {}, {}
    for _, item in ipairs(r.items) do
      if not seen[item.track] then seen[item.track], out[#out + 1] = true, item.track end
    end
    return out
  end
  if not r.tracks then fail("`%s` takes tracks: `:t2,t4 %s`", name, name) end
  return r.tracks
end

local function set_tracks(ctx, name, field, read)
  local ids = tracks_in(ctx, name)
  for _, id in ipairs(ids) do
    local value = read(api.track_get(id, field))
    api.track_set(id, field, value)
  end
  return ids
end

--- What muting or soloing came to: `muted 3 tracks`, and those that were
--- so already, so that doing it twice does not say it did it twice.
local function said(word, changed, total, what)
  if changed == total then return word .. " " .. plural(total, what) end
  if changed == 0 then return plural(total, what) .. (total == 1 and " was " or " were ") .. word .. " already" end
  return string.format("%s %s (%d %s already)", word, plural(changed, what), total - changed, total - changed == 1 and "was" or "were")
end

local function mute_or_solo(ctx, field, on)
  local r = range_of(ctx, "track")
  local word = field == "mute" and (on == false and "unmuted" or "muted") or (on == false and "unsoloed" or "soloed")
  local toggle = bang(ctx)
  local function value(now)
    if toggle then return not now end
    return on
  end
  local function set(get, put, ids)
    local changed = 0
    for _, id in ipairs(ids) do
      local now = get(id)
      if value(now) ~= now then changed = changed + 1 end
      put(id, value(now))
    end
    return changed
  end
  local function track_flag(id) return api.track_get(id, field) end
  local function set_track(id, to) api.track_set(id, field, to) end
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
    if field ~= "mute" then fail("clips are muted, not soloed: `solo` takes tracks") end
    local ids = {}
    for i, item in ipairs(clips) do ids[i] = item.clip.id end
    local changed = set(function(id) return api.clip_get(id).muted end, function(id, to) api.clip_set(id, "muted", to) end, ids)
    return paw.notify(said(word, changed, #clips, "clip"))
  end
  local ids = tracks_in(ctx, field)
  paw.notify(said(word, set(track_flag, set_track, ids), #ids, "track"))
end

local function number_arg(ctx, name, example)
  local text = arg(ctx)
  if text == "" then fail("`%s` needs a value: %s", name, example) end
  return text
end

local function grid_arg(text)
  if text == "" then return paw.opt.note_grid end
  local a, b = text:match("^(%d+)/(%d+)$")
  local n = a and 4 * tonumber(a) / tonumber(b) or tonumber(text)
  if not n or n <= 0 then fail("`%s`: a grid is beats (`0.25`) or a note value (`1/16`)", text) end
  return n
end

local last = {}   -- the last pattern, and the last substitution: { pattern, replacement, flags }

--- Read `/pattern/replacement/flags` (any delimiter that is not a letter,
--- a digit or a space; `\` before it keeps it in). Missing ends are empty.
local function delimited(text, parts)
  text = text:match("^%s*(.*)$")
  local delim = text:sub(1, 1)
  if delim == "" then return nil end
  if delim:match("[%w%s\"|]") then fail("`%s`: a pattern goes between two `/`", text) end
  local out, cur, i = {}, {}, 2
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

local function pattern_text(text)
  text = text:match("^%s*(.-)%s*$")
  if text == "" then
    if not last.pattern then fail("no pattern yet to use again") end
    return last.pattern
  end
  last.pattern = text
  return text
end

--- What a substitution would do: the matches, the ones it changes, and
--- for each its change (false to remove it).
function M.substitution(r, pattern, replacement, flags)
  local items = {}
  for _, item in ipairs(M.items(r, pattern.level)) do
    if pattern.test(item) then items[#items + 1] = item end
  end
  local all = flags:find("g") ~= nil
  if paw.opt.gdefault then all = not all end
  local chosen, seen = {}, {}
  for _, item in ipairs(items) do
    -- As in Vim, without `g` only the first match of each line changes,
    -- and a line here is a bar.
    local key = item.kind == "track" and item.track or paw.time.bar_of(item.at)
    if all or not seen[key] then
      seen[key] = true
      chosen[#chosen + 1] = { item = item, change = #replacement > 0 and M.change(item, replacement, pattern) or false }
    end
  end
  return items, chosen
end

local function substitute_args(ctx)
  local text = arg(ctx)
  if text == "" then
    if not last.sub then fail("no substitution yet to do again") end
    return last.sub[1], last.sub[2], ctx.keep_flags and last.sub[3] or ""
  end
  local parts = delimited(text, 3)
  local pat = pattern_text(parts[1])
  local rep, flags = parts[2] or "", parts[3] or ""
  local bad = flags:match("[^gcni&%s]")
  if bad then fail("`%s`: not a flag of :s (g every match, c confirm each, n only count)", bad) end
  if flags:find("&") then flags = flags:gsub("&", "") .. (last.sub and last.sub[3] or "") end
  return pat, rep, flags
end

local confirm

local function substitute(ctx)
  local pat, rep, flags = substitute_args(ctx)
  last.sub = { pat, rep, flags }
  local pattern = M.pattern(pat)
  local replacement = M.replacement(rep, pattern)
  local r = range_of(ctx, ".")
  local items, chosen = M.substitution(r, pattern, replacement, flags)
  if #items == 0 then return paw.notify(string.format("no %s match `%s` in %s", pattern.level .. "s", pat, M.describe(r) ~= "" and M.describe(r) or "the range"), "warn") end
  if flags:find("n") then return paw.notify(string.format("%s match", plural(#items, pattern.level))) end
  if flags:find("c") then return confirm(chosen, rep, ctx.line or (":s/" .. pat .. "/" .. rep .. "/" .. flags)) end
  local changes, removed = {}, {}
  for _, c in ipairs(chosen) do
    if c.change then changes[#changes + 1] = c else removed[#removed + 1] = c.item end
  end
  M.apply(changes, removed)
  local word = #changes > 0 and "changed " or "removed "
  paw.notify(word .. plural(#chosen, pattern.level) .. (#chosen < #items and string.format(" of %d that match (g for all)", #items) or ""))
end

--- Run keys at each place: `go()` puts the cursor there first.
local function at_each(places, keys)
  if keys == "" then fail("`normal` needs keys to type: `:5,8normal x`") end
  local failed
  for _, go in ipairs(places) do
    paw.keymap.set_mode("n")
    go()
    local ok, err = pcall(paw.keymap.normal, keys)
    if not ok then failed = failed or tostring(err) end
  end
  paw.keymap.set_mode("n")
  if failed then paw.notify(failed, "error") end
end

local function normal(ctx)
  local keys = ctx.args[1] or ""
  keys = keys:match("^%s?(.*)$")
  if not ctx.range and not ctx.target then return paw.keymap.normal(keys) end
  local r = range_of(ctx, ".")
  local places = {}
  if r.items then
    for i, item in ipairs(r.items) do
      -- By address: what an earlier run moved or removed is found or skipped.
      local uri = M.address_of(item)
      places[i] = function()
        if M.item_of(uri) then M.show(M.item_of(uri)) end
      end
    end
  elseif whole_tracks(r) then
    for i, id in ipairs(r.tracks) do
      places[i] = function()
        paw.ui.focus("arrange")
        paw.cursor.set_track(id)
      end
    end
  else
    -- Where the range starts, then every bar line inside it.
    local bars = { { beat = r.from } }
    for _, bar in ipairs(paw.time.bars(r.from + NEAR, r.to - NEAR)) do bars[#bars + 1] = bar end
    local tracks = in_view_clips(r) and { false } or r.tracks or { paw.cursor.track_id() }
    local a = adapter()
    for _, id in ipairs(tracks) do
      for _, bar in ipairs(bars) do
        places[#places + 1] = function()
          if id then paw.cursor.set_track(id) end
          if a.go then a.go(bar.beat) else paw.cursor.set_beat(bar.beat) end
        end
      end
    end
  end
  at_each(places, keys)
end

--- Run a command on every match of a pattern, or put the matches in the
--- quickfix list when there is no command.
local function global(ctx, invert)
  local parts = delimited(arg(ctx), 2)
  if not parts then fail("`g` needs a pattern: `:g/vel<20/d`") end
  local pat = pattern_text(parts[1])
  local pattern = M.pattern(pat)
  local r = range_of(ctx, "%")
  local matches = {}
  for _, item in ipairs(M.items(r, pattern.level)) do
    if pattern.test(item) ~= invert then matches[#matches + 1] = item end
  end
  local cmd = (parts[2] or ""):match("^%s*(.-)%s*$")
  local title = string.format(":%s/%s/", invert and "v" or "g", pat)
  -- Vim's `:g/pat/p` prints the lines: here the list of them is the print.
  local prints = { [""] = true, p = true, print = true, ["#"] = true, nu = true, number = true, l = true, list = true }
  if prints[cmd] then
    local entries = {}
    for i, item in ipairs(matches) do entries[i] = { address = M.address_of(item), text = M.label(item), source = "ex" } end
    paw.qf.set(entries, { title = title })
    return paw.notify(string.format("%s in the quickfix list: ]q goes through them, :cdo runs a command on each", plural(#matches, pattern.level)))
  end
  if #matches == 0 then return paw.notify(string.format("no %ss match `%s`", pattern.level, pat), "warn") end
  local _, rest = M.range(cmd)
  local name, args, steps = M.split(rest or cmd)
  local spec = name and commands.get(name)
  if spec and spec.items then
    return commands.run(name, { args }, { range = { items = matches }, steps = steps, line = ctx.line })
  end
  -- Any other command runs once at each match, the cursor on it.
  for _, item in ipairs(matches) do
    local uri = M.address_of(item)
    local now = M.item_of(uri)
    if now then
      M.show(now)
      commands.exec(cmd, { target = uri })
    end
  end
end

--- Define an Ex command: a command that takes a range, as `:5,8d`.
--- `opts.items` says it also works on the matches `:g` hands it.
local function ex(names, run, opts)
  for i, name in ipairs(names) do
    if i == 1 then
      commands.define(name, run, util.merge(opts, { range = true, raw = true }))
      local spec = commands.get(name)
      spec.ex, spec.items = true, opts.items
    else
      commands.alias(name, names[1])
      local spec = commands.get(name)
      spec.ex, spec.items = true, opts.items
    end
  end
end

ex({ "d", "d!" }, function(ctx) delete_or_yank(ctx, false) end, { items = true,
  desc = "Delete what a range holds into a register: `:5,8d`, `:t2 d` whole tracks, `:5,8d!` taking the time out", label = "Delete" })
ex({ "y" }, function(ctx) delete_or_yank(ctx, true) end, { items = true,
  desc = "Yank what a range holds: `:5,8y`, `:5,8y a` into register a", label = "Yank" })
ex({ "co", "co!" }, function(ctx) copy_or_move(ctx, false) end, {
  desc = "Copy a range to a place: `:5,8co 17` over what is there, `co!` making room", label = "Copy" })
ex({ "m", "m!" }, function(ctx) copy_or_move(ctx, true) end, {
  desc = "Move a range to a place: `:5,8m 17`, `m!` closing the gap and making room", label = "Move" })
ex({ ">" }, function(ctx) shift(ctx, 1) end, { items = true,
  desc = "Move the clips (or the piano roll's notes) of a range a grid step later: `:5,8>`, `:5,8>>` two", label = "Move later" })
ex({ "<" }, function(ctx) shift(ctx, -1) end, { items = true,
  desc = "Move the clips (or notes) of a range a grid step earlier", label = "Move earlier" })
ex({ "j" }, function(ctx)
  local r = range_of(ctx, ".")
  if r.items or in_view_clips(r) or whole_tracks(r) then fail("`j` joins the clips of a stretch of time: `:5,8j`") end
  local joined = 0
  for _, id in ipairs(time_tracks(r)) do
    if paw.edit.arrange.join(id, r.from, r.to) then joined = joined + 1 end
  end
  paw.notify(joined == 0 and "nothing to join" or "joined clips on " .. plural(joined, "track"))
end, { desc = "Join the MIDI clips of a range into one on each track: `:5,8j`", label = "Join clips" })
ex({ "mute", "mute!" }, function(ctx) mute_or_solo(ctx, "mute", true) end, { items = true,
  desc = "Mute tracks (`:t2,t4 mute`) or the clips of a stretch of time (`:5,8 mute`); `mute!` switches", label = "Mute" })
ex({ "unmute" }, function(ctx) mute_or_solo(ctx, "mute", false) end, { items = true, desc = "Unmute tracks or clips: `:t* unmute`", label = "Unmute" })
ex({ "solo", "solo!" }, function(ctx) mute_or_solo(ctx, "solo", true) end, { items = true,
  desc = "Solo tracks: `:t/Drums/ solo`; `solo!` switches", label = "Solo" })
ex({ "unsolo" }, function(ctx) mute_or_solo(ctx, "solo", false) end, { items = true, desc = "Unsolo tracks: `:t* unsolo`", label = "Unsolo" })
ex({ "volume" }, function(ctx)
  local text = number_arg(ctx, "volume", "`:t* volume -6` to -6 dB, `-=3` 3 dB down")
  local read = require("paw.views.cmdline").read_value
  local ids = set_tracks(ctx, "volume", "volume", function(now)
    local v = read(text, now)
    if not v then fail("`%s`: not a volume: `-6`, `+=2`, `-=3`", text) end
    return util.clamp(v, -150, 24)
  end)
  paw.notify("volume of " .. plural(#ids, "track"))
end, { items = true, desc = "Set the volume of tracks: `:t* volume -6` sets -6 dB, `-=3` steps down 3 dB", label = "Volume" })
ex({ "pan" }, function(ctx)
  local text = number_arg(ctx, "pan", "`:t2 pan -0.5` half left, `+=0.1` a step right")
  local read = require("paw.views.cmdline").read_value
  local ids = set_tracks(ctx, "pan", "pan", function(now)
    local v = read(text, now)
    if not v then fail("`%s`: not a pan: `-0.5`, `+=0.1`, `0`", text) end
    return util.clamp(v, -1, 1)
  end)
  paw.notify("pan of " .. plural(#ids, "track"))
end, { items = true, desc = "Pan tracks, -1 left to 1 right: `:t2 pan -0.5`, `+=0.1` a step right", label = "Pan" })
ex({ "quantize" }, function(ctx)
  local grid = grid_arg(arg(ctx))
  local items = notes_in(ctx)
  local changes = {}
  for i, item in ipairs(items) do
    -- On the song's grid, so that clips that start off it still line up.
    local at = util.round(item.at, grid)
    changes[i] = { item = item, change = { start = math.max(0, item.note.start + at - item.at) } }
  end
  M.apply(changes)
  paw.notify(string.format("snapped %s to %g beats", plural(#items, "note"), grid))
end, { items = true, desc = "Snap the notes of a range to the grid: `:%quantize`, `:5,8quantize 1/16`", label = "Quantize" })
ex({ "transpose" }, function(ctx)
  local by = tonumber((arg(ctx):gsub("^%+", "")))
  if not by then fail("`transpose` needs semitones: `:5,8transpose 12`, `-3`") end
  local items = notes_in(ctx)
  local changes = {}
  for i, item in ipairs(items) do changes[i] = { item = item, change = { pitch = util.clamp(item.note.pitch + by, 0, 127) } } end
  M.apply(changes)
  paw.notify(string.format("moved %s by %d", plural(#items, "note"), by))
end, { items = true, desc = "Move the notes of a range up or down: `:5,8transpose 12`, `:%transpose -3`", label = "Transpose" })
ex({ "s" }, substitute, { items = true,
  desc = "Change what matches a pattern: `:%s/c4/d4/g`, `:s/vel>100/vel=90/`, `:%s/name:Verse/name:Chorus/`; flags g c n", label = "Substitute" })
ex({ "&", "&&" }, function(ctx)
  ctx.args = { "" }
  ctx.keep_flags = ctx.name == "&&"
  substitute(ctx)
end, { items = true, desc = "Do the last :s again on a range; `&&` with its flags", label = "Substitute again" })
ex({ "g", "g!" }, function(ctx) global(ctx, bang(ctx)) end, {
  desc = "Run a command on every match: `:g/vel<20/d`, `:g/name:Verse/mute`; no command puts them in the quickfix list", label = "Global" })
ex({ "v" }, function(ctx) global(ctx, true) end, {
  desc = "Run a command on every thing that does not match: `:v/c/d`", label = "Global, not matching" })
-- `normal` alone types keys; with a range, at each bar, track, clip or note of it.
ex({ "normal" }, normal, { items = true,
  desc = "Type keys: `normal 3j dd`; with a range at each bar of it, `:t* normal gc` at each track, `:g/c4/normal x` at each match" })

-- Running a line -------------------------------------------------------------------

--- Split what follows a range into the command's name, the text after it,
--- and how many times a `>` or `<` was typed.
function M.split(rest)
  local sym, after = rest:match("^%s*([<>]+)(.*)$")
  if sym then
    if sym:find("<") and sym:find(">") then fail("`%s`: `>` or `<`, not both", sym) end
    return sym:sub(1, 1), after, #sym
  end
  local amp = rest:match("^%s*(&&?)")
  if amp then return amp, rest:match("^%s*&&?(.*)$") end
  local name, args = rest:match("^%s*([%a_][%w_%.%-]*!?)(.*)$")
  if not name then return nil end
  if commands.get(name) then return name, args end
  -- `co16`, `s/a/b/`, `g!/x/`: the letters are the name.
  local word, bang_, more = rest:match("^%s*(%a+)(!?)(.*)$")
  if word and commands.get(word .. bang_) then return word .. bang_, more end
  return name, args
end

--- Move to where a range starts, as `:5` does in Vim.
function M.go(r)
  paw.keymap.push_jump()
  if r.tracks then paw.cursor.set_track(r.tracks[1]) end
  if r.from then
    local a = adapter()
    if a.go then a.go(r.from) else paw.cursor.set_beat(r.from) end
  end
end

--- Run a command line, as typed after `:`, with a range in front if it
--- has one. A line with a range, or an Ex command, is one undo step named
--- after the line (a line typed after `:` always is).
function M.exec(line, ctx)
  ctx = ctx or {}
  local range, rest, err = M.range(line)
  if err then error(err, 0) end
  if not rest:match("%S") then
    if range then M.go(range) end
    return
  end
  local name, args, steps = M.split(rest)
  if not name then error("`" .. rest:match("^%s*(.-)%s*$") .. "`: not a command", 0) end
  local spec = commands.get(name)
  if not spec then
    spec = commands.main(name)
    if not spec then error(commands.unknown(name), 0) end
    name = spec.name
  end
  local text = line:match("^%s*:?(.-)%s*$")
  if spec.ex and (range or name ~= "normal") then
    api.undo_label(":" .. text)
    return commands.run(name, { args }, util.merge(ctx, { range = range, steps = steps, line = ":" .. text }))
  end
  local _, parsed = commands.parse(rest)
  if not range then return commands.run(name, parsed, ctx) end
  -- A number right before a command that takes no range is its count.
  if range.single and not spec.range then
    return commands.run(name, parsed, util.merge(ctx, { count = range.bars[1] }))
  end
  api.undo_label(":" .. text)
  ctx.range = range
  if spec.range then
    local function run(r)
      local c = util.merge(ctx, { range = r })
      if r.selection then return paw.keymap.with_selection(r.region, commands.run, name, parsed, c) end
      return commands.run(name, parsed, c)
    end
    -- A view of several clips runs its own commands on each in its own way.
    local each = adapter().each_clip
    if range.clips and each then return each(range, run) end
    return run(range)
  end

  if range.selection and not range.track_range then
    return paw.keymap.with_selection(range.region, commands.run, name, parsed, ctx)
  end
  if whole_tracks(range) then
    -- Any command at each track, the cursor on it, as `:g` runs one at each match.
    for _, id in ipairs(range.tracks) do
      paw.cursor.set_track(id)
      commands.run(name, parsed, util.merge(ctx, { target = paw.address.track(id) }))
    end
    return
  end
  error("`" .. name .. "` takes no range of bars", 0)
end

-- Confirming each change (`:s///c`) -----------------------------------------------

local view_state   -- what the views show while a line is typed: see M.preview

confirm = function(chosen, rep, line)
  local accepted, i = {}, 0
  local cmdline = require("paw.views.cmdline")
  local function done()
    view_state = nil
    api.undo_label(line)
    local changes, removed = {}, {}
    for _, c in ipairs(accepted) do
      if c.change then changes[#changes + 1] = c else removed[#removed + 1] = c.item end
    end
    M.apply(changes, removed)
    paw.notify(string.format("changed %d of %d", #accepted, #chosen))
    api.ui_redraw()
  end
  local ask
  ask = function()
    i = i + 1
    if i > #chosen then return done() end
    local c = chosen[i]
    view_state = view_state or {}
    view_state.current = c.item
    M.show(c.item)
    local what = rep == "" and "remove" or "replace with " .. rep
    cmdline.ask_key(string.format("%s: %s (%d of %d)? y/n/a/q/l ", M.label(c.item), what, i, #chosen), function(key)
      if key == "y" then
        accepted[#accepted + 1] = c
        ask()
      elseif key == "n" then
        ask()
      elseif key == "a" then
        for k = i, #chosen do accepted[#accepted + 1] = chosen[k] end
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
    end)
  end
  -- The matches stay lit while each is asked about.
  view_state = { matches = {}, notes = {}, clips = {} }
  for _, c in ipairs(chosen) do M.mark(view_state, c.item, c.change) end
  ask()
end

-- Live preview ---------------------------------------------------------------------
--
-- While a line is typed, the views show what it would act on, as Neovim's
-- `inccommand` does: the stretch of time on the rulers, the tracks in the
-- headers, the matches lit, and what a replacement would make of them as
-- ghosts in the piano roll. Nothing changes until Enter.

--- Remember an item for the views: lit, and with its change as a ghost.
function M.mark(state, item, change)
  state.matches[#state.matches + 1] = item
  if item.kind == "note" then
    state.notes[item.clip.id] = state.notes[item.clip.id] or {}
    state.notes[item.clip.id][item.note.id or item.place] = { item = item, change = change }
    state.clips[item.clip.id] = (state.clips[item.clip.id] or 0) + 1
  elseif item.kind == "clip" then
    state.clips[item.clip.id] = (state.clips[item.clip.id] or 0) + 1
  else
    state.tracks = state.tracks or {}
    state.tracks[item.track] = true
  end
end

local function preview_of(text)
  local r, rest, err = M.range(text)
  if err then return err, "error" end
  local state = { matches = {}, notes = {}, clips = {} }
  if r then
    state.from, state.to = r.from, r.to
    if r.tracks then
      state.tracks = {}
      for _, id in ipairs(r.tracks) do state.tracks[id] = true end
    end
  end
  view_state = state
  local ok, name, args = pcall(M.split, rest)
  if not ok or not name then return r and M.describe(r) or nil end
  local base = name:gsub("!$", "")
  if base == "s" or base == "g" or base == "v" then
    local parts = delimited(args or "", base == "s" and 3 or 2)
    if not parts or (parts[1] == "" and not last.pattern) then return r and M.describe(r) or nil end
    local pattern = M.pattern(parts[1] ~= "" and parts[1] or last.pattern)
    local range = r or range_of({}, base == "s" and "." or "%")
    if not r then state.from, state.to = range.from, range.to end
    if base == "s" then
      local replacement = parts[2] and M.replacement(parts[2], pattern) or nil
      local items, chosen = M.substitution(range, pattern, replacement or {}, parts[3] or "")
      for _, c in ipairs(chosen) do M.mark(state, c.item, replacement and c.change) end
      local said = string.format("%s match", plural(#items, pattern.level))
      if replacement and #chosen < #items then said = said .. string.format(", %d change (g: all)", #chosen) end
      if replacement and #replacement == 0 and parts[3] then said = said .. ", removed" end
      return said
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
  if r then return M.describe(r) end
end

--- Show what a line typed so far would do: called by the command line as
--- it changes, and with nil when it closes. Returns a few words for the
--- command line, and "error" when they say what is wrong.
function M.preview(text)
  view_state = nil
  if text then
    local ok, said, level = pcall(preview_of, text)
    if not ok then said, level = tostring(said), "error" end
    if level == "error" then view_state = nil end
    -- A range typed up to its comma (`:t2,`, `:5,`) is not finished yet,
    -- not wrong: it says nothing until there is more, and Enter says why.
    if level == "error" and text:match("[,;]t?%s*$") then said, level = nil, nil end
    api.ui_redraw()
    return said, level
  end
  api.ui_redraw()
end

--- What the views show now, for frontends and tests: `{ from, to, tracks,
--- matches, notes, clips, current }`, or nil.
function M.shown() return view_state end

-- The piano roll: the range on its ruler, matches lit, replacements as ghosts.
local function paint_roll(p)
  local s = view_state
  if not s then return end
  local offset0 = roll_start()
  if s.from then
    local x0, x1 = p.x(s.from - offset0), p.x(s.to - offset0)
    local from = math.max(0, x0)
    local w = math.min(p.ruler.width, x1) - from
    if w > 0 then p.ruler:fill(from, 0, w, 1, nil, "ExRange") end
  end
  for _, part in ipairs(p.parts or { { id = p.clip.id, offset = 0 } }) do
    local marks = s.notes[part.id]
    if marks then
      local offset = part.offset or 0
      for key, m in pairs(marks) do
        local n = m.item.note
        local current = s.current and s.current.kind == "note" and s.current.clip.id == part.id
          and (s.current.note.id or s.current.place) == key
        local x0, x1 = p.x(n.start + offset), p.x(n.start + n.length + offset)
        local row = p.row(n.pitch)
        if row then p.roll:fill(x0, row, math.max(1, x1 - x0), 1, nil, current and "ExCurrent" or "ExMatch") end
        local c = m.change
        if c and (c.pitch or c.length or c.start) then
          local start, len = c.start or n.start, c.length or n.length
          local grow = p.row(c.pitch or n.pitch)
          if grow then
            local g0, g1 = p.x(start + offset), p.x(start + len + offset)
            p.roll:fill(g0, grow, math.max(1, g1 - g0), 1, paw.opt.ascii and ":" or "░", "ExGhost")
          end
        end
      end
    end
  end
end

paw.ui.views.pianoroll.layer("ex", 45, paint_roll)

-- The arrange view: the range on the ruler, its tracks marked in the
-- headers, clips that match (or hold notes that do) lit with how many.
paw.ui.views.arrange.layers.ex = function(_, layer)
  local s = view_state
  if not (s and s.from) then return end
  local x0, x1 = layer.x(s.from), layer.x(s.to)
  local from = math.max(0, x0)
  local w = math.min(layer.ruler.width, x1) - from
  if w > 0 then layer.ruler:fill(from, 0, w, 1, nil, "ExRange") end
end
paw.ui.layer("arrange", "header", "ex", 45, function(c)
  local s = view_state
  if s and s.tracks and s.tracks[c.track] then c.buf:text(c.x, c.y, "▌", "ExCurrent") end
end)
paw.ui.layer("arrange", "clip", "ex", 45, function(c)
  local s = view_state
  local n = s and s.clips[c.clip.id]
  if not n then return end
  local current = s.current and s.current.clip and s.current.clip.id == c.clip.id
  c.buf:fill(0, 0, c.width, 1, nil, current and "ExCurrent" or "ExMatch")
  local label = s.notes[c.clip.id] and tostring(n) or nil
  if label and c.width > #label + 2 then c.buf:text(c.width - #label - 1, 0, label, current and "ExCurrent" or "ExMatch") end
end)

-- Completion of ranges ---------------------------------------------------------------

--- What could finish a range being typed: marks after `'`, tracks after
--- `t/`. Nil when the line is not in the middle of one.
function M.complete_range(line)
  local before = line:match("^(.-)'%a?$")
  if before and not before:find("%s") then
    local out = { { text = before .. "'<,'>", label = "'<,'>", desc = "the last selection" } }
    local names = {}
    for name, pos in pairs(paw.keymap.marks()) do
      if name:match("^%a$") then names[#names + 1] = { name, pos } end
    end
    table.sort(names, function(a, b) return a[1] < b[1] end)
    for _, m in ipairs(names) do
      local ok, at = pcall(mark_beat, m[1])
      out[#out + 1] = { text = before .. "'" .. m[1], label = "'" .. m[1], desc = ok and "mark at " .. paw.time.format(at) or "mark" }
    end
    local typed = line:match("'(%a)$")
    if typed then
      local kept = {}
      for _, c in ipairs(out) do
        if c.label:sub(2, 2) == typed then kept[#kept + 1] = c end
      end
      out = kept
    end
    return out
  end
  local stem = line:match("^%s*t/([^/]*)$")
  if stem then
    local out = {}
    for i, id in ipairs(scoped()) do
      local name = api.track_get(id, "name")
      if name:lower():find(stem:lower(), 1, true) then
        out[#out + 1] = { text = "t/" .. name .. "/ ", label = "t/" .. name .. "/", desc = "track " .. i }
      end
    end
    return out
  end
end

--- Field names as they are typed in a pattern: `:%s/ve` offers `vel`.
function M.complete_pattern(line)
  local head, word = line:match("^(.-[/%s|!])([%a_]+)$")
  if not head or not line:find("[sgv]!?/") then return nil end
  local out = {}
  for name, spec in pairs(M.fields) do
    if name:sub(1, #word) == word:lower() and name ~= word:lower() then
      out[#out + 1] = { text = head .. name, label = name, desc = spec.desc }
    end
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return #out > 0 and out or nil
end

return M
