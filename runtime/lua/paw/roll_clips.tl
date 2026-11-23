-- `paw.roll_clips`: the clips the piano roll edits, and the notes it shows
-- around them.
--
-- The roll edits one clip, the *active* one, where new notes go. Others can
-- be edited with it (REAPER's "editability follows selection"): selections,
-- operators, motions, yank and paste work on the notes of all of them, and a
-- note that moves stays in its own clip. Behind them the roll shows the
-- notes of other tracks that sound at the same time, faintly and in their
-- tracks' colours: the *context*, so the harmony can be seen where it is
-- written.
--
-- Beats here are the roll's: from the start of the active clip. A note at
-- its own clip's beat `b` is at `b + offset` in the roll, `offset` being how
-- far its clip starts after the active one.
--
-- Pitches here are the roll's too: those that the notes play at. A clip
-- with a transpose (`:clip.override`) shows each note that much higher than
-- it is stored, and a pitch written in the roll is stored that much lower:
-- each part's `clip` is a handle that does this (`Clip:shifted`).
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local context = require("paw.roll_context")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type objects = require("paw.objects")
local type DrawModule = require("paw.draw")
local type HarmonyModule = require("paw.harmony")
local type ScopeModule = require("paw.scope")
local type UiModule = require("paw.ui")

local EPS = 1e-9

-- Which tracks' notes the roll shows behind its own: "all" pitched tracks,
-- those of the active clip's "group", "none", or a list of track ids. Drum
-- tracks (those with a drum map) are left out of "all" and "group".
options.define("roll_context", "all", {type = {"string", "table"}, values = {"all", "group", "none"}})
-- At most this many context notes, so that a dense song stays quick to draw.
options.define("roll_context_max", 4000)

--- The state of a window of the piano roll that this module reads and
--- keeps: the active clip, the cursor's beat and the scroll (both in the
--- roll's beats), the ids of the clips edited with the active one, and
--- the toggles over `roll_context` (track id -> shown or not). The roll
--- (paw/views/pianoroll.tl) is one; `edit` opens a clip in it alone.
local interface Window
  clip_id: integer
  beat: number
  scroll: number
  edited: {integer}
  context_shown: {integer: boolean}
  edit: function(self: Window, clip: objects.Clip)
end

--- An editable clip: its id, a handle whose pitches are those that the
--- clip plays (`Clip:shifted`), where it starts in the roll's beats
--- (`offset`) and in the song's, and its length, track and name. A
--- module that keeps more of a part has a record of its own that is one.
local interface Portion
  id: integer
  clip: objects.Clip
  offset: number
  start: number
  length: number
  track: integer
  name: string
end

--- A note of an editable clip in the roll's beats: the note, its clip's id
--- (`clip`), its place among that clip's notes (`place`, for `edit_notes`)
--- and its clip's `offset`.
local record Note
  start: number
  length: number
  pitch: integer
  velocity: integer
  id: integer
  meta: types.Meta
  attr: types.NoteAttr
  clip: integer
  place: integer
  offset: number
end

--- Which notes `notes` gives: as `Clip:notes` takes them, in the roll's beats.
local record Range
  from: number
  to: number
  low: integer
  high: integer
end

--- A row of the list of `:roll.tracks` (`rows`): a track (`kind` "track",
--- `on` its notes show) or one of its MIDI clips (`kind` "clip", `on` it is
--- editable). `active` marks the active clip and its track.
local record Row
  kind: string
  id: integer
  name: string
  color: string
  track: integer
  on: boolean
  active: boolean
end

--- The payload of `roll_clips.changed`: the active clip and how many
--- clips are edited.
local record Changed
  active: integer
  count: integer
end

-- What this module reads of `paw`, which paw/init.lua makes. paw/pick.tl
-- and paw/frontend.tl name this module's types (through the modules they
-- require): this module declares only what it calls of them.
local record Frontend
  refresh: function()
end
local record Paw is partial.Paw
  ui: UiModule
  draw: DrawModule
  clip: function(id: integer): objects.Clip
  frontend: Frontend
  pick: function(spec: contracts.PickSource<Row>)
end
local paw = (_G as {string: Paw}).paw

local record M
  type Window = Window
  type Portion = Portion
  type Note = Note
  type Range = Range
  type Row = Row
  type Changed = Changed
  --- A track near the roll (`tracks`), as paw/roll_context.tl gives it.
  type Track = context.Track
  --- A note behind the roll (`context`), as paw/roll_context.tl gives it.
  type ContextNote = context.Note
  --- The event `roll_clips.changed`: the clips that the piano roll edits changed.
  changed: events.Event<Changed>
