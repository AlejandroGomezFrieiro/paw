-- Takes: several versions of what a clip plays, one of them playing.
--
-- Recording with the loop on goes round it, and every time round becomes a
-- take of one clip over the loop; the last is the one that plays. Sound
-- recorded over sound clips becomes their newest take (`M.record_over`).
-- Any clip can be given takes by hand as well (`:take.new`).
--
--   ]t and [t             -- the next take of the clip under the cursor, the one before
--   :take 2               -- play the second; over a selection, only there (see below)
--   :take.list            -- choose from a list
--   :take.new             -- keep what the clip plays as a take and carry on in a copy
--   :take.remove          -- throw the playing take away
--   :take.keep            -- throw the others away
--   :take.explode         -- every take as a clip on a track of its own
--
-- Comping, choosing the best of each take: cut the clip where the choice
-- changes (`S`, or select a stretch of time and say `:take 2`, which cuts
-- at its ends) and choose a take for each piece. Every piece keeps all the
-- takes, lined up, so a cut can be moved and a choice changed later.
-- `M.comp(track, take, from, to)` does it in one go, and joins pieces side
-- by side that then play the same take back into one where that is exact.
--
-- Take lanes: a track can show its takes as rows under its clips
-- (`:take.lanes`, `zt`), row k holding take k of every clip of the track
-- that has takes, each over the clip's own stretch of time, so that the
-- pieces of a comp line up into lanes. In the window a drag across row k
-- makes take k play over that stretch (`paw.frontend.act.comp`). Which
-- tracks show them is kept for the session, like open automation lanes,
-- not in the project.
--
--   :take.lanes           -- show or hide the take lanes of the cursor's track
--
-- Where they are kept: `clip.meta.takes = { active, origin, list }`. The
-- playing take is the clip's own content and its entry holds only a name;
-- the others hold theirs: `file`, `offset` and `gain` for sound, `notes`
-- and `controls` for notes. `origin` is the clip's own offset into its file
-- at the time the others' offsets were written, so that a clip trimmed or
-- cut since (which moves its offset) still finds them lined up.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local commands = require("paw.commands")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type LanesModule = require("paw.lanes")
local type objects = require("paw.objects")
local type CursorModule = require("paw.cursor")
local type EditModule = require("paw.edit")

--- A take of a clip, as `clip.meta.takes.list` keeps it. The one that plays
--- holds only its name; the others hold what they play: `file`, `offset`
--- and `gain` for sound, `notes` and `controls` for notes.
local record Take
  name: string
  file: string
  offset: number
  gain: number
  notes: {types.Note}
  controls: {types.Control}
end

--- The takes of a clip (`clip.meta.takes`): which plays, the list, and the
--- clip's offset into its file when the others' offsets were written.
local record Takes
  active: integer
  origin: number
  list: {Take}
end

--- What a take plays, as the clip would have it (`content`).
local record Content
  file: string
  offset: number
  gain: number
  notes: {types.Note}
  controls: {types.Control}
end

--- A clip: its id, or the clip (`paw.api.clip_get`, `paw.clip`).
local type ClipRef = integer | types.Clip

--- A track: its id, or the track itself (`paw.track`).
local type TrackRef = integer | contracts.TrackHandle

--- A value that `copy` passes on and never reads.
local record Value
end

--- A note or a controller move: what `same_moved` compares of each.
local record Item
  start: number
  pitch: integer
  length: number
  velocity: integer
  type: types.ControlType
  number: integer
  value: number
end

-- What this module reads of `paw`, which paw/init.lua makes.
local record Moved
  offset: number
  loop_start: number
  shift: number
end
local record Stretch
  carry: function(c: types.Clip, snap: objects.ClipSnapshot, by: number): Moved
  moved: function(c: types.Clip, by: number): Moved
  file_seconds: function(c: types.Clip, beats: number, at?: number): number
end

--- `paw.pick` (paw/pick.tl), the part of it that this module calls: opening
--- a picker.
local record Pick
  metamethod __call: function<T>(self: Pick, spec: contracts.PickSource<T>)
end

local record Paw is partial.Paw
  keymap: KeymapModule
  pick: Pick
  lanes: LanesModule
  stretch: Stretch
  edit: EditModule
  cursor: CursorModule
  add_track: function(opts?: objects.TrackInput): objects.Track
  restore_clip: function(snap: objects.ClipSnapshot, track: integer | objects.Track): objects.Clip
end
local paw = (_G as {string: Paw}).paw

local type Context = commands.Context
local type Result = commands.Result

local record M
  type Take = Take
  type Takes = Takes
  type Content = Content
  type ClipRef = ClipRef
end

local EPS = 1e-9

local function copy<T>(t: T): T
  local out: {string: Value} = {}
  for k, v in pairs(t as {string: Value}) do
    out[k] = v
  end
  return out as T
end

local function clip_of(clip: ClipRef): types.Clip
  if clip is types.Clip then
    return clip
  end
  return api.clip_get(clip)
end

--- The takes of a clip: { active, list = { { name }, ... } }, or nil for a
--- clip that has only what it plays.
function M.of(clip: ClipRef): Takes
  local c = clip_of(clip)
  local takes = type(c.meta) == "table" and c.meta.takes as Takes
  if type(takes) ~= "table" or type(takes.list) ~= "table" or #takes.list < 2 then
    return nil
  end
  return takes
end

--- How many takes a clip has (1 without any others), and which plays.
function M.count(clip: ClipRef): integer, integer
  local takes = M.of(clip)
  if not takes then
    return 1, 1
  end
  return #takes.list, takes.active
end

local function write(id: integer, c: types.Clip, takes: Takes)
  local meta = copy(type(c.meta) == "table" and c.meta or {})
  meta.takes = takes
  api.clip_set(id, {meta = meta})
end

--- What the clip plays now, as an entry of the list.
local function current(id: integer, c: types.Clip, name: string): Take
  if c.kind == "audio" then
    return {name = name, file = c.file, offset = c.offset, gain = c.gain}
  end
  return {
    name = name,
    notes = api.clip_notes(id),
    controls = c.control_count > 0 and api.clip_controls(id) or nil,
  }
end

--- Make an entry what the clip plays. `shift` is how far the clip's offset
--- has moved since the entry's own was written.
local function play(id: integer, c: types.Clip, entry: Take, shift: number)
  if c.kind == "audio" then
    if entry.file ~= c.file then
      api.clip_set(id, {file = entry.file})
    end
    api.clip_set(id, {offset = math.max(0, (entry.offset or 0) + shift)})
    api.clip_set(id, {gain = entry.gain or 0})
  else
    api.clip_set_notes(id, entry.notes or {})
    api.clip_set_controls(id, entry.controls or {})
  end
end

--- True if the name of a clip comes from its takes: the name of the take
--- that plays, or of the recording ("take 1" for "take 1.2").
function M.named_by_take(c: types.Clip, takes?: Takes): boolean
  takes = takes or M.of(c)
  local name = takes and takes.list[takes.active] and takes.list[takes.active].name
  if not name then
    return false
  end
  return c.name == name or c.name == (name:gsub("%.%d+$", "")) or c.name == (name:gsub(" %d+$", ""))
end

--- Play take `index` of a clip. One undo step. Returns the take's name.
function M.select(id: integer, index: integer): string
  local c = api.clip_get(id)
  local takes = M.of(c)
  if not takes then
    error("the clip has no other takes", 2)
  end
  index = math.floor(index)
  if not takes.list[index] then
    error("the clip has " .. #takes.list .. " takes", 2)
  end
  if index == takes.active then
    return takes.list[index].name
  end
  local list: {Take} = {}
  -- How far the clip has been trimmed or slipped since the offsets were written.
  local shift = c.kind == "audio" and (c.offset - (takes.origin or c.offset)) or 0
  for i, entry in ipairs(takes.list) do
    if i == takes.active then
      list[i] = current(id, c, entry.name)
    elseif i == index then
      list[i] = {name = entry.name}
    else
      list[i] = copy(entry)
      if c.kind == "audio" then
        list[i].offset = (entry.offset or 0) + shift
      end
    end
  end
  play(id, c, takes.list[index], shift)
  -- A clip named after its recording ("take 1", its takes "take 1.1" and
  -- "take 1.2") or after the take it played is named after the take it
  -- plays now: a piece of a comp says which take it is. A name of the
  -- user's own stays.
  if takes.list[index].name and M.named_by_take(c, takes) then
    api.clip_set(id, {name = takes.list[index].name})
  end
  local origin = c.kind == "audio" and api.clip_get(id).offset or nil
  write(id, c, {active = index, origin = origin, list = list})
  return takes.list[index].name
end

--- Step through a clip's takes, round and round.
function M.step(id: integer, by: integer): string
  local n, active = M.count(id)
  if n < 2 then
    return nil
  end
  return M.select(id, (active - 1 + by) % n + 1)
end

--- Keep the sound of the clip as a take, and continue in a copy of it. The
--- copy becomes the take that plays. Use it to try a variation. Returns its number.
function M.new(id: integer, name?: string): integer
  local c = api.clip_get(id)
  local takes = M.of(c)
  local list: {Take} = {}
  local shift = takes and c.kind == "audio" and (c.offset - (takes.origin or c.offset)) or 0
  if takes then
    for i, entry in ipairs(takes.list) do
      if i == takes.active then
        list[i] = current(id, c, entry.name)
      else
        list[i] = copy(entry)
        if c.kind == "audio" then
          list[i].offset = (entry.offset or 0) + shift
        end
      end
    end
  else
    list[1] = current(id, c, c.name .. " 1")
  end
  list[#list + 1] = {name = name or (c.name .. " " .. (#list + 1))}
  write(id, c, {active = #list, origin = c.kind == "audio" and c.offset or nil, list = list})
  return #list
end

--- Discard a take: by default the take that plays. Then the take before it
--- plays. With one take left, the clip becomes a clip without takes again.
function M.remove(id: integer, index?: integer)
  local c = api.clip_get(id)
  local takes = M.of(c)
  if not takes then
    error("the clip has no other takes", 2)
  end
  index = index or takes.active
  if not takes.list[index] then
    error("the clip has " .. #takes.list .. " takes", 2)
  end
  if index == takes.active then
    M.select(id, index > 1 and index - 1 or 2)
    c = api.clip_get(id)
    takes = M.of(c)
  end
  local list, active: {Take}, integer = {}, takes.active
  for i, entry in ipairs(takes.list) do
    if i ~= index then
      list[#list + 1] = entry
    end
  end
  if index < active then
    active = active - 1
  end
  write(id, c, #list > 1 and {active = active, origin = takes.origin, list = list} or nil)
end

--- Throw away every take but the one that plays.
function M.keep(id: integer)
  local c = api.clip_get(id)
  if M.of(c) then
    write(id, c, nil)
  end
end

--- Each take as a separate clip, on new tracks below the track of the clip,
--- one take on each track. The clip keeps the take that plays. Returns the tracks.
function M.explode(id: integer): {contracts.TrackHandle}
  local c = api.clip_get(id)
  local takes = M.of(c)
  if not takes then
    error("the clip has no other takes", 2)
  end
  local track = api.track_get(c.track)
  local shift = c.kind == "audio" and (c.offset - (takes.origin or c.offset)) or 0
  local out, at: {contracts.TrackHandle}, integer = {}, track.index
  for i, entry in ipairs(takes.list) do
    if i ~= takes.active then
      at = at + 1
      local t = paw.add_track({name = entry.name or (track.name .. " take " .. i), index = at})
      local snap: objects.ClipSnapshot = {
        name = entry.name or c.name, start = c.start, length = c.length, kind = c.kind
      }
      -- Each plays as the clip does: stretched, shifted, looped.
      paw.stretch.carry(c, snap, 0)
      if c.kind == "audio" then
        snap.file, snap.offset, snap.gain = entry.file, math.max(0, (entry.offset or 0) + shift), entry.gain or 0
        snap.fade_in, snap.fade_out = c.fade_in, c.fade_out
      else
        snap.notes, snap.controls = entry.notes or {}, entry.controls
      end
      paw.restore_clip(snap, t)
      out[#out + 1] = t
    end
  end
  write(id, c, nil)
  return out
end

--- The takes of a piece of a clip, from beat `from` to `to` of the
--- timeline: what a cut gives to each side. Sound keeps its entries as they
--- are (the offset of the piece tells where it is in them). Notes are those
--- of the range, counted from the start of the piece. Nil for a clip
--- without takes. All notes of a looped clip go with each piece, moved by
--- `shift` as the notes of the piece are (see `paw.stretch.moved`).
function M.piece(c: types.Clip, from: number, to: number, shift?: number): Takes
  local takes = M.of(c)
  if not takes then
    return nil
  end
  if c.kind == "audio" then
    return takes
  end
  local a, b = from - c.start, to - c.start
  if shift then
    a, b = -shift, math.huge
  end
  local list: {Take} = {}
  for i, entry in ipairs(takes.list) do
    local e = copy(entry)
    if entry.notes then
      e.notes = {}
      for _, n in ipairs(entry.notes) do
        if shift then
          local note = copy(n)
          note.start = n.start + shift
          e.notes[#e.notes + 1] = note
        elseif n.start >= a - EPS and n.start < b - EPS then
          local note = copy(n)
          note.start, note.length = n.start - a, math.min(n.length, b - n.start)
          e.notes[#e.notes + 1] = note
        end
      end
    end
    if entry.controls then
      e.controls = {}
      for _, move in ipairs(entry.controls) do
        if shift or (move.start >= a - EPS and move.start < b - EPS) then
          local m = copy(move)
          m.start = move.start - a
          e.controls[#e.controls + 1] = m
        end
      end
    end
    list[i] = e
  end
  return {active = takes.active, list = list}
end

--- Move the notes of a clip's other takes by `by` beats, as its own are
--- moved when its start is trimmed or its content slipped.
function M.shift(id: integer, by: number)
  local c = api.clip_get(id)
  local takes = M.of(c)
  if not takes or c.kind ~= "midi" then
    return
  end
  local list: {Take} = {}
  for i, entry in ipairs(takes.list) do
    local e = copy(entry)
    if entry.notes then
      e.notes = {}
      for j, n in ipairs(entry.notes) do
        e.notes[j] = copy(n)
        e.notes[j].start = n.start + by
      end
    end
    if entry.controls then
      e.controls = {}
      for j, move in ipairs(entry.controls) do
        e.controls[j] = copy(move)
        e.controls[j].start = move.start + by
      end
    end
    list[i] = e
  end
  write(id, c, {active = takes.active, list = list})
end

--- A clip's takes in a few characters, for its label: "2/4", or nil.
function M.badge(c: types.Clip): string
  local takes = M.of(c)
  return takes and (takes.active .. "/" .. #takes.list) or nil
end

--- What take `index` of a clip plays, as the clip would have it if that
--- take were selected. For sound, it is `{ file, offset, gain }`, with the
--- offset of the start of the clip in the file. For notes, it is
--- `{ notes, controls }`, counted from the start of the clip. The take that
--- plays is the content of the clip.
function M.content(clip: ClipRef, index: integer): Content
  local c = clip_of(clip)
  local takes = M.of(c)
  local entry = takes and index ~= takes.active and takes.list[index]
  if not entry then
    if c.kind == "audio" then
      return {file = c.file, offset = c.offset, gain = c.gain}
    end
    return {notes = api.clip_notes(c.id), controls = c.control_count > 0 and api.clip_controls(c.id) or {}}
  end
  if c.kind == "audio" then
    local shift = c.offset - (takes.origin or c.offset)
    return {file = entry.file, offset = math.max(0, (entry.offset or 0) + shift), gain = entry.gain or 0}
  end
  return {notes = entry.notes or {}, controls = entry.controls or {}}
end

--- The waveform of take `index` of an audio clip, as `n` `{ min, max, rms }`
--- across the clip, as `paw.api.clip_peaks` gives the clip's. The take that
--- plays is the clip's own waveform, stretched. Another take is its file,
--- stretched in time as the clip stretches it, and repeated as a looped
--- clip repeats. Nothing for a missing file.
function M.peaks(clip: ClipRef, index: integer, n: integer): {types.Peak}
  local c = clip_of(clip)
  local takes = M.of(c)
  if not takes or index == takes.active then
    local ok, peaks = pcall(api.clip_peaks, c.id, n)
    return ok and peaks as {types.Peak} or {}
  end
  local content = M.content(c, index)
  local seconds = paw.stretch.file_seconds(c, c.length)
  local peaks: {types.Peak}
  if c.loop and c.loop_length then
    -- One repeat's worth, laid along the clip as it repeats.
    local period = paw.stretch.file_seconds(c, c.loop_length)
    local lead = c.loop_start / c.loop_length * period
    local per = math.max(1, math.min(4096, math.ceil(n * period / seconds)))
    local ok, one = pcall(api.media_peaks, content.file, math.max(0, content.offset + lead), period, per)
    local repeat_peaks = one as {types.Peak}
    if not ok or #repeat_peaks == 0 then
      return {}
    end
    peaks = {}
    for i = 1, n do
      local at = (i - 0.5) * seconds / n
      local phase = ((at - lead) % period) / period
      peaks[i] = repeat_peaks[math.min(#repeat_peaks, math.floor(phase * #repeat_peaks) + 1)]
    end
  else
    local ok, all = pcall(api.media_peaks, content.file, content.offset, seconds, n)
    if not ok then
      return {}
    end
    peaks = all as {types.Peak}
  end
  -- The take's own gain, as the clip would play it.
  local gain = 10 ^ ((content.gain or 0) / 20)
  local out: {types.Peak} = {}
  for i, p in ipairs(peaks) do
    out[i] = {p[1] * gain, p[2] * gain, p[3] * gain}
  end
  return out
end

-- Comping --------------------------------------------------------------------------

--- Whether every note of a list lies within a clip `length` beats long:
--- notes hidden past either edge would show if the clip were joined to another.
local function within(notes: {types.Note}, length: number): boolean
  for _, n in ipairs(notes or {}) do
    if n.start < -EPS or n.start >= length - EPS then
      return false
    end
  end
  return true
end

--- Whether two lists of notes or controller moves are the same, the first
--- moved by `by` beats.
local function same_moved(xs: {Item}, ys: {Item}, by: number): boolean
  local x, y = xs or {}, ys or {}
  if #x ~= #y then
    return false
  end
  local function key(item: Item, shift: number): string
    return string.format(
      "%.6f|%s|%s|%s|%s|%s",
      item.start + shift,
      tostring(item.pitch),
      tostring(item.length),
      tostring(item.velocity),
      tostring(item.type or item.number),
      tostring(item.value)
    )
  end
  local a, b: {string}, {string} = {}, {}
  for i, item in ipairs(x) do
    a[i] = key(item, by)
  end
  for i, item in ipairs(y) do
    b[i] = key(item, 0)
  end
  table.sort(a)
  table.sort(b)
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

--- Whether looped clip `b` carries on `a`'s repeats where `a` ends: the
--- same loop, turned on as far as `a` is long (see `paw.stretch.moved`),
--- and for notes the same notes, every take's too.
local function loop_continues(a: types.Clip, b: types.Clip, ta: Takes, tb: Takes): boolean
  if not (a.loop and b.loop) or math.abs(a.loop_length - b.loop_length) > 1e-9 then
    return false
  end
  local m = paw.stretch.moved(a, a.length)
  if math.abs(m.loop_start - b.loop_start) > 1e-6 then
    return false
  end
  if a.kind == "audio" then
    for i = 1, #ta.list do
      local x, y = M.content(a, i), M.content(b, i)
      if x.file ~= y.file or math.abs((x.gain or 0) - (y.gain or 0)) > 1e-9 then
        return false
      end
    end
    return math.abs(m.offset - b.offset) < 1e-6
  end
  if not same_moved(api.clip_notes(a.id) as {Item}, api.clip_notes(b.id) as {Item}, m.shift) then
    return false
  end
  if
    (a.control_count > 0 or b.control_count > 0)
    and not same_moved(api.clip_controls(a.id) as {Item}, api.clip_controls(b.id) as {Item}, m.shift)
  then
    return false
  end
  for i = 1, #ta.list do
    if i ~= ta.active then
      if not same_moved(ta.list[i].notes as {Item}, tb.list[i].notes as {Item}, m.shift) then
        return false
      end
      if not same_moved(ta.list[i].controls as {Item}, tb.list[i].controls as {Item}, m.shift) then
        return false
      end
    end
  end
  return true
end

--- Whether clip `b` carries straight on from clip `a`: side by side on the
--- track, alike in kind, name and mute, playing the same take of the same
--- list, stretched, shifted and looped alike, and for sound every take
--- lined up across the join (the same file, gain and place in it), so that
--- one clip in their place plays just what the two did. Looped clips join
--- where the second carries on the first's repeats.
local function continues(a: types.Clip, b: types.Clip): boolean
  if math.abs(a.start + a.length - b.start) > 1e-6 or a.kind ~= b.kind then
    return false
  end
  local ta, tb = M.of(a), M.of(b)
  -- Names that only say the take (pieces of a comp) do not keep them apart.
  local same_name = a.name == b.name or (ta and tb and M.named_by_take(a, ta) and M.named_by_take(b, tb))
  if not same_name or (a.muted or false) ~= (b.muted or false) then
    return false
  end
  if not (ta and tb) or ta.active ~= tb.active or #ta.list ~= #tb.list then
    return false
  end
  for i = 1, #ta.list do
    if ta.list[i].name ~= tb.list[i].name then
      return false
    end
  end
  if
    a.stretch ~= b.stretch
    or a.pitch ~= b.pitch
    or a.stretch_mode ~= b.stretch_mode
    or a.source_tempo ~= b.source_tempo
    or a.timebase ~= b.timebase
    or a.loop ~= b.loop
    or a.loop_length ~= b.loop_length
    or a.formants ~= b.formants
  then
    return false
  end
  -- Warp markers alike, the same moments of the file in the same places.
  local wa, wb = a.warp or {}, b.warp or {}
  if #wa ~= #wb then
    return false
  end
  for i = 1, #wa do
    if wa[i].source ~= wb[i].source or wa[i].target ~= wb[i].target then
      return false
    end
  end
  if a.loop then
    if a.kind == "audio" and ((a.fade_out or 0) > EPS or (b.fade_in or 0) > EPS) then
      return false
    end
    return loop_continues(a, b, ta, tb)
  end
  if a.kind == "midi" then
    if not (within(api.clip_notes(a.id), a.length) and within(api.clip_notes(b.id), b.length)) then
      return false
    end
    for i = 1, #ta.list do
      if not (within(ta.list[i].notes, a.length) and within(tb.list[i].notes, b.length)) then
        return false
      end
    end
    return true
  end
  if (a.fade_out or 0) > EPS or (b.fade_in or 0) > EPS then
    return false
  end
  local seconds = paw.stretch.file_seconds(a, a.length)
  for i = 1, #ta.list do
    local x, y = M.content(a, i), M.content(b, i)
    if x.file ~= y.file or math.abs((x.gain or 0) - (y.gain or 0)) > 1e-9 then
      return false
    end
    if math.abs(x.offset + seconds - y.offset) > 1e-6 then
      return false
    end
  end
  return true
end

--- What `shifted` moves: a note or a controller move.
local interface Moving
  start: number
end

local function shifted<T>(list: {T}, by: number): {T}
  local out: {T} = {}
  for i, item in ipairs(list or {}) do
    out[i] = copy(item)
    (out[i] as Moving).start = (item as Moving).start + by
  end
  return out
end

local function append<T>(into: {T}, more: {T}): {T}
  for _, item in ipairs(more) do
    into[#into + 1] = item
  end
  return into
end

--- Make clip `b` part of clip `a`, which `continues` has found it carries on.
--- A looped clip already holds what the other repeats.
local function join(a: types.Clip, b: types.Clip)
  if a.loop then
    if a.kind == "audio" then
      api.clip_set(a.id, {fade_out = b.fade_out or 0})
    end
  elseif a.kind == "midi" then
    local ta, tb = M.of(a), M.of(b)
    api.clip_set_notes(a.id, append(api.clip_notes(a.id), shifted(api.clip_notes(b.id), a.length)))
    if a.control_count > 0 or b.control_count > 0 then
      local mine = a.control_count > 0 and api.clip_controls(a.id) or {}
      local theirs = b.control_count > 0 and api.clip_controls(b.id) or {}
      api.clip_set_controls(a.id, append(mine, shifted(theirs, a.length)))
    end
    local list: {Take} = {}
    for i, entry in ipairs(ta.list) do
      local e = copy(entry)
      if i ~= ta.active then
        e.notes = append(shifted(entry.notes, 0), shifted(tb.list[i].notes, a.length))
        if entry.controls or tb.list[i].controls then
          e.controls = append(shifted(entry.controls, 0), shifted(tb.list[i].controls, a.length))
        end
      end
      list[i] = e
    end
    write(a.id, a, {active = ta.active, list = list})
  else
    api.clip_set(a.id, {fade_out = b.fade_out or 0})
  end
  api.clip_set(a.id, {length = a.length + b.length})
  api.clip_remove(b.id)
end

--- Join the pieces of a track that continue exactly from one another (see
--- `continues`). This applies to the pieces from beat `from` to `to`, with
--- the pieces that touch each end. Returns the number of joins.
function M.join_pieces(track: integer, from: number, to: number): integer
  local joins = 0
  local again = true
  while again do
    again = false
    local list = api.clip_list(track)
    table.sort(list, function(x: types.Clip, y: types.Clip): boolean return x.start < y.start end)
    for i = 1, #list - 1 do
      local a, b = list[i], list[i + 1]
      if a.start + a.length >= from - 1e-6 and b.start <= to + 1e-6 and continues(a, b) then
        join(a, b)
        joins, again = joins + 1, true
        break
      end
    end
  end
  return joins
end

-- The pieces of a comp say the take they play, not the recording.
local function name_pieces(track: integer)
  for _, c in ipairs(api.clip_list(track)) do
    local takes = M.of(c)
    local name = takes and takes.list[takes.active].name
    if name and c.name ~= name and M.named_by_take(c, takes) then
      api.clip_set(c.id, {name = name})
    end
  end
end

--- Make take `take` play on a track from beat `from` to `to`. paw cuts
--- each clip there with that number of takes at the two ends where it goes
--- across them. paw selects take `take` for each piece between them. Then
--- it joins again the adjacent pieces that play the same take, where that
--- is exact (`M.join_pieces`). Clips without takes do not change. Returns
--- the number of pieces that got the take, or 0 when no clip there has it.
--- A piece named after its recording or its take is named after the take
--- that it plays.
function M.comp(track: integer, take: integer, from: number, to: number): integer
  take = math.floor(take)
  from, to = math.max(0, math.min(from, to)), math.max(from, to)
  local function has(c: types.Clip): boolean
    local n = M.count(c)
    return n > 1 and take >= 1 and take <= n
  end
  local function cut(at: number)
    local only: {integer: boolean} = {}
    for _, c in ipairs(api.clip_list(track)) do
      if has(c) then
        only[c.id] = true
      end
    end
    paw.edit.arrange.clear(track, at, at, only)
  end
  local some = false
  for _, c in ipairs(api.clip_list(track)) do
    some = some or (has(c) and c.start < to - EPS and c.start + c.length > from + EPS)
  end
  if not some then
    return 0
  end
  cut(from)
  cut(to)
  local n = 0
  for _, c in ipairs(api.clip_list(track)) do
    if c.start >= from - EPS and c.start + c.length <= to + EPS and has(c) then
      M.select(c.id, take)
      n = n + 1
    end
  end
  name_pieces(track)
  M.join_pieces(track, from, to)
  return n
end

--- The clip of a track at `beat` that has a take `take`, or nil.
local function piece_at(track: integer, take: integer, beat: number): types.Clip
  for _, c in ipairs(api.clip_list(track)) do
    local n = M.count(c)
    if beat >= c.start - EPS and beat < c.start + c.length - EPS and n > 1 and take <= n then
      return c
    end
  end
end

--- Make take `take` play in the piece of a track at `beat`, and join it to
--- the pieces next to it where that is exact. Returns the clip, or nil if
--- no piece there has such a take.
function M.choose_at(track: integer, take: number, beat: number): types.Clip
  local c = piece_at(track, math.floor(take), beat)
  if not c then
    return nil
  end
  M.select(c.id, math.floor(take))
  name_pieces(track)
  M.join_pieces(track, c.start, c.start + c.length)
  return c
end

-- Recording over clips --------------------------------------------------------------

--- Give clip `c` more takes, `sounds` (sound as `Take` entries, each from
--- the clip's start), and play the take `playing` of them. What the clip
--- plays now stays as a take. A clip named after its recording or its take
--- is named after the take that it plays.
local function add_sounds(c: types.Clip, sounds: {Take}, playing: integer)
  local takes = M.of(c)
  local renamed = takes and M.named_by_take(c, takes) or (not takes and c.name:match("^take %d+$") ~= nil)
  local list: {Take} = {}
  if takes then
    local shift = c.offset - (takes.origin or c.offset)
    for i, entry in ipairs(takes.list) do
      if i == takes.active then
        list[i] = current(c.id, c, entry.name)
      else
        list[i] = copy(entry)
        list[i].offset = (entry.offset or 0) + shift
      end
    end
  else
    list[1] = current(c.id, c, c.name)
  end
  local first = #list
  for i, sound in ipairs(sounds) do
    list[first + i] = copy(sound)
  end
  local active = first + playing
  play(c.id, c, list[active], 0)
  list[active] = {name = list[active].name}
  write(c.id, c, {active = active, origin = api.clip_get(c.id).offset, list = list})
  if renamed and list[active].name then
    api.clip_set(c.id, {name = list[active].name})
  end
end

--- Make a new audio recording, clip `id`, the newest take of the audio
--- clips under it on its track, instead of a clip on top of them. paw cuts
--- those clips where the recording starts and ends. Each piece gets all the
--- takes of the recording, lined up, and plays the take that the recording
--- plays. What the piece played before stays as a take. The part of the
--- recording where no clip was stays a clip. Returns the number of clips
--- that got takes.
function M.record_over(id: integer): integer
  local r = api.clip_get(id)
  if r.kind ~= "audio" then
    return 0
  end
  local track, from, to = r.track, r.start, r.start + r.length
  local function under(): {integer: boolean}, boolean
    local set: {integer: boolean} = {}
    local any = false
    for _, c in ipairs(api.clip_list(track, from, to)) do
      if c.id ~= id and c.kind == "audio" and c.start < to - EPS and c.start + c.length > from + EPS then
        set[c.id], any = true, true
      end
    end
    return set, any
  end
  local set, any = under()
  if not any then
    return 0
  end
  -- Each take of the recording, from its start.
  local takes = M.of(r)
  local n, playing = M.count(r)
  local sounds: {Take} = {}
  for i = 1, n do
    local content = M.content(r, i)
    sounds[i] = {
      name = takes and takes.list[i].name or r.name,
      file = content.file,
      offset = content.offset,
      gain = content.gain,
    }
  end
  paw.edit.arrange.clear(track, from, from, set)
  set = under()
  paw.edit.arrange.clear(track, to, to, set)
  local covered: {{number}} = {}
  for _, c in ipairs(api.clip_list(track, from, to)) do
    if c.id ~= id and c.kind == "audio" and c.start >= from - EPS and c.start + c.length <= to + EPS then
      local by = paw.stretch.file_seconds(r, c.start - from)
      local lined: {Take} = {}
      for i, sound in ipairs(sounds) do
        lined[i] = copy(sound)
        lined[i].offset = sound.offset + by
      end
      add_sounds(c, lined, playing)
      covered[#covered + 1] = {c.start, c.start + c.length}
    end
  end
  -- The recording keeps only what lies where no clip was: from the last
  -- stretch back, so that what is left of it before keeps its id.
  table.sort(covered, function(a: {number}, b: {number}): boolean return a[1] > b[1] end)
  for _, span in ipairs(covered) do
    paw.edit.arrange.clear(track, span[1], span[2], {[id] = true})
  end
  return #covered
end

-- Take lanes -----------------------------------------------------------------------

local lanes_open: {integer: boolean} = {}
do
  local saved = api.state_get("take_lanes_open")
  if type(saved) == "table" then
    for key, on in pairs(saved as {string: boolean}) do
      local id = tonumber(key)
      if on and id then
        lanes_open[id as integer] = true
      end
    end
  end
end

local function save_lanes()
  local out: {string: boolean} = {}
  for id, on in pairs(lanes_open) do
    if on then
      out[tostring(id)] = true
    end
  end
  api.state_set("take_lanes_open", out)
  api.ui_redraw()
  -- A graphical frontend draws them too.
  events.emit(paw.lanes.changed, {})
end

local function id_of(track: TrackRef): integer
  if track is contracts.TrackHandle then
    return track.id
  end
  return track
end

--- True if a track shows its take lanes.
function M.lanes_shown(track: TrackRef): boolean
  return lanes_open[id_of(track)] == true
end

--- Show a track's take lanes, or hide them (`on` false).
function M.show_lanes(track: TrackRef, on?: boolean)
  lanes_open[id_of(track)] = on ~= false or nil
  save_lanes()
end

--- Show the take lanes of a track, or hide them. Returns true if they show.
function M.toggle_lanes(track: TrackRef): boolean
  M.show_lanes(track, not M.lanes_shown(track))
  return M.lanes_shown(track)
end

--- The number of take lanes that a track shows: the highest number of takes
--- of its clips. None while they are hidden or when no clip has takes.
function M.lane_count(track: TrackRef): integer
  local id = id_of(track)
  if not lanes_open[id] then
    return 0
  end
  local most = 0
  local ok, clips = pcall(api.clip_list, id)
  for _, c in ipairs(ok and clips or {}) do
    local n = M.count(c)
    if n > 1 then
      most = math.max(most, n)
    end
  end
  return most
end

-- A track that goes away takes its take lanes with it.
events.on(
  kernel.track_removed,
  function(event: kernel.TrackId)
    if lanes_open[event.id] then
      lanes_open[event.id] = nil
      save_lanes()
    end
  end
)

-- Commands -----------------------------------------------------------------------

local function need_clip(): objects.Clip
  local clip = paw.cursor.clip()
  if not clip then
    paw.notify("no clip under the cursor", "warn")
    return nil
  end
  if not M.of(clip.id) then
    paw.notify("the clip has no other takes: record with the loop on, or `:take.new`", "warn")
    return nil
  end
  return clip
end

local function said(id: integer)
  local n, active = M.count(id)
  local takes = M.of(id)
  paw.notify(string.format("take %d of %d: %s", active, n, takes and takes.list[active].name or ""))
end

--- The cursor's track and the stretch of time selected on it, or nil when
--- no stretch is selected.
local function selected_stretch(): integer, number, number
  local sel = paw.keymap.selection()
  local track = paw.cursor.track_id()
  if not (sel and sel.kind ~= "line" and sel.c0 and sel.c1 and sel.c1 > sel.c0 and track) then
    return nil
  end
  return track, sel.c0, sel.c1
end

--- A take in the list of `:take.list`.
local record Choice
  text: string
  index: integer
end

commands.define(
  "take",
  function(ctx: Context): Result
    local word = ctx.args[1] as string
    local track, from, to: integer, number, number
    if word then
      track, from, to = selected_stretch()
    end
    -- Comping: this take over the selected stretch, whatever plays around it.
    if track and tonumber(word) and M.comp(track, tonumber(word) as integer, from, to) > 0 then
      paw.keymap.set_mode("n")
      return paw.notify("take " .. word .. " over the selection")
    end
    local clip = need_clip()
    if not clip then
      return
    end
    if word == "next" or not word then
      M.step(clip.id, ctx.count or 1)
    elseif word == "prev" then
      M.step(clip.id, -(ctx.count or 1))
    else
      local index = tonumber(word) as integer
      if not index then
        for i, entry in ipairs(M.of(clip.id).list) do
          if entry.name == table.concat(ctx.args as {string}, " ") then
            index = i
          end
        end
      end
      if not index then
        return paw.notify("take: a number, `next` or `prev`", "warn")
      end
      M.select(clip.id, index)
    end
    said(clip.id)
  end,
  {desc = "Play another take of the clip: `take 2`, `take next`, `take prev`; over a selected stretch, only there"}
)

commands.define(
  "take.list",
  function(): Result
    local clip = need_clip()
    if not clip then
      return
    end
    local takes = M.of(clip.id)
    local items: {Choice} = {}
    for i, entry in ipairs(takes.list) do
      items[i] = {text = string.format("%s %d  %s", i == takes.active and "●" or " ", i, entry.name or ""), index = i}
    end
    paw.pick(
      {
        title = "Takes",
        items = items,
        on_choose = function(item: Choice) M.select(clip.id, item.index); said(clip.id) end,
      }
    )
  end,
  {desc = "Choose the take that plays from a list"}
)

commands.define(
  "take.new",
  function(ctx: Context): Result
    local clip = paw.cursor.clip()
    if not clip then
      return paw.notify("no clip under the cursor", "warn")
    end
    local n = M.new(clip.id, ctx.args[1] and table.concat(ctx.args as {string}, " "))
    paw.notify("take " .. n .. ": a copy to change, with what was there kept as take " .. (n - 1))
  end,
  {desc = "Keep what the clip plays as a take and carry on in a copy"}
)

commands.define(
  "take.remove",
  function(ctx: Context): Result
    local clip = need_clip()
    if not clip then
      return
    end
    M.remove(clip.id, tonumber(ctx.args[1]) as integer)
    if M.of(clip.id) then
      said(clip.id)
    else
      paw.notify("one take left: the clip is a clip again")
    end
  end,
  {desc = "Throw away the playing take, or the one numbered: `take.remove 1`"}
)

commands.define(
  "take.keep",
  function(): Result
    local clip = need_clip()
    if not clip then
      return
    end
    M.keep(clip.id)
    paw.notify("kept the playing take alone")
  end,
  {desc = "Throw away every take but the one that plays"}
)

commands.define(
  "take.lanes",
  function(ctx: Context): Result
    local track = paw.cursor.track_id()
    if not track then
      return paw.notify("no track selected", "warn")
    end
    local word = ctx.args[1]
    local on: boolean
    if word == "on" or word == "off" then
      M.show_lanes(track, word == "on")
      on = word == "on"
    else
      on = M.toggle_lanes(track)
    end
    if not on then
      return paw.notify("take lanes hidden")
    end
    local n = M.lane_count(track)
    if n == 0 then
      return paw.notify("take lanes shown: no clip of this track has takes yet")
    end
    paw.notify(
      n .. " take lanes: a drag across one in the window makes that take play there; `:take 2` over a selection here"
    )
  end,
  {desc = "Show the track's takes as lanes under its clips, or hide them: `take.lanes`, `take.lanes on`"}
)

commands.define(
  "take.explode",
  function(): Result
    local clip = need_clip()
    if not clip then
      return
    end
    local tracks = M.explode(clip.id)
    paw.notify(#tracks .. " takes are clips on tracks of their own now")
  end,
  {desc = "Put every other take on a track of its own"}
)

return M