end
M.changed = events.event("roll_clips.changed")

local function roll(): Window
  return paw.ui.views:get("pianoroll") as Window
end

-- Each window of the roll edits clips of its own: the state is in the
-- roll's instance of the window (`window_state` in paw/views/pianoroll.tl),
-- and each terminal has its own windows. A new window edits the same clips.
-- The notes around them are `paw.roll_context`'s, for all windows.

--- The ids of the clips edited with the active one, in order.
local function others(): {integer}
  local view = roll()
  local list = view.edited
  if not list then
    list = {}
    view.edited = list
  end
  return list
end

--- Track id -> true or false: a toggle over `roll_context`.
local function shown(): {integer: boolean}
  local view = roll()
  local set = view.context_shown
  if not set then
    set = {}
    view.context_shown = set
  end
  return set
end

--- The clip `id` if it is a MIDI clip that is there, else nil.
local function midi(id: integer): types.Clip
  if not id then
    return nil
  end
  local ok, c = pcall(api.clip_get, id) as (boolean, types.Clip)
  return ok and c.kind == "midi" and c or nil
end

--- The id of the active clip, or nil with no clip open.
function M.active(): integer
  return roll().clip_id
end

--- The window's scope (`paw.scope`): it leaves out what it does not show.
local function scope(): ScopeModule
  return rawget(paw as {string: ScopeModule}, "scope")
end

--- True if the window's scope shows a clip: its track, and some of its time.
local function in_scope(c: types.Clip): boolean
  local s = scope()
  if not s then
    return true
  end
  local from, to = s.span()
  return s.contains(c.track) and (not from or (c.start < to - EPS and c.start + c.length > from + EPS))
end

--- The ids of the editable clips, the active one first, then the others in
--- the order they were added. In a narrowed window, only the clips that its
--- scope shows (the active one always).
function M.ids(): {integer}
  local active = M.active()
  if not midi(active) then
    return {}
  end
  local out = {active}
  for _, id in ipairs(others()) do
    local c = id ~= active and midi(id)
    if c and in_scope(c) then
      out[#out + 1] = id
    end
  end
  return out
end

--- True if a clip is one of the editable clips.
function M.editable(id: integer): boolean
  for _, other in ipairs(M.ids()) do
    if other == id then
      return true
    end
  end
  return false
end

--- Say that the clips edited changed, and draw them again.
local function changed()
  events.emit(M.changed, {active = M.active(), count = #M.ids()})
  if paw.frontend then
    paw.frontend.refresh()
  else
    api.ui_redraw()
  end
end

--- Where a clip's beats are in the roll: add this to them.
function M.offset(id: integer): number
  local a, c = midi(M.active()), midi(id)
  return (a and c) and c.start - a.start or 0
end

--- The editable clips, the active one first: `{ id, clip, offset, start,
--- length, track, name }` each, `clip` a handle (`paw.clip`) whose pitches
--- are those that the clip plays (`Clip:shifted`).
function M.portions(): {Portion}
  local a = midi(M.active())
  if not a then
    return {}
  end
  local out: {Portion} = {}
  for _, id in ipairs(M.ids()) do
    local c = midi(id)
    out[#out + 1] = {
      id = id,
      clip = paw.clip(id):shifted(c.transpose or 0),
      offset = c.start - a.start,
      start = c.start,
      length = c.length,
      track = c.track,
      name = c.name,
    }
  end
  return out
end

--- The stretch of the roll the editable clips cover: from, to. In a scope
--- with time, only its time, as the arrange view (`0` and `$` stop there).
function M.span(): number, number
  local lo, hi: number, number = 0, 0
  local portions = M.portions()
  for i, portion in ipairs(portions) do
    if i == 1 then
      lo, hi = portion.offset, portion.offset + portion.length
    end
    lo, hi = math.min(lo, portion.offset), math.max(hi, portion.offset + portion.length)
  end
  local s = scope()
  local from, to: number, number
  if s and portions[1] then
    from, to = s.span()
  end
  if from then
    local start = portions[1].start
    local a, b = math.max(lo, from - start), math.min(hi, to - start)
    if b > a then
      lo, hi = a, b
    end
  end
  return lo, hi
end

--- The editable clip a new note at `beat` goes into: the active one, unless
--- the beat is outside it and inside another. Returns the part.
function M.target(beat: number, portions?: {Portion}): Portion
  portions = portions or M.portions()
  local active = portions[1]
  if not active or (beat >= -EPS and beat < active.length - EPS) then
    return active
  end
  for _, portion in ipairs(portions) do
    if beat >= portion.offset - EPS and beat < portion.offset + portion.length - EPS then
      return portion
    end
  end
  return active
end

-- Which clips -----------------------------------------------------------------

--- Edit these clips together. `active` (or the first of them) gets the new
--- notes. paw does not use clips that are not MIDI.
function M.open(ids: {integer}, active?: integer)
  local list: {integer} = {}
  for _, id in ipairs(ids) do
    if midi(id) then
      list[#list + 1] = id
    end
  end
  active = midi(active) and active or list[1]
  if not active then
    return paw.notify("no MIDI clip to open in the piano roll", "warn")
  end
  roll():edit(paw.clip(active))
  local edited: {integer} = {}
  for _, id in ipairs(list) do
    if id ~= active then
      edited[#edited + 1] = id
    end
  end
  roll().edited = edited
  changed()
end

--- Edit the active clip alone. This is what paw does when you open a clip.
function M.only()
  if #others() == 0 then
    return
  end
  roll().edited = {}
  changed()
end

--- Make a clip the active clip. A clip that is not editable yet takes the
--- place of the old active clip in the set. The cursor stays at its
--- position in the song.
function M.activate(id: integer)
  local view = roll()
  local old, new = midi(view.clip_id), midi(id)
  if not new or id == view.clip_id then
    return
  end
  local list: {integer} = {}
  local kept = M.editable(id)
  for _, other in ipairs(M.ids()) do
    if other ~= id and (kept or other ~= view.clip_id) then
      list[#list + 1] = other
    end
  end
  view.edited = list
  view.clip_id = id
  if old then
    local by = old.start - new.start
    view.beat, view.scroll = view.beat + by, view.scroll + by
  end
  paw.notify("editing " .. new.name .. (#list > 0 and string.format(" and %d more", #list) or ""))
  changed()
end

--- Make the clip `n` places after the active one (before it, with a
--- negative `n`) active, the editable clips taken in the order they start.
function M.cycle(n: integer)
  local ids = M.ids()
  if #ids < 2 then
    return paw.notify("the piano roll edits one clip", "warn")
  end
  local starts: {integer: number} = {}
  for _, id in ipairs(ids) do
    starts[id] = api.clip_get(id).start
  end
  table.sort(
    ids,
    function(a: integer, b: integer): boolean
      if starts[a] ~= starts[b] then
        return starts[a] < starts[b]
      end
      return a < b
    end
  )
  for i, id in ipairs(ids) do
    if id == M.active() then
      return M.activate(ids[(i - 1 + n) % #ids + 1])
    end
  end
end

--- Add a clip to the editable set, or remove it. If you remove the active
--- clip, the next clip becomes active. The last clip stays. Returns whether
--- the clip is editable now, nil for a clip that is not MIDI.
function M.toggle(id: integer): boolean
  if not midi(id) then
    return nil
  end
  local ids = M.ids()
  if not M.editable(id) then
    local list = others()
    list[#list + 1] = id
    changed()
    return true
  end
  if #ids == 1 then
    paw.notify("the piano roll edits at least one clip", "warn")
    return nil
  end
  if id == M.active() then
    M.activate(ids[2])
  end
  local list: {integer} = {}
  for _, other in ipairs(others()) do
    if other ~= id then
      list[#list + 1] = other
    end
  end
  roll().edited = list
  changed()
  return false
end

-- Notes -----------------------------------------------------------------------

--- The notes of the editable clips in the roll's beats, in the order they
--- start (lower pitches first in a chord), each with `clip` (its clip's id),
--- `place` (its place among that clip's notes, for `edit_notes`) and
--- `offset`. With one clip they are that clip's notes in its own order.
--- `range` is as for `Clip:notes`, its beats the roll's.
function M.notes(range?: Range, portions?: {Portion}): {Note}
  portions = portions or M.portions()
  local out: {Note} = {}
  for _, portion in ipairs(portions) do
    local mine: objects.NoteRangeInput = range
      and {
        from = range.from and range.from - portion.offset,
        to = range.to and range.to - portion.offset,
        low = range.low,
        high = range.high,
      }
    local found, places = portion.clip:notes(mine)
    for i, found_note in ipairs(found) do
      local n = found_note as Note
      n.start, n.clip, n.place, n.offset = n.start + portion.offset, portion.id, places[i], portion.offset
      out[#out + 1] = n
    end
  end
  if #portions > 1 then
    table.sort(
      out,
      function(a: Note, b: Note): boolean
        if math.abs(a.start - b.start) > EPS then
          return a.start < b.start
        end
        if a.pitch ~= b.pitch then
          return a.pitch < b.pitch
        end
        return a.clip < b.clip
      end
    )
  end
  return out
end

--- The note of an editable clip on `pitch` that sounds at roll beat `beat`,
--- the active clip first. Returns the note (in the beats of the roll), its
--- place and its part.
function M.note_at(pitch: integer, beat: number, portions?: {Portion}): types.Note, integer, Portion
  for _, portion in ipairs(portions or M.portions()) do
    local note, place = portion.clip:note_at(pitch, beat - portion.offset)
    if note then
      if portion.offset ~= 0 then
        note.start = note.start + portion.offset
      end
      return note, place, portion
    end
  end
end

-- Context ---------------------------------------------------------------------

-- What the roll asks `paw.roll_context` for: the active clip, the edited
-- clips, their span in the song and the toggles. Nil with no clip open.
local function request(): context.Request
  local a = midi(M.active())
  if not a then
    return nil
  end
  local lo, hi = M.span()
  return context.request(a, M.ids(), a.start + lo, a.start + hi, shown())
end

--- The tracks whose notes can show behind the notes of the roll. These are
--- the tracks with MIDI clips (of the scope, in a narrowed window), but not the
--- track of the active clip. `{ id, name, color, drums, on }` each. `on`
--- tells if its notes show.
function M.tracks(): {context.Track}
  local asked = request()
  return asked and context.tracks(asked) or {}
end

--- Show the notes of a track behind the notes of the roll, or not. nil
--- returns to the value of `paw.opt.roll_context`.
function M.show_track(id: integer, on?: boolean)
  shown()[id] = on
  changed()
end

--- The context notes, in the beats of the roll. These are the notes of the
--- other clips of the active clip's track, and of the clips of the shown
--- tracks (not the editable clips), that sound in the range of the editable
--- clips. Each is `{ pitch, start, length, velocity, clip, track, color }`,
--- at most `paw.opt.roll_context_max` of them. paw finds them again only
--- when those clips, the shown tracks, the edited clips or their span change:
--- an edit of the notes of an edited clip keeps them.
function M.context(): {context.Note}
  local asked = request()
  return asked and context.notes(asked) or {}
end

--- The context note on `pitch` that sounds at roll beat `beat`, if any.
function M.context_at(pitch: integer, beat: number): context.Note
  for _, n in ipairs(M.context()) do
    if n.pitch == pitch and beat >= n.start - EPS and beat < n.start + n.length - EPS then
      return n
    end
  end
end

--- The pitches that sound at roll beat `beat`, in the editable clips and
--- the context, lowest first. The second value is the name of the chord
--- that they make, when `paw.harmony` can tell it. The name comes from
--- the chords that paw has read so far, so right after an edit it can be
--- the name from before the edit.
function M.sounding(beat: number): {integer}, string
  local set: {integer: boolean} = {}
  local out: {integer} = {}
  for _, n in ipairs(M.notes({from = beat, to = beat + EPS})) do
    set[n.pitch] = true
  end
  for _, n in ipairs(M.context()) do
    if beat >= n.start - EPS and beat < n.start + n.length - EPS then
      set[n.pitch] = true
    end
  end
  for pitch in pairs(set) do
    out[#out + 1] = pitch
  end
  table.sort(out)
  local name: string
  local harmony, a = rawget(paw as {string: HarmonyModule}, "harmony"), midi(M.active())
  if harmony and harmony.at and a then
    -- The reading as it stands: a frame after an edit does not wait for it.
    local ok, chord = pcall(harmony.at, a.start + beat, true) as (boolean, HarmonyModule.Chord)
    if ok and chord is HarmonyModule.Chord then
      name = chord.name
    end
  end
  return out, name
end

-- The active track -------------------------------------------------------------

--- The tracks whose notes the roll shows, in the order of the track list:
--- the active clip's and those shown behind it.
function M.visible(): {integer}
  local a = midi(M.active())
  if not a then
    return {}
  end
  local on: {integer: boolean} = {[a.track] = true}
  for _, t in ipairs(M.tracks()) do
    if t.on then
      on[t.id] = true
    end
  end
  local out: {integer} = {}
  for _, id in ipairs(api.track_list()) do
    if on[id] then
      out[#out + 1] = id
    end
  end
  return out
end

--- A track's MIDI clip to edit from the roll: the one under the roll's
--- cursor in the song, else the one nearest it.
local function clip_of(track: integer, at: number): types.Clip
  local best: types.Clip
  local gap: number
  for _, c in ipairs(api.clip_list(track)) do
    if c.kind == "midi" then
      local d = at < c.start and c.start - at or at >= c.start + c.length and at - (c.start + c.length) + EPS or 0
      if not gap or d < gap then
        best, gap = c, d
      end
    end
  end
  return best
end

--- Make active the track `n` places after the track of the active clip, in
--- the tracks that the roll shows (before it with a negative `n`). Its clip
--- under the cursor gets the new notes. The notes of the old clip show
--- behind. With `wrap`, it goes round. False when the roll shows no other track.
function M.step_track(n: integer, wrap?: boolean): boolean
  local view, list = roll(), M.visible()
  local a = midi(M.active())
  if not a or #list < 2 then
    return false
  end
  local at = 1
  for i, id in ipairs(list) do
    if id == a.track then
      at = i
    end
  end
  local to = at + n
  if wrap then
    to = (to - 1) % #list + 1
  end
  to = math.max(1, math.min(#list, to))
  if to == at then
    paw.notify(n > 0 and "the last track the roll shows" or "the first track the roll shows", "warn")
    return true
  end
  local c = clip_of(list[to], a.start + view.beat)
  if c then
    M.activate(c.id)
  end
  return true
end

-- Choosing --------------------------------------------------------------------

--- Each clip near the roll, as rows for a list. Each shown track is a row
--- (`kind` "track", `on` tells if its notes show). Under it are its MIDI
--- clips in the range of the roll (`kind` "clip", `on` tells if it is
--- editable, `active`). The track of the active clip is first, with its clips.
function M.rows(): {Row}
  local a = midi(M.active())
  if not a then
    return {}
  end
  local lo, hi = M.span()
  local from, to = a.start + lo, a.start + hi
  local out: {Row} = {}
  local function clips_of(track: integer)
    for _, c in ipairs(api.clip_list(track)) do
      if c.kind == "midi" and c.start < to - EPS and c.start + c.length > from + EPS then
        out[#out + 1] = {
          kind = "clip", id = c.id, name = c.name, on = M.editable(c.id), active = c.id == a.id, track = track
        }
      end
    end
  end
  local own = api.track_get(a.track)
  out[#out + 1] = {
    kind = "track", id = a.track, name = own.name, color = paw.draw.track_colour(own), on = true, active = true
  }
  clips_of(a.track)
  for _, t in ipairs(M.tracks()) do
    out[#out + 1] = {kind = "track", id = t.id, name = t.name, color = t.color, on = t.on, active = false}
    clips_of(t.id)
  end
  return out
end

--- `:roll.tracks`: a list of the tracks near the roll and of their clips.
--- On a track, Enter shows or hides its notes. On a clip, Enter adds it to
--- the editable set or removes it.
function M.pick()
  if not M.active() then
    return paw.notify("open a clip in the piano roll first", "warn")
  end
  local function line(row: Row): string
    if row.kind == "track" then
      if row.active then
        return "    " .. row.name .. "  (this clip's track)"
      end
      return (row.on and "[x] " or "[ ] ") .. row.name
    end
    return "      " .. (row.active and "(active) " or row.on and "[edit] " or "[    ] ") .. row.name
  end
  paw.pick(
    {
      title = "Piano roll: tracks and clips",
      items = M.rows(),
      format = line,
      empty = "no other tracks with MIDI clips",
      actions = {
        ["<CR>"] = {
          keep = true,
          refresh = true,
          desc = "show or hide / edit or not",
          fn = function(row: Row)
            if not row then
              return
            end
            -- The row keeps what it shows now, so the line (`refresh`)
            -- and the next Enter on it read the new state.
            if row.kind == "track" and not row.active then
              M.show_track(row.id, not row.on)
              row.on = not row.on
            elseif row.kind == "clip" and not row.active then
              row.on = M.toggle(row.id) and true or false
            end
          end,
        },
        ["<C-a>"] = {
          desc = "make the clip active",
          fn = function(row: Row)
            if row and row.kind == "clip" then
              M.activate(row.id)
            end
          end,
        },
      },
    }
  )
end

-- The set goes when the clip does, or when the project changes under it.
events.on(kernel.project_loaded, function() local view = roll(); view.edited, view.context_shown = {}, {} end)

return M
